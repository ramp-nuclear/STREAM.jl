# dimensionless.jl -- Dimensionless number utilities for STREAM.jl
# Mirrors Python STREAM dimensionless.py
# All functions are plain Julia arithmetic -- MTK traces through them symbolically.
# None are @register_symbolic.

"""
    Re(mdot, A, Dh, mu) -> Float64

Reynolds number from mass flow rate.

# Arguments
- `mdot`: mass flow rate [kg/s] (absolute value taken internally)
- `A`: flow area [m^2]
- `Dh`: hydraulic diameter [m]
- `mu`: dynamic viscosity [Pa*s]

# Returns
Reynolds number (dimensionless).
"""
Re(mdot, A, Dh, mu) = abs(mdot) * Dh / (A * mu)

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
Grashof number.

# Arguments
- `rho`: density [kg/m³]
- `mu`: viscosity [kg/(m°K)]
- `beta`: thermal expansion coefficient [1/K]
- `T_wall`: Wall temperature [°K]
- `T`: Bulk temperature [°K]
- `L`: characteristic length (aka hydraulic diameter) [m]
- `g`: gravitational acceleration [m/s^2]

# Returns
Float64
Grashof number (dimensionless).
"""
Gr(rho, mu, beta, T_wall, T, L, g) = rho^2 * beta * g * (T_wall - T) * L^3 / mu^2

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
