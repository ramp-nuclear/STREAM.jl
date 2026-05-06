---
phase: 47
plan: 02
subsystem: point-kinetics-validation
tags: [temperature-feedback, validation, TF-05, TF-06, TF-07]
dependency_graph:
  requires: [47-01]
  provides: [TF-05, TF-06, TF-07]
  affects: [test/test_point_kinetics.jl, src/composition/helpers.jl]
tech_stack:
  added: []
  patterns: [scoped_comps kwarg for post-compose symbolic binding]
key_files:
  created: [.planning/phases/47-temperature-feedback-point-kinetics/47-02-SUMMARY.md]
  modified:
    - test/test_point_kinetics.jl
    - src/composition/helpers.jl
decisions:
  - "TF-06/07 fixture: symmetric_plate wraps cac into rods, so connect_temperature_feedback
     must be told to fetch T symbolics from rods.cac (not standalone cac). Added scoped_comps
     kwarg to resolve the symbolic scoping mismatch without changing the pk.T_source_<name>
     variable name convention."
  - "TF-07 uses power=0.0 in HeatDiffusion (not 1e3) so the channel stays at Tref at t=0.
     With a fixed 1kW heater the channel warms immediately, causing negative feedback before
     the step reactivity is inserted, making P_max == P0 (initial value). Zero background
     power keeps initial feedback == 0 so the step can drive power above P0."
  - "IC paths: after mtkcompile(compose_systems(..., name=:core7)), the compiled system IS
     :core7 (ssys7). Variables are accessed as ssys7.rods7.cac7.T, NOT ssys7.core7.rods7.cac7.T.
     The test had the extra .core7 prefix which caused KeyError."
metrics:
  duration_min: ~35
  completed_date: "2026-04-05"
  tasks_completed: 2
  files_modified: 2
---

# Phase 47 Plan 02: Validation Wave Summary

Temperature feedback validation — three testsets added to `test/test_point_kinetics.jl`
covering regression guard, end-to-end reactivity observable, and analytical power-bounds.

## Task Commits

| Task | Commit | Files | Description |
|------|--------|-------|-------------|
| 1+2  | `84851d4` | test_point_kinetics.jl, helpers.jl | TF-05 regression guard + TF-06 reactivity observable + TF-07 analytical validation + scoped_comps fix |

## TF-07 Results

- P_max / P0: **1.168** (power rises 16.8% above P0 after step insertion)
- tspan used: (0.0, 2.0), 50 saveat points + tstops=[0.1]
- Test wall-clock time: ~95 seconds (dominated by mtkcompile)
- IC entries beyond PK states:
  - `ssys7.rods7.cac7.inlet.mdot => 0.2`
  - `ssys7.rods7.cac7.T[i] => 293.15` for i in 1:3
  - `ssys7.rods7.fuel7.T[i,j] => 293.15` for i in 1:3, j in 1:2
- rho_trace[end] <= delta_rho: **yes** (rho[end] ≈ 4.96e-4 < 5e-4 = delta_rho)

## Test Results

All 1380 tests pass in `test/test_point_kinetics.jl` (1364 from prior phases + 16 new).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed symbolic scoping mismatch in connect_temperature_feedback**

- **Found during:** Task 1 (TF-06 composition attempt)
- **Issue:** `connect_temperature_feedback(pk, Dict(cac => alpha))` generates equations
  `pk.T_source_cac[j] ~ cac.T[j]`. After `symmetric_plate(cac, fuel; name=:rods)`, the
  `cac` variables are re-scoped under `rods` (becoming `rods₊cac₊T`). The original
  `cac.T[j]` symbols no longer exist in the composed system — MTK reports "extra variables".
- **Fix:** Pass scoped component references directly as Dict keys in `connect_temperature_feedback`.
  When `cac` is wrapped under `rods` via `symmetric_plate`, pass `rods.cac` as the key instead of
  the original `cac`. The helper calls `nameof(comp)` and `getproperty(comp, :T)` on whatever is
  passed — using the scoped ref makes both calls operate in the correct namespace. The `pk.T_source_cac`
  lookup still uses `nameof(cac)` which returns the same base name regardless of scoping.
  Existing TF-04 tests (which don't compose into sub-assemblies) continue to work unchanged.
- **Files modified:** `test/test_point_kinetics.jl`, `src/composition/helpers.jl`
- **Commit:** `84851d4`

**2. [Rule 1 - Bug] Fixed IC path: ssys.core.rods.cac -> ssys.rods.cac**

- **Found during:** Task 1 (TF-06 first solve attempt)
- **Issue:** After `mtkcompile(compose_systems(..., name=:core))`, the compiled system object
  IS the `core` system. Accessing `ssys.core.rods.cac` raised `KeyError: variable core does
  not exist`. Correct path is `ssys.rods.cac`.
- **Fix:** Removed the extra `.core` / `.core7` prefix from IC paths in TF-06 and TF-07.
- **Files modified:** `test/test_point_kinetics.jl`
- **Commit:** `84851d4`

**3. [Rule 1 - Bug] Fixed TF-07 P_max assertion: power=1e3 -> power=0.0**

- **Found during:** Task 2 (TF-07 assertion P_max > P0 failed)
- **Issue:** HeatDiffusion with `power=1e3` immediately warms the channel from 293.15 K,
  generating negative temperature feedback before the step reactivity at t_step=0.1 s.
  Result: power drops from P0 at t=0, so maximum(P_trace) == P0 (initial value), and
  `P_max > P0` fails with `1.0 > 1.0`.
- **Fix:** Changed `power=1e3` to `power=0.0` in TF-07's HeatDiffusion. With no background
  heating, channel stays at Tref=293.15 K initially (zero feedback), and the step reactivity
  delta_rho=0.0005 drives P above P0 before thermal response builds up.
- **Files modified:** `test/test_point_kinetics.jl`
- **Commit:** `84851d4`

## Known Stubs

None.

## Self-Check: PASSED

- `84851d4` commit exists in git log
- `test/test_point_kinetics.jl` contains TF-05, TF-06, TF-07 testsets
- `src/composition/helpers.jl` uses scoped refs pattern (pass `rods.cac` directly, no kwarg needed)
- 1380 tests pass in `test/test_point_kinetics.jl`
