using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using STREAM
using STREAM.Substances

# Property values below are the reference values recorded in each correlation's docstring in
# src/substances/. They come from the ORNL/TM-12322 fits (Crabtree and Siman-Tov, 1993) that
# those functions implement, and are asserted here to 1e-12 so any edit to the arithmetic
# fails a test instead of drifting.
#
# Independent physical anchors, not tied to the fits: water boils at 100 °C at 1 atm, heavy
# water is about 10% denser than light water, and ρ(H2O) near room temperature sits close to
# 1000 kg/m^3.

@testset "property calls are type stable" begin
    # The scalar (Float64) path must return a concrete Float64. Components trace symbolically
    # through these same bodies, so a type regression here shows up as a widened equation later.
    @test (@inferred ρ(H2O, 50.0)) isa Float64
    @test (@inferred cₚ(H2O, 50.0)) isa Float64
    @test (@inferred μ(H2O, 50.0)) isa Float64
    @test (@inferred κ(H2O, 50.0)) isa Float64
    @test (@inferred β(H2O, 20.0)) isa Float64
    @test (@inferred Tsat(H2O, 1e5)) isa Float64
end

@testset "aliases name the same functions" begin
    @test ρ === density
    @test ρᵥ === vapor_density
    @test cₚ === specific_heat
    @test μ === viscosity
    @test κ === conductivity
    @test σ === surface_tension
    @test hfg === latent_heat
    @test β === thermal_expansion
    @test Tsat === sat_temperature
end

@testset "two-argument form fills the pressure with ATM" begin
    for T in (20.0, 50.0, 100.0)
        @test ρ(H2O, T) == ρ(H2O, T, ATM)
        @test cₚ(H2O, T) == cₚ(H2O, T, ATM)
    end
    # Tsat's short form takes the pressure, not a temperature.
    @test Tsat(H2O, 1e5) == sat_temperature(H2O, 0.0, 1e5)
end

@testset "light water matches its documented reference values" begin
    @test ρ(H2O, 50.0) ≈ 987.27431208 rtol = 1e-12
    @test ρ(H2O, 100.0) ≈ 959.13959928 rtol = 1e-12

    @test β(H2O, 20.0) ≈ 279.0788203166585e-6 rtol = 1e-12
    @test β(H2O, 100.0) ≈ 721.3442303074213e-6 rtol = 1e-12

    @test cₚ(H2O, 8.0) ≈ 4179.863745234987 rtol = 1e-12
    @test cₚ(H2O, 50.0) ≈ 4181.4264285644285 rtol = 1e-12
    @test cₚ(H2O, 8.0) == cₚ(H2O, -8.0)          # the fit is even in temperature

    @test μ(H2O, 90.0) ≈ 3.1444961652895464e-4 rtol = 1e-12
    @test κ(H2O, 50.0) ≈ 0.6419141378687501 rtol = 1e-12

    @test Tsat(H2O, 1e5) ≈ 99.63072810857243 rtol = 1e-12
    @test Tsat(H2O, 0.5e5) ≈ 81.28047959788387 rtol = 1e-12
    @test Tsat(H2O, 2e5) ≈ 120.29401952865119 rtol = 1e-12

    @test hfg(H2O, 50.0) ≈ 2382729.243923866 rtol = 1e-12
    @test hfg(H2O, 100.0) ≈ 2257149.1343506747 rtol = 1e-12

    @test σ(H2O, 50.0) ≈ 0.06794675477982745 rtol = 1e-12
    @test σ(H2O, 100.0) ≈ 0.05891594230703328 rtol = 1e-12

    @test ρᵥ(H2O, 50.0) ≈ 0.08307666133931553 rtol = 1e-12
    @test ρᵥ(H2O, 100.0) ≈ 0.5978051373615001 rtol = 1e-12
end

@testset "heavy water matches its documented reference values" begin
    @test ρ(D2O, 50.0) ≈ 1095.7419670000002 rtol = 1e-12
    @test ρ(D2O, 100.0) ≈ 1063.4244970000002 rtol = 1e-12

    @test β(D2O, 20.0) ≈ 312.34463951465654e-6 rtol = 1e-12
    @test β(D2O, 100.0) ≈ 736.0686181371651e-6 rtol = 1e-12

    @test cₚ(D2O, 50.0) ≈ 4220.658975628751 rtol = 1e-12
    @test cₚ(D2O, 100.0) ≈ 4162.210117465748 rtol = 1e-12

    @test μ(D2O, 50.0) ≈ 6.441125212510078e-4 rtol = 1e-12
    @test μ(D2O, 100.0) ≈ 3.301433604774831e-4 rtol = 1e-12

    @test κ(D2O, 50.0) ≈ 0.6167873183429435 rtol = 1e-12
    @test κ(D2O, 100.0) ≈ 0.6357784886396809 rtol = 1e-12

    @test Tsat(D2O, 1e5) ≈ 100.98975482398993 rtol = 1e-12
    @test Tsat(D2O, 0.5e5) ≈ 82.7830309880722 rtol = 1e-12
    @test Tsat(D2O, 2e5) ≈ 121.5058319422803 rtol = 1e-12

    @test hfg(D2O, 50.0) ≈ 2199499.183881408 rtol = 1e-12
    @test hfg(D2O, 100.0) ≈ 2076983.0825663893 rtol = 1e-12

    @test σ(D2O, 50.0) ≈ 0.06809951822968323 rtol = 1e-12
    @test σ(D2O, 100.0) ≈ 0.059250184550697166 rtol = 1e-12

    @test ρᵥ(D2O, 50.0) ≈ 0.08342446145018677 rtol = 1e-12
    @test ρᵥ(D2O, 100.0) ≈ 0.6309356177290303 rtol = 1e-12
end

@testset "physical anchors independent of the fits" begin
    # Water boils at 100 °C at 1 atm.
    @test isapprox(Tsat(H2O, ATM), 100.0; rtol=1e-3)
    # Liquid water near room temperature is close to 1000 kg/m^3.
    @test isapprox(ρ(H2O, 20.0), 1000.0; rtol=2e-2)
    # Heavy water is roughly 10% denser and conducts heat less well.
    for T in (20.0, 50.0, 100.0)
        @test 1.09 < ρ(D2O, T) / ρ(H2O, T) < 1.12
        @test κ(D2O, T) < κ(H2O, T)
    end
    # And it boils a little above light water.
    @test Tsat(D2O, ATM) > Tsat(H2O, ATM)
    @test isapprox(Tsat(D2O, ATM), 101.4; atol=0.5)
end

@testset "properties trace symbolically" begin
    # Nothing is @register_symbolic, so a symbolic argument has to come back as an expression
    # rather than dispatching to a numeric method or erroring.
    @variables T_sym(t) = 50.0
    @variables P_sym(t) = 1e5
    @test ρ(H2O, T_sym) isa Symbolics.Num
    @test β(H2O, T_sym) isa Symbolics.Num
    @test Tsat(H2O, P_sym) isa Symbolics.Num
    @test ρ(D2O, T_sym) isa Symbolics.Num
end

@testset "every liquid answers every property" begin
    for liquid in (H2O, D2O, Liquid())
        for f in (ρ, ρᵥ, cₚ, μ, κ, σ, hfg, β)
            @test f(liquid, 50.0) isa Real
        end
        @test Tsat(liquid, ATM) isa Real
    end
end

@testset "Liquid holds fixed properties" begin
    mock = Liquid()   # the all-ones mock used by channel tests
    for T in (1.0, 50.0, 326.85)   # temperature-independent
        @test ρ(mock, T) == 1.0
        @test cₚ(mock, T) == 1.0
        @test μ(mock, T) == 1.0
        @test κ(mock, T) == 1.0
        @test β(mock, T) == 1.0
    end
    l = Liquid(; ρ=1000.0, cₚ=4200.0, μ=1.0e-3, κ=0.6, β=2.0e-4)
    @test ρ(l, 46.85) == 1000.0
    @test cₚ(l, 46.85) == 4200.0
    @test μ(l, 46.85) == 1.0e-3
    @test κ(l, 46.85) == 0.6
    @test β(l, 46.85) == 2.0e-4
    # A Liquid is a coolant in its own right, so it can stand in for one.
    @test l isa AbstractLiquid
end

@testset "calling a liquid freezes it at a state point" begin
    snap = H2O(50.0)
    @test snap isa Liquid
    @test snap isa AbstractLiquid
    @test snap.ρ == ρ(H2O, 50.0)
    @test snap.cₚ == cₚ(H2O, 50.0)
    @test snap.κ == κ(H2O, 50.0)
    @test snap.Tsat == Tsat(H2O, 50.0, ATM)
    # The snapshot then answers property queries with the frozen values.
    @test ρ(snap, 999.0) == ρ(H2O, 50.0)

    # Array arguments give a Liquid whose fields are arrays.
    temps = [20.0, 50.0, 100.0]
    arr = H2O(temps)
    @test arr.ρ == ρ.(H2O, temps)
    @test length(arr.cₚ) == 3
end

@testset "Ra from real water properties" begin
    # Feed Gr and Pr the actual water-property functions and check Ra behaves physically:
    # positive under a heated wall, in range for water, and sign-flipping when the wall cools.
    # A 10 K wall superheat over a 5 mm channel:
    using STREAM: Gr, Pr
    T = 46.85          # bulk [°C]
    T_wall = 56.85     # wall [°C], hotter than bulk
    L = 5.0e-3         # characteristic length [m]
    g = 9.81           # [m/s^2]
    rho = ρ(H2O, T)
    mu = μ(H2O, T)
    beta = β(H2O, T)
    cp = cₚ(H2O, T)
    kk = κ(H2O, T)
    Gr_val = Gr(rho, mu, beta, T_wall, T, L, g)
    Pr_val = Pr(cp, mu, kk)
    # Heated wall (T_wall > T) drives buoyancy, so Ra is positive; water near 47 °C has Pr a few.
    @test Ra(Gr_val, Pr_val) > 0.0
    @test 1.0 < Pr_val < 10.0
    # Flip the wall below the bulk: buoyancy reverses, so Ra changes sign.
    Gr_cooled = Gr(rho, mu, beta, T - 10.0, T, L, g)
    @test Ra(Gr_cooled, Pr_val) < 0.0
end

@testset "_bergles_rohsenow_dT_ONB" begin
    # Zero heat flux -> zero superheat
    @test STREAM.HTC._bergles_rohsenow_dT_ONB(1e10, 0.0) == 0.0
    # Typical reactor conditions: positive dT
    dT = STREAM.HTC._bergles_rohsenow_dT_ONB(1e5, 1e6)
    @test dT > 0.0
    @test isfinite(dT)
end
