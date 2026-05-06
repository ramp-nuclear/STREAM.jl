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

Pr(l::AbstractLiquid, T) = cₚ(l, T) * μ(l, T) / k(l, T)

"""
    Nu(h, Dh, k) -> Float64

Nusselt number from heat transfer coefficient.

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
    Gr(beta, g, dT, L, nu) -> Float64

Grashof number. Simplified form using kinematic viscosity:
Gr = beta * g * dT * L^3 / nu^2

Mathematically equivalent to Python STREAM's rho^2 * g * beta * dT * L^3 / mu^2
(since nu = mu/rho).

# Arguments
- `beta`: thermal expansion coefficient [1/K]
- `g`: gravitational acceleration [m/s^2]
- `dT`: temperature difference T_wall - T_bulk [K]
- `L`: characteristic length [m]
- `nu`: kinematic viscosity [m^2/s] (= mu/rho)

# Returns
Grashof number (dimensionless).
"""
Gr(beta, g, dT, L, nu) = beta * g * dT * L^3 / nu^2

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
