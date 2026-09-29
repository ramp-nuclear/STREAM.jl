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
using STREAM.Examples
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

geom = PipeGeometry_circular(L_DEFAULT, D_DEFAULT)

_names(sys) = string.(ModelingToolkit.getname.(ModelingToolkit.get_systems(sys)))

@testset "Channel with no h and no wall temperature gradient outputs the inlet" begin
    n = N_DEFAULT
    @named pump = Pump(DP_PUMP)
    @named bc = HeatExchanger(T_INLET)
    @named ch = Channel(; n=n, geometry=geom)
    connections = [
        inseries(pump, bc, ch, pump),
        pump.inlet.p ~ 1.0e5,
        ch.T_wall_left .~ T_INLET,
        ch.T_wall_right .~ T_INLET,
    ]
    @named sys = assembly(connections, pump, bc, ch)
    ssys = mtkcompile(sys)
    sol = solve_steady(ssys, [ssys.ch.inlet.ṁ => 0.5])
    @test sol.retcode == ReturnCode.Success
    # T_out ≈ T_inlet — no heating
    @test isapprox(sol[ssys.ch.T_out], T_INLET; rtol=1e-5)
end

@testset "ChannelHeatFlux with zero q outputs the inlet" begin
    n = N_DEFAULT
    @named pump = Pump(DP_PUMP)
    @named bc = HeatExchanger(T_INLET)
    @named chf = ChannelHeatFlux(; n=n, geometry=geom)
    connections = [
        inseries(pump, bc, chf, pump),
        pump.inlet.p ~ 1.0e5, chf.q_left .~ 0.0, chf.q_right .~ 0.0,
    ]
    @named sys = assembly(connections, pump, bc, chf)
    ssys = mtkcompile(sys)
    sol = solve_steady(ssys, [ssys.chf.inlet.ṁ => 0.5])
    @test sol.retcode == ReturnCode.Success
    @test isapprox(sol[ssys.chf.T_out], T_INLET; rtol=1e-5)
end

@testset "Channel heated with higher wall than inlet increases temperature" begin
    n = N_DEFAULT
    @named pump = Pump(DP_PUMP)
    @named bc = HeatExchanger(T_INLET)
    @named ch = Channel(; n=n, geometry=geom,
                          h_left=H_DEFAULT, h_right=0.0)
    connections = [
        inseries(pump, bc, ch, pump),
        pump.inlet.p ~ 1.0e5,
        ch.T_wall_left .~ T_WALL,
        ch.T_wall_right .~ T_INLET,  # decorative; h_right=0
    ]
    @named sys = assembly(connections, pump, bc, ch)
    ssys = mtkcompile(sys)
    sol = solve_steady(ssys, [ssys.ch.inlet.ṁ => 0.5])
    @test sol.retcode == ReturnCode.Success
    @test sol[ssys.ch.T_out] > T_INLET
    # q_wall_left[i] finite + signed correctly (positive for T_wall > T)
    ql = sol[ssys.ch.q_wall_left[:]]
    qr = sol[ssys.ch.q_wall_right[:]]
    @test all(>(0), ql)
    @test all(isapprox.(qr, 0.0, atol=1e-9))
end

@testset "ChannelHeatFlux heated with q>0 increases temperature" begin
    n = N_DEFAULT
    dz = L_DEFAULT / n
    expected = Q_FLUX_DEFAULT * geom.heated_parts[1] * dz
    @named pump = Pump(DP_PUMP)
    @named bc = HeatExchanger(T_INLET)
    @named chf = ChannelHeatFlux(; n=n, geometry=geom)
    connections = [
        inseries(pump, bc, chf, pump),
        pump.inlet.p ~ 1.0e5,
        chf.q_left .~ Q_FLUX_DEFAULT,
        chf.q_right .~ 0.0,
    ]
    @named sys = assembly(connections, pump, bc, chf)
    ssys = mtkcompile(sys)
    sol = solve_steady(ssys, [ssys.chf.inlet.ṁ => 0.5])
    @test sol.retcode == ReturnCode.Success
    @test sol[ssys.chf.T_out] > T_INLET
    @test all(isapprox.(sol[ssys.chf.q_wall_left[:]], expected, rtol=1e-7))
    @test all(isapprox.(sol[ssys.chf.q_wall_right[:]], 0., atol=1e-9))
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
    @named pump = Pump(; ṁ0=ṁ)        # fixed-flow (current source), so ṁ is exact
    @named bc = HeatExchanger(T_INLET)
    @named chf = ChannelHeatFlux(; n=n, geometry=geom, liquid=liquid)
    connections = [
        inseries(pump, bc, chf, pump),
        pump.inlet.p ~ 1.0e5, chf.q_left .~ q, chf.q_right .~ 0.0,
    ]
    @named sys = assembly(connections, pump, bc, chf)
    ssys = mtkcompile(sys)
    sol = solve_steady(ssys, [ssys.chf.inlet.ṁ => ṁ])
    @test sol.retcode == ReturnCode.Success
    dT = q * geom.heated_parts[1] * dz / (ṁ * cp_mock)
    Tc = [sol[ssys.chf.T[i]] for i in 1:n]
    @test isapprox(Tc[1] - T_INLET, dT; rtol=1e-6)
    for i in 2:n
        @test isapprox(Tc[i] - Tc[i - 1], dT; rtol=1e-6)
    end
end

@testset "Channel wall bound to a parameter changes without recompiling" begin
    n = N_DEFAULT
    @parameters T_w = T_WALL
    @named pump = Pump(DP_PUMP)
    @named bc = HeatExchanger(T_INLET)
    @named ch = Channel(; n=n, geometry=geom, h_left=H_DEFAULT, h_right=0.0)
    connections = [
        inseries(pump, bc, ch, pump),
        pump.inlet.p ~ 1.0e5,
        ch.T_wall_left .~ T_w,
    ]
    @named sys = assembly(connections, pump, bc, ch)
    ssys = mtkcompile(sys)
    sol = solve_steady(ssys, [ssys.ch.inlet.ṁ => 0.5])
    hot = solve_steady(ssys, [ssys.ch.inlet.ṁ => 0.5, T_w => T_WALL + 50.0])
    @test sol.retcode == ReturnCode.Success
    @test hot.retcode == ReturnCode.Success
    @test all(sol[ssys.ch.T_wall_left[i]] == T_WALL for i in 1:n)
    @test all(hot[ssys.ch.T_wall_left[i]] == T_WALL + 50.0 for i in 1:n)
    @test sol[ssys.ch.T_out] < hot[ssys.ch.T_out]
end

@testset "Channel h_left::Real (broadcast) same as constant vector" begin
    n = N_DEFAULT
    @named pump = Pump(DP_PUMP)
    @named bc = HeatExchanger(T_INLET)
    @named ch = Channel(; n=n, geometry=geom,
                          h_left=H_DEFAULT, h_right=0.0)
    conns = [
        inseries(pump, bc, ch, pump),
        pump.inlet.p ~ 1.0e5,
        ch.T_wall_left .~ T_WALL,
        ch.T_wall_right .~ T_INLET,
    ]
    @named sys = assembly(conns, pump, bc, ch)
    ssys = mtkcompile(sys)
    sol = solve_steady(ssys, [ssys.ch.inlet.ṁ => 0.5])
    @test sol.retcode == ReturnCode.Success

    @named ch2 = Channel(; n=n, geometry=geom,
                           h_left=collect([H_DEFAULT for i in 1:n]), h_right=0.0)
    conns = [
        inseries(pump, bc, ch2, pump),
        pump.inlet.p ~ 1.0e5,
        ch2.T_wall_left .~ T_WALL,
        ch2.T_wall_right .~ T_INLET,
    ]
    @named sys2 = assembly(conns, pump, bc, ch2)
    ssys2 = mtkcompile(sys2)
    sol2 = solve_steady(ssys2, [ssys2.ch2.inlet.ṁ => 0.5])
    @test sol2.retcode == ReturnCode.Success
    @test all(isapprox.(sol2[ssys2.ch2.T[:]], sol[ssys.ch.T[:]], rtol=1e-6))
    @test all(isapprox.(sol2[ssys2.ch2.q_wall_left[:]], sol[ssys.ch.q_wall_left[:]], rtol=1e-6))

end

@testset "Channel h_left:: constant Function same as constant" begin
    n = N_DEFAULT
    h_fn(t) = H_DEFAULT
    @named pump = Pump(DP_PUMP)
    @named bc = HeatExchanger(T_INLET)
    @named ch = Channel(; n=n, geometry=geom,
                          h_left=h_fn, h_right=0.0)
    conns = [
        inseries(pump, bc, ch, pump),
        pump.inlet.p ~ 1.0e5,
        ch.T_wall_left .~ T_WALL,
        ch.T_wall_right .~ T_INLET,
    ]
    @named sys = assembly(conns, pump, bc, ch)
    ssys = mtkcompile(sys)
    # Callable parameter goes into the same op dict as ICs.
    sol = solve_steady(ssys, [ssys.ch.inlet.ṁ => 0.5, ssys.ch.h_left_fn => h_fn])
    @named ch2 = Channel(; n=n, geometry=geom,
                           h_left=H_DEFAULT, h_right=0.0)
    conns = [
        inseries(pump, bc, ch2, pump),
        pump.inlet.p ~ 1.0e5,
        ch2.T_wall_left .~ T_WALL,
        ch2.T_wall_right .~ T_INLET,
    ]
    @named sys2 = assembly(conns, pump, bc, ch2)
    ssys2 = mtkcompile(sys2)
    # Callable parameter goes into the same op dict as ICs.
    sol2 = solve_steady(ssys2, [ssys2.ch2.inlet.ṁ => 0.5])
    @test sol.retcode == ReturnCode.Success
    @test all(isapprox.(sol2[ssys2.ch2.T[:]], sol[ssys.ch.T[:]], rtol=1e-6))
    @test all(isapprox.(sol2[ssys2.ch2.q_wall_left[:]], sol[ssys.ch.q_wall_left[:]], rtol=1e-6))
end

@testset "CAC with HTC.DittusBoelter solves a transient without crashing" begin
    n = N_DEFAULT
    @named pump = Pump(DP_PUMP)
    @named bc = HeatExchanger(T_INLET)
    @named cac = ChannelAndContacts(; n=n, geometry=geom,
                                     htc=HTC.DittusBoelter(),
                                     darcy=Friction.Blasius())
    # Pin each cell's left thermal port T to T_WALL via per-cell ConstantTemperature.
    @named ct_l = ConstantTemperature(T_WALL; n=n)
    conns = [
        inseries(pump, bc, cac, pump),
        pump.inlet.p ~ 1.0e5,
        faces(
            (ct_l, :thermal) => (cac, :thermal_left),
            (ct_l, :thermal) => (cac, :thermal_right),
        ),
    ]
    @named sys = assembly(conns, pump, bc, cac, ct_l)
    ssys = mtkcompile(sys; fully_determined=false)
    sol = solve_transient(ssys, [ssys.cac.inlet.ṁ => 0.5], range(0.0, 1.0, length=50))
    @test sol.retcode == ReturnCode.Success
    @test sol[ssys.cac.T_out, end] > T_INLET
    @test all(>(0), sol[ssys.cac.h_tc_left[:], end])
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
        @named pump = Pump(dP_pump_iscb)
        @named cac = ChannelAndContacts(
            n=n, geometry=PipeGeometry_circular(L_ch, D_ch), htc=htc
        )
        @named bc = HeatExchanger(T_inlet_iscb)
        @named ct_l = ConstantTemperature(T_wall_bc; n=n)
        @named ct_r = ConstantTemperature(T_wall_bc; n=n)
        conns = [
            inseries(pump, bc, cac, pump),
            faces(
                (ct_l, :thermal) => (cac, :thermal_left),
                (ct_r, :thermal) => (cac, :thermal_right),
            ),
            pump.inlet.p ~ 2e5,
        ]
        @named sys = assembly(conns, pump, bc, cac, ct_l, ct_r)
        ssys = mtkcompile(sys)
        sol = solve_steady(ssys, [ssys.cac.inlet.ṁ => 0.490])
        return ssys, sol
    end

    @testset "Low T_wall -> matches single-phase exactly" begin
        # T_wall = 330K < T_sat (~393K at 2 bar) ⇒ SCB inactive, pure single-phase.
        # Both SCB and non-SCB loops solve to identical h_tc values.
        scb_fn = HTC.regime_dependent_q_scb()
        ssys_scb, sol_scb = _build_scb_loop(scb_correction=scb_fn, T_wall_bc=56.85)
        ssys_noscb, sol_noscb = _build_scb_loop(scb_correction=nothing, T_wall_bc=56.85)

        htc_scb = sol_scb[ssys_scb.cac.h_tc_left[:]]
        htc_noscb = sol_noscb[ssys_noscb.cac.h_tc_left[:]]
        @test all(isapprox.(htc_noscb, htc_scb, rtol=1e-10))
    end
end

const N_SIGN          = 5
const T_INLET_SIGN    = 40.0
const T_WALL_SIGN     = 100.0
const ṁ_NEG = -0.490
const GEOM_SIGN       = PipeGeometry_circular(0.6, 0.01)

@testset "flow reversal: Channel ṁ < 0 " begin
    @named pump = Pump(; ṁ0=ṁ_NEG)
    @named ch = Channel(; n=N_SIGN, geometry=GEOM_SIGN,
                          h_left=H_DEFAULT, h_right=0.0)
    @named bc = HeatExchanger(T_INLET_SIGN)
    conns = [
        inseries(pump, bc, ch, pump),
        pump.inlet.p ~ 1.0e5,
        ch.T_wall_left .~ T_WALL_SIGN,
        ch.T_wall_right .~ T_INLET_SIGN,
    ]
    @named sys = assembly(conns, pump, bc, ch)
    ssys = mtkcompile(sys)
    sol = solve_steady(ssys, [ssys.ch.inlet.ṁ => ṁ_NEG])

    @test sol.retcode == ReturnCode.Success

    T_vals = [sol[ssys.ch.T[i]] for i in 1:N_SIGN]
    Re_vals = [sol[ssys.ch.Re[i]] for i in 1:N_SIGN]

    @test sol[ssys.ch.inlet.ṁ] < 0
    @test all(T_vals[i] >= T_vals[i + 1] for i in 1:(N_SIGN - 1))
    @test all(Re_vals .> 0)
end

@testset "flow reversal: ChannelAndContacts ṁ < 0" begin
    @named pump = Pump(; ṁ0=ṁ_NEG)
    @named cac = ChannelAndContacts(n=N_SIGN, geometry=GEOM_SIGN)
    @named bc = HeatExchanger(T_INLET_SIGN)
    @named ct_l = ConstantTemperature(T_WALL_SIGN; n=N_SIGN)
    @named ct_r = ConstantTemperature(T_WALL_SIGN; n=N_SIGN)
    conns = [
        inseries(pump, bc, cac, pump),
        faces(
            (ct_l, :thermal) => (cac, :thermal_left),
            (ct_r, :thermal) => (cac, :thermal_right),
        ),
        pump.inlet.p ~ 1.0e5,
    ]
    @named sys = assembly(conns, pump, bc, cac, ct_l, ct_r)
    ssys = mtkcompile(sys; fully_determined=false)
    sol = solve_steady(ssys, [ssys.cac.inlet.ṁ => ṁ_NEG])

    @test sol.retcode == ReturnCode.Success

    T_vals = [sol[ssys.cac.T[i]] for i in 1:N_SIGN]
    Re_vals = [sol[ssys.cac.Re[i]] for i in 1:N_SIGN]
    vel_vals = [sol[ssys.cac.velocity[i]] for i in 1:N_SIGN]

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
    # CHF flux is intrinsic — q_left[i] sign is direction-independent.
    @named pump = Pump(; ṁ0=ṁ_NEG)
    @named chf = ChannelHeatFlux(n=N_SIGN, geometry=GEOM_SIGN)
    @named bc = HeatExchanger(T_INLET_SIGN)
    conns = [
        inseries(pump, bc, chf, pump),
        pump.inlet.p ~ 1.0e5,
        chf.q_left .~ Q_FLUX_DEFAULT,
        chf.q_right .~ 0.0,
    ]
    @named sys = assembly(conns, pump, bc, chf)
    ssys = mtkcompile(sys)
    sol = solve_steady(ssys, [ssys.chf.inlet.ṁ => ṁ_NEG])

    @test sol.retcode == ReturnCode.Success

    T_vals = sol[ssys.chf.T[:]]
    Re_vals = sol[ssys.chf.Re[:]]

    @test sol[ssys.chf.inlet.ṁ] < 0
    @test all(T_vals[i] >= T_vals[i + 1] for i in 1:(N_SIGN - 1))
    @test all(Re_vals .> 0)

    # CHF q_wall stays positive — q is intrinsic / sign-independent of flow.
    @test all(>(0), sol[ssys.chf.q_wall_left[:]])

    # Energy balance: advective heat gain ≈ summed q_wall.
    T_mean = (sol[ssys.chf.T_out] + T_INLET_SIGN) / 2
    Q_advect = abs(ṁ_NEG) * cₚ(H2O, T_mean) * (sol[ssys.chf.T_out] - T_INLET_SIGN)
    Q_wall_total = sum(sol[ssys.chf.q_wall[:]])
    @test isapprox(Q_wall_total, Q_advect; rtol=0.01)
end


@testset "Direction of flow does not matter for temperature profile" begin
    n = 3
    geom = PipeGeometry_circular(0.3, 0.01)
    Q = 800.0
    dz = 0.3 / n
    q_density_g3b = Q / (geom.heated_parts[1] * dz)
    T_in = 46.85

    function _build_loop_g3b(ṁ0)
        @named pump = Pump(; ṁ0=ṁ0)
        @named hex  = HeatExchanger(T_in)
        @named chf  = ChannelHeatFlux(; n=n, geometry=geom)
        eqs = [
            inseries(pump, hex, chf, pump),
            pump.inlet.p ~ 1.0e5, chf.q_left .~ q_density_g3b, chf.q_right .~ 0.0,
        ]
        @named sys = assembly(eqs, pump, hex, chf)
        ssys = mtkcompile(sys)
        sol = solve_steady(ssys; abstol=1e-12, reltol=1e-12)
        return ssys, sol
    end

    ssys_fwd, sol_fwd = _build_loop_g3b(+0.1)
    ssys_rev, sol_rev = _build_loop_g3b(-0.1)

    @test sol_fwd.retcode == ReturnCode.Success
    @test sol_rev.retcode == ReturnCode.Success

    T_fwd = sol_fwd[ssys_fwd.chf.T[:]]
    T_rev = sol_rev[ssys_rev.chf.T[:]]

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
    @named pump_cac = Pump(DP_PUMP)
    @named bc_cac = HeatExchanger(T_INLET)
    @named cac = ChannelAndContacts(; n=n, geometry=geom,
                                     htc=HTC.ConstantNusselt(; Nu=4.0))
    @named ct_l_xeq = ConstantTemperature(T_WALL; n=n)
    conns_cac = [
        inseries(pump_cac, bc_cac, cac, pump_cac),
        pump_cac.inlet.p ~ 1.0e5,
        faces(
            (ct_l_xeq, :thermal) => (cac, :thermal_left),
            (ct_l_xeq, :thermal) => (cac, :thermal_right),
        ),
    ]
    @named sys_cac = assembly(conns_cac, pump_cac, bc_cac, cac, ct_l_xeq)
    ssys_cac = mtkcompile(sys_cac; fully_determined=false)  # integration test: per-cell wall-T binding
    ic_cac = [
        [ssys_cac.cac.T[i] => T_INLET for i in 1:n]...,
        ssys_cac.cac.inlet.ṁ => 0.5,
    ]
    sol_cac = solve_transient(ssys_cac, ic_cac, range(0.0, 1.0, length=50))
    @test sol_cac.retcode == ReturnCode.Success
    T_out_cac = sol_cac[ssys_cac.cac.T_out, end]
    # Read CAC's converged per-cell q_density from q_wall_left.
    dz = L_DEFAULT / n
    q_per_cell = [
        sol_cac[ssys_cac.cac.q_wall_left[i], end] / (geom.heated_parts[1] * dz)
        for i in 1:n
    ]

    # CHF side: the flux pinned to per-cell q_per_cell.
    @named pump_chf = Pump(DP_PUMP)
    @named bc_chf = HeatExchanger(T_INLET)
    @named chf = ChannelHeatFlux(; n=n, geometry=geom)
    conns_chf = [
        inseries(pump_chf, bc_chf, chf, pump_chf),
        pump_chf.inlet.p ~ 1.0e5, chf.q_left .~ q_per_cell, chf.q_right .~ 0.0,
    ]
    @named sys_chf = assembly(conns_chf, pump_chf, bc_chf, chf)
    ssys_chf = mtkcompile(sys_chf)
    ic_chf = [
        [ssys_chf.chf.T[i] => T_INLET for i in 1:n]...,
        ssys_chf.chf.inlet.ṁ => 0.5,
    ]
    sol_chf = solve_transient(ssys_chf, ic_chf, range(0.0, 1.0, length=50))
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
        @named pump = Pump(dP_pump_scb)
        @named cac = ChannelAndContacts(
            n=n_scb,
            geometry=PipeGeometry_circular(L_ch_scb, D_ch_scb),
            htc=htc,
        )
        @named bc = HeatExchanger(T_inlet_scb)
        @named ct_l = ConstantTemperature(T_wall_bc; n=n_scb)
        @named ct_r = ConstantTemperature(T_wall_bc; n=n_scb)
        conns = [
            inseries(pump, bc, cac, pump),
            faces(
                (ct_l, :thermal) => (cac, :thermal_left),
                (ct_r, :thermal) => (cac, :thermal_right),
            ),
            pump.inlet.p ~ 2e5,
        ]
        @named sys = assembly(conns, pump, bc, cac, ct_l, ct_r)
        ssys = mtkcompile(sys)
        sol = solve_steady(ssys, [ssys.cac.inlet.ṁ => 0.490])
        return ssys, sol
    end

    @testset "SCB ChannelAndContacts compiles" begin
        scb_fn = HTC.regime_dependent_q_scb()
        @named cac = ChannelAndContacts(
            n=3,
            geometry=PipeGeometry_circular(L_ch_scb, D_ch_scb),
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
            h_spl = sol_scb[ssys_scb.cac.h_tc_left[i]]
            q_spl = h_spl * (T_wall - T_bulk)
            T_ONB = T_sat + _bergles_rohsenow_dT_ONB(P_cell, q_spl)
            @test T_wall < T_ONB
        end

        # Inactive SCB => identical to the plain single-phase channel.
        @test all(isapprox(sol_scb[ssys_scb.cac.h_tc_left[i]], sol_noscb[ssys_noscb.cac.h_tc_left[i]]; rtol=1e-10) for i in 1:n_scb)
        @test all(isapprox(sol_scb[ssys_scb.cac.h_tc_right[i]], sol_noscb[ssys_noscb.cac.h_tc_right[i]]; rtol=1e-10) for i in 1:n_scb)
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

        htc_scb = [sol_scb[ssys_scb.cac.h_tc_left[i]] for i in 1:n_scb]
        htc_noscb = [sol_noscb[ssys_noscb.cac.h_tc_left[i]] for i in 1:n_scb]
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
    sol = solve_steady(ssys, [ssys.ch.inlet.ṁ => 0.5])
    @test sol.retcode == ReturnCode.Success
    ch = ssys.ch

    # Total pressure at each cell's outlet-side face, and the dynamic head there.
    p_total = sol[ch.inlet.p] .- cumsum([sol[ch.dp[i]] for i in 1:n])
    head = [ρ(H2O, sol[ch.T[i]]) * sol[ch.v[i]]^2 / 2 for i in 1:n]
    @test all(head .> 0)
    @test [sol[ch.P[i]] for i in 1:n] ≈ p_total .- head rtol = 1e-12
    @test [sol[ch.T_sat[i]] for i in 1:n] ≈ [Tsat(H2O, sol[ch.P[i]]) for i in 1:n] rtol = 1e-12
end
