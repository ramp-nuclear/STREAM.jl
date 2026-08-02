# friction.jl -- Darcy friction factor correlations
#
# Design:
#   - Standalone named functions (blasius, turbulent, viscosity_correction,
#     rectangular_correction): plain Julia arithmetic, NOT @register_symbolic.
#     MTK traces through these symbolically when Re is symbolic.
#   - Factory (rectangular_laminar): returns closure capturing geom-derived state.
#   - No @register_symbolic on any function in this file — all are plain arithmetic.

"""
    blasius(Re) -> f_darcy

Blasius friction factor correlation for turbulent smooth-pipe flow.
Returns Darcy friction factor f = 0.3164 * Re^(-0.25).

Valid for: 4,000 < Re < 100,000.
MTK-compatible: plain arithmetic on symbolic Re traces correctly.
"""
blasius(Re) = 0.3164 * Re^(-0.25)

"""
    laminar(Re) -> f_darcy

Hagen-Poiseuille analytic Darcy friction factor for fully-developed laminar flow in a
circular duct, `f = 64 / Re`. Mirrors Python STREAM `friction.py::laminar_friction`
(the `k_R = 1.0` case of the regime-dependent model), which is the same pure `64 / re`.

This is the bare factor, so it goes to `Inf` as `Re -> 0`. That is the correct factor:
the physical quantity is the pressure drop `f * ṁ*|ṁ| / (...)`, and with
`ṁ*|ṁ| ~ Re^2` the product `~ (64/Re) * Re^2 ~ Re` vanishes smoothly as the flow
stops (the Hagen-Poiseuille drop is linear in velocity). The no-flow case is handled by
the caller that forms that product. For flow that reverses through `Re = 0`, use
[`RegimeDependent`](@ref); it guards the no-flow point.

# Arguments
- `Re`: Reynolds number

# Returns
Darcy friction factor (dimensionless).
"""
laminar(Re) = 64.0 / Re

"""
    rectangular_correction(aspect_ratio) -> K_R

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
Reference: KAERI, "Development of Research Reactor Technology", Korea Atomic Energy
Research Institute, KAERI/RR-3818/2014, 2014.
"""
function rectangular_correction(aspect_ratio::Real)
    return (
        0.88919 +
        87.656 *
        ((1 + aspect_ratio * (sqrt(2) - 1)) / (4 * (1 + aspect_ratio)) - sqrt(2) / 8)^1.9
    )^(-1)
end

"""
    rectangular_laminar(geom::PipeGeometry) -> (Re) -> f_darcy

Factory returning a friction correlation for fully-developed laminar flow in a
rectangular duct.

Internally derives `aspect_ratio = geom.depth / geom.width` from the
`PipeGeometry` descriptor (where `depth = min(edge1, edge2)` and
`width = max(edge1, edge2)` for rectangular geometry; both equal `D` for
circular). Precomputes the geometric correction factor
`K_R = rectangular_correction(aspect_ratio)` at construction time.

Returns a closure `(Re) -> 64.0 / (Re * K_R)`.

This is the rectangular companion to [`laminar`]: the circular factor is `64/Re`,
this one is `64/(Re*K_R)`. Both are bare `64/Re`-style factors with no no-flow guard, which
is correct for a forced-flow channel where `Re > 0` always. The plain `64/(Re*K_R)` form
keeps the residual and Jacobian for a forced-flow steady solve identical to the pre-reversal
form, which a borderline forced-flow solve (two plates in hydraulic series) relies on to
converge. A loop whose flow reverses through `Re = 0` should use [`RegimeDependent`](@ref)
instead, which guards the no-flow point in its returned closure.

Note: For circular geometry constructed via `PipeGeometry_circular(L, D)`,
`depth == width == D` so `aspect_ratio == 1.0`. `rectangular_correction(1.0)`
≈ 1.1246, giving `f ≈ 56.9/Re` (NOT the strict circular `64/Re`). Callers who
want the strict circular `64/Re` should use a raw lambda `(Re) -> 64.0 / Re`
instead of this factory.

Usage:
```julia
geom = PipeGeometry_rectangular(L, e1, e2, he)
f_fn = rectangular_laminar(geom)
ChannelAndContacts(darcy = FromReynolds(f_fn), ...)
```
"""
function rectangular_laminar(geom::PipeGeometry)
    aspect_ratio = geom.depth / geom.width
    k_R = rectangular_correction(aspect_ratio)
    return (Re) -> 64.0 / (Re * k_R)
end

"""
    turbulent(Re, epsilon=0) -> f_darcy

Colebrook-White approximation for turbulent Darcy friction factor, as written in RELAP and
in KAERI/RR-3818/2014 page 3 chapter 2.1.2 (full reference below). `epsilon` is relative
roughness (roughness height / Dh), defaults to smooth pipe.

Returns 0.0 when `Re < 10`: the correlation is only valid for turbulent flow, and below
that threshold the `log10` terms diverge. Python guards the same way with
`np.nan_to_num` (its docstring quotes "approx <7"); the `Re < 10` floor here is a touch
more conservative and matches the published `turbulent(5.0) == 0.0` reference.

`Base.ifelse`, not a Julia `if`/`&&`: MTK traces this function symbolically to build the
equations and Jacobian, so `Re` is a symbolic value at trace time and a normal `if` errors
on it. `Base.ifelse` records the branch into the expression for the solver to evaluate each
step. `max(Re, 10)` keeps `log10` finite on the branch that is not taken, since tracing
walks both.

# Arguments
- `Re`: Reynolds number
- `epsilon`: relative roughness (default 0)

# Returns
Darcy friction factor (dimensionless).

Known values: `turbulent(4e3) == 0.039804935964641644`,
`turbulent(1e6) == 0.011649393290640643`,
`turbulent(4e3, 0.1) == 0.10560870441248855`,
`turbulent(5.0) == 0.0`.

Reference: KAERI, "Development of Research Reactor Technology", Korea Atomic Energy
Research Institute, KAERI/RR-3818/2014, 2014.
"""
function turbulent(Re, epsilon=0)
    # Clamp the Re feeding the log10 terms so they are evaluated at a turbulent Re even
    # while tracing the not-taken branch; the ifelse zeroes the result below Re 10.
    Re_safe = max(Re, 10)
    inlog = log10(epsilon + 21.25 / Re_safe^0.9)
    outlog = log10(epsilon / 3.7 + (2.51 / Re_safe) * (1.14 - 2 * inlog))
    f = (-2 * outlog)^(-2)
    return Base.ifelse(Re < 10, zero(f), f)
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

"""
    darcy_weisbach_dp(ṁ, rho, f, L, Dh, A) -> Pa
    darcy_weisbach_dp(ṁ, rho, f, geom::PipeGeometry) -> Pa

Distributed friction pressure drop over a length of duct:

    dP = f * ṁ|ṁ| / (2*rho*A^2) * (L/Dh)

`ṁ|ṁ|` rather than `ṁ^2` so the drop reverses sign with the flow. Positive `ṁ`
gives a positive drop.

The `PipeGeometry` form takes `L`, `Dh` and `A` from the geometry. Pass `L` explicitly for a
single cell of a discretised channel, where the length is `geom.L / n` rather than `geom.L`.

# Arguments
- `ṁ`: mass flow rate [kg/s]
- `rho`: density [kg/m^3]
- `f`: Darcy friction factor, e.g. from a [`AbstractDarcyFactor`](@ref)
- `L`: length over which the friction acts [m]
- `Dh`: hydraulic diameter [m]
- `A`: flow area [m^2]

# Returns
Pressure drop [Pa].
"""
darcy_weisbach_dp(ṁ, rho, f, L, Dh, A) = f * (ṁ * abs(ṁ) / (2 * rho * A^2)) * (L / Dh)

darcy_weisbach_dp(ṁ, rho, f, geom::PipeGeometry) =
    darcy_weisbach_dp(ṁ, rho, f, geom.L, geom.Dh, geom.A)
