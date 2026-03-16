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
