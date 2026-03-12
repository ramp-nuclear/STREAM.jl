using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using STREAM
import STREAM: Pump, Friction, Gravity

# TDD RED: These tests should fail while stubs are in place
@testset "TDD RED: Pump, Friction, Gravity" begin
    @testset "Pump instantiates" begin
        @named pump = Pump(dP=1e4)
        @test pump isa ModelingToolkit.System
        @test_nowarn mtkcompile(pump)
    end

    @testset "Friction instantiates" begin
        @named fr = Friction(L=1.0, D=0.01, A=7.85e-5)
        @test fr isa ModelingToolkit.System
        sys_fr = mtkcompile(fr)
        obs = observed(sys_fr)
        println("Friction observed count: ", length(obs))
        @test length(obs) >= 2  # Re and f should appear
    end

    @testset "Gravity instantiates" begin
        @named grav = Gravity(H=3.0, A=7.85e-5)
        @test grav isa ModelingToolkit.System
        @test_nowarn mtkcompile(grav)
    end
end
