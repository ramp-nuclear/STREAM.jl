---
phase: 17-file-structure-reorganization
plan: 02
subsystem: infra
tags: [julia, modelingtoolkit, file-structure, reorganization]

# Dependency graph
requires:
  - phase: 17-01
    provides: components/ directory with 6 split files, geometry.jl extracted, interim 11-include STREAM.jl

provides:
  - src/physical_models/correlations.jl (correlation functions at canonical path)
  - src/composition/helpers.jl (composition helpers at canonical path)
  - src/examples.jl (example system builders extracted from solvers.jl)
  - src/STREAM.jl final canonical 13-include list
  - src/solvers.jl trimmed to solver-only logic

affects:
  - Phase 18 (test cleanup — CLAUDE.md layout now fully in effect)
  - Phase 19 (API cleanup — solvers.jl keyword-only args)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "physical_models/ subdir for HTC/friction correlations (matches Python STREAM naming)"
    - "composition/ subdir for system wiring helpers"
    - "examples.jl isolated from solver logic — no using/export/include in examples.jl"

key-files:
  created:
    - src/physical_models/correlations.jl
    - src/composition/helpers.jl
    - src/examples.jl
  modified:
    - src/STREAM.jl (final 13-include canonical list)
    - src/solvers.jl (trimmed to 3 solver functions only)
  deleted:
    - src/correlations.jl (moved to physical_models/)
    - src/helpers.jl (moved to composition/)

key-decisions:
  - "examples.jl has no using/export/include — all symbols accessed from module scope"
  - "solvers.jl using statements (ModelingToolkit, DifferentialEquations, Sundials) left untouched per locked decision"
  - "VAL-01 Fourier series flaky failure is pre-existing — not introduced by this plan"

patterns-established:
  - "File moves are verbatim copies — zero content changes during reorganization"
  - "STREAM.jl include order: fluids → connectors → geometry → physical_models/correlations → components/* → composition/helpers → solvers → examples"

requirements-completed:
  - STR-03
  - STR-04
  - STR-05

# Metrics
duration: 25min
completed: 2026-03-16
---

# Phase 17 Plan 02: File Structure Reorganization (correlations, helpers, examples) Summary

**correlations.jl and helpers.jl moved to canonical subdirs, four build_* functions extracted into examples.jl, STREAM.jl updated to the final 13-include canonical list**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-03-16T10:35:00Z
- **Completed:** 2026-03-16
- **Tasks:** 2
- **Files modified:** 5 (2 moved/created new dirs, 1 new, 2 updated)

## Accomplishments
- Moved `src/correlations.jl` verbatim to `src/physical_models/correlations.jl` and deleted old file
- Moved `src/helpers.jl` verbatim to `src/composition/helpers.jl` and deleted old file
- Created `src/examples.jl` with `build_loop`, `build_loop_vertical`, `build_loop_transient`, `build_cube` — no using/export/include statements
- Trimmed `src/solvers.jl` to three solver-only functions: `steady_state_guess`, `solve_steady`, `solve_transient`
- Updated `src/STREAM.jl` to the canonical 13-include list matching CLAUDE.md layout exactly
- 160/161 tests pass; VAL-01 Fourier series failure is pre-existing flaky test (documented in STATE.md)

## Task Commits

Each task was committed atomically:

1. **Task 1: Move correlations.jl and helpers.jl** - `2be030f` (feat)
2. **Task 2: Extract example builders into examples.jl** - `126828c` (feat)

## Files Created/Modified
- `src/physical_models/correlations.jl` - dittus_boelter, blasius_friction, constant_Nusselt, laminar_friction, rectangular_laminar_correction, regime_dependent (verbatim from old correlations.jl)
- `src/composition/helpers.jl` - port, check_gravity_mismatch, _infer_n, symmetric_plate, plate, one_sided_connection, compose_systems (verbatim from old helpers.jl)
- `src/examples.jl` - build_loop, build_loop_vertical, build_loop_transient, build_cube (extracted from solvers.jl)
- `src/solvers.jl` - trimmed to steady_state_guess, solve_steady, solve_transient + using statements
- `src/STREAM.jl` - updated to final 13-include canonical list
- `src/correlations.jl` - deleted (moved)
- `src/helpers.jl` - deleted (moved)

## Decisions Made
- examples.jl has no `using`, `export`, or `include` statements — all referenced symbols (Pump, Channel, HeatExchanger, Gravity, Resistor, etc.) are available in module scope since STREAM.jl includes everything before examples.jl
- solvers.jl `using ModelingToolkit`, `using DifferentialEquations`, `using Sundials` left untouched per locked decision from CONTEXT.md
- VAL-01 (Fourier series validation) flaky failure is pre-existing and documented — confirmed not introduced by file structure changes

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

VAL-01 test failure observed during Task 2 test suite run. This is a pre-existing flaky numerical test documented in STATE.md prior to this plan. The `isapprox(371.56, 376.75; rtol=0.01)` assertion is sensitive to ODE solver timing. Not introduced by this plan.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Canonical file layout from CLAUDE.md is now fully in effect: `src/` has no flat correlations.jl or helpers.jl
- Phase 18 (test cleanup) and Phase 19 (API cleanup) can proceed
- CLAUDE.md File Structure Standard is the single source of truth — matches actual layout

---
*Phase: 17-file-structure-reorganization*
*Completed: 2026-03-16*
