---
phase: 29-threshold-analysis
plan: 01
subsystem: physical_models
tags: [julia, threshold-analysis, nuclear-safety, CHF, ONB, OFI, OSV, QuadGK]

# Dependency graph
requires:
  - phase: 28-subcooled-boiling
    provides: _bergles_rohsenow_dT_ONB helper in correlations.jl; cp_water/k_water/rho_water fluid functions
  - phase: 27-pressure-field
    provides: sat_temperature @register_symbolic function

provides:
  - 8 plain-Julia nuclear safety threshold functions (THRS-01..08)
  - QuadGK dependency for cp integration in q_OFI_whittle_forgan
  - Unit test suite test_analysis.jl with 30 passing tests

affects: [29-02, 30-laminar-htc-friction]

# Tech tracking
tech-stack:
  added: [QuadGK "2.11.2"]
  patterns:
    - Plain Julia post-solve analysis functions (no @register_symbolic, no ifelse)
    - Private _SK sub-correlations for Sudo-Kaminaga CHF formula decomposition
    - quadgk(cp_water, T_inlet, T_sat) pattern for thermodynamic integrals

key-files:
  created:
    - src/physical_models/threshold_analysis.jl
    - test/test_analysis.jl
  modified:
    - src/STREAM.jl
    - test/runtests.jl
    - Project.toml
    - Manifest.toml

key-decisions:
  - "threshold_analysis.jl uses no @register_symbolic or ifelse() — post-solve only (D-01)"
  - "QuadGK added as direct dependency for OFI cp integration (transitive dep promoted to explicit)"
  - "q_OSV_saha_zuber returns minimum over cells (most conservative onset value)"
  - "q_CHF_sudo_kaminaga scalar T_bulk matches Python STREAM single-cell evaluation"

patterns-established:
  - "Post-solve physics: plain Julia arithmetic, no MTK, no ifelse, direct float operations"
  - "Private helper prefix _SK for Sudo-Kaminaga sub-correlations"

requirements-completed: [THRS-01, THRS-02, THRS-03, THRS-04, THRS-05, THRS-06, THRS-07, THRS-08]

# Metrics
duration: 30min
completed: 2026-03-31
---

# Phase 29 Plan 01: Threshold Analysis Summary

**8 nuclear safety threshold functions (ONB, OFI, OSV, CHF×3, boiling power, twall_limit) as plain Julia arithmetic matching Python STREAM exactly, with 30 unit tests.**

## Performance

- **Duration:** 30 min
- **Started:** 2026-03-31T19:18:45Z
- **Completed:** 2026-03-31T19:48:49Z
- **Tasks:** 2 (executed as 1 combined TDD cycle)
- **Files modified:** 6

## Accomplishments
- All 8 threshold physics functions implemented in `src/physical_models/threshold_analysis.jl`
- Functions wired into STREAM module (include + 8 exports)
- QuadGK added as direct dependency for Whittle-Forgan OFI cp integration
- 30 unit tests passing in `test/test_analysis.jl` covering all THRS-01..08 requirements

## Task Commits

Each task was committed atomically:

1. **Task 1+2: Implement all 8 physics functions + unit tests** - `bd16bba` (feat)

**Plan metadata:** (docs commit follows)

_Note: Tasks 1 and 2 merged into a single TDD cycle — test file was written in RED phase of Task 1, then implementation in GREEN phase, resulting in one atomic commit covering both tasks._

## Files Created/Modified
- `src/physical_models/threshold_analysis.jl` — 8 threshold physics functions + 4 private _SK helpers
- `test/test_analysis.jl` — 30 unit tests for THRS-01..08 with shared PipeGeometry fixture
- `src/STREAM.jl` — Added include + export for all 8 functions
- `test/runtests.jl` — Added `include("test_analysis.jl")`
- `Project.toml` — Added QuadGK direct dependency
- `Manifest.toml` — Updated with QuadGK

## Decisions Made
- **No @register_symbolic / no ifelse**: All threshold functions are post-solve arithmetic, not MTK equations. Plain Julia if/else and standard math is correct here.
- **QuadGK promoted to direct dependency**: Was already a transitive dependency in Manifest; added explicitly to Project.toml for clarity and stability.
- **q_OSV returns minimum over cells**: The most conservative (first) onset cell is the safety limit.
- **q_CHF_sudo_kaminaga uses scalar T_bulk**: Python STREAM evaluates at T_bulk[0] (inlet); Julia matches this with a single scalar value.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] QuadGK promoted to direct Project.toml dependency**
- **Found during:** Task 1 (q_OFI_whittle_forgan implementation)
- **Issue:** `using QuadGK` inside threshold_analysis.jl requires QuadGK to be a direct dependency; it was only a transitive dep before
- **Fix:** Ran `julia -e 'import Pkg; Pkg.add("QuadGK")'` which added it to Project.toml and Manifest.toml
- **Files modified:** Project.toml, Manifest.toml
- **Verification:** `using QuadGK; quadgk(x->x, 0.0, 1.0)` returns 0.5
- **Committed in:** bd16bba (part of Task 1 commit)

---

**Total deviations:** 1 auto-fixed (blocking dependency)
**Impact on plan:** Required for OFI cp integration; no scope creep.

## Issues Encountered
None — all functions implemented cleanly on first attempt with all 30 tests passing.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All 8 THRS-01..08 functions available from `using STREAM`
- Ready for Phase 29 Plan 02: threshold_analysis post-processor (if applicable) or Phase 30
- Stub check: no stubs — all functions return meaningful computed values

---
*Phase: 29-threshold-analysis*
*Completed: 2026-03-31*
