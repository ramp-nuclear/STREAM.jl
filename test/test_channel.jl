using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using DifferentialEquations
using STREAM
import STREAM: Channel, ChannelAndContacts, ChannelHeatFlux, ConstantTemperature, build_loop_vertical

@testset "COMP-01: Channel stub callable" begin
    @named ch = Channel(n=5, geometry=PipeGeometry_circular(1.0, 0.01))
    @test ch isa ModelingToolkit.System
end

@testset "COMP-01: Channel equation count" begin
    @named ch = Channel(n=5, geometry=PipeGeometry_circular(1.0, 0.01))
    energy_eqs = filter(eq -> occursin("Differential", string(eq)), equations(ch))
    @test length(energy_eqs) == 5  # 5 energy balance ODEs (one per cell)
end

@testset "COMP-01: Channel mtkcompile" begin
    @named ch = Channel(n=5, geometry=PipeGeometry_circular(1.0, 0.01))
    # fully_determined=false required for isolated component with unconnected ports
    @test_nowarn mtkcompile(ch; fully_determined=false)
end

@testset "COMP-02: Pump stub callable" begin
    @named pump = Pump(1e4)
    @test pump isa ModelingToolkit.System
    @test_nowarn mtkcompile(pump; fully_determined=false)
end

@testset "COMP-03: Friction stub callable" begin
    @named fr = Friction(L=1.0, D=0.01, A=7.85e-5)
    @test fr isa ModelingToolkit.System
    @test_nowarn mtkcompile(fr; fully_determined=false)
end

@testset "COMP-04: Gravity stub callable" begin
    @named grav = Gravity(H=3.0)
    @test grav isa ModelingToolkit.System
    @test_nowarn mtkcompile(grav; fully_determined=false)
end

# ─────────────────────────────────────────────────────────────────
# GRAV-01: Vertical closed loop assembles, compiles, and solves
# Topology: Pump -> TempBC -> Channel(g_acc=9.80665, L=0.6m) -> Gravity(H=0.6m) -> Pump
# Channel carries g_acc for the upward leg; Gravity carries the return leg.
# ─────────────────────────────────────────────────────────────────
@testset "GRAV-01: vertical loop mtkcompiles" begin
    ssys_v = build_loop_vertical()
    @test ssys_v isa ModelingToolkit.AbstractSystem
end

@testset "GRAV-01: vertical loop solves" begin
    n = 10; T_inlet = 313.15
    ssys_v = build_loop_vertical(T_inlet=T_inlet)
    T_guess = steady_state_guess(T_inlet=T_inlet, Q_wall=1e4, mdot_guess=0.490, n=n)
    op = [ssys_v.ch.T[i] => T_guess[i] for i in 1:n]
    push!(op, ssys_v.ch.port_in.mdot => 0.490)
    sol = solve_steady(ssys_v, op)
    @test sol.retcode == ReturnCode.Success
    @test sol[ssys_v.ch.port_in.mdot] > 0
end

# ─────────────────────────────────────────────────────────────────
# GRAV-02: Gravity cancellation — equal up/down height gives same
# steady-state mass flow as horizontal reference loop (within 1%)
#
# Physics: Channel dP includes +rho*g_acc*L (head loss going up).
# Gravity component adds rho*9.80665*H to the return leg (head gain going down).
# When H == L_ch == 0.6m, the two terms cancel; net gravity effect = 0.
# The cancellation loop should therefore match the horizontal loop's mdot.
# ─────────────────────────────────────────────────────────────────
@testset "GRAV-02: gravity cancellation within 1% of horizontal" begin
    n = 10; T_inlet = 313.15; L_ch = 0.6

    # Horizontal reference (g_acc=0, no Gravity component)
    ssys_h = build_loop(T_inlet=T_inlet)
    T_guess = steady_state_guess(T_inlet=T_inlet, Q_wall=1e4, mdot_guess=0.490, n=n)
    op_h = [ssys_h.ch.T[i] => T_guess[i] for i in 1:n]
    push!(op_h, ssys_h.ch.port_in.mdot => 0.490)
    sol_h = solve_steady(ssys_h, op_h)
    mdot_horiz = abs(sol_h[ssys_h.ch.port_in.mdot])

    # Vertical cancellation loop (g_acc=9.80665, H_return=L_ch)
    ssys_v = build_loop_vertical(T_inlet=T_inlet, L_ch=L_ch, H_return=L_ch)
    op_v = [ssys_v.ch.T[i] => T_guess[i] for i in 1:n]
    push!(op_v, ssys_v.ch.port_in.mdot => 0.490)
    sol_v = solve_steady(ssys_v, op_v)
    mdot_vert = abs(sol_v[ssys_v.ch.port_in.mdot])

    @test isapprox(mdot_vert, mdot_horiz; rtol=0.01)
end

# ─────────────────────────────────────────────────────────────────
# THERM-01: ChannelAndContacts — n ThermalPorts, per-cell energy balance
# ─────────────────────────────────────────────────────────────────
@testset "THERM-01: ChannelAndContacts callable" begin
    @named ch = ChannelAndContacts(n=5, geometry=PipeGeometry_circular(1.0, 0.01))
    @test ch isa ModelingToolkit.System
end

@testset "THERM-01: ChannelAndContacts mtkcompile" begin
    @named ch = ChannelAndContacts(n=5, geometry=PipeGeometry_circular(1.0, 0.01))
    @test_nowarn mtkcompile(ch; fully_determined=false)
end

@testset "THERM-01: ChannelAndContacts has n ThermalPort subsystems" begin
    @named ch = ChannelAndContacts(n=5, geometry=PipeGeometry_circular(1.0, 0.01))
    subsys_names = Symbol.(ModelingToolkit.getname.(ModelingToolkit.get_systems(ch)))
    for i in 1:5
        @test Symbol(:thermal_left, i)  in subsys_names
        @test Symbol(:thermal_right, i) in subsys_names
    end
    # Old single-side names must be absent
    @test !(Symbol(:thermal, 1) in subsys_names)
end

# ─────────────────────────────────────────────────────────────────
# THERM-02: Channel unchanged — all v0.1-v0.2 tests still pass
# (implicit: reaching this point means prior testsets passed)
# ─────────────────────────────────────────────────────────────────
@testset "THERM-02: Channel unmodified (regression)" begin
    @named ch = Channel(n=5, geometry=PipeGeometry_circular(1.0, 0.01))
    @test ch isa ModelingToolkit.System
    subsys_names = Symbol.(ModelingToolkit.getname.(ModelingToolkit.get_systems(ch)))
    @test :thermal in subsys_names   # single ThermalPort, unchanged
    @test !(Symbol(:thermal, 1) in subsys_names)  # no per-cell array on Channel
end

# ─────────────────────────────────────────────────────────────────
# THERM-03: ChannelAndContacts two-sided matches ChannelHeatFlux within 0.1%
# Both thermal_left and thermal_right connected to T_wall with D_cac = D_chf.
# h_tc*(π*D/2)*dz*(T_wall-T)*2 = h_tc*(π*D)*dz*(T_wall-T) — exact CHF equivalence.
# ─────────────────────────────────────────────────────────────────
@testset "THERM-03: ChannelAndContacts two-sided matches ChannelHeatFlux within 0.1%" begin
    # Two-sided CAC (both left and right connected to same T_wall) with D=D_chf
    # gives h_tc*(π*D/2)*dz*(T_wall-T)*2 = h_tc*(π*D)*dz*(T_wall-T) — identical to CHF.
    # Same D ensures identical h_tc. CHAN-03 separately validates the adiabatic right side.
    n = 10; T_inlet = 313.15; T_wall = 373.15
    L_ch = 0.6; D_ch = 0.01; A_ch = 7.85e-5; dP_pump = 3.0e4

    # --- ChannelHeatFlux reference ---
    @named pump_chf = Pump(dP_pump)
    @named chf = ChannelHeatFlux(n=n, geometry=PipeGeometry_circular(L_ch, D_ch), T_wall=T_wall)
    @named bc_chf = HeatExchanger(T_bc=T_inlet)
    conns_chf = [
        connect(pump_chf.port_out, bc_chf.port_in),
        connect(bc_chf.port_out, chf.port_in),
        connect(chf.port_out, pump_chf.port_in),
        pump_chf.port_in.P ~ 1.0e5,
        chf.port_in.T ~ T_inlet,
    ]
    @named sys_chf = compose(System(conns_chf, t; name=:sys_chf), pump_chf, bc_chf, chf)
    ssys_chf = mtkcompile(sys_chf)
    T_guess = steady_state_guess(T_inlet=T_inlet, Q_wall=1e4, mdot_guess=0.490, n=n)
    op_chf = [ssys_chf.chf.T[i] => T_guess[i] for i in 1:n]
    push!(op_chf, ssys_chf.chf.port_in.mdot => 0.490)
    sol_chf = solve_steady(ssys_chf, op_chf)
    T_out_chf = sol_chf[ssys_chf.chf.T_out]

    # --- ChannelAndContacts two-sided (both left and right connected to T_wall) ---
    @named pump_cac = Pump(dP_pump)
    @named cac = ChannelAndContacts(n=n, geometry=PipeGeometry_circular(L_ch, D_ch))
    @named bc_cac = HeatExchanger(T_bc=T_inlet)
    ct_l = [ConstantTemperature(name=Symbol(:ct_l, i), T=T_wall) for i in 1:n]
    ct_r = [ConstantTemperature(name=Symbol(:ct_r, i), T=T_wall) for i in 1:n]
    conns_cac = [
        connect(pump_cac.port_out, bc_cac.port_in),
        connect(bc_cac.port_out, cac.port_in),
        connect(cac.port_out, pump_cac.port_in),
        [connect(ct_l[i].thermal, getproperty(cac, Symbol(:thermal_left,  i))) for i in 1:n]...,
        [connect(ct_r[i].thermal, getproperty(cac, Symbol(:thermal_right, i))) for i in 1:n]...,
        pump_cac.port_in.P ~ 1.0e5,
        cac.port_in.T ~ T_inlet,
    ]
    @named sys_cac = compose(System(conns_cac, t; name=:sys_cac), pump_cac, bc_cac, cac, ct_l..., ct_r...)
    ssys_cac = mtkcompile(sys_cac)
    op_cac = [ssys_cac.cac.T[i] => T_guess[i] for i in 1:n]
    push!(op_cac, ssys_cac.cac.port_in.mdot => 0.490)
    sol_cac = solve_steady(ssys_cac, op_cac)
    T_out_cac = sol_cac[ssys_cac.cac.T_out]

    @test isapprox(T_out_cac, T_out_chf; rtol=1e-3)  # 0.1%
end

# ─────────────────────────────────────────────────────────────────
# CHAN-03: Unconnected thermal_right defaults to adiabatic (Q_flow == 0)
# Uses same one-sided CAC geometry as THERM-03
# ─────────────────────────────────────────────────────────────────
@testset "CHAN-03: Unconnected thermal_right is adiabatic (Q_flow == 0)" begin
    n = 5; T_inlet = 313.15; T_wall = 373.15
    L_ch = 0.6; D_cac = 0.02; A_ch = 7.85e-5; dP_pump = 3.0e4

    @named pump2 = Pump(dP_pump)
    @named cac2 = ChannelAndContacts(n=n, geometry=PipeGeometry_circular(L_ch, D_cac))
    @named bc2 = HeatExchanger(T_bc=T_inlet)
    ct2 = [ConstantTemperature(name=Symbol(:ct2_, i), T=T_wall) for i in 1:n]
    conns2 = [
        connect(pump2.port_out, bc2.port_in),
        connect(bc2.port_out, cac2.port_in),
        connect(cac2.port_out, pump2.port_in),
        [connect(ct2[i].thermal, getproperty(cac2, Symbol(:thermal_left, i))) for i in 1:n]...,
        pump2.port_in.P ~ 1.0e5,
        cac2.port_in.T ~ T_inlet,
    ]
    @named sys2 = compose(System(conns2, t; name=:sys2), pump2, bc2, cac2, ct2...)
    ssys2 = mtkcompile(sys2; fully_determined=false)
    T_guess2 = steady_state_guess(T_inlet=T_inlet, Q_wall=5e3, mdot_guess=0.490, n=n)
    op2 = [ssys2.cac2.T[i] => T_guess2[i] for i in 1:n]
    push!(op2, ssys2.cac2.port_in.mdot => 0.490)
    # Unconnected thermal_right ports have free T variables — provide initial guess
    right_syms2 = [getproperty(ssys2.cac2, Symbol(:thermal_right, i)) for i in 1:n]
    append!(op2, [right_syms2[i].T => T_wall for i in 1:n])
    # Provide Re/Nu/h_tc guesses to break initialization cycle for algebraic variables
    append!(op2, [ssys2.cac2.Re[i] => 3e5 for i in 1:n])
    append!(op2, [ssys2.cac2.Nu[i] => 800.0 for i in 1:n])
    append!(op2, [ssys2.cac2.h_tc[i] => 2.7e4 for i in 1:n])
    sol2 = solve_steady(ssys2, op2)

    # Verify all unconnected thermal_right ports have Q_flow == 0
    right_syms = [getproperty(ssys2.cac2, Symbol(:thermal_right, i)) for i in 1:n]
    for i in 1:n
        @test isapprox(sol2[right_syms[i].Q_flow], 0.0; atol=1e-8)
    end
end

# ─────────────────────────────────────────────────────────────────
# CHAN-01: ChannelAndContacts dual port arrays (DEBT-01 + CHAN-01/02)
# ─────────────────────────────────────────────────────────────────
@testset "CHAN-01: ChannelAndContacts callable with dual ports" begin
    @named ch = ChannelAndContacts(n=2, geometry=PipeGeometry_circular(1.0, 0.01))
    @test ch isa ModelingToolkit.System
end

@testset "CHAN-01: ChannelAndContacts mtkcompile (bare, no connections)" begin
    @named ch = ChannelAndContacts(n=2, geometry=PipeGeometry_circular(1.0, 0.01))
    @test_nowarn mtkcompile(ch; fully_determined=false)
end

@testset "CHAN-02: ConstantTemperature exported from STREAM" begin
    @test isdefined(STREAM, :ConstantTemperature)
end

@testset "CHAN-02: ConstantTemperature callable and mtkcompiles" begin
    @named ct = ConstantTemperature(T=373.15)
    @test ct isa ModelingToolkit.System
    @test_nowarn mtkcompile(ct; fully_determined=false)
end

# ─────────────────────────────────────────────────────────────────
# ChannelHeatFlux: standalone — builds, solves, produces heated output
# Topology: Pump -> HeatExchanger(T_bc) -> ChannelHeatFlux(T_wall) -> Pump
# Confirms: retcode Success, T_out > T_inlet (heat added)
# ─────────────────────────────────────────────────────────────────
@testset "ChannelHeatFlux: standalone" begin
    n = 10; T_inlet = 313.15; T_wall = 373.15
    L_ch = 0.6; D_ch = 0.01; dP_pump = 3.0e4

    @named pump = Pump(dP_pump)
    @named chf  = ChannelHeatFlux(n=n, geometry=PipeGeometry_circular(L_ch, D_ch), T_wall=T_wall)
    @named bc   = HeatExchanger(T_bc=T_inlet)
    conns = [
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out, chf.port_in),
        connect(chf.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
        chf.port_in.T  ~ T_inlet,
    ]
    @named sys = compose(System(conns, t; name=:sys), pump, bc, chf)
    ssys = mtkcompile(sys)
    T_guess = steady_state_guess(T_inlet=T_inlet, Q_wall=1e4, mdot_guess=0.490, n=n)
    op = [ssys.chf.T[i] => T_guess[i] for i in 1:n]
    push!(op, ssys.chf.port_in.mdot => 0.490)
    sol = solve_steady(ssys, op)

    @test sol.retcode == ReturnCode.Success
    @test sol[ssys.chf.T_out] > T_inlet   # outlet must be warmer than inlet
end
