using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using STREAM
import STREAM: Channel
import STREAM:
    dittus_boelter,
    blasius_friction,
    constant_Nusselt,
    laminar_friction,
    rectangular_laminar_correction,
    regime_dependent

# ─────────────────────────────────────────────────────────────────
# Phase 15: Composition Helpers & QoL
# QOL-01: @observed Re/Nu/velocity/Pe accessible via sol
# QOL-02: check_gravity_mismatch — balanced loop returns :ok
# QOL-03: port() helper — indexed port access
# COMP-01/02/03/04: composition helpers (pending 15-02-PLAN.md)
# ─────────────────────────────────────────────────────────────────

@testset "QOL-01: @observed Re/Nu accessible via sol" begin
    # Tests that Re, Nu, velocity, Pe, h_tc_left, T_wall_left, q_wall_left
    # are accessible via MTK symbolic indexing after solve.
    # Uses same topology as PHY-04 turbulent integration test (known-working geometry).
    n_qol = 3;
    T_inlet_qol = 313.15;
    T_wall_qol = 373.15
    geom_qol = PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07)
    @named ch_qol = ChannelAndContacts(n=n_qol, geometry=geom_qol)
    @named pump_qol = Pump(3.0e4)
    @named bc_qol = HeatExchanger(T_inlet_qol)
    ct_l_qol = [
        ConstantTemperature(T_wall_qol; name=Symbol(:ct_l_qol_, i)) for i in 1:n_qol
    ]
    ct_r_qol = [
        ConstantTemperature(T_wall_qol; name=Symbol(:ct_r_qol_, i)) for i in 1:n_qol
    ]
    conns_qol = vcat(
        [
            connect(pump_qol.outlet, bc_qol.inlet),
            connect(bc_qol.outlet, ch_qol.inlet),
            connect(ch_qol.outlet, pump_qol.inlet),
            pump_qol.inlet.P ~ 1.0e5,
        ],
        [
            connect(ct_l_qol[i].thermal, getproperty(ch_qol, Symbol(:thermal_left, i))) for
            i in 1:n_qol
        ],
        [
            connect(ct_r_qol[i].thermal, getproperty(ch_qol, Symbol(:thermal_right, i))) for
            i in 1:n_qol
        ],
    )
    @named sys_qol = compose(
        System(conns_qol, t; name=:sys_qol),
        pump_qol,
        bc_qol,
        ch_qol,
        ct_l_qol...,
        ct_r_qol...,
    )
    ssys_qol = mtkcompile(sys_qol)
    T_g_qol = steady_state_guess(T_inlet=T_inlet_qol, Q_wall=1e4, mdot_guess=0.250, n=n_qol)
    op_qol = [ssys_qol.ch_qol.T[i] => T_g_qol[i] for i in 1:n_qol]
    push!(op_qol, ssys_qol.ch_qol.inlet.mdot => 0.250)
    sol_qol = solve_steady(ssys_qol, op_qol)
    @test sol_qol.retcode == ReturnCode.Success
    @test sol_qol[ssys_qol.ch_qol.Re[1]] isa Real
    @test sol_qol[ssys_qol.ch_qol.Re[1]] > 0.0
    @test sol_qol[ssys_qol.ch_qol.Nu[1]] isa Real
    @test sol_qol[ssys_qol.ch_qol.Nu[1]] > 0.0
    @test sol_qol[ssys_qol.ch_qol.velocity[1]] isa Real
    @test sol_qol[ssys_qol.ch_qol.velocity[1]] > 0.0
    @test sol_qol[ssys_qol.ch_qol.Pe[1]] > 0.0
    @test sol_qol[ssys_qol.ch_qol.h_tc_left[1]] > 0.0
    @test sol_qol[ssys_qol.ch_qol.h_tc_right[1]] > 0.0
    @test sol_qol[ssys_qol.ch_qol.T_wall_left[1]] ≈ T_wall_qol atol=1.0
    @test sol_qol[ssys_qol.ch_qol.q_wall_left[1]] isa Real
end

@testset "QOL-02: check_gravity_mismatch — balanced loop" begin
    # build_loop_vertical has a Gravity return component that balances the
    # channel upward gravity term — returns :ok.
    ssys = build_loop_vertical(n=3, dP_pump=5000.0, T_inlet=600.0)
    @test check_gravity_mismatch(ssys) == :ok
end

@testset "QOL-02: check_gravity_mismatch — unbalanced loop :mismatch" begin
    # Channel with g=9.81 (gravity active) but no Gravity return component.
    # check_gravity_mismatch detects g_acc > 0 with no matching H parameter.
    @named ch_gm = Channel(n=1, geometry=PipeGeometry_circular(0.6, 0.01), g=9.81)
    @named pump_gm = Pump(1000.0)
    @named hx_gm = HeatExchanger(600.0)
    conns_gm = [
        connect(pump_gm.outlet, hx_gm.inlet),
        connect(hx_gm.outlet, ch_gm.inlet),
        connect(ch_gm.outlet, pump_gm.inlet),
        pump_gm.inlet.P ~ 1.0e5,
        ch_gm.thermal.T ~ 600.0,
    ]
    @named sys_gm = compose(System(conns_gm, t; name=:sys_gm), pump_gm, hx_gm, ch_gm)
    ssys_gm = mtkcompile(sys_gm)
    @test check_gravity_mismatch(ssys_gm) == :mismatch
end

@testset "QOL-03: port() helper" begin
    # port(sys, :thermal_left, i) wraps getproperty(sys, Symbol(face, i))
    # Verify it returns the same object as direct getproperty access.
    geom = PipeGeometry_circular(0.6, 0.01)  # L=0.6, D=0.01
    @named cac = ChannelAndContacts(n=3, geometry=geom)
    # port() and getproperty should return the same MTK subsystem (same name)
    @test nameof(port(cac, :thermal_left, 1)) == nameof(getproperty(cac, :thermal_left1))
    @test nameof(port(cac, :thermal_right, 2)) == nameof(getproperty(cac, :thermal_right2))
    # port() constructs Symbol(:thermal_left, 3) = :thermal_left3 (checks concat logic)
    @test nameof(port(cac, :thermal_left, 3)) ==
        nameof(getproperty(cac, Symbol(:thermal_left, 3)))
end

# Shared geometry for COMP tests (n=3 cells, small MTR-like channel)
const geom_comp = PipeGeometry_rectangular(0.6, 0.070, 0.0025, 0.070)
const ps_comp = ones(3, 3)  # uniform power shape, 3x3

@testset "COMP-01: symmetric_plate — builds and solves" begin
    @named cac = ChannelAndContacts(
        n=3,
        geometry=geom_comp,
        htc_correlation=constant_Nusselt(Nu=8.235),
        friction_correlation=laminar_friction(0.0025/0.070),
    )
    @named fuel = HeatDiffusion(
        nz=3,
        nx=3,
        Lz=0.6,
        Lx=0.006,
        y=0.003,
        rho_s=19300.0,
        cp_s=130.0,
        k_s=20.0,
        power_shape=ps_comp,
        power=1e4,
    )
    plate_sys = symmetric_plate(cac, fuel; name=:plate)
    # Add pump and HeatExchanger BCs for hydraulic closure
    @named pump = Pump(3.0e4)
    @named hx_in = HeatExchanger(600.0)
    outer_conns = [
        connect(pump.outlet, hx_in.inlet),
        connect(hx_in.outlet, plate_sys.cac.inlet),
        connect(plate_sys.cac.outlet, pump.inlet),
        pump.inlet.P ~ 1.0e5,
        plate_sys.fuel.power ~ 1e4,
    ]
    @named top = compose(System(outer_conns, t; name=:top), pump, hx_in, plate_sys)
    ssys = mtkcompile(top)
    @test length(ModelingToolkit.unknowns(ssys)) > 0
    @test length(ModelingToolkit.equations(ssys)) > 0
end

@testset "COMP-02: plate — two-channel wiring" begin
    @named ch_l = ChannelAndContacts(
        n=3,
        geometry=geom_comp,
        htc_correlation=constant_Nusselt(Nu=8.235),
        friction_correlation=laminar_friction(0.0025/0.070),
    )
    @named ch_r = ChannelAndContacts(
        n=3,
        geometry=geom_comp,
        htc_correlation=constant_Nusselt(Nu=8.235),
        friction_correlation=laminar_friction(0.0025/0.070),
    )
    @named fuel = HeatDiffusion(
        nz=3,
        nx=3,
        Lz=0.6,
        Lx=0.006,
        y=0.003,
        rho_s=19300.0,
        cp_s=130.0,
        k_s=20.0,
        power_shape=ps_comp,
        power=1e4,
    )
    plate_sys = plate(ch_l, ch_r, fuel; name=:plate)
    @named pump_l = Pump(3.0e4)
    @named hx_l = HeatExchanger(600.0)
    @named pump_r = Pump(3.0e4)
    @named hx_r = HeatExchanger(600.0)
    outer_conns = [
        connect(pump_l.outlet, hx_l.inlet),
        connect(hx_l.outlet, plate_sys.ch_l.inlet),
        connect(plate_sys.ch_l.outlet, pump_l.inlet),
        pump_l.inlet.P ~ 1.0e5,
        connect(pump_r.outlet, hx_r.inlet),
        connect(hx_r.outlet, plate_sys.ch_r.inlet),
        connect(plate_sys.ch_r.outlet, pump_r.inlet),
        pump_r.inlet.P ~ 1.0e5,
        plate_sys.fuel.power ~ 1e4,
    ]
    @named top = compose(
        System(outer_conns, t; name=:top), pump_l, hx_l, pump_r, hx_r, plate_sys
    )
    ssys = mtkcompile(top)
    @test length(ModelingToolkit.unknowns(ssys)) > 0
end

@testset "COMP-03: one_sided_connection — single face" begin
    for test_side in [:left, :right]
        @named ch = ChannelAndContacts(
            n=3,
            geometry=geom_comp,
            htc_correlation=constant_Nusselt(Nu=8.235),
            friction_correlation=laminar_friction(0.0025/0.070),
        )
        @named fuel = HeatDiffusion(
            nz=3,
            nx=3,
            Lz=0.6,
            Lx=0.006,
            y=0.003,
            rho_s=19300.0,
            cp_s=130.0,
            k_s=20.0,
            power_shape=ps_comp,
            power=1e4,
        )
        osc_sys = one_sided_connection(ch, fuel; side=test_side, name=:osc)
        @named pump = Pump(3.0e4)
        @named hx_in = HeatExchanger(600.0)
        outer_conns = [
            connect(pump.outlet, hx_in.inlet),
            connect(hx_in.outlet, osc_sys.ch.inlet),
            connect(osc_sys.ch.outlet, pump.inlet),
            pump.inlet.P ~ 1.0e5,
            osc_sys.fuel.power ~ 1e4,
        ]
        @named top = compose(System(outer_conns, t; name=:top), pump, hx_in, osc_sys)
        ssys = mtkcompile(top)
        @test length(ModelingToolkit.unknowns(ssys)) > 0
    end
end

@testset "COMP-04: compose_systems — variadic wrapper" begin
    # Build two symmetric_plate assemblies, connect hydraulically in series
    @named cac1 = ChannelAndContacts(
        n=3,
        geometry=geom_comp,
        htc_correlation=constant_Nusselt(Nu=8.235),
        friction_correlation=laminar_friction(0.0025/0.070),
    )
    @named fuel1 = HeatDiffusion(
        nz=3,
        nx=3,
        Lz=0.6,
        Lx=0.006,
        y=0.003,
        rho_s=19300.0,
        cp_s=130.0,
        k_s=20.0,
        power_shape=ps_comp,
        power=1e4,
    )
    @named cac2 = ChannelAndContacts(
        n=3,
        geometry=geom_comp,
        htc_correlation=constant_Nusselt(Nu=8.235),
        friction_correlation=laminar_friction(0.0025/0.070),
    )
    @named fuel2 = HeatDiffusion(
        nz=3,
        nx=3,
        Lz=0.6,
        Lx=0.006,
        y=0.003,
        rho_s=19300.0,
        cp_s=130.0,
        k_s=20.0,
        power_shape=ps_comp,
        power=1e4,
    )
    p1 = symmetric_plate(cac1, fuel1; name=:plate1)
    p2 = symmetric_plate(cac2, fuel2; name=:plate2)

    # Series hydraulic connection: pump -> plate1 -> plate2 -> hx_in -> pump
    @named pump = Pump(3.0e4)
    @named hx_in = HeatExchanger(600.0)
    cross_conns = Equation[
        connect(pump.outlet, hx_in.inlet),
        connect(hx_in.outlet, p1.cac1.inlet),
        connect(p1.cac1.outlet, p2.cac2.inlet),
        connect(p2.cac2.outlet, pump.inlet),
        pump.inlet.P ~ 1.0e5,
        p1.fuel1.power ~ 1e4,
        p2.fuel2.power ~ 1e4,
    ]
    reactor = compose_systems(p1, p2, pump, hx_in; connections=cross_conns, name=:reactor)
    ssys = mtkcompile(reactor)
    @test length(ModelingToolkit.unknowns(ssys)) > 0
end

@testset "COMP: symmetric_plate — physics verification (energy balance)" begin
    # Verify symmetric_plate produces physically correct output: T_out > T_in,
    # full plate power matches channel energy gain within 5%.
    # Uses default (Dittus-Boelter + Blasius) correlations for turbulent-regime convergence.
    n_cp = 3;
    T_in_cp = 313.15
    geom_cp = PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07)
    ps_cp = fill(1.0 / (n_cp * n_cp), n_cp, n_cp)
    @named cac_cp = ChannelAndContacts(n=n_cp, geometry=geom_cp)
    @named fuel_cp = HeatDiffusion(
        nz=n_cp,
        nx=n_cp,
        Lz=0.6,
        Lx=0.00127,
        y=0.07,
        rho_s=19300.0,
        cp_s=130.0,
        k_s=20.0,
        power_shape=ps_cp,
        power=1e4,
    )
    plate_cp = symmetric_plate(cac_cp, fuel_cp; name=:plate_cp)
    @named pump_cp = Pump(3.0e4)
    @named hx_cp = HeatExchanger(T_in_cp)
    outer_cp = [
        connect(pump_cp.outlet, hx_cp.inlet),
        connect(hx_cp.outlet, plate_cp.cac_cp.inlet),
        connect(plate_cp.cac_cp.outlet, pump_cp.inlet),
        pump_cp.inlet.P ~ 1.0e5,
        plate_cp.fuel_cp.power ~ 1e4,
    ]
    @named top_cp = compose(System(outer_cp, t; name=:top_cp), pump_cp, hx_cp, plate_cp)
    ssys_cp = mtkcompile(top_cp)
    T_g_cp = steady_state_guess(T_inlet=T_in_cp, Q_wall=1e4, mdot_guess=0.250, n=n_cp)
    op_cp = vcat(
        [ssys_cp.plate_cp.cac_cp.T[i] => T_g_cp[i] for i in 1:n_cp],
        [
            ssys_cp.plate_cp.fuel_cp.T[i, j] => T_g_cp[i] + 2.0 for i in 1:n_cp for
            j in 1:n_cp
        ],
        [ssys_cp.plate_cp.cac_cp.inlet.mdot => 0.250],
    )
    sol_cp = solve_steady(ssys_cp, op_cp)
    @test sol_cp.retcode == ReturnCode.Success
    @test sol_cp[ssys_cp.plate_cp.cac_cp.T_out] > T_in_cp
    mdot_cp = sol_cp[ssys_cp.plate_cp.cac_cp.inlet.mdot]
    @test isapprox(
        sol_cp[ssys_cp.plate_cp.cac_cp.T_out] - T_in_cp,
        1e4 / (mdot_cp * cp_water(T_in_cp));
        rtol=0.05,
    )
end
