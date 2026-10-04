"""
    blasius(Re) -> f_darcy

Blasius' Darcy friction factor for turbulent flow in a smooth pipe [Blasius1913](@cite):

    f = 0.3164 · Re^(-1/4)

Fitted for `4000 < Re < 10⁵`.

# Arguments
- `Re`: Reynolds number

# Returns
Darcy friction factor (dimensionless).

# Examples
```jldoctest
julia> Friction.blasius(1.0e5)
0.017792479529022645
```
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

Geometric correction ``K_R`` to the laminar friction factor of a rectangular duct,
`f = 64 / (Re · K_R)`, from the fit in [KAERI2014](@cite) also used by the TERMIC code.

# Arguments
- `aspect_ratio`: `depth / width`, in [0, 1]. 0 is the gap between infinite parallel
  plates, 1 a square duct.

# Returns
``K_R`` (dimensionless).

# Examples
```jldoctest
julia> round.(Friction.rectangular_correction.([0.0, 0.01814, 0.5, 1.0]); digits=5)
4-element Vector{Float64}:
 0.66685
 0.68543
 1.03639
 1.12462
```
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

Laminar Darcy friction factor for a rectangular duct, `f = 64 / (Re · K_R)`, with ``K_R``
from [`rectangular_correction`](@ref) at the duct's `depth / width`.

This is the rectangular companion to [`laminar`](@ref). Like it, it has no guard at
`Re = 0`, so a loop whose flow reverses should use [`RegimeDependent`](@ref) instead.
A circular `PipeGeometry` has `depth == width`, so it gets the square-duct factor
(`f ≈ 56.9/Re`), not `64/Re`.

# Arguments
- `geom`: the duct

# Returns
A function `Re -> f`. Wrap it in [`FromReynolds`](@ref) to hand it to a channel.

# Examples
```jldoctest
julia> f = Friction.rectangular_laminar(PipeGeometry_rectangular(0.6, 0.07, 0.07 * 0.01814, 0.07));

julia> f(100.0)
0.9337140113944999
```
"""
function rectangular_laminar(geom::PipeGeometry)
    aspect_ratio = geom.depth / geom.width
    k_R = rectangular_correction(aspect_ratio)
    return (Re) -> 64.0 / (Re * k_R)
end

"""
    turbulent(Re, epsilon=0) -> f_darcy

Explicit approximation to the Colebrook-White turbulent Darcy friction factor, in the form
used by RELAP and by [KAERI2014](@cite) (chapter 2.1.2):

    f = [-2 log₁₀( ε/3.7 + (2.51/Re)·(1.14 - 2 log₁₀(ε + 21.25/Re^0.9)) )]^(-2)

Returns 0 below `Re = 10`, where the logarithms diverge. Python STREAM zeroes the same region.

# Arguments
- `Re`: Reynolds number
- `epsilon`: relative roughness, roughness height over `Dh` (default 0, a smooth pipe)

# Returns
Darcy friction factor (dimensionless).

# Examples
```jldoctest
julia> Friction.turbulent(4e3)
0.039804935964641644

julia> Friction.turbulent(1e6)
0.011649393290640643

julia> Friction.turbulent(4e3, 0.1)
0.1056087044124885
```
"""
function turbulent(Re, epsilon=0)
    # Clamp the Re feeding the log10 terms so they are evaluated at a turbulent Re even
    # while tracing the not-taken branch; the ifelse zeroes the result below Re 10. It is
    # ifelse rather than if because MTK traces this with a symbolic Re.
    Re_safe = max(Re, 10)
    inlog = log10(epsilon + 21.25 / Re_safe^0.9)
    outlog = log10(epsilon / 3.7 + (2.51 / Re_safe) * (1.14 - 2 * inlog))
    f = (-2 * outlog)^(-2)
    return Base.ifelse(Re < 10, zero(f), f)
end

"""
    viscosity_correction(heat_wet_ratio, mu_ratio) -> K_H

Correction ``K_H`` to the friction factor of a heated channel, for the wall viscosity
differing from the bulk:

    K_H = 1 + (P_heated / P_wet) · ((μ_wall / μ_bulk)^0.58 - 1)

# Arguments
- `heat_wet_ratio`: heated perimeter over wetted perimeter
- `mu_ratio`: viscosity at the wall over viscosity in the bulk

# Returns
``K_H`` (dimensionless), a multiplier on the friction factor.

# Examples
```jldoctest
julia> Friction.viscosity_correction(1.0, 2.0)
1.4948492486349383

julia> Friction.viscosity_correction(0.0, 5.0)  # an unheated wall needs no correction
1.0
```
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
