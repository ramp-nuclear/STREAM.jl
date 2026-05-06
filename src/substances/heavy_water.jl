"""
    HeavyWater

Type representing saturated heavy water (D₂O) correlations.
"""
struct HeavyWater <: AbstractLiquid end

const D2O = HeavyWater()

function density(::HeavyWater, T)
    TF = 1.8*T + 32
    A = 1117.772605
    B = -0.077855
    C = -8.42e-4
    return A + B*TF + C*TF^2
end

function thermal_expansion(::HeavyWater, T)
    B = -0.077855
    C = -8.42e-4
    TF = 1.8*T + 32
    return -1.8 * (B + 2C*TF) / density(D2O, T)
end

function specific_heat(::HeavyWater, T)
    Tl = (1.8*T + 491.67) * 1e-4
    A = 2.237124
    B = 122.217151
    C = -2303.384060
    D = 13555.737878
    return 1000 * (A + B*Tl + C*Tl^2 + D*Tl^3)
end

function viscosity(::HeavyWater, T)
    TF = 1.8*T + 32
    A = -1.111606e-4
    B = 9.46e-8
    C = 0.0873655375
    D = 0.4111103409
    return A + B*TF + C/TF + D/(TF^2)
end

function conductivity(::HeavyWater, T)
    Tl = (1.8*T + 491.67) * 1e-4
    A = -0.4521496
    B = 36.0743280
    C = -357.9973221
    D = 924.0219962
    return A + B*Tl + C*Tl^2 + D*Tl^3
end

function sat_temperature(::HeavyWater, P)
    X = log(abs(P) * 1e-6)
    A = 5.194927982
    B = 0.236771673
    C = -2.615268e-3
    D = 1.708386e-3
    return exp(A + B*X + C*X^2 + D*X^3)
end

function surface_tension(::HeavyWater, T)
    X = abs(373.99 - T) / 647.15
    A = 2.44835759e-1
    B = 1.269
    C = -6.60709649e-1
    return A * X^B * (1 + C*X)
end

function vapor_density(::HeavyWater, T)
    A = -5.456208705
    B = 2.386228e-3
    C = 0.060526809
    D = -1.15778e-5
    E = -1.1136e-4
    return exp((A + C*T + E*T^2) / (1 + B*T + D*T^2))
end

function latent_heat(::HeavyWater, T)
    X = abs(371.49 - T)
    A = 508093.6669
    B = 17006.921765
    C = -11.009078
    return sqrt(A + B*X + C*X^2) * 1000
end