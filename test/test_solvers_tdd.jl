# test_solvers_tdd.jl -- TDD tests for src/solvers.jl (Phase 3, Plan 01)
# RED phase: these tests should fail before solvers.jl is created

using Test
using STREAM
import STREAM: Channel, Pump, Friction  # resolve Base.Channel ambiguity

@testset "SYS-01: steady_state_guess returns physically correct profile" begin
    T = STREAM.steady_state_guess(T_inlet=313.15, Q_wall=1e4, mdot_guess=0.1, n=10)
    @test length(T) == 10
    @test T[1] > 313.15      # first cell above inlet
    @test all(diff(T) .> 0)  # monotonically increasing
end

@testset "SYS-01: build_loop compiles without error" begin
    ssys = STREAM.build_loop()
    @test ssys isa ModelingToolkit.AbstractSystem
end

@testset "SYS-02: STREAM exports solve_steady" begin
    @test isdefined(STREAM, :solve_steady)
end

@testset "SYS-02: STREAM exports steady_state_guess" begin
    @test isdefined(STREAM, :steady_state_guess)
end

@testset "SYS-02: STREAM exports build_loop" begin
    @test isdefined(STREAM, :build_loop)
end

@testset "SYS-02: STREAM exports solve_transient stub" begin
    @test isdefined(STREAM, :solve_transient)
end
