---
phase: 30-htc-friction-completions
plan: 02
subsystem: physical_models
tags: [correlations, htc, laminar, developing-flow, nusselt, combinator]

# Dependency graph
requires:
  - phase: 30-htc-friction-completions
    provides: "htc/correlations.jl with Marco_Han_Nusselt, split htc/friction subdirs"
provides:
  - "fully_developed_laminar_h_spl — 2-sided heating laminar Nu factory"
  - "developing_laminar_h_spl — thermally developing laminar Nu factory with x_star correction"
  - "maximal_htc — max-combinator for selecting dominant HTC mechanism"
  - "_two_sided_heating_nusselt — Kakac Table 44 case 3 private helper"
  - "_nusselt_coefficient_developing — Shah & London piecewise Nu private helper"
affects: [channel-components, physical-models, future-regime-dependent-extensions]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "HTC factory closures with precomputed geometry corrections"
    - "maximal_htc combinator pattern for multi-mechanism HTC selection"

key-files:
  created: []
  modified:
    - "src/physical_models/htc/correlations.jl"
    - "src/STREAM.jl"
    - "test/test_correlations.jl"

key-decisions:
  - "D-01 enforced: fully_developed_laminar_h_spl uses _two_sided_heating_nusselt, NOT Marco_Han_Nusselt"
  - "developing_laminar_h_spl precomputes correction factor at construction time for efficiency"

patterns-established:
  - "HTC combinator pattern: maximal_htc(corr1, corr2, ...) returns closure selecting max Nu"

requirements-completed: [HTC-02, HTC-03, HTC-04]

# Metrics
duration: 9min
completed: 2026-04-01
---

# Phase 30 Plan 02: HTC Factory Functions + Combinator Summary

**Laminar HTC factories (fully-developed and developing flow) with 2-sided heating Nusselt and max-combinator for multi-mechanism HTC selection**

## Performance

- **Duration:** 9 min
- **Started:** 2026-04-01T08:47:35Z
- **Completed:** 2026-04-01T08:56:29Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Added _two_sided_heating_nusselt (Kakac Table 44 case 3) and _nusselt_coefficient_developing (Shah & London) private helpers
- Implemented fully_developed_laminar_h_spl factory returning geometry-only laminar Nu closure (HTC-02)
- Implemented developing_laminar_h_spl factory with x_star aspect-ratio correction factor (HTC-03)
- Implemented maximal_htc combinator selecting maximum Nu across multiple correlations (HTC-04)
- All 15 new unit tests pass; 78 correlation tests total

## Task Commits

Each task was committed atomically:

1. **Task 1: Add HTC factory functions and private helpers to htc/correlations.jl** - `29c38b1` (feat)
2. **Task 2: Add unit tests for HTC-02, HTC-03, HTC-04** - `376035b` (test)

## Files Created/Modified
- `src/physical_models/htc/correlations.jl` - Added 5 functions: _two_sided_heating_nusselt, _nusselt_coefficient_developing, fully_developed_laminar_h_spl, developing_laminar_h_spl, maximal_htc
- `src/STREAM.jl` - Added 3 new exports: fully_developed_laminar_h_spl, developing_laminar_h_spl, maximal_htc
- `test/test_correlations.jl` - Added 15 tests across 3 new testsets (HTC-02, HTC-03, HTC-04)

## Decisions Made
- D-01 enforced: fully_developed_laminar_h_spl uses _two_sided_heating_nusselt (2-sided heating), NOT Marco_Han_Nusselt (4-sided heating), matching Python STREAM behavior for MTR fuel channels
- developing_laminar_h_spl precomputes the aspect-ratio correction factor `6 - 5*exp(-0.75*ar/0.3257)` at construction time rather than inside the closure

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- VAL-01 (Fourier series validation) is a pre-existing flaky numerical test failure, documented in STATE.md; not caused by this plan's changes

## User Setup Required
None - no external service configuration required.

## Known Stubs
None - all functions are fully implemented with validated reference values.

## Next Phase Readiness
- All 6 HTC/friction correlation requirements complete (HTC-01..04, FRIC-01..02)
- Correlation library ready for integration into channel components and regime_dependent extensions

---
*Phase: 30-htc-friction-completions*
*Completed: 2026-04-01*
