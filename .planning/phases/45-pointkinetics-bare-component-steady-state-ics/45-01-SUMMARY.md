---
phase: 45-pointkinetics-bare-component-steady-state-ics
plan: 01
subsystem: components
tags: [point-kinetics, neutronics, MTK, ODE, delayed-neutrons]

requires:
  - phase: none
    provides: standalone component (no dependencies on prior phases)
provides:
  - PointKinetics MTK component (7 ODEs: P + 6 precursor groups)
  - point_kinetics_steady_state analytical IC helper
  - U235 6-group nuclear data constants
affects: [46-callable-reactivity, 47-temperature-feedback, 48-coupling, 49-scram]

tech-stack:
  added: []
  patterns: [standalone-ODE-component-no-ports, scalar-MTK-parameters-from-vector-input]

key-files:
  created:
    - src/components/point_kinetics.jl
    - test/test_point_kinetics.jl
  modified:
    - src/STREAM.jl
    - test/runtests.jl

key-decisions:
  - "U235_LAMBDA_K values [55.72, 22.72, 6.22, 2.3, 0.618, 0.23] match Python STREAM test reference exactly"
  - "rho_val as MTK parameter name to avoid shadowing constructor kwarg rho"
  - "precursor_source local variable for DRY between eqs and obs (inlined by MTK symbolics)"

patterns-established:
  - "Standalone ODE component without ports: System(eqs, t, vars, pars; observed=obs, name=name) -- no compose() needed"
  - "Scalar MTK parameters from vector input: @parameters beta_1=beta_k[1] ... avoids array parameter pitfalls"

requirements-completed: [PK-01, PK-02]

duration: 5min
completed: 2026-04-04
---

# Phase 45 Plan 01: PointKinetics Bare Component & Steady-State ICs Summary

**6-group point kinetics MTK component (7 ODEs) with U-235 defaults and analytical steady-state IC helper validated against precursor-only decay analytical solution**

## Performance

- **Duration:** 5 min
- **Started:** 2026-04-04T14:20:17Z
- **Completed:** 2026-04-04T14:25:57Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- PointKinetics component with 7 state variables compiles with mtkcompile and exposes 3 @observed diagnostics
- point_kinetics_steady_state(P0) returns analytically correct C_k values (verified rtol=1e-12)
- Precursor-only decay transient matches analytical exponential solution within rtol=1e-3 over 100 seconds
- Zero ICs confirmed to produce trivial P=0 solution, proving IC helper is essential

## Task Commits

Each task was committed atomically:

1. **Task 1: Create PointKinetics component and steady-state IC helper** - `d0e0eef` (feat)
2. **Task 2: Create comprehensive tests for PK-01 and PK-02** - `6999145` (test)

## Files Created/Modified
- `src/components/point_kinetics.jl` - PointKinetics MTK component + point_kinetics_steady_state helper + U235 constants
- `src/STREAM.jl` - Added include and export lines for PointKinetics, fixed physical_models include paths
- `test/test_point_kinetics.jl` - 5 test sets: compile, IC formula, precursor decay, zero ICs, observables
- `test/runtests.jl` - Added include for test_point_kinetics.jl

## Decisions Made
- Used U235_LAMBDA_K = [55.72, 22.72, 6.22, 2.3, 0.618, 0.23] from Python STREAM test_point_kinetics.py (these are precursor decay constants in 1/s)
- Used U235_BETA_K = [0.000215, 0.001424, 0.001274, 0.002568, 0.000748, 0.000273] (Keepin 1965 standard U-235 thermal values, beta_total = 0.006502)
- Named MTK parameter `rho_val` (not `rho`) to avoid shadowing the constructor keyword argument
- Used local `precursor_source` variable for both the Dt(P) equation and the dPdt observed -- MTK inlines this symbolically

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed physical_models include paths in STREAM.jl**
- **Found during:** Task 1 (component wiring)
- **Issue:** STREAM.jl had `include("physical_models/correlations.jl")` but the file was split into `htc/correlations.jl` and `friction/correlations.jl` in v0.7 Phase 30
- **Fix:** Changed to `include("physical_models/htc/correlations.jl")` and `include("physical_models/friction/correlations.jl")`
- **Files modified:** src/STREAM.jl
- **Verification:** Package precompiles and loads successfully
- **Committed in:** d0e0eef (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Include path fix was necessary for the package to load. No scope creep.

## Issues Encountered
None beyond the include path fix documented above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- PointKinetics component ready for Phase 46 (callable reactivity rho(t))
- point_kinetics_steady_state ready for use in all coupled transient ICs
- U235 constants exported for downstream test validation

## Self-Check: PASSED

All artifacts verified:
- src/components/point_kinetics.jl: FOUND
- test/test_point_kinetics.jl: FOUND
- Commit d0e0eef: FOUND
- Commit 6999145: FOUND
- STREAM.jl include/export: FOUND
- runtests.jl include: FOUND

---
*Phase: 45-pointkinetics-bare-component-steady-state-ics*
*Completed: 2026-04-04*
