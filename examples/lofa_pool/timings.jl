# Cold and warm timings of the pool LOFA case. The first pass in a fresh process pays for
# compiling Julia and the model's generated code; the later passes reuse what they can.
#   STREAM_DECAY_HEAT_STANDARDS=/path julia --project=. examples/lofa_pool/timings.jl
const t_script_start = time()

using STREAM
using STREAM.Components
using OrdinaryDiffEq: ReturnCode
using Printf
using DelimitedFiles: writedlm

include(joinpath(@__DIR__, "model.jl"))
include(joinpath(@__DIR__, "case.jl"))
const t_load = time() - t_script_start

const times = range(0.0, t_end; length=n_saved)

function transient(model, sol_ss)
    sol = solve_transient(
        model.ssys, sol_ss, times;
        overrides=model.trip, callbacks=model.callbacks, tstops=times,
    )
    sol.retcode == ReturnCode.Success || error("the transient failed with $(sol.retcode)")
    return sol
end

# The transient scrams the reactor and opens the flapper, and both machines remember it, so
# re-solving the same model needs them back where they started.
untrip!(model) = (reset!(model.protection); reset!(model.valve); model)

phases = ("build and compile", "steady state", "transient")
passes = Pair{String,Vector{Any}}[]

ctrl, source = controls()
build = @timed build_pool_lofa(ctrl, source; case=case)
model = build.value
steady = @timed solve_pool_lofa_steady(model)
trans = @timed transient(model, steady.value)
push!(passes, "cold" => Any[build, steady, trans])

untrip!(model)
steady = @timed solve_pool_lofa_steady(model)
trans = @timed transient(model, steady.value)
push!(passes, "same model" => Any[nothing, steady, trans])

ctrl, source = controls()
build = @timed build_pool_lofa(ctrl, source; case=case)
steady = @timed solve_pool_lofa_steady(build.value)
trans = @timed transient(build.value, steady.value)
push!(passes, "rebuilt model" => Any[build, steady, trans])

compiling(r) = 100 * r.compile_time / r.time
cell(r) = r === nothing ? "-" : @sprintf("%.1f (%.0f%%)", r.time, compiling(r))
println("\nWALL TIME [s], with the share spent compiling")
@printf "  %-20s %18s %18s %18s\n" "phase" first.(passes)...
for (i, phase) in enumerate(phases)
    @printf "  %-20s %18s %18s %18s\n" phase (cell(last(p)[i]) for p in passes)...
end
@printf "  %-20s %18.1f\n" "load packages" t_load

# compare.py puts these next to Python's timings in comparison.md.
field(r, f) = r === nothing ? NaN : f(r)
table = Any["phase" "cold" "cold_compiling" "same_model" "rebuilt_model"]
for (i, phase) in enumerate(phases)
    cold, same, rebuilt = (last(p)[i] for p in passes)
    wall = [field(r, x -> x.time) for r in (cold, same, rebuilt)]
    share = field(cold, x -> x.compile_time / x.time)
    row = Any[phase wall[1] share wall[2] wall[3]]
    global table = vcat(table, row)
end
table = vcat(table, Any["load packages" t_load NaN NaN NaN])
outdir = joinpath(@__DIR__, "..", "output", "lofa_pool")
mkpath(outdir)
writedlm(joinpath(outdir, "julia_timings.csv"), table, ',')
