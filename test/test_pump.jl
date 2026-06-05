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
    @named p_real = Pump(1e5)
    @test p_real isa ModelingToolkit.System

    @named p_fn = Pump(t -> 1e5)
    @test p_fn isa ModelingToolkit.System

    @named p_mdot = Pump(mdot0=0.6)
    @test p_mdot isa ModelingToolkit.System
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

    dP_fn = t -> dP0 * (1 - t / T_ramp)

    @named pump = Pump(dP_fn)
    @named ine = Inertia(L_over_A)
    @named res = Resistor(R_val)

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

    mdot_0 = dP0 / R_val
    op = [ssys.ine.port_in.mdot => mdot_0, ssys.pump.dP_pump_fn => dP_fn]

    t_arr = range(0.0, T_ramp, length=1000)
    sol = solve_transient(ssys, op, t_arr)

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
