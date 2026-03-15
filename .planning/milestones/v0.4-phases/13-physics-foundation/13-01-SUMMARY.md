---
phase: 13-physics-foundation
plan: 01
subsystem: physics
tags: [julia, PipeGeometry, hydraulic-diameter, wet-perimeter, MTR, rectangular-channel]

# Dependency graph
requires:
  - phase: 12-mtr-validation
    provides: existing PipeGeometry struct with sentinel-kwargs constructor and all VAL tests
provides:
  - PipeGeometry struct redesigned with 6 fields including wet_perimeter
  - PipeGeometry_rectangular factory function with one_sided support
  - PipeGeometry_circular factory function
  - PHY-01 unit testsets (12 assertions)
  - All ~20 call sites in tests and solvers migrated to factory functions
affects: [13-02-physics-foundation, VAL-01, VAL-02, VAL-03 reference constants]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Factory function constructors (PipeGeometry_rectangular, PipeGeometry_circular) instead of sentinel-kwargs dispatch"
    - "Dh derived from wet_perimeter: Dh = 4*area/wet_perimeter"

key-files:
  created: []
  modified:
    - src/components.jl
    - src/STREAM.jl
    - src/solvers.jl
    - test/runtests.jl

key-decisions:
  - "PipeGeometry_rectangular uses edge1=plate_width, edge2=channel_gap — Dh=4*A/wet_perimeter gives ~2.5 mm for MTR (was wrongly 10 mm)"
  - "PipeGeometry_circular stores Dh=D (exact for circular), wet_perimeter=pi*D, heated_parts=(pi*D/2, pi*D/2)"
  - "Old sentinel-kwargs constructor deleted with no backward-compat shim — MethodError on old calls is correct behavior"
  - "VAL-01/02/03 quantitative assertions fail after this plan as expected — Plan 02 regenerates reference constants"

patterns-established:
  - "PipeGeometry construction: always use PipeGeometry_rectangular or PipeGeometry_circular, never inner positional constructor"

requirements-completed: [PHY-01]

# Metrics
duration: 11min
completed: 2026-03-14
---

# Phase 13 Plan 01: Physics Foundation — PipeGeometry Redesign Summary

**6-field PipeGeometry struct with Dh=4*area/wet_perimeter, factory constructors PipeGeometry_rectangular/PipeGeometry_circular, and ~20 call-site migration correcting MTR hydraulic diameter from 10 mm (wrong) to 2.5 mm (correct)**

## Performance

- **Duration:** 11 min
- **Started:** 2026-03-14T19:13:52Z
- **Completed:** 2026-03-14T19:24:52Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Redesigned PipeGeometry struct with 6 fields: L, Dh, A, heated_perimeter, wet_perimeter, heated_parts
- Added PipeGeometry_rectangular with two-sided / one_sided=:left / one_sided=:right support
- Added PipeGeometry_circular with exact Dh=D derivation and symmetric heated_parts split
- Migrated all ~20 call sites in tests and 3 call sites in solvers.jl to factory functions
- PHY-01 testsets (12 assertions) all pass; all non-VAL tests green
- VAL-01/02/03 quantitative assertions fail as expected (Dh 0.01→0.002495 m shifts Re/HTC)

## Task Commits

Each task was committed atomically:

1. **Task 1: Redesign PipeGeometry struct and add factory constructors** - `833ba94` (feat)
2. **Task 2: Migrate all existing PipeGeometry call sites in tests** - `3c99b98` (feat)

## Files Created/Modified

- `/home/itay/projects/Julia-STREAM/src/components.jl` — PipeGeometry 6-field struct, PipeGeometry_rectangular, PipeGeometry_circular; old sentinel-kwargs constructor removed
- `/home/itay/projects/Julia-STREAM/src/STREAM.jl` — Exported PipeGeometry_rectangular and PipeGeometry_circular
- `/home/itay/projects/Julia-STREAM/src/solvers.jl` — Migrated 3 PipeGeometry(L, D, A) calls to PipeGeometry_circular(L, D)
- `/home/itay/projects/Julia-STREAM/test/runtests.jl` — Added PHY-01 testsets; migrated all old PipeGeometry( call sites

## Decisions Made

- Dh for rectangular is always derived: `4*area/wet_perimeter`. The old `Dh=0.01` parameter was a 10 mm circular approximation for MTR channels that are actually ~2.5 mm rectangular slots.
- `PipeGeometry_circular` splits heated_parts symmetrically `(pi*D/2, pi*D/2)` matching Julia convention, not Python's `(pi*D, 0.0)`.
- No backward-compat shim for old constructor. MethodError is the correct failure mode to force migration.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Migrated PipeGeometry calls in src/solvers.jl**
- **Found during:** Task 2 (migrate test call sites)
- **Issue:** src/solvers.jl has 3 `PipeGeometry(L = L_ch, D = D_ch, A = A_ch)` calls in build_loop, build_loop_vertical, build_loop_transient — these caused SYS-01, SOLV-01, SOLV-02, VAL-01, VAL-02 to Error (not merely fail)
- **Fix:** Replaced all 3 occurrences with `PipeGeometry_circular(L_ch, D_ch)` using replace_all
- **Files modified:** src/solvers.jl
- **Verification:** SYS-01, SOLV-01, SOLV-02 pass after fix; only VAL quantitative assertions fail
- **Committed in:** 3c99b98 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Required for correctness — solvers.jl was in scope as a call site the plan's migration map missed.

## Issues Encountered

None beyond the auto-fixed solvers.jl call sites.

## Next Phase Readiness

- PipeGeometry struct is correct and stable — Plan 02 can regenerate VAL reference constants
- All non-VAL tests green; VAL failures are exactly the expected Dh-shift failures
- No blockers for Plan 02 (regenerate MTR reference constants with correct Dh)

---
*Phase: 13-physics-foundation*
*Completed: 2026-03-14*
