---
phase: 02-components
plan: "03"
subsystem: components
tags: [modelingtoolkit, mtk, pump, friction, gravity, darcy-weisbach, blasius, hydrostatic, julia]

# Dependency graph
requires:
  - phase: 02-components/02-01
    provides: FlowPort connector, component stubs with error guards, test scaffold
  - phase: 02-components/02-02
    provides: Channel implementation, fully_determined=false pattern for isolation tests

provides:
  - Pump: constant pressure rise component (no local state variables)
  - Friction: Darcy-Weisbach pressure drop with Blasius friction factor (Re, f as observed vars)
  - Gravity: hydrostatic pressure component (rho * g * H)
  - COMP-02/03/04 test assertions active and passing

affects:
  - phase: 03-integration

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Algebraic-only MTK components pass [] as vars argument to System() when no local state"
    - "mtkcompile(comp; fully_determined=false) for all isolated component tests with unconnected ports"
    - "instream(inlet.T) bound to local T_in variable before use in equations for clarity"
    - "Re and f declared as @variables (not parameters) so they appear in observed() after mtkcompile"

key-files:
  created: []
  modified:
    - src/components.jl
    - test/runtests.jl

key-decisions:
  - "Use [] (empty vector) as vars argument for Pump and Gravity (no local state, purely algebraic via port variables)"
  - "A_grav parameter kept in Gravity for API consistency even though unused in current pressure equation"
  - "D and L kwargs in Friction equations reference the Julia local keyword args directly (not the renamed pars), consistent with the plan"

patterns-established:
  - "TDD flow for MTK: write real @test_nowarn tests first (they fail against error stubs = RED), then implement (GREEN)"
  - "All isolation tests use fully_determined=false to avoid ExtraVariablesSystemException on unconnected ports"

requirements-completed: [COMP-02, COMP-03, COMP-04]

# Metrics
duration: 3min
completed: "2026-03-12"
---

# Phase 2 Plan 03: Pump, Friction, Gravity Implementation Summary

**Pure-algebraic Pump, Friction (Darcy-Weisbach + Blasius), and Gravity (hydrostatic) components implemented in MTK with Re/f as observable variables; full Phase 2 test suite green (34/34)**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-03-12T01:27:11Z
- **Completed:** 2026-03-12T01:30:03Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Pump component: constant pressure rise (dP_pump), mass continuity, isenthalpic temperature — no local state variables
- Friction component: Darcy-Weisbach pressure drop with Blasius correlation (0.3164 * Re^-0.25), Re and f as MTK observed variables
- Gravity component: hydrostatic pressure drop (rho_water * 9.80665 * H), A_grav parameter retained for future velocity observable
- COMP-02/03/04 testsets activated with real assertions (instantiation + mtkcompile); all 9 Phase 2 tests passing

## Task Commits

Each task was committed atomically:

1. **TDD RED: Failing tests for Pump/Friction/Gravity** - `8018232` (test)
2. **Task 1: Implement Pump, Friction, Gravity** - `acbf03b` (feat)
3. **Task 2: Activate COMP-02/03/04 tests** - `a31b981` (feat)

_Note: TDD task has two commits (test RED then feat GREEN)_

## Files Created/Modified
- `src/components.jl` - Replaced three error stubs with full Pump, Friction, Gravity implementations
- `test/runtests.jl` - COMP-02/03/04 testsets replaced from @test_throws to real System assertions

## Decisions Made
- `[]` passed as vars argument to `System()` for Pump and Gravity (no local observables beyond port variables needed)
- `A_grav` parameter kept in Gravity for API consistency (parallel to Friction's A_f) even though it is unused in the current pressure equation — future velocity observable will use it
- Friction equations reference the original Julia keyword args `D` and `L` directly in equations (not renamed pars `D_h`, `L_f`) — this avoids shadowing but means the numeric values are captured at construction time, consistent with MTK symbolic parameter substitution

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added fully_determined=false to TDD test script**
- **Found during:** Task 1 GREEN phase verification
- **Issue:** mtkcompile on isolated components fails with ExtraVariablesSystemException (inlet.P unconstrained) — same issue as COMP-01 in PLAN 02
- **Fix:** Updated TDD test script to use `mtkcompile(comp; fully_determined=false)` for all three components
- **Files modified:** test/test_comp_tdd.jl (temporary, removed after task completion)
- **Verification:** All 6 TDD tests pass after fix
- **Committed in:** acbf03b (Task 1 commit, TDD test file included then removed before Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 2 - missing critical flag for unconnected port testing)
**Impact on plan:** Expected pattern from PLAN 02. The `fully_determined=false` approach is documented in STATE.md and is the correct MTK approach. No scope creep.

## Issues Encountered
- ExtraVariablesSystemException for isolated Pump/Friction/Gravity mtkcompile — resolved with `fully_determined=false` per established pattern from PLAN 02

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All four Phase 2 components implemented: Channel, Pump, Friction, Gravity
- All Phase 2 requirements satisfied: COMP-01, COMP-02, COMP-03, COMP-04
- Full test suite green: 34 tests, 0 failures
- Phase 3 (Integration/Validation): ready to assemble closed forced-convection loop using compose() + connect() + mtkcompile()

---
*Phase: 02-components*
*Completed: 2026-03-12*

## Self-Check: PASSED

- src/components.jl: FOUND
- test/runtests.jl: FOUND
- 02-03-SUMMARY.md: FOUND
- Commit 8018232 (TDD RED tests): FOUND
- Commit acbf03b (feat: implement components): FOUND
- Commit a31b981 (feat: activate tests): FOUND
