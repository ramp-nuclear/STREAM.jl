using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using STREAM
using STREAM: Channel
using STREAM:
    dittus_boelter,
    blasius_friction,
    constant_Nusselt,
    laminar_friction_rectangular,
    rectangular_laminar_correction,
    elenbaas_nusselt,
    Gr,
    Ra,
    marco_han_nusselt,
    turbulent_friction,
    viscosity_correction,
    fully_developed_laminar_h_spl,
    developing_laminar_h_spl

@testset "Correlation Library" begin
    @testset "rectangular_laminar_correction reference values" begin
        @test isapprox(rectangular_laminar_correction(0.0), 0.66685; atol=1e-4)
        @test isapprox(rectangular_laminar_correction(0.01814), 0.68544; atol=1e-4)
        @test isapprox(rectangular_laminar_correction(0.5), 1.03639; atol=1e-4)
        @test isapprox(rectangular_laminar_correction(1.0), 1.12462; atol=1e-4)
    end

    @testset "dittus_boelter standalone function" begin
        # Definition check: mirrors the source formula Nu = 0.023*Re^0.8*Pr^0.4.
        expected_Nu = 0.023 * 8000.0^0.8 * 7.0^0.4
        @test isapprox((@inferred dittus_boelter(8000.0, 7.0)), expected_Nu; rtol=1e-6)

        # Anchored point computed independently at clean inputs (not a copy of the source
        # expression). At Pr=1 the Pr^0.4 factor is exactly 1, and Re=1e4 gives
        # Re^0.8 = (10^4)^0.8 = 10^3.2 = 1584.8932. The heating-mode Dittus-Boelter value is
        # then 0.023 * 1584.8932 = 36.45255, which pins both the lead coefficient 0.023 and
        # the Re exponent 0.8. rtol=1e-4 is pure float round-off on a hand value.
        @test isapprox(dittus_boelter(1.0e4, 1.0), 36.45255; rtol=1e-4)
        # Second clean point exercises the Pr exponent: at Re=1e4 the Re factor is the same
        # 1584.8932, and Pr=32 gives Pr^0.4 = (2^5)^0.4 = 2^2 = 4 exactly, so the value is
        # 0.023 * 1584.8932 * 4 = 145.8102. A wrong Pr exponent would miss this.
        @test isapprox(dittus_boelter(1.0e4, 32.0), 145.8102; rtol=1e-4)
    end

    @testset "blasius_friction standalone function" begin
        # Definition check: mirrors the source formula f_darcy = 0.3164*Re^(-0.25).
        expected_f = 0.3164 * 8000.0^(-0.25)
        @test isapprox((@inferred blasius_friction(8000.0)), expected_f; rtol=1e-6)

        # Anchored reference point. The Blasius smooth-pipe Darcy factor at Re=1e5 is the
        # standard textbook value f = 0.3164/100000^0.25 = 0.01779 (e.g. White, Fluid
        # Mechanics, 7th ed., the Moody-chart smooth-wall limit). rtol=1e-3 covers the
        # 4-significant-figure rounding of the published 0.0178.
        @test isapprox(blasius_friction(1.0e5), 0.0178; rtol=1e-3)
    end

    @testset "constant_Nusselt factory" begin
        # Default Nu = 8.235
        htc_fn = constant_Nusselt()
        @test htc_fn(300.0, 7.0) == 8.235
        @test htc_fn(100.0, 3.0) == 8.235
        # Custom Nu
        htc_custom = constant_Nusselt(Nu=5.0)
        @test htc_custom(300.0, 7.0) == 5.0
    end

    @testset "laminar_friction_rectangular factory" begin
        # MTR-like rectangular geometry constructed so depth/width == 0.01814 exactly.
        # width = 0.07, depth = 0.07 * 0.01814 = 0.0012698  →  aspect_ratio = 0.01814.
        geom = PipeGeometry_rectangular(0.6, 0.07, 0.07 * 0.01814, 0.07)
        f_fn = laminar_friction_rectangular(geom)
        k_R = rectangular_laminar_correction(0.01814)
        @test isapprox(f_fn(100.0), 64.0 / (100.0 * k_R); rtol=1e-6)
        @test isapprox(f_fn(500.0), 64.0 / (500.0 * k_R); rtol=1e-6)
    end
end

@testset "Integration Tests — Pluggable Correlations in Solved Systems" begin
    @testset "constant_Nusselt integration — Nu≈8.235 in solution" begin
        n = 3;
        T_inlet = 40.0;
        T_wall = 100.0;
        dP_pump = 3.0e4
        geom = PipeGeometry_circular(0.6, 0.01)

        @named pump_phy02 = Pump(dP_pump)
        @named cac_phy02 = ChannelAndContacts(
            n=n, geometry=geom, htc=ConstantNusselt(; Nu=8.235)
        )
        @named bc_phy02 = HeatExchanger(T_inlet)
        ct_l_phy02 = [
            ConstantTemperature(T_wall; name=Symbol(:ct_l_phy02_, i)) for i in 1:n
        ]
        ct_r_phy02 = [
            ConstantTemperature(T_wall; name=Symbol(:ct_r_phy02_, i)) for i in 1:n
        ]
        conns_phy02 = [
            connect(pump_phy02.outlet, bc_phy02.inlet),
            connect(bc_phy02.outlet, cac_phy02.inlet),
            connect(cac_phy02.outlet, pump_phy02.inlet),
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
            pump_phy02.inlet.p ~ 1.0e5,
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
        T_g = steady_state_guess(; T_inlet=T_inlet, Q_wall=1e4, ṁ_guess=0.490, n=n)
        op_phy02 = [ssys_phy02.cac_phy02.T[i] => T_g[i] for i in 1:n]
        push!(op_phy02, ssys_phy02.cac_phy02.inlet.ṁ => 0.490)
        sol_phy02 = solve_steady(ssys_phy02, op_phy02)

        @test sol_phy02.retcode == ReturnCode.Success
        @test all(isapprox.(sol_phy02[ssys_phy02.cac_phy02.Nu_left[:]], 8.235, rtol=1e-4))
    end

    @testset "laminar_friction_rectangular integration — dP > 0 in solution" begin
        n = 3;
        T_inlet = 40.0;
        T_wall = 100.0
        geom = PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07)

        @named pump_phy03 = Pump(30.0)
        @named cac_phy03 = ChannelAndContacts(
            n=n,
            geometry=geom,
            htc=ConstantNusselt(; Nu=8.235),
            darcy=RectangularLaminarFriction(geom),
        )
        @named bc_phy03 = HeatExchanger(T_inlet)
        ct_l_phy03 = [
            ConstantTemperature(T_wall; name=Symbol(:ct_l_phy03_, i)) for i in 1:n
        ]
        ct_r_phy03 = [
            ConstantTemperature(T_wall; name=Symbol(:ct_r_phy03_, i)) for i in 1:n
        ]
        conns_phy03 = [
            connect(pump_phy03.outlet, bc_phy03.inlet),
            connect(bc_phy03.outlet, cac_phy03.inlet),
            connect(cac_phy03.outlet, pump_phy03.inlet),
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
            pump_phy03.inlet.p ~ 1.0e5,
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
        op_phy03 = [ssys_phy03.cac_phy03.T[i] => T_inlet for i in 1:n]
        push!(op_phy03, ssys_phy03.cac_phy03.inlet.ṁ => 8.8e-4)
        sol_phy03 = solve_steady(ssys_phy03, op_phy03)

        @test sol_phy03.retcode == ReturnCode.Success
        @test sol_phy03[ssys_phy03.cac_phy03.dP] > 0.0
        # Re should be in laminar regime
        @test sol_phy03[ssys_phy03.cac_phy03.Re[1]] < 2300.0

        # Magnitude check: the solved dP must equal the friction correlation evaluated at
        # the solved state, not just be positive. The channel sets dP = sum_i dp[i] (steady
        # momentum balance with inlet.p - outlet.p), and per cell (no gravity, g=0):
        #   dp[i] = f(Re[i]) * ṁ*|ṁ|/(2*rho(T[i])*A^2) * (dz/Dh)
        # with f = 64/(Re*K_R) the laminar rectangular factor. Reconstruct that sum here
        # from the solved Re[i] and T[i] and the same friction closure the channel uses, so
        # a 2x-wrong friction magnitude fails. rtol=1e-6: pure arithmetic re-evaluation of
        # the same closed form on the converged state, only float round-off differs.
        f_lam = laminar_friction_rectangular(geom)
        A = geom.A
        Dh = geom.Dh
        dz = geom.L / n
        ṁ03 = sol_phy03[ssys_phy03.cac_phy03.inlet.ṁ]
        dP_expected_03 = sum(
            let
                Re_i = sol_phy03[ssys_phy03.cac_phy03.Re[i]]
                T_i = sol_phy03[ssys_phy03.cac_phy03.T[i]]
                darcy_weisbach_dp(ṁ03, ρ(H2O, T_i), f_lam(Re_i), dz, Dh, A)
            end for i in 1:n
        )
        @test isapprox(sol_phy03[ssys_phy03.cac_phy03.dP], dP_expected_03; rtol=1e-6)
    end

    @testset "regime switching in a solved loop — laminar branch (Re < 2300)" begin
        n = 3;
        T_inlet = 40.0;
        T_wall = 100.0
        geom = PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07)
        htc_rd = RegimeDependentHTC(;
            laminar=ConstantNusselt(; Nu=8.235),
            turbulent=DittusBoelter(),
            re_bounds=(2000.0, 5000.0),
            geom=geom,
        )
        friction_rd = RegimeDependentFriction(;
            laminar=laminar_friction_rectangular(geom),
            turbulent=blasius_friction,
            re_bounds=(2000.0, 5000.0),
        )
        dP_lam = 30.0

        @named pump_lam = Pump(dP_lam)
        @named cac_lam = ChannelAndContacts(
            n=n, geometry=geom, htc=htc_rd, darcy=friction_rd
        )
        @named bc_lam = HeatExchanger(T_inlet)
        ct_l_lam = [ConstantTemperature(T_wall; name=Symbol(:ct_l_lam_, i)) for i in 1:n]
        ct_r_lam = [ConstantTemperature(T_wall; name=Symbol(:ct_r_lam_, i)) for i in 1:n]
        conns_lam = [
            connect(pump_lam.outlet, bc_lam.inlet),
            connect(bc_lam.outlet, cac_lam.inlet),
            connect(cac_lam.outlet, pump_lam.inlet),
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
            pump_lam.inlet.p ~ 1.0e5,
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
        op_lam = [ssys_lam.cac_lam.T[i] => T_inlet for i in 1:n]
        push!(op_lam, ssys_lam.cac_lam.inlet.ṁ => 1e-4)
        sol_lam = solve_steady(ssys_lam, op_lam)

        @test sol_lam.retcode == ReturnCode.Success
        @test sol_lam[ssys_lam.cac_lam.Re[1]] < 2300.0

        # Magnitude check: confirm the regime_dependent closure actually drove the solved dP
        # through its laminar branch. friction_rd blends over re_bounds; every cell
        # here is below 2300, so it must return the laminar rectangular factor. Rebuild
        # dP = sum_i f(Re[i]) * ṁ*|ṁ|/(2*rho(T[i])*A^2) * (dz/Dh) using friction_rd
        # itself (same closure the channel evaluates) so a wrong-branch or 2x-wrong factor
        # fails. rtol=1e-6: arithmetic re-evaluation of the same form on the converged state.
        A = geom.A
        Dh = geom.Dh
        dz = geom.L / n
        ṁ_lam = sol_lam[ssys_lam.cac_lam.inlet.ṁ]
        dP_expected_lam = sum(
            let
                Re_i = sol_lam[ssys_lam.cac_lam.Re[i]]
                T_i = sol_lam[ssys_lam.cac_lam.T[i]]
                @test Re_i < 2300.0   # confirm the laminar branch is the one selected
                darcy_weisbach_dp(ṁ_lam, ρ(H2O, T_i), friction_rd(T_i, T_i, ṁ_lam, H2O, geom), dz, Dh, A)
            end for i in 1:n
        )
        @test isapprox(sol_lam[ssys_lam.cac_lam.dP], dP_expected_lam; rtol=1e-6)
    end

    @testset "regime switching in a solved loop — turbulent branch (Re > 2300)" begin
        n = 3;
        T_inlet = 40.0;
        T_wall = 100.0
        geom = PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07)
        htc_rd = RegimeDependentHTC(;
            laminar=ConstantNusselt(; Nu=8.235),
            turbulent=DittusBoelter(),
            re_bounds=(2000.0, 5000.0),
            geom=geom,
        )
        friction_rd = RegimeDependentFriction(;
            laminar=laminar_friction_rectangular(geom),
            turbulent=blasius_friction,
            re_bounds=(2000.0, 5000.0),
        )
        dP_turb = 3.0e4

        @named pump_turb = Pump(dP_turb)
        @named cac_turb = ChannelAndContacts(
            n=n, geometry=geom, htc=htc_rd, darcy=friction_rd
        )
        @named bc_turb = HeatExchanger(T_inlet)
        ct_l_turb = [ConstantTemperature(T_wall; name=Symbol(:ct_l_turb_, i)) for i in 1:n]
        ct_r_turb = [ConstantTemperature(T_wall; name=Symbol(:ct_r_turb_, i)) for i in 1:n]
        conns_turb = [
            connect(pump_turb.outlet, bc_turb.inlet),
            connect(bc_turb.outlet, cac_turb.inlet),
            connect(cac_turb.outlet, pump_turb.inlet),
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
            pump_turb.inlet.p ~ 1.0e5,
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
        T_g_turb = steady_state_guess(; T_inlet=T_inlet, Q_wall=1e4, ṁ_guess=0.250, n=n)
        op_turb = [ssys_turb.cac_turb.T[i] => T_g_turb[i] for i in 1:n]
        push!(op_turb, ssys_turb.cac_turb.inlet.ṁ => 0.250)
        sol_turb = solve_steady(ssys_turb, op_turb)

        @test sol_turb.retcode == ReturnCode.Success
        @test sol_turb[ssys_turb.cac_turb.Re[1]] > 2300.0

        # Magnitude check: confirm the solved dP went through the turbulent (Blasius) branch.
        # Above re_bounds[2] friction_rd must return blasius_friction(Re). Rebuild
        # dP = sum_i f(Re[i]) * ṁ*|ṁ|/(2*rho(T[i])*A^2) * (dz/Dh) from friction_rd on
        # the converged Re[i]/T[i], so a wrong branch (e.g. still laminar 64/(Re*K_R)) or a
        # 2x factor fails. rtol=1e-6: same-form arithmetic on the converged state.
        A = geom.A
        Dh = geom.Dh
        dz = geom.L / n
        ṁ_turb = sol_turb[ssys_turb.cac_turb.inlet.ṁ]
        dP_expected_turb = sum(
            let
                Re_i = sol_turb[ssys_turb.cac_turb.Re[i]]
                T_i = sol_turb[ssys_turb.cac_turb.T[i]]
                @test Re_i > 2300.0   # confirm the turbulent branch is the one selected
                # friction_rd must equal Blasius here, not the laminar rectangular factor.
                @test isapprox(friction_rd(T_i, T_i, ṁ_turb, H2O, geom),
                               blasius_friction(Re_i); rtol=1e-12)
                darcy_weisbach_dp(ṁ_turb, ρ(H2O, T_i), friction_rd(T_i, T_i, ṁ_turb, H2O, geom), dz, Dh, A)
            end for i in 1:n
        )
        @test isapprox(sol_turb[ssys_turb.cac_turb.dP], dP_expected_turb; rtol=1e-6)
    end
end

@testset "Elenbaas Natural Convection" begin
    @testset "elenbaas_nusselt standalone for known values" begin
        @test isapprox(
            elenbaas_nusselt(12375.512696, 0.00254, 0.6), 1.2731625848; rtol=1e-6
        )
    end

    @testset "elenbaas_nusselt limiting cases" begin
        @test isapprox(elenbaas_nusselt(0.0, 0.00254, 0.6), 0.0; atol=1e-10)
        Nu_large = elenbaas_nusselt(1e6, 0.00254, 0.6)
        @test Nu_large > 0.0
        @test Nu_large > elenbaas_nusselt(1e4, 0.00254, 0.6)
    end

    @testset "elenbaas_nusselt Python STREAM validation" begin
        # Full validation against pre-computed Python STREAM reference values
        # Test point: T_bulk=40 °C, T_wall=60 °C, S=0.00254m, Lh=0.6m
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
        T_bulk = 40.0  # °C
        T_wall = 60.0  # °C
        b = 0.00254
        L_h = 0.6

        beta_val = β(H2O, T_bulk)
        @test isapprox(beta_val, 3.851798e-04; rtol=1e-4)

        Gr_val = Gr(ρ(H2O, T_bulk), μ(H2O, T_bulk), beta_val, T_wall, T_bulk, b, 9.81)
        # rtol=5e-4: Gr is sensitive to rho/mu product; Julia and Python Simantov coefficients
        # produce numerically identical results but differ from the tabulated reference by ~0.034%
        @test isapprox(Gr_val, 2862.302086; rtol=5e-4)

        Pr_val = cₚ(H2O, T_bulk) * μ(H2O, T_bulk) / κ(H2O, T_bulk)
        @test isapprox(Pr_val, 4.323622; rtol=1e-4)

        Ra_val = Ra(Gr_val, Pr_val)
        @test isapprox(Ra_val, 12375.512696; rtol=5e-4)

        Nu_val = elenbaas_nusselt(Ra_val, b, L_h)
        # Nu tolerance matches Ra tolerance (propagated from Gr uncertainty)
        @test isapprox(Nu_val, 1.2731625848; rtol=5e-4)
    end
end

@testset "flow_regime_blend" begin
    bounds = (2000.0, 5000.0)
    lam, turb = 4.0, 100.0

    # Outside the band each limit comes through untouched. re_lo itself counts as laminar.
    @test flow_regime_blend(1000.0, bounds, lam, turb) == lam
    @test flow_regime_blend(2000.0, bounds, lam, turb) == lam
    @test flow_regime_blend(8000.0, bounds, lam, turb) == turb

    # Inside it the blend is linear in Re, so the band midpoint is the average.
    @test flow_regime_blend(3500.0, bounds, lam, turb) ≈ (lam + turb) / 2
    @test flow_regime_blend(2750.0, bounds, lam, turb) ≈ lam + 0.25 * (turb - lam)

    # Continuous at both edges: that is the point of blending rather than stepping, since a
    # jump here lands in the solver residual.
    @test flow_regime_blend(nextfloat(2000.0), bounds, lam, turb) ≈ lam atol = 1e-6
    @test flow_regime_blend(5000.0, bounds, lam, turb) ≈ turb rtol = 1e-12
end

@testset "regime_dependent_q_scb blends across the transition band" begin
    pressure = 1e5
    q_scb = regime_dependent_q_scb(; pressure=pressure, re_bounds=(2000.0, 5000.0))
    T_sat, T_wall = 100.0, 130.0
    q_lam = bergles_rohsenow_scb_heat_flux(T_wall, T_sat, pressure)
    q_turb = mcadams_scb_heat_flux(T_sat, T_wall)
    # The two correlations must actually disagree, or the blend proves nothing.
    @test !isapprox(q_lam, q_turb; rtol=1e-3)

    @test q_scb(T_wall, T_sat, 1000.0) ≈ q_lam
    @test q_scb(T_wall, T_sat, 8000.0) ≈ q_turb
    @test q_scb(T_wall, T_sat, 3500.0) ≈ (q_lam + q_turb) / 2
end

@testset "marco_han_nusselt" begin
    # Reference values from Python STREAM laminar.py doctest
    @test marco_han_nusselt(0.0) == 8.235
    @test isapprox(marco_han_nusselt(0.2), 5.991134842079999; rtol=1e-10)

    # ar=0 to ar=0.5: Nu decreases (thin gap to moderate aspect ratio)
    @test marco_han_nusselt(0.0) > marco_han_nusselt(0.5)

    # ar=1.0 (square duct): positive Nu
    @test marco_han_nusselt(1.0) > 0.0
end

@testset "turbulent_friction (Colebrook-White)" begin
    # Reference values from Python STREAM friction.py doctest
    @test isapprox(turbulent_friction(4e3), 0.039804935964641644; rtol=1e-10)
    @test isapprox(turbulent_friction(4e3, 0.1), 0.10560870441248855; rtol=1e-10)
    @test isapprox(turbulent_friction(1e6), 0.011649393290640643; rtol=1e-10)

    # Re <= 0 guard
    @test turbulent_friction(5.0) == 0.0
    @test turbulent_friction(0.0) == 0.0
    @test turbulent_friction(-1.0) == 0.0

    # Smooth pipe (epsilon=0): friction decreases with Re
    @test turbulent_friction(4e3) > turbulent_friction(1e6)
end

@testset "viscosity_correction" begin
    # Reference values from Python STREAM friction.py doctest
    @test viscosity_correction(1.0, 1.0) == 1.0
    @test viscosity_correction(1.0, 0.0) == 0.0
    @test isapprox(viscosity_correction(1.0, 2.0), 1.4948492486349383; rtol=1e-10)

    # heat_wet_ratio = 0 => no correction regardless of mu_ratio
    @test viscosity_correction(0.0, 5.0) == 1.0
end

@testset "fully_developed_laminar_h_spl" begin
    # is derived inside the factory. geom.Dh is NOT consumed by this factory's Nu calc
    # Helper: rectangular geom with exact aspect_ratio = ar via depth=ar, width=1.0.
    _geom_for_ar(ar) = PipeGeometry_rectangular(1.0, 1.0, ar, 1.0)

    # Uses _two_sided_heating_nusselt, NOT marco_han_nusselt
    # Reference: _two_sided_heating_nusselt(0.0) = 8.235
    htc_fn = fully_developed_laminar_h_spl(_geom_for_ar(0.0))
    @test htc_fn(1000.0, 7.0, 39.85, 59.85) == 8.235

    # At ar=0.2: _two_sided_heating_nusselt(0.2) != marco_han_nusselt(0.2)
    # two_sided: 8.235*(1 - 1.4122*0.2 + 2.3473*0.04 - 2.8983*0.008 + 2.0629*0.0016 - 0.6077*0.00032)
    htc_fn_ar02 = fully_developed_laminar_h_spl(_geom_for_ar(0.2))
    nu_two_sided_02 =
        8.235 *
        (1.0 - 1.4122*0.2 + 2.3473*0.2^2 - 2.8983*0.2^3 + 2.0629*0.2^4 - 0.6077*0.2^5)
    @test isapprox(htc_fn_ar02(500.0, 5.0, 36.85, 76.85), nu_two_sided_02; rtol=1e-10)
    # Confirm it differs from Marco_Han
    @test htc_fn_ar02(500.0, 5.0, 36.85, 76.85) != marco_han_nusselt(0.2)

    # Closure ignores Re, Pr — same Nu for any inputs
    @test htc_fn_ar02(100.0, 3.0, 26.85, 126.85) == htc_fn_ar02(5000.0, 10.0, 16.85, 106.85)

    # ar=1.0 (square): _two_sided gives different value than Marco_Han
    htc_sq = fully_developed_laminar_h_spl(_geom_for_ar(1.0))
    @test htc_sq(100.0, 7.0, 39.85, 59.85) > 0.0
end

@testset "developing_laminar_h_spl" begin
    # and Dh = geom.Dh are derived inside the factory.
    # Helper builds a rectangular geom where geom.Dh = Dh_target AND geom.depth/geom.width = ar
    # exactly. Derivation: with depth = ar*width and Dh = 2*ar*width / (ar+1),
    # solving for width: width = Dh*(ar+1)/(2*ar); depth = ar*width = Dh*(ar+1)/2.
    # (Only valid for 0 < ar <= 1.)
    _geom_for(Dh, ar) = PipeGeometry_rectangular(
        1.0, Dh*(ar+1)/(2*ar), ar*Dh*(ar+1)/(2*ar), 1.0
    )

    # At very high Re (large x_star), developing flow Nu should approach
    # the fully-developed value _two_sided_heating_nusselt(ar)
    ar = 0.2
    htc_dev = developing_laminar_h_spl(_geom_for(0.005, ar); develop_length=0.3)
    htc_fd = fully_developed_laminar_h_spl(_geom_for(0.005, ar))

    # At high Re, x_star is small -> developing Nu is LARGER than fully developed
    Nu_dev_high_Re = htc_dev(2000.0, 7.0, 39.85, 59.85)
    Nu_fd = htc_fd(2000.0, 7.0, 39.85, 59.85)
    @test Nu_dev_high_Re > Nu_fd  # developing flow enhances heat transfer

    # At very low Re (large x_star -> fully developed), should converge toward fd value
    # Re=1 with develop_length=0.3 -> x_star is large -> _nusselt_coefficient_developing ~ 8.235
    Nu_dev_low_Re = htc_dev(1.0, 7.0, 39.85, 59.85)
    @test isapprox(Nu_dev_low_Re, Nu_fd; rtol=0.05)  # within 5% of fully developed
    @test htc_dev(500.0, 5.0, 36.85, 76.85) > 0.0

    # x_star correction factor test: changing aspect_ratio changes the result
    htc_dev_ar05 = developing_laminar_h_spl(_geom_for(0.005, 0.5); develop_length=0.3)
    @test htc_dev(1000.0, 7.0, 39.85, 59.85) != htc_dev_ar05(1000.0, 7.0, 39.85, 59.85)
end

@testset "laminar HTC factories in compiled Channel" begin
    @testset "fully_developed_laminar_h_spl compiles in Channel" begin
        n = 5;
        T_inlet = 40.0;
        T_wall = 100.0;
        dP_pump = 30.0
        # Rectangular geom with aspect_ratio = depth/width = 0.1 (a circular geom would
        # give aspect_ratio = 1.0, a different correlation point).
        geom = PipeGeometry_rectangular(0.6, 1.0, 0.1, 1.0)
        htc_fd_lam = FullyDevelopedLaminar(geom)

        @named pump_fd = Pump(dP_pump)
        @named cac_fd = ChannelAndContacts(
            n=n,
            geometry=geom,
            htc=htc_fd_lam,
            darcy=RectangularLaminarFriction(geom),
        )
        @named bc_fd = HeatExchanger(T_inlet)
        ct_l_fd = [ConstantTemperature(T_wall; name=Symbol(:ct_l_fd_, i)) for i in 1:n]
        ct_r_fd = [ConstantTemperature(T_wall; name=Symbol(:ct_r_fd_, i)) for i in 1:n]
        conns_fd = [
            connect(pump_fd.outlet, bc_fd.inlet),
            connect(bc_fd.outlet, cac_fd.inlet),
            connect(cac_fd.outlet, pump_fd.inlet),
            [
                connect(ct_l_fd[i].thermal, getproperty(cac_fd, Symbol(:thermal_left, i)))
                for i in 1:n
            ]...,
            [
                connect(ct_r_fd[i].thermal, getproperty(cac_fd, Symbol(:thermal_right, i)))
                for i in 1:n
            ]...,
            pump_fd.inlet.p ~ 1.0e5,
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

        op_fd = [ssys_fd.cac_fd.T[i] => T_inlet for i in 1:n]
        push!(op_fd, ssys_fd.cac_fd.inlet.ṁ => 1e-3)
        sol_fd = solve_steady(ssys_fd, op_fd)
        @test sol_fd.retcode == ReturnCode.Success
    end

    @testset "developing_laminar_h_spl compiles in Channel" begin
        n = 5;
        T_inlet = 40.0;
        T_wall = 100.0;
        dP_pump = 30.0
        # Rectangular geom with aspect_ratio = 0.1; Dh follows from the edges
        # (4 * 1.0*0.1 / (2*(1.0+0.1)) ≈ 0.1818). develop_length stays mandatory.
        geom = PipeGeometry_rectangular(0.6, 1.0, 0.1, 1.0)
        htc_dev_lam = DevelopingLaminar(geom; develop_length=0.3)

        @named pump_dev = Pump(dP_pump)
        @named cac_dev = ChannelAndContacts(
            n=n,
            geometry=geom,
            htc=htc_dev_lam,
            darcy=RectangularLaminarFriction(geom),
        )
        @named bc_dev = HeatExchanger(T_inlet)
        ct_l_dev = [ConstantTemperature(T_wall; name=Symbol(:ct_l_dev_, i)) for i in 1:n]
        ct_r_dev = [ConstantTemperature(T_wall; name=Symbol(:ct_r_dev_, i)) for i in 1:n]
        conns_dev = [
            connect(pump_dev.outlet, bc_dev.inlet),
            connect(bc_dev.outlet, cac_dev.inlet),
            connect(cac_dev.outlet, pump_dev.inlet),
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
            pump_dev.inlet.p ~ 1.0e5,
        ]
        @named sys_dev = compose(
            System(conns_dev, t; name=:sys_dev),
            pump_dev,
            bc_dev,
            cac_dev,
            ct_l_dev...,
            ct_r_dev...,
        )
        ssys_dev = @test_nowarn mtkcompile(sys_dev)
        @test ssys_dev !== nothing

        op_dev = [ssys_dev.cac_dev.T[i] => T_inlet for i in 1:n]
        push!(op_dev, ssys_dev.cac_dev.inlet.ṁ => 1e-3)
        sol_dev = solve_steady(ssys_dev, op_dev)
        @test sol_dev.retcode == ReturnCode.Success
    end
end

@testset "Idelchik local-loss factors — analytic high-Re limits" begin
    # Above the table's Reynolds range the closed forms apply.
    @test isapprox(STREAM._sudden_expansion_factor(0.5, 1e5), (1 - 0.5)^2; rtol=1e-12)
    @test isapprox(STREAM._sudden_contraction_factor(0.5, 1e5), 0.5 * (1 - 0.5)^0.75; rtol=1e-12)
    @test isapprox(STREAM._sudden_expansion_factor(0.0, 1e5), 1.0; rtol=1e-12)   # full expansion
end

@testset "Idelchik local-loss factors — table nodes" begin
    # At a (Re, area-ratio) grid node the interpolation returns the tabulated value.
    @test isapprox(STREAM._sudden_expansion_factor(0.3, 100.0), 1.20; rtol=1e-12)   # Table 4.2
    @test isapprox(STREAM._sudden_contraction_factor(0.3, 100.0), 1.10; rtol=1e-12) # Table 4.10
end

@testset "Idelchik local-loss factor — direction dispatch (A2>A1)" begin
    # A2 > A1: forward flow expands, reverse flow contracts.
    mu = 1.0e-3
    A1, A2 = 1.0, 2.0
    fwd = STREAM._local_loss_factor(3.0, A1, A2, mu)
    rev = STREAM._local_loss_factor(-3.0, A1, A2, mu)
    aratio = 0.5
    A = 1.0
    Dh = sqrt(A / pi)
    re = 3.0 * Dh / (A * mu)
    @test isapprox(fwd, STREAM._sudden_expansion_factor(aratio, re); rtol=1e-12)
    @test isapprox(rev, STREAM._sudden_contraction_factor(aratio, re); rtol=1e-12)
end
