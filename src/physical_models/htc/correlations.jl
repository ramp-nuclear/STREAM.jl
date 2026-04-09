# htc/correlations.jl — Heat transfer coefficient correlation functions for STREAM.jl
#
# Design:
#   - Standalone named functions (dittus_boelter, elenbaas_nusselt, Marco_Han_Nusselt):
#     plain Julia arithmetic, NOT @register_symbolic. MTK traces through these symbolically.
#   - Factories (constant_Nusselt, regime_dependent, elenbaas_htc): return closures
#     that capture construction-time scalars; inner function receives only symbolic Re/Pr.
#   - No @register_symbolic on any function in this file — all are plain arithmetic.

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
function constant_Nusselt(; Nu = 8.235)
    return (Re, Pr, args...) -> Nu
end

"""
    regime_dependent(; htc_laminar, htc_turbulent, friction_laminar, friction_turbulent,
                       Re_transition=2300, htc_natural=nothing, Dh=nothing, g=nothing) -> (htc=fn, friction=fn)

Factory returning a named tuple of regime-switching HTC and friction correlations.
Switches between laminar and turbulent correlations using `ifelse()` — MTK-compatible
smooth switching (established project pattern; same as flow reversal in Channel).

`Re_transition` is converted to `Float64` immediately to avoid type-promotion issues
when `Re` is a Symbolics.Num at system-build time.

When `htc_natural`, `Dh`, and `g` are all provided, the returned `htc` closure additionally
switches to the natural convection correlation when `Gr/Re^2 > 1` (Grashof-over-Reynolds-squared
criterion, matching Python STREAM convention). In this mode, the HTC closure computes:
- `Gr = beta * g * dT * Dh^3 / nu^2` from T_bulk and T_wall
- If `Gr/Re^2 > 1`: return `htc_natural(Re, Pr, T_bulk, T_wall)` (natural convection)
- Else: return forced-convection (laminar or turbulent based on Re vs Re_transition)

# Arguments
- `htc_laminar`: HTC closure `(Re, Pr, T_bulk, T_wall) -> Nu` for laminar forced convection
- `htc_turbulent`: HTC closure `(Re, Pr, T_bulk, T_wall) -> Nu` for turbulent forced convection
- `friction_laminar`: friction closure `(Re) -> f` for laminar regime
- `friction_turbulent`: friction closure `(Re) -> f` for turbulent regime
- `Re_transition`: Reynolds number transition threshold (default 2300)
- `htc_natural`: optional NC HTC closure `(Re, Pr, T_bulk, T_wall) -> Nu`; when provided
  with `Dh` and `g`, enables NC regime switching via `Gr/Re^2 > 1`
- `Dh`: hydraulic diameter [m] for Grashof computation (required when `htc_natural` is provided)
- `g`: gravitational acceleration [m/s^2] for Grashof computation (required when `htc_natural` is provided)

Returns:
```julia
(
    htc      = (Re, Pr, T_bulk, T_wall) -> ifelse(Re < Re_tr, htc_laminar(Re, Pr, T_bulk, T_wall), htc_turbulent(Re, Pr, T_bulk, T_wall)),
    friction = (Re)                     -> ifelse(Re < Re_tr, friction_laminar(Re), friction_turbulent(Re))
)
```

Usage:
```julia
rd = regime_dependent(
    htc_laminar        = constant_Nusselt(Nu=8.235),
    htc_turbulent      = dittus_boelter,
    friction_laminar   = laminar_friction(geom.depth / geom.width),
    friction_turbulent = blasius_friction,
    Re_transition      = 2300.0
)
ChannelAndContacts(htc_correlation = rd.htc, friction_correlation = rd.friction, ...)

# With NC detection:
rd_nc = regime_dependent(
    htc_laminar        = constant_Nusselt(Nu=8.235),
    htc_turbulent      = dittus_boelter,
    friction_laminar   = laminar_friction(geom.depth / geom.width),
    friction_turbulent = blasius_friction,
    htc_natural        = elenbaas_htc(b=D_ch, L=L_ch, Dh=D_ch, g=g_acc),
    Dh                 = D_ch,
    g                  = g_acc,
)
```
"""
function regime_dependent(;
    htc_laminar,
    htc_turbulent,
    friction_laminar,
    friction_turbulent,
    Re_transition = 2300,
    htc_natural   = nothing,
    Dh            = nothing,
    g             = nothing)

    # Convert to Float64 immediately — avoids type-promotion issues with symbolic Re
    Re_tr = Float64(Re_transition)

    # D-04: htc_natural requires both Dh and g
    if !isnothing(htc_natural) && (isnothing(Dh) || isnothing(g))
        throw(ArgumentError("regime_dependent: htc_natural provided but Dh or g is missing — all three (htc_natural, Dh, g) must be supplied together."))
    end

    # D-03: Dh or g without htc_natural is a likely miscall — warn
    if isnothing(htc_natural) && (!isnothing(Dh) || !isnothing(g))
        @warn "regime_dependent: Dh and g supplied but htc_natural not provided — NC regime will not be detected."
    end

    if !isnothing(htc_natural)
        # NC-enabled path: switch on Gr/Re^2 > 1
        Dh_val = Float64(Dh)
        g_val  = Float64(g)
        htc_forced_fn = (Re, Pr, T_bulk, T_wall) -> ifelse(Re < Re_tr, htc_laminar(Re, Pr, T_bulk, T_wall), htc_turbulent(Re, Pr, T_bulk, T_wall))
        htc_fn = (Re, Pr, T_bulk, T_wall) -> begin
            beta_v = beta_water(T_bulk)
            nu_v   = mu_water(T_bulk) / rho_water(T_bulk)
            Gr_val = Gr(beta_v, g_val, T_wall - T_bulk, Dh_val, nu_v)
            ifelse(Gr_val / Re^2 > 1, htc_natural(Re, Pr, T_bulk, T_wall), htc_forced_fn(Re, Pr, T_bulk, T_wall))
        end
    else
        # Existing forced-convection-only path (backward compatible)
        htc_fn = (Re, Pr, T_bulk, T_wall) -> ifelse(Re < Re_tr, htc_laminar(Re, Pr, T_bulk, T_wall), htc_turbulent(Re, Pr, T_bulk, T_wall))
    end

    friction_fn = (Re) -> ifelse(Re < Re_tr, friction_laminar(Re), friction_turbulent(Re))

    return (htc = htc_fn, friction = friction_fn)
end

"""
    elenbaas_nusselt(Ra, b, L) -> Nu

Elenbaas natural convection correlation for parallel vertical plates.
Formula: Nu = (1/24) * Ra * (b/L) * (1 - exp(-35 * L / (Ra * b)))^0.75

Source: Elenbaas (1942), as implemented in Python STREAM `_Elenbaas`.

# Arguments
- `Ra`: Rayleigh number (based on gap width b)
- `b`: gap between plates [m] (channel depth)
- `L`: heated length [m]

# Returns
Nusselt number (dimensionless).
"""
elenbaas_nusselt(Ra, b, L) = (1/24) * Ra * (b / L) * (1 - exp(-35 * L / (Ra * b)))^0.75

"""
    elenbaas_htc(; b, L, Dh, g=9.81) -> (Re, Pr, T_bulk, T_wall) -> Nu

Factory returning an HTC correlation for Elenbaas natural convection.
Captures geometry and gravity at construction time. The returned closure
computes beta, nu, Gr, and Ra from T_bulk and T_wall at each evaluation.

Compatible with the 4-arg HTC interface `(Re, Pr, T_bulk, T_wall) -> Nu`.
When T_wall = T_bulk (dT=0), returns Nu=0 (physically correct: no buoyancy
driving force).

Note: Re and Pr arguments are accepted for interface compatibility but
are NOT used in the Elenbaas correlation (natural convection does not
depend on forced-flow Reynolds number).

# Arguments
- `b`: gap between plates [m] (channel depth)
- `L`: heated length [m]
- `Dh`: hydraulic diameter [m] (used as characteristic length in Gr)
- `g`: gravitational acceleration [m/s^2] (default 9.81)

# Returns
Closure `(Re, Pr, T_bulk, T_wall) -> Nu`.
"""
function elenbaas_htc(; b, L, Dh, g = 9.81)
    return (Re, Pr, T_bulk, T_wall) -> begin
        beta   = beta_water(T_bulk)
        nu     = mu_water(T_bulk) / rho_water(T_bulk)
        Gr_val = Gr(beta, g, T_wall - T_bulk, Dh, nu)
        Ra_val = Ra(Gr_val, Pr)
        elenbaas_nusselt(Ra_val, b, L)
    end
end

# _bergles_rohsenow_dT_ONB: Bergles-Rohsenow onset of nucleate boiling
# temperature difference. Private helper for T_ONB[i] observables.
# Phase 29 will elevate this to public Bergles_Rohsenow_T_ONB export.
#
# Source: Python STREAM temperatures.py lines 103-105
# Formula: dT = 0.556 * (q_spl / (1082 * p^1.156))^(0.463 * p^0.0234)
# where p = P_Pa / 1e5 (pressure in bar)
function _bergles_rohsenow_dT_ONB(P_Pa, q_spl)
    p = P_Pa / 1e5
    return 0.556 * (q_spl / (1082 * p^1.156))^(0.463 * p^0.0234)
end

# Kakac Table 44 case 3 — 2-sided heating in rectangular duct.
# Private helper used by HTC-02 and HTC-03 factories.
# NOT the same as Marco_Han_Nusselt (which is 4-sided uniform heat flux).
function _two_sided_heating_nusselt(aspect_ratio, nu0=8.235)
    return nu0 * (
        1.0
        - 1.4122 * aspect_ratio
        + 2.3473 * aspect_ratio^2
        - 2.8983 * aspect_ratio^3
        + 2.0629 * aspect_ratio^4
        - 0.6077 * aspect_ratio^5
    )
end

# Shah & London equations 317-319 for parallel plates, thermally developing flow.
# Uses ifelse() (not if/else) so that MTK can trace through this function when x is
# a symbolic Num expression. See CLAUDE.md MTK Patterns.
function _nusselt_coefficient_developing(x)
    nu_low  = 1.49 * x^(-1/3)
    nu_mid  = 1.49 * x^(-1/3) - 0.4
    nu_high = 8.235 + 8.68 * exp(-164 * x) * (1e3 * x)^(-0.506)
    return ifelse(x <= 2e-4, nu_low, ifelse(x <= 1e-3, nu_mid, nu_high))
end

"""
    fully_developed_laminar_h_spl(; Dh, aspect_ratio) -> (Re, Pr, T_bulk, T_wall) -> Nu

Factory returning an HTC correlation for fully-developed laminar flow in a
rectangular duct with 2-sided heating.

# Arguments
- `Dh`: hydraulic diameter [m] (accepted for interface consistency, not used in Nu calculation)
- `aspect_ratio`: channel depth / channel width (0 to 1)

# Returns
Closure `(Re, Pr, T_bulk, T_wall) -> Nu`.
"""
function fully_developed_laminar_h_spl(; Dh, aspect_ratio)
    nu = _two_sided_heating_nusselt(aspect_ratio)
    return (Re, Pr, args...) -> nu
end

"""
    developing_laminar_h_spl(; Dh, develop_length, aspect_ratio) -> (Re, Pr, T_bulk, T_wall) -> Nu

Factory returning an HTC correlation for thermally developing laminar flow in a
rectangular duct with 2-sided heating.

# Arguments
- `Dh`: hydraulic diameter [m]
- `develop_length`: distance from channel entrance [m]
- `aspect_ratio`: channel depth / channel width (0 to 1)

# Returns
Closure `(Re, Pr, T_bulk, T_wall) -> Nu`.
"""
function developing_laminar_h_spl(; Dh, develop_length, aspect_ratio)
    correction = 6 - 5 * exp(-0.75 * aspect_ratio / 0.3257)
    return (Re, Pr, args...) -> begin
        x_star = develop_length / Dh / Re / Pr / correction
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
        reduce(max, (c(Re, Pr, T_bulk, T_wall) for c in correlations))
    end
end

"""
    Marco_Han_Nusselt(aspect_ratio) -> Nu

Marco and Han approximation for Nusselt number in fully-developed laminar flow
through rectangular ducts with uniform wall temperature (4-sided heating).

# Arguments
- `aspect_ratio`: channel depth / channel width (0 to 1)

# Returns
Nusselt number (dimensionless).
"""
function Marco_Han_Nusselt(aspect_ratio)
    return 8.235 * (
        1.0
        - 2.0421 * aspect_ratio
        + 3.853 * aspect_ratio^2
        - 2.4765 * aspect_ratio^3
        + 1.0578 * aspect_ratio^4
        - 0.1861 * aspect_ratio^5
    )
end
