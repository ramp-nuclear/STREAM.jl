---
phase: 48-scram-solver-integration
plan: 01
subsystem: callback-factories
tags: [scram, flapper, callback, refactor, point-kinetics]
dependency_graph:
  requires: [point_kinetics.jl, flapper.jl, solvers.jl]
  provides: [SCRAMCondition, SCRAM_at_power, scram_callback, flapper_callback]
  affects: [examples.jl, test_flapper.jl, test_loss_of_flow.jl, test_point_kinetics.jl]
tech_stack:
  added: []
  patterns: [unified callback factory pattern, ContinuousCallback external wiring]
key_files:
  created: []
  modified:
    - src/components/point_kinetics.jl
    - src/components/flapper.jl
    - src/STREAM.jl
    - src/examples.jl
    - test/test_flapper.jl
    - test/test_loss_of_flow.jl
    - test/test_point_kinetics.jl
decisions:
  - "Unified callback factory pattern: all event-driven components expose _callback() factory returning external ContinuousCallback"
  - "SCRAMCondition is a struct (not bare closure) so scram_callback can read power_limit from ctrl.state_machine"
  - "scram_callback takes p_sym::Num as first arg (not ssys) for namespace flexibility (standalone vs nested PK)"
  - "flapper_callback uses symbolic indexing (integrator[sym]) for ref_mdot (may be algebraic after mtkcompile)"
  - "Removed threshold from build_loop_lof_bypass signature — threshold is now a callback concern"
metrics:
  duration_seconds: 356
  completed: "2026-04-08T13:50:29Z"
---

# Phase 48 Plan 01: Unified Callback Factory Pattern Summary

**One-liner:** SCRAMCondition struct + scram_callback/flapper_callback factories establishing a single external ContinuousCallback pattern for all event-driven STREAM.jl components.

## What Was Done

### Task 1: SCRAMCondition and scram_callback (58bbd10)
- Added `SCRAMCondition` struct with `power_limit::Float64` field
- Added `SCRAM_at_power(power_limit)` constructor with Float64 coercion
- Added callable protocol `(s::SCRAMCondition)(state, t, P, dPdt)` matching ReactivityController state_machine contract
- Added `scram_callback(ssys, p_sym::Num, ctrl; terminate=true)` factory returning ContinuousCallback
- Exported SCRAMCondition, SCRAM_at_power, scram_callback, flapper_callback from STREAM.jl

### Task 2: Flapper refactor + flapper_callback (cee689a)
- Removed `SymbolicContinuousCallback` import from flapper.jl
- Removed `use_callback` and `threshold` kwargs from Flapper constructor
- Removed `threshold` from `@parameters` block
- Flapper is now a pure equation system (no internal events)
- Added `flapper_callback(ssys, monitored_sym; threshold=0.01)` factory returning ContinuousCallback
- Updated `build_loop_lof_bypass` in examples.jl to use simplified Flapper constructor
- Removed `threshold` kwarg from `build_loop_lof_bypass` signature

### Task 3: Test updates (a5cfe09)
- FLAP-05: uses `flapper_callback(ssys; threshold=1e-6)` via callbacks kwarg
- FLAP-06: uses `flapper_callback(ssys; threshold=threshold_val)` via callbacks kwarg
- SOLV-01: updated to use simplified `_build_flapper_scalar_loop` (no flap_kwargs)
- LOF-02: replaced manual `variable_index` + `ContinuousCallback` with `flapper_callback(ssys; threshold=BYPASS_THRESHOLD)`
- SCRAM-01: 8 assertions on SCRAMCondition struct, callable semantics, boundary behavior
- SCRAM-02: standalone PK solver termination test (step reactivity, SCRAM fires, ctrl.state transitions)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Removed threshold from build_loop_lof_bypass signature**
- **Found during:** Task 2
- **Issue:** After removing `threshold` from Flapper constructor, `build_loop_lof_bypass` accepted but no longer used `threshold` kwarg
- **Fix:** Removed `threshold` from function signature; it is now a `flapper_callback` concern
- **Files modified:** src/examples.jl
- **Commit:** cee689a (included in Task 2 commit), a5cfe09 (test side)

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| Unified callback factory pattern | All event-driven components expose `_callback()` factories returning external ContinuousCallback -- no hidden magic inside components |
| SCRAMCondition as struct | Allows scram_callback to read power_limit from ctrl.state_machine -- single source of truth |
| ssys first arg + p_sym::Num second arg for scram_callback | ssys provides namespace context; p_sym::Num identifies the specific power variable (ssys.pk.P for nested PK). Post-Phase-48 fixup (commit 98a64ac). |
| flapper_callback uses integrator[sym] | ref_mdot may be algebraic (substituted away by mtkcompile); symbolic indexing follows substitution chains correctly |
| Removed threshold from build_loop_lof_bypass | Threshold is a callback concern, not a topology concern |

## Self-Check: PASSED
