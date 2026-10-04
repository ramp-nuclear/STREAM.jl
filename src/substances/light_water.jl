"""
    LightWater()
    H2O

Saturated light water (H₂O).

The correlations are those of Crabtree and Siman-Tov [CrabtreeSimantov1993](@cite).

[`H2O`](@ref) is the singleton instance and is what components default to.

Fits along the saturation line, so every property except the saturation temperature depends on
temperature alone and ignores its pressure argument. Temperatures are Celsius, pressures Pa.

Several correlations wrap their argument in `abs`, which keeps a solver iterate that wanders
below the fitted range from raising a `DomainError`.
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

# Examples
```jldoctest
julia> density(H2O, 50.0)
987.27431208

julia> density(H2O, 100.0)
959.13959928
```
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

# Examples
```jldoctest
julia> thermal_expansion(H2O, 20.0)
0.0002790788203166585

julia> thermal_expansion(H2O, 100.0)
0.0007213442303074213
```
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

# Examples
```jldoctest
julia> specific_heat(H2O, 8.0)
4179.863745234987

julia> specific_heat(H2O, 50.0)
4181.4264285644285
```
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

# Examples
```jldoctest
julia> viscosity(H2O, 90.0)
0.00031444961652895464
```
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

# Examples
```jldoctest
julia> conductivity(H2O, 50.0)
0.6419141378687501
```
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

# Examples
```jldoctest
julia> sat_temperature(H2O, 1e5)
99.63072810857243

julia> sat_temperature(H2O, 0.5e5)
81.28047959788387

julia> sat_temperature(H2O, 2e5)
120.29401952865119
```
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

# Examples
```jldoctest
julia> latent_heat(H2O, 50.0)
2.382729243923866e6

julia> latent_heat(H2O, 100.0)
2.2571491343506747e6
```
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

# Examples
```jldoctest
julia> surface_tension(H2O, 50.0)
0.06794675477982745

julia> surface_tension(H2O, 100.0)
0.05891594230703328
```
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

# Examples
```jldoctest
julia> vapor_density(H2O, 50.0)
0.08307666133931553

julia> vapor_density(H2O, 100.0)
0.5978051373615001
```
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

# `H2O` is how this singleton is referred to everywhere, so print it that way.
Base.show(io::IO, ::LightWater) = print(io, "H2O")
