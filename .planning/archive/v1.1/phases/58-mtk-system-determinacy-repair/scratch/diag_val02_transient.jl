# Phase 58 — Scenario F — VAL-02 transient T_wall step diagnostic
#
# Lifts the relevant fragments of test/test_validation.jl:295-326. This is
# NOT a determinacy gap — `build_loop_transient(...)` returns Δ=0 already.
# What fails is the symbol-access expression `ssys.sys.T_wall_callable` at line
# 317 of test_validation.jl. The compiled system reaches the callable via the
# top-level `ssys.T_wall_callable` (or `last(parameters(ssys))`).
#
# This script does NOT apply a fix; it is the diagnostic record of the symbol-
# access mismatch for the per-scenario diagnostic table.
#
# R-1 mitigation: explicit `using ModelingToolkit: connect`.

using ModelingToolkit
using ModelingToolkit: t_nounits as t
using ModelingToolkit: connect
using STREAM
import STREAM: build_loop_transient

println("\n=== Scenario F: VAL-02 transient T_wall step ===\n")

T_wall_step = t_val -> t_val < 10.0 ? 373.15 : 393.15
ssys = build_loop_transient(; T_inlet=313.15, T_wall_fn=T_wall_step)
n_eq = length(equations(ssys)); n_uk = length(unknowns(ssys))
n_init = length(ModelingToolkit.initialization_equations(ssys))
println("  Δ=", n_eq - n_uk, "  n_eqs=", n_eq, "  n_unknowns=", n_uk, "  n_init_eqs=", n_init,
        "   (NOT determinacy — Δ=0 already)")

println("\n-- ssys.sys.T_wall_callable access path (test_validation.jl:317) --")
try
    sym = ssys.sys.T_wall_callable
    println("  OK — found ", sym, "  (unexpected — research said this fails)")
catch e
    println("  FAILED: ", split(sprint(showerror, e), "\n")[1])
end

println("\n-- ssys.T_wall_callable direct access (the working alternative) --")
try
    sym = ssys.T_wall_callable
    println("  OK — found ", sym)
catch e
    println("  FAILED: ", split(sprint(showerror, e), "\n")[1])
end

println("\n-- last(parameters(ssys)) (test_integration.jl:192 alt) --")
try
    sym = last(parameters(ssys))
    println("  OK — found ", sym)
catch e
    println("  FAILED: ", split(sprint(showerror, e), "\n")[1])
end
