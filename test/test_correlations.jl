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
    regime_dependent,
    elenbaas_nusselt,
    elenbaas_htc,
    Gr,
    Ra,
    Marco_Han_Nusselt,
    turbulent_friction,
    viscosity_correction,
    fully_developed_laminar_h_spl,
    developing_laminar_h_spl,
    maximal_htc

# ─────────────────────────────────────────────────────────────────────────────
# Phase 14: Laminar Correlations
# PHY-02: constant_Nusselt factory
# PHY-03: rectangular_laminar_correction + laminar_friction factory
# PHY-04: regime_dependent switching wrapper
# ─────────────────────────────────────────────────────────────────────────────

@testset "PHY-02/03/04: Correlation Library" begin
    @testset "PHY-03: rectangular_laminar_correction reference values" begin
        # Verified reference values from Python STREAM friction.py (2026-03-15)
        @test isapprox(rectangular_laminar_correction(0.0), 0.66685; atol=1e-4)
        @test isapprox(rectangular_laminar_correction(0.01814), 0.68544; atol=1e-4)
        @test isapprox(rectangular_laminar_correction(0.5), 1.03639; atol=1e-4)
        @test isapprox(rectangular_laminar_correction(1.0), 1.12462; atol=1e-4)
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
        f_fn = laminar_friction(0.01814)
        k_R = rectangular_laminar_correction(0.01814)
        @test isapprox(f_fn(100.0), 64.0 / (100.0 * k_R); rtol=1e-6)
        # Different Re
        @test isapprox(f_fn(500.0), 64.0 / (500.0 * k_R); rtol=1e-6)
    end

    @testset "PHY-04: regime_dependent switching" begin
        rd = regime_dependent(
            htc_laminar=constant_Nusselt(Nu=8.235),
            htc_turbulent=dittus_boelter,
            friction_laminar=laminar_friction(0.01814),
            friction_turbulent=blasius_friction,
        )
        # Named tuple must have :htc and :friction keys
        @test haskey(NamedTuple(pairs(rd)), :htc)
        @test haskey(NamedTuple(pairs(rd)), :friction)

        # Laminar branch (Re=100 < 2300): 4-arg interface (Re, Pr, T_bulk, T_wall)
        @test rd.htc(100.0, 7.0, 300.0, 320.0) == 8.235
        k_R = rectangular_laminar_correction(0.01814)
        @test isapprox(rd.friction(100.0), 64.0 / (100.0 * k_R); rtol=1e-6)

        # Turbulent branch (Re=8000 > 2300): 4-arg interface
        @test isapprox(
            rd.htc(8000.0, 7.0, 300.0, 320.0), dittus_boelter(8000.0, 7.0); rtol=1e-6
        )
        @test isapprox(rd.friction(8000.0), blasius_friction(8000.0); rtol=1e-6)
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
        n = 3;
        T_inlet = 313.15;
        T_wall = 373.15;
        dP_pump = 3.0e4
        geom = PipeGeometry_circular(0.6, 0.01)

        @named pump_phy02 = Pump(dP_pump)
        @named cac_phy02 = ChannelAndContacts(
            n=n, geometry=geom, htc_correlation=constant_Nusselt(Nu=8.235)
        )
        @named bc_phy02 = HeatExchanger(T_inlet)
        ct_l_phy02 = [
            ConstantTemperature(T_wall; name=Symbol(:ct_l_phy02_, i)) for i in 1:n
        ]
        ct_r_phy02 = [
            ConstantTemperature(T_wall; name=Symbol(:ct_r_phy02_, i)) for i in 1:n
        ]
        conns_phy02 = [
            connect(pump_phy02.port_out, bc_phy02.port_in),
            connect(bc_phy02.port_out, cac_phy02.port_in),
            connect(cac_phy02.port_out, pump_phy02.port_in),
            [
                connect(
                    ct_l_phy02[i].thermal, getproperty(cac_phy02, Symbol(:thermal_left, i))
                ) for i in 1:n
            ]...,
            [
                connect(
                    ct_r_phy02[i].thermal, getproperty(cac_phy02, Symbol(:thermal_right, i))
                ) for i in 1:n
            ]...,
            pump_phy02.port_in.P ~ 1.0e5,
        ]
        @named sys_phy02 = compose(
            System(conns_phy02, t; name=:sys_phy02),
            pump_phy02,
            bc_phy02,
            cac_phy02,
            ct_l_phy02...,
            ct_r_phy02...,
        )
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
    # PHY-03: laminar_friction(0.01814) plugged into ChannelAndContacts
    # Solved system must return retcode==Success and dP > 0 (positive pressure drop).
    # ─────────────────────────────────────────────────────────────────
    @testset "PHY-03: laminar_friction integration — dP > 0 in solution" begin
        # Use MTR rectangular geometry with laminar friction for which the K_R was derived.
        # Combine constant_Nusselt (well-conditioned HTC) with laminar_friction to isolate
        # friction pluggability. Low pump dP (30 Pa) to stay firmly in laminar regime.
        # Physics: mdot = dP*rho*A*K_R*Dh^2 / (32*mu*L) ≈ 8.8e-4 kg/s at 313 K
        n = 3;
        T_inlet = 313.15;
        T_wall = 373.15
        geom = PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07)
        ar = geom.depth / geom.width   # aspect_ratio for MTR geometry (~0.01814)

        @named pump_phy03 = Pump(30.0)   # 30 Pa → Re << 2300 → laminar regime
        @named cac_phy03 = ChannelAndContacts(
            n=n,
            geometry=geom,
            htc_correlation=constant_Nusselt(Nu=8.235),
            friction_correlation=laminar_friction(ar),
        )
        @named bc_phy03 = HeatExchanger(T_inlet)
        ct_l_phy03 = [
            ConstantTemperature(T_wall; name=Symbol(:ct_l_phy03_, i)) for i in 1:n
        ]
        ct_r_phy03 = [
            ConstantTemperature(T_wall; name=Symbol(:ct_r_phy03_, i)) for i in 1:n
        ]
        conns_phy03 = [
            connect(pump_phy03.port_out, bc_phy03.port_in),
            connect(bc_phy03.port_out, cac_phy03.port_in),
            connect(cac_phy03.port_out, pump_phy03.port_in),
            [
                connect(
                    ct_l_phy03[i].thermal, getproperty(cac_phy03, Symbol(:thermal_left, i))
                ) for i in 1:n
            ]...,
            [
                connect(
                    ct_r_phy03[i].thermal, getproperty(cac_phy03, Symbol(:thermal_right, i))
                ) for i in 1:n
            ]...,
            pump_phy03.port_in.P ~ 1.0e5,
        ]
        @named sys_phy03 = compose(
            System(conns_phy03, t; name=:sys_phy03),
            pump_phy03,
            bc_phy03,
            cac_phy03,
            ct_l_phy03...,
            ct_r_phy03...,
        )
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
        n = 3;
        T_inlet = 313.15;
        T_wall = 373.15
        geom = PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07)
        rd = regime_dependent(
            htc_laminar=constant_Nusselt(Nu=8.235),
            htc_turbulent=dittus_boelter,
            friction_laminar=laminar_friction(geom.depth / geom.width),
            friction_turbulent=blasius_friction,
            Re_transition=2300.0,
        )
        # Very low dP to force laminar regime
        dP_lam = 30.0   # ~30 Pa gives very low mdot -> Re << 2300

        @named pump_lam = Pump(dP_lam)
        @named cac_lam = ChannelAndContacts(
            n=n, geometry=geom, htc_correlation=rd.htc, friction_correlation=rd.friction
        )
        @named bc_lam = HeatExchanger(T_inlet)
        ct_l_lam = [ConstantTemperature(T_wall; name=Symbol(:ct_l_lam_, i)) for i in 1:n]
        ct_r_lam = [ConstantTemperature(T_wall; name=Symbol(:ct_r_lam_, i)) for i in 1:n]
        conns_lam = [
            connect(pump_lam.port_out, bc_lam.port_in),
            connect(bc_lam.port_out, cac_lam.port_in),
            connect(cac_lam.port_out, pump_lam.port_in),
            [
                connect(
                    ct_l_lam[i].thermal, getproperty(cac_lam, Symbol(:thermal_left, i))
                ) for i in 1:n
            ]...,
            [
                connect(
                    ct_r_lam[i].thermal, getproperty(cac_lam, Symbol(:thermal_right, i))
                ) for i in 1:n
            ]...,
            pump_lam.port_in.P ~ 1.0e5,
        ]
        @named sys_lam = compose(
            System(conns_lam, t; name=:sys_lam),
            pump_lam,
            bc_lam,
            cac_lam,
            ct_l_lam...,
            ct_r_lam...,
        )
        ssys_lam = mtkcompile(sys_lam)
        # For laminar regime: very low mdot — initial guess near zero
        op_lam = [ssys_lam.cac_lam.T[i] => T_inlet for i in 1:n]
        push!(op_lam, ssys_lam.cac_lam.port_in.mdot => 1e-4)
        sol_lam = solve_steady(ssys_lam, op_lam)

        @test sol_lam.retcode == ReturnCode.Success
        @test sol_lam[ssys_lam.cac_lam.Re[1]] < 2300.0
    end

    @testset "PHY-04: regime_dependent integration — turbulent branch (Re > 2300)" begin
        n = 3;
        T_inlet = 313.15;
        T_wall = 373.15
        geom = PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07)
        rd = regime_dependent(
            htc_laminar=constant_Nusselt(Nu=8.235),
            htc_turbulent=dittus_boelter,
            friction_laminar=laminar_friction(geom.depth / geom.width),
            friction_turbulent=blasius_friction,
            Re_transition=2300.0,
        )
        dP_turb = 3.0e4   # standard MTR dP, gives Re >> 2300

        @named pump_turb = Pump(dP_turb)
        @named cac_turb = ChannelAndContacts(
            n=n, geometry=geom, htc_correlation=rd.htc, friction_correlation=rd.friction
        )
        @named bc_turb = HeatExchanger(T_inlet)
        ct_l_turb = [ConstantTemperature(T_wall; name=Symbol(:ct_l_turb_, i)) for i in 1:n]
        ct_r_turb = [ConstantTemperature(T_wall; name=Symbol(:ct_r_turb_, i)) for i in 1:n]
        conns_turb = [
            connect(pump_turb.port_out, bc_turb.port_in),
            connect(bc_turb.port_out, cac_turb.port_in),
            connect(cac_turb.port_out, pump_turb.port_in),
            [
                connect(
                    ct_l_turb[i].thermal, getproperty(cac_turb, Symbol(:thermal_left, i))
                ) for i in 1:n
            ]...,
            [
                connect(
                    ct_r_turb[i].thermal, getproperty(cac_turb, Symbol(:thermal_right, i))
                ) for i in 1:n
            ]...,
            pump_turb.port_in.P ~ 1.0e5,
        ]
        @named sys_turb = compose(
            System(conns_turb, t; name=:sys_turb),
            pump_turb,
            bc_turb,
            cac_turb,
            ct_l_turb...,
            ct_r_turb...,
        )
        ssys_turb = mtkcompile(sys_turb)
        T_g_turb = steady_state_guess(T_inlet=T_inlet, Q_wall=1e4, mdot_guess=0.250, n=n)
        op_turb = [ssys_turb.cac_turb.T[i] => T_g_turb[i] for i in 1:n]
        push!(op_turb, ssys_turb.cac_turb.port_in.mdot => 0.250)
        sol_turb = solve_steady(ssys_turb, op_turb)

        @test sol_turb.retcode == ReturnCode.Success
        @test sol_turb[ssys_turb.cac_turb.Re[1]] > 2300.0
    end
end  # @testset "PHY-02/03/04: Integration Tests — Pluggable Correlations in Solved Systems"

# ─────────────────────────────────────────────────────────────────────────────
# Phase 21: Natural Convection Correlations
# NATCONV-01: elenbaas_nusselt standalone + elenbaas_htc factory
# NATCONV-02: Validation against Python STREAM reference values
# ─────────────────────────────────────────────────────────────────────────────

@testset "NATCONV-01/02: Elenbaas Natural Convection" begin
    @testset "NATCONV-01: elenbaas_nusselt standalone" begin
        # Reference: RESEARCH.md MTR-scale test point
        # Ra=12375.512696, b=0.00254m, L=0.6m
        # Expected Nu = 1.2731625848
        @test isapprox(
            elenbaas_nusselt(12375.512696, 0.00254, 0.6), 1.2731625848; rtol=1e-6
        )
    end

    @testset "NATCONV-01: elenbaas_nusselt limiting cases" begin
        # Ra -> 0: Nu -> 0 (no buoyancy)
        @test isapprox(elenbaas_nusselt(0.0, 0.00254, 0.6), 0.0; atol=1e-10)
        # Large Ra: Nu should be positive and growing
        Nu_large = elenbaas_nusselt(1e6, 0.00254, 0.6)
        @test Nu_large > 0.0
        @test Nu_large > elenbaas_nusselt(1e4, 0.00254, 0.6)
    end

    @testset "NATCONV-01: elenbaas_htc factory produces 4-arg closure" begin
        htc_fn = elenbaas_htc(b=0.00254, L=0.6, Dh=0.00254)
        # Must accept 4 args
        Nu_val = htc_fn(0.0, 4.32, 313.15, 333.15)  # Re=0 (natural conv), Pr~4.32, T_bulk=40C, T_wall=60C
        @test Nu_val > 0.0

        # T_wall = T_bulk -> dT=0 -> Nu=0
        Nu_zero = htc_fn(0.0, 4.32, 313.15, 313.15)
        @test isapprox(Nu_zero, 0.0; atol=1e-10)
    end

    @testset "NATCONV-02: elenbaas_nusselt Python STREAM validation" begin
        # Full validation against pre-computed Python STREAM reference values
        # Test point: T_bulk=40C (313.15K), T_wall=60C (333.15K), S=0.00254m, Lh=0.6m
        #
        # Python STREAM computation chain:
        #   rho   = 991.3511 kg/m^3
        #   mu    = 6.5197e-04 Pa*s
        #   cp    = 4178.9588 J/(kg*K)
        #   k     = 0.630156 W/(m*K)
        #   beta  = 3.851798e-04 1/K
        #   nu    = mu/rho = 6.5766e-07 m^2/s
        #   Gr    = beta*g*dT*Dh^3/nu^2 = 2862.302086
        #   Pr    = cp*mu/k = 4.323622
        #   Ra    = Gr*Pr = 12375.512696
        #   Nu    = (1/24)*Ra*(b/L)*(1-exp(-35*L/(Ra*b)))^0.75 = 1.2731625848
        #
        # This test reproduces the full chain using Julia functions:
        T_bulk = 40.0
        T_wall = 60.0
        b = 0.00254
        L_h = 0.6

        l = H2O(T_bulk)
        @test isapprox(l.β, 3.851798e-04; rtol=1e-4)

        ν = l.μ / l.ρ
        Gr_val = Gr(l.β, 9.81, T_wall - T_bulk, b, ν)
        # rtol=5e-4: Gr is sensitive to rho/mu product; Julia and Python Simantov coefficients
        # produce numerically identical results but differ from the tabulated reference by ~0.034%
        @test isapprox(Gr_val, 2862.302086; rtol=5e-4)

        Pr_val = l.cₚ * l.μ / l.k
        @test isapprox(Pr_val, 4.323622; rtol=1e-4)

        Ra_val = Ra(Gr_val, Pr_val)
        @test isapprox(Ra_val, 12375.512696; rtol=5e-4)

        Nu_val = elenbaas_nusselt(Ra_val, b, L_h)
        # Nu tolerance matches Ra tolerance (propagated from Gr uncertainty)
        @test isapprox(Nu_val, 1.2731625848; rtol=5e-4)
    end
end  # @testset "NATCONV-01/02: Elenbaas Natural Convection"

# ─────────────────────────────────────────────────────────────────────────────
# Phase 26: NC regime detection in regime_dependent
# NATCONV-01: regime_dependent NC kwargs — branch selection, backward compat,
#             ArgumentError on partial kwargs, @warn on Dh/g without htc_natural
# ─────────────────────────────────────────────────────────────────────────────

@testset "NATCONV-01: regime_dependent NC detection" begin
    # Setup: laminar HTC returns 4.0, turbulent returns 100.0, NC returns 999.0
    htc_lam = (Re, Pr, T_b, T_w) -> 4.0
    htc_turb = (Re, Pr, T_b, T_w) -> 100.0
    htc_nc = (Re, Pr, T_b, T_w) -> 999.0
    f_lam = (Re) -> 64.0 / Re
    f_turb = (Re) -> 0.316 * Re^(-0.25)

    # Test 1: NC branch selected when Gr/Re^2 > 1
    # Use low Re (high Gr/Re^2) and large dT to trigger NC
    rd = regime_dependent(
        htc_laminar=htc_lam,
        htc_turbulent=htc_turb,
        friction_laminar=f_lam,
        friction_turbulent=f_turb,
        htc_natural=htc_nc,
        Dh=0.01,
        g=9.81,
    )
    # At Re=10, Pr=7, T_bulk=313.15 (40C), T_wall=373.15 (100C):
    # beta ~ 3.85e-4, nu ~ 6.6e-7, Gr = beta*g*60*0.01^3/nu^2 ~ 520
    # Re^2 = 100. Gr/Re^2 ~ 5.2 > 1 => NC branch
    @test rd.htc(10.0, 7.0, 313.15, 373.15) == 999.0

    # Test 2: Forced-conv branch selected when Gr/Re^2 < 1
    # At Re=5000 (turbulent, Re^2=25e6 >> Gr): forced turb branch
    @test rd.htc(5000.0, 7.0, 313.15, 373.15) == 100.0

    # Test 3: Laminar forced at low Re when Gr/Re^2 < 1 (small dT)
    # T_wall ~ T_bulk => Gr ~ 0 => forced branch => laminar at Re=100
    @test rd.htc(100.0, 7.0, 313.15, 313.20) == 4.0

    # Test 4: Friction unchanged by NC kwargs
    @test rd.friction(100.0) == 64.0 / 100.0     # laminar
    @test rd.friction(5000.0) == 0.316 * 5000.0^(-0.25)  # turbulent

    # Test 5: Backward compat — no NC kwargs => identical to existing regime_dependent
    rd_no_nc = regime_dependent(
        htc_laminar=htc_lam,
        htc_turbulent=htc_turb,
        friction_laminar=f_lam,
        friction_turbulent=f_turb,
    )
    @test rd_no_nc.htc(100.0, 7.0, 313.15, 373.15) == 4.0   # laminar forced
    @test rd_no_nc.htc(5000.0, 7.0, 313.15, 373.15) == 100.0 # turbulent forced

    # Test 6: D-04 — htc_natural without g => ArgumentError
    @test_throws ArgumentError regime_dependent(
        htc_laminar=htc_lam,
        htc_turbulent=htc_turb,
        friction_laminar=f_lam,
        friction_turbulent=f_turb,
        htc_natural=htc_nc,
        Dh=0.01,  # g missing
    )

    # Test 7: D-03 — Dh and g without htc_natural => @warn
    @test_logs (:warn, r"NC regime will not be detected") regime_dependent(
        htc_laminar=htc_lam,
        htc_turbulent=htc_turb,
        friction_laminar=f_lam,
        friction_turbulent=f_turb,
        Dh=0.01,
        g=9.81,  # htc_natural missing
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# Phase 30: HTC & Friction Completions
# HTC-01: Marco_Han_Nusselt
# FRIC-01: turbulent_friction (Colebrook-White)
# FRIC-02: viscosity_correction
# ─────────────────────────────────────────────────────────────────────────────

@testset "HTC-01: Marco_Han_Nusselt" begin
    # Reference values from Python STREAM laminar.py doctest
    @test Marco_Han_Nusselt(0.0) == 8.235
    @test isapprox(Marco_Han_Nusselt(0.2), 5.991134842079999; rtol=1e-10)

    # ar=0 to ar=0.5: Nu decreases (thin gap to moderate aspect ratio)
    @test Marco_Han_Nusselt(0.0) > Marco_Han_Nusselt(0.5)

    # ar=1.0 (square duct): positive Nu
    @test Marco_Han_Nusselt(1.0) > 0.0
end

@testset "FRIC-01: turbulent_friction (Colebrook-White)" begin
    # Reference values from Python STREAM friction.py doctest
    @test isapprox(turbulent_friction(4e3), 0.039804935964641644; rtol=1e-10)
    @test isapprox(turbulent_friction(4e3, 0.1), 0.10560870441248855; rtol=1e-10)
    @test isapprox(turbulent_friction(1e6), 0.011649393290640643; rtol=1e-10)

    # D-08: Re <= 0 guard
    @test turbulent_friction(5.0) == 0.0
    @test turbulent_friction(0.0) == 0.0
    @test turbulent_friction(-1.0) == 0.0

    # Smooth pipe (epsilon=0): friction decreases with Re
    @test turbulent_friction(4e3) > turbulent_friction(1e6)
end

@testset "FRIC-02: viscosity_correction" begin
    # Reference values from Python STREAM friction.py doctest
    @test viscosity_correction(1.0, 1.0) == 1.0
    @test viscosity_correction(1.0, 0.0) == 0.0
    @test isapprox(viscosity_correction(1.0, 2.0), 1.4948492486349383; rtol=1e-10)

    # heat_wet_ratio = 0 => no correction regardless of mu_ratio
    @test viscosity_correction(0.0, 5.0) == 1.0
end

@testset "HTC-02: fully_developed_laminar_h_spl" begin
    # D-01: Uses _two_sided_heating_nusselt, NOT Marco_Han_Nusselt
    # Reference: _two_sided_heating_nusselt(0.0) = 8.235
    htc_fn = fully_developed_laminar_h_spl(Dh=0.005, aspect_ratio=0.0)
    @test htc_fn(1000.0, 7.0, 313.0, 333.0) == 8.235

    # At ar=0.2: _two_sided_heating_nusselt(0.2) != Marco_Han_Nusselt(0.2)
    # two_sided: 8.235*(1 - 1.4122*0.2 + 2.3473*0.04 - 2.8983*0.008 + 2.0629*0.0016 - 0.6077*0.00032)
    htc_fn_ar02 = fully_developed_laminar_h_spl(Dh=0.005, aspect_ratio=0.2)
    nu_two_sided_02 =
        8.235 *
        (1.0 - 1.4122*0.2 + 2.3473*0.2^2 - 2.8983*0.2^3 + 2.0629*0.2^4 - 0.6077*0.2^5)
    @test isapprox(htc_fn_ar02(500.0, 5.0, 310.0, 350.0), nu_two_sided_02; rtol=1e-10)
    # Confirm it differs from Marco_Han
    @test htc_fn_ar02(500.0, 5.0, 310.0, 350.0) != Marco_Han_Nusselt(0.2)

    # Closure ignores Re, Pr — same Nu for any inputs
    @test htc_fn_ar02(100.0, 3.0, 300.0, 400.0) == htc_fn_ar02(5000.0, 10.0, 290.0, 380.0)

    # ar=1.0 (square): _two_sided gives different value than Marco_Han
    htc_sq = fully_developed_laminar_h_spl(Dh=0.01, aspect_ratio=1.0)
    @test htc_sq(100.0, 7.0, 313.0, 333.0) > 0.0
end

@testset "HTC-03: developing_laminar_h_spl" begin
    # At very high Re (large x_star), developing flow Nu should approach
    # the fully-developed value _two_sided_heating_nusselt(ar)
    ar = 0.2
    htc_dev = developing_laminar_h_spl(Dh=0.005, develop_length=0.3, aspect_ratio=ar)
    htc_fd = fully_developed_laminar_h_spl(Dh=0.005, aspect_ratio=ar)

    # At high Re, x_star is small -> developing Nu is LARGER than fully developed
    Nu_dev_high_Re = htc_dev(2000.0, 7.0, 313.0, 333.0)
    Nu_fd = htc_fd(2000.0, 7.0, 313.0, 333.0)
    @test Nu_dev_high_Re > Nu_fd  # developing flow enhances heat transfer

    # At very low Re (large x_star -> fully developed), should converge toward fd value
    # Re=1 with develop_length=0.3 -> x_star is large -> _nusselt_coefficient_developing ~ 8.235
    Nu_dev_low_Re = htc_dev(1.0, 7.0, 313.0, 333.0)
    @test isapprox(Nu_dev_low_Re, Nu_fd; rtol=0.05)  # within 5% of fully developed

    # Positive for all reasonable inputs
    @test htc_dev(500.0, 5.0, 310.0, 350.0) > 0.0

    # x_star correction factor test: changing aspect_ratio changes the result
    htc_dev_ar05 = developing_laminar_h_spl(Dh=0.005, develop_length=0.3, aspect_ratio=0.5)
    @test htc_dev(1000.0, 7.0, 313.0, 333.0) != htc_dev_ar05(1000.0, 7.0, 313.0, 333.0)
end

@testset "HTC-04: maximal_htc" begin
    # max of two constant correlations
    c5 = constant_Nusselt(Nu=5.0)
    c10 = constant_Nusselt(Nu=10.0)
    htc_max = maximal_htc(c5, c10)
    @test htc_max(100.0, 7.0, 313.0, 333.0) == 10.0

    # max of three correlations
    c1 = constant_Nusselt(Nu=1.0)
    htc_max3 = maximal_htc(c1, c5, c10)
    @test htc_max3(100.0, 7.0, 313.0, 333.0) == 10.0

    # Single correlation passthrough
    htc_single = maximal_htc(c5)
    @test htc_single(100.0, 7.0, 313.0, 333.0) == 5.0

    # Works with non-constant correlations (dittus_boelter)
    htc_mixed = maximal_htc(c5, dittus_boelter)
    # At Re=100, Pr=7: dittus_boelter ~ 0.023 * 100^0.8 * 7^0.4 ~ 2.7 < 5
    @test htc_mixed(100.0, 7.0, 313.0, 333.0) == 5.0
    # At Re=10000, Pr=7: dittus_boelter ~ 0.023 * 10000^0.8 * 7^0.4 ~ 55.2 > 5
    @test htc_mixed(10000.0, 7.0, 313.0, 333.0) > 5.0
    @test isapprox(
        htc_mixed(10000.0, 7.0, 313.0, 333.0), dittus_boelter(10000.0, 7.0); rtol=1e-10
    )
end

# ─────────────────────────────────────────────────────────────────────────────
# Phase 30 in-system smoke tests
# HTC-02/03: Phase 30 laminar HTC factories plugged into a real compiled Channel
# Closes audit gap: fully_developed_laminar_h_spl and developing_laminar_h_spl
# have never been passed as htc_correlation to a Channel and mtkcompiled.
# ─────────────────────────────────────────────────────────────────────────────

@testset "HTC-02/03: Phase 30 laminar HTC factories in compiled Channel" begin
    @testset "HTC-02: fully_developed_laminar_h_spl compiles in Channel" begin
        n = 5;
        T_inlet = 313.15;
        T_wall = 373.15;
        dP_pump = 30.0
        geom = PipeGeometry_circular(0.6, 0.01)
        htc_fn = fully_developed_laminar_h_spl(Dh=0.01, aspect_ratio=0.1)

        @named pump_fd = Pump(dP_pump)
        @named cac_fd = ChannelAndContacts(
            n=n,
            geometry=geom,
            htc_correlation=htc_fn,
            friction_correlation=laminar_friction(0.1),
        )
        @named bc_fd = HeatExchanger(T_inlet)
        ct_l_fd = [ConstantTemperature(T_wall; name=Symbol(:ct_l_fd_, i)) for i in 1:n]
        ct_r_fd = [ConstantTemperature(T_wall; name=Symbol(:ct_r_fd_, i)) for i in 1:n]
        conns_fd = [
            connect(pump_fd.port_out, bc_fd.port_in),
            connect(bc_fd.port_out, cac_fd.port_in),
            connect(cac_fd.port_out, pump_fd.port_in),
            [
                connect(ct_l_fd[i].thermal, getproperty(cac_fd, Symbol(:thermal_left, i)))
                for i in 1:n
            ]...,
            [
                connect(ct_r_fd[i].thermal, getproperty(cac_fd, Symbol(:thermal_right, i)))
                for i in 1:n
            ]...,
            pump_fd.port_in.P ~ 1.0e5,
        ]
        @named sys_fd = compose(
            System(conns_fd, t; name=:sys_fd),
            pump_fd,
            bc_fd,
            cac_fd,
            ct_l_fd...,
            ct_r_fd...,
        )
        # Critical assertion: mtkcompile must succeed without symbolic tracing error
        ssys_fd = @test_nowarn mtkcompile(sys_fd)
        @test ssys_fd !== nothing

        # Solve to verify the system is also numerically tractable
        op_fd = [ssys_fd.cac_fd.T[i] => T_inlet for i in 1:n]
        push!(op_fd, ssys_fd.cac_fd.port_in.mdot => 1e-3)
        sol_fd = solve_steady(ssys_fd, op_fd)
        @test sol_fd.retcode == ReturnCode.Success
    end

    @testset "HTC-03: developing_laminar_h_spl compiles in Channel" begin
        n = 5;
        T_inlet = 313.15;
        T_wall = 373.15;
        dP_pump = 30.0
        geom = PipeGeometry_circular(0.6, 0.01)
        htc_fn = developing_laminar_h_spl(Dh=0.01, develop_length=0.3, aspect_ratio=0.1)

        @named pump_dev = Pump(dP_pump)
        @named cac_dev = ChannelAndContacts(
            n=n,
            geometry=geom,
            htc_correlation=htc_fn,
            friction_correlation=laminar_friction(0.1),
        )
        @named bc_dev = HeatExchanger(T_inlet)
        ct_l_dev = [ConstantTemperature(T_wall; name=Symbol(:ct_l_dev_, i)) for i in 1:n]
        ct_r_dev = [ConstantTemperature(T_wall; name=Symbol(:ct_r_dev_, i)) for i in 1:n]
        conns_dev = [
            connect(pump_dev.port_out, bc_dev.port_in),
            connect(bc_dev.port_out, cac_dev.port_in),
            connect(cac_dev.port_out, pump_dev.port_in),
            [
                connect(
                    ct_l_dev[i].thermal, getproperty(cac_dev, Symbol(:thermal_left, i))
                ) for i in 1:n
            ]...,
            [
                connect(
                    ct_r_dev[i].thermal, getproperty(cac_dev, Symbol(:thermal_right, i))
                ) for i in 1:n
            ]...,
            pump_dev.port_in.P ~ 1.0e5,
        ]
        @named sys_dev = compose(
            System(conns_dev, t; name=:sys_dev),
            pump_dev,
            bc_dev,
            cac_dev,
            ct_l_dev...,
            ct_r_dev...,
        )
        # Critical assertion: mtkcompile must succeed without symbolic tracing error
        ssys_dev = @test_nowarn mtkcompile(sys_dev)
        @test ssys_dev !== nothing

        # Solve to verify the system is also numerically tractable
        op_dev = [ssys_dev.cac_dev.T[i] => T_inlet for i in 1:n]
        push!(op_dev, ssys_dev.cac_dev.port_in.mdot => 1e-3)
        sol_dev = solve_steady(ssys_dev, op_dev)
        @test sol_dev.retcode == ReturnCode.Success
    end
end  # @testset "HTC-02/03: Phase 30 laminar HTC factories in compiled Channel"
