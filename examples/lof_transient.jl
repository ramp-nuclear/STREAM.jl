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
#   5. Print key metrics: ṁ_ss, ṁ_nc, T_max, flapper fire time, energy balance.
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
#     t=0       Pump dP = 0 (tripped). Inertia carries momentum; ṁ decays.
#     ~20-30s   ṁ (ine) drops below threshold (0.01 kg/s). Flapper fires.
#     +dt_ramp  Flapper fully open (5s ramp). Resistance drops from 1e8 to 100 Pa.s/kg.
#     ~60-120s  Buoyancy drives reversed upward flow through heated ch. NC establishes.
#     ~270-300s NC equilibrium: ch.inlet.ṁ < 0 (upward), ret.inlet.ṁ > 0 (downward).

using STREAM
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using Statistics
using Printf

using Plots
const mm = Plots.PlotMeasures.mm
ENV["GKSwstype"] = "100"   # headless GR — no display window, avoids X11 errors
Plots.gr()

#! format: off
const n          = 50          # axial cells in each channel
const L_ch       = 1.0         # channel length [m]
const D_ch       = 0.01        # hydraulic diameter [m]
const T_wall     = 373.15      # heated channel wall temperature [K] (~100°C)
const T_inlet    = 313.15      # inlet / HX boundary temperature [K] (~40°C)
const g_acc      = G_EARTH     # gravitational acceleration [m/s^2]
const L_over_A   = 5e6         # Inertia L/A [1/m] — controls coastdown time constant
const R_ext      = 1.0e6       # external bypass resistance [Pa·s/kg]
const threshold  = 0.01        # Flapper trigger threshold [kg/s]
const dt_ramp    = 0.5         # Flapper ramp duration [s]
const dP_ref     = 1.5e4       # reference pump dP for SS [Pa]
#! format: on

println("="^70)
println("LOF Transient Example — STREAM.jl")
println("="^70)
println("Parameters:")
println("  n         = $n cells,  L_ch = $L_ch m,  D_ch = $D_ch m")
println("  T_wall    = $T_wall K  ($(round(T_wall - 273.15; digits=1)) °C)")
println("  T_inlet   = $T_inlet K  ($(round(T_inlet - 273.15; digits=1)) °C)")
println("  threshold = $threshold kg/s,  dt_ramp = $dt_ramp s")
println()

const h_wall = 5000.0   # convective HTC [W/(m^2·K)] for the SS reference loop

println("Building steady-state reference loop...")

@named pump_ref = Pump(dP_ref)
@named hx_ref = HeatExchanger(T_inlet)

@named ch_ref = STREAM.Channel(;
    n=n, geometry=PipeGeometry_circular(L_ch, D_ch), g=(-g_acc), h_left=h_wall, h_right=0.0
)

conns_ref = Equation[
    connect(pump_ref.outlet, hx_ref.inlet),
    connect(hx_ref.outlet, ch_ref.inlet),
    connect(ch_ref.outlet, pump_ref.inlet),
    pump_ref.inlet.p ~ 1.0e5,
    [ch_ref.T_wall_left[i] ~ T_wall for i in 1:n]...,
    [ch_ref.T_wall_right[i] ~ T_inlet for i in 1:n]...,  # decorative; h_right=0
]
@named ref_sys = compose(System(conns_ref, t; name=:ref), pump_ref, hx_ref, ch_ref)
ref_ssys = mtkcompile(ref_sys)

# Initial guess for SS: linear temperature ramp from T_inlet to T_wall
op_ref = Pair{Any,Any}[ref_ssys.ch_ref.inlet.ṁ => 0.3]
for i in 1:n
    push!(op_ref, ref_ssys.ch_ref.T[i] => T_inlet + i * (T_wall - T_inlet) / n)
end

ss_sol = solve_steady(ref_ssys, op_ref)
ṁ_ss = ss_sol[ref_ssys.ch_ref.inlet.ṁ]
T_ss = [ss_sol[ref_ssys.ch_ref.T[i]] for i in 1:n]

println("Steady-state solved:")
println("  ṁ_ss   = $(round(ṁ_ss; digits=6)) kg/s")
println("  T_ss min  = $(round(minimum(T_ss) - 273.15; digits=2)) °C")
println("  T_ss max  = $(round(maximum(T_ss) - 273.15; digits=2)) °C")
println()

println("Building bypass LOF system...")

const power_W = 1.0e3   # total fuel-plate power [W] (Spike B baseline; produces NC ~ 4 g/s)
const fuel_nx = 2       # lateral cells in HeatDiffusion plate

#! format: off
ssys = build_loop_lof_bypass(;
    n         = n,
    L_ch      = L_ch,
    D_ch      = D_ch,
    T_inlet   = T_inlet,
    power_W   = power_W,
    fuel_nx   = fuel_nx,
    L_over_A  = L_over_A,
    g_acc     = g_acc,
    R_ext     = R_ext,
    dt_ramp   = dt_ramp,
)
#! format: on

Dt = Differential(t)
op = Pair{Any,Any}[
    ssys.ine.inlet.ṁ => ṁ_ss,  # Inertia carries forced-flow momentum
    ssys.ret.inlet.ṁ => ṁ_ss,  # return channel flow (flapper closed at t=0)
    Dt(ssys.ret.inlet.ṁ) => 0.0,  # index-reduced state; zero at quasi-SS
    ssys.flapper.T_open => 1.0e30,     # sentinel: flapper has not fired yet
]
for i in 1:n
    push!(op, ssys.heated.ch.T[i] => T_ss[i])      # heated-channel cells from SS reference
end
for i in 1:n
    for j in 1:fuel_nx
        push!(op, ssys.heated.fuel.T[i, j] => T_ss[i])  # fuel-plate cells seeded from coolant
    end
end
for i in 1:n
    push!(op, ssys.ret.T[i] => T_inlet)            # return channel starts cold
end

i_T_open = ModelingToolkit.variable_index(ssys, ssys.flapper.T_open)
i_ine_ṁ = ModelingToolkit.variable_index(ssys, ssys.ine.inlet.ṁ)

cb = ContinuousCallback(
    (u, t_cb, integrator) -> u[i_ine_ṁ] - threshold,
    nothing,
    (integrator) -> (integrator.u[i_T_open] = integrator.t),
)

println("Bypass system compiled. Variables: $(length(unknowns(ssys)))")
println()

t_arr = range(0.0, 300.0; length=3001)

println("Solving transient (300s, 3001 points)...")
flush(stdout)

sol = solve_transient(ssys, op, t_arr; callbacks=cb)

if sol.retcode != ReturnCode.Success
    error("Solver failed with retcode: $(sol.retcode)")
end

println("Transient solve complete. retcode = $(sol.retcode)")
println()

t_vec = sol.t  # actual solver time points (may include callback-inserted extras)

ṁ_ch = sol[ssys.heated.ch.inlet.ṁ, :]
ṁ_ret = sol[ssys.ret.inlet.ṁ, :]
ṁ_flap = sol[ssys.flapper.inlet.ṁ, :]
ṁ_ine = sol[ssys.ine.inlet.ṁ, :]

# Cell temperatures
T_ch = [sol[ssys.heated.ch.T[i], :] for i in 1:n]   # T_ch[i][time_idx]
T_ret = [sol[ssys.ret.T[i], :] for i in 1:n]

# Heat flux, Reynolds, HTC in heated channel
q_wall_ch = [sol[ssys.heated.ch.q_wall_left[i], :] for i in 1:n]
Re_ch = [sol[ssys.heated.ch.Re[i], :] for i in 1:n]
htc_ch = [sol[ssys.heated.ch.h_tc[i], :] for i in 1:n]

# Flapper state
xi_arr = sol[ssys.flapper.xi, :]
T_open_arr = sol[ssys.flapper.T_open, :]

# Pressure drops
dP_ch = sol[ssys.heated.ch.dP, :]
dP_ret = sol[ssys.ret.dP, :]

ṁ_nc = abs(ṁ_ch[end])
T_max_nc = maximum(T_ch[i][end] for i in 1:n)
T_max_ss = maximum(T_ss)

flapper_fire_time = T_open_arr[end] < 1.0e10 ? T_open_arr[end] : NaN
flapper_open_time = isnan(flapper_fire_time) ? NaN : flapper_fire_time + dt_ramp

dt_step = (t_arr[end] - t_arr[1]) / (length(t_arr) - 1)  # nominal 0.1s step
nc_time_found = Ref(NaN)
if !isnan(flapper_open_time)
    idx_open = findfirst(t_vec .>= flapper_open_time)
    if !isnothing(idx_open)
        for idx in idx_open:(length(t_vec) - 1)
            dmdt = abs(ṁ_ch[idx + 1] - ṁ_ch[idx]) / dt_step
            if dmdt < 1e-5
                nc_time_found[] = t_vec[idx]
                break
            end
        end
    end
end
nc_time = nc_time_found[]

T_inlet_ch_final = sol[ssys.ret.T[1], end]
T_outlet_ch_final = T_ch[1][end]  # T[1] = hottest in NC reversed flow
Q_wall_final = abs(sum(q_wall_ch[i][end] for i in 1:n))
Q_advect_final = ṁ_nc * cp_water(T_inlet) * abs(T_outlet_ch_final - T_inlet_ch_final)
energy_balance_ratio = (Q_advect_final > 1e-3) ? Q_wall_final / Q_advect_final : NaN

println("="^70)
println("KEY METRICS")
println("="^70)
@printf "  Steady-state ṁ     : %.6f kg/s\n" ṁ_ss
@printf "  NC ṁ (t=300s)      : %.6f kg/s  (%.1f%% of SS)\n" ṁ_nc (
    100 * ṁ_nc / ṁ_ss
)
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
    println("  Energy balance ratio  : N/A (ṁ_nc too small)")
end
println("="^70)
println()

#! format: off
outdir_base  = "examples/output/lof_transient"
dir_overview = joinpath(outdir_base, "01_overview")
dir_trans    = joinpath(outdir_base, "02_transition_0to60s")
dir_nc       = joinpath(outdir_base, "03_nc_equilibrium")
dir_spatial  = joinpath(outdir_base, "04_spatial_profiles")
#! format: on

for d in [dir_overview, dir_trans, dir_nc, dir_spatial]
    mkpath(d)
end
println("Output directories created under: $outdir_base/")
println()

colors_cells = range(
    parse(Plots.Colors.Colorant, "navy");
    stop=parse(Plots.Colors.Colorant, "firebrick"),
    length=n,
)

function add_events!(
    p; tfire=flapper_fire_time, topen=flapper_open_time, tmin=(-Inf), tmax=Inf
)
    if !isnan(tfire) && tmin <= tfire <= tmax
        vline!(
            p,
            [tfire];
            color=:darkorange,
            lw=2,
            ls=:dash,
            label="flapper fires ($(round(tfire; digits=2))s)",
        )
    end
    if !isnan(topen) && tmin <= topen <= tmax
        vline!(
            p,
            [topen];
            color=:red,
            lw=1.5,
            ls=:dot,
            label="fully open ($(round(topen; digits=2))s)",
        )
    end
    return p
end

# Return indices of t_vec that fall in [t_lo, t_hi]
wmask(t_lo, t_hi) = findall(x -> t_lo <= x <= t_hi, t_vec)

println("=== 01_overview (0–300s) ===")
println("  01_flow_all_components.png")

p8a_ch = plot(
    t_vec,
    ṁ_ch;
    ylabel="ch [kg/s]",
    label="ch (heated)",
    lw=2,
    color=:royalblue,
    title="LOF Bypass — Mass Flows (0-300s)",
)
hline!(p8a_ch, [0.0]; color=:black, lw=1, ls=:dot, label=nothing)
add_events!(p8a_ch)

p8a_ret = plot(
    t_vec,
    ṁ_ret;
    ylabel="ret [kg/s]",
    label="ret (return)",
    lw=2,
    color=:forestgreen,
)
hline!(p8a_ret, [0.0]; color=:black, lw=1, ls=:dot, label=nothing)
add_events!(p8a_ret)

p8a_ine = plot(
    t_vec,
    ṁ_ine;
    ylabel="ine [kg/s]",
    label="ine (pump branch)",
    lw=2,
    color=:gray,
)
hline!(p8a_ine, [0.0]; color=:black, lw=1, ls=:dot, label=nothing)
add_events!(p8a_ine)

p8a_flap = plot(
    t_vec,
    ṁ_flap;
    xlabel="Time [s]",
    ylabel="flapper [kg/s]",
    label="flapper path",
    lw=2,
    color=:purple,
    ls=:dash,
)
hline!(p8a_flap, [0.0]; color=:black, lw=1, ls=:dot, label=nothing)
add_events!(p8a_flap)

pov_flow = plot(
    p8a_ch,
    p8a_ret,
    p8a_ine,
    p8a_flap;
    layout=(4, 1),
    size=(1000, 900),
    dpi=150,
    left_margin=8mm,
    right_margin=5mm,
    bottom_margin=3mm,
)
savefig(pov_flow, joinpath(dir_overview, "01_flow_all_components.png"))

println("  02_flow_ch_ret.png")
p8b = plot(
    t_vec,
    ṁ_ch;
    label="ch (heated)",
    lw=2.5,
    color=:royalblue,
    xlabel="Time [s]",
    ylabel="Mass flow [kg/s]",
    title="LOF Bypass: ch and ret Mass Flows (0-300s)\n(positive = port_in→port_out, negative = reversed)",
    size=(1000, 500),
    dpi=150,
)
plot!(p8b, t_vec, ṁ_ret; label="ret (return)", lw=2.5, color=:forestgreen)
hline!(p8b, [0.0]; color=:black, lw=1, ls=:dot, label="zero")
add_events!(p8b)
savefig(p8b, joinpath(dir_overview, "02_flow_ch_ret.png"))

println("  03_temperatures_ch.png")
p8c = plot(;
    xlabel="Time [s]",
    ylabel="Temperature [K]",
    title="LOF Bypass: Heated Channel (ch) Cell Temperatures — Overview (0-300s)\n(blue=cell 1, red=cell 10; reversed during NC)",
    size=(1000, 600),
    dpi=150,
    legend=:right,
)
for i in 1:n
    plot!(p8c, t_vec, T_ch[i]; label="T[$i]", lw=1.5, color=colors_cells[i])
end
add_events!(p8c)
savefig(p8c, joinpath(dir_overview, "03_temperatures_ch.png"))

println("  04_flapper_xi.png")
p8d = plot(
    t_vec,
    xi_arr;
    xlabel="Time [s]",
    ylabel="ξ (opening fraction)",
    title="Flapper Check Valve Opening State (0-300s)\n(ξ=0: closed, ξ=1: fully open)",
    lw=2.5,
    color=:purple,
    label="ξ",
    ylims=(-0.05, 1.1),
    size=(900, 400),
    dpi=150,
)
add_events!(p8d)
savefig(p8d, joinpath(dir_overview, "04_flapper_xi.png"))

println()
println("=== 02_transition_0to60s ===")

t_trans_hi = 60.0
idx_t = wmask(0.0, t_trans_hi)
tv_t = t_vec[idx_t]
mch_t = ṁ_ch[idx_t]
mret_t = ṁ_ret[idx_t]
mine_t = ṁ_ine[idx_t]
mflap_t = ṁ_flap[idx_t]
xi_t = xi_arr[idx_t]
dPch_t = dP_ch[idx_t]
dPret_t = dP_ret[idx_t]
Tch_t = [T_ch[i][idx_t] for i in 1:n]
Tret_t = [T_ret[i][idx_t] for i in 1:n]
Re_t = [Re_ch[i][idx_t] for i in 1:n]
htc_t = [htc_ch[i][idx_t] for i in 1:n]
qw_t = [q_wall_ch[i][idx_t] for i in 1:n]

println("  01_flow_ch_ret_zoom.png")
p9a = plot(
    tv_t,
    mch_t;
    label="ch (heated)",
    lw=2.5,
    color=:royalblue,
    xlabel="Time [s]",
    ylabel="Mass flow [kg/s]",
    title="LOF Bypass: ch and ret Flow — Transition 0–$(Int(t_trans_hi))s\n(ch crosses zero = flow reversal; negative = upward NC)",
    size=(1000, 500),
    dpi=150,
)
plot!(p9a, tv_t, mret_t; label="ret (return)", lw=2.5, color=:forestgreen)
hline!(p9a, [0.0]; color=:black, lw=1, ls=:dot, label="zero")

# Annotate ch zero-crossing
if any(mch_t .< 0)
    idx_cross = findfirst(mch_t .< 0)
    if !isnothing(idx_cross)
        t_cross = tv_t[idx_cross]
        vline!(
            p9a,
            [t_cross];
            color=:royalblue,
            lw=1.5,
            ls=:dashdot,
            label="ch reverses ($(round(t_cross; digits=1))s)",
        )
    end
end
add_events!(p9a; tmin=0.0, tmax=t_trans_hi)
savefig(p9a, joinpath(dir_trans, "01_flow_ch_ret_zoom.png"))

println("  02_flow_all_zoom.png")
p9b_top = plot(
    tv_t,
    mch_t;
    label="ch",
    lw=2,
    color=:royalblue,
    ylabel="ch / ret [kg/s]",
    title="LOF Bypass: All Flows — Transition 0–$(Int(t_trans_hi))s",
)
plot!(p9b_top, tv_t, mret_t; label="ret", lw=2, color=:forestgreen)
hline!(p9b_top, [0.0]; color=:black, lw=1, ls=:dot, label=nothing)
add_events!(p9b_top; tmin=0.0, tmax=t_trans_hi)

p9b_bot = plot(
    tv_t,
    mine_t;
    label="ine (pump branch)",
    lw=2,
    color=:gray,
    xlabel="Time [s]",
    ylabel="ine / flapper [kg/s]",
)
plot!(p9b_bot, tv_t, mflap_t; label="flapper path", lw=2, color=:purple, ls=:dash)
hline!(p9b_bot, [0.0]; color=:black, lw=1, ls=:dot, label=nothing)
add_events!(p9b_bot; tmin=0.0, tmax=t_trans_hi)

p9b = plot(
    p9b_top,
    p9b_bot;
    layout=(2, 1),
    size=(1000, 700),
    dpi=150,
    left_margin=8mm,
    right_margin=5mm,
)
savefig(p9b, joinpath(dir_trans, "02_flow_all_zoom.png"))

println("  03_flapper_xi_zoom.png")
t_xi_hi = isnan(flapper_fire_time) ? 20.0 : min(flapper_fire_time + 15.0, t_trans_hi)
idx_xi = wmask(0.0, t_xi_hi)
p9c = plot(
    t_vec[idx_xi],
    xi_arr[idx_xi];
    xlabel="Time [s]",
    ylabel="ξ (opening fraction)",
    title="Flapper Opening Event — Zoomed (0–$(round(t_xi_hi; digits=1))s)\n(Hermite cubic ramp over dt_ramp=$(dt_ramp)s)",
    lw=2.5,
    color=:purple,
    label="ξ",
    ylims=(-0.05, 1.1),
    size=(900, 420),
    dpi=150,
)
add_events!(p9c; tmin=0.0, tmax=t_xi_hi)
savefig(p9c, joinpath(dir_trans, "03_flapper_xi_zoom.png"))

println("  04_temperatures_ch_zoom.png")
p9d = plot(;
    xlabel="Time [s]",
    ylabel="Temperature [K]",
    title="LOF Bypass: Heated Channel (ch) Temperatures — Transition 0–$(Int(t_trans_hi))s\n(blue=cell 1 / inlet forward, red=cell 10 / outlet forward)",
    size=(1000, 600),
    dpi=150,
    legend=:right,
)
for i in 1:n
    plot!(p9d, tv_t, Tch_t[i]; label="T[$i]", lw=1.5, color=colors_cells[i])
end
add_events!(p9d; tmin=0.0, tmax=t_trans_hi)
savefig(p9d, joinpath(dir_trans, "04_temperatures_ch_zoom.png"))

println("  05_heat_flux_zoom.png")
p9e = plot(;
    xlabel="Time [s]",
    ylabel="Heat flux per cell [W]",
    title="LOF Bypass: Channel Wall Heat Flux — Transition 0–$(Int(t_trans_hi))s",
    size=(1000, 600),
    dpi=150,
    legend=:right,
)
for i in 1:n
    plot!(p9e, tv_t, qw_t[i]; label="q[$i]", lw=1.5, color=colors_cells[i])
end
add_events!(p9e; tmin=0.0, tmax=t_trans_hi)
savefig(p9e, joinpath(dir_trans, "05_heat_flux_zoom.png"))

println("  06_re_htc_log_zoom.png")
# Use mid-channel cell (cell 5) as representative; all cells behave similarly.
Re5_pos = max.(Re_t[5], 1.0)   # floor at 1 to avoid log(0) issues
htc5_pos = max.(htc_t[5], 1.0)

p9f_re = plot(
    tv_t,
    Re5_pos;
    ylabel="Re [-] (cell 5, log₁₀)",
    yscale=:log10,
    title="LOF Bypass: Re and HTC Log Scale — Transition 0–$(Int(t_trans_hi))s\n(Dittus-Boelter regime: HTC ∝ Re^0.8; NC Re << SS Re)",
    lw=2,
    color=:steelblue,
    label="Re (cell 5)",
    size=(1000, 700),
    dpi=150,
)
hline!(p9f_re, [2300.0]; color=:black, lw=1, ls=:dash, label="Re=2300 (lam/turb)")
add_events!(p9f_re; tmin=0.0, tmax=t_trans_hi)

p9f_htc = plot(
    tv_t,
    htc5_pos;
    xlabel="Time [s]",
    ylabel="HTC [W/m²K] (cell 5, log₁₀)",
    yscale=:log10,
    lw=2,
    color=:firebrick,
    label="HTC (cell 5)",
)
add_events!(p9f_htc; tmin=0.0, tmax=t_trans_hi)

p9f = plot(
    p9f_re,
    p9f_htc;
    layout=(2, 1),
    size=(1000, 700),
    dpi=150,
    left_margin=12mm,
    right_margin=5mm,
)
savefig(p9f, joinpath(dir_trans, "06_re_htc_log_zoom.png"))

println("  07_pressure_drops_zoom.png")
p9g = plot(
    tv_t,
    dPch_t;
    label="ch dP (heated channel)",
    lw=2,
    color=:royalblue,
    xlabel="Time [s]",
    ylabel="Pressure drop [Pa]",
    title="LOF Bypass: Channel Pressure Drops — Transition 0–$(Int(t_trans_hi))s\n(ch sign flips at NC; ch+ret buoyancy difference drives NC loop)",
    size=(1000, 500),
    dpi=150,
)
plot!(p9g, tv_t, dPret_t; label="ret dP (return channel)", lw=2, color=:forestgreen)
hline!(p9g, [0.0]; color=:black, lw=1, ls=:dot, label=nothing)
add_events!(p9g; tmin=0.0, tmax=t_trans_hi)
savefig(p9g, joinpath(dir_trans, "07_pressure_drops_zoom.png"))

println()
println("=== 03_nc_equilibrium (200–300s) ===")

t_nc_lo = 200.0
idx_nc = wmask(t_nc_lo, 300.0)
tv_nc = t_vec[idx_nc]
mch_nc = ṁ_ch[idx_nc]
mret_nc = ṁ_ret[idx_nc]
mflap_nc = ṁ_flap[idx_nc]
mine_nc = ṁ_ine[idx_nc]
Tch_nc = [T_ch[i][idx_nc] for i in 1:n]
qw_nc = [q_wall_ch[i][idx_nc] for i in 1:n]
Re_nc = [Re_ch[i][idx_nc] for i in 1:n]
htc_nc = [htc_ch[i][idx_nc] for i in 1:n]

ṁ_nc_mean = mean(abs.(mch_nc))

println("  01_nc_flow.png")
p10a = plot(
    tv_nc,
    mch_nc;
    label="ch (heated, upward NC → negative)",
    lw=2.5,
    color=:royalblue,
    xlabel="Time [s]",
    ylabel="Mass flow [kg/s]",
    title="LOF Bypass: Natural Circulation Mass Flows (200–300s)\nNC |ṁ| = $(round(ṁ_nc_mean; digits=5)) kg/s  ($(round(100*ṁ_nc_mean/ṁ_ss; digits=1))% of SS)",
    size=(1000, 500),
    dpi=150,
)
plot!(
    p10a,
    tv_nc,
    mret_nc;
    label="ret (return, downward NC → positive)",
    lw=2.5,
    color=:forestgreen,
)
plot!(p10a, tv_nc, mflap_nc; label="flapper path", lw=1.5, color=:purple, ls=:dash)
plot!(p10a, tv_nc, mine_nc; label="ine (pump branch, ≈ 0)", lw=1.5, color=:gray, ls=:dot)
hline!(p10a, [0.0]; color=:black, lw=1, ls=:dot, label=nothing)
savefig(p10a, joinpath(dir_nc, "01_nc_flow.png"))

println("  02_nc_temperatures_ch.png")
T_nc_max_mean = mean(Tch_nc[1])   # cell 1 = outlet in NC = hottest
p10b = plot(;
    xlabel="Time [s]",
    ylabel="Temperature [K]",
    title="LOF Bypass: Heated Channel Temperatures at NC Equilibrium (200–300s)\n(cell 1 = outlet under NC; T_max ≈ $(round(T_nc_max_mean - 273.15; digits=1)) °C)",
    size=(1000, 600),
    dpi=150,
    legend=:right,
)
for i in 1:n
    plot!(p10b, tv_nc, Tch_nc[i]; label="T[$i]", lw=1.5, color=colors_cells[i])
end
savefig(p10b, joinpath(dir_nc, "02_nc_temperatures_ch.png"))

println("  03_nc_heat_flux.png")
p10c = plot(;
    xlabel="Time [s]",
    ylabel="Heat flux per cell [W]",
    title="LOF Bypass: Channel Wall Heat Flux at NC Equilibrium (200–300s)",
    size=(1000, 600),
    dpi=150,
    legend=:right,
)
for i in 1:n
    plot!(p10c, tv_nc, qw_nc[i]; label="q[$i]", lw=1.5, color=colors_cells[i])
end
savefig(p10c, joinpath(dir_nc, "03_nc_heat_flux.png"))

println("  04_nc_re_htc.png")
Re_nc_mid = Re_nc[5]
htc_nc_mid = htc_nc[5]
Re_nc_mean = mean(Re_nc_mid)
p10d_re = plot(
    tv_nc,
    Re_nc_mid;
    ylabel="Re [-] (cell 5)",
    title="LOF Bypass: Re and HTC at NC Equilibrium (200–300s)\nRe ≈ $(round(Int, Re_nc_mean))  ($(Re_nc_mean < 2300 ? "laminar" : "turbulent"))",
    lw=2,
    color=:steelblue,
    label="Re (cell 5)",
)
hline!(p10d_re, [2300.0]; color=:black, lw=1, ls=:dash, label="Re=2300")
p10d_htc = plot(
    tv_nc,
    htc_nc_mid;
    xlabel="Time [s]",
    ylabel="HTC [W/m²K] (cell 5)",
    lw=2,
    color=:firebrick,
    label="HTC (cell 5)",
)
p10d = plot(p10d_re, p10d_htc; layout=(2, 1), size=(900, 700), dpi=150, left_margin=8mm)
savefig(p10d, joinpath(dir_nc, "04_nc_re_htc.png"))

println()
println("=== 04_spatial_profiles ===")

# Snapshot times: spread across the entire transient
snap_times_target = [0.0, 0.5, 2.0, 10.0, 30.0, 100.0, 200.0, 300.0]
snap_times_target = filter(t -> t <= t_vec[end], snap_times_target)
snap_idx = [argmin(abs.(t_vec .- tt)) for tt in snap_times_target]
snap_t = [t_vec[i] for i in snap_idx]
n_snaps = length(snap_idx)

# Color: early times = cool blue, late times = warm red
snap_colors_range = range(
    parse(Plots.Colors.Colorant, "steelblue");
    stop=parse(Plots.Colors.Colorant, "darkred"),
    length=n_snaps,
)
cell_axis = 1:n

println("  01_temperature_ch_multitime.png")
p11a = plot(;
    xlabel="Cell index (1=Node A, n=Node B)",
    ylabel="Temperature [K]",
    title="LOF Bypass: ch Temperature Profile at Key Times\n(gradient inversion = NC flow reversal established)",
    size=(1000, 650),
    dpi=150,
    legend=:outerright,
)
for (k, idx) in enumerate(snap_idx)
    T_snap = [T_ch[i][idx] for i in 1:n]
    lbl = "t=$(round(snap_t[k]; digits=1))s"
    plot!(
        p11a,
        cell_axis,
        T_snap;
        label=lbl,
        lw=2,
        color=snap_colors_range[k],
        marker=:circle,
        markersize=5,
    )
end
savefig(p11a, joinpath(dir_spatial, "01_temperature_ch_multitime.png"))

println("  02_temperature_ret_multitime.png")
p11b = plot(;
    xlabel="Cell index (1=Node B, n=Node C)",
    ylabel="Temperature [K]",
    title="LOF Bypass: ret Temperature Profile at Key Times\n(ret stays near T_inlet=$(T_inlet-273.15)°C — HX removes heat)",
    size=(1000, 650),
    dpi=150,
    legend=:outerright,
)
for (k, idx) in enumerate(snap_idx)
    T_snap = [T_ret[i][idx] for i in 1:n]
    lbl = "t=$(round(snap_t[k]; digits=1))s"
    plot!(
        p11b,
        cell_axis,
        T_snap;
        label=lbl,
        lw=2,
        color=snap_colors_range[k],
        marker=:circle,
        markersize=5,
    )
end
savefig(p11b, joinpath(dir_spatial, "02_temperature_ret_multitime.png"))

println("  03_heat_flux_ch_multitime.png")
p11c = plot(;
    xlabel="Cell index",
    ylabel="Heat flux per cell [W]",
    title="LOF Bypass: ch Wall Heat Flux Profile at Key Times\n(q ∝ HTC × (T_wall - T_cell); drops sharply with Re at coastdown)",
    size=(1000, 650),
    dpi=150,
    legend=:outerright,
)
for (k, idx) in enumerate(snap_idx)
    q_snap = [q_wall_ch[i][idx] for i in 1:n]
    lbl = "t=$(round(snap_t[k]; digits=1))s"
    plot!(
        p11c,
        cell_axis,
        q_snap;
        label=lbl,
        lw=2,
        color=snap_colors_range[k],
        marker=:circle,
        markersize=5,
    )
end
savefig(p11c, joinpath(dir_spatial, "03_heat_flux_ch_multitime.png"))
println("  04_temperature_heatmap_ch.png")

sub_step = max(1, div(length(t_vec), 600))
idx_sub = 1:sub_step:length(t_vec)
t_sub = t_vec[idx_sub]
T_matrix = Float64[T_ch[i][j] - 273.15 for i in 1:n, j in idx_sub]

p11d = heatmap(
    t_sub,
    1:n,
    T_matrix;
    xlabel="Time [s]",
    ylabel="Cell index\n(1=Node A under forward flow)",
    title="LOF Bypass: Heated Channel Temperature [°C] (cell × time)\n(gradient inversion shows NC reversal)",
    c=:hot,
    colorbar_title=" T [°C]",
    size=(1100, 500),
    dpi=150,
    left_margin=5mm,
    right_margin=20mm,
    bottom_margin=5mm,
    top_margin=5mm,
)
if !isnan(flapper_fire_time)
    vline!(
        p11d,
        [flapper_fire_time];
        color=:cyan,
        lw=2.5,
        ls=:dash,
        label="flapper fires ($(round(flapper_fire_time; digits=2))s)",
    )
end
savefig(p11d, joinpath(dir_spatial, "04_temperature_heatmap_ch.png"))

println()
println("="^70)
println("ALL PLOTS SAVED")
println("="^70)
println()
println("  01_overview/                        (0–300s, big picture)")
println("    01_flow_all_components.png        4-panel: each ṁ separately")
println("    02_flow_ch_ret.png                ch vs ret reversal, full time")
println("    03_temperatures_ch.png            all cell temps, full time")
println("    04_flapper_xi.png                 flapper opening, full time")
println()
println("  02_transition_0to60s/               (key action window)")
println("    01_flow_ch_ret_zoom.png           reversal + zero-crossing annotated")
println("    02_flow_all_zoom.png              2-panel, all components")
println("    03_flapper_xi_zoom.png            opening event, tight zoom")
println("    04_temperatures_ch_zoom.png       cell temps during transition")
println("    05_heat_flux_zoom.png             wall heat flux during transition")
println("    06_re_htc_log_zoom.png            Re & HTC log scale (lam/turb)")
println("    07_pressure_drops_zoom.png        dP sign flip at NC onset")
println()
println("  03_nc_equilibrium/                  (200–300s, NC plateau)")
println("    01_nc_flow.png                    NC ṁ values + flat lines")
println("    02_nc_temperatures_ch.png         cell temps at NC equilibrium")
println("    03_nc_heat_flux.png               wall heat flux at NC")
println("    04_nc_re_htc.png                  Re & HTC at NC (laminar check)")
println()
println("  04_spatial_profiles/")
println("    01_temperature_ch_multitime.png   ch T vs cell, 8 time snapshots")
println("    02_temperature_ret_multitime.png  ret T vs cell, 8 time snapshots")
println("    03_heat_flux_ch_multitime.png     q_wall vs cell, 8 snapshots")
println("    04_temperature_heatmap_ch.png     2D: cell×time heatmap (best overview)")
println()
println("Done.")
