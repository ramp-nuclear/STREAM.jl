# Operating-point helpers (src/initial_conditions.jl).
#
# steady_state_guess and uniform. Driven through the `build_loop` example so the pairs
# uniform builds are checked against a real compiled system.

using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using STREAM
using STREAM.Components
using STREAM.Examples

@testset "Operating-point helpers" begin
    @testset "steady_state_guess monotonically increasing" begin
        T_guess = steady_state_guess(; T_inlet=40.0, Q_wall=1e4, ṁ_guess=0.1, n=10)
        @test length(T_guess) == 10
        @test T_guess[1] > 40.0        # first cell above inlet temperature
        @test all(diff(T_guess) .> 0)    # monotonically increasing
    end

    @testset "uniform gives every named variable one value" begin
        ssys = build_loop()
        op = uniform([ssys.ch], 40.0, :T, :dP, :nope)
        @test length(op) == 2
        @test isequal(first(op[1]), ssys.ch.T) && last(op[1]) == fill(40.0, 10)
        @test isequal(first(op[2]), ssys.ch.dP) && last(op[2]) == 40.0
        @test isempty(uniform([ssys.ch], 40.0, :nope))
        sol = solve_steady(ssys, [uniform([ssys.ch], 40.0, :T)...; ssys.ch.inlet.ṁ => 0.49])
        @test sol.retcode == ReturnCode.Success
    end
end
