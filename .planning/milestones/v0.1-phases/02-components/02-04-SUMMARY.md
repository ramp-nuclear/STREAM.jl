---
phase: 02-components
plan: "04"
subsystem: components
tags: [julia, modelingtoolkit, mtk, pump, gravity, api-consistency]

# Dependency graph
requires:
  - phase: 02-components/02-03
    provides: "Pump and Gravity implementations with inconsistent public kwargs (dP/A)"
provides:
  - "Pump public API: function Pump(; name, dP_pump) — kwarg matches MTK parameter name"
  - "Gravity public API: function Gravity(; name, H, A_grav) — kwarg matches MTK parameter name"
  - "All 34 tests green after kwarg rename"
affects: [03-integration]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Public constructor kwargs match internal MTK @parameters names exactly"
    - "dP_pump = dP_pump and A_grav = A_grav self-assignment pattern for clarity in @parameters block"

key-files:
  created: []
  modified:
    - src/components.jl
    - test/runtests.jl

key-decisions:
  - "Constructor kwargs renamed to match MTK parameter names (dP -> dP_pump, A -> A_grav) to eliminate UndefKeywordError in consumer code"

patterns-established:
  - "API consistency pattern: public kwarg name == internal MTK @parameters name to prevent ambiguity"

requirements-completed: [COMP-02, COMP-04]

# Metrics
duration: 3min
completed: 2026-03-12
---

# Phase 2 Plan 04: API Kwarg Rename (Pump/Gravity) Summary

**Renamed `Pump(; dP)` to `Pump(; dP_pump)` and `Gravity(; H, A)` to `Gravity(; H, A_grav)` in src/components.jl, closing UAT gaps COMP-02 and COMP-04; all 34 tests pass.**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-12T02:02:55Z
- **Completed:** 2026-03-12T02:05:10Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Renamed Pump constructor kwarg `dP` -> `dP_pump` so the public API matches the internal MTK parameter name
- Renamed Gravity constructor kwarg `A` -> `A_grav` so the public API matches the internal MTK parameter name
- Updated both call sites in `test/runtests.jl` to use the new kwarg names
- Confirmed all 34 tests pass (25 Phase 1 + 9 Phase 2) with 0 failures and 0 errors

## Task Commits

Each task was committed atomically:

1. **Task 1: Rename Pump and Gravity constructor kwargs** - `dbed1bc` (fix)
2. **Task 2: Update test constructor calls and run full suite** - `b287116` (fix)

**Plan metadata:** (pending docs commit)

## Files Created/Modified
- `src/components.jl` - Renamed constructor kwargs for Pump (dP -> dP_pump) and Gravity (A -> A_grav); self-assignment pattern in @parameters block
- `test/runtests.jl` - Updated Pump(dP_pump=1e4) and Gravity(H=3.0, A_grav=7.85e-5) call sites

## Decisions Made
None - followed plan as specified. The rename strategy (kwarg name = MTK parameter name) was already captured in STATE.md decisions.

## Deviations from Plan
None - plan executed exactly as written.

## Issues Encountered
None. The Task 1 verification command in the plan was missing `using ModelingToolkit` (needed for `equations()` function), but this was a minor adjustment to the test invocation only — the code change itself was correct and verified correctly.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All four components (Channel, Pump, Friction, Gravity) have consistent public APIs
- Pump: `Pump(; name, dP_pump)` — ready for Phase 3 assembly
- Gravity: `Gravity(; name, H, A_grav)` — ready for Phase 3 assembly
- UAT gaps COMP-02 and COMP-04 closed; Phase 3 integration can proceed without kwarg confusion
- No blockers

## Self-Check: PASSED

- FOUND: src/components.jl
- FOUND: test/runtests.jl
- FOUND: 02-04-SUMMARY.md
- FOUND commit: dbed1bc (Task 1)
- FOUND commit: b287116 (Task 2)

---
*Phase: 02-components*
*Completed: 2026-03-12*
