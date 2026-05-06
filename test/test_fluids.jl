using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using STREAM

zabs = 273.15
# ─────────────────────────────────────────────────────────────────
# FOUND-02: Fluid property spot-checks (Simantov correlations)
# Reference values computed from Python STREAM light_water.py
# Tolerance: rtol=1e-6 (deterministic polynomial; any larger diff = unit error)
# ─────────────────────────────────────────────────────────────────
@testset "FOUND-02: ρ H2O" begin
    r(T) = ρ(H2O, T - zabs)
    @test isapprox(r(300.0), 995.925708; rtol=1e-5)
    @test isapprox(r(350.0), 973.771824; rtol=1e-5)
    @test isapprox(r(400.0), 938.700383; rtol=1e-5)
end

@testset "FOUND-02: cₚ H2O" begin
    c(T) = cₚ(H2O, T - zabs)
    @test isapprox(c(300.0), 4177.781138; rtol=1e-5)
    @test isapprox(c(350.0), 4195.561824; rtol=1e-5)
    @test isapprox(c(400.0), 4258.577497; rtol=1e-5)
end

@testset "FOUND-02: μ H2O" begin
    m(T) = μ(H2O, T - zabs)
    @test isapprox(m(300.0), 8.5524859163e-4; rtol=1e-5)
    @test isapprox(m(350.0), 3.6810159678e-4; rtol=1e-5)
    @test isapprox(m(400.0), 2.1973269076e-4; rtol=1e-5)
end

@testset "FOUND-02: k H2O" begin
    k_(T) = k(H2O, T - zabs)
    @test isapprox(k_(300.0), 0.61240475; rtol=1e-5)
    @test isapprox(k_(350.0), 0.66632812; rtol=1e-5)
    @test isapprox(k_(400.0), 0.68588445; rtol=1e-5)
end

@testset "FOUND-02: MTK smoke test — ρ symbolic" begin
    # Verify @register_symbolic is correctly placed at module top-level:
    # calling ρ on a symbolic variable should return a symbolic expression (Num),
    # not a concrete Float64.
    @variables T_sym(t) = 300.0
    result = ρ(H2O, T_sym)
    @test result isa Symbolics.Num  # symbolic, not a Float64
end

# ─────────────────────────────────────────────────────────────────
# FLUID-01: β spot-checks (Simantov thermal expansion)
# Reference values computed from Python STREAM light_water.py
# ─────────────────────────────────────────────────────────────────
@testset "FLUID-01: β H2O" begin
    b(T) = β(H2O, T - zabs)
    @test isapprox(b(293.15), 2.7907882032e-04; rtol=1e-6)
    @test isapprox(b(323.15), 4.3910662994e-04; rtol=1e-6)
    @test isapprox(b(373.15), 7.2134423031e-04; rtol=1e-6)
end

@testset "FLUID-01: β MTK symbolic" begin
    @variables T_sym(t) = 300.0
    result = β(H2O, T_sym)
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

# ─────────────────────────────────────────────────────────────────
# PRES-03: sat_temperature spot-checks (Simantov saturation correlation)
# Reference values from Python STREAM light_water.py docstring
# ─────────────────────────────────────────────────────────────────
@testset "PRES-03: Tsat" begin
    Ts(p) = Tsat(H2O, p) + zabs
    @test isapprox(Ts(1e5), 372.78; rtol=1e-4)   # 99.63 C
    @test isapprox(Ts(0.5e5), 354.43; rtol=1e-4)   # 81.28 C
    @test isapprox(Ts(2e5), 393.44; rtol=1e-4)   # 120.29 C
    @test isapprox(Ts(101325.0), 373.15; rtol=1e-3)  # 100.00 C (1 atm)
end

@testset "PRES-03: Tsat MTK symbolic" begin
    @variables P_sym(t) = 1e5
    result = Tsat(H2O, P_sym)
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
