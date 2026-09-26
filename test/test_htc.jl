using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using STREAM
using STREAM.Components
using STREAM: Re, Pr

const GEOM_MTR = PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07)

@testset "HTC models" begin
    Dh, A = GEOM_MTR.Dh, GEOM_MTR.A
    T_wall, T_bulk, ṁ = 90.0, 40.0, 0.25

    @testset "property basis picks the evaluation temperature" begin
        @test HTC.property_temperature(HTC.AtFilm(), 90.0, 40.0) == 65.0
        @test HTC.property_temperature(HTC.AtBulk(), 90.0, 40.0) == 40.0

        # The basis is not cosmetic: over a 50 °C wall-to-bulk span it moves h by a
        # double-digit percentage, which is exactly the discrepancy the handle exists to
        # let a user control.
        h_film = HTC.DittusBoelter()(T_wall, T_bulk, ṁ, Dh, A, H2O)
        h_bulk = HTC.DittusBoelter(; basis=HTC.AtBulk())(T_wall, T_bulk, ṁ, Dh, A, H2O)
        @test !isapprox(h_film, h_bulk; rtol=1e-3)
        @test abs(h_film - h_bulk) / h_bulk > 0.1

        # Each is the correlation closed by hand at its own temperature.
        for (basis, T_prop) in ((HTC.AtFilm(), 65.0), (HTC.AtBulk(), 40.0))
            Nu_hand = HTC.dittus_boelter(Re(H2O, T_prop, ṁ, A, Dh), Pr(H2O, T_prop))
            h_hand = Nu_hand * κ(H2O, T_prop) / Dh
            @test HTC.DittusBoelter(; basis=basis)(T_wall, T_bulk, ṁ, Dh, A, H2O) ≈ h_hand
        end

        # With no wall-to-bulk difference the two bases have to agree.
        @test HTC.DittusBoelter()(50.0, 50.0, ṁ, Dh, A, H2O) ≈
              HTC.DittusBoelter(; basis=HTC.AtBulk())(50.0, 50.0, ṁ, Dh, A, H2O)
    end

    @testset "HTC.FromNusselt closes any correlation" begin
        # A bare (Re, Pr) correlation works: the trailing temperatures are absorbed.
        @test HTC.FromNusselt(HTC.constant_Nusselt(; Nu=10.0))(T_wall, T_bulk, ṁ, Dh, A, H2O) ≈
              10.0 * κ(H2O, HTC.film_temperature(T_wall, T_bulk)) / Dh
        # A four-argument one sees the temperatures it asked for.
        seen = Float64[]
        record = (Re_v, Pr_v, Tw, Tb) -> (push!(seen, Tw, Tb); 5.0)
        HTC.FromNusselt(record)(T_wall, T_bulk, ṁ, Dh, A, H2O)
        @test seen == [T_wall, T_bulk]
    end

    @testset "named constructors" begin
        @test HTC.ConstantNusselt(; Nu=8.235)(T_wall, T_bulk, ṁ, Dh, A, H2O) ≈
              8.235 * κ(H2O, 65.0) / Dh
        # Python STREAM evaluates its laminar branches at the bulk, so ours default there.
        @test HTC.FullyDevelopedLaminar(GEOM_MTR).basis isa HTC.AtBulk
        @test HTC.DevelopingLaminar(GEOM_MTR; develop_length=0.3).basis isa HTC.AtBulk
        @test HTC.DittusBoelter().basis isa HTC.AtFilm
        # A develop length that matters: it must not give the fully-developed answer.
        @test HTC.DevelopingLaminar(GEOM_MTR; develop_length=0.05)(T_wall, T_bulk, ṁ, Dh, A, H2O) !=
              HTC.FullyDevelopedLaminar(GEOM_MTR)(T_wall, T_bulk, ṁ, Dh, A, H2O)
    end

    @testset "user-defined models" begin
        mine = HTC.FromFunction((Tw, Tb, m, dh, a, liq) -> 1234.0)
        @test mine(T_wall, T_bulk, ṁ, Dh, A, H2O) == 1234.0
        # A channel hands every model a pressure; one that does not want it ignores it.
        @test mine(T_wall, T_bulk, ṁ, Dh, A, H2O, 2e5) == 1234.0
        @test HTC.DittusBoelter()(T_wall, T_bulk, ṁ, Dh, A, H2O, 2e5) ==
              HTC.DittusBoelter()(T_wall, T_bulk, ṁ, Dh, A, H2O)

        # Subtyping HTC directly is the other way in.
        @test HTC.Maximal(mine, HTC.DittusBoelter())(T_wall, T_bulk, ṁ, Dh, A, H2O) ==
              max(1234.0, HTC.DittusBoelter()(T_wall, T_bulk, ṁ, Dh, A, H2O))
        @test HTC.Maximal(HTC.FromFunction((args...) -> 1.0),
                         HTC.FromFunction((args...) -> 7.0),
                         HTC.FromFunction((args...) -> 3.0))(T_wall, T_bulk, ṁ, Dh, A, H2O) == 7.0
    end

    @testset "HTC.Elenbaas natural convection" begin
        el = HTC.Elenbaas(GEOM_MTR)
        @test el(60.0, 40.0, 0.0, Dh, A, H2O) > 0.0
        # No wall-to-bulk difference means no buoyancy and no heat transfer.
        @test el(40.0, 40.0, 0.0, Dh, A, H2O) ≈ 0.0 atol = 1e-10
        # Python STREAM's Elenbaas_h_spl on the 1.27 mm gap, handed film and bulk properties.
        @test el(60.0, 40.0, 0.0, Dh, A, H2O) ≈ 91.55185723551294 rtol = 1e-8
        el_bulk = HTC.Elenbaas(GEOM_MTR; basis=HTC.AtBulk())
        @test el_bulk(60.0, 40.0, 0.0, Dh, A, H2O) ≈ 67.6941463465902 rtol = 1e-8
    end

    @testset "HTC.RegimeDependent" begin
        lam = HTC.FromFunction((args...) -> 4.0)
        turb = HTC.FromFunction((args...) -> 100.0)
        rd = HTC.RegimeDependent(; laminar=lam, turbulent=turb,
                                re_bounds=(2000.0, 5000.0), geom=GEOM_MTR)

        # The regime is picked on the bulk Reynolds number, so solve for the flows that put
        # it where each test wants it.
        ṁ_at(Re_target) = Re_target * μ(H2O, T_bulk) * A / Dh
        @test rd(T_wall, T_bulk, ṁ_at(1000.0), Dh, A, H2O) == 4.0
        @test rd(T_wall, T_bulk, ṁ_at(8000.0), Dh, A, H2O) == 100.0
        # A quarter of the way through the band.
        @test rd(T_wall, T_bulk, ṁ_at(2750.0), Dh, A, H2O) ≈ 4.0 + 0.25 * 96.0

        # Selection on bulk Re rather than film Re is observable: at this flow the two
        # differ enough to land on opposite sides of the lower bound.
        Re_bulk = Re(H2O, T_bulk, ṁ_at(1900.0), A, Dh)
        Re_film = Re(H2O, HTC.film_temperature(T_wall, T_bulk), ṁ_at(1900.0), A, Dh)
        @test Re_bulk < 2000.0 < Re_film
        @test rd(T_wall, T_bulk, ṁ_at(1900.0), Dh, A, H2O) == 4.0

        @testset "matches Python's regime_dependent_h_spl" begin
            # ConstantNusselt and Elenbaas default to the film. Python hands its laminar and
            # natural branches bulk properties, so both are rebased to the bulk.
            rd_py = HTC.RegimeDependent(;
                laminar=HTC.ConstantNusselt(; Nu=8.235),
                turbulent=HTC.DittusBoelter(),
                natural=HTC.Elenbaas(GEOM_MTR),
                geom=GEOM_MTR,
            )
            @test rd_py.laminar.basis isa HTC.AtBulk
            @test rd_py.natural.basis isa HTC.AtBulk
            @test rd_py.turbulent.basis isa HTC.AtFilm
            # Python's stream-next regime_dependent_h_spl, which always treats buoyancy as
            # aiding. A model no channel has oriented does the same.
            @test rd_py.flow_up == 0.0
            for (Re_target, h_python) in ((1000.0, 2080.4723673553563),
                                          (2750.0, 3340.8813105054483),
                                          (8000.0, 16735.80121133571))
                @test rd_py(T_wall, T_bulk, ṁ_at(Re_target), Dh, A, H2O) ≈ h_python rtol = 1e-8
            end
            # At 2.3 g/s buoyancy outweighs the flow (Gr > Re²), but the flow still renews
            # the channel, so forced convection stays and buoyancy adds to it.
            @test rd_py(100.0, 40.0, 0.0022739555958189747, Dh, A, H2O) ≈
                  2080.7152503637144 rtol = 1e-8
        end

        @testset "buoyancy combines with forced convection" begin
            h_f, h_n = 4.0, 3.0   # the laminar value at Re 1000, and a natural one
            nc = HTC.FromFunction((args...) -> h_n)
            rd_nc = HTC.RegimeDependent(; laminar=lam, turbulent=turb, natural=nc,
                                       geom=GEOM_MTR)
            up, down = HTC._oriented(rd_nc, 1), HTC._oriented(rd_nc, -1)
            m = ṁ_at(1000.0)
            aiding = cbrt(h_f^3 + h_n^3)
            opposing = cbrt(h_f^3 - h_n^3)

            # A hot wall pushes the fluid beside it up.
            @test up(100.0, 40.0, m, Dh, A, H2O) ≈ aiding
            @test down(100.0, 40.0, m, Dh, A, H2O) ≈ opposing
            @test opposing < h_f < aiding
            # Reversing the flow, or cooling the wall instead, swaps the two.
            @test up(100.0, 40.0, -m, Dh, A, H2O) ≈ opposing
            @test down(100.0, 40.0, -m, Dh, A, H2O) ≈ aiding
            @test down(20.0, 40.0, m, Dh, A, H2O) ≈ aiding
            # A model no channel has oriented takes buoyancy as aiding, as Python does.
            @test rd_nc(100.0, 40.0, m, Dh, A, H2O) ≈ aiding

            # Past h_n = 2^(-1/3)·h_f, opposed flow separates at the wall and natural
            # convection sets h.
            strong = HTC._oriented(HTC.RegimeDependent(; laminar=lam, turbulent=turb,
                natural=HTC.FromFunction((args...) -> 3.5), geom=GEOM_MTR), -1)
            @test 3.5 > 2^(-1 / 3) * h_f
            @test strong(100.0, 40.0, m, Dh, A, H2O) == 3.5

            # With no flow through the channel, only natural convection is left.
            @test up(100.0, 40.0, 0.0, Dh, A, H2O) == h_n
            @test down(100.0, 40.0, 0.0, Dh, A, H2O) == h_n
            # Inside the Graetz band the value lies between the two, whichever way the flow
            # runs, so it has no jump where the flow reverses.
            Gz_per_Re = Pr(H2O, 40.0) * Dh / GEOM_MTR.L
            m_band = ṁ_at(0.03 / Gz_per_Re)
            for h in (up(100.0, 40.0, m_band, Dh, A, H2O), up(100.0, 40.0, -m_band, Dh, A, H2O))
                @test min(h_n, opposing) < h < aiding
            end
            @test up(100.0, 40.0, 1e-12, Dh, A, H2O) ≈ h_n rtol = 1e-9
            @test up(100.0, 40.0, -1e-12, Dh, A, H2O) ≈ h_n rtol = 1e-9
        end

        @testset "each cell's wall balance has one solution" begin
            # h·(T_wall - T_bulk) must rise with the wall temperature at any fixed flow, or
            # a cell has more than one wall temperature for its heat flux.
            rd_real = HTC.RegimeDependent(;
                laminar=HTC.ConstantNusselt(; Nu=8.235), turbulent=HTC.DittusBoelter(),
                natural=HTC.Elenbaas(GEOM_MTR), geom=GEOM_MTR,
            )
            T_walls = range(40.01, 190.0; length=600)
            for flow_up in (-1, 0, 1), Re_target in (-1000.0, -50.0, 1.0, 20.0, 300.0, 3000.0)
                model = HTC._oriented(rd_real, flow_up)
                m = sign(Re_target) * ṁ_at(abs(Re_target))
                flux = [model(Tw, 40.0, m, Dh, A, H2O) * (Tw - 40.0) for Tw in T_walls]
                @test all(diff(flux) .>= -1e-9 * maximum(flux))
            end
        end

        @testset "a channel's flow direction reaches the model" begin
            rd_nat = HTC.RegimeDependent(; laminar=lam, turbulent=turb,
                natural=HTC.FromFunction((args...) -> 3.0), geom=GEOM_MTR)
            @test HTC._oriented(rd_nat, -1).flow_up == -1.0
            wrapped = HTC._oriented(HTC.SubcooledBoiling(rd_nat, HTC.regime_dependent_q_scb()), -1)
            @test wrapped.single_phase.flow_up == -1.0
            @test HTC._oriented(HTC.Maximal(rd_nat, lam), 1).models[1].flow_up == 1.0
            # Models with no buoyancy term come back as they were.
            @test HTC._oriented(lam, 1) === lam
        end
    end

    @testset "HTC.SubcooledBoiling" begin
        q_scb = HTC.regime_dependent_q_scb()
        scb = HTC.SubcooledBoiling(HTC.DittusBoelter(), q_scb)
        P = 1e5

        # Below the onset of nucleate boiling the wrapper is its single-phase model.
        h_spl = HTC.DittusBoelter()(60.0, 40.0, ṁ, Dh, A, H2O)
        @test scb(60.0, 40.0, ṁ, Dh, A, H2O, P) ≈ h_spl
        # Well above it, boiling enhances the coefficient.
        @test scb(150.0, 40.0, ṁ, Dh, A, H2O, P) >
              HTC.DittusBoelter()(150.0, 40.0, ṁ, Dh, A, H2O)
        # With no pressure there is nothing to boil against.
        @test scb(150.0, 40.0, ṁ, Dh, A, H2O) ≈
              HTC.DittusBoelter()(150.0, 40.0, ṁ, Dh, A, H2O)
        # It wraps any model, not just the default.
        scb_lam = HTC.SubcooledBoiling(HTC.FullyDevelopedLaminar(GEOM_MTR), q_scb)
        @test scb_lam(60.0, 40.0, ṁ, Dh, A, H2O, P) ≈
              HTC.FullyDevelopedLaminar(GEOM_MTR)(60.0, 40.0, ṁ, Dh, A, H2O)
    end

    @testset "SubcooledBoiling matches Python's wall_heat_transfer_coeff" begin
        # Python STREAM's (stream-next) wall_heat_transfer_coeff with regime_dependent_h_spl and
        # regime_dependent_q_scb: a 135 °C wall over 60 °C coolant at 1.7 bar, at bulk Re
        # 1000, 3500 and 8000. The laminar case boils on Rohsenow's flux, the turbulent one
        # on McAdams.
        scb_py = HTC.SubcooledBoiling(
            HTC.RegimeDependent(;
                laminar=HTC.ConstantNusselt(; Nu=8.235),
                turbulent=HTC.DittusBoelter(),
                natural=HTC.Elenbaas(GEOM_MTR),
                geom=GEOM_MTR,
            ),
            HTC.regime_dependent_q_scb(),
        )
        for (ṁ_python, h_python) in ((0.016566504372602292, 25638.966882980738),
                                     (0.05798276530410803, 14842.513704589586),
                                     (0.13253203498081834, 15554.052288550205))
            @test scb_py(135.0, 60.0, ṁ_python, Dh, A, H2O, 1.7e5) ≈ h_python rtol = 1e-8
        end
    end

    @testset "partial_SCB_correction" begin
        factor = HTC.partial_SCB_correction
        # Python STREAM's Bergles_Rohsenhow_partial_SCB on the same fluxes.
        @test factor(1.0e5, 2.0e5, 5.0e4) ≈ 1.8027756377319946 rtol = 1e-12
        @test factor(1.0e5, 1.5e5, 1.0e5) ≈ 1.118033988749895 rtol = 1e-12
        @test factor(3.0e4, 9.0e4, 3.0e4) ≈ 2.23606797749979 rtol = 1e-12
        # No correction below the onset, or without a single-phase flux.
        @test factor(1.0e5, 5.0e4, 1.0e5) == 1.0
        @test factor(0.0, 2.0e5, 5.0e4) == 1.0
        @test factor(-1.0e3, 2.0e5, 5.0e4) == 1.0
        # A single-phase flux that is positive but vanishingly small is the case the floor on
        # the divisor exists for. Without it the ratio overflows and the factor is Inf, which
        # the heat transfer coefficient would inherit.
        @test isfinite(factor(1.0e-300, 2.0e5, 5.0e4))
        @test factor(1.0e-300, 2.0e5, 5.0e4) >= 1.0
    end
end

@testset "a user-defined HTC drives a compiled channel" begin
    n = 3
    T_inlet, T_wall_bc, h_fixed = 40.0, 100.0, 7500.0
    geom = PipeGeometry_circular(0.6, 0.01)

    @named pump_u = Pump(3.0e4)
    @named cac_u = ChannelAndContacts(;
        n=n, geometry=geom, htc=HTC.FromFunction((Tw, Tb, m, dh, a, liq) -> h_fixed)
    )
    @named bc_u = HeatExchanger(T_inlet)
    ct_l = [ConstantTemperature(T_wall_bc; name=Symbol(:ct_l_u_, i)) for i in 1:n]
    ct_r = [ConstantTemperature(T_wall_bc; name=Symbol(:ct_r_u_, i)) for i in 1:n]
    conns = [
        connect(pump_u.outlet, bc_u.inlet),
        connect(bc_u.outlet, cac_u.inlet),
        connect(cac_u.outlet, pump_u.inlet),
        [connect(ct_l[i].thermal, getproperty(cac_u, Symbol(:thermal_left, i))) for i in 1:n]...,
        [connect(ct_r[i].thermal, getproperty(cac_u, Symbol(:thermal_right, i))) for i in 1:n]...,
        pump_u.inlet.p ~ 1.0e5,
    ]
    @named sys_u = compose(
        System(conns, t; name=:sys_u), pump_u, bc_u, cac_u, ct_l..., ct_r...
    )
    ssys_u = mtkcompile(sys_u)
    op = [ssys_u.cac_u.T[i] => T_inlet for i in 1:n]
    push!(op, ssys_u.cac_u.inlet.ṁ => 0.49)
    sol_u = solve_steady(ssys_u, op)

    @test sol_u.retcode == ReturnCode.Success
    @test all(isapprox.(sol_u[ssys_u.cac_u.h_tc_left[:]], h_fixed; rtol=1e-8))
    # The reported Nusselt number is the one implied by the h in use.
    T_cells = sol_u[ssys_u.cac_u.T[:]]
    Nu_expected = [h_fixed * geom.Dh / κ(H2O, HTC.film_temperature(T_wall_bc, T_c))
                   for T_c in T_cells]
    @test all(isapprox.(sol_u[ssys_u.cac_u.Nu_left[:]], Nu_expected; rtol=1e-6))
end
