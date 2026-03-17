using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using Symbolics
using STREAM

# ─────────────────────────────────────────────────────────────────
# FOUND-02: Fluid property spot-checks (Simantov correlations)
# Reference values computed from Python STREAM light_water.py
# Tolerance: rtol=1e-6 (deterministic polynomial; any larger diff = unit error)
# ─────────────────────────────────────────────────────────────────
@testset "FOUND-02: rho_water" begin
    @test isapprox(rho_water(300.0), 995.925708;  rtol=1e-5)
    @test isapprox(rho_water(350.0), 973.771824;  rtol=1e-5)
    @test isapprox(rho_water(400.0), 938.700383;  rtol=1e-5)
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

# ─────────────────────────────────────────────────────────────────
# FLUID-02/03: Gr and Ra dimensionless number utilities
# Reference: MTR-scale test point from RESEARCH.md
# T_bulk=40C, T_wall=60C, S=0.00254m, Lh=0.6m
# ─────────────────────────────────────────────────────────────────
@testset "FLUID-02: Gr" begin
    # Reference values from RESEARCH.md:
    # beta=3.851798e-04, g=9.81, dT=20, L=0.00254, nu=6.5766e-07
    # Gr = beta * g * dT * L^3 / nu^2 = 2863.260
    @test isapprox(Gr(3.851798e-04, 9.81, 20.0, 0.00254, 6.5766e-07), 2863.260; rtol=1e-4)
end

@testset "FLUID-03: Ra" begin
    # Ra = Gr * Pr = 2863.260 * 4.323622 = 12379.654
    @test isapprox(Ra(2863.260, 4.323622), 12379.654; rtol=1e-4)
end
