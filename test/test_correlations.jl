using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using DifferentialEquations
using STREAM
import STREAM: Channel
import STREAM: dittus_boelter, blasius_friction, constant_Nusselt, laminar_friction,
               rectangular_laminar_correction, regime_dependent

# ─────────────────────────────────────────────────────────────────────────────
# Phase 14: Laminar Correlations
# PHY-02: constant_Nusselt factory
# PHY-03: rectangular_laminar_correction + laminar_friction factory
# PHY-04: regime_dependent switching wrapper
# ─────────────────────────────────────────────────────────────────────────────

@testset "PHY-02/03/04: Correlation Library" begin

@testset "PHY-03: rectangular_laminar_correction reference values" begin
    # Verified reference values from Python STREAM friction.py (2026-03-15)
    @test isapprox(rectangular_laminar_correction(0.0),     0.66685; atol=1e-4)
    @test isapprox(rectangular_laminar_correction(0.01814), 0.68544; atol=1e-4)
    @test isapprox(rectangular_laminar_correction(0.5),     1.03639; atol=1e-4)
    @test isapprox(rectangular_laminar_correction(1.0),     1.12462; atol=1e-4)
end

@testset "dittus_boelter standalone function" begin
    # 0.023 * 8000^0.8 * 7^0.4
    expected_Nu = 0.023 * 8000.0^0.8 * 7.0^0.4
    @test isapprox(dittus_boelter(8000.0, 7.0), expected_Nu; rtol=1e-6)
end

@testset "blasius_friction standalone function" begin
    # 0.3164 * 8000^(-0.25)
    expected_f = 0.3164 * 8000.0^(-0.25)
    @test isapprox(blasius_friction(8000.0), expected_f; rtol=1e-6)
end

@testset "PHY-02: constant_Nusselt factory" begin
    # Default Nu = 8.235
    htc_fn = constant_Nusselt()
    @test htc_fn(300.0, 7.0) == 8.235
    @test htc_fn(100.0, 3.0) == 8.235
    # Custom Nu
    htc_custom = constant_Nusselt(Nu=5.0)
    @test htc_custom(300.0, 7.0) == 5.0
end

@testset "PHY-03: laminar_friction factory" begin
    # MTR geometry: aspect_ratio = 0.00127/0.07 = 0.01814
    f_fn = laminar_friction(aspect_ratio=0.01814)
    k_R  = rectangular_laminar_correction(0.01814)
    @test isapprox(f_fn(100.0), 64.0 / (100.0 * k_R); rtol=1e-6)
    # Different Re
    @test isapprox(f_fn(500.0), 64.0 / (500.0 * k_R); rtol=1e-6)
end

@testset "PHY-04: regime_dependent switching" begin
    rd = regime_dependent(
        htc_laminar        = constant_Nusselt(Nu=8.235),
        htc_turbulent      = dittus_boelter,
        friction_laminar   = laminar_friction(aspect_ratio=0.01814),
        friction_turbulent = blasius_friction
    )
    # Named tuple must have :htc and :friction keys
    @test haskey(NamedTuple(pairs(rd)), :htc)
    @test haskey(NamedTuple(pairs(rd)), :friction)

    # Laminar branch (Re=100 < 2300): 4-arg interface (Re, Pr, T_bulk, T_wall)
    @test rd.htc(100.0, 7.0, 300.0, 320.0) == 8.235
    k_R = rectangular_laminar_correction(0.01814)
    @test isapprox(rd.friction(100.0), 64.0 / (100.0 * k_R); rtol=1e-6)

    # Turbulent branch (Re=8000 > 2300): 4-arg interface
    @test isapprox(rd.htc(8000.0, 7.0, 300.0, 320.0), dittus_boelter(8000.0, 7.0); rtol=1e-6)
    @test isapprox(rd.friction(8000.0), blasius_friction(8000.0);                   rtol=1e-6)
end

end  # @testset "PHY-02/03/04: Correlation Library"

# ─────────────────────────────────────────────────────────────────────────────
# Phase 14 Integration Tests: Pluggable correlations in solved systems
# PHY-02: constant_Nusselt integration — ChannelAndContacts with Nu=8.235 constant
# PHY-03: laminar_friction integration — ChannelAndContacts with laminar friction
# PHY-04: regime_dependent integration — both laminar (Re<2300) and turbulent (Re>2300) branches
# ─────────────────────────────────────────────────────────────────────────────

@testset "PHY-02/03/04: Integration Tests — Pluggable Correlations in Solved Systems" begin

# ─────────────────────────────────────────────────────────────────
# PHY-02: constant_Nusselt(Nu=8.235) plugged into ChannelAndContacts
# Solved system must return Nu≈8.235 for all cells.
# ─────────────────────────────────────────────────────────────────
@testset "PHY-02: constant_Nusselt integration — Nu≈8.235 in solution" begin
    n = 3; T_inlet = 313.15; T_wall = 373.15; dP_pump = 3.0e4
    geom = PipeGeometry_circular(0.6, 0.01)

    @named pump_phy02 = Pump(dP_pump=dP_pump)
    @named cac_phy02  = ChannelAndContacts(n=n, geometry=geom,
                                           htc_correlation=constant_Nusselt(Nu=8.235))
    @named bc_phy02   = HeatExchanger(T_bc=T_inlet)
    ct_l_phy02 = [ConstantTemperature(name=Symbol(:ct_l_phy02_, i), T=T_wall) for i in 1:n]
    ct_r_phy02 = [ConstantTemperature(name=Symbol(:ct_r_phy02_, i), T=T_wall) for i in 1:n]
    conns_phy02 = [
        connect(pump_phy02.port_out, bc_phy02.port_in),
        connect(bc_phy02.port_out, cac_phy02.port_in),
        connect(cac_phy02.port_out, pump_phy02.port_in),
        [connect(ct_l_phy02[i].thermal, getproperty(cac_phy02, Symbol(:thermal_left,  i))) for i in 1:n]...,
        [connect(ct_r_phy02[i].thermal, getproperty(cac_phy02, Symbol(:thermal_right, i))) for i in 1:n]...,
        pump_phy02.port_in.P ~ 1.0e5,
        cac_phy02.port_in.T ~ T_inlet,
    ]
    @named sys_phy02 = compose(System(conns_phy02, t; name=:sys_phy02),
                                pump_phy02, bc_phy02, cac_phy02, ct_l_phy02..., ct_r_phy02...)
    ssys_phy02 = mtkcompile(sys_phy02)
    T_g = steady_state_guess(T_inlet=T_inlet, Q_wall=1e4, mdot_guess=0.490, n=n)
    op_phy02 = [ssys_phy02.cac_phy02.T[i] => T_g[i] for i in 1:n]
    push!(op_phy02, ssys_phy02.cac_phy02.port_in.mdot => 0.490)
    sol_phy02 = solve_steady(ssys_phy02, op_phy02)

    @test sol_phy02.retcode == ReturnCode.Success
    for i in 1:n
        @test isapprox(sol_phy02[ssys_phy02.cac_phy02.Nu[i]], 8.235; atol=0.01)
    end
end

# ─────────────────────────────────────────────────────────────────
# PHY-03: laminar_friction(aspect_ratio=0.01814) plugged into ChannelAndContacts
# Solved system must return retcode==Success and dP > 0 (positive pressure drop).
# ─────────────────────────────────────────────────────────────────
@testset "PHY-03: laminar_friction integration — dP > 0 in solution" begin
    # Use MTR rectangular geometry with laminar friction for which the K_R was derived.
    # Combine constant_Nusselt (well-conditioned HTC) with laminar_friction to isolate
    # friction pluggability. Low pump dP (30 Pa) to stay firmly in laminar regime.
    # Physics: mdot = dP*rho*A*K_R*Dh^2 / (32*mu*L) ≈ 8.8e-4 kg/s at 313 K
    n = 3; T_inlet = 313.15; T_wall = 373.15
    geom = PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07)
    ar   = geom.depth / geom.width   # aspect_ratio for MTR geometry (~0.01814)

    @named pump_phy03 = Pump(dP_pump=30.0)   # 30 Pa → Re << 2300 → laminar regime
    @named cac_phy03  = ChannelAndContacts(n=n, geometry=geom,
                                           htc_correlation      = constant_Nusselt(Nu=8.235),
                                           friction_correlation = laminar_friction(aspect_ratio=ar))
    @named bc_phy03   = HeatExchanger(T_bc=T_inlet)
    ct_l_phy03 = [ConstantTemperature(name=Symbol(:ct_l_phy03_, i), T=T_wall) for i in 1:n]
    ct_r_phy03 = [ConstantTemperature(name=Symbol(:ct_r_phy03_, i), T=T_wall) for i in 1:n]
    conns_phy03 = [
        connect(pump_phy03.port_out, bc_phy03.port_in),
        connect(bc_phy03.port_out, cac_phy03.port_in),
        connect(cac_phy03.port_out, pump_phy03.port_in),
        [connect(ct_l_phy03[i].thermal, getproperty(cac_phy03, Symbol(:thermal_left,  i))) for i in 1:n]...,
        [connect(ct_r_phy03[i].thermal, getproperty(cac_phy03, Symbol(:thermal_right, i))) for i in 1:n]...,
        pump_phy03.port_in.P ~ 1.0e5,
        cac_phy03.port_in.T ~ T_inlet,
    ]
    @named sys_phy03 = compose(System(conns_phy03, t; name=:sys_phy03),
                                pump_phy03, bc_phy03, cac_phy03, ct_l_phy03..., ct_r_phy03...)
    ssys_phy03 = mtkcompile(sys_phy03)
    # Initial guess: mdot≈8.8e-4 kg/s from laminar Hagen-Poiseuille estimate at 30 Pa
    op_phy03 = [ssys_phy03.cac_phy03.T[i] => T_inlet for i in 1:n]
    push!(op_phy03, ssys_phy03.cac_phy03.port_in.mdot => 8.8e-4)
    sol_phy03 = solve_steady(ssys_phy03, op_phy03)

    @test sol_phy03.retcode == ReturnCode.Success
    @test sol_phy03[ssys_phy03.cac_phy03.dP] > 0.0
    # Re should be in laminar regime
    @test sol_phy03[ssys_phy03.cac_phy03.Re[1]] < 2300.0
end

# ─────────────────────────────────────────────────────────────────
# PHY-04: regime_dependent tested in both branches
# Low-dP (laminar, Re < 2300): Nu≈8.235; solver converges.
# High-dP (turbulent, Re > 2300): solver converges; Re > 2300.
# ─────────────────────────────────────────────────────────────────
@testset "PHY-04: regime_dependent integration — laminar branch (Re < 2300)" begin
    n = 3; T_inlet = 313.15; T_wall = 373.15
    geom = PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07)
    rd = regime_dependent(
        htc_laminar        = constant_Nusselt(Nu=8.235),
        htc_turbulent      = dittus_boelter,
        friction_laminar   = laminar_friction(aspect_ratio = geom.depth / geom.width),
        friction_turbulent = blasius_friction,
        Re_transition      = 2300.0
    )
    # Very low dP to force laminar regime
    dP_lam = 30.0   # ~30 Pa gives very low mdot -> Re << 2300

    @named pump_lam = Pump(dP_pump=dP_lam)
    @named cac_lam  = ChannelAndContacts(n=n, geometry=geom,
                                          htc_correlation      = rd.htc,
                                          friction_correlation = rd.friction)
    @named bc_lam   = HeatExchanger(T_bc=T_inlet)
    ct_l_lam = [ConstantTemperature(name=Symbol(:ct_l_lam_, i), T=T_wall) for i in 1:n]
    ct_r_lam = [ConstantTemperature(name=Symbol(:ct_r_lam_, i), T=T_wall) for i in 1:n]
    conns_lam = [
        connect(pump_lam.port_out, bc_lam.port_in),
        connect(bc_lam.port_out, cac_lam.port_in),
        connect(cac_lam.port_out, pump_lam.port_in),
        [connect(ct_l_lam[i].thermal, getproperty(cac_lam, Symbol(:thermal_left,  i))) for i in 1:n]...,
        [connect(ct_r_lam[i].thermal, getproperty(cac_lam, Symbol(:thermal_right, i))) for i in 1:n]...,
        pump_lam.port_in.P ~ 1.0e5,
        cac_lam.port_in.T ~ T_inlet,
    ]
    @named sys_lam = compose(System(conns_lam, t; name=:sys_lam),
                              pump_lam, bc_lam, cac_lam, ct_l_lam..., ct_r_lam...)
    ssys_lam = mtkcompile(sys_lam)
    # For laminar regime: very low mdot — initial guess near zero
    op_lam = [ssys_lam.cac_lam.T[i] => T_inlet for i in 1:n]
    push!(op_lam, ssys_lam.cac_lam.port_in.mdot => 1e-4)
    sol_lam = solve_steady(ssys_lam, op_lam)

    @test sol_lam.retcode == ReturnCode.Success
    @test sol_lam[ssys_lam.cac_lam.Re[1]] < 2300.0
end

@testset "PHY-04: regime_dependent integration — turbulent branch (Re > 2300)" begin
    n = 3; T_inlet = 313.15; T_wall = 373.15
    geom = PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07)
    rd = regime_dependent(
        htc_laminar        = constant_Nusselt(Nu=8.235),
        htc_turbulent      = dittus_boelter,
        friction_laminar   = laminar_friction(aspect_ratio = geom.depth / geom.width),
        friction_turbulent = blasius_friction,
        Re_transition      = 2300.0
    )
    dP_turb = 3.0e4   # standard MTR dP, gives Re >> 2300

    @named pump_turb = Pump(dP_pump=dP_turb)
    @named cac_turb  = ChannelAndContacts(n=n, geometry=geom,
                                           htc_correlation      = rd.htc,
                                           friction_correlation = rd.friction)
    @named bc_turb   = HeatExchanger(T_bc=T_inlet)
    ct_l_turb = [ConstantTemperature(name=Symbol(:ct_l_turb_, i), T=T_wall) for i in 1:n]
    ct_r_turb = [ConstantTemperature(name=Symbol(:ct_r_turb_, i), T=T_wall) for i in 1:n]
    conns_turb = [
        connect(pump_turb.port_out, bc_turb.port_in),
        connect(bc_turb.port_out, cac_turb.port_in),
        connect(cac_turb.port_out, pump_turb.port_in),
        [connect(ct_l_turb[i].thermal, getproperty(cac_turb, Symbol(:thermal_left,  i))) for i in 1:n]...,
        [connect(ct_r_turb[i].thermal, getproperty(cac_turb, Symbol(:thermal_right, i))) for i in 1:n]...,
        pump_turb.port_in.P ~ 1.0e5,
        cac_turb.port_in.T ~ T_inlet,
    ]
    @named sys_turb = compose(System(conns_turb, t; name=:sys_turb),
                               pump_turb, bc_turb, cac_turb, ct_l_turb..., ct_r_turb...)
    ssys_turb = mtkcompile(sys_turb)
    T_g_turb = steady_state_guess(T_inlet=T_inlet, Q_wall=1e4, mdot_guess=0.250, n=n)
    op_turb = [ssys_turb.cac_turb.T[i] => T_g_turb[i] for i in 1:n]
    push!(op_turb, ssys_turb.cac_turb.port_in.mdot => 0.250)
    sol_turb = solve_steady(ssys_turb, op_turb)

    @test sol_turb.retcode == ReturnCode.Success
    @test sol_turb[ssys_turb.cac_turb.Re[1]] > 2300.0
end

end  # @testset "PHY-02/03/04: Integration Tests — Pluggable Correlations in Solved Systems"
