# dimensionless.jl -- Dimensionless number utilities
# Mirrors Python STREAM dimensionless.py
# All functions are plain Julia arithmetic -- MTK traces through them symbolically.
# None are @register_symbolic.

"""
    Re(ṁ, A, Dh, mu) -> Float64

Reynolds number from mass flow rate.

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

Reynolds number from velocity.

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

Prandtl number.

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
"""
Re(liquid::AbstractLiquid, T, ṁ, A, Dh) = Re(ṁ, A, Dh, μ(liquid, T))
Pr(liquid::AbstractLiquid, T) = Pr(cₚ(liquid, T), μ(liquid, T), κ(liquid, T))

"""
    Nu(h, Dh, k) -> Float64

Nusselt number.

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

Grashof number.

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
