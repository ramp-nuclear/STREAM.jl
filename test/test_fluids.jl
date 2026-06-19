using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using STREAM

# The `@inferred` on the first call of each property checks that the scalar (Float64) method is
# type stable and returns a concrete Float64. That is the numeric path callers and the registered
# symbolic wrappers ultimately dispatch to; it does not exercise the symbolic-trace path itself.
#
# The expected property values are not golden masters captured from a first run. They are the
# outputs of Python STREAM's stream.substances.light_water, which carries the same Simantov
# correlations these Julia functions reimplement (identical coefficients in src/fluids.jl).
# Each value was computed at the matching input and confirmed to agree, run as:
#   conda run -n stream-env python -c "from stream.substances.light_water import *; ..."
# The comment on each expected number names the Python function that produced it.
# Independent physical sanity: rho_water(300 K) sits near 1000 kg/m^3 (liquid water near room
# temperature) and sat_temperature(101325 Pa) lands at 373.15 K (boiling at 1 atm).

@testset "rho_water" begin
    # Python STREAM _density(T - 273.15), saturated liquid density [kg/m^3]
    @test isapprox((@inferred rho_water(300.0)), 995.9257081113179; rtol=1e-5)
    @test isapprox(rho_water(350.0), 973.771823739318; rtol=1e-5)
    @test isapprox(rho_water(400.0), 938.700383367318; rtol=1e-5)
end

@testset "cp_water" begin
    # Python STREAM _specific_heat(abs(T - 273.15)), specific heat [J/(kg*K)]
    @test isapprox((@inferred cp_water(300.0)), 4177.78113807794; rtol=1e-5)
    @test isapprox(cp_water(350.0), 4195.561824263842; rtol=1e-5)
    @test isapprox(cp_water(400.0), 4258.577497251415; rtol=1e-5)
end

@testset "mu_water" begin
    # Python STREAM _viscosity(T - 273.15), dynamic viscosity [Pa*s]
    @test isapprox((@inferred mu_water(300.0)), 8.552485916327526e-4; rtol=1e-5)
    @test isapprox(mu_water(350.0), 3.681015967799774e-4; rtol=1e-5)
    @test isapprox(mu_water(400.0), 2.197326907637552e-4; rtol=1e-5)
end

@testset "k_water" begin
    # Python STREAM _conductivity(T - 273.15), thermal conductivity [W/(m*K)]
    @test isapprox((@inferred k_water(300.0)), 0.6124047547796636; rtol=1e-5)
    @test isapprox(k_water(350.0), 0.6663281213189647; rtol=1e-5)
    @test isapprox(k_water(400.0), 0.6858844508770785; rtol=1e-5)
end

@testset "MTK smoke test — rho_water symbolic" begin
    @variables T_sym(t) = 300.0
    result = rho_water(T_sym)
    @test result isa Symbolics.Num  # symbolic, not a Float64
end

@testset "beta_water" begin
    # Python STREAM _thermal_expansion(T - 273.15), expansion coefficient [1/K]
    @test isapprox((@inferred beta_water(293.15)), 2.790788203166585e-04; rtol=1e-6)
    @test isapprox(beta_water(323.15), 4.3910662993617064e-04; rtol=1e-6)
    @test isapprox(beta_water(373.15), 7.213442303074213e-04; rtol=1e-6)
end

@testset "beta_water MTK symbolic" begin
    @variables T_sym(t) = 300.0
    result = beta_water(T_sym)
    @test result isa Symbolics.Num
end

@testset "Ra from real water properties" begin
    # The old test multiplied two bare numbers and compared to their product, which only restates
    # Ra = Gr * Pr. Instead feed Gr and Pr the actual water-property functions and check the
    # composition holds and behaves physically. A 10 K wall superheat over a 5 mm channel:
    using STREAM: Gr, Pr
    T = 320.0          # bulk [K]
    T_wall = 330.0     # wall [K], hotter than bulk
    L = 5.0e-3         # characteristic length [m]
    g = 9.81           # [m/s^2]
    rho = rho_water(T)
    mu = mu_water(T)
    beta = beta_water(T)
    cp = cp_water(T)
    k = k_water(T)
    Gr_val = Gr(rho, mu, beta, T_wall, T, L, g)
    Pr_val = Pr(cp, mu, k)
    # Ra reproduces the Gr-times-Pr chain built from independent property calls.
    @test isapprox(Ra(Gr_val, Pr_val), Gr_val * Pr_val; rtol=1e-12)
    # Heated wall (T_wall > T) drives buoyancy, so Ra is positive; water near 320 K has Pr a few.
    @test Ra(Gr_val, Pr_val) > 0.0
    @test 1.0 < Pr_val < 10.0
    # Flip the wall below the bulk: buoyancy reverses, so Ra changes sign.
    Gr_cooled = Gr(rho, mu, beta, T - 10.0, T, L, g)
    @test Ra(Gr_cooled, Pr_val) < 0.0
end

@testset "sat_temperature" begin
    # Python STREAM _sat_temperature(P) + 273.15, saturation temperature [K].
    @test isapprox((@inferred sat_temperature(1e5)), 372.7807281085724; rtol=1e-4)   # 99.63 C
    @test isapprox(sat_temperature(0.5e5), 354.43047959788385; rtol=1e-4)   # 81.28 C
    @test isapprox(sat_temperature(2e5), 393.44401952865115; rtol=1e-4)   # 120.29 C
    # Independent physical anchor: water boils at 373.15 K (100 C) at 1 atm.
    @test isapprox(sat_temperature(101325.0), 373.15; rtol=1e-3)
end

@testset "sat_temperature MTK symbolic" begin
    @variables P_sym(t) = 1e5
    result = sat_temperature(P_sym)
    @test result isa Symbolics.Num
end

@testset "_bergles_rohsenow_dT_ONB" begin
    # Zero heat flux -> zero superheat
    @test STREAM._bergles_rohsenow_dT_ONB(1e10, 0.0) == 0.0
    # Typical reactor conditions: positive dT
    dT = STREAM._bergles_rohsenow_dT_ONB(1e5, 1e6)
    @test dT > 0.0
    @test isfinite(dT)
end

@testset "AbstractFluid — Water() forwards to the *_water correlations" begin
    for T in (300.0, 350.0, 400.0)
        @test density(Water(), T) == rho_water(T)
        @test specific_heat(Water(), T) == cp_water(T)
        @test viscosity(Water(), T) == mu_water(T)
        @test conductivity(Water(), T) == k_water(T)
        @test thermal_expansion(Water(), T) == beta_water(T)
    end
end

@testset "ConstantFluid — fixed properties, all-ones mock default" begin
    mock = ConstantFluid()
    for T in (1.0, 300.0, 600.0)   # temperature-independent
        @test density(mock, T) == 1.0
        @test specific_heat(mock, T) == 1.0
        @test viscosity(mock, T) == 1.0
        @test conductivity(mock, T) == 1.0
        @test thermal_expansion(mock, T) == 1.0
    end
    cf = ConstantFluid(; rho=1000.0, cp=4200.0, mu=1.0e-3, k=0.6, beta=2.0e-4)
    @test density(cf, 320.0) == 1000.0
    @test specific_heat(cf, 320.0) == 4200.0
    @test viscosity(cf, 320.0) == 1.0e-3
    @test conductivity(cf, 320.0) == 0.6
    @test thermal_expansion(cf, 320.0) == 2.0e-4
end
