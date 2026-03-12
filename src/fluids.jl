# Fluid property functions for light water (Simantov correlations)
# Stub implementation — replaced by Plan 02
# Temperature input: Kelvin. No range guards (ForwardDiff compatibility).

_to_fahrenheit(T_C::Real) = 1.8 * T_C + 32.0

"""
    rho_water(T_K) -> kg/m³
Saturated liquid water density (Simantov). T_K in Kelvin.
"""
function rho_water(T_K::Real)
    return 0.0  # STUB — Plan 02 implements
end

"""
    cp_water(T_K) -> J/(kg·K)
Specific heat of saturated liquid water (Simantov). T_K in Kelvin.
"""
function cp_water(T_K::Real)
    return 0.0  # STUB — Plan 02 implements
end

"""
    mu_water(T_K) -> Pa·s
Dynamic viscosity of saturated liquid water (Simantov). T_K in Kelvin.
"""
function mu_water(T_K::Real)
    return 0.0  # STUB — Plan 02 implements
end

"""
    k_water(T_K) -> W/(m·K)
Thermal conductivity of saturated liquid water (Simantov). T_K in Kelvin.
"""
function k_water(T_K::Real)
    return 0.0  # STUB — Plan 02 implements
end

# @register_symbolic must be at module top-level — placed here after definitions
@register_symbolic rho_water(T::Real)
@register_symbolic cp_water(T::Real)
@register_symbolic mu_water(T::Real)
@register_symbolic k_water(T::Real)
