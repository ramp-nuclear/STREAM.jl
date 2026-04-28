using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using STREAM
import STREAM: Pump, Channel

# ─────────────────────────────────────────────────────────────────
# PHY-05: Pump fixed-flow mode (mdot0 dispatch)
# ─────────────────────────────────────────────────────────────────
@testset "PHY-05: Pump fixed-flow mode" begin
    # Test: Pump(mdot0=0.6) is callable and assembles as a System
    @named pump = Pump(mdot0=0.6)
    @test pump isa ModelingToolkit.System

    # Test: Pump(mdot0=0.6) mtkcompiles without error (bare, no connections)
    # fully_determined=false: isolated ports make system under-determined
    @test_nowarn mtkcompile(pump; fully_determined=false)

    # Test: Integration — Pump(mdot0=0.6) in a loop: Pump → HeatExchanger → Channel → back
    # HeatExchanger provides pressure closure (port_in.P - port_out.P ~ 0)
    # pump.port_in.P ~ 1e5 provides absolute pressure reference
    @named pump5  = Pump(mdot0=0.6)
    @named bc5    = HeatExchanger(313.15)
    @named ch5    = Channel(n=5, geometry=PipeGeometry_circular(0.6, 0.01))
    conns5 = [
        connect(pump5.port_out, bc5.port_in),
        connect(bc5.port_out,   ch5.port_in),
        connect(ch5.port_out,   pump5.port_in),
        pump5.port_in.P ~ 1e5,
        ch5.thermal.T  ~ 350.0,   # pin wall temperature (adiabatic not needed; mdot0 drives flow)
    ]
    @named sys5 = compose(System(conns5, t; name=:phy05_loop), pump5, bc5, ch5)
    ssys5 = mtkcompile(sys5; fully_determined=false)
    op5 = Pair{Any,Any}[ssys5.ch5.port_in.mdot => 0.6]
    append!(op5, [ssys5.ch5.T[i] => 313.15 for i in 1:5])
    sol5 = solve_steady(ssys5, op5)
    @test sol5.retcode == ReturnCode.Success
    @test isapprox(sol5[ssys5.pump5.port_in.mdot], 0.6; rtol=1e-4)
end

# ─────────────────────────────────────────────────────────────────
# PUMP-02: Pump dispatch correctness (regression — scalar and mdot0 modes)
# ─────────────────────────────────────────────────────────────────
@testset "PUMP-02: Pump dispatch correctness" begin
    # Scalar dispatches to Real method
    @named p_real = Pump(1e5)
    @test p_real isa ModelingToolkit.System

    # Function dispatches to Any method
    @named p_fn = Pump(t -> 1e5)
    @test p_fn isa ModelingToolkit.System

    # mdot0 keyword still works
    @named p_mdot = Pump(mdot0=0.6)
    @test p_mdot isa ModelingToolkit.System
end

# ─────────────────────────────────────────────────────────────────
# PUMP-02: Scalar Pump(dP_pump) unchanged (regression integration test)
# ─────────────────────────────────────────────────────────────────
@testset "PUMP-02: Scalar Pump(dP_pump) unchanged" begin
    # Verify scalar dispatch still works with positional signature
    @named pump_s = Pump(1e5)
    @test pump_s isa ModelingToolkit.System
    @test_nowarn mtkcompile(pump_s; fully_determined=false)

    # Integration: scalar pump in a loop (positional arg syntax)
    @named pump_r  = Pump(3.0e4)
    @named bc_r    = HeatExchanger(313.15)
    @named ch_r    = Channel(n=5, geometry=PipeGeometry_circular(0.6, 0.01))
    conns_r = [
        connect(pump_r.port_out, bc_r.port_in),
        connect(bc_r.port_out,   ch_r.port_in),
        connect(ch_r.port_out,   pump_r.port_in),
        pump_r.port_in.P ~ 1e5,
        ch_r.thermal.T  ~ 350.0,
    ]
    @named sys_r = compose(System(conns_r, t; name=:pump02_loop), pump_r, bc_r, ch_r)
    ssys_r = mtkcompile(sys_r; fully_determined=false)
    op_r = [ssys_r.ch_r.T[i] => 313.15 for i in 1:5]
    push!(op_r, ssys_r.ch_r.port_in.mdot => 0.490)
    sol_r = solve_steady(ssys_r, op_r)
    @test sol_r.retcode == ReturnCode.Success
    @test sol_r[ssys_r.ch_r.port_in.mdot] > 0   # positive flow
end

# ─────────────────────────────────────────────────────────────────
# PUMP-01: Callable pump dispatch constructs and compiles
# ─────────────────────────────────────────────────────────────────
@testset "PUMP-01: Callable pump dispatch" begin
    dP_fn = t -> 1e5 * (1 - t / 100.0)
    @named pump_c = Pump(dP_fn)
    @test pump_c isa ModelingToolkit.System
    # Verify callable method was selected (not scalar)
    @test_nowarn mtkcompile(pump_c; fully_determined=false)
end

# ─────────────────────────────────────────────────────────────────
# PUMP-03: Callable pump ramp — mdot decays to zero, validated against analytical
# System: Pump + Inertia + Resistor in a closed loop
# Pump ramps dP from 1e5 to 0 over 100s
# Analytical: first-order linear ODE tau*d(mdot)/dt + mdot = dP(t)/R
# ─────────────────────────────────────────────────────────────────
@testset "PUMP-03: Callable pump ramp — mdot decays to zero" begin
    dP0      = 1e5       # Pa
    T_ramp   = 100.0     # s
    R_val    = 1e5       # Pa/(kg/s) — steady-state mdot_0 = dP0/R = 1.0 kg/s
    L_over_A = 5e5       # m^{-1} — tau = L_over_A/R = 5.0 s; T_ramp/tau = 20
    tau      = L_over_A / R_val   # 5.0 s

    dP_fn = t -> dP0 * (1 - t / T_ramp)

    @named pump = Pump(dP_fn)
    @named ine  = Inertia(L_over_A)
    @named res  = Resistor(R_val)

    # Closed loop: pump -> inertia -> resistor -> pump
    # Two thermal anchors needed: circular instream in a closed hydraulics-only loop
    # (no HeatExchanger) is degenerate; pinning pump inlet + inertia outlet breaks it.
    conns = [
        connect(pump.port_out, ine.port_in),
        connect(ine.port_out, res.port_in),
        connect(res.port_out, pump.port_in),
        pump.port_in.P ~ 1e5,       # pressure anchor
        pump.port_in.T ~ 313.15,    # thermal anchor 1
        ine.port_out.T ~ 313.15,    # thermal anchor 2 (breaks circular instream)
    ]
    @named sys = compose(System(conns, t; name=:pump03), pump, ine, res)
    ssys = mtkcompile(sys; fully_determined=false)

    mdot_0 = dP0 / R_val   # 1.0 kg/s at steady state

    op = [
        ssys.ine.port_in.mdot  => mdot_0,
        ssys.pump.dP_pump_fn   => dP_fn,
    ]

    t_arr = range(0.0, T_ramp, length=1000)
    sol = solve_transient(ssys, op, t_arr)

    @test sol.retcode == ReturnCode.Success

    # Analytical solution for forced first-order linear ODE:
    # (L/A)*d(mdot)/dt + R*mdot = dP0*(1 - t/T_ramp)
    # Particular solution (undetermined coefficients): x_p(t) = a + b*t
    #   b = -(dP0/R)/T_ramp, a = (dP0/R)*(1 + tau/T_ramp)
    # General: mdot(t) = (dP0/R)*(1 + tau/T_ramp - t/T_ramp) + C*exp(-t/tau)
    # IC mdot(0) = dP0/R -> C = -(dP0/R)*(tau/T_ramp)
    # mdot(t) = (dP0/R) * (1 + tau/T_ramp - t/T_ramp - (tau/T_ramp)*exp(-t/tau))
    function mdot_analytical(t_val)
        return (dP0 / R_val) * (1 + tau/T_ramp - t_val/T_ramp - (tau/T_ramp) * exp(-t_val/tau))
    end

    mdot_end_analytical = mdot_analytical(T_ramp)
    mdot_end_numerical  = sol[ssys.ine.port_in.mdot, end]

    @test isapprox(mdot_end_numerical, mdot_end_analytical; rtol=0.01)

    # Sanity: mdot at t=0 should be near mdot_0
    @test isapprox(sol[ssys.ine.port_in.mdot, 1], mdot_0; rtol=0.01)

    # Sanity: mdot near zero at T_ramp (|mdot| < 10% of initial)
    @test abs(mdot_end_numerical) < 0.1 * mdot_0

    # Check a midpoint too: t = T_ramp/2 = 50s
    idx_mid = length(t_arr) ÷ 2
    t_mid = t_arr[idx_mid]
    mdot_mid_analytical = mdot_analytical(t_mid)
    mdot_mid_numerical  = sol[ssys.ine.port_in.mdot, idx_mid]
    @test isapprox(mdot_mid_numerical, mdot_mid_analytical; rtol=0.01)
end
