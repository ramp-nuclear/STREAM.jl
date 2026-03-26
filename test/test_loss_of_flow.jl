using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using DifferentialEquations
using Statistics
using STREAM

# ─────────────────────────────────────────────────────────────────────────────
# Loss-of-Flow (LOF) transient validation — Phase 24.1
#
# Topology: 4-node parallel bypass (build_loop_lof_bypass)
#   Node A (top): ine output, ch input (ChannelHeatFlux, g=-g_acc), flapper input
#   Node B (bottom): ch output, ret input (Channel, g=+g_acc)
#   Node C (top): ret output, flapper output, ext_res input
#   D series: ext_res -> hx -> pump -> ine
#
# Gravity signs:
#   ch (A->B, downward): g = -BYPASS_G_ACC  (gravity assists downward flow)
#   ret (B->C, upward):  g = +BYPASS_G_ACC  (gravity opposes upward flow)
#
# IC strategy:
#   Reference loop: Pump(DP_REF) -> HX(T_inlet) -> ChannelHeatFlux(g=-G_ACC) -> Pump
#   Solve SS to get mdot_ss and T_ss[1:n]. Transfer to bypass system IC via NoInit.
#
# LOF-03: ch has g=-G_ACC (assists downward flow). Positive mdot = downward (A->B).
#   After NC: flow reverses to upward, ch.port_in.mdot < 0.
# ─────────────────────────────────────────────────────────────────────────────

const BYPASS_N        = 10
const BYPASS_L_CH     = 1.0
const BYPASS_D_CH     = 0.01
const BYPASS_T_WALL   = 373.15
const BYPASS_T_INLET  = 313.15
const BYPASS_G_ACC    = 9.80665
const BYPASS_L_OVER_A = 1.75e5
const BYPASS_R_EXT    = 1.0e6
const BYPASS_THRESHOLD = 0.01
const BYPASS_DT_RAMP  = 5.0
const BYPASS_DP_REF   = 1.5e4

# ─────────────────────────────────────────────────────────────────────────────
# Helper: solve SS reference loop, build bypass system, return (ssys, op, mdot_ss, cb)
#
# IC strategy:
#   - ine.port_in.mdot = mdot_ss (total loop flow)
#   - ret.port_in.mdot = mdot_ss (all flow through ch-ret path; flapper closed at t=0)
#   - Dt(ret.port_in.mdot) = 0.0 (index-reduced derivative state; zero at quasi-SS t=0)
#   - flapper.T_open = 1e30 (sentinel: flapper not yet fired)
#
# Callback strategy (use_callback=false in Flapper):
#   MTK's SymbolicContinuousCallback is incompatible with parallel topologies where
#   channel inertia (Dt(mdot)) appears in the callback's pressure balance equations,
#   causing UnsolvableCallbackError. Instead, we build a native DifferentialEquations
#   ContinuousCallback that monitors ine.port_in.mdot and directly sets T_open in u.
# ─────────────────────────────────────────────────────────────────────────────
function _lof_bypass_ic(; n=BYPASS_N)
    # Reference loop for SS: Pump -> HX -> ChannelHeatFlux -> Pump
    # No Flapper, no Inertia -> KINSOL-friendly
    # ch_ref uses g=-BYPASS_G_ACC (same gravity orientation as bypass ch)
    @named pump_ref = Pump(BYPASS_DP_REF)
    @named hx_ref   = HeatExchanger(BYPASS_T_INLET)
    @named ch_ref   = ChannelHeatFlux(n=n,
                          geometry = PipeGeometry_circular(BYPASS_L_CH, BYPASS_D_CH),
                          g        = -BYPASS_G_ACC,
                          T_wall   = BYPASS_T_WALL)

    conns_ref = [
        connect(pump_ref.port_out, hx_ref.port_in),
        connect(hx_ref.port_out,   ch_ref.port_in),
        connect(ch_ref.port_out,   pump_ref.port_in),
        pump_ref.port_in.P ~ 1.0e5,
    ]
    @named ref_sys = compose(System(conns_ref, t; name=:ref), pump_ref, hx_ref, ch_ref)
    ref_ssys = mtkcompile(ref_sys)

    op_ref = Pair{Any,Any}[ref_ssys.ch_ref.port_in.mdot => 0.3]
    for i in 1:n
        push!(op_ref, ref_ssys.ch_ref.T[i] => BYPASS_T_INLET + i * (BYPASS_T_WALL - BYPASS_T_INLET) / n)
    end
    ss_sol = solve_steady(ref_ssys, op_ref)

    mdot_ss = ss_sol[ref_ssys.ch_ref.port_in.mdot]
    T_ss    = [ss_sol[ref_ssys.ch_ref.T[i]] for i in 1:n]

    # Build bypass system (Flapper has use_callback=false)
    ssys = build_loop_lof_bypass(;
        n         = n,
        L_ch      = BYPASS_L_CH,
        D_ch      = BYPASS_D_CH,
        T_wall    = BYPASS_T_WALL,
        T_inlet   = BYPASS_T_INLET,
        L_over_A  = BYPASS_L_OVER_A,
        g_acc     = BYPASS_G_ACC,
        R_ext     = BYPASS_R_EXT,
        threshold = BYPASS_THRESHOLD,
        dt_ramp   = BYPASS_DT_RAMP,
    )

    Dt = Differential(t)
    op = Pair{Any,Any}[
        ssys.ine.port_in.mdot        => mdot_ss,  # total loop flow
        ssys.ret.port_in.mdot        => mdot_ss,  # all flow through ch-ret (flapper closed)
        Dt(ssys.ret.port_in.mdot)    => 0.0,      # index-reduced derivative state
        ssys.flapper.T_open          => 1.0e30,   # sentinel: not yet fired
    ]
    for i in 1:n
        push!(op, ssys.ch.T[i] => T_ss[i])
    end
    for i in 1:n
        push!(op, ssys.ret.T[i] => BYPASS_T_INLET)
    end

    # Build native callback: monitors ine.port_in.mdot crossing threshold (downward).
    # When mdot drops below BYPASS_THRESHOLD, latch T_open = current solver time.
    # This replaces MTK's SymbolicContinuousCallback which cannot handle the parallel
    # topology's pressure balance equations that contain Dt(mdot) inertia terms.
    i_T_open   = ModelingToolkit.variable_index(ssys, ssys.flapper.T_open)
    i_ine_mdot = ModelingToolkit.variable_index(ssys, ssys.ine.port_in.mdot)
    cb = ContinuousCallback(
        (u, t, integrator) -> u[i_ine_mdot] - BYPASS_THRESHOLD,
        nothing,                                         # ignore upward crossing
        (integrator) -> (integrator.u[i_T_open] = integrator.t),  # downward: latch T_open
    )

    return ssys, op, mdot_ss, cb
end

# ─────────────────────────────────────────────────────────────────────────────
# LOF-01: bypass topology compiles and SS IC is physical
# ─────────────────────────────────────────────────────────────────────────────
@testset "LOF-01: bypass topology compiles and SS IC is physical" begin
    ssys, op, mdot_ss, _ = _lof_bypass_ic()

    @test length(equations(ssys)) == length(unknowns(ssys))
    @test 0.001 < mdot_ss < 1.0

    T_open_init = op[findfirst(p -> isequal(p.first, ssys.flapper.T_open), op)].second
    @test T_open_init == 1.0e30
end

# ─────────────────────────────────────────────────────────────────────────────
# LOF-02: Flapper fires at correct threshold
# ─────────────────────────────────────────────────────────────────────────────
@testset "LOF-02: Flapper fires at correct threshold" begin
    ssys, op, _, cb = _lof_bypass_ic()

    t_arr = range(0.0, 300.0; length=3001)
    sol   = solve_transient(ssys, op, t_arr; callbacks=cb)

    @test sol.retcode == ReturnCode.Success

    T_open_end = sol[ssys.flapper.T_open, end]
    @test T_open_end < 1.0e10
    @test T_open_end >= 0.0
    @test isapprox(sol[ssys.flapper.xi, end], 1.0; atol=1e-4)
end

# ─────────────────────────────────────────────────────────────────────────────
# LOF-03: channel flow reversal — ch.port_in.mdot crosses zero
# ch has g=-G_ACC (assists downward flow). Positive mdot = downward (A->B).
# After NC establishes, ch reverses to upward: mdot < 0.
# ─────────────────────────────────────────────────────────────────────────────
@testset "LOF-03: channel flow reversal (mdot crosses zero)" begin
    ssys, op, _, cb = _lof_bypass_ic()

    t_arr = range(0.0, 300.0; length=3001)
    sol   = solve_transient(ssys, op, t_arr; callbacks=cb)

    mdot_ch_initial = sol[ssys.ch.port_in.mdot, 1]
    @test mdot_ch_initial > 0.0

    mdot_ch_final = sol[ssys.ch.port_in.mdot, end]
    @test mdot_ch_final < 0.0

    mdot_nc = abs(mdot_ch_final)
    @test 0.001 < mdot_nc < 2.0
end

# ─────────────────────────────────────────────────────────────────────────────
# VAL-01: energy balance at 5 checkpoints (rtol=5%)
#
# Energy balance: Q_wall = |mdot| * cp * |T_outlet - T_inlet_to_ch|
#
# Forward flow (mdot > 0): fluid enters ch via port_in from the HX chain.
#   T_inlet_to_ch ≈ BYPASS_T_INLET (HX forces T_bc); T_outlet = T[n] (≈ T_max).
#
# Backward flow / NC (mdot < 0): fluid enters ch via port_out from Node B (ret side).
#   T_inlet_to_ch = ret.T[1] (what ret offers at port_in = Node B interface);
#   T_outlet = T[1] (≈ T_max). This is exact at NC steady state: Q_wall ≈ 0.3%.
# ─────────────────────────────────────────────────────────────────────────────
@testset "VAL-01: energy balance at 5 checkpoints (rtol=5%)" begin
    ssys, op, _, cb = _lof_bypass_ic()

    t_arr = range(0.0, 300.0; length=3001)
    sol   = solve_transient(ssys, op, t_arr; callbacks=cb)

    n           = BYPASS_N
    checkpoints = [1, 751, 1501, 2251, 3001]

    for idx in checkpoints
        mdot_v = abs(sol[ssys.ch.port_in.mdot, idx])
        mdot_v < 1e-6 && continue
        T_cells = [sol[ssys.ch.T[i], idx] for i in 1:n]
        Q_wall  = abs(sum(sol[ssys.ch.q_wall[i], idx] for i in 1:n))
        if sol[ssys.ch.port_in.mdot, idx] >= 0.0
            # Forward flow: inlet = BYPASS_T_INLET (from HX chain), outlet = T[n]
            T_inlet_ch = BYPASS_T_INLET
            T_outlet_ch = T_cells[n]
        else
            # Backward flow (NC): inlet = ret.T[1] at Node B, outlet = T[1]
            T_inlet_ch  = sol[ssys.ret.T[1], idx]
            T_outlet_ch = T_cells[1]
        end
        Q_meas = mdot_v * cp_water(BYPASS_T_INLET) * abs(T_outlet_ch - T_inlet_ch)
        @test isapprox(Q_meas, Q_wall; rtol=0.05)
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# VAL-02: NC equilibrium mdot within 30% of analytical buoyancy estimate
#
# In the bypass topology, the NC closed loop is ch (hot, upward) + ret (cold,
# downward). Both channels carry the same |mdot_nc| and have identical geometry.
# Full loop friction = 2 × channel friction:
#   δρ * g * L = 2 × f * (L/Dh) × mdot² / (2 * rho * A²)
#              = f * (L/Dh) × mdot² / (rho * A²)
# Solving for mdot:
#   mdot = sqrt(δρ * g * rho * A² * Dh / f)   [note: factor of 2 cancels L]
#
# 30% tolerance: accounts for temperature-dependent property variations and
# the small but non-zero ext_res bypass flow that slightly reduces NC mdot.
# ─────────────────────────────────────────────────────────────────────────────
@testset "VAL-02: NC equilibrium mdot within 30% of analytical buoyancy estimate" begin
    ssys, op, _, cb = _lof_bypass_ic()

    t_arr = range(0.0, 300.0; length=3001)
    sol   = solve_transient(ssys, op, t_arr; callbacks=cb)

    n          = BYPASS_N
    nc_indices = 2701:3001

    mdot_nc_series = abs.(sol[ssys.ch.port_in.mdot, nc_indices])
    mdot_nc        = mean(mdot_nc_series)

    T_max_nc = mean([maximum([sol[ssys.ch.T[i], idx] for i in 1:n]) for idx in nc_indices])

    geom = PipeGeometry_circular(BYPASS_L_CH, BYPASS_D_CH)
    A_xs = geom.A
    Dh   = geom.Dh

    T_hot_avg = (BYPASS_T_INLET + T_max_nc) / 2
    rho_cold  = rho_water(BYPASS_T_INLET)
    rho_hot   = rho_water(T_hot_avg)
    delta_rho = rho_cold - rho_hot

    Re_nc = mdot_nc * Dh / (A_xs * mu_water(T_hot_avg))
    f_nc  = 0.316 * Re_nc^(-0.25)
    # Full loop (ch + ret, same geometry): 2x friction → factor of 2 cancels in sqrt
    mdot_analytical = sqrt(delta_rho * BYPASS_G_ACC * BYPASS_L_CH *
                           rho_hot * A_xs^2 * Dh / (f_nc * BYPASS_L_CH))

    # 30% tolerance: accounts for property variations and small ext_res bypass flow
    @test isapprox(mdot_nc, mdot_analytical; rtol=0.30)

    # VAL-02 temperature rise: NC-phase dT through heated channel (ch) matches
    # Elenbaas analytical estimate (D-14, D-15).
    #
    # In reversed NC flow, fluid enters ch at Node B (ret.T[1]) and exits at Node A (ch.T[1]).
    # The actual inlet temperature to ch is ret.T[1], which is > BYPASS_T_INLET because the
    # return channel cools the fluid but not fully back to T_inlet.
    # We measure the actual temperature rise through ch: T_max_nc - T_inlet_nc.
    T_inlet_nc = mean([sol[ssys.ret.T[1], idx] for idx in nc_indices])
    T_bulk_nc  = (BYPASS_T_INLET + T_max_nc) / 2
    htc_fn_nc  = elenbaas_htc(b=BYPASS_D_CH, L=BYPASS_L_CH, Dh=BYPASS_D_CH, g=BYPASS_G_ACC)
    Pr_nc      = cp_water(T_bulk_nc) * mu_water(T_bulk_nc) / k_water(T_bulk_nc)
    Nu_nc      = htc_fn_nc(0.0, Pr_nc, T_bulk_nc, BYPASS_T_WALL)
    h_nc       = Nu_nc * k_water(T_bulk_nc) / BYPASS_D_CH
    A_heated   = pi * BYPASS_D_CH * BYPASS_L_CH
    DeltaT_analytical = (BYPASS_T_WALL - BYPASS_T_INLET) *
                        (1 - exp(-h_nc * A_heated / (mdot_nc * cp_water(BYPASS_T_INLET))))
    @test isapprox(T_max_nc - T_inlet_nc, DeltaT_analytical; rtol=0.30)
end
