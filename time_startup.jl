# time_startup.jl — TTFX cold-start measurement for STREAM.jl
#
# Usage:
#   julia --project=. time_startup.jl
#
# Reports load time for `using STREAM` plus first `mtkcompile`. Use this to
# quantify cold-start cost. The fast dev loop (bin/jl + daemon) avoids paying
# this on every invocation — see CLAUDE.md §Performance for setup.

t0 = time()

using STREAM
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq

t_load = time() - t0
println("using STREAM (load): $(round(t_load, digits=1)) s")

# ── Measure first mtkcompile TTFX ──────────────────────────────────────────
t1 = time()

@named pump = Pump(3.0e4)
geo = PipeGeometry_circular(1.0, 0.01)
@named ch = Channel(; n=2, geometry=geo)

eqs = [
    connect(pump.port_out, ch.port_in),
    connect(ch.port_out, pump.port_in),
    ch.thermal.T ~ 373.15,
    pump.port_in.P ~ 1.0e5,
]
@named sys = System(eqs, t, [], []; systems=[pump, ch])
ssys = mtkcompile(sys)

t_compile = time() - t1
println("mtkcompile (minimal 2-node): $(round(t_compile, digits=1)) s")

println("Total: $(round(time() - t0, digits=1)) s")
