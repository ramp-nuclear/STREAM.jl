using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using STREAM
import STREAM:
    ChannelAndContacts,
    Pump,
    HeatExchanger,
    ConstantTemperature,
    PipeGeometry_circular,
    solve_steady,
    steady_state_guess,
    regime_dependent_q_scb

# ─────────────────────────────────────────────────────────────────────────────
# Phase 28: Subcooled Boiling Correlations
# SCB-01: McAdams_SCB_heat_flux
# SCB-02: Bergles_Rohsenow_SCB_heat_flux
# SCB-03: partial_SCB_correction
# SCB-04: regime_dependent_q_scb
# ─────────────────────────────────────────────────────────────────────────────

@testset "Subcooled Boiling Correlations" begin
    @testset "SCB-01: McAdams_SCB_heat_flux" begin
        T_sat = 373.15  # 100C at ~1 atm
        # Positive heat flux for T_wall > T_sat
        q = McAdams_SCB_heat_flux(T_sat, T_sat + 10.0)
        @test q > 0.0
        @test q isa Float64
        # Zero for T_wall <= T_sat
        @test McAdams_SCB_heat_flux(T_sat, T_sat) == 0.0
        @test McAdams_SCB_heat_flux(T_sat, T_sat - 5.0) == 0.0
        # Monotonicity: higher dT -> higher q
        q1 = McAdams_SCB_heat_flux(T_sat, T_sat + 5.0)
        q2 = McAdams_SCB_heat_flux(T_sat, T_sat + 10.0)
        q3 = McAdams_SCB_heat_flux(T_sat, T_sat + 20.0)
        @test q1 < q2 < q3
    end

    @testset "SCB-02: Bergles_Rohsenow_SCB_heat_flux" begin
        T_sat = 373.15
        pressure = 1e5  # 1 bar
        # Positive heat flux for T_wall > T_sat
        q = Bergles_Rohsenow_SCB_heat_flux(T_sat + 10.0, T_sat, pressure)
        @test q > 0.0
        @test q isa Float64
        # Zero for T_wall <= T_sat
        @test Bergles_Rohsenow_SCB_heat_flux(T_sat, T_sat, pressure) == 0.0
        @test Bergles_Rohsenow_SCB_heat_flux(T_sat - 5.0, T_sat, pressure) == 0.0
        # Accepts kwargs without error
        q_kw = Bergles_Rohsenow_SCB_heat_flux(
            T_sat + 10.0, T_sat, pressure; h_fg=2257e3, sigma=0.059
        )
        @test q_kw == q  # defaults match explicit values
        # Pressure sensitivity: different pressure gives different result
        q_2bar = Bergles_Rohsenow_SCB_heat_flux(T_sat + 10.0, T_sat, 2e5)
        @test q_2bar != q  # pressure changes the result
    end

    @testset "SCB-03: partial_SCB_correction" begin
        # Inside boiling: factor > 1.0
        factor = partial_SCB_correction(1e4, 2e4, 5e3)
        @test factor > 1.0
        # Outside boiling (q_scb <= q_scb_inc): factor = 1.0
        @test partial_SCB_correction(1e4, 5e3, 5e3) == 1.0
        @test partial_SCB_correction(1e4, 3e3, 5e3) == 1.0
        # q_spl = 0 safety: factor = 1.0
        @test partial_SCB_correction(0.0, 1e4, 5e3) == 1.0
        # Negative q_spl safety
        @test partial_SCB_correction(-100.0, 1e4, 5e3) == 1.0
    end

    @testset "SCB-04: regime_dependent_q_scb" begin
        T_sat = 373.15
        T_wall = T_sat + 10.0
        pressure = 1e5
        # Factory returns a callable
        scb_fn = regime_dependent_q_scb(pressure=pressure)
        @test scb_fn isa Function
        # Turbulent (Re >= 2300): returns McAdams value
        q_turb = scb_fn(T_wall, T_sat, 5000.0)
        q_mcadams = McAdams_SCB_heat_flux(T_sat, T_wall)
        @test q_turb == q_mcadams
        # Laminar (Re < 2300): returns Bergles-Rohsenow value
        q_lam = scb_fn(T_wall, T_sat, 1000.0)
        q_br = Bergles_Rohsenow_SCB_heat_flux(T_wall, T_sat, pressure)
        @test q_lam == q_br
        # Custom Re_transition shifts cutoff
        scb_fn2 = regime_dependent_q_scb(pressure=pressure, Re_transition=5000)
        @test scb_fn2(T_wall, T_sat, 3000.0) == q_br  # now laminar at Re=3000
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# ISCB: In-loop SCB Correction Integration Tests
# ISCB-01: ChannelAndContacts with scb_correction solves without error
# ISCB-02: SCB-corrected HTC > uncorrected when T_wall >> T_sat;
#           SCB-corrected HTC == uncorrected when T_wall < T_ONB
# ─────────────────────────────────────────────────────────────────────────────
@testset "ISCB: In-loop SCB Correction" begin
    n = 5;
    T_inlet = 313.15;
    L_ch = 0.6;
    D_ch = 0.01;
    dP_pump = 3.0e4

    # Helper: build a minimal loop with ChannelAndContacts + Pump + HeatExchanger + ConstantTemperature BCs.
    # Returns (compiled_sys, solution). T_wall must be below T_ONB for KINSOL convergence
    # (SCB correction factors are 10-100x, which makes fully-boiling steady-state stiff for Newton).
    function _build_scb_loop(; scb_correction=nothing, T_wall_bc=373.15)
        @named pump = Pump(dP_pump)
        @named cac = ChannelAndContacts(
            n=n, geometry=PipeGeometry_circular(L_ch, D_ch), scb_correction=scb_correction
        )
        @named bc = HeatExchanger(T_inlet)
        ct_l = [ConstantTemperature(T_wall_bc; name=Symbol(:ct_l, i)) for i in 1:n]
        ct_r = [ConstantTemperature(T_wall_bc; name=Symbol(:ct_r, i)) for i in 1:n]
        conns = [
            connect(pump.outlet, bc.inlet),
            connect(bc.outlet, cac.inlet),
            connect(cac.outlet, pump.inlet),
            [
                connect(ct_l[i].thermal, getproperty(cac, Symbol(:thermal_left, i))) for
                i in 1:n
            ]...,
            [
                connect(ct_r[i].thermal, getproperty(cac, Symbol(:thermal_right, i))) for
                i in 1:n
            ]...,
            pump.inlet.P ~ 2e5,
        ]
        @named sys = compose(System(conns, t; name=:sys), pump, bc, cac, ct_l..., ct_r...)
        ssys = mtkcompile(sys)
        Q_guess = max(1e4, 1e3 * (T_wall_bc - T_inlet))
        T_guess = steady_state_guess(T_inlet=T_inlet, Q_wall=Q_guess, mdot_guess=0.490, n=n)
        op = [ssys.cac.T[i] => T_guess[i] for i in 1:n]
        push!(op, ssys.cac.inlet.mdot => 0.490)
        sol = solve_steady(ssys, op)
        return ssys, sol
    end

    @testset "ISCB-01: SCB ChannelAndContacts compiles" begin
        # Verify mtkcompile succeeds with SCB correction — structural correctness
        scb_fn = regime_dependent_q_scb(pressure=2e5)
        @named cac = ChannelAndContacts(
            n=3, geometry=PipeGeometry_circular(L_ch, D_ch), scb_correction=scb_fn
        )
        @test cac isa ModelingToolkit.System
    end

    @testset "ISCB-01: SCB ChannelAndContacts solves (sub-ONB)" begin
        # T_wall=380K < T_ONB (~408K at 2 bar): SCB present but inactive => KINSOL converges
        scb_fn = regime_dependent_q_scb(pressure=2e5)
        ssys, sol = _build_scb_loop(scb_correction=scb_fn, T_wall_bc=380.0)
        @test sol.retcode == ReturnCode.Success
    end

    @testset "ISCB-01: Default (no SCB) backward compatibility" begin
        ssys, sol = _build_scb_loop(scb_correction=nothing, T_wall_bc=373.15)
        @test sol.retcode == ReturnCode.Success
    end

    @testset "ISCB-02: High T_wall -> enhanced HTC (numerical)" begin
        # Direct numerical evaluation: at T_wall >> T_sat, the SCB correction factor > 1
        # This validates the physics without requiring KINSOL convergence in the boiling regime.
        T_bulk = 320.0;
        P = 2e5;
        T_wall = 420.0
        mdot = 0.49;
        Dh = D_ch;
        Ac = pi/4 * Dh^2
        Re_val = abs(mdot) * Dh / (Ac * STREAM.mu_water(T_bulk))
        Pr_val = STREAM.cp_water(T_bulk) * STREAM.mu_water(T_bulk) / STREAM.k_water(T_bulk)

        h_spl = dittus_boelter(Re_val, Pr_val, T_bulk, T_wall) * STREAM.k_water(T_bulk) / Dh
        q_spl = h_spl * (T_wall - T_bulk)

        T_sat = sat_temperature(P)
        import STREAM: _bergles_rohsenow_dT_ONB
        T_ONB = T_sat + _bergles_rohsenow_dT_ONB(P, q_spl)

        scb_fn = regime_dependent_q_scb(pressure=P)
        q_scb = scb_fn(T_wall, T_sat, Re_val)
        q_scb_inc = scb_fn(T_ONB, T_sat, Re_val)
        factor = partial_SCB_correction(q_spl, q_scb, q_scb_inc)

        @test T_wall > T_ONB                     # boiling is active
        @test factor > 1.0                        # correction enhances h_tc
        @test h_spl * factor > h_spl              # SCB h_tc > single-phase h_tc
    end

    @testset "ISCB-02: Low T_wall -> matches single-phase exactly" begin
        # T_wall = 330K < T_sat (~393K at 2 bar) -> SCB inactive, pure single-phase
        # Both SCB and non-SCB loops solve to identical h_tc values
        scb_fn = regime_dependent_q_scb(pressure=2e5)
        ssys_scb, sol_scb = _build_scb_loop(scb_correction=scb_fn, T_wall_bc=330.0)
        ssys_noscb, sol_noscb = _build_scb_loop(scb_correction=nothing, T_wall_bc=330.0)

        htc_scb = [sol_scb[ssys_scb.cac.h_tc[i]] for i in 1:n]
        htc_noscb = [sol_noscb[ssys_noscb.cac.h_tc[i]] for i in 1:n]
        # Should be identical (ifelse selects uncorrected branch)
        for i in 1:n
            @test htc_scb[i] ≈ htc_noscb[i] rtol=1e-10
        end
    end
end
