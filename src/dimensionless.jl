
@doc raw"""
    Re(ṁ, A, Dh, mu) -> Float64

Reynolds number from mass flow rate, ``Re = |\dot{m}| D_h / (A μ)``.

# Arguments
- `ṁ`: mass flow rate [kg/s] (absolute value taken internally)
- `A`: flow area [m^2]
- `Dh`: hydraulic diameter [m]
- `mu`: dynamic viscosity [Pa*s]

# Returns
Reynolds number (dimensionless).
"""
Re(ṁ, A, Dh, mu) = abs(ṁ) * Dh / (A * mu)

"""
    Re_vel(rho, u, L, mu) -> Float64

Reynolds number from velocity, ``Re = ρ |u| L / μ``.

# Arguments
- `rho`: density [kg/m^3]
- `u`: velocity [m/s] (absolute value taken internally)
- `L`: characteristic length [m]
- `mu`: dynamic viscosity [Pa*s]

# Returns
Reynolds number (dimensionless).
"""
Re_vel(rho, u, L, mu) = rho * abs(u) * L / mu

"""
    Pr(cp, mu, k) -> Float64

Prandtl number, ``Pr = c_p μ / k``.

# Arguments
- `cp`: specific heat [J/(kg*K)]
- `mu`: dynamic viscosity [Pa*s]
- `k`: thermal conductivity [W/(m*K)]

# Returns
Prandtl number (dimensionless).
"""
Pr(cp, mu, k) = cp * mu / k

"""
    Re(liquid, T, ṁ, A, Dh) -> Float64
    Pr(liquid, T) -> Float64
    Gr(liquid, T, T_wall, L, g) -> Float64

The same numbers with the properties read off a coolant at the bulk temperature `T` [°C].

# Examples
```jldoctest
julia> round(Pr(H2O, 40.0); sigdigits=7)
4.323622
```
"""
Re(liquid::AbstractLiquid, T, ṁ, A, Dh) = Re(ṁ, A, Dh, μ(liquid, T))
Pr(liquid::AbstractLiquid, T) = Pr(cₚ(liquid, T), μ(liquid, T), κ(liquid, T))

"""
    flow_regime_blend(Re, re_bounds, laminar, turbulent)

Choose between a laminar and a turbulent value on Reynolds number, blending linearly across
the transition band.

`re_bounds` is `(re_lo, re_hi)`: at or below `re_lo` the flow is laminar, above `re_hi` it is
turbulent, and between them the two values are interpolated linearly in `Re`. Both values are
evaluated whichever is returned, so each must be finite everywhere.

# Arguments
- `Re`: Reynolds number to classify
- `re_bounds`: `(re_lo, re_hi)` band edges
- `laminar`, `turbulent`: the two values to select between or blend

# Returns
The laminar value, the turbulent value, or their linear blend.

# Examples
```jldoctest
julia> [flow_regime_blend(Re, (2000.0, 5000.0), 4.0, 100.0) for Re in (1000.0, 3500.0, 8000.0)]
3-element Vector{Float64}:
   4.0
  52.0
 100.0
```
"""
function flow_regime_blend(Re, re_bounds, laminar, turbulent)
    re_lo, re_hi = re_bounds
    interim = (turbulent - laminar) / (re_hi - re_lo) * (Re - re_hi) + turbulent
    return ifelse(Re <= re_lo, laminar, ifelse(Re > re_hi, turbulent, interim))
end

"""
    Nu(h, Dh, k) -> Float64

Nusselt number, ``Nu = h D_h / k``.

# Arguments
- `h`: heat transfer coefficient [W/(m^2*K)]
- `Dh`: hydraulic diameter [m]
- `k`: thermal conductivity [W/(m*K)]

# Returns
Nusselt number (dimensionless).
"""
Nu(h, Dh, k) = h * Dh / k

"""
    Pe(Re_val, Pr_val) -> Float64

Peclet number = Re * Pr.

# Arguments
- `Re_val`: Reynolds number
- `Pr_val`: Prandtl number

# Returns
Peclet number (dimensionless).
"""
Pe(Re_val, Pr_val) = Re_val * Pr_val

"""
    Gr(rho, mu, beta, T_wall, T, L, g) -> Float64

Grashof number, ``Gr = ρ^2 β g (T_{wall} - T) L^3 / μ^2``.

# Arguments
- `rho`: density [kg/m^3]
- `mu`: viscosity [Pa*s]
- `beta`: thermal expansion coefficient [1/K]
- `T_wall`: wall temperature [°C]
- `T`: bulk temperature [°C]
- `L`: characteristic length (hydraulic diameter) [m]
- `g`: gravitational acceleration [m/s^2]

# Returns
Grashof number (dimensionless).
"""
Gr(rho, mu, beta, T_wall, T, L, g) = rho^2 * beta * g * (T_wall - T) * L^3 / mu^2

# Buoyancy is driven by the bulk-to-wall difference, so ρ, μ and β are taken at the bulk
# temperature `T`.
function Gr(liquid::AbstractLiquid, T, T_wall, L, g)
    return Gr(ρ(liquid, T), μ(liquid, T), β(liquid, T), T_wall, T, L, g)
end

"""
    Ra(Gr_val, Pr_val) -> Float64

Rayleigh number = Gr * Pr.

# Arguments
- `Gr_val`: Grashof number
- `Pr_val`: Prandtl number

# Returns
Rayleigh number (dimensionless).
"""
Ra(Gr_val, Pr_val) = Gr_val * Pr_val
