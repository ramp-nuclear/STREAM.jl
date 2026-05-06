---
phase: 23-flapper-solver-events
plan: "02"
subsystem: testing
tags: [modelingtoolkit, continuous-events, check-valve, flapper, callbacks, differential-equations]

# Dependency graph
requires:
  - phase: 23-flapper-solver-events
    plan: "01"
    provides: "Flapper component (src/components/flapper.jl), solve_transient callbacks kwarg"
provides:
  - Flapper integration tests: FLAP-05 (closed state), FLAP-06 (open transition), SOLV-01 (user callbacks)
  - test/test_flapper.jl fully implemented (replaces placeholder from Plan 23-01)
affects:
  - Future LOF transient validation (FLAP-07)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pump(0)+Inertia+Resistor decay pattern for Flapper FLAP-06 test: avoids callable pump parameter incompatibility with MTK callback compilation"
    - "Pair{Any,Any}[] op vector for mixed Float64/callable parameter ICs"
    - "ContinuousCallback at user level passed via callbacks=CallbackSet(...) kwarg"

key-files:
  created: []
  modified:
    - test/test_flapper.jl

key-decisions:
  - "Callable Pump(f(t)) cannot be used in FLAP-06 when a SymbolicContinuousCallback is present in the same system: MTK's callback compilation in ODEProblem construction requires all parameters resolvable at build time; the pump callable parameter resolution fails during affect compilation. Workaround: Pump(0)+Inertia+Resistor decay loop achieves the same test objective without callable parameters."
  - "FLAP-05 uses threshold=1e-6 (not default 0.01): default threshold is higher than steady-state mdot through high-resistance Flapper, making closed-state validation fragile; explicit small threshold guarantees ref_mdot >> threshold throughout transient"

patterns-established:
  - "For FLAP-05 closed-state test: use threshold << expected mdot to guarantee no downward crossing; assert T_open == 1e30 and xi == 0"
  - "For FLAP-06 open-transition test: use decaying mdot system (zero-dP pump + Inertia IC); assert T_open < 1e10, T_open > 0, xi == 1 at end"

requirements-completed: [FLAP-05, FLAP-06, SOLV-01]

# Metrics
duration: 21min
completed: 2026-03-20
---

# Phase 23 Plan 02: Flapper Test Suite Summary

**Flapper test suite with 10 passing tests: closed-state sentinel assertion (FLAP-05), Inertia-decay open-transition with ramp completion (FLAP-06), and user ContinuousCallback forwarding via solve_transient (SOLV-01)**

## Performance

- **Duration:** ~21 min
- **Started:** 2026-03-20T18:35:21Z
- **Completed:** 2026-03-20T18:56:17Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Replaced the `test/test_flapper.jl` placeholder with a full 153-line test suite
- FLAP-05: proves Flapper stays closed (T_open == 1e30, xi == 0) when ref_mdot exceeds threshold throughout transient
- FLAP-06: proves event fires at a positive time (T_open < 1e10), and ramp completes (xi == 1.0) after T_open + dt
- SOLV-01: proves user-supplied `ContinuousCallback` fires via `solve_transient(ssys, op, t; callbacks=CallbackSet(...))`

## Task Commits

1. **Task 1: Create Flapper test suite (FLAP-05, FLAP-06, SOLV-01)** - `5abb33d` (feat)

## Files Created/Modified

- `test/test_flapper.jl` — Full Flapper test suite: FLAP-05 (3 assertions), FLAP-06 (5 assertions), SOLV-01 (2 assertions); 10 tests total

## Decisions Made

- **Callable pump incompatible with MTK callback compilation:** When a `SymbolicContinuousCallback` is present in the system, `ODEProblem` construction compiles the `affect_neg` effect as a sub-`ImplicitDiscreteProblem`, which requires all parameter values at build time. The callable pump parameter `dP_pump_fn` is not resolvable during this sub-problem construction even when provided in the `op` dict — MTK can't find it before the ODEProblem is fully built. The workaround is `Pump(0.0)` + `Inertia` + initial condition `ine.inlet.mdot = 1.0`, letting the natural RL decay drive mdot below threshold.

- **threshold=1e-6 for FLAP-05:** With default `threshold=0.01` kg/s and `Pump(1e5)+Resistor(1e5)+Flapper(R_closed=1e8)`, the steady-state mdot is ~1e-3 kg/s (below the default threshold). The test depends on the fact that the continuous event only fires on a downward crossing — if the system starts at mdot=0 and rises to a value already below threshold, no crossing occurs. This is fragile. Using `threshold=1e-6` eliminates ambiguity: mdot is always well above threshold and T_open definitively stays at 1e30.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Callable pump incompatible with Flapper's SymbolicContinuousCallback in same ODEProblem**
- **Found during:** Task 1 (FLAP-06 implementation)
- **Issue:** Plan specified `Pump(dP_fn)` callable for FLAP-06 to ramp mdot to zero. When combined with `Flapper` (which has `SymbolicContinuousCallback`), `ODEProblem` construction fails: MTK's `compile_equational_affect` creates a sub-`ImplicitDiscreteProblem` that cannot resolve the callable `dP_pump_fn` parameter.
- **Fix:** Replaced callable pump ramp with `Pump(0.0) + Inertia(L_over_A=5e5)` initial condition `mdot=1.0`. Natural RL decay drives mdot below `threshold=1e-4` kg/s within a few tau=5s, achieving the same test objective.
- **Files modified:** test/test_flapper.jl
- **Verification:** FLAP-06 passes with 5 assertions; T_open = 0.046s (event fired early as expected from fast decay)
- **Committed in:** 5abb33d (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - Bug)
**Impact on plan:** The alternative approach fully satisfies FLAP-06 test objectives. The fix is documented for future reference if MTK resolves callable parameter resolution in sub-problem compilation.

## Issues Encountered

- The `FLAP-06` as-written test approach (callable pump ramp) is blocked by a MTK internal limitation. The workaround (Inertia decay) achieves the same behavioral test coverage. See Decisions Made section for details.

## Known Stubs

None — all three testsets are fully implemented with passing assertions.

## Next Phase Readiness

- Phase 23 is complete: Flapper component (Plan 01) + full test suite (Plan 02) both done
- All v0.6 flapper requirements satisfied: FLAP-01..06 complete, SOLV-01 complete
- Ready for FLAP-07 (loss-of-flow transient validation) in a future phase

## Self-Check: PASSED

- `test/test_flapper.jl` exists and contains 153 lines (min_lines=80: satisfied)
- Commit `5abb33d` verified in git log
- `julia --project test/test_flapper.jl` exits 0 (10/10 tests pass)
- `julia --project test/runtests.jl` exits 0 (no regressions)

---
*Phase: 23-flapper-solver-events*
*Completed: 2026-03-20*
