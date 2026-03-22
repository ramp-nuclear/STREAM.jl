---
phase: quick
plan: 260322-l7z
subsystem: examples
tags: [lof, transient, visualization, bypass-topology, natural-circulation]
dependency_graph:
  requires: [build_loop_lof_bypass, solve_transient, ChannelHeatFlux, Channel, Flapper, Inertia]
  provides: [examples/lof_transient.jl]
  affects: []
tech_stack:
  added: [Plots.jl (gr backend)]
  patterns: [_lof_bypass_ic IC strategy, native ContinuousCallback, sol.t as time axis]
key_files:
  created:
    - examples/lof_transient.jl
  modified:
    - .gitignore
    - Project.toml
    - Manifest.toml
decisions:
  - "Use sol.t as time axis: ContinuousCallback inserts extra time points, so sol[sym,:] returns 3003 elements vs t_arr 3001; must use sol.t for consistent array lengths in all plots"
  - "Replace vline!/hline! with full-length series: GR backend BoundsError when mixing 2-element reference lines with N-element data; workaround is fill(val, length(t_vec)) or zeros(length(t_vec))"
  - "Use annotate! for event markers: no series added, avoids GR length-mismatch issue"
metrics:
  duration_minutes: 25
  completed_date: "2026-03-22"
  tasks_completed: 2
  files_created: 1
  files_modified: 3
---

# Quick Task 260322-l7z Summary

**One-liner:** Standalone LOF bypass transient example script producing 11 annotated PNG plots and printing physical metrics (mdot_ss, mdot_nc, T_max, flapper fire time, energy balance ratio).

## What Was Built

`examples/lof_transient.jl` — a self-contained 616-line script that:

1. Builds a steady-state reference loop and solves for `mdot_ss` and `T_ss[1:n]`
2. Constructs the bypass LOF topology via `build_loop_lof_bypass()`
3. Sets initial conditions matching the `_lof_bypass_ic` pattern from `test/test_loss_of_flow.jl`
4. Registers a native `DifferentialEquations.ContinuousCallback` for the Flapper (required for parallel topologies)
5. Runs a 300-second transient simulation
6. Extracts all time series and prints a formatted metrics summary to stdout
7. Generates 11 PNG plots to `examples/output/lof_transient/`

## Plots Generated

| File | Content |
|------|---------|
| 01_mass_flow_rates.png | ch, ret, flapper, ine mdot vs time |
| 02_channel_temperatures.png | Heated channel T[1..10] vs time |
| 03_return_temperatures.png | Return channel T[1..10] vs time |
| 04_heat_flux.png | Heated channel q_wall[1..10] vs time |
| 05_reynolds.png | Heated channel Re[1..10] vs time with Re=2300 reference |
| 06_htc.png | Heated channel h_tc[1..10] vs time |
| 07_flapper_state.png | xi and T_open time series (2-panel) |
| 08_pressure_drops.png | ch.dP and ret.dP vs time |
| 09_temperature_profiles.png | T spatial profiles at t=0, t_fire, t=300s |
| 10_reynolds_profiles.png | Re spatial profiles at same 3 snapshots |
| 11_htc_profiles.png | HTC spatial profiles at same 3 snapshots |

## Sample Output (Physical Correctness)

```
Steady-state mdot     : 0.409677 kg/s
NC mdot (t=300s)      : 0.009355 kg/s  (2.3% of SS)
T_max at SS           : 334.16 K  (61.01 °C)
T_max at NC (t=300s)  : 357.64 K  (84.49 °C)
Flapper fires at      : 0.72 s
Flapper fully open at : 5.72 s
NC established ~      : 5.8 s
Energy balance ratio  : 1.0033  (1.0 = perfect, <5% err expected)
```

Results are physically correct:
- `mdot_nc` (2.3% of `mdot_ss`) confirms buoyancy-driven flow << forced flow
- `T_max_nc > T_max_ss` confirms higher temperature rise at lower NC flow rate
- Energy balance ratio 1.0033 (0.33% error) matches `VAL-01` test tolerance

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `SciMLBase` not in project dependencies**
- **Found during:** Task 1 first run
- **Fix:** Removed `using SciMLBase` — `ReturnCode` is re-exported by `DifferentialEquations`
- **Files modified:** examples/lof_transient.jl

**2. [Rule 3 - Blocking] `Plots.jl` not in project dependencies**
- **Found during:** Task 1 first run
- **Fix:** `julia --project -e 'import Pkg; Pkg.add("Plots")'`; updated Project.toml/Manifest.toml
- **Files modified:** Project.toml, Manifest.toml

**3. [Rule 1 - Bug] `@printf` requires `using Printf`**
- **Found during:** Task 1 first run
- **Fix:** Added `using Printf` to imports
- **Files modified:** examples/lof_transient.jl

**4. [Rule 1 - Bug] GR backend BoundsError: `sol[sym, :]` length mismatch with `t_arr`**
- **Found during:** Task 1 plot generation
- **Issue:** `ContinuousCallback` inserts 2 extra time points at the callback event, so `sol[ssys.ch.port_in.mdot, :]` returns 3003 elements while `collect(t_arr)` has 3001 elements. GR `gr_draw_segments` tries to access `x[1:3003]` on a 3001-element vector.
- **Fix:** Changed `t_vec = collect(t_arr)` to `t_vec = sol.t` throughout; all extracted data arrays now share the same length.
- **Files modified:** examples/lof_transient.jl

**5. [Rule 1 - Bug] GR backend BoundsError: mixing short reference lines with long data series**
- **Found during:** Task 1 plot generation (same root cause as above, different manifestation)
- **Issue:** `plot!(p, [x1, x2], [y1, y2]; ...)` 2-element series mixed with 3001-element data in same axes triggers GR's `x[1:N+2]` access.
- **Fix:** Replaced all 2-element reference lines with `fill(val, length(t_vec))` and `zeros(length(t_vec))` full-length series.
- **Files modified:** examples/lof_transient.jl

**6. [Rule 1 - Bug] `nc_time` soft-scope ambiguity in `for` loop**
- **Found during:** Task 1 first successful run (warning)
- **Fix:** Used `Ref{Float64}` pattern to avoid global/local ambiguity in loop.
- **Files modified:** examples/lof_transient.jl

## Commits

| Task | Commit | Files |
|------|--------|-------|
| Task 1: LOF example script | 16cf91b | examples/lof_transient.jl, Project.toml, Manifest.toml |
| Task 2: gitignore | 1cc2abe | .gitignore |

## Self-Check: PASSED

- `examples/lof_transient.jl` exists (616 lines, > 200 min_lines requirement)
- 11 PNG files exist in `examples/output/lof_transient/`
- `examples/output/` is in `.gitignore`
- Script runs to completion: `julia --project examples/lof_transient.jl` exits with code 0
- Stdout contains all required metrics (mdot_ss, mdot_nc, T_max_ss, T_max_nc, flapper fire time, energy balance ratio)
