# test_transient_tdd.jl -- TDD tests for transient solver (Phase 3, Plan 02)
# RED phase: these tests fail until solve_transient is implemented.

using Test
using ModelingToolkit
using STREAM
import STREAM: Channel, Pump, Friction

@testset "SOLV-02: build_loop_transient returns (ssys, Q_wall_sym)" begin
    result = STREAM.build_loop_transient()
    @test result isa Tuple
    ssys, Q_sym = result
    @test ssys isa ModelingToolkit.AbstractSystem
end

@testset "SOLV-02: build_loop_transient exported" begin
    @test isdefined(STREAM, :build_loop_transient)
end

@testset "SOLV-02: solve_transient returns ODESolution" begin
    ssys, Q_sym = STREAM.build_loop_transient()
    n = 10
    T_inlet = 313.15
    Q_wall_0 = 1.0e4
    mdot_guess = 0.490

    T_guess = STREAM.steady_state_guess(T_inlet=T_inlet, Q_wall=Q_wall_0, mdot_guess=mdot_guess, n=n)
    Re_guess = abs(mdot_guess) * 0.01 / (7.85e-5 * STREAM.mu_water(T_inlet))

    op = [ssys.ch.T[i] => T_guess[i] for i in 1:n]
    push!(op, ssys.fr.port_in.mdot => mdot_guess)
    push!(op, ssys.fr.Re => Re_guess)

    # T_wall_final: raise wall temperature to increase heat input (step change)
    sol = STREAM.solve_transient(ssys, Q_sym, op, (0.0, 30.0);
                                 T_wall_final=393.15, t_step=10.0)
    @test length(sol.t) > 2
end

@testset "SOLV-02: solve_transient no NaN/Inf in T_outlet" begin
    ssys, Q_sym = STREAM.build_loop_transient()
    n = 10
    T_inlet = 313.15
    Q_wall_0 = 1.0e4
    mdot_guess = 0.490

    T_guess = STREAM.steady_state_guess(T_inlet=T_inlet, Q_wall=Q_wall_0, mdot_guess=mdot_guess, n=n)
    Re_guess = abs(mdot_guess) * 0.01 / (7.85e-5 * STREAM.mu_water(T_inlet))

    op = [ssys.ch.T[i] => T_guess[i] for i in 1:n]
    push!(op, ssys.fr.port_in.mdot => mdot_guess)
    push!(op, ssys.fr.Re => Re_guess)

    sol = STREAM.solve_transient(ssys, Q_sym, op, (0.0, 30.0);
                                 T_wall_final=393.15, t_step=10.0)
    T_ts = sol[ssys.ch.T_out, :]
    @test !any(isnan, T_ts)
    @test !any(isinf, T_ts)
end
