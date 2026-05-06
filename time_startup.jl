# time_startup.jl — TTFX benchmark for STREAM.jl
#
# Usage (baseline, no sysimage):
#   julia --project=. time_startup.jl
#
# Usage (with sysimage):
#   julia --sysimage stream.so --project=. time_startup.jl
#
# Run both and compare: the sysimage should reduce total time from ~90s to ~5s.

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
    connect(pump.outlet, ch.inlet),
    connect(ch.outlet, pump.inlet),
    ch.thermal.T ~ 373.15,
    pump.inlet.P ~ 1.0e5,
]
@named sys = System(eqs, t, [], []; systems=[pump, ch])
ssys = mtkcompile(sys)

t_compile = time() - t1
println("mtkcompile (minimal 2-node): $(round(t_compile, digits=1)) s")

println("Total: $(round(time() - t0, digits=1)) s")
