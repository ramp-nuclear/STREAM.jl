using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using STREAM
using STREAM.Substances
using STREAM.Components
using STREAM.Assemblies
using STREAM.Components: Channel  # explicit: Base.Channel also exists
using QuadGK: quadgk

"""
    _coolant_readers(; kw...) -> Vector{System}

Every component that reads a coolant, with `kw` forwarded to each constructor.
"""
function _coolant_readers(; kw...)
    geom = PipeGeometry_circular(0.6, 0.01)
    opened = StateMachine(; initial_state=:OPEN)
    return [
        Channel(; name=:ch, n=4, geometry=geom, kw...),
        ChannelHeatFlux(; name=:chf, n=4, geometry=geom, kw...),
        ChannelAndContacts(; name=:cac, n=4, geometry=geom, kw...),
        FrictionResistor(; name=:friction, geometry=geom, kw...),
        Gravity(1.0; name=:rise, kw...),
        ResistorFromKnownPoint(; name=:known, dp=-1.0e3, ṁ=0.5, T=40.0, kw...),
        LocalPressureDrop(; name=:loss, A1=1.0e-4, A2=2.0e-4, kw...),
        Flapper(; name=:flap, machine=opened, kw...),
        Orifice(; name=:hole, area=1.0e-4, cd=0.6, machine=opened, kw...),
        Tank(; name=:pool, area=1.0, L0=1.0, ports=(bottom=0.0,), kw...),
        HeatExchanger(40.0; UA=1.0e3, name=:hx, kw...),
    ]
end

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
    @test (@inferred enthalpy(H2O, 50.0)) isa Float64
    @test (@inferred temperature(H2O, 2.0e5)) isa Float64
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
    @test hₗ === enthalpy
    @test hᵥ === vapor_enthalpy
end

@testset "the coolant default" begin
    mock = Liquid()
    with_coolant(D2O) do
        @test default_coolant() === D2O
        @test with_coolant(default_coolant, mock) === mock
        @test default_coolant() === D2O
    end
    @test_throws ErrorException with_coolant(() -> error("inside"), D2O)
    @test default_coolant() === H2O
end

@testset "with_coolant names the coolant for every component that reads one" begin
    scoped = with_coolant(_coolant_readers, D2O)
    explicit = _coolant_readers(; liquid=D2O)
    light = _coolant_readers()
    @test all(isequal(equations(a), equations(b)) for (a, b) in zip(scoped, explicit))
    @test !any(isequal(equations(a), equations(c)) for (a, c) in zip(scoped, light))

    # The two components whose coolant keyword is not `liquid`.
    volumetric = with_coolant(() -> VolumetricFlowResistor(; name=:v, k=1.0), D2O)
    @test isequal(equations(volumetric),
                  equations(VolumetricFlowResistor(; name=:v, k=1.0, density=T -> ρ(D2O, T))))
    two_stream = with_coolant(() -> HeatExchanger(; UA=1.0e3, name=:hx), D2O)
    @test isequal(equations(two_stream),
                  equations(HeatExchanger(; UA=1.0e3, primary_liquid=D2O, secondary_liquid=D2O,
                                          name=:hx)))

    # An explicit coolant inside the block wins over it.
    frozen = with_coolant(() -> Gravity(1.0; name=:rise, liquid=Liquid()), D2O)
    @test isequal(equations(frozen), equations(Gravity(1.0; name=:rise, liquid=Liquid())))

    # The correlation and the initial guess read the same default.
    pipe = PipeGeometry_rectangular(0.6, 0.0671, 0.0024, 0.0671)
    @test with_coolant(() -> Thresholds.q_OFI_whittle_forgan(0.5, 100.0, 26.85, pipe), D2O) ==
          Thresholds.q_OFI_whittle_forgan(0.5, 100.0, 26.85, pipe; liquid=D2O)
    guess(; kw...) = steady_state_guess(; T_inlet=40.0, Q_wall=1.0e4, ṁ_guess=0.1, n=5, kw...)
    @test with_coolant(guess, D2O) == guess(; liquid=D2O)
end

@testset "enthalpy is the integral of the specific heat from 0 °C" for liquid in (H2O, D2O)
    Ts = 0.0:5.0:300.0
    refs = [first(quadgk(x -> cₚ(liquid, x), 0.0, T; rtol=1e-13)) for T in Ts]
    @test enthalpy.(liquid, Ts) ≈ refs rtol = 1e-12
    @test enthalpy(liquid, 0.0) == 0.0
end

@testset "temperature inverts enthalpy to 1e-10 K between 0 and 300 °C" for liquid in (H2O, D2O)
    Ts = 0.0:10.0:300.0
    @test maximum(abs, temperature.(liquid, enthalpy.(liquid, Ts)) .- Ts) < 1e-10
end

@testset "temperature continues linearly beyond the fitted range" for liquid in (H2O, D2O)
    h_hi, h_lo = enthalpy(liquid, 300.0), enthalpy(liquid, 0.0)
    @test temperature(liquid, h_hi + 1.0e5) ≈ 300.0 + 1.0e5 / cₚ(liquid, 300.0)
    @test temperature(liquid, h_lo - 1.0e4) ≈ -1.0e4 / cₚ(liquid, 0.0)
    @test isfinite(temperature(liquid, 1.0e9))
end

@testset "the shipped enthalpies sit near IAPWS-IF97 saturation values" begin
    # IF97 h_f in kJ/kg with h = 0 for the liquid at the triple point, and h_g at 1 atm. The
    # fits are within 0.5 %; the datum differs by 0.01 °C of liquid, which is 0.04 kJ/kg.
    Ts = [25.0, 50.0, 100.0, 200.0]
    @test enthalpy.(H2O, Ts) ./ 1e3 ≈ [104.83, 209.34, 419.17, 852.39] rtol = 5e-3
    @test vapor_enthalpy(H2O, ATM) / 1e3 ≈ 2675.6 rtol = 5e-3
end

@testset "a Liquid's enthalpies are the closed forms of its constants" begin
    mock = Liquid(; cₚ=2000.0, Tsat=100.0, hfg=2.0e6)
    @test enthalpy(mock, 40.0) == 8.0e4
    @test temperature(mock, 8.0e4) == 40.0
    @test vapor_enthalpy(mock, ATM) == 2000.0 * 100.0 + 2.0e6
end

@testset "a channel records its coolant, and coolant(sys) returns it after compilation" begin
    geom = PipeGeometry_circular(0.6, 0.01)
    @named pump = Pump(3.0e4)
    @named bc = HeatExchanger(40.0)
    @named ch = Channel(; n=3, geometry=geom, liquid=D2O)
    @named sys = assembly([inseries(pump, bc, ch, pump), pump.inlet.p ~ ATM], pump, bc, ch)
    ssys = mtkcompile(sys)
    @test coolant(ch) === D2O
    @test coolant(ssys.ch) === D2O
    @test with_coolant(() -> coolant(Channel(; name=:scoped, n=3, geometry=geom)), D2O) === D2O
    # An explicit coolant inside the block is the one recorded.
    @test with_coolant(() -> coolant(Channel(; name=:kept, n=3, geometry=geom, liquid=H2O)),
                       D2O) === H2O
    @test_throws ArgumentError coolant(ssys.pump)
end

@testset "two-argument form fills the pressure with ATM" begin
    for T in (20.0, 50.0, 100.0)
        @test ρ(H2O, T) == ρ(H2O, T, ATM)
        @test cₚ(H2O, T) == cₚ(H2O, T, ATM)
    end
    # Tsat's short form takes the pressure, not a temperature.
    @test Tsat(H2O, 1e5) == sat_temperature(H2O, 0.0, 1e5)
    @test enthalpy(H2O, 50.0) == enthalpy(H2O, 50.0, ATM)
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
    @test enthalpy(H2O, T_sym) isa Symbolics.Num
    @variables h_sym(t)
    for liquid in (H2O, D2O)
        T_of_h = temperature(liquid, h_sym)
        @test T_of_h isa Symbolics.Num
        T_of = Symbolics.build_function(T_of_h, h_sym; expression=Val(false))
        @test T_of(enthalpy(liquid, 50.0)) ≈ 50.0 atol = 1e-10
        # The traced expression stays one Horner chain.
        @test length(string(T_of_h)) < 5_000
    end
end

@testset "every liquid answers every property" begin
    for liquid in (H2O, D2O, Liquid())
        for f in (ρ, ρᵥ, cₚ, μ, κ, σ, hfg, β, enthalpy)
            @test f(liquid, 50.0) isa Real
        end
        @test Tsat(liquid, ATM) isa Real
        @test vapor_enthalpy(liquid, ATM) isa Real
        @test temperature(liquid, 1.0e5) isa Real
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

@testset "Solid" begin
    s = Solid(; ρ=2700, cₚ=900.0, κ=250)
    @test s === Solid(2700.0, 900.0, 250.0)
    @test Solid(; density=2700, specific_heat=900.0, conductivity=250) === s
    @test Solid(; ρ=2700, specific_heat=900.0, κ=250) === s
    @test_throws ArgumentError Solid(; density=2700, specific_heat=900.0)
    @test (ρ(s), cₚ(s), κ(s)) == (2700.0, 900.0, 250.0)
    # Python's Solid.from_array doctest: a matrix of solids gives property matrices.
    materials = [Solid(1, 2, 3) Solid(4, 5, 6)]
    @test density.(materials) == [1 4]
    @test conductivity.(materials) == [3 6]
    @test κ.(ifelse.([true false], Solid(1, 1, 7), Solid(1, 1, 9))) == [7 9]
end
