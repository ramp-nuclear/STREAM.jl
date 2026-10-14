using Test
using ModelingToolkit
using OrdinaryDiffEq, SteadyStateDiffEq
using STREAM
using STREAM.Assemblies
using STREAM.Components

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
        # And its gravity, which the same way only a model that wants it reads.
        @test mine(T_wall, T_bulk, ṁ, Dh, A, H2O, 2e5, G_EARTH) == 1234.0
        @test HTC.DittusBoelter()(T_wall, T_bulk, ṁ, Dh, A, H2O, 2e5, -G_EARTH) ==
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
        h(model, T_w, g=G_EARTH) = model(T_w, 40.0, 0.0, Dh, A, H2O, 1e5, g)
        @test h(el, 60.0) > 0.0
        # No wall-to-bulk difference means no buoyancy and no heat transfer.
        @test h(el, 40.0) ≈ 0.0 atol = 1e-10
        # Python STREAM's Elenbaas_h_spl on the 1.27 mm gap, handed film and bulk properties.
        @test h(el, 60.0) ≈ 91.55185723551294 rtol = 1e-8
        el_bulk = HTC.Elenbaas(GEOM_MTR; basis=HTC.AtBulk())
        @test h(el_bulk, 60.0) ≈ 67.6941463465902 rtol = 1e-8
        # Gravity comes from the call. Only its size matters, a horizontal channel has no
        # buoyancy along it, and without it there is nothing to compute.
        @test h(el, 60.0, -G_EARTH) == h(el, 60.0)
        @test h(el, 60.0, 0.0) ≈ 0.0 atol = 1e-10
        @test_throws ArgumentError el(60.0, 40.0, 0.0, Dh, A, H2O)
        @test_throws ArgumentError el(60.0, 40.0, 0.0, Dh, A, H2O, 1e5)
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
            # Python's stream-next regime_dependent_h_spl always adds buoyancy to the flow.
            # A heated wall in upflow, positive g, is the case where that is right.
            h_py(T_w, T_b, m) = rd_py(T_w, T_b, m, Dh, A, H2O, 1e5, G_EARTH)
            for (Re_target, h_python) in ((1000.0, 2080.4723673553563),
                                          (2750.0, 3340.8813105054483),
                                          (8000.0, 16735.80121133571))
                @test h_py(T_wall, T_bulk, ṁ_at(Re_target)) ≈ h_python rtol = 1e-8
            end
            # At 2.3 g/s buoyancy outweighs the flow (Gr > Re²), but the flow still renews
            # the channel, so forced convection stays and buoyancy adds to it.
            @test h_py(100.0, 40.0, 0.0022739555958189747) ≈ 2080.7152503637144 rtol = 1e-8
        end

        @testset "buoyancy combines with forced convection" begin
            h_f, h_n = 4.0, 3.0   # the laminar value at Re 1000, and a natural one
            nc = HTC.FromFunction((args...) -> h_n)
            rd_nc = HTC.RegimeDependent(; laminar=lam, turbulent=turb, natural=nc,
                                       geom=GEOM_MTR)
            # Positive g: positive flow runs up. Negative: it runs down.
            up(T_w, m) = rd_nc(T_w, 40.0, m, Dh, A, H2O, 1e5, G_EARTH)
            down(T_w, m) = rd_nc(T_w, 40.0, m, Dh, A, H2O, 1e5, -G_EARTH)
            m = ṁ_at(1000.0)
            aiding = cbrt(h_f^3 + h_n^3)
            opposing = cbrt(h_f^3 - h_n^3)

            # A hot wall pushes the fluid beside it up.
            @test up(100.0, m) ≈ aiding
            @test down(100.0, m) ≈ opposing
            @test opposing < h_f < aiding
            # Reversing the flow, or cooling the wall instead, swaps the two.
            @test up(100.0, -m) ≈ opposing
            @test down(100.0, -m) ≈ aiding
            @test down(20.0, m) ≈ aiding
            # In a horizontal channel buoyancy crosses the flow, and the two add.
            @test rd_nc(100.0, 40.0, m, Dh, A, H2O, 1e5, 0.0) ≈ aiding
            # Without g there is no telling which way buoyancy acts, so it refuses to guess.
            @test_throws ArgumentError rd_nc(100.0, 40.0, m, Dh, A, H2O)
            @test_throws ArgumentError rd_nc(100.0, 40.0, m, Dh, A, H2O, 1e5)
            # A model with no natural branch has no use for g.
            rd_forced = HTC.RegimeDependent(; laminar=lam, turbulent=turb, geom=GEOM_MTR)
            @test rd_forced(100.0, 40.0, m, Dh, A, H2O) == h_f
            @test rd_forced(100.0, 40.0, m, Dh, A, H2O, 1e5, -G_EARTH) == h_f

            # Past h_n = 2^(-1/3)·h_f, opposed flow separates at the wall and natural
            # convection sets h.
            strong = HTC.RegimeDependent(; laminar=lam, turbulent=turb,
                natural=HTC.FromFunction((args...) -> 3.5), geom=GEOM_MTR)
            @test 3.5 > 2^(-1 / 3) * h_f
            @test strong(100.0, 40.0, m, Dh, A, H2O, 1e5, -G_EARTH) == 3.5

            # With no flow through the channel, only natural convection is left.
            @test up(100.0, 0.0) == h_n
            @test down(100.0, 0.0) == h_n
            # Inside the Graetz band the value lies between the two, whichever way the flow
            # runs, so it has no jump where the flow reverses.
            Gz_per_Re = Pr(H2O, 40.0) * Dh / GEOM_MTR.L
            m_band = ṁ_at(0.03 / Gz_per_Re)
            for h in (up(100.0, m_band), up(100.0, -m_band))
                @test min(h_n, opposing) < h < aiding
            end
            @test up(100.0, 1e-12) ≈ h_n rtol = 1e-9
            @test up(100.0, -1e-12) ≈ h_n rtol = 1e-9
        end

        @testset "the Graetz band only reaches a dying flow" begin
            # The band where h hands over to natural convection is a modelling choice. Moving
            # it a decade either way changes nothing once Gz is past the highest band, which
            # any circulating flow is, and inside a band h stays between natural convection
            # and the mixed value.
            h_f, h_n = 4.0, 3.0
            nc = HTC.FromFunction((args...) -> h_n)
            bands = ((1e-3, 1e-2), (1e-2, 1e-1), (1e-1, 1.0))
            models = [HTC.RegimeDependent(; laminar=lam, turbulent=turb, natural=nc,
                                          geom=GEOM_MTR, gz_band=b) for b in bands]
            Gz_per_Re = Pr(H2O, 40.0) * Dh / GEOM_MTR.L
            ṁ_gz(Gz) = ṁ_at(Gz / Gz_per_Re)
            aiding, opposing = cbrt(h_f^3 + h_n^3), cbrt(h_f^3 - h_n^3)
            for g in (G_EARTH, -G_EARTH), Gz in (1.0, 10.0, 100.0), dir in (1, -1)
                hs = [model(100.0, 40.0, dir * ṁ_gz(Gz), Dh, A, H2O, 1e5, g) for model in models]
                @test allequal(hs)
            end
            for (model, (lo, hi)) in zip(models, bands), g in (G_EARTH, -G_EARTH), dir in (1, -1)
                for Gz in exp10.(range(log10(lo), log10(hi); length=7))
                    h = model(100.0, 40.0, dir * ṁ_gz(Gz), Dh, A, H2O, 1e5, g)
                    @test min(h_n, opposing) - 1e-12 <= h <= aiding + 1e-12
                end
                @test model(100.0, 40.0, dir * 1e-12, Dh, A, H2O, 1e5, g) ≈ h_n rtol = 1e-9
            end
        end

        @testset "each cell's wall balance has one solution" begin
            # h·(T_wall - T_bulk) must rise with the wall temperature at any fixed flow, or
            # a cell has more than one wall temperature for its heat flux.
            rd_real = HTC.RegimeDependent(;
                laminar=HTC.ConstantNusselt(; Nu=8.235), turbulent=HTC.DittusBoelter(),
                natural=HTC.Elenbaas(GEOM_MTR), geom=GEOM_MTR,
            )
            T_walls = range(40.01, 190.0; length=600)
            for g in (-G_EARTH, 0.0, G_EARTH), Re_target in (-1000.0, -50.0, 1.0, 20.0, 300.0, 3000.0)
                m = sign(Re_target) * ṁ_at(abs(Re_target))
                flux = [rd_real(Tw, 40.0, m, Dh, A, H2O, 1e5, g) * (Tw - 40.0) for Tw in T_walls]
                @test all(diff(flux) .>= -1e-9 * maximum(flux))
            end
        end

        @testset "wrappers pass gravity through" begin
            rd_nat = HTC.RegimeDependent(; laminar=lam, turbulent=turb,
                natural=HTC.FromFunction((args...) -> 3.0), geom=GEOM_MTR)
            m = ṁ_at(1000.0)
            # Below the onset of boiling, SubcooledBoiling is its single-phase model, and the
            # largest of one model is that model, so both have to see the same g.
            scb = HTC.SubcooledBoiling(rd_nat, HTC.regime_dependent_q_scb())
            for g in (G_EARTH, -G_EARTH)
                expected = rd_nat(60.0, 40.0, m, Dh, A, H2O, 1e5, g)
                @test scb(60.0, 40.0, m, Dh, A, H2O, 1e5, g) == expected
                @test HTC.Maximal(rd_nat)(60.0, 40.0, m, Dh, A, H2O, 1e5, g) == expected
            end
            @test rd_nat(60.0, 40.0, m, Dh, A, H2O, 1e5, G_EARTH) !=
                  rd_nat(60.0, 40.0, m, Dh, A, H2O, 1e5, -G_EARTH)
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
            @test scb_py(135.0, 60.0, ṁ_python, Dh, A, H2O, 1.7e5, G_EARTH) ≈ h_python rtol = 1e-8
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
    @named ct_l = ConstantTemperature(T_wall_bc; n=n)
    @named ct_r = ConstantTemperature(T_wall_bc; n=n)
    conns = [
        inseries(pump_u, bc_u, cac_u, pump_u),
        faces(
            (ct_l, :thermal) => (cac_u, :thermal_left),
            (ct_r, :thermal) => (cac_u, :thermal_right),
        ),
        pump_u.inlet.p ~ 1.0e5,
    ]
    @named sys_u = assembly(conns, pump_u, bc_u, cac_u, ct_l, ct_r)
    ssys_u = mtkcompile(sys_u)
    sol_u = solve_steady(ssys_u, [ssys_u.cac_u.inlet.ṁ => 0.49])

    @test sol_u.retcode == ReturnCode.Success
    @test all(isapprox.(sol_u[ssys_u.cac_u.h_tc_left], h_fixed; rtol=1e-8))
    # The reported Nusselt number is the one implied by the h in use.
    T_cells = sol_u[ssys_u.cac_u.T]
    Nu_expected = [h_fixed * geom.Dh / κ(H2O, HTC.film_temperature(T_wall_bc, T_c))
                   for T_c in T_cells]
    @test all(isapprox.(sol_u[ssys_u.cac_u.Nu_left], Nu_expected; rtol=1e-6))
end
