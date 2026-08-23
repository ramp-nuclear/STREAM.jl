using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using STREAM
using STREAM.Components
using STREAM: Re, Pr, Gr, Ra

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
        # Properties come from the bulk, so the value has to match the hand computation there.
        Ra_hand = Ra(Gr(H2O, 40.0, 60.0, GEOM_MTR.Dh, G_EARTH), Pr(H2O, 40.0))
        Nu_hand = HTC.elenbaas_nusselt(Ra_hand, GEOM_MTR.depth, GEOM_MTR.L)
        @test el(60.0, 40.0, 0.0, Dh, A, H2O) ≈ Nu_hand * κ(H2O, 40.0) / Dh
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

        @testset "branches keep their own property basis" begin
            # The laminar branch reading bulk and the turbulent one reading film is the
            # whole reason each branch is a full HTC rather than a Nusselt number.
            rd_real = HTC.RegimeDependent(;
                laminar=HTC.FullyDevelopedLaminar(GEOM_MTR),
                turbulent=HTC.DittusBoelter(),
                geom=GEOM_MTR,
            )
            m_lam = ṁ_at(1000.0)
            @test rd_real(T_wall, T_bulk, m_lam, Dh, A, H2O) ≈
                  HTC.FullyDevelopedLaminar(GEOM_MTR)(T_wall, T_bulk, m_lam, Dh, A, H2O)
            m_turb = ṁ_at(8000.0)
            @test rd_real(T_wall, T_bulk, m_turb, Dh, A, H2O) ≈
                  HTC.DittusBoelter()(T_wall, T_bulk, m_turb, Dh, A, H2O)
        end

        @testset "natural convection takes over at Gr/Re² > 1" begin
            nc = HTC.FromFunction((args...) -> 999.0)
            rd_nc = HTC.RegimeDependent(; laminar=lam, turbulent=turb, natural=nc,
                                       geom=GEOM_MTR, g=G_EARTH)
            # Barely any flow, a hot wall: buoyancy wins.
            @test rd_nc(100.0, 40.0, 1e-6, Dh, A, H2O) == 999.0
            # Fast flow: forced convection wins, and the natural branch changes nothing.
            m_fast = ṁ_at(8000.0)
            @test rd_nc(100.0, 40.0, m_fast, Dh, A, H2O) == 100.0
            @test rd_nc(100.0, 40.0, m_fast, Dh, A, H2O) ==
                  rd(100.0, 40.0, m_fast, Dh, A, H2O)
        end
    end

    @testset "HTC.SubcooledBoiling" begin
        q_scb = HTC.regime_dependent_q_scb(; pressure=1e5)
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
