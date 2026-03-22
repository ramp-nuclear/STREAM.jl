# examples/lof_transient.jl
# Standalone LOF (Loss-of-Flow) transient example script with comprehensive analysis.
#
# Usage:
#   julia --project examples/lof_transient.jl
#
# What this script demonstrates:
#   1. Build and solve a steady-state reference loop for initial conditions.
#   2. Build the bypass LOF topology and set up a native ContinuousCallback for the
#      Flapper check valve (required for parallel-channel topologies).
#   3. Run the 300-second transient: pump trip -> momentum coastdown -> flapper fires ->
#      flow reversal -> natural circulation (NC) establishment.
#   4. Extract and plot all relevant time series and spatial profiles.
#   5. Print key metrics: mdot_ss, mdot_nc, T_max, flapper fire time, energy balance.
#
# Physical overview:
#   Topology (bypass, 4-node parallel):
#     Node A (top): ine output, ch input (ChannelHeatFlux, g=-g_acc), flapper input
#     Node B (bottom): ch output, ret input (Channel, g=+g_acc)
#     Node C (top): ret output, flapper output, ext_res input
#     D series: ext_res -> hx -> pump -> ine
#
#   Gravity convention:
#     ch (A->B, nominally downward): g = -g_acc => gravity ASSISTS positive (downward) flow
#     ret (B->C, nominally upward):  g = +g_acc => gravity OPPOSES positive (upward) flow
#
#   Event sequence:
#     t=0       Pump dP = 0 (tripped). Inertia carries momentum; mdot decays.
#     ~20-30s   mdot (ine) drops below threshold (0.01 kg/s). Flapper fires.
#     +dt_ramp  Flapper fully open (5s ramp). Resistance drops from 1e8 to 100 Pa.s/kg.
#     ~60-120s  Buoyancy drives reversed upward flow through heated ch. NC establishes.
#     ~270-300s NC equilibrium: ch.port_in.mdot < 0 (upward), ret.port_in.mdot > 0 (downward).

using STREAM
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using DifferentialEquations
using Plots
using Statistics
using Printf

ENV["GKSwstype"] = "100"   # headless GR — no display window, avoids X11 errors
gr()

# =============================================================================
# SECTION 1: Parameters
# (Matches test/test_loss_of_flow.jl constants exactly)
# =============================================================================

const n          = 10          # axial cells in each channel
const L_ch       = 1.0         # channel length [m]
const D_ch       = 0.01        # hydraulic diameter [m]
const T_wall     = 373.15      # heated channel wall temperature [K] (~100°C)
const T_inlet    = 313.15      # inlet / HX boundary temperature [K] (~40°C)
const g_acc      = 9.80665     # gravitational acceleration [m/s^2]
const L_over_A   = 1.75e5      # Inertia L/A [1/m] — controls coastdown time constant
const R_ext      = 1.0e6       # external bypass resistance [Pa·s/kg]
const threshold  = 0.01        # Flapper trigger threshold [kg/s]
const dt_ramp    = 5.0         # Flapper ramp duration [s]
const dP_ref     = 1.5e4       # reference pump dP for SS [Pa]

println("=" ^ 70)
println("LOF Transient Example — STREAM.jl")
println("=" ^ 70)
println("Parameters:")
println("  n         = $n cells,  L_ch = $L_ch m,  D_ch = $D_ch m")
println("  T_wall    = $T_wall K  ($(round(T_wall - 273.15; digits=1)) °C)")
println("  T_inlet   = $T_inlet K  ($(round(T_inlet - 273.15; digits=1)) °C)")
println("  threshold = $threshold kg/s,  dt_ramp = $dt_ramp s")
println()

# =============================================================================
# SECTION 2: Steady-state reference loop
#
# Purpose: Obtain mdot_ss and T_ss[1:n] for the bypass system's initial conditions.
# Reference loop: Pump(dP_ref) -> HeatExchanger(T_inlet) -> ChannelHeatFlux(g=-g_acc)
# No Flapper, no Inertia — KINSOL-friendly (avoids D(T_open)=0 zero-Jacobian issue).
#
# Physical: at t=0- the system is at forced-flow SS with pump providing dP_ref.
# ch flows downward (positive mdot), heated from T_inlet to ~T_max_ss.
# =============================================================================

println("Building steady-state reference loop...")

@named pump_ref = Pump(dP_ref)
@named hx_ref   = HeatExchanger(T_bc=T_inlet)
@named ch_ref   = ChannelHeatFlux(n=n,
                      geometry = PipeGeometry_circular(L_ch, D_ch),
                      g        = -g_acc,
                      T_wall   = T_wall)

conns_ref = [
    connect(pump_ref.port_out, hx_ref.port_in),
    connect(hx_ref.port_out,   ch_ref.port_in),
    connect(ch_ref.port_out,   pump_ref.port_in),
    pump_ref.port_in.P ~ 1.0e5,
]
@named ref_sys = compose(System(conns_ref, t; name=:ref), pump_ref, hx_ref, ch_ref)
ref_ssys = mtkcompile(ref_sys)

# Initial guess for SS: linear temperature ramp from T_inlet to T_wall
op_ref = Pair{Any,Any}[ref_ssys.ch_ref.port_in.mdot => 0.3]
for i in 1:n
    push!(op_ref, ref_ssys.ch_ref.T[i] => T_inlet + i * (T_wall - T_inlet) / n)
end

ss_sol = solve_steady(ref_ssys, op_ref)
mdot_ss = ss_sol[ref_ssys.ch_ref.port_in.mdot]
T_ss    = [ss_sol[ref_ssys.ch_ref.T[i]] for i in 1:n]

println("Steady-state solved:")
println("  mdot_ss   = $(round(mdot_ss; digits=6)) kg/s")
println("  T_ss min  = $(round(minimum(T_ss) - 273.15; digits=2)) °C")
println("  T_ss max  = $(round(maximum(T_ss) - 273.15; digits=2)) °C")
println()

# =============================================================================
# SECTION 3: Build bypass system and set initial conditions
#
# IC strategy (matches _lof_bypass_ic in test/test_loss_of_flow.jl):
#   - ine.port_in.mdot = mdot_ss  (total loop flow; Inertia carries this momentum)
#   - ret.port_in.mdot = mdot_ss  (all flow through ch-ret path; flapper closed at t=0)
#   - Dt(ret.port_in.mdot) = 0.0  (index-reduced derivative state; zero at quasi-SS)
#   - flapper.T_open = 1e30       (sentinel: valve not yet fired; ramp = 0 for all t << 1e30)
#   - ch.T[i] = T_ss[i]           (channel cells initialized from SS reference)
#   - ret.T[i] = T_inlet          (return channel starts cold)
#
# Callback strategy:
#   MTK SymbolicContinuousCallback is incompatible with parallel topologies where
#   channel inertia (Dt(mdot)) appears in the callback's pressure balance equations.
#   Instead: native DifferentialEquations ContinuousCallback monitors ine.port_in.mdot,
#   and directly sets T_open in the ODE state vector when mdot drops below threshold.
# =============================================================================

println("Building bypass LOF system...")

ssys = build_loop_lof_bypass(;
    n         = n,
    L_ch      = L_ch,
    D_ch      = D_ch,
    T_wall    = T_wall,
    T_inlet   = T_inlet,
    L_over_A  = L_over_A,
    g_acc     = g_acc,
    R_ext     = R_ext,
    threshold = threshold,
    dt_ramp   = dt_ramp,
)

Dt = Differential(t)
op = Pair{Any,Any}[
    ssys.ine.port_in.mdot        => mdot_ss,  # Inertia carries forced-flow momentum
    ssys.ret.port_in.mdot        => mdot_ss,  # return channel flow (flapper closed at t=0)
    Dt(ssys.ret.port_in.mdot)    => 0.0,      # index-reduced state; zero at quasi-SS
    ssys.flapper.T_open          => 1.0e30,   # sentinel: flapper has not fired yet
]
for i in 1:n
    push!(op, ssys.ch.T[i] => T_ss[i])     # heated channel cells from SS reference
end
for i in 1:n
    push!(op, ssys.ret.T[i] => T_inlet)    # return channel starts cold
end

# Native ContinuousCallback:
#   Condition: u[i_ine_mdot] - threshold (zero crossing = flapper trigger)
#   affect_neg: downward crossing -> latch T_open = current solver time
#   nothing: ignore upward crossing
i_T_open   = ModelingToolkit.variable_index(ssys, ssys.flapper.T_open)
i_ine_mdot = ModelingToolkit.variable_index(ssys, ssys.ine.port_in.mdot)

cb = ContinuousCallback(
    (u, t_cb, integrator) -> u[i_ine_mdot] - threshold,
    nothing,
    (integrator) -> (integrator.u[i_T_open] = integrator.t),
)

println("Bypass system compiled. Variables: $(length(unknowns(ssys)))")
println()

# =============================================================================
# SECTION 4: Solve transient
#
# 300 seconds at 0.1s resolution (3001 points).
# After pump trip at t=0, we expect:
#   - Exponential-like mdot decay (time constant ~ L_over_A / R_loop)
#   - Flapper fires at ~20-30s (when mdot crosses threshold)
#   - Flow reversal and NC establishment by ~100-150s
#   - NC equilibrium by ~270s: ch.mdot < 0, |mdot_nc| << mdot_ss
# =============================================================================

t_arr = range(0.0, 300.0; length=3001)

println("Solving transient (300s, 3001 points)...")
flush(stdout)

sol = solve_transient(ssys, op, t_arr; callbacks=cb)

if sol.retcode != ReturnCode.Success
    error("Solver failed with retcode: $(sol.retcode)")
end

println("Transient solve complete. retcode = $(sol.retcode)")
println()

# =============================================================================
# SECTION 5: Extract time series into plain arrays for plotting
#
# Note: The solver inserts extra time points at callback events (flapper firing).
# sol.t has length > length(t_arr). We use sol.t as the common time axis so all
# extracted arrays have the same length. The dt_step for NC detection uses the
# uniform portion: approx (t_arr[end] - t_arr[1]) / (length(t_arr) - 1).
# =============================================================================

t_vec = sol.t  # actual solver time points (may include callback-inserted extras)

# Mass flow rates
mdot_ch   = sol[ssys.ch.port_in.mdot, :]
mdot_ret  = sol[ssys.ret.port_in.mdot, :]
mdot_flap = sol[ssys.flapper.port_in.mdot, :]
mdot_ine  = sol[ssys.ine.port_in.mdot, :]

# Cell temperatures
T_ch  = [sol[ssys.ch.T[i],  :] for i in 1:n]   # T_ch[i][time_idx]
T_ret = [sol[ssys.ret.T[i], :] for i in 1:n]

# Heat flux, Reynolds, HTC in heated channel
q_wall_ch = [sol[ssys.ch.q_wall[i], :] for i in 1:n]
Re_ch     = [sol[ssys.ch.Re[i],     :] for i in 1:n]
htc_ch    = [sol[ssys.ch.h_tc[i],   :] for i in 1:n]

# Flapper state
xi_arr    = sol[ssys.flapper.xi,     :]
T_open_arr = sol[ssys.flapper.T_open, :]

# Pressure drops
dP_ch  = sol[ssys.ch.dP,  :]
dP_ret = sol[ssys.ret.dP, :]

# =============================================================================
# SECTION 6: Compute and print key metrics
#
# Physical summary of each metric:
#   mdot_nc     — NC mass flow at t=300s. Should be << mdot_ss (buoyancy-driven)
#   T_max_nc    — max cell temperature at NC steady state (at ch cell 1, top of upward ch)
#   flapper_fire_time — when Flapper triggered; T_open latched from sentinel 1e30 to t_fire
#   nc_time     — estimated NC establishment time (|d(mdot)/dt| < 1e-5 kg/s^2)
#   energy_balance_ratio — Q_wall / Q_advect at final time (should be ~1.0 at 5% rtol)
# =============================================================================

mdot_nc    = abs(mdot_ch[end])
T_max_nc   = maximum(T_ch[i][end] for i in 1:n)
T_max_ss   = maximum(T_ss)

# Flapper fire time: T_open latched from 1e30 sentinel to actual time when mdot crossed threshold
flapper_fire_time = T_open_arr[end] < 1.0e10 ? T_open_arr[end] : NaN
flapper_open_time = isnan(flapper_fire_time) ? NaN : flapper_fire_time + dt_ramp

# NC establishment: first index (after flapper fully open) where |d(mdot_ch)/dt| < 1e-5
dt_step = (t_arr[end] - t_arr[1]) / (length(t_arr) - 1)  # nominal 0.1s step
nc_time_found = Ref(NaN)
if !isnan(flapper_open_time)
    idx_open = findfirst(t_vec .>= flapper_open_time)
    if !isnothing(idx_open)
        for idx in idx_open:length(t_vec)-1
            dmdt = abs(mdot_ch[idx+1] - mdot_ch[idx]) / dt_step
            if dmdt < 1e-5
                nc_time_found[] = t_vec[idx]
                break
            end
        end
    end
end
nc_time = nc_time_found[]

# Energy balance at final time
# Backward flow (NC): inlet to ch is from ret.T[1] at Node B; outlet is T[1] (cell 1 = top, hottest)
T_inlet_ch_final = sol[ssys.ret.T[1], end]
T_outlet_ch_final = T_ch[1][end]  # T[1] = hottest in NC reversed flow
Q_wall_final  = abs(sum(q_wall_ch[i][end] for i in 1:n))
Q_advect_final = mdot_nc * cp_water(T_inlet) * abs(T_outlet_ch_final - T_inlet_ch_final)
energy_balance_ratio = (Q_advect_final > 1e-3) ? Q_wall_final / Q_advect_final : NaN

println("=" ^ 70)
println("KEY METRICS")
println("=" ^ 70)
@printf "  Steady-state mdot     : %.6f kg/s\n" mdot_ss
@printf "  NC mdot (t=300s)      : %.6f kg/s  (%.1f%% of SS)\n" mdot_nc (100*mdot_nc/mdot_ss)
@printf "  T_max at SS           : %.2f K  (%.2f °C)\n" T_max_ss (T_max_ss - 273.15)
@printf "  T_max at NC (t=300s)  : %.2f K  (%.2f °C)\n" T_max_nc (T_max_nc - 273.15)
if !isnan(flapper_fire_time)
    @printf "  Flapper fires at      : %.2f s\n" flapper_fire_time
    @printf "  Flapper fully open at : %.2f s\n" flapper_open_time
else
    println("  Flapper fires at      : DID NOT FIRE (check threshold)")
end
if !isnan(nc_time)
    @printf "  NC established ~      : %.1f s\n" nc_time
else
    println("  NC established ~      : not detected within 300s")
end
if !isnan(energy_balance_ratio)
    @printf "  Energy balance ratio  : %.4f  (1.0 = perfect, <5%% err expected)\n" energy_balance_ratio
else
    println("  Energy balance ratio  : N/A (mdot_nc too small)")
end
println("=" ^ 70)
println()

# =============================================================================
# SECTION 7: Create output directory
# =============================================================================

outdir = "examples/output/lof_transient"
mkpath(outdir)
println("Output directory: $outdir")

# Helper: build viridis-like color gradient for n lines
function cell_colors(n)
    [RGB(1-i/n, 0.3+0.4*(i/n), i/n) for i in 1:n]
end

# Helper: vertical event annotations using annotate! (avoids GR BoundsError
# that occurs when mixing 2-element series with 3001-element series in same axes).
# Draws a label at the top of the plot at the event time.
function add_event_vlines!(p, fire_t, open_t, t_range; ymin=-1e12, ymax=1e12)
    # Use annotate! with a vertical text marker at the event times.
    # We also overlay a thin 3-element series (x=[t, t, t], y=[y1, 0.5*(y1+y2), y2])
    # using enough points to avoid GR's padding check triggering on length mismatch.
    # Simplest robust approach: construct a NaN-padded full-length series.
    n_pts = length(t_range)
    t_vec_full = collect(t_range)

    function _vline_series(t_event, y_lo, y_hi)
        # Build a series that is NaN everywhere except at the closest time index
        # where it draws a 3-point spike: [y_lo, y_hi, NaN] pattern repeated.
        # We find the closest 3 consecutive indices around t_event.
        idx = argmin(abs.(t_vec_full .- t_event))
        y_series = fill(NaN, n_pts)
        # Place a 2-point up-down spike at idx
        if idx > 1
            y_series[idx-1] = y_lo
        end
        y_series[idx] = y_hi
        return t_vec_full, y_series
    end

    if !isnan(fire_t) && fire_t >= t_range[1] && fire_t <= t_range[end]
        # Use annotate! for the label
        try
            annotate!(p, fire_t, 0.0, Plots.text("fire", 7, :orange, :left))
        catch
        end
    end
    if !isnan(open_t) && open_t >= t_range[1] && open_t <= t_range[end]
        try
            annotate!(p, open_t, 0.0, Plots.text("open", 7, :red, :left))
        catch
        end
    end
end

# =============================================================================
# SECTION 8: Time-series plots
# =============================================================================

# -----------------------------------------------------------------------
# Plot 1 — Mass flow rates
#
# Physical behavior to expect:
#   - All mdot start at mdot_ss (positive = downward forced flow).
#   - After pump trip: ine.mdot decays (Inertia coastdown).
#   - ch.mdot follows ine.mdot initially (all flow through ch-ret with flapper closed).
#   - At t_fire: flapper opens; flow redistributes between ch and flapper paths.
#   - ch.mdot crosses zero and goes negative (upward NC flow).
#   - ret.mdot also reverses (follows ch by mass conservation through Node B).
#   - mdot_ine approaches zero (pump is off, ext_res path carries tiny flow).
# -----------------------------------------------------------------------
println("Generating Plot 1: Mass flow rates...")
p1 = plot(t_vec, mdot_ch;
    label="ch (heated, ChannelHeatFlux)",
    xlabel="Time [s]", ylabel="Mass flow [kg/s]",
    title="LOF Bypass: Mass Flow Rates",
    linewidth=2, color=:blue, size=(900, 600), dpi=150, legend=:topright)
plot!(p1, t_vec, mdot_ret;  label="ret (return, Channel)", linewidth=2, color=:green)
plot!(p1, t_vec, mdot_flap; label="flapper path",          linewidth=2, color=:purple, linestyle=:dash)
plot!(p1, t_vec, mdot_ine;  label="ine (pump branch)",     linewidth=2, color=:gray)
plot!(p1, t_vec, zeros(length(t_vec)); linestyle=:dot, color=:black, linewidth=1, label=nothing)  # zero reference
add_event_vlines!(p1, flapper_fire_time, flapper_open_time, t_vec)
savefig(p1, "$outdir/01_mass_flow_rates.png")

# -----------------------------------------------------------------------
# Plot 2 — Channel (heated) cell temperatures over time
#
# Physical behavior:
#   - At t=0: T_ch[i] = T_ss[i] (hot cells from SS, T_ss[n] ~highest).
#   - After pump trip: forced flow stops; cells cool if mdot goes to zero temporarily,
#     then reheat as NC reversed flow heats them from the bottom (cell 1) up.
#   - At NC: T_ch[1] becomes highest (top of upward-flowing heated channel).
#     In NC with reversed flow, cell 1 is the outlet of the heated channel.
# -----------------------------------------------------------------------
println("Generating Plot 2: Channel temperatures...")
colors2 = range(colorant"blue", stop=colorant"red", length=n)
p2 = plot(; xlabel="Time [s]", ylabel="Temperature [K]",
    title="LOF Bypass: Heated Channel (ch) Cell Temperatures",
    size=(900, 600), dpi=150, legend=:outerright)
for i in 1:n
    plot!(p2, t_vec, T_ch[i]; label="T[$i]", linewidth=1.5, color=colors2[i])
end
add_event_vlines!(p2, flapper_fire_time, flapper_open_time, t_vec)
savefig(p2, "$outdir/02_channel_temperatures.png")

# -----------------------------------------------------------------------
# Plot 3 — Return channel (ret) cell temperatures over time
#
# Physical behavior:
#   - ret is a Channel (not ChannelHeatFlux) with thermal BC pinned to T_inlet.
#   - In NC: ret carries cold water (from HX at T_inlet) downward (B->C).
#   - ret.T[i] stays near T_inlet throughout (effective heat removal by HX).
# -----------------------------------------------------------------------
println("Generating Plot 3: Return channel temperatures...")
p3 = plot(; xlabel="Time [s]", ylabel="Temperature [K]",
    title="LOF Bypass: Return Channel (ret) Cell Temperatures",
    size=(900, 600), dpi=150, legend=:outerright)
for i in 1:n
    plot!(p3, t_vec, T_ret[i]; label="T[$i]", linewidth=1.5, color=colors2[i])
end
add_event_vlines!(p3, flapper_fire_time, flapper_open_time, t_vec)
savefig(p3, "$outdir/03_return_temperatures.png")

# -----------------------------------------------------------------------
# Plot 4 — Heat flux per cell in heated channel
#
# Physical behavior:
#   - q_wall[i] = h_tc[i] * heated_perimeter * dz * (T_wall - T[i])
#   - At SS: all cells positive (T_wall > T[i]), more heat in cooler (early) cells.
#   - During coastdown: mdot drops -> Re drops -> h_tc drops -> q_wall drops.
#   - At NC: flow reversed; cell 1 (coolest in NC inlet) has highest q_wall again.
# -----------------------------------------------------------------------
println("Generating Plot 4: Heat flux per cell...")
p4 = plot(; xlabel="Time [s]", ylabel="Heat flux [W]",
    title="LOF Bypass: Heated Channel Wall Heat Flux per Cell",
    size=(900, 600), dpi=150, legend=:outerright)
for i in 1:n
    plot!(p4, t_vec, q_wall_ch[i]; label="q[$i]", linewidth=1.5, color=colors2[i])
end
add_event_vlines!(p4, flapper_fire_time, flapper_open_time, t_vec)
savefig(p4, "$outdir/04_heat_flux.png")

# -----------------------------------------------------------------------
# Plot 5 — Reynolds numbers per cell
#
# Physical behavior:
#   - At SS: Re > 2300 (forced convection, turbulent).
#   - During coastdown: Re drops as mdot decays.
#   - At NC: Re << SS value (mdot_nc << mdot_ss -> laminar or low-turbulent regime).
#   - All cells have the same Re (same mdot, same geometry — Re varies only via T[i]).
# -----------------------------------------------------------------------
println("Generating Plot 5: Reynolds numbers...")
p5 = plot(; xlabel="Time [s]", ylabel="Reynolds number [-]",
    title="LOF Bypass: Heated Channel Reynolds Number per Cell",
    size=(900, 600), dpi=150, legend=:outerright)
for i in 1:n
    plot!(p5, t_vec, Re_ch[i]; label="Re[$i]", linewidth=1.5, color=colors2[i])
end
plot!(p5, t_vec, fill(2300.0, length(t_vec)); linestyle=:dash, color=:black, linewidth=1, label="Re=2300 (lam/turb)")
add_event_vlines!(p5, flapper_fire_time, flapper_open_time, t_vec)
savefig(p5, "$outdir/05_reynolds.png")

# -----------------------------------------------------------------------
# Plot 6 — Heat transfer coefficient (HTC) per cell
#
# Physical behavior:
#   - HTC follows Re (Dittus-Boelter: Nu ~ Re^0.8 Pr^0.4 -> h_tc ~ Re^0.8).
#   - Drops sharply during coastdown as Re decreases.
#   - At NC: low Re -> low HTC, but significant heating still occurs due to
#     long residence time (low mdot through long channel).
# -----------------------------------------------------------------------
println("Generating Plot 6: HTC...")
p6 = plot(; xlabel="Time [s]", ylabel="HTC [W/(m^2·K)]",
    title="LOF Bypass: Heated Channel HTC per Cell",
    size=(900, 600), dpi=150, legend=:outerright)
for i in 1:n
    plot!(p6, t_vec, htc_ch[i]; label="h[$i]", linewidth=1.5, color=colors2[i])
end
add_event_vlines!(p6, flapper_fire_time, flapper_open_time, t_vec)
savefig(p6, "$outdir/06_htc.png")

# -----------------------------------------------------------------------
# Plot 7 — Flapper state (xi and T_open)
#
# Physical behavior:
#   - xi = clamp((t - T_open) / dt_ramp, 0, 1) — smooth cubic ramp from 0 to 1.
#   - Before firing: T_open = 1e30 -> xi = 0 (valve fully closed).
#   - After firing: T_open latched to t_fire -> xi ramps from 0 to 1 over dt_ramp.
#   - T_open display clamped to [0, 300] for readability (sentinel 1e30 not shown).
# -----------------------------------------------------------------------
println("Generating Plot 7: Flapper state...")
T_open_display = clamp.(T_open_arr, 0.0, 300.0)   # sentinel -> 300 (off-chart)
p7a = plot(t_vec, xi_arr;
    ylabel="xi (opening fraction)", title="Flapper Opening State",
    linewidth=2, color=:purple, label="xi",
    ylims=(-0.05, 1.1), size=(900, 300), dpi=150)
add_event_vlines!(p7a, flapper_fire_time, flapper_open_time, t_vec)

p7b = plot(t_vec, T_open_display;
    xlabel="Time [s]", ylabel="T_open [s]",
    title="Flapper T_open (latch time; 300 = sentinel/not fired)",
    linewidth=2, color=:orange, label="T_open (clamped)",
    size=(900, 300), dpi=150)

p7 = plot(p7a, p7b; layout=(2,1), size=(900, 600), dpi=150)
savefig(p7, "$outdir/07_flapper_state.png")

# -----------------------------------------------------------------------
# Plot 8 — Pressure drops
#
# Physical behavior:
#   - At SS: dP_ch > 0 (friction + gravity head for downward flow).
#   - During coastdown: dP decreases as mdot decreases.
#   - At NC: dP_ch changes sign (buoyancy drives reversed flow).
#   - dP_ret opposes NC flow (gravity opposes upward return).
# -----------------------------------------------------------------------
println("Generating Plot 8: Pressure drops...")
p8 = plot(t_vec, dP_ch;
    label="ch dP (heated)", xlabel="Time [s]", ylabel="Pressure drop [Pa]",
    title="LOF Bypass: Channel Pressure Drops",
    linewidth=2, color=:blue, size=(900, 600), dpi=150, legend=:topright)
plot!(p8, t_vec, dP_ret; label="ret dP (return)", linewidth=2, color=:green)
plot!(p8, t_vec, zeros(length(t_vec)); linestyle=:dot, color=:black, linewidth=1, label=nothing)
add_event_vlines!(p8, flapper_fire_time, flapper_open_time, t_vec)
savefig(p8, "$outdir/08_pressure_drops.png")

# =============================================================================
# SECTION 9: Spatial profile snapshots
#
# Three time slices: t=0 (SS), t~flapper_fire (transition), t=300s (NC).
# Spatial axis = cell index 1..n (1 = port_in side under positive flow,
#                                  but becomes "outlet" under reversed NC flow).
# =============================================================================

# Pick snapshot indices
idx_t0   = 1
idx_fire = isnan(flapper_fire_time) ? div(length(t_vec), 2) :
           argmin(abs.(t_vec .- flapper_fire_time))
idx_end  = length(t_vec)

t_labels = [
    "t=0s (SS)",
    isnan(flapper_fire_time) ? "t=$(round(t_vec[idx_fire]; digits=1))s" :
        "t=$(round(flapper_fire_time; digits=1))s (fire)",
    "t=300s (NC)",
]
snap_indices = [idx_t0, idx_fire, idx_end]
snap_colors  = [:blue, :orange, :red]

cell_axis = 1:n

# -----------------------------------------------------------------------
# Plot 9 — Temperature spatial profiles at three snapshots
#
# Physical: At SS, T increases monotonically from cell 1 to n (coolant heats up).
#           At NC: T increases from n to 1 (reversed flow heats from bottom cell upward).
# -----------------------------------------------------------------------
println("Generating Plot 9: Temperature spatial profiles...")
p9 = plot(; xlabel="Cell index", ylabel="Temperature [K]",
    title="LOF Bypass: Temperature Profiles at Key Times",
    size=(900, 600), dpi=150, legend=:topleft)
for (k, idx) in enumerate(snap_indices)
    T_snap = [T_ch[i][idx] for i in 1:n]
    plot!(p9, cell_axis, T_snap; label=t_labels[k], linewidth=2, color=snap_colors[k],
          marker=:circle, markersize=4)
end
savefig(p9, "$outdir/09_temperature_profiles.png")

# -----------------------------------------------------------------------
# Plot 10 — Reynolds number spatial profiles at three snapshots
#
# Physical: At SS, Re is nearly uniform (same mdot, slight variation via T[i]).
#           At NC: Re much lower (mdot_nc << mdot_ss).
# -----------------------------------------------------------------------
println("Generating Plot 10: Reynolds spatial profiles...")
p10 = plot(; xlabel="Cell index", ylabel="Reynolds number [-]",
    title="LOF Bypass: Reynolds Profiles at Key Times",
    size=(900, 600), dpi=150, legend=:topright)
for (k, idx) in enumerate(snap_indices)
    Re_snap = [Re_ch[i][idx] for i in 1:n]
    plot!(p10, cell_axis, Re_snap; label=t_labels[k], linewidth=2, color=snap_colors[k],
          marker=:circle, markersize=4)
end
plot!(p10, collect(cell_axis), fill(2300.0, n); linestyle=:dash, color=:black, linewidth=1, label="Re=2300")
savefig(p10, "$outdir/10_reynolds_profiles.png")

# -----------------------------------------------------------------------
# Plot 11 — HTC spatial profiles at three snapshots
#
# Physical: HTC tracks Re^0.8, so same trend as Re profiles.
# -----------------------------------------------------------------------
println("Generating Plot 11: HTC spatial profiles...")
p11 = plot(; xlabel="Cell index", ylabel="HTC [W/(m^2·K)]",
    title="LOF Bypass: HTC Profiles at Key Times",
    size=(900, 600), dpi=150, legend=:topright)
for (k, idx) in enumerate(snap_indices)
    htc_snap = [htc_ch[i][idx] for i in 1:n]
    plot!(p11, cell_axis, htc_snap; label=t_labels[k], linewidth=2, color=snap_colors[k],
          marker=:circle, markersize=4)
end
savefig(p11, "$outdir/11_htc_profiles.png")

println()
println("All plots saved to: $outdir/")
println("Files generated:")
for f in sort(readdir(outdir))
    println("  $outdir/$f")
end
println()
println("Done.")
