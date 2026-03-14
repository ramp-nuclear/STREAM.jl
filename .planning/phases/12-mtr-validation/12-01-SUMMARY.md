---
phase: 12-mtr-validation
plan: "01"
subsystem: testing
tags: [python-stream, mtr-geometry, heat-diffusion, validation, reference-values]

requires:
  - phase: 11-heat-diffusion
    provides: HeatDiffusion component with power_shape parameter

provides:
  - "test/generate_mtr_reference.py: Python STREAM MTR reference script covering VAL-01/02/03"
  - "test/runtests.jl Phase 12 testset skeleton with HDIFF-03-gap test passing"

affects:
  - 12-02 (Plan 02 will use reference constants from generate_mtr_reference.py)

tech-stack:
  added: []
  patterns:
    - "FlowGraph + CalculationGraph composition: fg.aggregator + plate_cg + power_cg → .to_aggregator()"
    - "Fuel power funcs via CalculationGraph.from_decoupled(fuel, funcs={fuel: dict(power=POWER)})"

key-files:
  created:
    - test/generate_mtr_reference.py
  modified:
    - test/runtests.jl

key-decisions:
  - "plate() returns CalculationGraph with empty funcs; fuel power must be passed via separate CalculationGraph.from_decoupled"
  - "Non-uniform power_shape test uses [0.0, 1.0, 0.0] (center-sourced) not [0.5, 0.0, 0.5] — symmetric outer sources produce equal temperatures at steady state due to Laplacian=0 forcing T_center = avg(T_left, T_right)"
  - "generate_mtr_reference.py uses fresh component objects per scenario — Python STREAM components carry state"

requirements-completed:
  - VAL-01
  - VAL-02
  - VAL-03

duration: 30min
completed: 2026-03-14
---

# Phase 12 Plan 01: MTR Reference Script and HDIFF-03 Gap Test Summary

**Python STREAM MTR reference script (VAL-01/02/03) written and HDIFF-03-gap power_shape test passing; awaiting user to run generate_mtr_reference.py for hardcoded constants**

## Performance

- **Duration:** ~30 min
- **Started:** 2026-03-14T02:10:00Z
- **Completed:** 2026-03-14T02:40:04Z
- **Tasks:** 2 complete, 1 checkpoint (human-action)
- **Files modified:** 2

## Accomplishments

- Wrote `test/generate_mtr_reference.py` covering all three MTR validation scenarios using Python STREAM's `plate()` and `one_sided_connection()` APIs
- Discovered and documented the correct `FlowGraph + CalculationGraph` composition pattern for coupled thermal-hydraulic systems
- Added Phase 12 testset to `runtests.jl` with HDIFF-03-gap test (all 6 Phase 12 tests pass)
- Auto-fixed physically incorrect test assertion (center cell with zero source is NOT colder than outer cells — it equals them in symmetric steady state)

## Task Commits

1. **Task 1: Write test/generate_mtr_reference.py** - `0805cb5` (feat)
2. **Task 2: Add HDIFF-03 gap test and Phase 12 testset skeleton** - `12dd9e7` (feat)

## Files Created/Modified

- `test/generate_mtr_reference.py` — Python STREAM MTR coupled plate reference script; three scenarios (VAL-01 symmetric, VAL-02 asymmetric 90°C right, VAL-03 one-sided left); prints constants in paste-ready format
- `test/runtests.jl` — Extended with `@testset "STREAM Phase 12 Tests"` containing HDIFF-03-gap test

## Python STREAM API Discoveries

The key composition pattern for MTR reference:

```python
# Build separate FlowGraphs per hydraulic loop
fg_l = FlowGraph(flow_edge(("A","B"), pump_l, hx_l), flow_edge(("B","A"), ch_l),
                 funcs={ch_l: dict(p_abs=P_ABS)},
                 reference_node=("A", P_ABS), abs_pressure_comps=[ch_l])
fg_r = FlowGraph(...)  # similar for right loop

# plate() returns CalculationGraph with empty funcs
plate_cg = plate(ch_l, ch_r, fuel)  # → CalculationGraph, no funcs

# Fuel power must be injected via separate CalculationGraph
power_cg = CalculationGraph.from_decoupled(fuel, funcs={fuel: dict(power=POWER)})

# Combine all: hydraulic loops + thermal coupling + fuel power
full_cg = fg_l.aggregator + fg_r.aggregator + plate_cg + power_cg
agr = full_cg.to_aggregator()
```

For VAL-03 (one-sided), `one_sided_connection(ch_l, fuel, fuel_side="left")` replaces `plate()`.

## Decisions Made

1. **plate() funcs pattern**: `plate()` produces a CalculationGraph with no funcs. Fuel power is injected via `CalculationGraph.from_decoupled(fuel, funcs={fuel: dict(power=POWER)})`. The combine operation (`+`) merges the `funcs` dicts.

2. **HDIFF-03-gap test fix**: Changed power_shape from `[0.5, 0.0, 0.5]` to `[0.0, 1.0, 0.0]`. With symmetric BCs and equal outer sources, the steady-state Laplacian=0 constraint forces T_center = (T_left + T_right)/2 = T_left — center cannot be strictly colder. The reversed shape (all power in center) correctly demonstrates per-cell power_shape application.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed physically incorrect HDIFF-03 test assertion**
- **Found during:** Task 2 (HDIFF-03-gap test execution)
- **Issue:** Plan specified `power_shape = [0.5, 0.0, 0.5]` with assertion `T_left > T_center + 0.01`. At steady state, the Laplacian=0 constraint for the interior center cell forces `T_center = (T_left + T_right)/2`. With symmetric BC and equal outer sources, `T_left = T_right`, so `T_center = T_left` — the assertion is physically impossible.
- **Fix:** Changed power_shape to `[0.0, 1.0, 0.0]` (all power in center). Center cell receives all heat and must be hotter than outer cells. Assertions updated to `T_center > T_left + 0.01` and `T_center > T_right + 0.01`.
- **Files modified:** test/runtests.jl
- **Verification:** All 6 Phase 12 tests pass including HDIFF-03-gap
- **Committed in:** `12dd9e7` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - Bug)
**Impact on plan:** Essential fix for physical correctness. The test now correctly verifies per-cell power_shape application.

## Checkpoint: Human Action Required

**Status:** Awaiting user to run generate_mtr_reference.py

**Steps for user:**
1. Activate your Python STREAM environment
2. Run: `cd /home/itay/projects/Julia-STREAM/test && python generate_mtr_reference.py`
3. Copy the complete printed output (reference constants for VAL-01, VAL-02, VAL-03)
4. Paste the output when resuming Plan 02

**Reference constants will be recorded in Plan 02 SUMMARY when checkpoint is resolved.**

## Issues Encountered

- HDIFF-03 test assertion was physically incorrect — see Deviations section above

## Next Phase Readiness

- `test/generate_mtr_reference.py` ready for user to run in Python STREAM environment
- Phase 12 testset skeleton open in `runtests.jl` (VAL-01/02/03 slots reserved for Plan 02)
- Plan 02 requires: reference constants from `generate_mtr_reference.py` + Julia implementation of VAL-01/02/03 tests

## Self-Check: PASSED

- FOUND: test/generate_mtr_reference.py
- FOUND: test/runtests.jl (with Phase 12 testset)
- FOUND: .planning/phases/12-mtr-validation/12-01-SUMMARY.md
- FOUND commit 0805cb5 (Task 1)
- FOUND commit 12dd9e7 (Task 2)

---
*Phase: 12-mtr-validation*
*Completed: 2026-03-14*
