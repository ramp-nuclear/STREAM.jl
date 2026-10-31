using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using STREAM
using STREAM.Assemblies
using STREAM.Components

@testset "Pump fixed-flow mode compiles on its own" begin
    @named pump = Pump(; ṁ0=0.6)
    @test_nowarn mtkcompile(pump; fully_determined=false)
end

@testset "Pump dispatch correctness" begin
    # Each constructor dispatch must produce a System with the defining pressure/flow
    # relation of its mode, not merely "a System". Solve a small resistor loop in each mode
    # and check the relation the mode promises holds at the solved operating point.
    R_val = 1.0e5   # Pa/(kg/s)

    # --- Scalar fixed-pressure mode: outlet.p - inlet.p == dP_pump exactly. ---
    dP_scalar = 1.2e5
    @named p_real = Pump(dP_scalar)
    @test p_real isa ModelingToolkit.System
    @named res_real = Resistor(R_val)
    @named hx_real = HeatExchanger(40.0)
    conns_real = [
        inseries(p_real, hx_real, res_real, p_real),
        p_real.inlet.p ~ 1.0e5,
    ]
    @mtkcompile ssys_real = assembly(conns_real, p_real, hx_real, res_real)
    sol_real = solve_steady(ssys_real)
    @test sol_real.retcode == ReturnCode.Success
    # Defining relation of scalar mode: the head equals the prescribed dP (rtol=1e-8, the
    # head is an exact algebraic equation, only float round-off separates them).
    @test isapprox(
        sol_real[ssys_real.p_real.outlet.p] - sol_real[ssys_real.p_real.inlet.p],
        dP_scalar; rtol=1e-8,
    )
    # The same head also fixes the loop flow: ṁ = dP/R through the single resistor.
    @test isapprox(sol_real[ssys_real.res_real.inlet.ṁ], dP_scalar / R_val; rtol=1e-6)
    # Every two-port reports its pressure rise and flow: the pump rises by its head, and the
    # resistor drops by as much, carrying the same flow.
    @test sol_real[ssys_real.p_real.Δp] ≈ dP_scalar
    @test sol_real[ssys_real.res_real.Δp] ≈ -dP_scalar
    @test sol_real[ssys_real.res_real.ṁ] ≈ sol_real[ssys_real.res_real.inlet.ṁ]

    # --- Callable fixed-pressure mode: the head follows the callable at the solve time. ---
    # A steady solve reads the callable at t = 0; a constant callable's head is its value,
    # distinct from the scalar case above.
    dP_call_val = 8.0e4
    dP_call = (_tt) -> dP_call_val
    @named p_fn = Pump(dP_call)
    @test p_fn isa ModelingToolkit.System
    @named res_fn = Resistor(R_val)
    @named hx_fn = HeatExchanger(40.0)
    conns_fn = [
        inseries(p_fn, hx_fn, res_fn, p_fn),
        p_fn.inlet.p ~ 1.0e5,
    ]
    @mtkcompile ssys_fn = assembly(conns_fn, p_fn, hx_fn, res_fn)
    sol_fn = solve_steady(ssys_fn)
    @test sol_fn.retcode == ReturnCode.Success
    # Defining relation of callable mode: the head equals the callable's value (rtol=1e-8,
    # exact algebraic head). Confirms the callable, not a frozen constant, drove the solve.
    @test isapprox(
        sol_fn[ssys_fn.p_fn.outlet.p] - sol_fn[ssys_fn.p_fn.inlet.p],
        dP_call_val; rtol=1e-8,
    )
    @test isapprox(sol_fn[ssys_fn.res_fn.inlet.ṁ], dP_call_val / R_val; rtol=1e-6)

    # --- Fixed-flow mode: inlet.ṁ == ṁ0 regardless of loop resistance. ---
    ṁ_set = 0.6
    @named p_ṁ = Pump(; ṁ0=ṁ_set)
    @test p_ṁ isa ModelingToolkit.System
    @named res_m = Resistor(R_val)
    @named hx_m = HeatExchanger(40.0)
    conns_m = [
        inseries(p_ṁ, hx_m, res_m, p_ṁ),
        p_ṁ.inlet.p ~ 1.0e5,
    ]
    @named sys_m = assembly(conns_m, p_ṁ, hx_m, res_m)
    ssys_m = mtkcompile(sys_m; fully_determined=false)
    sol_m = solve_steady(ssys_m)
    @test sol_m.retcode == ReturnCode.Success
    # Defining relation of fixed-flow mode: the flow is pinned to ṁ0 (rtol=1e-8, exact
    # algebraic constraint inlet.ṁ ~ ṁ0).
    @test isapprox(sol_m[ssys_m.p_ṁ.inlet.ṁ], ṁ_set; rtol=1e-8)
end

@testset "Pump fixed-pressure mode compiles on its own" begin
    @named pump = Pump(1e5)
    @test_nowarn mtkcompile(pump; fully_determined=false)
end

@testset "Callable pump dispatch" begin
    dP_fn = t -> 1e5 * (1 - t / 100.0)
    @named pump_c = Pump(dP_fn)
    @test pump_c isa ModelingToolkit.System
    @test_nowarn mtkcompile(pump_c; fully_determined=false)
end

@testset "Callable pump ramp — ṁ decays to zero" begin
    dP0 = 1e5       # Pa
    T_ramp = 100.0     # s
    R_val = 1e5       # Pa/(kg/s) — steady-state ṁ_0 = dP0/R = 1.0 kg/s
    L_over_A = 5e5       # m^{-1} — tau = L_over_A/R = 5.0 s; T_ramp/tau = 20
    tau = L_over_A / R_val   # 5.0 s

    dP_fn = tt -> dP0 * (1 - tt / T_ramp)

    @named pump = Pump(dP_fn)
    @named ine = Inertia(L_over_A)
    @named res = Resistor(R_val)
    @named hx = HeatExchanger(40.0)

    # Closed loop: pump -> inertia -> resistor -> heat exchanger -> pump. The heat exchanger pins
    # the loop temperature (a bare hydraulics-only loop has degenerate circular instream temps) and
    # gives solve_steady the same well-posed topology the integration coastdowns use.
    conns = [
        inseries(pump, ine, res, hx, pump),
        pump.inlet.p ~ 1e5,       # pressure anchor
    ]
    @mtkcompile ssys = assembly(conns, pump, ine, res, hx)

    ṁ_0 = dP0 / R_val

    # Initial condition: the steady flow at t = 0, under the head dP0, then the ramp transient
    # from that full solved state. Carrying every state from the solved point (not just a
    # hand-picked ṁ) keeps the start consistent no matter which variables MTK keeps as states; a
    # partial guess landed off the real state on newer MTK and the flow froze at ṁ=0.
    #
    # Solver choice: the default root finder goes unstable on this loop, so the steady solve
    # integrates with DynamicSS(Rodas5P) first.
    sol_ss = solve_steady(ssys; solver=DynamicSS(Rodas5P()))
    @test sol_ss.retcode == ReturnCode.Success
    @test isapprox(sol_ss[ssys.ine.inlet.ṁ], ṁ_0; rtol=1e-3)   # relaxation endpoint, loose

    t_arr = range(0.0, T_ramp, length=1000)
    sol = solve_transient(ssys, sol_ss, t_arr)

    @test sol.retcode == ReturnCode.Success

    function ṁ_analytical(t_val)
        return (dP0 / R_val) *
               (1 + tau/T_ramp - t_val/T_ramp - (tau/T_ramp) * exp(-t_val/tau))
    end

    ṁ_end_analytical = ṁ_analytical(T_ramp)
    ṁ_end_numerical = sol[ssys.ine.inlet.ṁ, end]

    @test isapprox(ṁ_end_numerical, ṁ_end_analytical; rtol=0.01)

    @test isapprox(sol[ssys.ine.inlet.ṁ, 1], ṁ_0; rtol=0.01)
    @test abs(ṁ_end_numerical) < 0.1 * ṁ_0
    idx_mid = length(t_arr) ÷ 2
    t_mid = t_arr[idx_mid]
    ṁ_mid_analytical = ṁ_analytical(t_mid)
    ṁ_mid_numerical = sol[ssys.ine.inlet.ṁ, idx_mid]
    @test isapprox(ṁ_mid_numerical, ṁ_mid_analytical; rtol=0.01)
end
