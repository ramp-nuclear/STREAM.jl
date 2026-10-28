using Test
using ModelingToolkit
using OrdinaryDiffEq, SteadyStateDiffEq
using STREAM
using STREAM.Assemblies
using STREAM.Components
using STREAM.Components: Channel  # explicit: Base.Channel also exists

@testset "Integration Tests — Pluggable Correlations in Solved Systems" begin
    @testset "HTC.constant_Nusselt integration — Nu≈8.235 in solution" begin
        n = 3;
        T_inlet = 40.0;
        T_wall = 100.0;
        dP_pump = 3.0e4
        geom = Duct(0.6, Circular(0.01))

        @named pump = Pump(dP_pump)
        @named cac = ChannelAndContacts(
            n=n, geometry=geom, htc=HTC.ConstantNusselt(; Nu=8.235)
        )
        @named bc = HeatExchanger(T_inlet)
        @named wall = ConstantTemperature(T_wall; n=n)
        conns = [
            inseries(pump, bc, cac, pump),
            faces((wall, :thermal) => (cac, :thermal_outer)),
            pump.inlet.p ~ 1.0e5,
        ]
        @mtkcompile ssys = assembly(conns, pump, bc, cac, wall)
        sol = solve_steady(ssys)

        @test sol.retcode == ReturnCode.Success
        @test all(isapprox.(sol[ssys.cac.Nu_outer], 8.235, rtol=1e-4))
    end

    @testset "Friction.rectangular_laminar integration — dP > 0 in solution" begin
        n = 3;
        T_inlet = 40.0;
        T_wall = 100.0
        geom = Duct(0.6, Rectangular(0.07, 0.00127))

        @named pump = Pump(30.0)
        @named cac = ChannelAndContacts(
            n=n,
            geometry=geom,
            htc=HTC.ConstantNusselt(; Nu=8.235),
            darcy=Friction.RectangularLaminar(),
        )
        @named bc = HeatExchanger(T_inlet)
        @named ct_l = ConstantTemperature(T_wall; n=n)
        @named ct_r = ConstantTemperature(T_wall; n=n)
        conns = [
            inseries(pump, bc, cac, pump),
            faces(
                (ct_l, :thermal) => (cac, :thermal_left),
                (ct_r, :thermal) => (cac, :thermal_right),
            ),
            pump.inlet.p ~ 1.0e5,
        ]
        @mtkcompile ssys = assembly(conns, pump, bc, cac, ct_l, ct_r)
        sol = solve_steady(ssys)

        @test sol.retcode == ReturnCode.Success
        @test sol[ssys.cac.dP] > 0.0
        # Re should be in laminar regime
        @test sol[ssys.cac.Re[1]] < 2300.0

        # Magnitude check: the solved dP must equal the friction correlation evaluated at
        # the solved state, not just be positive. The channel sets dP = sum_i dp[i] (steady
        # momentum balance with inlet.p - outlet.p), and per cell (no gravity, g=0):
        #   dp[i] = f(Re[i]) * ṁ*|ṁ|/(2*rho(T[i])*A^2) * (dz/Dh)
        # with f = 64/(Re*K_R) the laminar rectangular factor. Reconstruct that sum here
        # from the solved Re[i] and T[i] and the same friction closure the channel uses, so
        # a 2x-wrong friction magnitude fails. rtol=1e-6: pure arithmetic re-evaluation of
        # the same closed form on the converged state, only float round-off differs.
        f_lam(Re) = Friction.rectangular_laminar(Re, aspect_ratio(geom))
        A = flow_area(geom)
        Dh = hydraulic_diameter(geom)
        dz = geom.L / n
        ṁ_sol = sol[ssys.cac.inlet.ṁ]
        dP_expected = sum(
            let
                Re_i = sol[ssys.cac.Re[i]]
                T_i = sol[ssys.cac.T[i]]
                Friction.darcy_weisbach_dp(ṁ_sol, ρ(H2O, T_i), f_lam(Re_i), dz, Dh, A)
            end for i in 1:n
        )
        @test isapprox(sol[ssys.cac.dP], dP_expected; rtol=1e-6)
    end

    @testset "regime switching in a solved loop — laminar and turbulent branches" begin
        # One loop, solved at a low pump head that keeps every cell laminar and again at a
        # high head that makes every cell turbulent. The head is a parameter of the pump,
        # so both solves share one compiled system.
        n = 3
        T_inlet = 40.0
        T_wall = 100.0
        geom = Duct(0.6, Rectangular(0.07, 0.00127))
        htc_rd = HTC.RegimeDependent(;
            laminar=HTC.ConstantNusselt(; Nu=8.235),
            turbulent=HTC.DittusBoelter(),
            re_bounds=(2000.0, 5000.0),
        )
        friction_rd = Friction.RegimeDependent(;
            laminar=Re -> Friction.rectangular_laminar(Re, aspect_ratio(geom)),
            turbulent=Friction.blasius,
            re_bounds=(2000.0, 5000.0),
        )
        dP_lam = 30.0
        dP_turb = 3.0e4

        @named pump = Pump(dP_lam)
        @named cac = ChannelAndContacts(n=n, geometry=geom, htc=htc_rd, darcy=friction_rd)
        @named bc = HeatExchanger(T_inlet)
        @named ct_l = ConstantTemperature(T_wall; n=n)
        @named ct_r = ConstantTemperature(T_wall; n=n)
        conns = [
            inseries(pump, bc, cac, pump),
            faces((ct_l, :thermal) => (cac, :thermal_left), (ct_r, :thermal) => (cac, :thermal_right)),
            pump.inlet.p ~ 1.0e5,
        ]
        @mtkcompile ssys = assembly(conns, pump, bc, cac, ct_l, ct_r)
        sol_lam = solve_steady(ssys)
        sol_turb = solve_steady(ssys, [ssys.pump.dP_pump => dP_turb])
        @test sol_lam.retcode == ReturnCode.Success
        @test sol_turb.retcode == ReturnCode.Success
        @test sol_lam[ssys.cac.Re[1]] < 2300.0
        @test sol_turb[ssys.cac.Re[1]] > 2300.0

        # Magnitude check: confirm the regime_dependent closure drove the solved dP through
        # the branch each Reynolds number selects. Rebuild
        # dP = sum_i f(Re[i]) * ṁ*|ṁ|/(2*rho(T[i])*A^2) * (dz/Dh) with friction_rd itself (the
        # closure the channel evaluates), so a wrong branch or a 2x factor fails. rtol=1e-6:
        # same-form arithmetic on the converged state.
        A = flow_area(geom)
        Dh = hydraulic_diameter(geom)
        dz = geom.L / n
        function dP_rebuilt(sol)
            ṁ = sol[ssys.cac.inlet.ṁ]
            return sum(1:n) do i
                T_i = sol[ssys.cac.T[i]]
                f = friction_rd(T_i, T_i, ṁ, H2O, geom)
                Friction.darcy_weisbach_dp(ṁ, ρ(H2O, T_i), f, dz, Dh, A)
            end
        end
        # Every cell sits in the branch its solve is meant to exercise.
        @test all(<(2300.0), sol_lam[ssys.cac.Re])
        @test all(>(2300.0), sol_turb[ssys.cac.Re])
        @test isapprox(sol_lam[ssys.cac.dP], dP_rebuilt(sol_lam); rtol=1e-6)
        @test isapprox(sol_turb[ssys.cac.dP], dP_rebuilt(sol_turb); rtol=1e-6)
        # Above the band friction_rd must equal Blasius, not the laminar rectangular factor.
        ṁ_turb = sol_turb[ssys.cac.inlet.ṁ]
        for i in 1:n
            T_i, Re_i = sol_turb[ssys.cac.T[i]], sol_turb[ssys.cac.Re[i]]
            @test isapprox(friction_rd(T_i, T_i, ṁ_turb, H2O, geom), Friction.blasius(Re_i); rtol=1e-12)
        end
    end
end

@testset "HTC.Elenbaas Natural Convection" begin
    @testset "HTC.elenbaas_nusselt limiting cases" begin
        @test isapprox(HTC.elenbaas_nusselt(0.0, 0.00254, 0.6), 0.0; atol=1e-10)
        Nu_large = HTC.elenbaas_nusselt(1e6, 0.00254, 0.6)
        @test Nu_large > 0.0
        @test Nu_large > HTC.elenbaas_nusselt(1e4, 0.00254, 0.6)
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

        Nu_val = HTC.elenbaas_nusselt(Ra_val, b, L_h)
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

@testset "HTC.mcadams_scb_heat_flux" begin
    # Python STREAM's McAdams_SCB_heat_flux.
    @test HTC.mcadams_scb_heat_flux(100.0, 120.0) ≈ 237730.12702161702 rtol = 1e-12
    @test HTC.mcadams_scb_heat_flux(100.0, 130.0) ≈ 1137094.2996038366 rtol = 1e-12
    @test HTC.mcadams_scb_heat_flux(100.0, 100.0) == 0.0
    @test HTC.mcadams_scb_heat_flux(100.0, 90.0) == 0.0
end

@testset "HTC.rohsenow_scb_heat_flux" begin
    # Python STREAM's Bergles_Rohsenhow_SCB_heat_flux on saturated water.
    sat17 = H2O(Tsat(H2O, 1.7e5), 1.7e5)
    @test HTC.rohsenow_scb_heat_flux(120.0, sat17) ≈ 26177.759451978258 rtol = 1e-8
    @test HTC.rohsenow_scb_heat_flux(125.0, sat17) ≈ 229086.82394250282 rtol = 1e-8
    sat20 = H2O(Tsat(H2O, 2e5), 2e5)
    @test HTC.rohsenow_scb_heat_flux(130.0, sat20) ≈ 260672.44841443186 rtol = 1e-8
    # No boiling at or below saturation.
    @test HTC.rohsenow_scb_heat_flux(sat17.Tsat, sat17) == 0.0
    @test HTC.rohsenow_scb_heat_flux(100.0, sat17) == 0.0
end

@testset "HTC.regime_dependent_q_scb blends across the transition band" begin
    q_scb = HTC.regime_dependent_q_scb(; re_bounds=(2000.0, 5000.0))
    sat = H2O(Tsat(H2O, 1.7e5), 1.7e5)
    # Python STREAM's regime_dependent_q_scb at a 125 °C wall.
    @test q_scb(125.0, sat, 1000.0) ≈ 229086.82394250282 rtol = 1e-8
    @test q_scb(125.0, sat, 3500.0) ≈ 122057.77385754562 rtol = 1e-8
    @test q_scb(125.0, sat, 8000.0) ≈ 15028.723772588424 rtol = 1e-8
    # The two ends are the two correlations.
    @test q_scb(125.0, sat, 1000.0) == HTC.rohsenow_scb_heat_flux(125.0, sat)
    @test q_scb(125.0, sat, 8000.0) == HTC.mcadams_scb_heat_flux(sat.Tsat, 125.0)
end

@testset "HTC.marco_han_nusselt" begin
    # Reference values from Python STREAM laminar.py doctest
    @test HTC.marco_han_nusselt(0.0) == 8.235
    @test isapprox(HTC.marco_han_nusselt(0.2), 5.991134842079999; rtol=1e-10)

    # ar=0 to ar=0.5: Nu decreases (thin gap to moderate aspect ratio)
    @test HTC.marco_han_nusselt(0.0) > HTC.marco_han_nusselt(0.5)

    # ar=1.0 (square duct): positive Nu
    @test HTC.marco_han_nusselt(1.0) > 0.0
end

@testset "Friction.turbulent (Colebrook-White)" begin
    # Reference values from Python STREAM friction.py doctest
    @test isapprox(Friction.turbulent(4e3), 0.039804935964641644; rtol=1e-10)
    @test isapprox(Friction.turbulent(4e3, 0.1), 0.10560870441248855; rtol=1e-10)
    @test isapprox(Friction.turbulent(1e6), 0.011649393290640643; rtol=1e-10)

    # Re <= 0 guard
    @test Friction.turbulent(5.0) == 0.0
    @test Friction.turbulent(0.0) == 0.0
    @test Friction.turbulent(-1.0) == 0.0

    # Smooth pipe (epsilon=0): friction decreases with Re
    @test Friction.turbulent(4e3) > Friction.turbulent(1e6)
end

@testset "HTC.fully_developed_laminar_nusselt" begin
    @testset "the two-sided heating polynomial, not Marco and Han's four-sided one" begin
        @test HTC.fully_developed_laminar_nusselt(0.0) == 8.235
        nu_02 = 8.235 * (1.0 - 1.4122*0.2 + 2.3473*0.2^2 - 2.8983*0.2^3 + 2.0629*0.2^4 -
                         0.6077*0.2^5)
        @test isapprox(HTC.fully_developed_laminar_nusselt(0.2), nu_02; rtol=1e-10)
        @test HTC.fully_developed_laminar_nusselt(0.2) != HTC.marco_han_nusselt(0.2)
    end

    @testset "the duct form reads the aspect ratio and ignores everything else" begin
        duct = Duct(1.0, Rectangular(1.0, 0.2))
        @test HTC.fully_developed_laminar_nusselt(100.0, 3.0, 126.85, 26.85, duct) ==
              HTC.fully_developed_laminar_nusselt(5000.0, 10.0, 106.85, 16.85, duct) ==
              HTC.fully_developed_laminar_nusselt(aspect_ratio(duct))
    end

    @testset "a circle has no aspect ratio, and the polynomial is not its answer" begin
        @test_throws MethodError HTC.fully_developed_laminar_nusselt(
            100.0, 3.0, 60.0, 40.0, Duct(1.0, Circular(0.01)))
    end
end

@testset "HTC.developing_laminar_nusselt" begin
    ar, x_over_Dh = 0.2, 0.3 / 0.005
    Nu_fd = HTC.fully_developed_laminar_nusselt(ar)

    @testset "near the entrance (high Re, so small x*) it transfers more heat" begin
        @test HTC.developing_laminar_nusselt(2000.0, 7.0, ar, x_over_Dh) > Nu_fd
    end

    @testset "far downstream (x* large) it settles to the fully developed value" begin
        @test isapprox(HTC.developing_laminar_nusselt(1.0, 7.0, ar, x_over_Dh), Nu_fd;
                       rtol=0.05)
    end

    @testset "the aspect ratio enters x* too, not only the final scaling" begin
        @test HTC.developing_laminar_nusselt(1000.0, 7.0, ar, x_over_Dh) !=
              HTC.developing_laminar_nusselt(1000.0, 7.0, 0.5, x_over_Dh)
    end

    @testset "the model reads x/Dh and the aspect ratio off the duct" begin
        duct = Duct(1.0, Rectangular(0.07, 0.0014))
        model = HTC.DevelopingLaminar(; develop_length=0.3)
        Re_, Pr_ = Re(H2O, 40.0, 0.01, duct), Pr(H2O, 40.0)
        @test model.nusselt(Re_, Pr_, 40.0, 40.0, duct) ≈ HTC.developing_laminar_nusselt(
            Re_, Pr_, aspect_ratio(duct), 0.3 / hydraulic_diameter(duct))
    end
end

@testset "laminar HTC factories in compiled Channel" begin
    @testset "HTC.fully_developed_laminar_nusselt compiles in Channel" begin
        n = 5;
        T_inlet = 40.0;
        T_wall = 100.0;
        dP_pump = 10.0
        # Aspect ratio depth/width = 0.1 (a circular geom would give 1.0, a different
        # correlation point). The head keeps the flow laminar, Re ≈ 900.
        geom = Duct(0.6, Rectangular(0.05, 0.005))
        htc_fd_lam = HTC.FullyDevelopedLaminar()

        @named pump_fd = Pump(dP_pump)
        @named cac_fd = ChannelAndContacts(
            n=n,
            geometry=geom,
            htc=htc_fd_lam,
            darcy=Friction.RectangularLaminar(),
        )
        @named bc_fd = HeatExchanger(T_inlet)
        @named ct_l_fd = ConstantTemperature(T_wall; n=n)
        @named ct_r_fd = ConstantTemperature(T_wall; n=n)
        conns_fd = [
            inseries(pump_fd, bc_fd, cac_fd, pump_fd),
            faces(
                (ct_l_fd, :thermal) => (cac_fd, :thermal_left),
                (ct_r_fd, :thermal) => (cac_fd, :thermal_right),
            ),
            pump_fd.inlet.p ~ 1.0e5,
        ]
        @named sys_fd = assembly(conns_fd, pump_fd, bc_fd, cac_fd, ct_l_fd, ct_r_fd)
        # Critical assertion: mtkcompile must succeed without symbolic tracing error
        ssys_fd = @test_nowarn mtkcompile(sys_fd)
        @test ssys_fd !== nothing

        sol_fd = solve_steady(ssys_fd)
        @test sol_fd.retcode == ReturnCode.Success
    end

    @testset "HTC.developing_laminar_nusselt compiles in Channel" begin
        n = 5;
        T_inlet = 40.0;
        T_wall = 100.0;
        dP_pump = 10.0
        # Aspect ratio depth/width = 0.1, and the head keeps the flow laminar, Re ≈ 900.
        # develop_length stays mandatory.
        geom = Duct(0.6, Rectangular(0.05, 0.005))
        htc_dev_lam = HTC.DevelopingLaminar(; develop_length=0.3)

        @named pump_dev = Pump(dP_pump)
        @named cac_dev = ChannelAndContacts(
            n=n,
            geometry=geom,
            htc=htc_dev_lam,
            darcy=Friction.RectangularLaminar(),
        )
        @named bc_dev = HeatExchanger(T_inlet)
        @named ct_l_dev = ConstantTemperature(T_wall; n=n)
        @named ct_r_dev = ConstantTemperature(T_wall; n=n)
        conns_dev = [
            inseries(pump_dev, bc_dev, cac_dev, pump_dev),
            faces(
                (ct_l_dev, :thermal) => (cac_dev, :thermal_left),
                (ct_r_dev, :thermal) => (cac_dev, :thermal_right),
            ),
            pump_dev.inlet.p ~ 1.0e5,
        ]
        @named sys_dev = assembly(
            conns_dev, pump_dev, bc_dev, cac_dev, ct_l_dev, ct_r_dev
        )
        ssys_dev = @test_nowarn mtkcompile(sys_dev)
        @test ssys_dev !== nothing

        sol_dev = solve_steady(ssys_dev)
        @test sol_dev.retcode == ReturnCode.Success
    end
end

@testset "Idelchik local-loss factors — analytic high-Re limits" begin
    # Above the table's Reynolds range the closed forms apply.
    @test isapprox(STREAM.LocalLoss.sudden_expansion_factor(0.5, 1e5), (1 - 0.5)^2; rtol=1e-12)
    @test isapprox(STREAM.LocalLoss.sudden_contraction_factor(0.5, 1e5), 0.5 * (1 - 0.5)^0.75; rtol=1e-12)
    @test isapprox(STREAM.LocalLoss.sudden_expansion_factor(0.0, 1e5), 1.0; rtol=1e-12)   # full expansion
end

@testset "Idelchik local-loss factor — direction dispatch (A2>A1)" begin
    # A2 > A1: forward flow expands, reverse flow contracts.
    mu = 1.0e-3
    A1, A2 = 1.0, 2.0
    fwd = STREAM.LocalLoss.factor(3.0, A1, A2, mu)
    rev = STREAM.LocalLoss.factor(-3.0, A1, A2, mu)
    aratio = 0.5
    A = 1.0
    Dh = sqrt(A / pi)
    re = 3.0 * Dh / (A * mu)
    @test isapprox(fwd, STREAM.LocalLoss.sudden_expansion_factor(aratio, re); rtol=1e-12)
    @test isapprox(rev, STREAM.LocalLoss.sudden_contraction_factor(aratio, re); rtol=1e-12)
end

@testset "Discharge through a hole: Python's doctest values" begin
    @test LocalLoss.discharge_cd(:sharp) == 0.61
    @test LocalLoss.discharge_cd(:borda) == 0.51
    @test_throws ArgumentError LocalLoss.discharge_cd(:jagged)
    @test LocalLoss.lichtarowicz_cd(2e4, 2.0) ≈ 0.8088165976866 rtol = 1e-12
    @test LocalLoss.lichtarowicz_cd(100.0, 2.0) ≈ 0.4284155081876958 rtol = 1e-12
end
