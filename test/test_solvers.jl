# Solver API tests (src/solvers.jl).
#
# steady_state_guess and the solve_steady / solve_transient wrappers. Driven through the
# `build_loop` example so the wrappers are exercised on a real compiled system.

using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using OrdinaryDiffEq: ReturnCode
using STREAM

@testset "Solver wrappers" begin
    @testset "steady_state_guess monotonically increasing" begin
        T_guess = steady_state_guess(T_inlet=313.15, Q_wall=1e4, mdot_guess=0.1, n=10)
        @test length(T_guess) == 10
        @test T_guess[1] > 313.15        # first cell above inlet temperature
        @test all(diff(T_guess) .> 0)    # monotonically increasing
    end

    @testset "solve_steady returns physical solution" begin
        n = 10
        T_inlet = 313.15
        Q_wall = 1.0e4
        mdot_guess = 0.490  # physics-based estimate for 30 kPa pump, 0.01m pipe

        ssys = build_loop(T_inlet=T_inlet)
        T_guess = steady_state_guess(
            T_inlet=T_inlet, Q_wall=Q_wall, mdot_guess=mdot_guess, n=n
        )

        op = [ssys.ch.T[i] => T_guess[i] for i in 1:n]
        push!(op, ssys.ch.port_in.mdot => mdot_guess)

        sol = solve_steady(ssys, op)
        @test sol.retcode == ReturnCode.Success
        @test sol[ssys.ch.T_out] > T_inlet      # outlet > inlet (fluid heated)
        @test sol[ssys.ch.T_out] < 400.0        # physically reasonable (< 127°C)
        @test sol[ssys.ch.port_in.mdot] > 0     # positive mass flow
    end

    @testset "solve_transient returns time-series (callable T_wall step)" begin
        # Step-change: T_wall jumps from 373.15 to 393.15 at t=10s via callable.
        n = 10
        T_inlet = 313.15
        Q_wall_0 = 1.0e4
        mdot_guess = 0.490

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

        sol_ss = solve_steady(ssys_ss, op_guess)
        op_ic = Pair{Any,Any}[ssys.ch.T[i] => sol_ss[ssys_ss.ch.T[i]] for i in 1:n]
        push!(op_ic, ssys.ch.port_in.mdot => sol_ss[ssys_ss.ch.port_in.mdot])
        # Include callable parameter in op for the transient system.
        T_wall_sym = last(parameters(ssys))   # T_wall_callable is the last parameter
        push!(op_ic, T_wall_sym => T_wall_step)

        t_arr = range(0.0, 30.0, length=300)
        sol = solve_transient(ssys, op_ic, t_arr)
        @test sol.retcode == ReturnCode.Success
        @test length(sol.t) > 2
        T_ts = sol[ssys.ch.T_out, :]
        @test !any(isnan, T_ts)
        @test T_ts[end] > T_ts[1]   # T_outlet rises after T_wall step

        # Magnitude check: the outlet must approach the NEW steady state set by T_wall_final,
        # not just rise. Solve the same loop pinned at T_wall_final to get the target outlet,
        # and the loop pinned at T_wall_0 to confirm the pre-step outlet. The transient runs
        # 20s after the t=10s step; that is many flow-through + thermal times for this 10-cell
        # loop, so the end value should sit essentially on the new steady outlet.
        ssys_final = build_loop_transient(T_inlet=T_inlet, T_wall_0=T_wall_final)
        op_final = [ssys_final.ch.T[i] => T_guess[i] for i in 1:n]
        push!(op_final, ssys_final.ch.port_in.mdot => mdot_guess)
        sol_final = solve_steady(ssys_final, op_final)
        @test sol_final.retcode == ReturnCode.Success
        T_out_final_steady = sol_final[ssys_final.ch.T_out]

        T_out_initial_steady = sol_ss[ssys_ss.ch.T_out]   # steady outlet at T_wall_0
        # Sanity: raising the wall by 20 K must raise the steady outlet (positive step).
        @test T_out_final_steady > T_out_initial_steady

        # Pre-step outlet sits on the T_wall_0 steady value: the callable holds T_wall_0 for
        # t<10s, so the loop stays at its IC there. Sample by interpolation at t=5s (well
        # before the t=10s step) rather than the first saved point, whose observed T_out
        # reads a placeholder. rtol=2e-3 covers integrator interpolation only.
        T_out_pre_step = sol(5.0; idxs=ssys.ch.T_out)
        @test isapprox(T_out_pre_step, T_out_initial_steady; rtol=2e-3)

        # Settling value: the transient endpoint approaches the T_wall_final steady outlet.
        # rtol=2e-3 (a few mK on a ~330 K outlet) reflects that 20s of relaxation leaves only
        # a small residual short of the asymptote for this fast-settling loop; it is far
        # tighter than the 20 K step size, so a wrong settling magnitude would fail.
        @test isapprox(T_ts[end], T_out_final_steady; rtol=2e-3)
    end

    @testset "solve_transient from a solved state" begin
        # Minimal inertia coastdown: a pump holds a steady flow, then shuts off and the flow
        # coasts as mdot0·exp(-(r/L)·t). Exercises the solution overload of solve_transient: start
        # from a solved state, apply an override. The trajectory matching the analytic decay is the
        # check that the full state was transplanted (an incomplete IC would not coast correctly).
        r = 3.0
        L = 5.0
        mdot0 = 1.0
        @named pump = Pump(r * mdot0)
        @named ine = Inertia(L)
        @named res = Resistor(r)
        @named hx = HeatExchanger(300.0)
        conns = [
            connect(pump.port_out, ine.port_in),
            connect(ine.port_out, res.port_in),
            connect(res.port_out, hx.port_in),
            connect(hx.port_out, pump.port_in),
            pump.port_in.P ~ 1.0e5,
        ]
        @named sys = compose(System(conns, t; name=:coast), pump, ine, res, hx)
        ssys = mtkcompile(sys)
        sol_ss = solve_steady(ssys, [ssys.ine.port_in.mdot => mdot0])
        @test sol_ss.retcode == ReturnCode.Success

        t_arr = range(0.0, 1.0; length=5)
        sol = solve_transient(ssys, sol_ss, t_arr; overrides=[ssys.pump.dP_pump => 0.0])
        @test sol.retcode == ReturnCode.Success
        mdot = sol[ssys.ine.port_in.mdot, :]
        @test isapprox(mdot[1], mdot0; rtol=1e-4)                       # starts at the solved steady
        @test all(isapprox(mdot[i], mdot0 * exp(-(r / L) * tt); rtol=1e-3) for (i, tt) in enumerate(t_arr))
    end
end
