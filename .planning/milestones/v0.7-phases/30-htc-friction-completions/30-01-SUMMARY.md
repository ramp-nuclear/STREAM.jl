---
phase: 30-htc-friction-completions
plan: 01
subsystem: physical_models
tags: [correlations, htc, friction, colebrook-white, marco-han, nusselt]

# Dependency graph
requires:
  - phase: 14-laminar-correlations
    provides: "correlations.jl with regime_dependent, laminar_friction, etc."
provides:
  - "htc/correlations.jl — all HTC functions split into dedicated subdir"
  - "friction/correlations.jl — all friction functions split into dedicated subdir"
  - "Marco_Han_Nusselt — rectangular duct laminar Nu polynomial"
  - "turbulent_friction — Colebrook-White friction factor approximation"
  - "viscosity_correction — heated channel friction correction factor"
affects: [30-02-htc-friction-completions, channel-components, physical-models]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "physical_models split into htc/ and friction/ subdirectories per CLAUDE.md threshold"

key-files:
  created:
    - "src/physical_models/htc/correlations.jl"
    - "src/physical_models/friction/correlations.jl"
  modified:
    - "src/STREAM.jl"
    - "test/test_correlations.jl"

key-decisions:
  - "D-05: Split correlations.jl at ~270 lines into htc/ and friction/ per CLAUDE.md guidance"
  - "D-08: turbulent_friction Re<10 guard returns 0.0 to prevent DomainError in log10 for non-turbulent Re"

patterns-established:
  - "htc/ and friction/ subdirectory pattern for physical_models — future correlations go in appropriate subdir"

requirements-completed: [HTC-01, FRIC-01, FRIC-02]

# Metrics
duration: 13min
completed: 2026-04-01
---

# Phase 30 Plan 01: Correlation File Split + New Standalone Functions Summary

**Split correlations.jl into htc/ and friction/ subdirs; added Marco_Han_Nusselt, turbulent_friction (Colebrook-White), and viscosity_correction functions validated against Python STREAM**

## Performance

- **Duration:** 13 min
- **Started:** 2026-04-01T08:30:46Z
- **Completed:** 2026-04-01T08:44:01Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Split monolithic correlations.jl (~274 lines) into htc/correlations.jl and friction/correlations.jl
- Added Marco_Han_Nusselt polynomial for rectangular duct laminar Nu (HTC-01)
- Added turbulent_friction Colebrook-White approximation with low-Re guard (FRIC-01)
- Added viscosity_correction heated-channel friction factor (FRIC-02)
- All 15 new unit tests pass against Python STREAM reference values
- All existing tests remain green (63 correlation tests total)

## Task Commits

Each task was committed atomically:

1. **Task 1: Split correlations.jl into htc/ and friction/ and update STREAM.jl** - `18bdbbb` (feat)
2. **Task 2: Add unit tests for HTC-01, FRIC-01, FRIC-02** - `7e36471` (test)

## Files Created/Modified
- `src/physical_models/htc/correlations.jl` - All HTC functions: dittus_boelter, constant_Nusselt, regime_dependent, elenbaas_nusselt, elenbaas_htc, _bergles_rohsenow_dT_ONB, Marco_Han_Nusselt
- `src/physical_models/friction/correlations.jl` - All friction functions: blasius_friction, rectangular_laminar_correction, laminar_friction, turbulent_friction, viscosity_correction
- `src/STREAM.jl` - Updated includes (htc/ and friction/) and exports (3 new names)
- `test/test_correlations.jl` - Added 15 tests across 3 new testsets (HTC-01, FRIC-01, FRIC-02)

## Decisions Made
- Split threshold reached at ~274 lines per CLAUDE.md guidance ("split into htc/ and friction/ when file exceeds ~300 lines")
- turbulent_friction uses Re<10 guard (not just Re<=0) because Colebrook-White formula produces negative log10 arguments for very low Re, causing DomainError

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed turbulent_friction low-Re DomainError**
- **Found during:** Task 2 (unit tests)
- **Issue:** Plan specified `Re <= 0` guard, but `turbulent_friction(5.0)` triggers DomainError in log10 (negative argument)
- **Fix:** Extended guard to `Re < 10` — formula is only valid for turbulent Re anyway
- **Files modified:** src/physical_models/friction/correlations.jl
- **Verification:** turbulent_friction(5.0) == 0.0, turbulent_friction(4e3) matches reference
- **Committed in:** 7e36471 (Task 2 commit)

**2. [Rule 1 - Bug] Fixed incorrect monotonicity test for Marco_Han_Nusselt**
- **Found during:** Task 2 (unit tests)
- **Issue:** Plan assumed monotonic decrease from ar=0 to ar=1, but polynomial has minimum near ar=0.6 and rises at ar=1 (Nu=9.93)
- **Fix:** Changed test to only assert decrease from ar=0 to ar=0.5 (verified range)
- **Files modified:** test/test_correlations.jl
- **Verification:** All 4 HTC-01 tests pass
- **Committed in:** 7e36471 (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (2 bugs)
**Impact on plan:** Both fixes necessary for correctness. No scope creep.

## Issues Encountered
None beyond the deviations noted above.

## User Setup Required
None - no external service configuration required.

## Known Stubs
None - all functions are fully implemented with validated reference values.

## Next Phase Readiness
- htc/ and friction/ subdirectories established for 30-02 factory functions
- All existing correlation infrastructure intact for regime_dependent extensions

---
*Phase: 30-htc-friction-completions*
*Completed: 2026-04-01*
