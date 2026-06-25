# Fluid property functions for light water.
# Source: Moshe Siman Tov et al.

# Internal helper — not exported
_to_fahrenheit(T_C::Real) = 1.8 * T_C + 32.0

"""
    rho_water(T_K) -> kg/m^3

Saturated liquid water density (Simantov correlation).

Note: uses Fahrenheit internally, a quirk of the Simantov correlation.

# Arguments
- `T_K`: temperature [K]

# Returns
Density [kg/m^3] as `Float64`.
"""
function rho_water(T_K::Real)
    T_C = T_K - 273.15
    T_F = _to_fahrenheit(T_C)
    A = 1004.789042
    B = -0.046283
    C = -7.9738e-4
    return abs(A + B * T_F + C * T_F^2)
end

"""
    cp_water(T_K) -> J/(kg*K)

Specific heat of saturated liquid water (Simantov correlation).

# Arguments
- `T_K`: temperature [K]

# Returns
Specific heat [J/(kg*K)] as `Float64`.
"""
function cp_water(T_K::Real)
    T_C = abs(T_K - 273.15)   # abs matches Python STREAM's np.abs(T)
    A = 17.48908904
    B = -1.67507e-3
    C = -0.03189591
    D = -2.8748e-6
    return sqrt(max(0.0, (A + C * T_C) / (1 + B * T_C + D * T_C^2))) * 1000.0
end

"""
    mu_water(T_K) -> Pa*s

Dynamic viscosity of saturated liquid water (Simantov correlation).

# Arguments
- `T_K`: temperature [K]

# Returns
Dynamic viscosity [Pa*s] as `Float64`.
"""
function mu_water(T_K::Real)
    T_C = T_K - 273.15
    A = -6.325203964
    B = 8.705317e-3
    C = -0.088832314
    D = -9.657e-7
    return exp((A + C * T_C) / (1 + B * T_C + D * T_C^2))
end

"""
    k_water(T_K) -> W/(m*K)

Thermal conductivity of saturated liquid water (Simantov correlation).

# Arguments
- `T_K`: temperature [K]

# Returns
Thermal conductivity [W/(m*K)] as `Float64`.
"""
function k_water(T_K::Real)
    T_C = T_K - 273.15
    A = 0.5677829144
    B = 1.8774171e-3
    C = -8.1790e-6
    D = 5.66294775e-9
    return abs(A + B * T_C + C * T_C^2 + D * T_C^3)
end

"""
    beta_water(T_K) -> 1/K

Isobaric thermal expansion coefficient of saturated liquid water (Simantov correlation).
Derived analytically from the Simantov density formula: beta = -(1/rho) * d(rho)/dT.

# Arguments
- `T_K`: temperature [K]

# Returns
Thermal expansion coefficient [1/K] as `Float64`.
"""
function beta_water(T_K::Real)
    T_C = T_K - 273.15
    T_F = _to_fahrenheit(T_C)
    B = -0.046283
    C = -7.9738e-4
    return -1.8 * (B + 2 * C * T_F) / rho_water(T_K)
end

"""
    sat_temperature(P_Pa) -> K

Saturation temperature of light water at absolute pressure P_Pa (Simantov correlation).
Input: pressure in Pa. Output: temperature in Kelvin.

Guard: uses abs(P_Pa) inside log to prevent DomainError at bad Newton iterates.

Note: P[i] absolute pressure is only meaningful when a pressure anchor is set
on a FlowPort in the loop (e.g., pump.inlet.p ~ 1e5).

# Arguments
- `P_Pa`: absolute pressure [Pa]

# Returns
Saturation temperature [K] as `Float64`.
"""
function sat_temperature(P_Pa::Real)
    X = log(abs(P_Pa) * 1e-6)
    A = 179.9600321
    B = -0.1063030
    C = 24.2278298
    D = 2.951e-4
    T_C = (A + C * X) / (1 + B * X + D * X^2)
    return T_C + 273.15
end

# @register_symbolic must be at module top-level (not inside any function or begin block).
# These lines make the functions callable with symbolic MTK variables (Num type).
@register_symbolic rho_water(T::Real)
@register_symbolic cp_water(T::Real)
@register_symbolic mu_water(T::Real)
@register_symbolic k_water(T::Real)
@register_symbolic beta_water(T::Real)
@register_symbolic sat_temperature(P::Real)

# ----------------------------------------------------------------------------
# Injectable fluid properties.
#
# A channel's transport properties are looked up through an `AbstractFluid` so a
# test (or a future second coolant) can supply its own property set without
# editing the channel. `Water()` routes straight to the `*_water` correlations
# above, so a water channel emits the identical symbolic expressions it always
# has — the numeric path is unchanged. `ConstantFluid` returns fixed values, the
# Julia counterpart of Python STREAM's `mock_liquid_funcs` (all properties 1.0),
# which gives channel tests clean closed-form numbers.
# ----------------------------------------------------------------------------

"""
    AbstractFluid

Supertype for coolant property sets. Implement `density`, `specific_heat`,
`viscosity`, `conductivity`, and `thermal_expansion` for a concrete fluid; the
channel components dispatch on it.
"""
abstract type AbstractFluid end

"""
    Water() <: AbstractFluid

Light-water coolant. Properties come from the Simantov `*_water` correlations, so a
`Water` channel is identical to the original hard-coded behaviour.
"""
struct Water <: AbstractFluid end

"""
    ConstantFluid(; rho=1.0, cp=1.0, mu=1.0, k=1.0, beta=1.0) <: AbstractFluid

Temperature-independent coolant returning fixed property values — the analogue of Python
STREAM's `mock_liquid_funcs`. The all-ones default gives channel tests clean closed-form
temperatures (e.g. a uniform-heating linear rise with `cp = 1`).

# Arguments
- `rho`: density [kg/m^3]
- `cp`: specific heat [J/(kg·K)]
- `mu`: dynamic viscosity [Pa·s]
- `k`: thermal conductivity [W/(m·K)]
- `beta`: thermal expansion coefficient [1/K]
"""
struct ConstantFluid{T<:Real} <: AbstractFluid
    rho::T
    cp::T
    mu::T
    k::T
    beta::T
end

function ConstantFluid(; rho=1.0, cp=1.0, mu=1.0, k=1.0, beta=1.0)
    return ConstantFluid(promote(rho, cp, mu, k, beta)...)
end

"""
    density(fluid, T)        # [kg/m^3]
    specific_heat(fluid, T)  # [J/(kg·K)]
    viscosity(fluid, T)      # [Pa·s]
    conductivity(fluid, T)   # [W/(m·K)]
    thermal_expansion(fluid, T)  # [1/K]

Transport properties of `fluid` at temperature `T` [K]. `Water` forwards to the
`*_water` correlations; `ConstantFluid` returns its stored values.
"""
density(::Water, T) = rho_water(T)
specific_heat(::Water, T) = cp_water(T)
viscosity(::Water, T) = mu_water(T)
conductivity(::Water, T) = k_water(T)
thermal_expansion(::Water, T) = beta_water(T)

density(f::ConstantFluid, T) = f.rho
specific_heat(f::ConstantFluid, T) = f.cp
viscosity(f::ConstantFluid, T) = f.mu
conductivity(f::ConstantFluid, T) = f.k
thermal_expansion(f::ConstantFluid, T) = f.beta
