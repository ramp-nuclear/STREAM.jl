# Loss of flow in a pool-type MTR with two assembly types in parallel.
#
# Usage:
#   STREAM_DECAY_HEAT_STANDARDS=/path/to/STANDARDS julia --project examples/lofa_pool/run.jl
#
# The pump trips at t = 0. The flywheel carries the flow down, a low-flow signal scrams the
# reactor, and once the primary flow is low enough the flapper above the core opens and both
# assembly types turn around into natural circulation, with the pool taking the decay heat.
#
# Every number in the input block is a placeholder. They are sized so the model behaves as
# it would on real data, and they describe no plant. Replace them before reading anything
# off the results.

const t_script_start = time()

using STREAM
using STREAM.Components
using STREAM.Thresholds
using ModelingToolkit
using OrdinaryDiffEq: ReturnCode
using Printf
using DelimitedFiles: writedlm
include(joinpath(@__DIR__, "model.jl"))


# Wall, compile and GC time, allocations and peak memory of each phase, printed at the end.
const timings = Pair{String,Any}[]
function record!(label, time; compile_time=NaN, gctime=NaN, bytes=NaN)
    push!(timings, label => (; time, compile_time, gctime, bytes, rss=Sys.maxrss()))
    return nothing
end
function timed(f, label)
    r = @timed f()
    record!(label, r.time; r.compile_time, r.gctime, r.bytes)
    return r.value
end
record!("load packages", time() - t_script_start)

include(joinpath(@__DIR__, "case.jl"))

# #### Model
ctrl, source = controls()

println("Building and compiling the model...")
model = timed("build and compile model") do
    build_pool_lofa(ctrl, source; case=case)
end
ssys = model.ssys
@printf "  %d unknowns, %d observed\n" length(unknowns(ssys)) length(observed(ssys))
println("Settling the steady state...")
sol_ss = timed(() -> solve_pool_lofa_steady(model, case), "steady state")

println("\nSTEADY STATE")
@printf "  %-6s %14s %14s %10s\n" "type" "design ṁ" "achieved ṁ" "T_out"
for key in keys(case.types)
    ch = model.channels[key]
    design = case.types[key].design_ṁ
    achieved, T_out = sol_ss[ch.inlet.ṁ], sol_ss[ch.T[case.n]]
    @printf "  %-6s %14.4f %14.4f %10.2f\n" string(key) design achieved T_out
end
primary_ss, decay_share = sol_ss[ssys.flywheel.inlet.ṁ], 100 * source(0.0)
@printf "  primary flow %.3f kg/s, decay heat %.2f%% of rated\n" primary_ss decay_share

println("\nRunning the transient to $(t_end) s...")
times = range(0.0, t_end; length=n_saved)
sol = timed("transient") do
    # A saved point inside a step is read off the step's interpolant, which strays for this
    # DAE: an 85 to 97 s step once showed a 12% flow dip, and the step that ends on the trip
    # a 1.5% one. Stepping onto every saved time leaves no saved point interpolated.
    solve_transient(
        ssys, sol_ss, times; overrides=model.trip, callbacks=model.callbacks, tstops=times
    )
end
sol.retcode == ReturnCode.Success ||
    error("the transient failed with retcode $(sol.retcode)")

t_trip = ctrl.t_state
t_flapper = sol.ps[ssys.flapper.T_open]
flow(key) = sol[model.channels[key].inlet.ṁ, :]
function reversal_time(key)
    k = findfirst(<(0.0), flow(key))
    return k === nothing ? NaN : sol.t[k]
end

println("\nEVENTS")
@printf "  low-flow trip             %8.2f s\n" t_trip
@printf "  flapper opens             %8.2f s\n" t_flapper
for key in keys(case.types)
    @printf "  %-6s turns around        %8.2f s\n" string(key) reversal_time(key)
end

# #### Results for the Python comparison

# compare.py rebuilds this case in Python STREAM from these two files, so the placeholder
# numbers live in one place and the trip time Python imposes is the one Julia found.
_json(x::Integer) = string(x)
_json(x::Real) = isfinite(x) ? repr(Float64(x)) : "null"
_json(x::Symbol) = repr(string(x))
_json(x::Union{AbstractVector,Tuple}) = "[" * join(map(_json, collect(x)), ", ") * "]"
function _json(x::NamedTuple)
    fields = ("\"$(k)\": " * _json(v) for (k, v) in pairs(x))
    return "{" * join(fields, ", ") * "}"
end

resultsdir = joinpath(@__DIR__, "..", "output", "lofa_pool")
mkpath(resultsdir)
steady = (;
    primary=primary_ss,
    (Symbol(:mdot_, k) => sol_ss[model.channels[k].inlet.ṁ] for k in keys(case.types))...,
    (
        Symbol(:T_out_, k) => sol_ss[model.channels[k].T[case.n]] for k in keys(case.types)
    )...,
)
events = (;
    t_trip,
    t_flapper,
    (Symbol(:t_reversal_, k) => reversal_time(k) for k in keys(case.types))...,
)
# What the solver integrated: a unit on the mass matrix diagonal marks a differential
# unknown, a zero an algebraic one, and a plain identity means every one is differential.
n_unknowns = length(unknowns(ssys))
M = sol.prob.f.mass_matrix
n_differential =
    M isa AbstractMatrix ? count(i -> !iszero(M[i, i]), 1:n_unknowns) : n_unknowns
# The algebraic unknowns grouped by name, with the cell indices dropped, so the comparison
# can say what they are.
algebraic_names = Dict{String,Int}()
if M isa AbstractMatrix
    for (i, u) in enumerate(unknowns(ssys))
        iszero(M[i, i]) || continue
        # Cells show up both as array indices, T[3], and inside port names, thermal_left3.
        name = replace(string(u), r"\[[0-9, ]+\]" => "", "(t)" => "", r"(?<=[a-z])\d+(?=₊)" => "")
        algebraic_names[name] = get(algebraic_names, name, 0) + 1
    end
end
println("\nALGEBRAIC UNKNOWNS, by name")
for (name, count) in sort(collect(algebraic_names))
    @printf "  %4d  %s\n" count name
end
size_ = (;
    before=model.n_before,
    unknowns=n_unknowns,
    differential=n_differential,
    algebraic=n_unknowns - n_differential,
    observed=length(observed(ssys)),
    algebraic_by_name=(; (Symbol(k) => v for (k, v) in sort(collect(algebraic_names)))...),
)
# The wall cell that is hottest at steady state, where the comparison reads each type's h.
hot_cell = NamedTuple{keys(case.types)}(
    Tuple(
        argmax([sol_ss[model.channels[k].T_wall_left[i]] for i in 1:(case.n)]) for
        k in keys(case.types)
    ),
)
inputs = (;
    case, rod_delay, rod_insertion, rod_worth, captures_per_fission, t_end, n_saved, events,
    steady, size=size_, hot_cell,
)
write(joinpath(resultsdir, "julia_case.json"), _json(inputs))

hottest(syms) = reduce((a, b) -> max.(a, b), (sol[s] for s in syms))
dz = case.L / case.n
series = Pair{String,Vector{Float64}}[
    "t" => sol.t,
    "mdot_primary" => sol[ssys.flywheel.inlet.ṁ, :],
    "mdot_flapper" => sol[ssys.flapper.inlet.ṁ, :],
    "P" => sol[ssys.pk.P, :],
    "P_neutron" => sol[ssys.pk.P_neutron, :],
]
for key in keys(case.types)
    ch = model.channels[key]
    fuel = getproperty(getproperty(ssys, Symbol(:rods_, key)), Symbol(:fuel_, key))
    plate = vec([fuel.T[i, j] for i in 1:(case.n), j in 1:(case.nx)])
    # Each cell's dp is friction plus the hydrostatic ρ·g_acc·dz, with g_acc = -g in the
    # downward core, so adding ρ·g·dz back leaves the friction.
    friction = sum(sol[ch.dp[i]] .+ G_EARTH * dz .* ρ.(H2O, sol[ch.T[i]]) for i in 1:(case.n))
    push!(series, "mdot_$(key)" => flow(key))
    push!(series, "Tcool_max_$(key)" => hottest(collect(ch.T)))
    push!(series, "Twall_max_$(key)" => hottest(collect(ch.T_wall_left)))
    push!(series, "Tfuel_max_$(key)" => hottest(plate))
    push!(series, "h_$(key)" => sol[ch.h_tc_left[hot_cell[key]]])
    push!(series, "Q_$(key)" => sol[ch.Q_wall_total])
    push!(series, "dP_$(key)" => sol[ch.dP])
    push!(series, "dPfric_$(key)" => friction)
end
writedlm(
    joinpath(resultsdir, "julia_series.csv"),
    [permutedims(first.(series)); reduce(hcat, last.(series))],
    ',',
)

# #### Margins

# Each is arranged so larger is safer, which is what worst_case expects.
onb_margin(s) = bergles_rohsenow_t_onb(s) .- s.T_wall
function channel_power(s)
    faces =
        s.q_flux_left .* s.pipe.heated_parts[1] .+ s.q_flux_right .* s.pipe.heated_parts[2]
    return sum(faces) * s.pipe.L / s.n
end
ofi_ratio(s) = (Q = channel_power(s); Q > 0 ? q_OFI_whittle_forgan(s) / Q : Inf)
osv_ratio(s) = (q = maximum(s.q_flux); q > 0 ? q_OSV_saha_zuber(s) / q : Inf)

margins = timed("margins") do
    Dict(
        key => threshold_analysis(
            sol,
            model.channels[key];
            pipe=model.pipes[key],
            gravity=G_EARTH,
            chfr_sk=chfr(q_CHF_sudo_kaminaga),
            chfr_mirshak=chfr(q_CHF_mirshak),
            onb=onb_margin,
            ofi=ofi_ratio,
            osv=osv_ratio,
            twall=twall_limit,
        ) for key in keys(case.types)
    )
end
# Whittle-Forgan and Saha-Zuber are forced-flow correlations. Near zero flow and under
# reversal they stop meaning anything, so those times are left out of their minimum rather
# than hidden.
forced(key) = flow(key) .> forced_fraction * case.types[key].design_ṁ

# The whole run, then only once the rods are fully in. The full-power start usually sets the
# first table, and the second is the part a loss of flow is about.
windows = (
    ("WORST MARGINS, WHOLE TRANSIENT", trues(length(sol.t))),
    ("WORST MARGINS ONCE THE RODS ARE IN", sol.t .> t_trip + rod_delay + rod_insertion),
)
for (title, keep) in windows
    t_kept = sol.t[keep]
    println("\n", title, " (larger is safer)")
    @printf "  %-6s %-32s %10s %6s %10s\n" "type" "quantity" "worst" "cell" "t [s]"
    for key in keys(case.types)
        r = margins[key]
        ok = forced(key)[keep]
        wc(m) = worst_case(m; times=t_kept)
        forced_only(v) = ifelse.(ok, v[keep], Inf)
        rows = (
            ("CHF ratio, Sudo-Kaminaga", wc(r.chfr_sk[:, keep])),
            ("CHF ratio, Mirshak", wc(r.chfr_mirshak[:, keep])),
            ("ONB margin T_ONB - T_wall [K]", wc(r.onb[:, keep])),
            ("OFI ratio, forced flow only", wc(forced_only(r.ofi))),
            ("OSV ratio, forced flow only", wc(forced_only(r.osv))),
        )
        for (label, w) in rows
            cell = w.cell === nothing ? "-" : string(w.cell)
            @printf "  %-6s %-32s %10.3f %6s %10.2f\n" string(key) label w.value cell w.time
        end
        peak, idx = findmax(r.twall[:, keep])
        label = "peak wall temperature [°C]"
        t_peak = t_kept[idx[2]]
        @printf "  %-6s %-32s %10.2f %6d %10.2f\n" string(key) label peak idx[1] t_peak
    end
end

# #### Energy

cp = cₚ(H2O, case.T_pool)
# Upward flow leaves each channel through its top cell, into the pool.
function pool_duty(key)
    exit_rise = sol[model.channels[key].T[1], end] - case.T_pool
    return case.types[key].N * abs(flow(key)[end]) * cp * exit_rise
end
Q_pool = sum(pool_duty, keys(case.types))
println("\nENERGY AT THE END")
@printf "  decay power                %10.1f W\n" sol[ssys.pk.P, end] * case.P_rated
@printf "  carried into the pool      %10.1f W  (exit enthalpy rise, upward flow)\n" Q_pool

# #### Plots

# Loaded only here: loaded before the model is built, Plots invalidates code the build and
# the solves use, which then compiles again and costs about two minutes on a cold run.
using Plots
ENV["GKSwstype"] = "100"   # headless GR, so no display is needed
Plots.gr()

outdir = joinpath(@__DIR__, "..", "output", "lofa_pool")
timed("plots") do
    mkpath(outdir)
    events = filter(isfinite, [t_trip, t_flapper])
    mark!(p) = vline!(p, events; color=:gray, linestyle=:dash, label="trip, flapper")

    p_flow = plot(; xlabel="t [s]", ylabel="ṁ per channel [kg/s]", title="Channel flow")
    for key in keys(case.types)
        plot!(p_flow, sol.t, flow(key); label=string(key))
    end
    hline!(p_flow, [0.0]; color=:black, label="")
    mark!(p_flow)
    p_primary = plot(
        sol.t,
        sol[ssys.flywheel.inlet.ṁ, :];
        label="primary",
        xlabel="t [s]",
        ylabel="ṁ [kg/s]",
        title="Primary and flapper flow",
    )
    plot!(p_primary, sol.t, sol[ssys.flapper.inlet.ṁ, :]; label="flapper")
    mark!(p_primary)
    savefig(
        plot(p_flow, p_primary; layout=(2, 1), size=(900, 800)),
        joinpath(outdir, "01_flow.svg"),
    )

    floor_at(v) = max.(v, 1e-8)
    p_power = plot(
        sol.t,
        floor_at(sol[ssys.pk.P, :]);
        label="P, total",
        yscale=:log10,
        xlabel="t [s]",
        ylabel="fraction of rated",
        title="Power",
    )
    plot!(p_power, sol.t, floor_at(sol[ssys.pk.P_neutron, :]); label="P_neutron, fission")
    plot!(p_power, sol.t, floor_at(source.(sol.t)); label="decay heat", linestyle=:dot)
    mark!(p_power)
    savefig(p_power, joinpath(outdir, "02_power.svg"))

    p_temp = plot(; xlabel="t [s]", ylabel="T [°C]", title="Hottest coolant and fuel")
    for key in keys(case.types)
        ch = model.channels[key]
        fuel = getproperty(getproperty(ssys, Symbol(:rods_, key)), Symbol(:fuel_, key))
        coolant = [maximum(sol[ch.T[i], k] for i in 1:(case.n)) for k in eachindex(sol.t)]
        fuel_cells = [fuel.T[i, j] for i in 1:(case.n), j in 1:(case.nx)]
        plate = [maximum(sol[c, k] for c in fuel_cells) for k in eachindex(sol.t)]
        plot!(p_temp, sol.t, coolant; label="$(key) coolant")
        plot!(p_temp, sol.t, plate; label="$(key) fuel", linestyle=:dash)
    end
    mark!(p_temp)
    savefig(p_temp, joinpath(outdir, "03_temperatures.svg"))

    p_chf = plot(;
        xlabel="t [s]",
        ylabel="min CHF ratio",
        yscale=:log10,
        title="CHF ratio, Sudo-Kaminaga",
    )
    p_onb = plot(; xlabel="t [s]", ylabel="min T_ONB - T_wall [K]", title="ONB margin")
    for key in keys(case.types)
        r = margins[key]
        plot!(p_chf, sol.t, vec(minimum(r.chfr_sk; dims=1)); label=string(key))
        plot!(p_onb, sol.t, vec(minimum(r.onb; dims=1)); label=string(key))
    end
    hline!(p_onb, [0.0]; color=:black, label="")
    mark!(p_chf)
    mark!(p_onb)
    savefig(
        plot(p_chf, p_onb; layout=(2, 1), size=(900, 800)),
        joinpath(outdir, "04_margins.svg"),
    )
end

println("\nPlots written to $(outdir)")

# #### Timings

println("\nTIMINGS")
row = Printf.Format("  %-24s %9s %10s %6s %10s %9s\n")
Printf.format(stdout, row, "phase", "wall [s]", "compiling", "GC", "allocated", "peak RSS")
share(x, total) = isnan(x) ? "-" : @sprintf("%.0f%%", 100 * x / total)
gib(x) = isnan(x) ? "-" : @sprintf("%.2f GB", x / 2^30)
for (label, r) in timings
    wall = @sprintf("%.1f", r.time)
    compiling, gc = share(r.compile_time, r.time), share(r.gctime, r.time)
    Printf.format(stdout, row, label, wall, compiling, gc, gib(r.bytes), gib(r.rss))
end
total = time() - t_script_start
installed, free = Sys.total_memory() / 2^30, Sys.free_memory() / 2^30
@printf "  total %.1f s; memory %.1f GB, %.1f GB free at the end\n" total installed free
