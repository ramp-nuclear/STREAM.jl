# Channel-family unit tests (Channel, ChannelHeatFlux, ChannelAndContacts).
#

using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using STREAM
using STREAM: Channel  # disambiguate from Base.Channel
using STREAM: regime_dependent_q_scb, _bergles_rohsenow_dT_ONB  # for the SCB integration block
using OrdinaryDiffEq: ReturnCode

const N_DEFAULT      = 4
const L_DEFAULT      = 0.6
const D_DEFAULT      = 0.01
const T_INLET        = 313.15
const T_WALL         = 373.15
const H_DEFAULT      = 5000.0
const DP_PUMP        = 3.0e4
const Q_FLUX_DEFAULT = 1.0e5

_names(sys) = string.(ModelingToolkit.getname.(ModelingToolkit.get_systems(sys)))

@testset "Channel with no h and no wall temperature gradient outputs the inlet" begin
    n = N_DEFAULT
    @named pump = Pump(DP_PUMP)
    @named bc = HeatExchanger(T_INLET)
    @named ch = Channel(; n=n, geometry=PipeGeometry_circular(L_DEFAULT, D_DEFAULT))
    connections = Equation[
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out, ch.port_in),
        connect(ch.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
        [ch.T_wall_left[i]  ~ T_INLET for i in 1:n]...,
        [ch.T_wall_right[i] ~ T_INLET for i in 1:n]...,
    ]
    @named sys = compose(System(connections, t; name=:adiab), pump, bc, ch)
    ssys = mtkcompile(sys)
    ic = Pair{Any,Any}[
        [ssys.ch.T[i] => T_INLET for i in 1:n]...,
        ssys.ch.port_in.mdot => 0.5,
    ]
    sol = solve_steady(ssys, ic)
    @test sol.retcode == ReturnCode.Success
    # T_out ≈ T_inlet — no heating
    @test isapprox(sol[ssys.ch.T_out], T_INLET; rtol=1e-5)
end

@testset "ChannelHeatFlux with zero q outputs the inlet" begin
    n = N_DEFAULT
    @named pump = Pump(DP_PUMP)
    @named bc = HeatExchanger(T_INLET)
    @named chf = ChannelHeatFlux(; n=n, geometry=PipeGeometry_circular(L_DEFAULT, D_DEFAULT))
    connections = Equation[
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out, chf.port_in),
        connect(chf.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
        [chf.q_left[i]  ~ 0.0 for i in 1:n]...,
        [chf.q_right[i] ~ 0.0 for i in 1:n]...,
    ]
    @named sys = compose(System(connections, t; name=:adiab_chf), pump, bc, chf)
    ssys = mtkcompile(sys)
    ic = Pair{Any,Any}[
        [ssys.chf.T[i] => T_INLET for i in 1:n]...,
        ssys.chf.port_in.mdot => 0.5,
    ]
    sol = solve_steady(ssys, ic)
    @test sol.retcode == ReturnCode.Success
    @test isapprox(sol[ssys.chf.T_out], T_INLET; rtol=1e-5)
end

@testset "Channel heated with higher wall than inlet increases temperature" begin
    n = N_DEFAULT
    @named pump = Pump(DP_PUMP)
    @named bc = HeatExchanger(T_INLET)
    @named ch = Channel(; n=n, geometry=PipeGeometry_circular(L_DEFAULT, D_DEFAULT),
                          h_left=H_DEFAULT, h_right=0.0)
    connections = Equation[
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out, ch.port_in),
        connect(ch.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
        [ch.T_wall_left[i]  ~ T_WALL for i in 1:n]...,
        [ch.T_wall_right[i] ~ T_INLET for i in 1:n]...,  # decorative; h_right=0
    ]
    @named sys = compose(System(connections, t; name=:s1), pump, bc, ch)
    ssys = mtkcompile(sys)
    ic = Pair{Any,Any}[
        [ssys.ch.T[i] => T_INLET for i in 1:n]...,
        ssys.ch.port_in.mdot => 0.5,
    ]
    sol = solve_steady(ssys, ic)
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
    geom = PipeGeometry_circular(L_DEFAULT, D_DEFAULT)
    dz = L_DEFAULT / n
    expected = Q_FLUX_DEFAULT * geom.heated_parts[1] * dz
    @named pump = Pump(DP_PUMP)
    @named bc = HeatExchanger(T_INLET)
    @named chf = ChannelHeatFlux(; n=n, geometry=geom)
    connections = Equation[
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out, chf.port_in),
        connect(chf.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
        [chf.q_left[i]  ~ Q_FLUX_DEFAULT for i in 1:n]...,
        [chf.q_right[i] ~ 0.0 for i in 1:n]...,
    ]
    @named sys = compose(System(connections, t; name=:s1_chf), pump, bc, chf)
    ssys = mtkcompile(sys)
    ic = Pair{Any,Any}[
        [ssys.chf.T[i] => T_INLET for i in 1:n]...,
        ssys.chf.port_in.mdot => 0.5,
    ]
    sol = solve_steady(ssys, ic)
    @test sol.retcode == ReturnCode.Success
    @test sol[ssys.chf.T_out] > T_INLET
    @test all(isapprox.(sol[ssys.chf.q_wall_left[:]], expected, rtol=1e-7))
    @test all(isapprox.(sol[ssys.chf.q_wall_right[:]], 0., atol=1e-9))
end

@testset "ChannelHeatFlux with ConstantFluid — uniform heating gives exact linear rise" begin
    # With a constant-cp mock fluid the steady cell-to-cell rise is exactly
    # ΔT = q·heated_perimeter·dz / (mdot·cp), the closed-form Python uses with mock_liquid_funcs.
    n = 8
    geom = PipeGeometry_circular(L_DEFAULT, D_DEFAULT)
    dz = L_DEFAULT / n
    cp_mock = 2000.0
    mdot = 0.5
    q = Q_FLUX_DEFAULT
    fluid = ConstantFluid(; cp=cp_mock)
    @named pump = Pump(; mdot0=mdot)        # fixed-flow (current source), so mdot is exact
    @named bc = HeatExchanger(T_INLET)
    @named chf = ChannelHeatFlux(; n=n, geometry=geom, fluid=fluid)
    connections = Equation[
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out, chf.port_in),
        connect(chf.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
        [chf.q_left[i] ~ q for i in 1:n]...,
        [chf.q_right[i] ~ 0.0 for i in 1:n]...,
    ]
    @named sys = compose(System(connections, t; name=:s1_chf_mock), pump, bc, chf)
    ssys = mtkcompile(sys)
    ic = Pair{Any,Any}[
        [ssys.chf.T[i] => T_INLET for i in 1:n]...,
        ssys.chf.port_in.mdot => mdot,
    ]
    sol = solve_steady(ssys, ic)
    @test sol.retcode == ReturnCode.Success
    dT = q * geom.heated_parts[1] * dz / (mdot * cp_mock)
    Tc = [sol[ssys.chf.T[i]] for i in 1:n]
    @test isapprox(Tc[1] - T_INLET, dT; rtol=1e-6)
    for i in 2:n
        @test isapprox(Tc[i] - Tc[i - 1], dT; rtol=1e-6)
    end
end

@testset "Channel with WallTemperature connection the same as direct equations" begin
    n = N_DEFAULT
    # Style 1 (binding eqn).
    @named pump_s1 = Pump(DP_PUMP)
    @named bc_s1 = HeatExchanger(T_INLET)
    @named ch_s1 = Channel(; n=n, geometry=PipeGeometry_circular(L_DEFAULT, D_DEFAULT),
                            h_left=H_DEFAULT, h_right=0.0)
    conns_s1 = Equation[
        connect(pump_s1.port_out, bc_s1.port_in),
        connect(bc_s1.port_out, ch_s1.port_in),
        connect(ch_s1.port_out, pump_s1.port_in),
        pump_s1.port_in.P ~ 1.0e5,
        [ch_s1.T_wall_left[i]  ~ T_WALL for i in 1:n]...,
        [ch_s1.T_wall_right[i] ~ T_INLET for i in 1:n]...,  # Decorative, h is 0
    ]
    @named sys_s1 = compose(System(conns_s1, t; name=:baseline_s1), pump_s1, bc_s1, ch_s1)
    ssys_s1 = mtkcompile(sys_s1)
    ic_s1 = Pair{Any,Any}[
        [ssys_s1.ch_s1.T[i] => T_INLET for i in 1:n]...,
        ssys_s1.ch_s1.port_in.mdot => 0.5,
    ]
    sol_s1 = solve_steady(ssys_s1, ic_s1)
    @test sol_s1.retcode == ReturnCode.Success
    mdot_s1  = sol_s1[ssys_s1.ch_s1.port_in.mdot]

    # Style 2 — WallTemperature component connection.
    @named pump = Pump(DP_PUMP)
    @named bc = HeatExchanger(T_INLET)
    @named ch = Channel(; n=n, geometry=PipeGeometry_circular(L_DEFAULT, D_DEFAULT),
                          h_left=H_DEFAULT, h_right=0.0)
    @named wt = WallTemperature(; n=n, T_wall=T_WALL)
    connections = Equation[
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out, ch.port_in),
        connect(ch.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
        [ch.T_wall_left[i]  ~ wt.T_wall_out[i] for i in 1:n]...,
        [ch.T_wall_right[i] ~ T_INLET for i in 1:n]...,  # Decorative, h is 0
    ]
    @named sys = compose(System(connections, t; name=:s2), pump, bc, ch, wt)
    ssys = mtkcompile(sys)
    ic = Pair{Any,Any}[
        [ssys.ch.T[i] => T_INLET for i in 1:n]...,
        ssys.ch.port_in.mdot => 0.5,
    ]
    sol = solve_steady(ssys, ic)
    @test sol.retcode == ReturnCode.Success
    @test isapprox(sol[ssys.ch.port_in.mdot], sol_s1[ssys_s1.ch_s1.port_in.mdot]; rtol=1e-6)
    @test all(isapprox.(sol[ssys.ch.T[:]], sol_s1[ssys_s1.ch_s1.T[:]], rtol=1e-6))
    @test all(isapprox.(sol[ssys.ch.q_wall_left[:]], sol_s1[ssys_s1.ch_s1.q_wall_left[:]], rtol=1e-6))
end

@testset "ChannelHeatFlux with HeatFluxSource connection the same as direct equations" begin
    n = N_DEFAULT
    geom = PipeGeometry_circular(L_DEFAULT, D_DEFAULT)
    @named pump_s1 = Pump(DP_PUMP)
    @named bc_s1 = HeatExchanger(T_INLET)
    @named chf_s1 = ChannelHeatFlux(; n=n, geometry=geom)
    conns_s1 = Equation[
        connect(pump_s1.port_out, bc_s1.port_in),
        connect(bc_s1.port_out, chf_s1.port_in),
        connect(chf_s1.port_out, pump_s1.port_in),
        pump_s1.port_in.P ~ 1.0e5,
        [chf_s1.q_left[i]  ~ Q_FLUX_DEFAULT for i in 1:n]...,
        [chf_s1.q_right[i] ~ 0.0 for i in 1:n]...,
    ]
    @named sys_s1 = compose(System(conns_s1, t; name=:chf_baseline_s1), pump_s1, bc_s1, chf_s1)
    ssys_s1 = mtkcompile(sys_s1)
    ic_s1 = Pair{Any,Any}[
        [ssys_s1.chf_s1.T[i] => T_INLET for i in 1:n]...,
        ssys_s1.chf_s1.port_in.mdot => 0.5,
    ]
    sol_s1 = solve_steady(ssys_s1, ic_s1)
    @test sol_s1.retcode == ReturnCode.Success

    @named pump = Pump(DP_PUMP)
    @named bc = HeatExchanger(T_INLET)
    @named chf = ChannelHeatFlux(; n=n, geometry=geom)
    @named hfs = HeatFluxSource(; n=n, q=Q_FLUX_DEFAULT)
    connections = Equation[
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out, chf.port_in),
        connect(chf.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
        [chf.q_left[i]  ~ hfs.q_out[i] for i in 1:n]...,
        [chf.q_right[i] ~ 0.0 for i in 1:n]...,
    ]
    @named sys = compose(System(connections, t; name=:chf_s2), pump, bc, chf, hfs)
    ssys = mtkcompile(sys)
    ic = Pair{Any,Any}[
        [ssys.chf.T[i] => T_INLET for i in 1:n]...,
        ssys.chf.port_in.mdot => 0.5,
    ]
    sol = solve_steady(ssys, ic)
    @test sol.retcode == ReturnCode.Success
    @test isapprox(sol[ssys.chf.port_in.mdot], sol_s1[ssys_s1.chf_s1.port_in.mdot]; rtol=1e-6)
    @test all(isapprox.(sol[ssys.chf.T[:]], sol_s1[ssys_s1.chf_s1.T[:]], rtol=1e-6))
    @test all(isapprox.(sol[ssys.chf.q_wall_left[:]], sol_s1[ssys_s1.chf_s1.q_wall_left[:]], rtol=1e-6))
end

@testset "Channel h_left::Real (broadcast) same as constant vector" begin
    n = N_DEFAULT
    @named pump = Pump(DP_PUMP)
    @named bc = HeatExchanger(T_INLET)
    @named ch = Channel(; n=n, geometry=PipeGeometry_circular(L_DEFAULT, D_DEFAULT),
                          h_left=H_DEFAULT, h_right=0.0)
    conns = Equation[
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out, ch.port_in),
        connect(ch.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
        [ch.T_wall_left[i]  ~ T_WALL for i in 1:n]...,
        [ch.T_wall_right[i] ~ T_INLET for i in 1:n]...,
    ]
    @named sys = compose(System(conns, t; name=:hreal), pump, bc, ch)
    ssys = mtkcompile(sys)
    ic = Pair{Any,Any}[
        [ssys.ch.T[i] => T_INLET for i in 1:n]...,
        ssys.ch.port_in.mdot => 0.5,
    ]
    sol = solve_steady(ssys, ic)
    @test sol.retcode == ReturnCode.Success

    @named ch2 = Channel(; n=n, geometry=PipeGeometry_circular(L_DEFAULT, D_DEFAULT),
                           h_left=collect([H_DEFAULT for i in 1:n]), h_right=0.0)
    conns = Equation[
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out, ch2.port_in),
        connect(ch2.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
        [ch2.T_wall_left[i]  ~ T_WALL for i in 1:n]...,
        [ch2.T_wall_right[i] ~ T_INLET for i in 1:n]...,
    ]
    @named sys2 = compose(System(conns, t; name=:hreal), pump, bc, ch2)
    ssys2 = mtkcompile(sys2)
    ic = Pair{Any,Any}[
        [ssys2.ch2.T[i] => T_INLET for i in 1:n]...,
        ssys2.ch2.port_in.mdot => 0.5,
    ]
    sol2 = solve_steady(ssys2, ic)
    @test sol2.retcode == ReturnCode.Success
    @test all(isapprox.(sol2[ssys2.ch2.T[:]], sol[ssys.ch.T[:]], rtol=1e-6))
    @test all(isapprox.(sol2[ssys2.ch2.q_wall_left[:]], sol[ssys.ch.q_wall_left[:]], rtol=1e-6))

end

@testset "Channel h_left:: constant Function same as constant" begin
    n = N_DEFAULT
    h_fn(t) = H_DEFAULT
    @named pump = Pump(DP_PUMP)
    @named bc = HeatExchanger(T_INLET)
    @named ch = Channel(; n=n, geometry=PipeGeometry_circular(L_DEFAULT, D_DEFAULT),
                          h_left=h_fn, h_right=0.0)
    conns = Equation[
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out, ch.port_in),
        connect(ch.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
        [ch.T_wall_left[i]  ~ T_WALL for i in 1:n]...,
        [ch.T_wall_right[i] ~ T_INLET for i in 1:n]...,
    ]
    @named sys = compose(System(conns, t; name=:hfn), pump, bc, ch)
    ssys = mtkcompile(sys)
    # Callable parameter goes into the same op dict as ICs.
    ic = Pair{Any,Any}[
        [ssys.ch.T[i] => T_INLET for i in 1:n]...,
        ssys.ch.port_in.mdot => 0.5,
        ssys.ch.h_left_fn => h_fn,
    ]
    sol = solve_steady(ssys, ic)
    @named ch2 = Channel(; n=n, geometry=PipeGeometry_circular(L_DEFAULT, D_DEFAULT),
                           h_left=H_DEFAULT, h_right=0.0)
    conns = Equation[
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out, ch2.port_in),
        connect(ch2.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
        [ch2.T_wall_left[i]  ~ T_WALL for i in 1:n]...,
        [ch2.T_wall_right[i] ~ T_INLET for i in 1:n]...,
    ]
    @named sys2 = compose(System(conns, t; name=:hfn), pump, bc, ch2)
    ssys2 = mtkcompile(sys2)
    # Callable parameter goes into the same op dict as ICs.
    ic = Pair{Any,Any}[
        [ssys2.ch2.T[i] => T_INLET for i in 1:n]...,
        ssys2.ch2.port_in.mdot => 0.5,
    ]
    sol2 = solve_steady(ssys2, ic)
    @test sol.retcode == ReturnCode.Success
    @test all(isapprox.(sol2[ssys2.ch2.T[:]], sol[ssys.ch.T[:]], rtol=1e-6))
    @test all(isapprox.(sol2[ssys2.ch2.q_wall_left[:]], sol[ssys.ch.q_wall_left[:]], rtol=1e-6))
end

@testset "CAC htc_correlation=dittus_boelter solves transient without crash" begin
    n = N_DEFAULT
    geom = PipeGeometry_circular(L_DEFAULT, D_DEFAULT)
    @named pump = Pump(DP_PUMP)
    @named bc = HeatExchanger(T_INLET)
    @named cac = ChannelAndContacts(; n=n, geometry=geom,
                                     htc_correlation=dittus_boelter,
                                     friction_correlation=blasius_friction)
    # Pin each cell's left thermal port T to T_WALL via per-cell ConstantTemperature.
    ct_l = [ConstantTemperature(T_WALL; name=Symbol(:ct_l, i)) for i in 1:n]
    conns = Equation[
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out, cac.port_in),
        connect(cac.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
        [connect(ct_l[i].thermal, getproperty(cac, Symbol(:thermal_left, i))) for i in 1:n]...,
        [connect(ct_l[i].thermal, getproperty(cac, Symbol(:thermal_right, i))) for i in 1:n]...,
    ]
    @named sys = compose(System(conns, t; name=:cac_db), pump, bc, cac, ct_l...)
    ssys = mtkcompile(sys; fully_determined=false)
    ic = Pair{Any,Any}[
        [ssys.cac.T[i] => T_INLET for i in 1:n]...,
        ssys.cac.port_in.mdot => 0.5,
    ]
    sol = solve_transient(ssys, ic, range(0.0, 1.0, length=50))
    @test sol.retcode == ReturnCode.Success
    @test sol[ssys.cac.T_out, end] > T_INLET
    @test all(>(0), sol[ssys.cac.h_tc_left[:], end])
end

@testset "ISCB: In-loop SCB Correction" begin
    n = 5
    T_inlet_iscb = 313.15
    L_ch = 0.6
    D_ch = 0.01
    dP_pump_iscb = 3.0e4

    function _build_scb_loop(; scb_correction=nothing, T_wall_bc=373.15)
        @named pump = Pump(dP_pump_iscb)
        @named cac = ChannelAndContacts(
            n=n, geometry=PipeGeometry_circular(L_ch, D_ch), scb_correction=scb_correction
        )
        @named bc = HeatExchanger(T_inlet_iscb)
        ct_l = [ConstantTemperature(T_wall_bc; name=Symbol(:ct_l, i)) for i in 1:n]
        ct_r = [ConstantTemperature(T_wall_bc; name=Symbol(:ct_r, i)) for i in 1:n]
        conns = [
            connect(pump.port_out, bc.port_in),
            connect(bc.port_out, cac.port_in),
            connect(cac.port_out, pump.port_in),
            [connect(ct_l[i].thermal, getproperty(cac, Symbol(:thermal_left, i))) for i in 1:n]...,
            [connect(ct_r[i].thermal, getproperty(cac, Symbol(:thermal_right, i))) for i in 1:n]...,
            pump.port_in.P ~ 2e5,
        ]
        @named sys = compose(System(conns, t; name=:sys), pump, bc, cac, ct_l..., ct_r...)
        ssys = mtkcompile(sys)
        Q_guess = max(1e4, 1e3 * (T_wall_bc - T_inlet_iscb))
        T_guess = steady_state_guess(T_inlet=T_inlet_iscb, Q_wall=Q_guess, mdot_guess=0.490, n=n)
        op = [ssys.cac.T[i] => T_guess[i] for i in 1:n]
        push!(op, ssys.cac.port_in.mdot => 0.490)
        sol = solve_steady(ssys, op)
        return ssys, sol
    end

    @testset "Low T_wall -> matches single-phase exactly" begin
        # T_wall = 330K < T_sat (~393K at 2 bar) ⇒ SCB inactive, pure single-phase.
        # Both SCB and non-SCB loops solve to identical h_tc values.
        scb_fn = regime_dependent_q_scb(pressure=2e5)
        ssys_scb, sol_scb = _build_scb_loop(scb_correction=scb_fn, T_wall_bc=330.0)
        ssys_noscb, sol_noscb = _build_scb_loop(scb_correction=nothing, T_wall_bc=330.0)

        htc_scb = sol_scb[ssys_scb.cac.h_tc_left[:]]
        htc_noscb = sol_noscb[ssys_noscb.cac.h_tc_left[:]]
        @test all(isapprox.(htc_noscb, htc_scb, rtol=1e-10))
    end
end

const N_SIGN          = 5
const T_INLET_SIGN    = 313.15
const T_WALL_SIGN     = 373.15
const MDOT_NEG        = -0.490
const GEOM_SIGN       = PipeGeometry_circular(0.6, 0.01)

const T_GUESS_FWD_SIGN = steady_state_guess(;
    T_inlet=T_INLET_SIGN, Q_wall=1e4, mdot_guess=abs(MDOT_NEG), n=N_SIGN
)
const T_GUESS_REV_SIGN = reverse(T_GUESS_FWD_SIGN)

@testset "flow reversal: Channel mdot < 0 " begin
    @named pump = Pump(mdot0=MDOT_NEG)
    @named ch = Channel(; n=N_SIGN, geometry=GEOM_SIGN,
                          h_left=H_DEFAULT, h_right=0.0)
    @named bc = HeatExchanger(T_INLET_SIGN)
    conns = Equation[
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out, ch.port_in),
        connect(ch.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
        [ch.T_wall_left[i]  ~ T_WALL_SIGN for i in 1:N_SIGN]...,
        [ch.T_wall_right[i] ~ T_INLET_SIGN for i in 1:N_SIGN]...,
    ]
    @named sys = compose(System(conns, t; name=:sign_ch), pump, bc, ch)
    ssys = mtkcompile(sys)
    op = [ssys.ch.T[i] => T_GUESS_REV_SIGN[i] for i in 1:N_SIGN]
    push!(op, ssys.ch.port_in.mdot => MDOT_NEG)
    sol = solve_steady(ssys, op)

    @test sol.retcode == ReturnCode.Success

    T_vals = [sol[ssys.ch.T[i]] for i in 1:N_SIGN]
    Re_vals = [sol[ssys.ch.Re[i]] for i in 1:N_SIGN]

    @test sol[ssys.ch.port_in.mdot] < 0
    @test all(T_vals[i] >= T_vals[i + 1] for i in 1:(N_SIGN - 1))
    @test all(Re_vals .> 0)
end

@testset "flow reversal: ChannelAndContacts mdot < 0" begin
    @named pump = Pump(mdot0=MDOT_NEG)
    @named cac = ChannelAndContacts(n=N_SIGN, geometry=GEOM_SIGN)
    @named bc = HeatExchanger(T_INLET_SIGN)
    ct_l = [ConstantTemperature(T_WALL_SIGN; name=Symbol(:ct_l, i)) for i in 1:N_SIGN]
    ct_r = [ConstantTemperature(T_WALL_SIGN; name=Symbol(:ct_r, i)) for i in 1:N_SIGN]
    conns = [
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out, cac.port_in),
        connect(cac.port_out, pump.port_in),
        [connect(ct_l[i].thermal, getproperty(cac, Symbol(:thermal_left, i))) for i in 1:N_SIGN]...,
        [connect(ct_r[i].thermal, getproperty(cac, Symbol(:thermal_right, i))) for i in 1:N_SIGN]...,
        pump.port_in.P ~ 1.0e5,
    ]
    @named sys = compose(System(conns, t; name=:sign_cac), pump, bc, cac, ct_l..., ct_r...)
    ssys = mtkcompile(sys; fully_determined=false)
    op = [ssys.cac.T[i] => T_GUESS_REV_SIGN[i] for i in 1:N_SIGN]
    push!(op, ssys.cac.port_in.mdot => MDOT_NEG)
    sol = solve_steady(ssys, op)

    @test sol.retcode == ReturnCode.Success

    T_vals = [sol[ssys.cac.T[i]] for i in 1:N_SIGN]
    Re_vals = [sol[ssys.cac.Re[i]] for i in 1:N_SIGN]
    vel_vals = [sol[ssys.cac.velocity[i]] for i in 1:N_SIGN]

    @test sol[ssys.cac.port_in.mdot] < 0
    @test all(T_vals[i] >= T_vals[i + 1] for i in 1:(N_SIGN - 1))
    @test all(Re_vals .> 0)
    @test all(vel_vals .> 0)

    T_mean = (sol[ssys.cac.T_out] + T_INLET_SIGN) / 2
    Q_advect = abs(MDOT_NEG) * cp_water(T_mean) * (sol[ssys.cac.T_out] - T_INLET_SIGN)
    Q_wall_total = sol[ssys.cac.Q_wall_total]
    @test isapprox(Q_wall_total, Q_advect; rtol=0.01)
end

@testset "flow reversal: ChannelHeatFlux mdot < 0" begin
    # CHF flux is intrinsic — q_left[i] sign is direction-independent.
    @named pump = Pump(mdot0=MDOT_NEG)
    @named chf = ChannelHeatFlux(n=N_SIGN, geometry=GEOM_SIGN)
    @named bc = HeatExchanger(T_INLET_SIGN)
    conns = Equation[
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out, chf.port_in),
        connect(chf.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
        [chf.q_left[i]  ~ Q_FLUX_DEFAULT for i in 1:N_SIGN]...,
        [chf.q_right[i] ~ 0.0 for i in 1:N_SIGN]...,
    ]
    @named sys = compose(System(conns, t; name=:sign_chf), pump, bc, chf)
    ssys = mtkcompile(sys)
    op = [ssys.chf.T[i] => T_GUESS_REV_SIGN[i] for i in 1:N_SIGN]
    push!(op, ssys.chf.port_in.mdot => MDOT_NEG)
    sol = solve_steady(ssys, op)

    @test sol.retcode == ReturnCode.Success

    T_vals = sol[ssys.chf.T[:]]
    Re_vals = sol[ssys.chf.Re[:]]

    @test sol[ssys.chf.port_in.mdot] < 0
    @test all(T_vals[i] >= T_vals[i + 1] for i in 1:(N_SIGN - 1))
    @test all(Re_vals .> 0)

    # CHF q_wall stays positive — q is intrinsic / sign-independent of flow.
    @test all(>(0), sol[ssys.chf.q_wall_left[:]])

    # Energy balance: advective heat gain ≈ summed q_wall.
    T_mean = (sol[ssys.chf.T_out] + T_INLET_SIGN) / 2
    Q_advect = abs(MDOT_NEG) * cp_water(T_mean) * (sol[ssys.chf.T_out] - T_INLET_SIGN)
    Q_wall_total = sum(sol[ssys.chf.q_wall[:]])
    @test isapprox(Q_wall_total, Q_advect; rtol=0.01)
end


@testset "Direction of flow does not matter for temperature profile" begin
    n = 3
    geom = PipeGeometry_circular(0.3, 0.01)
    Q = 800.0
    dz = 0.3 / n
    q_density_g3b = Q / (geom.heated_parts[1] * dz)
    T_in = 320.0

    function _build_loop_g3b(mdot0)
        @named pump = Pump(; mdot0=mdot0)
        @named hex  = HeatExchanger(T_in)
        @named chf  = ChannelHeatFlux(; n=n, geometry=geom)
        eqs = Equation[
            connect(pump.port_out, hex.port_in),
            connect(hex.port_out,  chf.port_in),
            connect(chf.port_out,  pump.port_in),
            pump.port_in.P ~ 1.0e5,
            [chf.q_left[i]  ~ q_density_g3b for i in 1:n]...,
            [chf.q_right[i] ~ 0.0 for i in 1:n]...,
        ]
        nm = mdot0 > 0 ? :g3b_loop_fwd : :g3b_loop_rev
        @named sys = compose(System(eqs, t; name=nm), pump, hex, chf)
        ssys = mtkcompile(sys)
        op = [ssys.chf.T[i] => T_in + 1.0*i for i in 1:n]
        sol = solve_steady(ssys, op; abstol=1e-12, reltol=1e-12)
        return ssys, sol
    end

    ssys_fwd, sol_fwd = _build_loop_g3b(+0.1)
    ssys_rev, sol_rev = _build_loop_g3b(-0.1)

    @test sol_fwd.retcode == ReturnCode.Success
    @test sol_rev.retcode == ReturnCode.Success

    if sol_fwd.retcode == ReturnCode.Success && sol_rev.retcode == ReturnCode.Success
        T_fwd = sol_fwd[ssys_fwd.chf.T[:]]
        T_rev = sol_rev[ssys_rev.chf.T[:]]

        # Forward profile monotone increasing.
        @test T_fwd[1] < T_fwd[2] < T_fwd[3]
        # Reverse profile monotone decreasing.
        @test T_rev[1] > T_rev[2] > T_rev[3]

        # Spatial mirror.
        @test all(isapprox.(T_rev, T_fwd[end:-1:1], rtol=1e-9))
    end
end

@testset "CAC ↔ CHF cross-equivalence" begin
    n = N_DEFAULT
    geom = PipeGeometry_circular(L_DEFAULT, D_DEFAULT)
    # CAC side: constant-Nusselt drives h_tc, ConstantTemperature pins T_wall per cell.
    @named pump_cac = Pump(DP_PUMP)
    @named bc_cac = HeatExchanger(T_INLET)
    @named cac = ChannelAndContacts(; n=n, geometry=geom,
                                     htc_correlation=constant_Nusselt(Nu=4.0))
    ct_l_xeq = [ConstantTemperature(T_WALL; name=Symbol(:ct_l_xeq, i)) for i in 1:n]
    conns_cac = Equation[
        connect(pump_cac.port_out, bc_cac.port_in),
        connect(bc_cac.port_out, cac.port_in),
        connect(cac.port_out, pump_cac.port_in),
        pump_cac.port_in.P ~ 1.0e5,
        [connect(ct_l_xeq[i].thermal, getproperty(cac, Symbol(:thermal_left, i))) for i in 1:n]...,
        [connect(ct_l_xeq[i].thermal, getproperty(cac, Symbol(:thermal_right, i))) for i in 1:n]...,
    ]
    @named sys_cac = compose(System(conns_cac, t; name=:xeq_cac), pump_cac, bc_cac, cac, ct_l_xeq...)
    ssys_cac = mtkcompile(sys_cac; fully_determined=false)  # integration test: per-cell wall-T binding
    ic_cac = Pair{Any,Any}[
        [ssys_cac.cac.T[i] => T_INLET for i in 1:n]...,
        ssys_cac.cac.port_in.mdot => 0.5,
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

    # CHF side: HeatFluxSource pinned to per-cell q_per_cell.
    @named pump_chf = Pump(DP_PUMP)
    @named bc_chf = HeatExchanger(T_INLET)
    @named chf = ChannelHeatFlux(; n=n, geometry=geom)
    @named hfs = HeatFluxSource(; n=n, q=q_per_cell)
    conns_chf = Equation[
        connect(pump_chf.port_out, bc_chf.port_in),
        connect(bc_chf.port_out, chf.port_in),
        connect(chf.port_out, pump_chf.port_in),
        pump_chf.port_in.P ~ 1.0e5,
        [chf.q_left[i]  ~ hfs.q_out[i] for i in 1:n]...,
        [chf.q_right[i] ~ 0.0 for i in 1:n]...,
    ]
    @named sys_chf = compose(System(conns_chf, t; name=:xeq_chf), pump_chf, bc_chf, chf, hfs)
    ssys_chf = mtkcompile(sys_chf)
    ic_chf = Pair{Any,Any}[
        [ssys_chf.chf.T[i] => T_INLET for i in 1:n]...,
        ssys_chf.chf.port_in.mdot => 0.5,
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
    T_inlet_scb = 313.15
    L_ch_scb = 0.6
    D_ch_scb = 0.01
    dP_pump_scb = 3.0e4

    # Helper: build a minimal loop with CAC + Pump + HeatExchanger + per-cell
    # ConstantTemperature BCs. Returns (compiled_sys, solution).
    function _build_scb_loop(; scb_correction=nothing, T_wall_bc=373.15)
        @named pump = Pump(dP_pump_scb)
        @named cac = ChannelAndContacts(
            n=n_scb,
            geometry=PipeGeometry_circular(L_ch_scb, D_ch_scb),
            scb_correction=scb_correction,
        )
        @named bc = HeatExchanger(T_inlet_scb)
        ct_l = [ConstantTemperature(T_wall_bc; name=Symbol(:ct_l_scb, i)) for i in 1:n_scb]
        ct_r = [ConstantTemperature(T_wall_bc; name=Symbol(:ct_r_scb, i)) for i in 1:n_scb]
        conns = [
            connect(pump.port_out, bc.port_in),
            connect(bc.port_out, cac.port_in),
            connect(cac.port_out, pump.port_in),
            [
                connect(ct_l[i].thermal, getproperty(cac, Symbol(:thermal_left, i)))
                for i in 1:n_scb
            ]...,
            [
                connect(ct_r[i].thermal, getproperty(cac, Symbol(:thermal_right, i)))
                for i in 1:n_scb
            ]...,
            pump.port_in.P ~ 2e5,
        ]
        @named sys = compose(
            System(conns, t; name=:sys), pump, bc, cac, ct_l..., ct_r...,
        )
        ssys = mtkcompile(sys)
        Q_guess = max(1e4, 1e3 * (T_wall_bc - T_inlet_scb))
        T_guess = steady_state_guess(
            T_inlet=T_inlet_scb, Q_wall=Q_guess, mdot_guess=0.490, n=n_scb,
        )
        op = [ssys.cac.T[i] => T_guess[i] for i in 1:n_scb]
        push!(op, ssys.cac.port_in.mdot => 0.490)
        sol = solve_steady(ssys, op)
        return ssys, sol
    end

    @testset "SCB ChannelAndContacts compiles" begin
        scb_fn = regime_dependent_q_scb(pressure=2e5)
        @named cac = ChannelAndContacts(
            n=3,
            geometry=PipeGeometry_circular(L_ch_scb, D_ch_scb),
            scb_correction=scb_fn,
        )
        @test cac isa ModelingToolkit.System
    end

    @testset "SCB ChannelAndContacts solves (sub-ONB)" begin
        # T_wall=380K < T_ONB (~408K at 2 bar): SCB present but inactive,
        # KINSOL converges.
        scb_fn = regime_dependent_q_scb(pressure=2e5)
        ssys, sol = _build_scb_loop(scb_correction=scb_fn, T_wall_bc=380.0)
        @test sol.retcode == ReturnCode.Success
    end

    @testset "Default (no SCB) backward compatibility" begin
        ssys, sol = _build_scb_loop(scb_correction=nothing, T_wall_bc=373.15)
        @test sol.retcode == ReturnCode.Success
    end

    @testset "High T_wall -> enhanced HTC (numerical)" begin
        # Direct numerical evaluation: at T_wall >> T_sat, the SCB correction
        # factor > 1. Validates the physics without requiring KINSOL convergence
        # in the boiling regime.
        T_bulk = 320.0
        P = 2e5
        T_wall = 420.0
        mdot = 0.49
        Dh = D_ch_scb
        Ac = pi/4 * Dh^2
        Re_val = abs(mdot) * Dh / (Ac * STREAM.mu_water(T_bulk))
        Pr_val =
            STREAM.cp_water(T_bulk) * STREAM.mu_water(T_bulk) /
            STREAM.k_water(T_bulk)

        h_spl =
            dittus_boelter(Re_val, Pr_val, T_bulk, T_wall) * STREAM.k_water(T_bulk) /
            Dh
        q_spl = h_spl * (T_wall - T_bulk)

        T_sat = sat_temperature(P)
        T_ONB = T_sat + _bergles_rohsenow_dT_ONB(P, q_spl)

        scb_fn = regime_dependent_q_scb(pressure=P)
        q_scb = scb_fn(T_wall, T_sat, Re_val)
        q_scb_inc = scb_fn(T_ONB, T_sat, Re_val)
        factor = partial_SCB_correction(q_spl, q_scb, q_scb_inc)

        @test T_wall > T_ONB                     # boiling is active
        @test factor > 1.0                       # correction enhances h_tc
        @test h_spl * factor > h_spl             # SCB h_tc > single-phase h_tc
    end

    @testset "Low T_wall -> matches single-phase exactly" begin
        # T_wall = 330K < T_sat (~393K at 2 bar) -> SCB inactive, pure
        # single-phase. Both SCB and non-SCB loops solve to identical h_tc values.
        scb_fn = regime_dependent_q_scb(pressure=2e5)
        ssys_scb, sol_scb = _build_scb_loop(scb_correction=scb_fn, T_wall_bc=330.0)
        ssys_noscb, sol_noscb = _build_scb_loop(scb_correction=nothing, T_wall_bc=330.0)

        htc_scb = [sol_scb[ssys_scb.cac.h_tc_left[i]] for i in 1:n_scb]
        htc_noscb = [sol_noscb[ssys_noscb.cac.h_tc_left[i]] for i in 1:n_scb]
        # Should be identical (ifelse selects uncorrected branch).
        for i in 1:n_scb
            @test htc_scb[i] ≈ htc_noscb[i] rtol=1e-10
        end
    end
end

