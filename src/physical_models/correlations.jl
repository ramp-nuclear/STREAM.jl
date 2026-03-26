# correlations.jl — Pluggable HTC and friction correlation functions for STREAM.jl
#
# Design:
#   - Standalone named functions (dittus_boelter, blasius_friction): plain Julia arithmetic,
#     NOT @register_symbolic. MTK traces through these symbolically when Re/Pr are symbolic.
#   - Factories (constant_Nusselt, laminar_friction, regime_dependent): return closures
#     that capture construction-time scalars; inner function receives only symbolic Re/Pr.
#   - rectangular_laminar_correction: scalar utility function, always returns Float64.
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
    blasius_friction(Re) -> f_darcy

Blasius friction factor correlation for turbulent smooth-pipe flow.
Returns Darcy friction factor f = 0.3164 * Re^(-0.25).

Valid for: 4,000 < Re < 100,000.
MTK-compatible: plain arithmetic on symbolic Re traces correctly.
"""
blasius_friction(Re) = 0.3164 * Re^(-0.25)

"""
    rectangular_laminar_correction(aspect_ratio) -> K_R

Scalar geometric correction factor K_R from the KAERI formula for fully-developed
laminar flow in a rectangular duct.

`aspect_ratio = depth / width`, must be in [0, 1]:
- 0.0 (thin gap limit): K_R ≈ 0.66685
- 0.01814 (MTR geometry: 0.00127/0.07): K_R ≈ 0.68544
- 0.5: K_R ≈ 1.03639
- 1.0 (square): K_R ≈ 1.12462

Use: `f_darcy = 64 / (Re * K_R)` for rectangular laminar flow.

Source: KAERI formula as used in TERMIC thermal-hydraulics code;
matches Python STREAM friction.py `rectangular_laminar_correction`.
"""
function rectangular_laminar_correction(aspect_ratio::Real)
    return (
        0.88919 +
        87.656 * ((1 + aspect_ratio * (sqrt(2) - 1)) / (4 * (1 + aspect_ratio)) - sqrt(2) / 8)^1.9
    )^(-1)
end

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
    laminar_friction(aspect_ratio::Real) -> (Re) -> f_darcy

Factory returning a friction correlation for fully-developed laminar flow in a
rectangular duct.

`aspect_ratio` = `depth / width` where depth = min(edge1, edge2)
and width = max(edge1, edge2). Precomputes the geometric correction factor
`K_R = rectangular_laminar_correction(aspect_ratio)` at construction time.

Returns `(Re) -> 64.0 / (Re * K_R)`.

For truly circular geometry (no correction), use a raw lambda `(Re) -> 64.0 / Re`.
For square (aspect_ratio=1.0): K_R ≈ 1.1246, giving f ≈ 56.9/Re (NOT 64/Re).

Usage:
```julia
geom = PipeGeometry_rectangular(L, e1, e2, he)
f_fn = laminar_friction(geom.depth / geom.width)
ChannelAndContacts(friction_correlation = f_fn, ...)
```
"""
function laminar_friction(aspect_ratio::Real)
    k_R = rectangular_laminar_correction(aspect_ratio)
    return (Re) -> 64.0 / (Re * k_R)
end

"""
    regime_dependent(; htc_laminar, htc_turbulent, friction_laminar, friction_turbulent,
                       Re_transition=2300) -> (htc=fn, friction=fn)

Factory returning a named tuple of regime-switching HTC and friction correlations.
Switches between laminar and turbulent correlations using `ifelse()` — MTK-compatible
smooth switching (established project pattern; same as flow reversal in Channel).

`Re_transition` is converted to `Float64` immediately to avoid type-promotion issues
when `Re` is a Symbolics.Num at system-build time.

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
```
"""
function regime_dependent(;
    htc_laminar,
    htc_turbulent,
    friction_laminar,
    friction_turbulent,
    Re_transition = 2300)

    # Convert to Float64 immediately — avoids type-promotion issues with symbolic Re
    Re_tr = Float64(Re_transition)

    htc_fn      = (Re, Pr, T_bulk, T_wall) -> ifelse(Re < Re_tr, htc_laminar(Re, Pr, T_bulk, T_wall), htc_turbulent(Re, Pr, T_bulk, T_wall))
    friction_fn = (Re)                     -> ifelse(Re < Re_tr, friction_laminar(Re), friction_turbulent(Re))

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
