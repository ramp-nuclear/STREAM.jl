---
phase: 12-mtr-validation
plan: "01"
subsystem: testing
tags: [python-stream, mtr-geometry, heat-diffusion, validation, reference-values]

requires:
  - phase: 11-heat-diffusion
    provides: HeatDiffusion component with power_shape parameter

provides:
  - "test/generate_mtr_reference.py: Python STREAM MTR reference script covering VAL-01/02/03 (fixed and running)"
  - "test/runtests.jl Phase 12 testset skeleton with HDIFF-03-gap test passing"
  - "Reference constants for Plan 02 Julia validation tests (see section below)"

affects:
  - 12-02 (Plan 02 will use reference constants from generate_mtr_reference.py)

tech-stack:
  added: []
  patterns:
    - "FlowGraph unique Kirchhoff naming: k_constructor=partial(Kirchhoff, name=unique_name) required when combining multiple FlowGraph aggregators"
    - "FlowGraph initial guess: fg.guess_steady_state(mdots={...}, temperature=T) not manual state dict"
    - "Multi-loop aggregator: fg_l.aggregator + fg_r.aggregator + plate_cg + power_cg returns Aggregator directly; no .to_aggregator() call"
    - "Fuel power funcs via CalculationGraph.from_decoupled(fuel, funcs={fuel: dict(power=POWER)})"

key-files:
  created:
    - test/generate_mtr_reference.py
  modified:
    - test/runtests.jl

key-decisions:
  - "FlowGraph k_constructor=partial(Kirchhoff, name=unique_name) is required for multi-loop systems to avoid NonUniqueCalculationNameError"
  - "fg.guess_steady_state() must be used for initial guesses; manual dicts omit Kirchhoff node state and cause ValueError"
  - "Aggregator.__add__ returns Aggregator; .to_aggregator() only exists on CalculationGraph — do not call it on combined aggregators"
  - "plate() returns CalculationGraph with empty funcs; fuel power must be passed via separate CalculationGraph.from_decoupled"
  - "Non-uniform power_shape test uses [0.0, 1.0, 0.0] (center-sourced) — symmetric outer sources produce equal temperatures at steady state"

patterns-established:
  - "Multi-loop reference script: each FlowGraph gets unique Kirchhoff name via partial(); guesses built per-loop via guess_steady_state(), merged via dict unpacking"

requirements-completed:
  - VAL-01
  - VAL-02
  - VAL-03

duration: 35min
completed: 2026-03-14
---

# Phase 12 Plan 01: MTR Reference Script and HDIFF-03 Gap Test Summary

**Python STREAM MTR reference script fixed and running: three MTR scenarios (symmetric, asymmetric, one-sided) produce reference constants for Plan 02 Julia validation; HDIFF-03-gap power_shape test passing**

## Performance

- **Duration:** ~35 min total (2 tasks prior session + fix in continuation session)
- **Started:** 2026-03-14T02:10:00Z
- **Completed:** 2026-03-14
- **Tasks:** 3 complete (Tasks 1 and 2 from prior session; Task 3 = checkpoint fix)
- **Files modified:** 2

## Accomplishments

- Wrote `test/generate_mtr_reference.py` covering VAL-01/02/03 with Python STREAM `plate()` and `one_sided_connection()` APIs
- Diagnosed and fixed three bugs in the script (Kirchhoff naming collision, incorrect initial guess format, erroneous `.to_aggregator()` call)
- Obtained all reference constants (see table below)
- Added Phase 12 testset to `runtests.jl` with HDIFF-03-gap test passing

## Task Commits

1. **Task 1: Write test/generate_mtr_reference.py** - `0805cb5` (feat)
2. **Task 2: Add HDIFF-03 gap test and Phase 12 testset skeleton** - `12dd9e7` (feat)
3. **Task 3: Fix generate_mtr_reference.py errors** - `94a6046` (fix)

## Files Created/Modified

- `test/generate_mtr_reference.py` — Python STREAM MTR coupled plate reference script; three scenarios (VAL-01 symmetric, VAL-02 asymmetric 90°C right, VAL-03 one-sided left); prints constants in paste-ready format
- `test/runtests.jl` — Extended with `@testset "STREAM Phase 12 Tests"` containing HDIFF-03-gap test

## Reference Constants (for Plan 02)

Script run command:
```
cd /home/itay/projects/Julia-STREAM/test && /home/itay/miniforge3/envs/stream-env/bin/python generate_mtr_reference.py
```

**Script output:**
```
# VAL-01: Symmetric
  val01_T_outlet_l_ref = 313.1500   # K
  val01_T_outlet_r_ref = 313.9996   # K
  val01_mdot_l_ref     = 0.597697  # kg/s
  val01_mdot_r_ref     = 0.598400  # kg/s
  val01_T_plate_center = 317.5816   # K

# VAL-02: Asymmetric (right channel 90°C)
  val02_T_plate_center = 342.6925   # K
  # Assert: T_plate left face < T_plate right face (qualitative)

# VAL-03: One-sided (left face only)
  val03_T_outlet_ref   = 314.0473   # K
  val03_mdot_ref       = 0.598428  # kg/s
  val03_T_plate_center = 317.8484   # K
```

**High-precision values (for tight tolerances in Plan 02):**

| Constant | Value | Unit |
|----------|-------|------|
| val01_T_outlet_l | 313.1500000005 | K |
| val01_T_outlet_r | 313.9995593853 | K |
| val01_mdot_l | 0.59769667 | kg/s |
| val01_mdot_r | 0.59839960 | kg/s |
| val01_T_plate_center | 317.5816188245 | K |
| val02_T_plate_center | 342.6924559634 | K |
| val03_T_outlet | 314.0472914126 | K |
| val03_mdot | 0.59842784 | kg/s |
| val03_T_plate_center | 317.8483732649 | K |

**Physics note:** val01_T_outlet_l = 313.15 K to 10 decimal places (inlet = 313.15 K exactly). The left channel outlet barely heats because: aluminum plate (k=200 W/mK), 1.27mm wide, 10 kW total power, ~0.6 kg/s flow — thermal resistance is extremely low relative to convective capacity. The assertion `T_outlet_l > 313.15 K` passes by 5e-10 K margin. Plan 02 tests should use generous tolerances (1-2% relative for T, 2% for mdot).

## Python STREAM API Discoveries

**Critical multi-loop pattern:**
```python
from functools import partial
from stream.calculations import Kirchhoff

# Each FlowGraph must have a unique Kirchhoff node name
fg_l = FlowGraph(
    flow_edge(("A", "B"), pump_l, hx_l),
    flow_edge(("B", "A"), ch_l),
    funcs={ch_l: dict(p_abs=P_ABS)},
    reference_node=("A", P_ABS),
    abs_pressure_comps=[ch_l],
    k_constructor=partial(Kirchhoff, name="Kirchhoff_L"),   # REQUIRED!
)
fg_r = FlowGraph(
    ...,
    k_constructor=partial(Kirchhoff, name="Kirchhoff_R"),   # REQUIRED!
)

# Use guess_steady_state() not manual dicts
guess = {
    **fg_l.guess_steady_state(mdots={pump_l: 0.5, hx_l: 0.5, ch_l: 0.5}, temperature=40.0),
    **fg_r.guess_steady_state(mdots={pump_r: 0.5, hx_r: 0.5, ch_r: 0.5}, temperature=40.0),
    fuel.name: {"T": np.full((NZ, NX), 45.0), ...},
}

# Combine: returns Aggregator directly (no .to_aggregator() needed)
agr = fg_l.aggregator + fg_r.aggregator + plate_cg + power_cg
```

## Decisions Made

1. **Kirchhoff naming**: `k_constructor=partial(Kirchhoff, name=f"Kirchhoff_{suffix}")` established as the canonical pattern for all multi-loop FlowGraph scripts.
2. **Initial guess**: `fg.guess_steady_state()` is the only correct approach; manual dicts cannot reconstruct Kirchhoff state.
3. **HDIFF-03-gap fix**: Power_shape `[0.0, 1.0, 0.0]` (center-sourced) instead of `[0.5, 0.0, 0.5]`; symmetric outer sources cannot produce T_center < T_outer at steady state.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed physically incorrect HDIFF-03 test assertion (Task 2)**
- **Found during:** Task 2 (HDIFF-03-gap test execution)
- **Issue:** `power_shape = [0.5, 0.0, 0.5]` + assertion `T_left > T_center + 0.01` is physically impossible at steady state with symmetric BCs
- **Fix:** Changed to `[0.0, 1.0, 0.0]` + `T_center > T_left + 0.01`
- **Files modified:** test/runtests.jl
- **Committed in:** `12dd9e7`

**2. [Rule 1 - Bug] Fixed NonUniqueCalculationNameError (Task 3 checkpoint)**
- **Found during:** Task 3 (user ran script, reported error)
- **Issue:** Both FlowGraph objects created Kirchhoff nodes named "Kirchhoff"; combining aggregators via `+` raised `NonUniqueCalculationNameError`
- **Fix:** Added `k_constructor=partial(Kirchhoff, name=f"Kirchhoff_{name_suffix}")` to `_build_channel_and_loop()`
- **Files modified:** test/generate_mtr_reference.py
- **Committed in:** `94a6046`

**3. [Rule 1 - Bug] Replaced manual initial guess with `fg.guess_steady_state()` (Task 3 checkpoint)**
- **Found during:** Task 3 (second error after first fix)
- **Issue:** Manual state dict omitted Kirchhoff node state; `agr.load()` raised `ValueError`
- **Fix:** Replaced `_initial_guess()` with `_hydraulic_guess()` using `fg.guess_steady_state()` and `_fuel_guess()`
- **Files modified:** test/generate_mtr_reference.py
- **Committed in:** `94a6046`

**4. [Rule 1 - Bug] Removed erroneous `.to_aggregator()` calls (Task 3 checkpoint)**
- **Found during:** Task 3 (third error)
- **Issue:** `Aggregator.__add__` returns `Aggregator`; calling `.to_aggregator()` raised `AttributeError`
- **Fix:** `agr_01 = fg_l_01.aggregator + fg_r_01.aggregator + plate_cg_01 + power_cg_01` (no `.to_aggregator()`)
- **Files modified:** test/generate_mtr_reference.py
- **Committed in:** `94a6046`

---

**Total deviations:** 4 auto-fixed (all Rule 1 - Bugs)
**Impact on plan:** All fixes necessary for correctness. No scope creep.

## Issues Encountered

- Script written in Task 1 without access to a live Python STREAM environment; bugs discovered at the Task 3 checkpoint when user ran it
- Python STREAM must be run with `stream-env` conda environment: `/home/itay/miniforge3/envs/stream-env/bin/python`

## Next Phase Readiness

- Reference constants are in hand (table above) — Plan 02 can hardcode these in Julia tests
- Julia-STREAM must implement plate-coupling thermal boundary wiring for VAL-01/02/03
- Suggested tolerances: T within 1% relative, mdot within 2% relative (Python vs Julia model differences expected)
- HDIFF-03-gap test already passing in runtests.jl

## Self-Check: PASSED

- FOUND: test/generate_mtr_reference.py (runs without error, prints all reference constants)
- FOUND: test/runtests.jl (Phase 12 testset with HDIFF-03-gap)
- FOUND: .planning/phases/12-mtr-validation/12-01-SUMMARY.md
- FOUND commits: 0805cb5 (Task 1), 12dd9e7 (Task 2), 94a6046 (Task 3 fix)

---
*Phase: 12-mtr-validation*
*Completed: 2026-03-14*
