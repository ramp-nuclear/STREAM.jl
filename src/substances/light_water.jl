# light_water.jl -- saturated light water (H₂O) property correlations.
#
# Source for every coefficient below:
#   A. Crabtree and M. Siman-Tov, "Thermophysical Properties of Saturated Light and Heavy
#   Water for Advanced Neutron Source Applications", ORNL/TM-12322, 1993.
#
# Each function's docstring records reference values at a couple of temperatures. They are
# asserted in test_substances.jl, so a change to the arithmetic fails a test rather than
# drifting quietly.
#
# These are fits along the saturation line, so every property except the saturation
# temperature itself is a function of temperature alone and ignores the pressure
# argument. Temperatures are Celsius, pressures Pa.
#
# Several correlations wrap their argument in `abs`. That is not physics, it keeps a solver
# iterate that wanders outside the fitted range from raising a DomainError before it
# recovers.

"""
    LightWater()
    H2O

Saturated light water (H₂O).

Correlations come from A. Crabtree and M. Siman-Tov, "Thermophysical Properties of
Saturated Light and Heavy Water for Advanced Neutron Source Applications", ORNL/TM-12322,
1993.

[`H2O`](@ref) is the singleton instance and is what components default to.
"""
struct LightWater <: AbstractLiquid end

"""
    H2O

The [`LightWater`](@ref) singleton, and the default coolant across the package.
"""
const H2O = LightWater()

"""
    density(H2O, T, p) -> kg/m^3

Saturated liquid density. The ORNL fit is stated in Fahrenheit, hence the inline conversion.

Reference values: 987.27431208 at 50 °C, 959.13959928 at 100 °C.
"""
function density(::LightWater, T, p)
    A = 1004.789042
    B = -0.046283
    C = -7.9738e-4
    TF = 1.8T + 32
    return abs(A + B * TF + C * TF^2)
end

"""
    thermal_expansion(H2O, T, p) -> 1/K

Isobaric thermal expansion coefficient, `-(1/ρ)·dρ/dT` taken analytically from the density
fit above.

Reference values: 279.0788203166585e-6 at 20 °C, 721.3442303074213e-6 at 100 °C.
"""
function thermal_expansion(l::LightWater, T, p)
    B = -0.046283
    C = -7.9738e-4
    TF = 1.8T + 32
    return -1.8 * (B + 2C * TF) / density(l, T, p)
end

"""
    specific_heat(H2O, T, p) -> J/(kg·K)

Specific heat of the saturated liquid. The fit is even in temperature, so the argument is
folded through `abs` first and `T` and `-T` give the same answer.

Reference values: 4179.863745234987 at 8 °C, 4181.4264285644285 at 50 °C.
"""
function specific_heat(::LightWater, T, p)
    T = abs(T)
    A = 17.48908904
    B = -1.67507e-3
    C = -0.03189591
    D = -2.8748e-6
    return sqrt(abs((A + C * T) / (1 + B * T + D * T^2))) * 1e3
end

"""
    viscosity(H2O, T, p) -> Pa·s

Dynamic viscosity of the saturated liquid.

Reference value: 3.1444961652895464e-4 at 90 °C.
"""
function viscosity(::LightWater, T, p)
    A = -6.325203964
    B = 8.705317e-3
    C = -0.088832314
    D = -9.657e-7
    return exp((A + C * T) / (1 + B * T + D * T^2))
end

"""
    conductivity(H2O, T, p) -> W/(m·K)

Thermal conductivity of the saturated liquid.

Reference value: 0.6419141378687501 at 50 °C.
"""
function conductivity(::LightWater, T, p)
    A = 0.5677829144
    B = 1.8774171e-3
    C = -8.1790e-6
    D = 5.66294775e-9
    return abs(A + B * T + C * T^2 + D * T^3)
end

"""
    sat_temperature(H2O, T, p) -> °C

Saturation temperature at pressure `p`. The temperature argument is unused; the two-argument
short form `sat_temperature(H2O, p)` takes the pressure directly.

Reference values: 99.63072810857243 at 1e5 Pa, 81.28047959788387 at 0.5e5 Pa,
120.29401952865119 at 2e5 Pa.
"""
function sat_temperature(::LightWater, T, p)
    X = log(abs(p) * 1e-6)
    A = 179.9600321
    B = -0.1063030
    C = 24.2278298
    D = 2.951e-4
    return (A + C * X) / (1 + B * X + D * X^2)
end

"""
    latent_heat(H2O, T, p) -> J/kg

Latent heat of vaporization.

Reference values: 2382729.243923866 at 50 °C, 2257149.1343506747 at 100 °C.
"""
function latent_heat(::LightWater, T, p)
    A = 6254828.560
    B = -11742.337953
    C = 6.336845
    D = -0.049241
    return 1e3 * sqrt(abs(A + B * T + C * T^2 + D * T^3))
end

"""
    surface_tension(H2O, T, p) -> N/m

Liquid-vapor surface tension, correlated against reduced distance from the critical point.

Reference values: 0.06794675477982745 at 50 °C, 0.05891594230703328 at 100 °C.
"""
function surface_tension(::LightWater, T, p)
    X = abs(373.99 - T) / 647.15
    A = 235.8e-3
    B = 1.256
    C = -0.625
    return A * X^B * abs(1 + C * X)
end

"""
    vapor_density(H2O, T, p) -> kg/m^3

Saturated vapor density.

Reference values: 0.08307666133931553 at 50 °C, 0.5978051373615001 at 100 °C.
"""
function vapor_density(::LightWater, T, p)
    A = -4.375094e-4
    B = -6.947700e-3
    C = 7.662589e-4
    D = 2.418897e-5
    E = -5.963920e-6
    F = -4.227966e-8
    G = 2.867976e-7
    H = 2.594175e-11
    return (A + C * T + E * T^2 + G * T^3) /
           (1 + B * T + D * T^2 + F * T^3 + H * T^4)
end
