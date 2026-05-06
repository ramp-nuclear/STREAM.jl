---
phase: 13-physics-foundation
plan: "02"
subsystem: physics
tags: [julia, modelingtoolkit, pump, mtk, validation, heat-diffusion, pipe-geometry]

# Dependency graph
requires:
  - phase: 13-01
    provides: PipeGeometry_rectangular with correct Dh (2.495 mm) for MTR geometry

provides:
  - Pump dual-mode dispatch: Pump(dP_pump=X) or Pump(mdot0=X), error if both/neither
  - PHY-05 testsets: callable, mtkcompile, integration (sol[pump.port_in.mdot] ≈ 0.6), error cases
  - generate_mtr_reference.py updated to EffectivePipe.rectangular with correct Dh
  - VAL-01/02/03 reference constants regenerated for rectangular Dh ≈ 2.495 mm

affects:
  - future phases using Pump (PHY-05 pattern: mdot0 for forced-flow scenarios)
  - VAL-01/02/03 (now green with correct rectangular geometry)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Sentinel dispatch: dP_pump=nothing/mdot0=nothing kwargs in Pump constructor"
    - "Fixed-flow Pump: port_in.mdot ~ mdot0 constraint, no pressure equation (caller anchors P)"
    - "VAL-03 T_out: use energy balance not Python one_sided_connection (known Python issue)"

key-files:
  created:
    - .planning/phases/13-physics-foundation/13-02-SUMMARY.md
  modified:
    - src/components.jl
    - test/runtests.jl
    - test/generate_mtr_reference.py

key-decisions:
  - "Pump dual-mode via sentinel kwargs (dP_pump=nothing, mdot0=nothing): clean dispatch, single function"
  - "Fixed-flow Pump has NO pressure equation: caller must provide pressure anchor (e.g. pump.port_in.P ~ 1e5)"
  - "VAL-03 T_out assertion removed: Python one_sided_connection distributes heat to both faces (wrong); Julia correctly connects thermal_left only; energy balance is the truth"
  - "VAL-03 mdot assertion retained: Python hydraulics are correct (0.252547 kg/s, ~0.5% from Julia 0.2538)"
  - "Channel thermal port must be pinned (ch5.thermal.T ~ constant) in PHY-05 loop to avoid extra unknown"

patterns-established:
  - "Fixed-flow Pump pattern: Pump(mdot0=X) + P anchor equation + no pressure equation in pump"

requirements-completed:
  - PHY-05
---

# Phase 13 Plan 02: Physics Foundation — Pump mdot0 and VAL Reference Regeneration Summary

**Pump dual-mode dispatch (dP_pump|mdot0) and MTR VAL-01/02/03 constants regenerated for correct rectangular Dh ≈ 2.495 mm**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-03-14T19:30:00Z
- **Completed:** 2026-03-14T19:55:00Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Pump extended with sentinel dispatch: `Pump(mdot0=0.6)` creates fixed-flow mode (4 eqs: mass balance, mdot constraint, 2 T streams; NO pressure equation); `Pump(dP_pump=1e5)` unchanged
- PHY-05 testsets added: callable check, mtkcompile, loop integration (sol[pump.port_in.mdot] ≈ 0.6 rtol=1e-4), error cases (both/neither args throw ErrorException)
- generate_mtr_reference.py updated: `EffectivePipe(...)` circular approximation replaced with `EffectivePipe.rectangular(length=0.6, edge1=0.07, edge2=0.00127, heated_edge=0.07)` giving Dh ≈ 2.495 mm
- VAL-01: T_out 315.1463→317.8871 K, mdot 0.5993→0.2525 kg/s; VAL-02: T_plate_center 344.36→347.61 K; VAL-03: mdot updated, T_out assertion removed (Python one_sided_connection gives physically wrong T_out)
- Full test suite: all tests pass (0 failures)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add Pump dual-mode and PHY-05 tests** - `c5c3b90` (feat)
2. **Task 2: Regenerate MTR reference constants and restore VAL tests** - `0a7853a` (fix)

## Files Created/Modified
- `/home/itay/projects/Julia-STREAM/src/components.jl` - Pump extended with dual-mode sentinel dispatch (dP_pump=nothing, mdot0=nothing)
- `/home/itay/projects/Julia-STREAM/test/runtests.jl` - PHY-05 testsets added after PHY-01; VAL-01/02/03 constants updated; mdot guesses updated from 0.600→0.250
- `/home/itay/projects/Julia-STREAM/test/generate_mtr_reference.py` - EffectivePipe.rectangular replaces old circular approximation; D_H constant removed

## Decisions Made
- **Fixed-flow Pump has no pressure equation**: Only 4 equations — mass balance, mdot constraint, and 2 T stream equations. Caller must anchor pressure via `pump.port_in.P ~ 1e5`. This matches Python STREAM's flow-forced pump pattern.
- **VAL-03 T_out assertion removed**: Python `one_sided_connection()` distributes 10 kW equally to both plate faces even when only one is connected, giving T_out ≈ 317.9 K (energy T_rise ≈ 4.75 K). Julia correctly connects only thermal_left, giving T_out ≈ 322.6 K (energy T_rise ≈ 9.4 K = 10 kW / (mdot*cp)). Energy balance confirms Julia is correct. This extends the STATE.md decision about VAL-03 T_plate_center.
- **Channel thermal port must be pinned in PHY-05 loop**: `Channel` has a `thermal` ThermalPort; when unconnected, `thermal.T` becomes an unknown (6 unknowns vs 5 equations). Added `ch5.thermal.T ~ 350.0` to the connections to pin it and restore system determinacy.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Channel thermal port creates extra unknown in PHY-05 integration test**
- **Found during:** Task 1 (PHY-05 integration test)
- **Issue:** `Channel` has a `thermal` ThermalPort. When unconnected, `thermal.T` becomes a free unknown (6 unknowns, 5 equations), causing `ArgumentError: Equations (5), unknowns (6)...`
- **Fix:** Added `ch5.thermal.T ~ 350.0` to the loop connections in the PHY-05 integration test
- **Files modified:** test/runtests.jl
- **Verification:** `unknowns(ssys5)` has 5 elements, `equations(ssys5)` = 5, solve succeeds
- **Committed in:** c5c3b90 (Task 1)

**2. [Rule 1 - Bug] VAL-03 T_out assertion fails: Python one_sided_connection gives wrong T_out**
- **Found during:** Task 2 (VAL-03 update)
- **Issue:** With new Dh, Python gives T_out = 317.887 K, but Julia gives 322.575 K. The plan says update Python reference and use it, but Python's `one_sided_connection` is known to be physically wrong for T_out (distributes heat to both faces). Julia energy balance confirms 322.575 K is correct.
- **Fix:** Removed T_out quantitative assertion from VAL-03. Kept energy balance assertion (T_out - T_in ≈ P/(mdot*cp)), mdot assertion (Python hydraulics are correct), and T_center > T_out qualitative check.
- **Files modified:** test/runtests.jl
- **Verification:** VAL-03 passes with energy balance as truth; mdot assertion passes at rtol=1%
- **Committed in:** 0a7853a (Task 2)

---

**Total deviations:** 2 auto-fixed (2 bugs)
**Impact on plan:** Both fixes necessary for correctness. No scope creep. VAL-03 fix is consistent with existing STATE.md decision about T_plate_center.

## Issues Encountered
- Python STREAM `stream` module cannot be imported from default conda env (missing `scikits.odes`). Used `stream-env` conda environment: `/home/itay/miniforge3/envs/stream-env/bin/python`.

## Self-Check

Files exist:
- [x] src/components.jl (modified, Pump dual-mode)
- [x] test/runtests.jl (modified, PHY-05 testsets + VAL constants)
- [x] test/generate_mtr_reference.py (modified, EffectivePipe.rectangular)

Commits exist:
- [x] c5c3b90 — feat(13-02): Pump dual-mode + PHY-05 tests
- [x] 0a7853a — fix(13-02): VAL constants regenerated

## Self-Check: PASSED

## Next Phase Readiness
- PHY-05 complete: Pump(mdot0=X) pattern available for future scenarios requiring forced flow
- All VAL-01/02/03 tests pass with correct rectangular Dh ≈ 2.495 mm
- Full test suite green (0 failures)
- Phase 13 complete — ready for Phase 14 (next v0.4 phase)

---
*Phase: 13-physics-foundation*
*Completed: 2026-03-14*
