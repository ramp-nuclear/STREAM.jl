using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using STREAM
import STREAM: Channel

# ─────────────────────────────────────────────────────────────────
# SYS-01: build_loop assembles and compiles without error
# ─────────────────────────────────────────────────────────────────
@testset "SYS-01: build_loop compiles closed loop" begin
    ssys = build_loop()
    @test ssys isa ModelingToolkit.AbstractSystem
    # mtkcompile benchmark reported via @info (not asserted)
end

# ─────────────────────────────────────────────────────────────────
# SYS-02: steady_state_guess returns physically correct profile
# ─────────────────────────────────────────────────────────────────
@testset "SYS-02: steady_state_guess monotonically increasing" begin
    T = steady_state_guess(T_inlet=313.15, Q_wall=1e4, mdot_guess=0.1, n=10)
    @test length(T) == 10
    @test T[1] > 313.15       # first cell above inlet temperature
    @test all(diff(T) .> 0)   # monotonically increasing
end

# ─────────────────────────────────────────────────────────────────
# SOLV-01: solve_steady returns physical steady-state solution
# ─────────────────────────────────────────────────────────────────
@testset "SOLV-01: solve_steady returns physical solution" begin
    n = 10
    T_inlet = 313.15
    Q_wall = 1.0e4
    mdot_guess = 0.490  # physics-based estimate for 30 kPa pump, 0.01m pipe

    ssys = build_loop(T_inlet=T_inlet)
    T_guess = steady_state_guess(T_inlet=T_inlet, Q_wall=Q_wall, mdot_guess=mdot_guess, n=n)

    op = [ssys.ch.T[i] => T_guess[i] for i in 1:n]
    push!(op, ssys.ch.port_in.mdot => mdot_guess)

    sol = solve_steady(ssys, op)
    @test sol.retcode == ReturnCode.Success
    @test sol[ssys.ch.T_out] > T_inlet      # outlet > inlet (fluid heated)
    @test sol[ssys.ch.T_out] < 400.0        # physically reasonable (< 127°C)
    @test sol[ssys.ch.port_in.mdot] > 0     # positive mass flow
end

# ─────────────────────────────────────────────────────────────────
# SOLV-02: solve_transient returns time-series with T_outlet rising
# after T_wall step change (callable T_wall pattern)
# ─────────────────────────────────────────────────────────────────
@testset "SOLV-02: build_loop_transient compiles" begin
    ssys = build_loop_transient()
    @test ssys isa ModelingToolkit.AbstractSystem
    # No longer returns a tuple — just ssys
end

@testset "SOLV-02: solve_transient returns time-series (callable T_wall step)" begin
    n = 10
    T_inlet = 313.15
    Q_wall_0 = 1.0e4
    mdot_guess = 0.490

    # Step-change: T_wall jumps from 373.15 to 393.15 at t=10s via callable
    T_wall_0 = 373.15
    T_wall_final = 393.15
    t_step = 10.0
    T_wall_step = t -> t < t_step ? T_wall_0 : T_wall_final

    # Use a scalar-T_wall system for the steady-state solve (consistent ICs at T_wall_0)
    # then switch to the callable system for the transient.
    ssys_ss = build_loop_transient(T_inlet=T_inlet, T_wall_0=T_wall_0)
    ssys = build_loop_transient(T_inlet=T_inlet, T_wall_fn=T_wall_step)

    T_guess = steady_state_guess(
        T_inlet=T_inlet, Q_wall=Q_wall_0, mdot_guess=mdot_guess, n=n
    )

    op_guess = [ssys_ss.ch.T[i] => T_guess[i] for i in 1:n]
    push!(op_guess, ssys_ss.ch.port_in.mdot => mdot_guess)

    # Solve steady state on the scalar system for consistent ICs
    sol_ss = solve_steady(ssys_ss, op_guess)
    # Use Pair{Any,Any} so the callable parameter can be mixed with Float64 values
    op_ic = Pair{Any,Any}[ssys.ch.T[i] => sol_ss[ssys_ss.ch.T[i]] for i in 1:n]
    push!(op_ic, ssys.ch.port_in.mdot => sol_ss[ssys_ss.ch.port_in.mdot])
    # Include callable parameter in op for the transient system
    T_wall_sym = last(parameters(ssys))   # T_wall_callable is the last parameter
    push!(op_ic, T_wall_sym => T_wall_step)

    t_arr = range(0.0, 30.0, length=300)
    sol = solve_transient(ssys, op_ic, t_arr)
    @test sol.retcode == ReturnCode.Success
    @test length(sol.t) > 2
    T_ts = sol[ssys.ch.T_out, :]
    @test !any(isnan, T_ts)
    @test T_ts[end] > T_ts[1]   # T_outlet rises after T_wall step
end
