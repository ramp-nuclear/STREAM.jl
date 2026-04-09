---
phase: 46-callable-control-reactivity-reactivity-controller
plan: 01
subsystem: neutronics
tags: [julia, mtk, point-kinetics, reactivity-controller, callable-parameter]

# Dependency graph
requires:
  - phase: 45-pointkinetics-bare-component-steady-state-ics
    provides: PointKinetics scalar constructor + point_kinetics_steady_state + U235 constants
provides:
  - PointKinetics(rho_c_fn::Any; name, rho_val, ...) callable-mode MTK constructor
  - ReactivityController{S,F} mutable struct with state machine, log, abort_states
  - worth(ctrl, t) primary callable output method
  - change_state(ctrl, t, power, dPdt) state transition method
  - ReactivityController callable via ctrl(t) = worth(ctrl, t)
  - src/STREAM.jl exports ReactivityController, worth, change_state
affects: [46-02, phase-47-temperature-feedback, phase-49-scram-callback]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "PointKinetics multiple dispatch: scalar(; name, rho=0.0) vs callable(rho_c_fn::Any; name, rho_val=0.0)"
    - "MTK callable parameter: FType=typeof(fn) + @parameters (fn::FType)(..) variadic"
    - "Additive reactivity composition: rho_val + rho_c_fn(t) - beta_sum"
    - "ReactivityController{S,F} callable struct: ctrl(t) = worth(ctrl, t)"
    - "State-aware reactivity signature: (state, t_state, t) -> Float64"

key-files:
  created:
    - src/components/point_kinetics.jl
  modified:
    - src/STREAM.jl

key-decisions:
  - "Additive rho composition (D-01): rho_val + rho_c_fn(t) extends cleanly to Phase 47 temperature feedback"
  - "Multiple dispatch on first arg type (D-02): PointKinetics(rho_c_fn::Any;...) vs PointKinetics(;...) matches Pump precedent"
  - "ReactivityController callable (D-09): ctrl(t) = worth(ctrl,t) allows passing ctrl directly as MTK FType"
  - "State-aware input signature (D-04): (state, t_state, t)->Float64 matches Python STREAM InputReactivity protocol"

patterns-established:
  - "Callable MTK parameter pattern: FType=typeof(fn) at construction; @parameters (fn::FType)(..); used in eqs as fn(t)"
  - "ReactivityController as MTK callable: concrete FType = typeof(ctrl) captured at PointKinetics construction time"

requirements-completed: [PK-03, RC-01]

# Metrics
duration: 15min
completed: 2026-04-04
---

# Phase 46 Plan 01: Callable Control Reactivity & ReactivityController Summary

**MTK callable-mode PointKinetics with additive rho composition + pure-Julia ReactivityController state-machine struct**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-04-04T16:10:00Z
- **Completed:** 2026-04-04T16:27:11Z
- **Tasks:** 3
- **Files modified:** 2

## Accomplishments
- `PointKinetics(rho_c_fn::Any; name, rho_val=0.0, ...)` callable-mode constructor using MTK `@parameters (rho_c_fn::FType)(..)` pattern; power ODE uses `rho_val + rho_c_fn(t) - beta_sum`; `mtkcompile` produces 7 unknowns
- `ReactivityController{S,F}` mutable struct with `input_reactivity`, `state_machine`, `state`, `t_state`, `log`, `abort_states` fields; default constructor with `:NORMAL` state; `worth`, `change_state` methods; callable `ctrl(t)` dispatch
- Phase 45 scalar `PointKinetics(; name, rho=0.0)` preserved unchanged; all Phase 45 exports retained; three new names exported from STREAM module

## Task Commits

Each task was committed atomically:

1. **Task 1: Add PointKinetics(rho_c_fn::Any;...) callable-mode constructor** - `711ace5` (feat)
2. **Task 2: Add ReactivityController struct, worth, change_state, callable method** - included in `711ace5` (same file write)
3. **Task 3: Export ReactivityController, worth, change_state from STREAM module** - included in `711ace5` (same file write)

## Files Created/Modified
- `src/components/point_kinetics.jl` - Phase 45 content + callable PointKinetics constructor + ReactivityController struct + worth/change_state/callable method
- `src/STREAM.jl` - Added point_kinetics.jl include + exports for PointKinetics, point_kinetics_steady_state, U235 constants, ReactivityController, worth, change_state; fixed physical_models include paths

## Decisions Made
- Wrote point_kinetics.jl from scratch incorporating Phase 45 content (file didn't exist in worktree branch) plus Phase 46 extensions
- Tasks 1/2/3 committed together since all content was written in a single file creation operation

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed STREAM.jl include path for physical_models correlations**
- **Found during:** Task 1 verification (using STREAM load test)
- **Issue:** STREAM.jl had `include("physical_models/correlations.jl")` but Phase 30 split correlations into `htc/correlations.jl` and `friction/correlations.jl` subdirectories. This was a pre-existing mismatch between main branch STREAM.jl and the physical_models directory structure.
- **Fix:** Replaced single include with `include("physical_models/htc/correlations.jl")` + `include("physical_models/friction/correlations.jl")`
- **Files modified:** src/STREAM.jl
- **Verification:** `using STREAM` loads without errors
- **Committed in:** 711ace5 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Required fix — package wouldn't load without it. No scope creep.

## Issues Encountered
- `point_kinetics.jl` did not exist in the worktree branch (Phase 45 was on a separate worktree that was never merged). Recreated the Phase 45 content from the Phase 45 commit and appended Phase 46 content.

## Known Stubs
None — no stub data or placeholder values in produced code.

## Threat Flags
None — no new network endpoints, auth paths, file access, or schema changes.

## Next Phase Readiness
- Plan 46-02 can proceed: `PointKinetics(ctrl; rho_val=0.0)` callable mode + `ReactivityController` are both ready
- Phase 47 (temperature feedback): `rho_val + rho_c_fn(t) + alpha_c*(T_c - T_c0)` extends naturally from additive D-01 composition
- Phase 49 (SCRAM callback): `abort_states` set and `change_state` method are in place; only SymbolicContinuousCallback wiring remains

---
*Phase: 46-callable-control-reactivity-reactivity-controller*
*Completed: 2026-04-04*
