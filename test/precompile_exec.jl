# precompile_exec.jl — PackageCompiler warmup script
#
# Goal: trigger enough method compilation to bake the slow TTFX paths into
# stream.so, WITHOUT running heavy solves that spike memory during the build.
#
# Run via: ./build_sysimage.sh   (never run this file directly as a test)

using STREAM
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using QuadGK

# ── Warmup: minimal Pump + Channel system ────────────────────────────────────
# Calls mtkcompile on a connected 2-node system to bake MTK symbolic IR dispatch
# into stream.so. n=2 is the smallest valid topology; method signatures are
# identical across system sizes so this covers all real use cases.
# Do NOT expand to build_loop() + solve — that adds memory pressure during build
# (per D-02). The goal is to trigger dispatch, not run a simulation.

@named pump = Pump(3.0e4)
geo = PipeGeometry_circular(1.0, 0.01)
@named ch = STREAM.Channel(; n=2, geometry=geo)

eqs = [
    connect(pump.outlet, ch.inlet),
    connect(ch.outlet, pump.inlet),
    ch.thermal.T ~ 373.15,
    pump.inlet.P ~ 1.0e5,
]
@named sys = System(eqs, t, [], []; systems=[pump, ch])
ssys = mtkcompile(sys)
println("precompile_exec: mtkcompile completed successfully")
