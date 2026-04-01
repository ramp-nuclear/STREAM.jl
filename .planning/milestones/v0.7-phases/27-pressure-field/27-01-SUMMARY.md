---
phase: 27-pressure-field
plan: 01
subsystem: fluids
tags: [sat_temperature, bergles-rohsenow, simantov, register_symbolic, pressure]

# Dependency graph
requires:
  - phase: 20-codebase-reorg
    provides: canonical file layout (fluids.jl, correlations.jl)
provides:
  - sat_temperature(P_Pa) @register_symbolic fluid function
  - _bergles_rohsenow_dT_ONB(P_Pa, q_spl) private ONB helper
affects: [27-02 pressure-field channel refactor, 28 subcooled-boiling]

# Tech tracking
tech-stack:
  added: []
  patterns: [pressure-dependent fluid property with abs() DomainError guard]

key-files:
  created: []
  modified:
    - src/fluids.jl
    - src/physical_models/correlations.jl
    - src/STREAM.jl
    - test/test_fluids.jl

key-decisions:
  - "sat_temperature uses @register_symbolic (same pattern as rho_water); _bergles_rohsenow_dT_ONB is plain arithmetic (same as dittus_boelter)"

patterns-established:
  - "Pressure-input fluid functions use abs() guard for DomainError safety at bad Newton iterates"

requirements-completed: [PRES-03]

# Metrics
duration: 6min
completed: 2026-03-28
---

# Phase 27 Plan 01: Fluid Prerequisites Summary

**sat_temperature(P_Pa) Simantov saturation correlation and _bergles_rohsenow_dT_ONB ONB helper for per-cell pressure observables**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-27T22:52:58Z
- **Completed:** 2026-03-27T22:59:27Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- sat_temperature(P_Pa) with @register_symbolic for MTK symbolic compatibility, validated at 4 pressure points against Python STREAM
- _bergles_rohsenow_dT_ONB(P_Pa, q_spl) private helper in correlations.jl, plain arithmetic for MTK tracing
- 8 new PRES-03 tests (4 spot-checks, 1 symbolic, 3 ONB) all passing

## Task Commits

Each task was committed atomically:

1. **Task 1: Add sat_temperature and _bergles_rohsenow_dT_ONB functions** - `fb8e237` (feat)
2. **Task 2: Unit tests for sat_temperature and _bergles_rohsenow_dT_ONB** - `69ac922` (test)

## Files Created/Modified
- `src/fluids.jl` - Added sat_temperature function with abs() guard + @register_symbolic
- `src/physical_models/correlations.jl` - Added _bergles_rohsenow_dT_ONB private helper
- `src/STREAM.jl` - Added sat_temperature to fluid export line
- `test/test_fluids.jl` - Added 3 PRES-03 test sets (8 assertions total)

## Decisions Made
- sat_temperature follows @register_symbolic pattern (opaque to MTK, same as rho_water) because it uses log() which MTK cannot trace
- _bergles_rohsenow_dT_ONB is plain arithmetic (no @register_symbolic) because MTK can trace power/division symbolically, same as dittus_boelter
- _bergles_rohsenow_dT_ONB kept private (underscore prefix, not exported) per plan D-13; Phase 29 will elevate to public export

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- sat_temperature and _bergles_rohsenow_dT_ONB ready for Plan 02 channel refactor
- Plan 02 will use sat_temperature for T_sat[i] observables and _bergles_rohsenow_dT_ONB for T_ONB[i]
- Pre-existing VAL-01 flaky test failure unrelated to this plan (documented in STATE.md)

---
## Self-Check: PASSED

All 4 files verified present. Both commit hashes (fb8e237, 69ac922) found in git log.

---
*Phase: 27-pressure-field*
*Completed: 2026-03-28*
