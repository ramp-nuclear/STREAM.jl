using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using DifferentialEquations
using Statistics
using STREAM

# ─────────────────────────────────────────────────────────────────────────────
# Loss-of-Flow (LOF) transient validation — Phase 24
#
# Topology: series loop with Flapper check valve
#   Pump(0) → Inertia → HeatExchanger(T_inlet) → ChannelHeatFlux(g=+9.8) → Flapper → Pump
#
# Physics:
#   - g_acc_ch = +9.80665 m/s² (upward channel orientation; gravity opposes positive flow)
#   - Pump produces zero pressure rise; Inertia carries initial forced-flow momentum
#   - Flow decays as gravity + friction + Flapper(R_closed=1e8) remove momentum
#   - Flapper fires when ine.port_in.mdot drops below threshold → resistance ramps down
#   - After Flapper opens, gravity drives a stable reversed (downward) flow (natural circ)
#
# IC strategy:
#   - Reference loop (Pump(dP=1.5e4) → HX → ChannelHeatFlux, no Flapper/Inertia) gives SS
#   - T cells and mdot from SS applied to LOF system via Pair{Any,Any} op + NoInit
#
# Energy balance assertion (VAL-01, VAL-02):
#   Q_meas = |mdot| * cp_water(T_inlet) * |T_max_cells - T_inlet|
#   where T_max_cells = maximum(T[1..n]) at the sampling instant.
#   This formula is valid in both phases:
#     Forward flow: T_max = T[n] (outlet, top), T_inlet at port_in (bottom) — normal heating
#     Reversed flow: T_max = T[1] (exit, bottom, hottest cell), T_inlet enters at port_out top
#   Tolerance: 5% rtol (VAL-01, 5 checkpoints); 10% rtol (VAL-02, last-10%-window average)
# ─────────────────────────────────────────────────────────────────────────────

# Shared parameters for all LOF tests
const LOF_N        = 10
const LOF_L_CH     = 1.0
const LOF_D_CH     = 0.01
const LOF_T_WALL   = 373.15
const LOF_T_INLET  = 313.15
const LOF_G_ACC    = 9.80665
const LOF_L_OVER_A = 1.75e5
const LOF_THRESHOLD = 0.01
const LOF_DT_RAMP  = 5.0
const LOF_DP_REF   = 1.5e4    # reference pump dP for SS IC generation

# ─────────────────────────────────────────────────────────────────────────────
# Helper: build reference series loop (no Flapper/Inertia) and solve SS.
# Returns (ssys_lof, op, mdot_ss) where op is the Pair{Any,Any} IC vector.
# ─────────────────────────────────────────────────────────────────────────────
function _lof_ic(; n=LOF_N)
    # Reference loop: Pump(dP) -> HX -> ChannelHeatFlux; matches LOF topology
    # minus the Inertia and Flapper so KINSOL can converge without T_open Jacobian issue
    @named pump_ref = Pump(LOF_DP_REF)
    @named bc_ref   = HeatExchanger(T_bc=LOF_T_INLET)
    @named ch_ref   = ChannelHeatFlux(n=n,
                          geometry = PipeGeometry_circular(LOF_L_CH, LOF_D_CH),
                          g        = LOF_G_ACC,
                          T_wall   = LOF_T_WALL)
    conns_ref = [
        connect(pump_ref.port_out, bc_ref.port_in),
        connect(bc_ref.port_out,   ch_ref.port_in),
        connect(ch_ref.port_out,   pump_ref.port_in),
        pump_ref.port_in.P ~ 1.0e5,
        ch_ref.port_in.T   ~ LOF_T_INLET,
    ]
    @named ref_sys = compose(System(conns_ref, t; name=:ref), pump_ref, bc_ref, ch_ref)
    ref_ssys = mtkcompile(ref_sys)

    # Initial guess for KINSOL: linearly interpolated T cells
    op_ref = Pair{Any,Any}[ref_ssys.ch_ref.port_in.mdot => 0.1]
    for i in 1:n
        push!(op_ref, ref_ssys.ch_ref.T[i] => LOF_T_INLET + i * (LOF_T_WALL - LOF_T_INLET) * 0.1)
    end
    ss_sol = solve_steady(ref_ssys, op_ref)

    mdot_ss = ss_sol[ref_ssys.ch_ref.port_in.mdot]
    T_ss    = [ss_sol[ref_ssys.ch_ref.T[i]] for i in 1:n]

    # Build LOF system
    ssys = build_loop_lof(; n=n, L_ch=LOF_L_CH, D_ch=LOF_D_CH,
                            T_wall=LOF_T_WALL, T_inlet=LOF_T_INLET,
                            L_over_A=LOF_L_OVER_A, g_acc_ch=LOF_G_ACC,
                            threshold=LOF_THRESHOLD, dt_ramp=LOF_DT_RAMP)

    # IC vector: inertia mdot + Flapper sentinel + T cells
    op = Pair{Any,Any}[
        ssys.ine.port_in.mdot => mdot_ss,
        ssys.flapper.T_open   => 1.0e30,
    ]
    for i in 1:n
        push!(op, ssys.ch.T[i] => T_ss[i])
    end

    return ssys, op, mdot_ss
end

# ─────────────────────────────────────────────────────────────────────────────
# LOF-01: system compiles and steady-state reference IC is physically reasonable
# ─────────────────────────────────────────────────────────────────────────────
@testset "LOF-01: build_loop_lof compiles and SS IC is physical" begin
    ssys, op, mdot_ss = _lof_ic()

    # System is well-determined
    @test length(equations(ssys)) == length(unknowns(ssys))

    # SS mdot is in a physically reasonable range (5 mL/s to 1 L/s for this geometry)
    @test 0.01 < mdot_ss < 1.0

    # T_open initial value is the sentinel
    T_open_init = op[findfirst(p -> isequal(p.first, ssys.flapper.T_open), op)].second
    @test T_open_init == 1.0e30
end

# ─────────────────────────────────────────────────────────────────────────────
# LOF-02: transient run completes without error (retcode = Success)
# ─────────────────────────────────────────────────────────────────────────────
@testset "LOF-02: transient solve completes successfully" begin
    ssys, op, mdot_ss = _lof_ic()

    t_arr = range(0.0, 300.0; length=3001)
    sol   = solve_transient(ssys, op, t_arr)

    @test sol.retcode == ReturnCode.Success
end

# ─────────────────────────────────────────────────────────────────────────────
# LOF-03: Flapper fires (mdot drops below threshold → T_open is set)
# ─────────────────────────────────────────────────────────────────────────────
@testset "LOF-03: Flapper event fires during transient" begin
    ssys, op, mdot_ss = _lof_ic()

    t_arr = range(0.0, 300.0; length=3001)
    sol   = solve_transient(ssys, op, t_arr)

    T_open_end = sol[ssys.flapper.T_open, end]

    # Event fired: T_open is no longer the 1e30 sentinel
    @test T_open_end < 1.0e10

    # Event fired at a positive time (not at t=0 where mdot > threshold)
    @test T_open_end >= 0.0

    # Ramp complete by t=300s (T_open + dt_ramp << 300s)
    @test isapprox(sol[ssys.flapper.xi, end], 1.0; atol=1e-4)
end

# ─────────────────────────────────────────────────────────────────────────────
# LOF-04: flow reversal — mdot sign changes from positive to negative
# ─────────────────────────────────────────────────────────────────────────────
@testset "LOF-04: flow reversal occurs (mdot sign reversal)" begin
    ssys, op, mdot_ss = _lof_ic()

    t_arr = range(0.0, 300.0; length=3001)
    sol   = solve_transient(ssys, op, t_arr)

    # Initial mdot is positive (forward flow)
    @test sol[ssys.ine.port_in.mdot, 1] > 0.0

    # Final mdot is negative (reversed natural circulation)
    @test sol[ssys.ine.port_in.mdot, end] < 0.0

    # NC magnitude is physically reasonable (>0.01 kg/s, <2 kg/s for this geometry)
    mdot_nc = abs(sol[ssys.ine.port_in.mdot, end])
    @test 0.01 < mdot_nc < 2.0
end

# ─────────────────────────────────────────────────────────────────────────────
# VAL-01: energy balance throughout the full transient (5 checkpoints)
#
# Q_wall_total (computed from Dittus-Boelter HTC via q_wall[i] observables) must
# match the advective heat pickup by the fluid:
#   Q_meas = |mdot| * cp_water(T_inlet) * (T_max_cells - T_inlet)
#
# The formula uses T_max over all cells because the "outlet" temperature is T[n]
# in forward flow and T[1] in reversed flow. T_max selects the correct endpoint
# in both regimes without requiring explicit direction detection.
#
# Tolerance: 5% rtol at each of 5 evenly-spaced checkpoints.
# ─────────────────────────────────────────────────────────────────────────────
@testset "VAL-01: energy balance at 5 checkpoints (rtol=5%)" begin
    ssys, op, mdot_ss = _lof_ic()

    t_arr = range(0.0, 300.0; length=3001)
    sol   = solve_transient(ssys, op, t_arr)

    n = LOF_N
    checkpoints = [1, 751, 1501, 2251, 3001]   # t = 0, 75, 150, 225, 300 s

    for idx in checkpoints
        mdot_v  = abs(sol[ssys.ine.port_in.mdot, idx])
        T_cells = [sol[ssys.ch.T[i], idx] for i in 1:n]
        T_max_v = maximum(T_cells)
        Q_wall  = abs(sum(sol[ssys.ch.q_wall[i], idx] for i in 1:n))
        Q_meas  = mdot_v * cp_water(LOF_T_INLET) * abs(T_max_v - LOF_T_INLET)

        @test isapprox(Q_meas, Q_wall; rtol=0.05)
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# VAL-02: energy balance in quasi-steady natural circulation (last 10% of run)
#
# Average energy balance over t = 270 s to 300 s (last 10% of 300 s window).
# Tolerance: 10% rtol (relaxed from VAL-01 to account for time-averaging noise).
# ─────────────────────────────────────────────────────────────────────────────
@testset "VAL-02: NC energy balance in quasi-steady regime (rtol=10%)" begin
    ssys, op, mdot_ss = _lof_ic()

    t_arr = range(0.0, 300.0; length=3001)
    sol   = solve_transient(ssys, op, t_arr)

    n = LOF_N
    # Last 10%: indices 2701..3001 (t = 270..300 s)
    nc_indices = 2701:3001

    mdot_nc = mean(abs.(sol[ssys.ine.port_in.mdot, nc_indices]))
    T_max_nc = mean([maximum([sol[ssys.ch.T[i], idx] for i in 1:n]) for idx in nc_indices])
    Q_wall_nc = mean([abs(sum(sol[ssys.ch.q_wall[i], idx] for i in 1:n)) for idx in nc_indices])
    Q_meas_nc = mdot_nc * cp_water(LOF_T_INLET) * abs(T_max_nc - LOF_T_INLET)

    @test isapprox(Q_meas_nc, Q_wall_nc; rtol=0.10)
end
