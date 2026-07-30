# heavy_water.jl -- saturated heavy water (D₂O) property correlations.
#
# Source for every coefficient below:
#   A. Crabtree and M. Siman-Tov, "Thermophysical Properties of Saturated Light and Heavy
#   Water for Advanced Neutron Source Applications", ORNL/TM-12322, 1993.
#
# Same shape as light_water.jl: saturation-line fits in Celsius and Pa, with the pressure
# argument unused outside `sat_temperature`, and per-function reference values asserted in
# test_substances.jl.

"""
    HeavyWater()
    D2O

Saturated heavy water (D₂O).

Correlations come from A. Crabtree and M. Siman-Tov, "Thermophysical Properties of
Saturated Light and Heavy Water for Advanced Neutron Source Applications", ORNL/TM-12322,
1993.

[`D2O`](@ref) is the singleton instance.
"""
struct HeavyWater <: AbstractLiquid end

"""
    D2O

The [`HeavyWater`](@ref) singleton.
"""
const D2O = HeavyWater()

"""
    density(D2O, T, p) -> kg/m^3

Saturated liquid density. As with light water the ORNL fit is stated in Fahrenheit.

Reference values: 1095.7419670000002 at 50 °C, 1063.4244970000002 at 100 °C.
"""
function density(::HeavyWater, T, p)
    A = 1117.772605
    B = -0.077855
    C = -8.42e-4
    TF = 1.8T + 32
    return A + B * TF + C * TF^2
end

"""
    thermal_expansion(D2O, T, p) -> 1/K

Isobaric thermal expansion coefficient taken analytically from the density fit above.

Reference values: 312.34463951465654e-6 at 20 °C, 736.0686181371651e-6 at 100 °C.
"""
function thermal_expansion(l::HeavyWater, T, p)
    B = -0.077855
    C = -8.42e-4
    TF = 1.8T + 32
    return -1.8 * (B + 2C * TF) / density(l, T, p)
end

"""
    specific_heat(D2O, T, p) -> J/(kg·K)

Specific heat of the saturated liquid, a cubic in scaled Rankine temperature.

Reference values: 4220.658975628751 at 50 °C, 4162.210117465748 at 100 °C.
"""
function specific_heat(::HeavyWater, T, p)
    Tl = (1.8T + 491.67) * 1e-4
    A = 2.237124
    B = 122.217151
    C = -2303.384060
    D = 13555.737878
    return 1e3 * (A + B * Tl + C * Tl^2 + D * Tl^3)
end

"""
    viscosity(D2O, T, p) -> Pa·s

Dynamic viscosity of the saturated liquid.

Reference values: 6.441125212510078e-4 at 50 °C, 3.301433604774831e-4 at 100 °C.
"""
function viscosity(::HeavyWater, T, p)
    TF = 1.8T + 32
    A = -1.111606e-4
    B = 9.46e-8
    C = 0.0873655375
    D = 0.4111103409
    return A + B * TF + C / TF + D / TF^2
end

"""
    conductivity(D2O, T, p) -> W/(m·K)

Thermal conductivity of the saturated liquid.

Reference values: 0.6167873183429435 at 50 °C, 0.6357784886396809 at 100 °C.
"""
function conductivity(::HeavyWater, T, p)
    Tl = (1.8T + 491.67) * 1e-4
    A = -0.4521496
    B = 36.0743280
    C = -357.9973221
    D = 924.0219962
    return A + B * Tl + C * Tl^2 + D * Tl^3
end

"""
    sat_temperature(D2O, T, p) -> °C

Saturation temperature at pressure `p`. The temperature argument is unused; the two-argument
short form `sat_temperature(D2O, p)` takes the pressure directly.

Reference values: 100.98975482398993 at 1e5 Pa, 82.7830309880722 at 0.5e5 Pa,
121.5058319422803 at 2e5 Pa.
"""
function sat_temperature(::HeavyWater, T, p)
    X = log(abs(p) * 1e-6)
    A = 5.194927982
    B = 0.236771673
    C = -2.615268e-3
    D = 1.708386e-3
    return exp(A + B * X + C * X^2 + D * X^3)
end

"""
    latent_heat(D2O, T, p) -> J/kg

Latent heat of vaporization, correlated against distance from the critical temperature.

Reference values: 2199499.183881408 at 50 °C, 2076983.0825663893 at 100 °C.
"""
function latent_heat(::HeavyWater, T, p)
    X = abs(371.49 - T)
    A = 508093.6669
    B = 17006.921765
    C = -11.009078
    return 1e3 * sqrt(abs(A + B * X + C * X^2))
end

"""
    surface_tension(D2O, T, p) -> N/m

Liquid-vapor surface tension, correlated against reduced distance from the critical point.

Reference values: 0.06809951822968323 at 50 °C, 0.059250184550697166 at 100 °C.
"""
function surface_tension(::HeavyWater, T, p)
    X = abs(373.99 - T) / 647.15
    A = 2.44835759e-1
    B = 1.269
    C = -6.60709649e-1
    return A * X^B * (1 + C * X)
end

"""
    vapor_density(D2O, T, p) -> kg/m^3

Saturated vapor density.

Reference values: 0.08342446145018677 at 50 °C, 0.6309356177290303 at 100 °C.
"""
function vapor_density(::HeavyWater, T, p)
    A = -5.456208705
    B = 2.386228e-3
    C = 0.060526809
    D = -1.15778e-5
    E = -1.1136e-4
    return exp((A + C * T + E * T^2) / (1 + B * T + D * T^2))
end

Base.show(io::IO, ::HeavyWater) = print(io, "D2O")
