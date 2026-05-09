# Phase 58 baseline diagnostic — canonical build_loop must be fully determined.
# Verifies the determinacy assertion shape on a known-good system before
# applying it to the broken scenarios.
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using STREAM
import STREAM: build_loop, build_loop_vertical, build_loop_transient, build_cube,
                build_loop_lof_bypass

println("\n=== Phase 58 — canonical builder determinacy baseline ===\n")

function probe(name::String, ssys)
    n_eq = length(equations(ssys))
    n_uk = length(unknowns(ssys))
    println(rpad(name, 30), "  n_eqs=", lpad(n_eq, 4), "  n_unknowns=", lpad(n_uk, 4),
            "  Δ=", n_eq - n_uk)
    try
        n_ic = length(ModelingToolkit.initialization_equations(ssys))
        println(rpad("", 30), "  n_init_eqs=", n_ic)
    catch e
        println(rpad("", 30), "  initialization_equations() raised: ", typeof(e))
    end
end

probe("build_loop()", build_loop())
probe("build_loop_vertical()", build_loop_vertical())
probe("build_loop_transient()", build_loop_transient())
probe("build_cube()", build_cube())
# LOF bypass uses ChannelAndContacts + HeatDiffusion — same family as Phase 58 scenarios
probe("build_loop_lof_bypass()", build_loop_lof_bypass())

println("\n=== Determinacy contract test on build_loop() ===\n")
# Reconstruct uncompiled `sys` to test mtkcompile(sys; fully_determined=true) directly.
# build_loop's body is reproduced inline so we can invoke fully_determined=true.
@named pump = STREAM.Pump(3.0e4)
@named ch = STREAM.Channel(; n=10,
    geometry=STREAM.PipeGeometry_circular(0.6, 0.01),
    h_left=5000.0, h_right=0.0)
@named bc = STREAM.HeatExchanger(313.15)
T_wall = 373.15
T_inlet = 313.15
n = 10
connections = Equation[
    connect(pump.port_out, bc.port_in),
    connect(bc.port_out, ch.port_in),
    connect(ch.port_out, pump.port_in),
    pump.port_in.P ~ 1.0e5,
    [ch.T_wall_left[i]  ~ T_wall  for i in 1:n]...,
    [ch.T_wall_right[i] ~ T_inlet for i in 1:n]...,
]
@named sys = compose(System(connections, t; name=:sys), pump, bc, ch)

try
    ssys_strict = mtkcompile(sys; fully_determined=true)
    println("mtkcompile(sys; fully_determined=true) — SUCCESS")
    println("  n_eqs=", length(equations(ssys_strict)))
    println("  n_unknowns=", length(unknowns(ssys_strict)))
catch e
    println("mtkcompile(sys; fully_determined=true) — FAILED")
    println("  ", typeof(e), ": ", sprint(showerror, e))
end
