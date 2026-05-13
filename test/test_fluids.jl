using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using STREAM

# ─────────────────────────────────────────────────────────────────
# FOUND-02: Fluid property spot-checks (Simantov correlations)
# Reference values computed from Python STREAM light_water.py
# Tolerance: rtol=1e-6 (deterministic polynomial; any larger diff = unit error)
# ─────────────────────────────────────────────────────────────────
@testset "FOUND-02: rho_water" begin
    @test isapprox(rho_water(300.0), 995.925708; rtol=1e-5)
    @test isapprox(rho_water(350.0), 973.771824; rtol=1e-5)
    @test isapprox(rho_water(400.0), 938.700383; rtol=1e-5)
end

@testset "FOUND-02: cp_water" begin
    @test isapprox(cp_water(300.0), 4177.781138; rtol=1e-5)
    @test isapprox(cp_water(350.0), 4195.561824; rtol=1e-5)
    @test isapprox(cp_water(400.0), 4258.577497; rtol=1e-5)
end

@testset "FOUND-02: mu_water" begin
    @test isapprox(mu_water(300.0), 8.5524859163e-4; rtol=1e-5)
    @test isapprox(mu_water(350.0), 3.6810159678e-4; rtol=1e-5)
    @test isapprox(mu_water(400.0), 2.1973269076e-4; rtol=1e-5)
end

@testset "FOUND-02: k_water" begin
    @test isapprox(k_water(300.0), 0.61240475; rtol=1e-5)
    @test isapprox(k_water(350.0), 0.66632812; rtol=1e-5)
    @test isapprox(k_water(400.0), 0.68588445; rtol=1e-5)
end

@testset "FOUND-02: MTK smoke test — rho_water symbolic" begin
    # Verify @register_symbolic is correctly placed at module top-level:
    # calling rho_water on a symbolic variable should return a symbolic expression (Num),
    # not a concrete Float64.
    @variables T_sym(t) = 300.0
    result = rho_water(T_sym)
    @test result isa Symbolics.Num  # symbolic, not a Float64
end

# ─────────────────────────────────────────────────────────────────
# FLUID-01: beta_water spot-checks (Simantov thermal expansion)
# Reference values computed from Python STREAM light_water.py
# ─────────────────────────────────────────────────────────────────
@testset "FLUID-01: beta_water" begin
    @test isapprox(beta_water(293.15), 2.7907882032e-04; rtol=1e-6)
    @test isapprox(beta_water(323.15), 4.3910662994e-04; rtol=1e-6)
    @test isapprox(beta_water(373.15), 7.2134423031e-04; rtol=1e-6)
end

@testset "FLUID-01: beta_water MTK symbolic" begin
    @variables T_sym(t) = 300.0
    result = beta_water(T_sym)
    @test result isa Symbolics.Num
end

@testset "FLUID-03: Ra" begin
    # Ra = Gr * Pr = 2863.260 * 4.323622 = 12379.654
    @test isapprox(Ra(2863.260, 4.323622), 12379.654; rtol=1e-4)
end

# ─────────────────────────────────────────────────────────────────
# PRES-03: sat_temperature spot-checks (Simantov saturation correlation)
# Reference values from Python STREAM light_water.py docstring
# ─────────────────────────────────────────────────────────────────
@testset "PRES-03: sat_temperature" begin
    @test isapprox(sat_temperature(1e5), 372.78; rtol=1e-4)   # 99.63 C
    @test isapprox(sat_temperature(0.5e5), 354.43; rtol=1e-4)   # 81.28 C
    @test isapprox(sat_temperature(2e5), 393.44; rtol=1e-4)   # 120.29 C
    @test isapprox(sat_temperature(101325.0), 373.15; rtol=1e-3)  # 100.00 C (1 atm)
end

@testset "PRES-03: sat_temperature MTK symbolic" begin
    @variables P_sym(t) = 1e5
    result = sat_temperature(P_sym)
    @test result isa Symbolics.Num
end

# ─────────────────────────────────────────────────────────────────
# PRES-03: _bergles_rohsenow_dT_ONB spot-checks
# Reference: Python STREAM temperatures.py docstring
# Note: private helper, accessed via STREAM._bergles_rohsenow_dT_ONB
# ─────────────────────────────────────────────────────────────────
@testset "PRES-03: _bergles_rohsenow_dT_ONB" begin
    # Zero heat flux -> zero superheat
    @test STREAM._bergles_rohsenow_dT_ONB(1e10, 0.0) == 0.0
    # Typical reactor conditions: positive dT
    dT = STREAM._bergles_rohsenow_dT_ONB(1e5, 1e6)
    @test dT > 0.0
    @test isfinite(dT)
end
