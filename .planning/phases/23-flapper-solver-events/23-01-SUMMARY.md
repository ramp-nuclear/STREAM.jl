---
phase: 23-flapper-solver-events
plan: "01"
subsystem: components
tags: [modelingtoolkit, continuous-events, check-valve, flapper, flow-reversal]

# Dependency graph
requires:
  - phase: 22-time-varying-pump
    provides: "solve_transient with callbacks=nothing kwarg already implemented"
  - phase: 20-sign-safety
    provides: "Sign-safe channel components and FlowPort connectors"
provides:
  - Flapper check-valve component (src/components/flapper.jl)
  - Flapper exported from STREAM module
  - test/test_flapper.jl placeholder registered in runtests.jl
affects:
  - 23-02 (flapper tests)
  - Future LOF transient validation

# Tech tracking
tech-stack:
  added: ["ModelingToolkit.SymbolicContinuousCallback"]
  patterns:
    - "Differential state T_open with 1e30 sentinel for event-latch pattern"
    - "affect_neg=[T_open ~ t] for downward crossing (ref_mdot drops below threshold)"
    - "ref_mdot declared in vars with no equation — user wires externally during composition"

key-files:
  created:
    - src/components/flapper.jl
    - test/test_flapper.jl
  modified:
    - src/STREAM.jl
    - test/runtests.jl

key-decisions:
  - "T_open initial value is 1e30 (not Inf) — Inf causes Rodas5P instability; 1e30 sentinel keeps ramp at 0 before event fires"
  - "affect_neg fires on downward crossing (ref_mdot drops below threshold); affect=nothing ignores upward crossing"
  - "ref_mdot has no equation inside Flapper — user must wire flapper.ref_mdot ~ component.port_in.mdot during composition"
  - "clamp() works natively in MTK symbolic equations without @register_symbolic"

patterns-established:
  - "Event-latch pattern: differential state var + D(var)~0 + SymbolicContinuousCallback affect_neg sets var to t at crossing"
  - "Hermite cubic C1 ramp via 3*xi^2 - 2*xi^3 with xi=clamp((t-T_open)/dt, 0, 1)"

requirements-completed: [FLAP-01, FLAP-02, FLAP-03, FLAP-04, SOLV-01]

# Metrics
duration: 9min
completed: 2026-03-20
---

# Phase 23 Plan 01: Flapper Check-Valve Component Summary

**Flapper check-valve with MTK SymbolicContinuousCallback latch: T_open=1e30 sentinel, affect_neg fires on downward ref_mdot crossing, Hermite cubic C1 ramp from R_closed to R_open**

## Performance

- **Duration:** ~9 min
- **Started:** 2026-03-20T18:25:53Z
- **Completed:** 2026-03-20T18:34:13Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Implemented `Flapper(; name, dt, threshold, R_closed, R_open)` in `src/components/flapper.jl` with all required MTK patterns
- Wired Flapper into `src/STREAM.jl` (include + export) and `test/runtests.jl` (placeholder test file)
- Verified `mtkcompile(f; fully_determined=false)` succeeds and full test suite (all prior tests) still green

## Task Commits

1. **Task 1: Create Flapper component** - `25d81c9` (feat)
2. **Task 2: Wire Flapper into STREAM module and test runner** - `f3ed9a2` (feat)

## Files Created/Modified

- `src/components/flapper.jl` — Flapper check-valve component with SymbolicContinuousCallback, T_open latch, Hermite ramp
- `src/STREAM.jl` — Added `include("components/flapper.jl")` and `Flapper` to export line
- `test/runtests.jl` — Added `include("test_flapper.jl")`
- `test/test_flapper.jl` — Placeholder (full tests in Plan 23-02)

## Decisions Made

- **T_open = 1e30 not Inf:** Live testing confirmed Rodas5P fails with Inf in state vector (retcode=Unstable). 1e30 sentinel gives `clamp((t-1e30)/dt, 0, 1) = 0` for all practical t, keeping valve closed before event fires. Overrides D-01 from CONTEXT.md per RESEARCH.md recommendation.
- **affect_neg for downward crossing:** `ref_mdot - threshold` is positive when ref_mdot > threshold. When ref_mdot drops below threshold, condition goes positive-to-negative = downward crossing = `affect_neg`. Using `affect = nothing` correctly ignores the upward crossing (pump restart).
- **ref_mdot with no equation:** MTK will require exactly one equation for ref_mdot at mtkcompile time; the component is correct but under-determined standalone. Use `fully_determined=false` for standalone compile checks; composed systems must include `flapper.ref_mdot ~ ...`.
- **clamp() native in MTK:** No @register_symbolic wrapper needed; MTK handles clamp symbolically.

## Deviations from Plan

None — plan executed exactly as written. All patterns from RESEARCH.md applied correctly on first attempt.

## Issues Encountered

None.

## Known Stubs

- `test/test_flapper.jl` is a placeholder with a comment only. Full tests (FLAP-05, FLAP-06, SOLV-01) are deferred to Plan 23-02. This is intentional per the two-plan split design (D-10 in RESEARCH.md).

## Next Phase Readiness

- Flapper component is fully implemented and exportable — Plan 23-02 can write tests immediately
- `mtkcompile(flapper; fully_determined=false)` confirmed working
- Full test suite green with no regressions
- `solve_transient` with `callbacks` kwarg pre-wired in solvers.jl — SOLV-01 test just needs to call it

## Self-Check: PASSED

All created files found. All task commits verified.

---
*Phase: 23-flapper-solver-events*
*Completed: 2026-03-20*
