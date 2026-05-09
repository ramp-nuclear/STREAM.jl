# Phase 58 — diagnose PK validation determinacy.
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using ModelingToolkit: connect
using STREAM
import STREAM: build_loop_pk, ReactivityController

println("\n=== PK validation: build_loop_pk ===\n")
ctrl = ReactivityController()
ssys, ic = build_loop_pk(ctrl; n=7, T_inlet=293.15, P0=1.0, power_scale=1e4)
n_eq = length(equations(ssys)); n_uk = length(unknowns(ssys))
println("  build_loop_pk: Δ=", n_eq - n_uk, "  n_eqs=", n_eq, "  n_unk=", n_uk)
# Already part of build_loop_pk: `power_eqs = [rods_fuel.power ~ pk.P * power_scale]`
# So this is structurally complete (tier coupling closes power); confirm.
try
    ss_sol = solve_steady(ssys, ic)
    println("  solve_steady retcode: ", ss_sol.retcode)
catch e
    println("  solve_steady raised: ", split(sprint(showerror, e), "\n")[1])
end
