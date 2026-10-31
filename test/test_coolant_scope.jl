using Test
using ModelingToolkit
using STREAM
using STREAM.Substances
using STREAM.Components
using STREAM.Assemblies
using STREAM.Components: Channel  # explicit: Base.Channel also exists

const GEOM = Duct(0.6, Circular(0.01))
const OPENED = StateMachine(; initial_state=:OPEN)

# Every component whose coolant keyword is `liquid`, built with `kw` forwarded.
const READERS = (
    Channel=(; kw...) -> Channel(; name=:ch, n=4, geometry=GEOM, kw...),
    ChannelHeatFlux=(; kw...) -> ChannelHeatFlux(; name=:chf, n=4, geometry=GEOM, kw...),
    ChannelAndContacts=(; kw...) ->
        ChannelAndContacts(; name=:cac, n=4, geometry=GEOM, kw...),
    FrictionResistor=(; kw...) -> FrictionResistor(; name=:friction, geometry=GEOM, kw...),
    Gravity=(; kw...) -> Gravity(1.0; name=:rise, kw...),
    ResistorFromKnownPoint=(; kw...) ->
        ResistorFromKnownPoint(; name=:known, dp=-1.0e3, ṁ=0.5, T=40.0, kw...),
    LocalPressureDrop=(; kw...) ->
        LocalPressureDrop(; name=:loss, A1=1.0e-4, A2=2.0e-4, kw...),
    Flapper=(; kw...) -> Flapper(; name=:flap, machine=OPENED, kw...),
    Orifice=(; kw...) -> Orifice(; name=:hole, area=1.0e-4, cd=0.6, machine=OPENED, kw...),
    Tank=(; kw...) -> Tank(; name=:pool, area=1.0, L0=1.0, ports=(bottom=0.0,), kw...),
    HeatExchanger=(; kw...) -> HeatExchanger(40.0; UA=1.0e3, name=:hx, kw...),
)

@testset "$name takes the block's coolant" for (name, build) in pairs(READERS)
    @test isequal(equations(@coolant D2O build()), equations(build(; liquid=D2O)))
    @test !isequal(equations(@coolant D2O build()), equations(build()))
end

@testset "VolumetricFlowResistor's default density reads the block's coolant" begin
    scoped = @coolant D2O VolumetricFlowResistor(; name=:v, k=1.0)
    explicit = VolumetricFlowResistor(; name=:v, k=1.0, density=T -> ρ(D2O, T))
    @test isequal(equations(scoped), equations(explicit))
end

@testset "a two-stream exchanger takes the block's coolant on its primary side only" begin
    scoped = @coolant D2O HeatExchanger(; UA=1.0e3, name=:hx)
    explicit = HeatExchanger(; UA=1.0e3, primary_liquid=D2O, secondary_liquid=H2O, name=:hx)
    @test isequal(equations(scoped), equations(explicit))
end

@testset "an explicit liquid wins over the block" begin
    frozen = Liquid()
    @test isequal(equations(@coolant D2O Gravity(1.0; name=:rise, liquid=frozen)),
                  equations(Gravity(1.0; name=:rise, liquid=frozen)))
end

@testset "q_OFI_whittle_forgan reads the block's coolant" begin
    duct = Duct(0.6, Rectangular(0.0671, 0.0024))
    @test (@coolant D2O Thresholds.q_OFI_whittle_forgan(0.5, 100.0, 26.85, duct)) ==
          Thresholds.q_OFI_whittle_forgan(0.5, 100.0, 26.85, duct; liquid=D2O)
end

@testset "steady_state_guess reads the block's coolant" begin
    guess(; kw...) =
        steady_state_guess(; T_inlet=40.0, Q_wall=1.0e4, ṁ_guess=0.1, n=5, kw...)
    @test (@coolant D2O guess()) == guess(; liquid=D2O)
end

@testset "a nested block shadows the outer one until it ends" begin
    @coolant D2O begin
        @test (@coolant Liquid() coolant()) === Liquid()
        @test coolant() === D2O
    end
end

@testset "the coolant is back after a block that throws" begin
    @test_throws ErrorException @coolant D2O error("inside")
    @test coolant() === H2O
end

@testset "names assigned inside a block stay defined after it" begin
    @coolant D2O begin
        @named rise = Gravity(1.0)
    end
    @test isequal(equations(rise), equations(Gravity(1.0; name=:rise, liquid=D2O)))
end

@testset "the session coolant holds outside blocks" begin
    try
        @coolant D2O
        @test coolant() === D2O
    finally
        @coolant H2O
    end
    @test coolant() === H2O
end

@testset "a block wins over the session coolant" begin
    try
        @coolant D2O
        @test (@coolant H2O coolant()) === H2O
    finally
        @coolant H2O
    end
end

@testset "a channel keeps its coolant through compilation" begin
    @named pump = Pump(3.0e4)
    @named bc = HeatExchanger(40.0)
    @named ch = Channel(; n=3, geometry=GEOM, liquid=D2O)
    @named sys = assembly([inseries(pump, bc, ch, pump), pump.inlet.p ~ ATM], pump, bc, ch)
    ssys = mtkcompile(sys)
    @test coolant(ch) === D2O
    @test coolant(ssys.ch) === D2O
end

@testset "coolant(sys) refuses a system that is not a channel" begin
    @test_throws ArgumentError coolant(Pump(3.0e4; name=:pump))
end

@testset "a channel records the block's coolant, or its own explicit one" begin
    @test coolant(@coolant D2O Channel(; name=:scoped, n=3, geometry=GEOM)) === D2O
    kept = @coolant D2O Channel(; name=:kept, n=3, geometry=GEOM, liquid=H2O)
    @test coolant(kept) === H2O
end
