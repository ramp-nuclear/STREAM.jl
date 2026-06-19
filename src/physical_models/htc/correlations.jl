# htc/correlations.jl -- Heat transfer coefficient correlation functions
#
# Design:
#   - Standalone named functions (dittus_boelter, elenbaas_nusselt, marco_han_nusselt):
#     plain Julia arithmetic, NOT @register_symbolic. MTK traces through these symbolically.
#   - Factories (constant_Nusselt, regime_dependent(geom; ...), elenbaas_htc(geom; g),
#     fully_developed_laminar_h_spl(geom), developing_laminar_h_spl(geom; develop_length)):
#     take `geom::PipeGeometry` as first positional argument when they consume geometry
#     fields; return closures that capture construction-time scalars
#     derived from `geom.depth`, `geom.width`, `geom.L`, `geom.Dh`. Inner function
#     receives only symbolic Re/Pr.
#   - No @register_symbolic on any function in this file — all are plain arithmetic.
#
# Eval-point convention: callers pass `Re` and `Pr` evaluated at the film temperature
# `T_film = (T_bulk + T_wall)/2`. The Channel core (src/components/channels.jl) does this.

"""
    dittus_boelter(Re, Pr, args...) -> Nu

Dittus-Boelter heat transfer correlation for turbulent forced convection.
Returns Nusselt number Nu = 0.023 * Re^0.8 * Pr^0.4.

The `args...` accepts and ignores extra arguments for backward compatibility with
the 4-arg HTC interface `(Re, Pr, T_bulk, T_wall) -> Nu`.

Valid for: Re > 10,000, 0.6 <= Pr <= 160, L/D > 10.
MTK-compatible: plain arithmetic on symbolic Re/Pr traces correctly.
"""
dittus_boelter(Re, Pr, args...) = 0.023 * Re^0.8 * Pr^0.4

"""
    constant_Nusselt(; Nu=8.235) -> (Re, Pr) -> Nu

Factory returning an HTC correlation that yields a fixed Nusselt number `Nu`.

Default `Nu = 8.235` is the Shah & London fully-developed value for uniform-heat-flux
parallel plates (FIXED_FLUXES). The returned closure is MTK-compatible: `Nu[i] ~ 8.235`
is a valid algebraic equation in a ModelingToolkit system.

Usage:
```julia
htc_fn = constant_Nusselt()          # Nu = 8.235
htc_fn = constant_Nusselt(Nu = 5.0)  # custom Nu
ChannelAndContacts(htc_correlation = htc_fn, ...)
```
"""
function constant_Nusselt(; Nu=8.235)
    return (Re, Pr, args...) -> Nu
end

"""
    regime_dependent(geom::PipeGeometry; htc_laminar, htc_turbulent, friction_laminar, friction_turbulent,
                       htc_natural=nothing, g=nothing, Re_transition=2300) -> (htc=fn, friction=fn)

Factory returning a named tuple of regime-switching HTC and friction correlations.
Switches between laminar and turbulent correlations using `ifelse()` — MTK-compatible
smooth switching (established project pattern; same as flow reversal in Channel).

`Re_transition` is converted to `Float64` immediately to avoid type-promotion issues
when `Re` is a Symbolics.Num at system-build time.

When `htc_natural` and `g` are both provided, the returned `htc` closure additionally
switches to the natural convection correlation when `Gr/Re^2 > 1` (Grashof-over-Reynolds-squared
criterion, matching Python STREAM convention). The Grashof characteristic length is taken
from `geom.Dh`. In this mode, the HTC closure computes:
- `Gr = beta * g * dT * geom.Dh^3 / nu^2` from T_bulk and T_wall
- If `Gr/Re^2 > 1`: return `htc_natural(Re, Pr, T_bulk, T_wall)` (natural convection)
- Else: return forced-convection (laminar or turbulent based on Re vs Re_transition)

# Arguments
- `geom`: `PipeGeometry` describing the channel geometry; `geom.Dh` is read for the Grashof
  characteristic length when `htc_natural` is supplied.
- `htc_laminar`: HTC closure `(Re, Pr, T_bulk, T_wall) -> Nu` for laminar forced convection.
- `htc_turbulent`: HTC closure `(Re, Pr, T_bulk, T_wall) -> Nu` for turbulent forced convection.
- `friction_laminar`: friction closure `(Re) -> f` for laminar regime.
- `friction_turbulent`: friction closure `(Re) -> f` for turbulent regime.
- `htc_natural`: optional NC HTC closure `(Re, Pr, T_bulk, T_wall) -> Nu`; when provided
  together with `g`, enables NC regime switching via `Gr/Re^2 > 1`.
- `g`: gravitational acceleration [m/s^2] for Grashof computation (required when `htc_natural`
  is provided; otherwise unused).
- `Re_transition`: Reynolds number transition threshold (default 2300).

If `htc_natural` is provided, `g` must be too, otherwise an `ArgumentError` is raised.
`Dh` is not a user-facing kwarg (it is read from `geom.Dh`); a lone `g` without
`htc_natural` is simply ignored.

Returns:
```julia
(
    htc      = (Re, Pr, T_bulk, T_wall) -> ifelse(Re < Re_tr, htc_laminar(Re, Pr, T_bulk, T_wall), htc_turbulent(Re, Pr, T_bulk, T_wall)),
    friction = (Re)                     -> ifelse(Re < Re_tr, friction_laminar(Re), friction_turbulent(Re))
)
```

Usage:
```julia
geom = PipeGeometry_rectangular(L, e1, e2, he)
rd = regime_dependent(geom;
    htc_laminar        = constant_Nusselt(Nu=8.235),
    htc_turbulent      = dittus_boelter,
    friction_laminar   = laminar_friction_rectangular(geom),
    friction_turbulent = blasius_friction,
)
ChannelAndContacts(htc_correlation = rd.htc, friction_correlation = rd.friction, ...)

# With NC detection:
rd_nc = regime_dependent(geom;
    htc_laminar        = constant_Nusselt(Nu=8.235),
    htc_turbulent      = dittus_boelter,
    friction_laminar   = laminar_friction_rectangular(geom),
    friction_turbulent = blasius_friction,
    htc_natural        = elenbaas_htc(geom; g=9.81),
    g                  = 9.81,
)
```
"""
function regime_dependent(geom::PipeGeometry;
    htc_laminar::HTCCorrelation,
    htc_turbulent::HTCCorrelation,
    friction_laminar::Function,
    friction_turbulent::Function,
    htc_natural::Union{HTCCorrelation,Nothing}=nothing,
    g=nothing,
    Re_transition=2300,
)
    Re_tr = Float64(Re_transition)

    # htc_natural and g must be supplied together.
    if !isnothing(htc_natural) && isnothing(g)
        throw(
            ArgumentError(
                "regime_dependent: htc_natural provided but g is missing — both (htc_natural, g) must be supplied together.",
            ),
        )
    end

    if !isnothing(htc_natural)
        # NC-enabled path: switch on Gr/Re^2 > 1
        Dh_val = geom.Dh
        g_val = Float64(g)
        htc_forced_fn =
            (Re, Pr, T_bulk, T_wall) -> ifelse(
                Re < Re_tr,
                htc_laminar(Re, Pr, T_bulk, T_wall),
                htc_turbulent(Re, Pr, T_bulk, T_wall),
            )
        htc_fn =
            (Re, Pr, T_bulk, T_wall) -> begin
                Gr_val = Gr(
                    rho_water(T_bulk),
                    mu_water(T_bulk),
                    beta_water(T_bulk),
                    T_wall,
                    T_bulk,
                    Dh_val,
                    g_val,
                )
                ifelse(
                    Gr_val / Re^2 > 1,
                    htc_natural(Re, Pr, T_bulk, T_wall),
                    htc_forced_fn(Re, Pr, T_bulk, T_wall),
                )
            end
    else
        htc_fn =
            (Re, Pr, T_bulk, T_wall) -> ifelse(
                Re < Re_tr,
                htc_laminar(Re, Pr, T_bulk, T_wall),
                htc_turbulent(Re, Pr, T_bulk, T_wall),
            )
    end

    friction_fn = (Re) -> ifelse(Re < Re_tr, friction_laminar(Re), friction_turbulent(Re))

    return (htc=htc_fn, friction=friction_fn)
end

"""
    elenbaas_nusselt(Ra, b, L) -> Nu

Elenbaas natural convection correlation for parallel vertical plates.
Formula: Nu = (1/24) * Ra * (b/L) * (1 - exp(-35 * L / (Ra * b)))^0.75

Natural convection has no driving force for non-positive Rayleigh (wall not
hotter than bulk), so Nu = 0 for Ra <= 0. The shape term's base is clamped so
the fractional power never sees a negative argument, even when the expression is
eagerly constant-folded.

Source: Elenbaas (1942), as implemented in Python STREAM `_Elenbaas`.

# Arguments
- `Ra`: Rayleigh number (based on gap width b)
- `b`: gap between plates [m] (channel depth)
- `L`: heated length [m]

# Returns
Nusselt number (dimensionless). Zero for Ra <= 0.
"""
function elenbaas_nusselt(Ra, b, L)
    Ra_pos = ifelse(Ra > 0, Ra, one(Ra))    # clamp so the shape term never sees Ra<=0
    shape = (1 - exp(-35 * L / (Ra_pos * b)))^0.75
    return ifelse(Ra > 0, (1 / 24) * Ra * (b / L) * shape, zero(Ra))
end

"""
    elenbaas_htc(geom::PipeGeometry; g=9.81) -> (Re, Pr, T_bulk, T_wall) -> Nu

Factory returning an HTC correlation for Elenbaas natural convection.
Captures geometry (via `geom`) and gravity at construction time. The returned
closure computes beta, nu, Gr, and Ra from T_bulk and T_wall at each evaluation.

Compatible with the 4-arg HTC interface `(Re, Pr, T_bulk, T_wall) -> Nu`.
When T_wall = T_bulk (dT=0), returns Nu=0 (physically correct: no buoyancy
driving force).

This correlation is for **parallel-vertical-plates natural convection** and expects a
rectangular `PipeGeometry` where `geom.depth` is the plate gap. There is no runtime
check: a circular or non-plate geometry yields an aspect-ratio-blind Nu that may not
be physical. Validating the geometry is left to the caller.

Note: Re and Pr arguments are accepted for interface compatibility but
are NOT used in the Elenbaas correlation (natural convection does not
depend on forced-flow Reynolds number).

# Arguments
- `geom`: `PipeGeometry`; the factory reads `geom.depth` (gap between plates `b`),
  `geom.L` (heated length), and `geom.Dh` (hydraulic diameter, used as
  characteristic length in Gr).
- `g`: gravitational acceleration [m/s^2] (default 9.81).

# Returns
Closure `(Re, Pr, T_bulk, T_wall) -> Nu`.
NC exception: this closure evaluates `beta_water`, `mu_water`, `rho_water` INTERNALLY at `T_bulk` (NOT at film) — natural-convection driving force is a bulk-vs-wall ΔT phenomenon and Python STREAM evaluates β, ν at bulk for Gr.
"""
function elenbaas_htc(geom::PipeGeometry; g=9.81)
    b = geom.depth
    L_h = geom.L
    Dh_v = geom.Dh
    return (Re, Pr, T_bulk, T_wall) -> begin
        Gr_val = Gr(
            rho_water(T_bulk),
            mu_water(T_bulk),
            beta_water(T_bulk),
            T_wall,
            T_bulk,
            Dh_v,
            g,
        )
        Ra_val = Ra(Gr_val, Pr)
        elenbaas_nusselt(Ra_val, b, L_h)
    end
end

function _bergles_rohsenow_dT_ONB(P_Pa, q_spl)
    p = P_Pa / 1e5
    return 0.556 * (q_spl / (1082 * p^1.156))^(0.463 * p^0.0234)
end

function _two_sided_heating_nusselt(aspect_ratio, nu0=8.235)
    return nu0 * (
        1.0 - 1.4122 * aspect_ratio + 2.3473 * aspect_ratio^2 - 2.8983 * aspect_ratio^3 +
        2.0629 * aspect_ratio^4 - 0.6077 * aspect_ratio^5
    )
end

function _nusselt_coefficient_developing(x)
    nu_low = 1.49 * x^(-1 / 3)
    nu_mid = 1.49 * x^(-1 / 3) - 0.4
    nu_high = 8.235 + 8.68 * exp(-164 * x) * (1e3 * x)^(-0.506)
    return ifelse(x <= 2e-4, nu_low, ifelse(x <= 1e-3, nu_mid, nu_high))
end

"""
    fully_developed_laminar_h_spl(geom::PipeGeometry) -> (Re, Pr, T_bulk, T_wall) -> Nu

Factory returning an HTC correlation for fully-developed laminar flow in a
rectangular duct with 2-sided heating.

# Arguments
- `geom`: `PipeGeometry`; the factory reads `geom.depth` and `geom.width` to
  derive `aspect_ratio = depth / width`. `geom.Dh` is not used by the Nu calculation.

# Returns
Closure `(Re, Pr, T_bulk, T_wall) -> Nu`.
"""
function fully_developed_laminar_h_spl(geom::PipeGeometry)
    aspect_ratio = geom.depth / geom.width
    nu = _two_sided_heating_nusselt(aspect_ratio)
    return (Re, Pr, args...) -> nu
end

"""
    developing_laminar_h_spl(geom::PipeGeometry; develop_length) -> (Re, Pr, T_bulk, T_wall) -> Nu

Factory returning an HTC correlation for thermally developing laminar flow in a
rectangular duct with 2-sided heating.

`develop_length` is a **mandatory** kwarg with no default. The caller must explicitly
choose the evaluation point along the channel; there is no silent substitution with
`geom.L`.

# Arguments
- `geom`: `PipeGeometry`; the factory reads `geom.Dh`, `geom.depth`, and `geom.width`,
  deriving `aspect_ratio = depth / width`.
- `develop_length`: distance from channel entrance [m] (mandatory, no default).

# Returns
Closure `(Re, Pr, T_bulk, T_wall) -> Nu`.
"""
function developing_laminar_h_spl(geom::PipeGeometry; develop_length)
    aspect_ratio = geom.depth / geom.width
    Dh_v = geom.Dh
    correction = 6 - 5 * exp(-0.75 * aspect_ratio / 0.3257)
    return (Re, Pr, args...) -> begin
        x_star = develop_length / Dh_v / Re / Pr / correction
        nudev = _nusselt_coefficient_developing(x_star)
        _two_sided_heating_nusselt(aspect_ratio, nudev)
    end
end

"""
    maximal_htc(correlations...) -> (Re, Pr, T_bulk, T_wall) -> Nu

Combinator returning an HTC correlation that evaluates all provided correlations
and returns the maximum Nusselt number.

# Arguments
- `correlations...`: one or more HTC closures `(Re, Pr, T_bulk, T_wall) -> Nu`

# Returns
Closure `(Re, Pr, T_bulk, T_wall) -> max(c1(...), c2(...), ...)`.
"""
function maximal_htc(correlations...)
    return (Re, Pr, T_bulk, T_wall) -> begin
        maximum(c(Re, Pr, T_bulk, T_wall) for c in correlations)
    end
end

"""
    marco_han_nusselt(aspect_ratio) -> Nu

Marco and Han approximation for Nusselt number in fully-developed laminar flow
through rectangular ducts with uniform wall temperature (4-sided heating).

# Arguments
- `aspect_ratio`: channel depth / channel width (0 to 1)

# Returns
Nusselt number (dimensionless).
"""
function marco_han_nusselt(aspect_ratio)
    return 8.235 * (
        1.0 - 2.0421 * aspect_ratio + 3.853 * aspect_ratio^2 - 2.4765 * aspect_ratio^3 +
        1.0578 * aspect_ratio^4 - 0.1861 * aspect_ratio^5
    )
end
