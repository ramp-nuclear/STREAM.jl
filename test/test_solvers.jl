using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using DifferentialEquations
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
    Q_wall  = 1.0e4
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
# after T_wall step change
# ─────────────────────────────────────────────────────────────────
@testset "SOLV-02: build_loop_transient compiles" begin
    ssys, T_wall_sym = build_loop_transient()
    @test ssys isa ModelingToolkit.AbstractSystem
    @test T_wall_sym isa Symbolics.Num   # T_wall parameter symbol returned
end

@testset "SOLV-02: solve_transient returns time-series" begin
    n = 10
    T_inlet = 313.15
    Q_wall_0 = 1.0e4
    mdot_guess = 0.490  # rough guess; KINSOL is robust to this

    ssys, T_wall_sym = build_loop_transient(T_inlet=T_inlet)
    T_guess = steady_state_guess(T_inlet=T_inlet, Q_wall=Q_wall_0, mdot_guess=mdot_guess, n=n)

    op_guess = [ssys.ch.T[i] => T_guess[i] for i in 1:n]
    push!(op_guess, ssys.ch.port_in.mdot => mdot_guess)

    # Rodas5P+NoInit requires algebraically consistent ICs (pressure balance satisfied).
    # Run solve_steady on the transient system first to get a consistent starting point.
    sol_ss = solve_steady(ssys, op_guess)
    op_ic = [ssys.ch.T[i] => sol_ss[ssys.ch.T[i]] for i in 1:n]
    push!(op_ic, ssys.ch.port_in.mdot => sol_ss[ssys.ch.port_in.mdot])

    # Step T_wall from 373.15 K (100°C) to 393.15 K (120°C) at t=10s
    sol = solve_transient(ssys=ssys, T_wall_sym=T_wall_sym, op=op_ic, tspan=(0.0, 30.0),
                          T_wall_final=393.15, t_step=10.0)
    @test sol.retcode == ReturnCode.Success
    @test length(sol.t) > 2                            # multiple time points
    T_ts = sol[ssys.ch.T_out, :]
    @test !any(isnan, T_ts)                            # no NaN
    @test T_ts[end] > T_ts[1]                          # T_outlet rises after T_wall step
end
