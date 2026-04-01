---
phase: 28-subcooled-boiling
plan: 01
subsystem: physical_models
tags: [subcooled-boiling, mcadams, bergles-rohsenow, correlations, ifelse]

# Dependency graph
requires:
  - phase: 14-laminar-correlations
    provides: "regime_dependent factory pattern, _bergles_rohsenow_dT_ONB formula"
provides:
  - "McAdams_SCB_heat_flux: standalone subcooled boiling heat flux (McAdams 1949)"
  - "Bergles_Rohsenow_SCB_heat_flux: pressure-dependent SCB heat flux (Bergles-Rohsenow 1964)"
  - "partial_SCB_correction: Bergles-Rohsenow partial boiling superposition factor"
  - "regime_dependent_q_scb: factory returning Re-dependent SCB closure for ChannelAndContacts"
affects: [28-02-PLAN, thermal_channel, ChannelAndContacts]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "max(dT, 0.0) safe exponentiation for ifelse() eager evaluation"
    - "SCB factory pattern matching regime_dependent in correlations.jl"

key-files:
  created:
    - src/physical_models/subcooled_boiling.jl
    - test/test_subcooled_boiling.jl
  modified:
    - src/STREAM.jl
    - test/runtests.jl

key-decisions:
  - "Used max(dT, 0.0) to prevent DomainError in eager ifelse() branch evaluation"
  - "regime_dependent_q_scb is a factory (not direct function) to capture pressure at construction time"

patterns-established:
  - "Safe exponentiation: max(x, 0.0) when x^non-integer appears inside ifelse() guard"

requirements-completed: [SCB-01, SCB-02, SCB-03, SCB-04]

# Metrics
duration: 5min
completed: 2026-03-30
---

# Phase 28 Plan 01: Subcooled Boiling Correlations Summary

**Four standalone SCB correlation functions (McAdams, Bergles-Rohsenow, partial correction, regime-dependent factory) with 20 unit tests**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-30T20:33:12Z
- **Completed:** 2026-03-30T20:38:09Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Implemented McAdams (1949) subcooled boiling heat flux: q = 740*dT^3.86 W/m^2 with ifelse guard
- Implemented Bergles-Rohsenow (1964) SCB heat flux using 1082*p^1.156 coefficient family consistent with existing _bergles_rohsenow_dT_ONB
- Implemented partial_SCB_correction with division-by-zero and outside-boiling-regime guards
- Created regime_dependent_q_scb factory returning (T_wall, T_sat, Re) closure matching the regime_dependent pattern
- Added 20 unit tests covering all four functions including edge cases

## Task Commits

Each task was committed atomically:

1. **Task 1: Create subcooled_boiling.jl with SCB correlation functions** - `fd98893` (feat)
2. **Task 2: Create test_subcooled_boiling.jl with unit tests + DomainError fix** - `a50e643` (test)

## Files Created/Modified
- `src/physical_models/subcooled_boiling.jl` - Four SCB correlation functions (McAdams, Bergles-Rohsenow, partial_SCB_correction, regime_dependent_q_scb)
- `src/STREAM.jl` - Added include and export for subcooled_boiling functions
- `test/test_subcooled_boiling.jl` - 20 unit tests covering SCB-01..04
- `test/runtests.jl` - Added include for test_subcooled_boiling.jl

## Decisions Made
- Used `max(dT, 0.0)` to prevent DomainError when negative dT is raised to non-integer exponent 3.86 inside ifelse() (Julia evaluates both branches eagerly)
- `regime_dependent_q_scb` implemented as factory (not direct function per D-05) to capture pressure at construction time, matching D-06 scb_correction closure contract

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed DomainError in negative dT exponentiation**
- **Found during:** Task 2 (unit test execution)
- **Issue:** `ifelse(dT > 0, 740.0 * dT^3.86, 0.0)` raises DomainError when dT < 0 because Julia's `ifelse()` eagerly evaluates both branches, and `(-5.0)^3.86` requires complex arithmetic
- **Fix:** Changed to `dT_safe = max(dT, 0.0)` then `ifelse(dT > 0, 740.0 * dT_safe^3.86, 0.0)` for both McAdams and Bergles-Rohsenow functions
- **Files modified:** src/physical_models/subcooled_boiling.jl
- **Verification:** All 20 tests pass including negative dT cases
- **Committed in:** a50e643 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Essential fix for correctness. No scope creep.

## Issues Encountered
None beyond the DomainError fix documented above.

## Known Stubs
None - all four functions are fully implemented with correct formulas.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All four SCB correlation functions exported and tested
- Ready for Plan 02 (ISCB integration into ChannelAndContacts)
- `regime_dependent_q_scb` factory returns closures compatible with ChannelAndContacts `scb_correction` kwarg

---
*Phase: 28-subcooled-boiling*
*Completed: 2026-03-30*
