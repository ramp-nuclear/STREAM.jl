
"""
    LightWater

Type representing saturated light water correlations.
"""
struct LightWater <: AbstractLiquid end
const H2O = LightWater()

function viscosity(::LightWater, T)
    A = -6.325203964
    B = 8.705317e-3
    C = -0.088832314
    D = -9.657e-7
    return exp((A + C*T) / (1 + B*T + D*T^2))
end

function specific_heat(::LightWater, T)
    T = abs(T)
    A = 17.48908904
    B = -1.67507e-3
    C = -0.03189591
    D = -2.8748e-6
    return sqrt((A + C*T) / (1 + B*T + D*T^2)) * 1e3
end

function conductivity(::LightWater, T)
    A = 0.5677829144
    B = 1.8774171e-3
    C = -8.1790e-6
    D = 5.66294775e-9
    return abs(A + B*T + C*T^2 + D*T^3)
end

function density(::LightWater, T)
    A = 1004.789042
    B = -0.046283
    C = -7.9738e-4
    TF = 1.8*T + 32
    return abs(A + B*TF + C*TF^2)
end

function thermal_expansion(::LightWater, T)
    B = -0.046283
    C = -7.9738e-4
    TF = 1.8*T + 32
    return -1.8 * (B + 2C*TF) / density(H2O, T)
end

function sat_temperature(::LightWater, P)
    X = log(abs(P) * 1e-6)
    A = 179.9600321
    B = -0.1063030
    C = 24.2278298
    D = 2.951e-4
    return (A + C*X) / (1 + B*X + D*X^2)
end

function latent_heat(::LightWater, T)
    A = 6254828.560
    B = -11742.337953
    C = 6.336845
    D = -0.049241
    return 1e3 * sqrt(abs(A + B*T + C*T^2 + D*T^3))
end

function surface_tension(::LightWater, T)
    X = abs(373.99 - T) / 647.15
    A = 235.8e-3
    B = 1.256
    C = -0.625
    return A * X^B * abs(1 + C*X)
end

function vapor_density(::LightWater, T)
    A = -4.375094e-4
    B = -6.947700e-3
    C = 7.662589e-4
    D = 2.418897e-5
    E = -5.963920e-6
    F = -4.227966e-8
    G = 2.867976e-7
    H = 2.594175e-11
    return (A + C*T + E*T^2 + G*T^3) /
           (1 + B*T + D*T^2 + F*T^3 + H*T^4)
end

