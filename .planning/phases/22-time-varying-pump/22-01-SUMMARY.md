---
phase: 22-time-varying-pump
plan: 01
subsystem: components
tags: [modelingtoolkit, pump, callable-parameters, solve_transient, positional-dispatch]

# Dependency graph
requires:
  - phase: 21-fluid-properties
    provides: elenbaas_htc, fluid property functions already in place
provides:
  - "Three-method Pump dispatch: Pump(dP_pump::Real), Pump(dP_pump::Any callable), Pump(; mdot0)"
  - "MTK callable parameter pattern for time-varying pump pressure via @parameters (fn::FType)(..)"
  - "solve_transient(ssys, op, t; solver, callbacks, kwargs) positional API"
  - "build_loop_transient returns ssys only; accepts T_wall_fn callable kwarg"
affects: [22-02-tests, 23-flapper, 24-coastdown-validation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "MTK callable parameter: @parameters (fn::FType)(..) for user-supplied callables — alternative to @register_symbolic for lambdas"
    - "Positional dispatch on Pump: Real vs Any separates scalar from callable; keyword mdot0 stays keyword-only"
    - "solve_transient mirrors Python STREAM agr.solve(y0, time, ...) signature"

key-files:
  created: []
  modified:
    - src/components/pump.jl
    - src/solvers.jl
    - src/examples.jl

key-decisions:
  - "Pump(dP_pump::Any; name) uses @parameters (dP_pump_fn::FType)(..) — NOT @register_symbolic; caller passes ssys.pump.dP_pump_fn => f in op"
  - "solve_transient positional: ssys, op, t (time array); tspan derived as (t[1], t[end])"
  - "build_loop_transient: when T_wall_fn=nothing pins scalar T_wall_0; when callable wires ps[1](t) via @parameters (T_wall_callable::FType)(..)"
  - "All @named Pump() call sites in examples.jl updated to positional dispatch: @named pump = Pump(dP_pump)"
  - "Test files using old Pump(dP_pump=...) keyword syntax will break; Plan 02 fixes them"

patterns-established:
  - "Pattern: MTK callable parameter for any user-supplied f(t) -> Float64 in equations — use @parameters (fn::typeof(f))(..) and wire fn(t)"
  - "Pattern: positional dispatch Real vs Any for scalar vs callable disambiguation without Function restriction"

requirements-completed: [PUMP-01, PUMP-02]

# Metrics
duration: 7min
completed: 2026-03-18
---

# Phase 22 Plan 01: Time-Varying Pump API Summary

**Three-method Pump dispatch with MTK callable parameter pattern, positional solve_transient API, and callable T_wall support in build_loop_transient**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-17T23:50:02Z
- **Completed:** 2026-03-17T23:57:00Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Added `Pump(dP_pump::Any; name)` callable method using MTK `@parameters (dP_pump_fn::FType)(..)` pattern; caller passes `ssys.pump.dP_pump_fn => f` in `op`
- Replaced keyword-only `solve_transient(; ssys, T_wall_sym, op, tspan, T_wall_final, t_step)` with positional `solve_transient(ssys, op, t; solver, callbacks, kwargs)` mirroring Python STREAM API
- Rewrote `build_loop_transient` to return `ssys` only, accept `T_wall_fn` callable, and eliminate the `PresetTimeCallback`/`setp` mechanism

## Task Commits

1. **Task 1: Three-method Pump dispatch** - `65dfbfb` (feat)
2. **Task 2: Redesign solve_transient and build_loop_transient** - `20da50d` (feat)

## Files Created/Modified

- `/home/itay/projects/Julia-STREAM/src/components/pump.jl` - Replaced single keyword-only Pump with three dispatch methods; callable uses MTK `@parameters (fn::FType)(..)`
- `/home/itay/projects/Julia-STREAM/src/solvers.jl` - Rewrote `solve_transient` to positional API; removed T_wall_sym/PresetTimeCallback/setp
- `/home/itay/projects/Julia-STREAM/src/examples.jl` - Rewrote `build_loop_transient` (scalar/callable T_wall, returns ssys); updated all 4 `@named Pump(...)` call sites to positional syntax

## Decisions Made

- Used `@parameters (dP_pump_fn::FType)(..)` (MTK callable parameter) instead of `@register_symbolic` — the latter cannot be called inside function bodies and cannot register anonymous lambdas
- Named the callable parameter `dP_pump_fn` (not `dP_pump`) to avoid symbol collision with the scalar `@parameters dP_pump = dP_pump` in the Real method
- `solve_transient` accepts `t` as a time array (not a tspan tuple) with `saveat=t` for dense output mirroring Python STREAM
- `callbacks=nothing` pre-wired for Phase 23 Flapper `ContinuousCallback` support

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Updated all @named Pump() call sites in examples.jl to positional syntax**
- **Found during:** Task 2 (build_loop_transient verification)
- **Issue:** After removing the old `Pump(; name, dP_pump=nothing, mdot0=nothing)` keyword-only method, all existing call sites `@named pump = Pump(dP_pump = dP_pump)` dispatched to `Pump(; name, mdot0)` which has no `dP_pump` keyword — causing UndefKeywordError
- **Fix:** Changed all 4 `Pump(dP_pump = dP_pump)` call sites in `examples.jl` (build_loop, build_loop_vertical, build_loop_transient, build_cube) to positional `Pump(dP_pump)` with `@named` macro injecting the name
- **Files modified:** `src/examples.jl`
- **Verification:** `build_loop_transient()` and `build_loop_transient(T_wall_fn=t->373.15)` both compile and return system
- **Committed in:** `20da50d` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - Bug)
**Impact on plan:** Required fix — the call site update was implicit in the positional dispatch change. All test files using `Pump(dP_pump=X)` keyword syntax will also break; those are in scope for Plan 02.

## Issues Encountered

- Test files (`test_channel.jl`, `test_composition.jl`, `test_correlations.jl`, `test_validation.jl`, `test_solvers.jl`) still use `Pump(dP_pump=X)` keyword syntax and will fail. The plan notes SOLV-02 and VAL-02 breakage explicitly; the wider breakage is an expected consequence of the positional dispatch change. Plan 02 will fix all call sites.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Three Pump methods ready for PUMP-03 test integration (Plan 02)
- `solve_transient` positional API ready; Plan 02 will rewrite SOLV-02 and VAL-02 tests
- `build_loop_transient` callable T_wall ready for step-change tests in Plan 02
- `callbacks` kwarg pre-wired for Phase 23 Flapper support

## Self-Check: PASSED

- pump.jl: FOUND
- solvers.jl: FOUND
- examples.jl: FOUND
- SUMMARY.md: FOUND
- commit 65dfbfb: FOUND
- commit 20da50d: FOUND

---
*Phase: 22-time-varying-pump*
*Completed: 2026-03-18*
