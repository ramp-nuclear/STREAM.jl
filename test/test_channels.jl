# Channel-family unit tests (Channel, ChannelHeatFlux, ChannelAndContacts).
#

using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using STREAM
using STREAM.Assemblies
using STREAM.Components
using STREAM.Components: Channel  # explicit: Base.Channel also exists
using STREAM.Substances
@isdefined(build_loop) || include("fixtures.jl")
using STREAM.HTC: _bergles_rohsenow_dT_ONB  # private to HTC, for the SCB integration block
using OrdinaryDiffEq: ReturnCode

const N_DEFAULT      = 4
const L_DEFAULT      = 0.6
const D_DEFAULT      = 0.01
const T_INLET        = 40.0
const T_WALL         = 100.0
const H_DEFAULT      = 5000.0
const DP_PUMP        = 3.0e4
const Q_FLUX_DEFAULT = 1.0e5

geom = Duct(L_DEFAULT, Circular(D_DEFAULT))

_names(sys) = string.(ModelingToolkit.getname.(ModelingToolkit.get_systems(sys)))

@testset "Channel with no h and no wall temperature gradient outputs the inlet" begin
    n = N_DEFAULT
    @assembly ssys begin
        pump = Pump(DP_PUMP)
        bc = HeatExchanger(T_INLET)
        ch = Channel(; n=n, geometry=geom)
        pump --> bc --> ch --> pump
        pump.inlet.p ~ 1.0e5
        ch.T_wall_outer .~ T_INLET
    end
    sol = solve_steady(ssys)
    @test sol.retcode == ReturnCode.Success
    # T_out ≈ T_inlet — no heating
    @test isapprox(sol[ssys.ch.T_out], T_INLET; rtol=1e-5)
end

@testset "ChannelHeatFlux with zero q outputs the inlet" begin
    n = N_DEFAULT
    @assembly ssys begin
        pump = Pump(DP_PUMP)
        bc = HeatExchanger(T_INLET)
        chf = ChannelHeatFlux(; n=n, geometry=geom)
        pump --> bc --> chf --> pump
        pump.inlet.p ~ 1.0e5
        chf.q_outer .~ 0.0
    end
    sol = solve_steady(ssys)
    @test sol.retcode == ReturnCode.Success
    @test isapprox(sol[ssys.chf.T_out], T_INLET; rtol=1e-5)
end

@testset "Channel heated with higher wall than inlet increases temperature" begin
    n = N_DEFAULT
    @assembly ssys begin
        pump = Pump(DP_PUMP)
        bc = HeatExchanger(T_INLET)
        ch = Channel(; n=n, geometry=geom, h=H_DEFAULT)
        pump --> bc --> ch --> pump
        pump.inlet.p ~ 1.0e5
        ch.T_wall_outer .~ T_WALL
    end
    sol = solve_steady(ssys)
    @test sol.retcode == ReturnCode.Success
    @test sol[ssys.ch.T_out] > T_INLET
    # The wall heats the coolant, so the heat flow into every cell is positive. A circular
    # duct has its one face and no other.
    @test all(>(0), sol[ssys.ch.q_wall_outer])
    @test !hasproperty(ssys.ch, :q_wall_right)
end

@testset "ChannelHeatFlux heated with q>0 increases temperature" begin
    n = N_DEFAULT
    dz = L_DEFAULT / n
    expected = Q_FLUX_DEFAULT * geom.heated.outer * dz
    @assembly ssys begin
        pump = Pump(DP_PUMP)
        bc = HeatExchanger(T_INLET)
        chf = ChannelHeatFlux(; n=n, geometry=geom)
        pump --> bc --> chf --> pump
        pump.inlet.p ~ 1.0e5
        chf.q_outer .~ Q_FLUX_DEFAULT
    end
    sol = solve_steady(ssys)
    @test sol.retcode == ReturnCode.Success
    @test sol[ssys.chf.T_out] > T_INLET
    @test all(isapprox.(sol[ssys.chf.q_wall_outer], expected, rtol=1e-7))
end

@testset "ChannelHeatFlux with a fixed-property Liquid — uniform heating gives exact linear rise" begin
    # With a constant-cp mock fluid the steady cell-to-cell rise is exactly
    # ΔT = q·heated_perimeter·dz / (ṁ·cp), the closed-form Python uses with mock_liquid_funcs.
    n = 8
    dz = L_DEFAULT / n
    cp_mock = 2000.0
    ṁ = 0.5
    q = Q_FLUX_DEFAULT
    liquid = Liquid(; cₚ=cp_mock)
    @assembly ssys begin
        pump = Pump(; ṁ0=ṁ)        # fixed-flow (current source), so ṁ is exact
        bc = HeatExchanger(T_INLET)
        chf = ChannelHeatFlux(; n=n, geometry=geom, liquid=liquid)
        pump --> bc --> chf --> pump
        pump.inlet.p ~ 1.0e5
        chf.q_outer .~ q
    end
    sol = solve_steady(ssys)
    @test sol.retcode == ReturnCode.Success
    dT = q * geom.heated.outer * dz / (ṁ * cp_mock)
    Tc = sol[ssys.chf.T]
    @test isapprox(Tc[1] - T_INLET, dT; rtol=1e-6)
    for i in 2:n
        @test isapprox(Tc[i] - Tc[i - 1], dT; rtol=1e-6)
    end
end

@testset "Channel wall bound to a parameter changes without recompiling" begin
    n = N_DEFAULT
    @parameters T_w = T_WALL
    @assembly ssys begin
        pump = Pump(DP_PUMP)
        bc = HeatExchanger(T_INLET)
        ch = Channel(; n=n, geometry=geom, h=H_DEFAULT)
        pump --> bc --> ch --> pump
        pump.inlet.p ~ 1.0e5
        ch.T_wall_outer .~ T_w
    end
    sol = solve_steady(ssys)
    hot = solve_steady(ssys, [T_w => T_WALL + 50.0])
    @test sol.retcode == ReturnCode.Success
    @test hot.retcode == ReturnCode.Success
    @test all(sol[ssys.ch.T_wall_outer[i]] == T_WALL for i in 1:n)
    @test all(hot[ssys.ch.T_wall_outer[i]] == T_WALL + 50.0 for i in 1:n)
    @test sol[ssys.ch.T_out] < hot[ssys.ch.T_out]
end

@testset "Channel h::Real (broadcast) same as constant vector" begin
    n = N_DEFAULT
    @assembly ssys begin
        pump = Pump(DP_PUMP)
        bc = HeatExchanger(T_INLET)
        ch = Channel(; n=n, geometry=geom, h=H_DEFAULT)
        pump --> bc --> ch --> pump
        pump.inlet.p ~ 1.0e5
        ch.T_wall_outer .~ T_WALL
    end
    sol = solve_steady(ssys)
    @test sol.retcode == ReturnCode.Success

    @assembly ssys2 begin
        ch2 = Channel(; n=n, geometry=geom, h=collect([H_DEFAULT for i in 1:n]))
        pump --> bc --> ch2 --> pump
        pump.inlet.p ~ 1.0e5
        ch2.T_wall_outer .~ T_WALL
    end
    sol2 = solve_steady(ssys2)
    @test sol2.retcode == ReturnCode.Success
    @test all(isapprox.(sol2[ssys2.ch2.T], sol[ssys.ch.T], rtol=1e-6))
    @test all(isapprox.(sol2[ssys2.ch2.q_wall_outer], sol[ssys.ch.q_wall_outer], rtol=1e-6))

end

@testset "Channel h:: constant Function same as constant" begin
    n = N_DEFAULT
    h_fn(t) = H_DEFAULT
    @assembly ssys begin
        pump = Pump(DP_PUMP)
        bc = HeatExchanger(T_INLET)
        ch = Channel(; n=n, geometry=geom, h=h_fn)
        pump --> bc --> ch --> pump
        pump.inlet.p ~ 1.0e5
        ch.T_wall_outer .~ T_WALL
    end
    sol = solve_steady(ssys)
    @assembly ssys2 begin
        ch2 = Channel(; n=n, geometry=geom, h=H_DEFAULT)
        pump --> bc --> ch2 --> pump
        pump.inlet.p ~ 1.0e5
        ch2.T_wall_outer .~ T_WALL
    end
    sol2 = solve_steady(ssys2)
    @test sol.retcode == ReturnCode.Success
    @test all(isapprox.(sol2[ssys2.ch2.T], sol[ssys.ch.T], rtol=1e-6))
    @test all(isapprox.(sol2[ssys2.ch2.q_wall_outer], sol[ssys.ch.q_wall_outer], rtol=1e-6))
end

@testset "CAC with HTC.DittusBoelter solves a transient without crashing" begin
    n = N_DEFAULT
    @assembly ssys begin
        pump = Pump(DP_PUMP)
        bc = HeatExchanger(T_INLET)
        cac = ChannelAndContacts(; n=n, geometry=geom,
                                  htc=HTC.DittusBoelter(),
                                  darcy=Friction.Blasius())
        # Pin each cell's left thermal port T to T_WALL via per-cell ConstantTemperature.
        ct_l = ConstantTemperature(T_WALL; n=n)
        pump --> bc --> cac --> pump
        pump.inlet.p ~ 1.0e5
        faces(
            (ct_l, :thermal) => (cac, :thermal_outer),
        )
    end fully_determined=false
    sol = solve_transient(ssys, range(0.0, 1.0, length=50))
    @test sol.retcode == ReturnCode.Success
    @test sol[ssys.cac.T_out, end] > T_INLET
    @test all(>(0), sol[ssys.cac.h_tc_outer[:], end])
end

@testset "ISCB: In-loop SCB Correction" begin
    n = 5
    T_inlet_iscb = 40.0
    L_ch = 0.6
    D_ch = 0.01
    dP_pump_iscb = 3.0e4

    function _build_scb_loop(; scb_correction=nothing, T_wall_bc=100.0)
        htc = scb_correction === nothing ? HTC.DittusBoelter() :
              HTC.SubcooledBoiling(HTC.DittusBoelter(), scb_correction)
        @assembly ssys begin
            pump = Pump(dP_pump_iscb)
            cac = ChannelAndContacts(
                n=n, geometry=Duct(L_ch, Circular(D_ch)), htc=htc
            )
            bc = HeatExchanger(T_inlet_iscb)
            ct_l = ConstantTemperature(T_wall_bc; n=n)
            pump --> bc --> cac --> pump
            faces(
                (ct_l, :thermal) => (cac, :thermal_outer),
            )
            pump.inlet.p ~ 2e5
        end
        sol = solve_steady(ssys)
        return ssys, sol
    end

    @testset "Low T_wall -> matches single-phase exactly" begin
        # T_wall = 330K < T_sat (~393K at 2 bar) ⇒ SCB inactive, pure single-phase.
        # Both SCB and non-SCB loops solve to identical h_tc values.
        scb_fn = HTC.regime_dependent_q_scb()
        ssys_scb, sol_scb = _build_scb_loop(scb_correction=scb_fn, T_wall_bc=56.85)
        ssys_noscb, sol_noscb = _build_scb_loop(scb_correction=nothing, T_wall_bc=56.85)

        htc_scb = sol_scb[ssys_scb.cac.h_tc_outer]
        htc_noscb = sol_noscb[ssys_noscb.cac.h_tc_outer]
        @test all(isapprox.(htc_noscb, htc_scb, rtol=1e-10))
    end
end

@testset "a channel's faces are the heated walls of its duct" begin
    # A plate gap heated on its left wall only has one face, and h is given for it by name.
    rect = Duct(0.6, Rectangular(0.07, 0.0025); heated=(left=0.07,))
    @named ch = Channel(; n=3, geometry=rect, h=(left=H_DEFAULT,))
    @test hasproperty(ch, :T_wall_left)
    @test !hasproperty(ch, :T_wall_right)
    @test_throws ArgumentError Channel(; name=:bad, n=3, geometry=rect, h=(right=H_DEFAULT,))

    @assembly ssys begin
        pump = Pump(DP_PUMP)
        bc = HeatExchanger(T_INLET)
        pump --> bc --> ch --> pump
        pump.inlet.p ~ 1.0e5
        ch.T_wall_left .~ T_WALL
    end
    sol = solve_steady(ssys)
    @test sol.retcode == ReturnCode.Success
    @test sol[ssys.ch.T_out] > T_INLET
    @test sol[ssys.ch.q_wall] == sol[ssys.ch.q_wall_left]

    # A function of time given for one face becomes that face's callable parameter.
    h_fn = t -> H_DEFAULT
    @named ch_fn = Channel(; n=3, geometry=rect, h=(left=h_fn,))
    @test any(p -> occursin("h_left_fn", string(p)), parameters(ch_fn))
end

@testset "an unheated duct gives a channel with no faces" begin
    plain = Duct(L_DEFAULT, Circular(D_DEFAULT); heated=(;))
    @named riser = Channel(; n=3, geometry=plain)
    @test !hasproperty(riser, :T_wall_outer)
    @assembly ssys begin
        pump = Pump(DP_PUMP)
        bc = HeatExchanger(T_INLET)
        pump --> bc --> riser --> pump
        pump.inlet.p ~ 1.0e5
    end
    sol = solve_steady(ssys)
    @test sol.retcode == ReturnCode.Success
    @test sol[ssys.riser.T_out] ≈ T_INLET
    @test all(iszero, sol[ssys.riser.q_wall])
end

const N_SIGN          = 5
const T_INLET_SIGN    = 40.0
const T_WALL_SIGN     = 100.0
const ṁ_NEG = -0.490
const GEOM_SIGN       = Duct(0.6, Circular(0.01))

@testset "flow reversal: Channel ṁ < 0 " begin
    @assembly ssys begin
        pump = Pump(; ṁ0=ṁ_NEG)
        ch = Channel(; n=N_SIGN, geometry=GEOM_SIGN, h=H_DEFAULT)
        bc = HeatExchanger(T_INLET_SIGN)
        pump --> bc --> ch --> pump
        pump.inlet.p ~ 1.0e5
        ch.T_wall_outer .~ T_WALL_SIGN
    end
    sol = solve_steady(ssys)

    @test sol.retcode == ReturnCode.Success

    T_vals = sol[ssys.ch.T]
    Re_vals = sol[ssys.ch.Re]

    @test sol[ssys.ch.inlet.ṁ] < 0
    @test all(T_vals[i] >= T_vals[i + 1] for i in 1:(N_SIGN - 1))
    @test all(Re_vals .> 0)
end

@testset "flow reversal: ChannelAndContacts ṁ < 0" begin
    @assembly ssys begin
        pump = Pump(; ṁ0=ṁ_NEG)
        cac = ChannelAndContacts(n=N_SIGN, geometry=GEOM_SIGN)
        bc = HeatExchanger(T_INLET_SIGN)
        ct_l = ConstantTemperature(T_WALL_SIGN; n=N_SIGN)
        pump --> bc --> cac --> pump
        faces(
            (ct_l, :thermal) => (cac, :thermal_outer),
        )
        pump.inlet.p ~ 1.0e5
    end
    sol = solve_steady(ssys)

    @test sol.retcode == ReturnCode.Success

    T_vals = sol[ssys.cac.T]
    Re_vals = sol[ssys.cac.Re]
    vel_vals = sol[ssys.cac.velocity]

    @test sol[ssys.cac.inlet.ṁ] < 0
    @test all(T_vals[i] >= T_vals[i + 1] for i in 1:(N_SIGN - 1))
    @test all(Re_vals .> 0)
    @test all(vel_vals .> 0)

    T_mean = (sol[ssys.cac.T_out] + T_INLET_SIGN) / 2
    Q_advect = abs(ṁ_NEG) * cₚ(H2O, T_mean) * (sol[ssys.cac.T_out] - T_INLET_SIGN)
    Q_wall_total = sol[ssys.cac.Q_wall_total]
    @test isapprox(Q_wall_total, Q_advect; rtol=0.01)
end

@testset "flow reversal: ChannelHeatFlux ṁ < 0" begin
    # CHF flux is intrinsic: the sign of q_outer[i] does not depend on the flow direction.
    @assembly ssys begin
        pump = Pump(; ṁ0=ṁ_NEG)
        chf = ChannelHeatFlux(n=N_SIGN, geometry=GEOM_SIGN)
        bc = HeatExchanger(T_INLET_SIGN)
        pump --> bc --> chf --> pump
        pump.inlet.p ~ 1.0e5
        chf.q_outer .~ Q_FLUX_DEFAULT
    end
    sol = solve_steady(ssys)

    @test sol.retcode == ReturnCode.Success

    T_vals = sol[ssys.chf.T]
    Re_vals = sol[ssys.chf.Re]

    @test sol[ssys.chf.inlet.ṁ] < 0
    @test all(T_vals[i] >= T_vals[i + 1] for i in 1:(N_SIGN - 1))
    @test all(Re_vals .> 0)

    # CHF q_wall stays positive — q is intrinsic / sign-independent of flow.
    @test all(>(0), sol[ssys.chf.q_wall_outer])

    # Energy balance: advective heat gain ≈ summed q_wall.
    T_mean = (sol[ssys.chf.T_out] + T_INLET_SIGN) / 2
    Q_advect = abs(ṁ_NEG) * cₚ(H2O, T_mean) * (sol[ssys.chf.T_out] - T_INLET_SIGN)
    Q_wall_total = sum(sol[ssys.chf.q_wall])
    @test isapprox(Q_wall_total, Q_advect; rtol=0.01)
end


@testset "Direction of flow does not matter for temperature profile" begin
    n = 3
    geom = Duct(0.3, Circular(0.01))
    Q = 800.0
    dz = 0.3 / n
    q_density_g3b = Q / (geom.heated.outer * dz)
    T_in = 46.85

    function _build_loop_g3b(ṁ0)
        @assembly ssys begin
            pump = Pump(; ṁ0=ṁ0)
            hex = HeatExchanger(T_in)
            chf = ChannelHeatFlux(; n=n, geometry=geom)
            pump --> hex --> chf --> pump
            pump.inlet.p ~ 1.0e5
            chf.q_outer .~ q_density_g3b
        end
        sol = solve_steady(ssys; abstol=1e-12, reltol=1e-12)
        return ssys, sol
    end

    ssys_fwd, sol_fwd = _build_loop_g3b(+0.1)
    ssys_rev, sol_rev = _build_loop_g3b(-0.1)

    @test sol_fwd.retcode == ReturnCode.Success
    @test sol_rev.retcode == ReturnCode.Success

    T_fwd = sol_fwd[ssys_fwd.chf.T]
    T_rev = sol_rev[ssys_rev.chf.T]

    # Forward profile monotone increasing.
    @test T_fwd[1] < T_fwd[2] < T_fwd[3]
    # Reverse profile monotone decreasing.
    @test T_rev[1] > T_rev[2] > T_rev[3]

    # Spatial mirror.
    @test all(isapprox.(T_rev, T_fwd[end:-1:1], rtol=1e-9))
end

@testset "CAC ↔ CHF cross-equivalence" begin
    n = N_DEFAULT
    # CAC side: constant-Nusselt drives h_tc, ConstantTemperature pins T_wall per cell.
    @assembly ssys_cac begin
        pump_cac = Pump(DP_PUMP)
        bc_cac = HeatExchanger(T_INLET)
        cac = ChannelAndContacts(; n=n, geometry=geom, htc=HTC.ConstantNusselt(; Nu=4.0))
        ct_l_xeq = ConstantTemperature(T_WALL; n=n)
        pump_cac --> bc_cac --> cac --> pump_cac
        pump_cac.inlet.p ~ 1.0e5
        faces(
            (ct_l_xeq, :thermal) => (cac, :thermal_outer),
        )
    end fully_determined=false
    sol_cac = solve_transient(ssys_cac, [ssys_cac.cac.T => fill(T_INLET, n)],
                              range(0.0, 1.0, length=50))
    @test sol_cac.retcode == ReturnCode.Success
    T_out_cac = sol_cac[ssys_cac.cac.T_out, end]
    # Read CAC's converged per-cell q_density from q_wall_outer.
    dz = L_DEFAULT / n
    q_per_cell = [
        sol_cac[ssys_cac.cac.q_wall_outer[i], end] / (geom.heated.outer * dz)
        for i in 1:n
    ]

    # CHF side: the flux pinned to per-cell q_per_cell.
    @assembly ssys_chf begin
        pump_chf = Pump(DP_PUMP)
        bc_chf = HeatExchanger(T_INLET)
        chf = ChannelHeatFlux(; n=n, geometry=geom)
        pump_chf --> bc_chf --> chf --> pump_chf
        pump_chf.inlet.p ~ 1.0e5
        chf.q_outer .~ q_per_cell
    end
    sol_chf = solve_transient(ssys_chf, [ssys_chf.chf.T => fill(T_INLET, n)],
                              range(0.0, 1.0, length=50))
    @test sol_chf.retcode == ReturnCode.Success
    T_out_chf = sol_chf[ssys_chf.chf.T_out, end]
    @test isapprox(T_out_cac, T_out_chf; rtol=1e-3)
end

# §4 Subcooled-boiling integration (in-loop CAC + SCB).
# Pure-correlation subcooled-boiling tests live in test_thresholds.jl.
@testset "Subcooled-boiling integration (ISCB)" begin
    n_scb = 5
    T_inlet_scb = 40.0
    L_ch_scb = 0.6
    D_ch_scb = 0.01
    dP_pump_scb = 3.0e4

    # Helper: build a minimal loop with CAC + Pump + HeatExchanger + per-cell
    # ConstantTemperature BCs. Returns (compiled_sys, solution).
    function _build_scb_loop(; scb_correction=nothing, T_wall_bc=100.0)
        htc = scb_correction === nothing ? HTC.DittusBoelter() :
              HTC.SubcooledBoiling(HTC.DittusBoelter(), scb_correction)
        @assembly ssys begin
            pump = Pump(dP_pump_scb)
            cac = ChannelAndContacts(
                n=n_scb,
                geometry=Duct(L_ch_scb, Circular(D_ch_scb)),
                htc=htc,
            )
            bc = HeatExchanger(T_inlet_scb)
            ct_l = ConstantTemperature(T_wall_bc; n=n_scb)
            pump --> bc --> cac --> pump
            faces(
                (ct_l, :thermal) => (cac, :thermal_outer),
            )
            pump.inlet.p ~ 2e5
        end
        sol = solve_steady(ssys)
        return ssys, sol
    end

    @testset "SCB ChannelAndContacts compiles" begin
        scb_fn = HTC.regime_dependent_q_scb()
        @named cac = ChannelAndContacts(
            n=3,
            geometry=Duct(L_ch_scb, Circular(D_ch_scb)),
            htc=HTC.SubcooledBoiling(HTC.DittusBoelter(), scb_fn),
        )
        @test cac isa ModelingToolkit.System
    end

    @testset "SCB ChannelAndContacts solves (sub-ONB), matches non-SCB" begin
        # T_wall is below T_ONB at 2 bar, so SubcooledBoiling returns its
        # single-phase value unchanged. The "SCB present but inactive" claim
        # therefore means the SCB loop must reproduce the non-SCB loop exactly.
        # Build both, solve both, and compare h_tc and coolant T cell by cell.
        T_wall = 106.85
        scb_fn = HTC.regime_dependent_q_scb()
        ssys_scb, sol_scb = _build_scb_loop(scb_correction=scb_fn, T_wall_bc=T_wall)
        ssys_noscb, sol_noscb = _build_scb_loop(scb_correction=nothing, T_wall_bc=T_wall)
        @test sol_scb.retcode == ReturnCode.Success
        @test sol_noscb.retcode == ReturnCode.Success

        # The wall sits below ONB in every cell: confirm the regime the claim asserts.
        P_cell = 2e5
        T_sat = Tsat(H2O, P_cell)
        for i in 1:n_scb
            T_bulk = sol_scb[ssys_scb.cac.T[i]]
            h_spl = sol_scb[ssys_scb.cac.h_tc_outer[i]]
            q_spl = h_spl * (T_wall - T_bulk)
            T_ONB = T_sat + _bergles_rohsenow_dT_ONB(P_cell, q_spl)
            @test T_wall < T_ONB
        end

        # Inactive SCB => identical to the plain single-phase channel.
        @test all(isapprox(sol_scb[ssys_scb.cac.h_tc_outer[i]], sol_noscb[ssys_noscb.cac.h_tc_outer[i]]; rtol=1e-10) for i in 1:n_scb)
        @test all(isapprox(sol_scb[ssys_scb.cac.T[i]], sol_noscb[ssys_noscb.cac.T[i]]; rtol=1e-10) for i in 1:n_scb)
    end

    @testset "Default (no SCB) backward compatibility" begin
        ssys, sol = _build_scb_loop(scb_correction=nothing, T_wall_bc=100.0)
        @test sol.retcode == ReturnCode.Success
    end

    @testset "High T_wall -> enhanced HTC (numerical)" begin
        # Direct numerical evaluation: at T_wall >> T_sat, the SCB correction
        # factor > 1. Validates the physics without requiring KINSOL convergence
        # in the boiling regime.
        T_bulk = 46.85
        P = 2e5
        T_wall = 146.85
        ṁ = 0.49
        Dh = D_ch_scb
        Ac = pi/4 * Dh^2
        Re_val = abs(ṁ) * Dh / (Ac * μ(H2O, T_bulk))
        Pr_val =
            cₚ(H2O, T_bulk) * μ(H2O, T_bulk) /
            κ(H2O, T_bulk)

        h_spl =
            HTC.dittus_boelter(Re_val, Pr_val, T_bulk, T_wall) * κ(H2O, T_bulk) /
            Dh
        q_spl = h_spl * (T_wall - T_bulk)

        T_sat = Tsat(H2O, P)
        T_ONB = T_sat + _bergles_rohsenow_dT_ONB(P, q_spl)

        scb_fn = HTC.regime_dependent_q_scb()
        sat = H2O(T_sat, P)
        q_scb = scb_fn(T_wall, sat, Re_val)
        q_scb_inc = scb_fn(T_ONB, sat, Re_val)
        factor = HTC.partial_SCB_correction(q_spl, q_scb, q_scb_inc)

        @test T_wall > T_ONB                     # boiling is active
        @test factor > 1.0                       # correction enhances h_tc
        @test h_spl * factor > h_spl             # SCB h_tc > single-phase h_tc
    end

    @testset "Low T_wall -> matches single-phase exactly" begin
        # T_wall = 330K < T_sat (~393K at 2 bar) -> SCB inactive, pure
        # single-phase. Both SCB and non-SCB loops solve to identical h_tc values.
        scb_fn = HTC.regime_dependent_q_scb()
        ssys_scb, sol_scb = _build_scb_loop(scb_correction=scb_fn, T_wall_bc=56.85)
        ssys_noscb, sol_noscb = _build_scb_loop(scb_correction=nothing, T_wall_bc=56.85)

        htc_scb = sol_scb[ssys_scb.cac.h_tc_outer]
        htc_noscb = sol_noscb[ssys_noscb.cac.h_tc_outer]
        # Should be identical (ifelse selects uncorrected branch).
        for i in 1:n_scb
            @test htc_scb[i] ≈ htc_noscb[i] rtol=1e-10
        end
    end
end

@testset "a channel's pressure is the static pressure, the total less the dynamic head" begin
    # Ports carry the total pressure. Saturation depends on the static pressure, which sits
    # ρv²/2 below it, so that is what the channel reports as P and reads T_sat and T_ONB at.
    n = 5
    ssys = build_loop(; n=n)
    sol = solve_steady(ssys)
    @test sol.retcode == ReturnCode.Success
    ch = ssys.ch

    # Total pressure at each cell's outlet-side face, and the dynamic head there.
    p_total = sol[ch.inlet.p] .- cumsum(sol[ch.dp])
    head = [ρ(H2O, sol[ch.T[i]]) * sol[ch.v[i]]^2 / 2 for i in 1:n]
    @test all(head .> 0)
    @test sol[ch.P] ≈ p_total .- head rtol = 1e-12
    @test sol[ch.T_sat] ≈ [Tsat(H2O, sol[ch.P[i]]) for i in 1:n] rtol = 1e-12
end

@testset "a closed vertical loop gives back the head its upward channel loses" begin
    # The channel runs up and the return leg falls the same height, so the hydrostatic heads
    # cancel around the loop, apart from a few kelvin of buoyancy. The flow is the flat loop's,
    # and the channel's own drop grows by ρgL.
    flat, upright = build_loop(), build_loop(; g_acc=G_EARTH)
    sol_flat = solve_steady(flat)
    sol = solve_steady(upright)
    @test sol.retcode == ReturnCode.Success
    @test sol[upright.ch.inlet.ṁ] ≈ sol_flat[flat.ch.inlet.ṁ] rtol = 1e-3
    head = sum(ρ(H2O, T) for T in sol[upright.ch.T]) / 10 * G_EARTH * 0.6
    @test sol[upright.ch.dP] - sol_flat[flat.ch.dP] ≈ head rtol = 1e-2
end

@testset "a wall cooler than the coolant reports saturation as its ONB temperature" begin
    # The coolant enters at 40 °C over a 30 °C wall, so heat flows into the wall in every cell.
    ssys = build_loop(; n=5, T_wall=30.0)
    sol = solve_steady(ssys)
    @test sol.retcode == ReturnCode.Success
    @test all(sol[ssys.ch.q_wall] .< 0)
    @test sol[ssys.ch.T_ONB] == sol[ssys.ch.T_sat]
end
