# friction/correlations.jl -- Friction factor correlation functions
#
# Design:
#   - Standalone named functions (blasius_friction, turbulent_friction, viscosity_correction,
#     rectangular_laminar_correction): plain Julia arithmetic, NOT @register_symbolic.
#     MTK traces through these symbolically when Re is symbolic.
#   - Factory (laminar_friction_rectangular): returns closure capturing geom-derived state.
#   - No @register_symbolic on any function in this file — all are plain arithmetic.

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
        87.656 *
        ((1 + aspect_ratio * (sqrt(2) - 1)) / (4 * (1 + aspect_ratio)) - sqrt(2) / 8)^1.9
    )^(-1)
end

"""
    laminar_friction_rectangular(geom::PipeGeometry) -> (Re) -> f_darcy

Factory returning a friction correlation for fully-developed laminar flow in a
rectangular duct.

Internally derives `aspect_ratio = geom.depth / geom.width` from the
`PipeGeometry` descriptor (where `depth = min(edge1, edge2)` and
`width = max(edge1, edge2)` for rectangular geometry; both equal `D` for
circular). Precomputes the geometric correction factor
`K_R = rectangular_laminar_correction(aspect_ratio)` at construction time.

Returns `(Re) -> 64.0 / (Re * K_R)`.

Note: For circular geometry constructed via `PipeGeometry_circular(L, D)`,
`depth == width == D` so `aspect_ratio == 1.0`. `rectangular_laminar_correction(1.0)`
≈ 1.1246, giving `f ≈ 56.9/Re` (NOT the strict circular `64/Re`). Callers who
want the strict circular `64/Re` should use a raw lambda `(Re) -> 64.0 / Re`
instead of this factory.

Usage:
```julia
geom = PipeGeometry_rectangular(L, e1, e2, he)
f_fn = laminar_friction_rectangular(geom)
ChannelAndContacts(friction_correlation = f_fn, ...)
```
"""
function laminar_friction_rectangular(geom::PipeGeometry)
    aspect_ratio = geom.depth / geom.width
    k_R = rectangular_laminar_correction(aspect_ratio)
    return (Re) -> 64.0 / (Re * k_R)
end

"""
    turbulent_friction(Re, epsilon=0) -> f_darcy

Colebrook-White approximation for turbulent Darcy friction factor, as written
in RELAP and KAERI. `epsilon` is relative roughness (roughness height / Dh),
defaults to smooth pipe.

Returns 0.0 when `Re < 10`: the correlation is only valid for turbulent flow, and below
that threshold the `log10` terms diverge.

# Arguments
- `Re`: Reynolds number
- `epsilon`: relative roughness (default 0)

# Returns
Darcy friction factor (dimensionless).

Reference: `turbulent_friction(4e3) == 0.039804935964641644`,
`turbulent_friction(1e6) == 0.011649393290640643`,
`turbulent_friction(4e3, 0.1) == 0.10560870441248855`,
`turbulent_friction(5.0) == 0.0`.
"""
function turbulent_friction(Re, epsilon=0)
    # Guard: formula is only valid for turbulent Re; low Re causes DomainError in log10
    Re < 10 && return 0.0
    inlog = log10(epsilon + 21.25 / Re^0.9)
    outlog = log10(epsilon / 3.7 + (2.51 / Re) * (1.14 - 2 * inlog))
    return (-2 * outlog)^(-2)
end

"""
    viscosity_correction(heat_wet_ratio, mu_ratio) -> K_H

Viscosity correction factor for friction in heated channels. Accounts for
temperature-dependent viscosity variation between wall and bulk.

# Arguments
- `heat_wet_ratio`: heated perimeter / wet perimeter
- `mu_ratio`: viscosity at wall / viscosity at bulk

# Returns
Multiplicative correction factor K_H (dimensionless).

Reference: `viscosity_correction(1.0, 1.0) == 1.0`,
`viscosity_correction(1.0, 2.0) == 1.4948492486349383`.
"""
function viscosity_correction(heat_wet_ratio, mu_ratio)
    return 1 + heat_wet_ratio * (mu_ratio^0.58 - 1)
end
