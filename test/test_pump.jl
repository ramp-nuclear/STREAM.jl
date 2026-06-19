using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using STREAM
using STREAM: Pump, Channel

@testset "Pump fixed-flow mode" begin
    @named pump = Pump(mdot0=0.6)
    @test_nowarn mtkcompile(pump; fully_determined=false)
    @named pump5 = Pump(mdot0=0.6)
    @named bc5 = HeatExchanger(313.15)
    @named ch5 = Channel(n=5, geometry=PipeGeometry_circular(0.6, 0.01))
    conns5 = [
        connect(pump5.port_out, bc5.port_in),
        connect(bc5.port_out, ch5.port_in),
        connect(ch5.port_out, pump5.port_in),
        pump5.port_in.P ~ 1e5,
    ]
    @named sys5 = compose(System(conns5, t; name=:phy05_loop), pump5, bc5, ch5)
    ssys5 = mtkcompile(sys5; fully_determined=false)
    op5 = Pair{Any,Any}[ssys5.ch5.port_in.mdot => 0.6]
    append!(op5, [ssys5.ch5.T[i] => 313.15 for i in 1:5])
    sol5 = solve_steady(ssys5, op5)
    @test sol5.retcode == ReturnCode.Success
    @test isapprox(sol5[ssys5.pump5.port_in.mdot], 0.6; rtol=1e-4)
end

@testset "Pump dispatch correctness" begin
    # Each constructor dispatch must produce a System with the defining pressure/flow
    # relation of its mode, not merely "a System". Solve a small resistor loop in each mode
    # and check the relation the mode promises holds at the solved operating point.
    R_val = 1.0e5   # Pa/(kg/s)

    # --- Scalar fixed-pressure mode: port_out.P - port_in.P == dP_pump exactly. ---
    dP_scalar = 1.2e5
    @named p_real = Pump(dP_scalar)
    @test p_real isa ModelingToolkit.System
    @named res_real = Resistor(R_val)
    @named hx_real = HeatExchanger(313.15)
    conns_real = [
        connect(p_real.port_out, hx_real.port_in),
        connect(hx_real.port_out, res_real.port_in),
        connect(res_real.port_out, p_real.port_in),
        p_real.port_in.P ~ 1.0e5,
    ]
    @named sys_real = compose(System(conns_real, t; name=:disp_real), p_real, hx_real, res_real)
    ssys_real = mtkcompile(sys_real)
    sol_real = solve_steady(ssys_real, Pair{Any,Any}[ssys_real.res_real.port_in.mdot => 1.0])
    @test sol_real.retcode == ReturnCode.Success
    # Defining relation of scalar mode: the head equals the prescribed dP (rtol=1e-8, the
    # head is an exact algebraic equation, only float round-off separates them).
    @test isapprox(
        sol_real[ssys_real.p_real.port_out.P] - sol_real[ssys_real.p_real.port_in.P],
        dP_scalar; rtol=1e-8,
    )
    # The same head also fixes the loop flow: mdot = dP/R through the single resistor.
    @test isapprox(sol_real[ssys_real.res_real.port_in.mdot], dP_scalar / R_val; rtol=1e-6)

    # --- Callable fixed-pressure mode: the head follows the callable at the solve time. ---
    # A steady solve relaxes in real time to t where dP_pump_fn(t) is read; with a constant
    # callable the head must equal that constant value, distinct from the scalar case above.
    dP_call_val = 8.0e4
    dP_call = (_tt) -> dP_call_val
    @named p_fn = Pump(dP_call)
    @test p_fn isa ModelingToolkit.System
    @named res_fn = Resistor(R_val)
    @named hx_fn = HeatExchanger(313.15)
    conns_fn = [
        connect(p_fn.port_out, hx_fn.port_in),
        connect(hx_fn.port_out, res_fn.port_in),
        connect(res_fn.port_out, p_fn.port_in),
        p_fn.port_in.P ~ 1.0e5,
    ]
    @named sys_fn = compose(System(conns_fn, t; name=:disp_fn), p_fn, hx_fn, res_fn)
    ssys_fn = mtkcompile(sys_fn)
    sol_fn = solve_steady(
        ssys_fn,
        Pair{Any,Any}[
            ssys_fn.res_fn.port_in.mdot => 1.0,
            ssys_fn.p_fn.dP_pump_fn => dP_call,
        ],
    )
    @test sol_fn.retcode == ReturnCode.Success
    # Defining relation of callable mode: the head equals the callable's value (rtol=1e-8,
    # exact algebraic head). Confirms the callable, not a frozen constant, drove the solve.
    @test isapprox(
        sol_fn[ssys_fn.p_fn.port_out.P] - sol_fn[ssys_fn.p_fn.port_in.P],
        dP_call_val; rtol=1e-8,
    )
    @test isapprox(sol_fn[ssys_fn.res_fn.port_in.mdot], dP_call_val / R_val; rtol=1e-6)

    # --- Fixed-flow mode: port_in.mdot == mdot0 regardless of loop resistance. ---
    mdot_set = 0.6
    @named p_mdot = Pump(mdot0=mdot_set)
    @test p_mdot isa ModelingToolkit.System
    @named res_m = Resistor(R_val)
    @named hx_m = HeatExchanger(313.15)
    conns_m = [
        connect(p_mdot.port_out, hx_m.port_in),
        connect(hx_m.port_out, res_m.port_in),
        connect(res_m.port_out, p_mdot.port_in),
        p_mdot.port_in.P ~ 1.0e5,
    ]
    @named sys_m = compose(System(conns_m, t; name=:disp_m), p_mdot, hx_m, res_m)
    ssys_m = mtkcompile(sys_m; fully_determined=false)
    sol_m = solve_steady(ssys_m, Pair{Any,Any}[ssys_m.res_m.port_in.mdot => mdot_set])
    @test sol_m.retcode == ReturnCode.Success
    # Defining relation of fixed-flow mode: the flow is pinned to mdot0 (rtol=1e-8, exact
    # algebraic constraint port_in.mdot ~ mdot0).
    @test isapprox(sol_m[ssys_m.p_mdot.port_in.mdot], mdot_set; rtol=1e-8)
end

@testset "Scalar Pump(dP_pump) unchanged" begin
    @named pump_s = Pump(1e5)
    @test_nowarn mtkcompile(pump_s; fully_determined=false)

    @named pump_r = Pump(3.0e4)
    @named bc_r = HeatExchanger(313.15)
    @named ch_r = Channel(n=5, geometry=PipeGeometry_circular(0.6, 0.01))
    conns_r = [
        connect(pump_r.port_out, bc_r.port_in),
        connect(bc_r.port_out, ch_r.port_in),
        connect(ch_r.port_out, pump_r.port_in),
        pump_r.port_in.P ~ 1e5,
    ]
    @named sys_r = compose(System(conns_r, t; name=:pump02_loop), pump_r, bc_r, ch_r)
    ssys_r = mtkcompile(sys_r; fully_determined=false)
    op_r = [ssys_r.ch_r.T[i] => 313.15 for i in 1:5]
    push!(op_r, ssys_r.ch_r.port_in.mdot => 0.490)
    sol_r = solve_steady(ssys_r, op_r)
    @test sol_r.retcode == ReturnCode.Success
    @test sol_r[ssys_r.ch_r.port_in.mdot] > 0
end

@testset "Callable pump dispatch" begin
    dP_fn = t -> 1e5 * (1 - t / 100.0)
    @named pump_c = Pump(dP_fn)
    @test pump_c isa ModelingToolkit.System
    @test_nowarn mtkcompile(pump_c; fully_determined=false)
end

@testset "Callable pump ramp — mdot decays to zero" begin
    dP0 = 1e5       # Pa
    T_ramp = 100.0     # s
    R_val = 1e5       # Pa/(kg/s) — steady-state mdot_0 = dP0/R = 1.0 kg/s
    L_over_A = 5e5       # m^{-1} — tau = L_over_A/R = 5.0 s; T_ramp/tau = 20
    tau = L_over_A / R_val   # 5.0 s

    # Build both heads from one factory so they share a closure type. The pump stores its head as
    # an MTK callable parameter typed to the function it was constructed with, so the steady-state
    # head and the ramp head must be the same type to be interchangeable in the operating point.
    make_head = rate -> (tt -> dP0 * (1 - rate * tt / T_ramp))
    dP_fn = make_head(1.0)        # the ramp: dP0·(1 - t/T_ramp)
    dP_hold = make_head(0.0)      # constant dP0, for the steady solve

    @named pump = Pump(dP_fn)
    @named ine = Inertia(L_over_A)
    @named res = Resistor(R_val)
    @named hx = HeatExchanger(313.15)

    # Closed loop: pump -> inertia -> resistor -> heat exchanger -> pump. The heat exchanger pins
    # the loop temperature (a bare hydraulics-only loop has degenerate circular instream temps) and
    # gives solve_steady the same well-posed topology the integration coastdowns use.
    conns = [
        connect(pump.port_out, ine.port_in),
        connect(ine.port_out, res.port_in),
        connect(res.port_out, hx.port_in),
        connect(hx.port_out, pump.port_in),
        pump.port_in.P ~ 1e5,       # pressure anchor
    ]
    @named sys = compose(System(conns, t; name=:pump03), pump, ine, res, hx)
    ssys = mtkcompile(sys)

    mdot_0 = dP0 / R_val

    # solve_steady relaxes to steady in real time, so feed it the held head dP0 (not the ramp,
    # which would keep falling during the solve and drive the flow unstable) and let it settle at
    # mdot_0. The stiff DynamicSS solver is explicit here: the default steady solver goes unstable on
    # this callable-head loop. Then run the ramp transient from that full solved state. Seeding every
    # state from the solved point rather than a hand-picked mdot keeps the start consistent
    # regardless of which variables MTK keeps as differential states. The old partial IC plus NoInit
    # landed off the real state on newer MTK and the flow sat frozen at the mdot=0 fixed point.
    sol_ss = solve_steady(ssys,
        Pair{Any,Any}[ssys.ine.port_in.mdot => mdot_0, ssys.pump.dP_pump_fn => dP_hold];
        solver=DynamicSS(Rodas5P()))
    @test sol_ss.retcode == ReturnCode.Success
    @test isapprox(sol_ss[ssys.ine.port_in.mdot], mdot_0; rtol=1e-3)   # relaxation endpoint, loose

    t_arr = range(0.0, T_ramp, length=1000)
    sol = solve_transient(ssys, sol_ss, t_arr; overrides=[ssys.pump.dP_pump_fn => dP_fn])

    @test sol.retcode == ReturnCode.Success

    function mdot_analytical(t_val)
        return (dP0 / R_val) *
               (1 + tau/T_ramp - t_val/T_ramp - (tau/T_ramp) * exp(-t_val/tau))
    end

    mdot_end_analytical = mdot_analytical(T_ramp)
    mdot_end_numerical = sol[ssys.ine.port_in.mdot, end]

    @test isapprox(mdot_end_numerical, mdot_end_analytical; rtol=0.01)

    @test isapprox(sol[ssys.ine.port_in.mdot, 1], mdot_0; rtol=0.01)
    @test abs(mdot_end_numerical) < 0.1 * mdot_0
    idx_mid = length(t_arr) ÷ 2
    t_mid = t_arr[idx_mid]
    mdot_mid_analytical = mdot_analytical(t_mid)
    mdot_mid_numerical = sol[ssys.ine.port_in.mdot, idx_mid]
    @test isapprox(mdot_mid_numerical, mdot_mid_analytical; rtol=0.01)
end
