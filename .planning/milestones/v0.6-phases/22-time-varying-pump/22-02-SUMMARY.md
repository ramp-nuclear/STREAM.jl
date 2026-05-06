---
phase: 22-time-varying-pump
plan: 02
subsystem: testing
tags: [modelingtoolkit, pump, callable-parameters, solve_transient, analytical-validation, test-migration]

# Dependency graph
requires:
  - phase: 22-time-varying-pump plan 01
    provides: Three-method Pump dispatch, positional solve_transient API, callable build_loop_transient
provides:
  - "PUMP-01: callable Pump dispatch test (Pump(f) compiles via Any method)"
  - "PUMP-02: scalar Pump regression test (Pump(X) positional call, integration)"
  - "PUMP-03: mdot ramp analytical validation test (1% rtol at t=50s and t=100s)"
  - "SOLV-02: rewritten for new positional solve_transient API and callable T_wall"
  - "VAL-02 transient: rewritten using callable T_wall pattern"
  - "Full test suite migrated: all Pump(dP_pump=X) call sites -> Pump(X) positional"
affects: [23-flapper, 24-coastdown-validation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Analytical ODE solution for first-order forced response: undetermined coefficients for tau*x'+x=f(t) with linear f(t)"
    - "Two separate build_loop_transient calls for IC + transient: scalar for solve_steady, callable for solve_transient"
    - "Pair{Any,Any} op vector required when mixing Float64 state ICs with callable parameter values"
    - "last(parameters(ssys)) to retrieve callable parameter symbol from compiled system"

key-files:
  created: []
  modified:
    - test/test_pump.jl
    - test/test_solvers.jl
    - test/test_validation.jl
    - test/test_channel.jl
    - test/test_correlations.jl
    - test/test_composition.jl

key-decisions:
  - "Analytical formula corrected: plan spec had sign error; correct solution is (dP0/R)*(1 + tau/T_ramp - t/T_ramp - (tau/T_ramp)*exp(-t/tau))"
  - "Callable T_wall ICs: use scalar build_loop_transient for solve_steady, then callable for solve_transient — SteadyStateProblem cannot handle time-dependent callable params"
  - "Pair{Any,Any} op vector: Julia type inference specializes [sym => float64, ...] as Vector{Pair{Num,Float64}}; push!(callable_pair) fails; use explicit Pair{Any,Any}"
  - "Two thermal anchors in PUMP-03 loop (pump.inlet.T + ine.outlet.T): single anchor insufficient to resolve circular instream in pure hydraulics-only closed loop"
  - "last(parameters(ssys)) to access T_wall_callable param symbol: ssys.T_wall_callable returns CallAndWrap{Num}, not Num; use raw sym from parameters(ssys)"

patterns-established:
  - "Pattern: analytical ODE validation in tests — derive closed-form via undetermined coefficients; verify numerics match within 1% rtol at multiple time points"
  - "Pattern: two-system approach for transient with callable BCs — build scalar system for SS, build callable system for transient, transfer SS solution as IC"

requirements-completed: [PUMP-01, PUMP-02, PUMP-03]

# Metrics
duration: 32min
completed: 2026-03-18
---

# Phase 22 Plan 02: Time-Varying Pump Tests Summary

**PUMP-01/02/03 test suite with analytical ODE validation, SOLV-02/VAL-02 migrated to positional API, all Pump call sites updated to positional dispatch**

## Performance

- **Duration:** 32 min
- **Started:** 2026-03-18T00:02:04Z
- **Completed:** 2026-03-18T00:34:00Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- Added PUMP-01 (callable dispatch constructs and compiles), PUMP-02 (scalar regression integration), PUMP-03 (ramp test validates mdot decay against corrected analytical solution within 1% rtol)
- Rewrote SOLV-02 in test_solvers.jl for new positional `solve_transient(ssys, op, t)` API with callable T_wall step-change pattern
- Rewrote VAL-02 transient test in test_validation.jl using callable T_wall pattern
- Fixed all `Pump(dP_pump=X)` call sites in test_channel.jl, test_correlations.jl, test_composition.jl, test_validation.jl (23 sites) to positional `Pump(X)` syntax

## Task Commits

1. **Task 1: PUMP-01/02/03 tests in test_pump.jl** - `eb2d629` (test)
2. **Task 2: SOLV-02/VAL-02 rewrite + all Pump call site fixes** - `18190c0` (test)

## Files Created/Modified

- `/home/itay/projects/Julia-STREAM/test/test_pump.jl` - Added PUMP-01/02/03 testsets; replaced PHY-05 error cases with dispatch correctness tests
- `/home/itay/projects/Julia-STREAM/test/test_solvers.jl` - Rewrote SOLV-02: build_loop_transient returns ssys (not tuple); callable T_wall via two-system pattern
- `/home/itay/projects/Julia-STREAM/test/test_validation.jl` - Rewrote VAL-02 transient; fixed all other Pump call sites
- `/home/itay/projects/Julia-STREAM/test/test_channel.jl` - Fixed 5 Pump call sites
- `/home/itay/projects/Julia-STREAM/test/test_correlations.jl` - Fixed 4 Pump call sites
- `/home/itay/projects/Julia-STREAM/test/test_composition.jl` - Fixed 8 Pump call sites

## Decisions Made

- **Analytical formula corrected:** The plan spec provided an incorrect analytical solution for the PUMP-03 ODE. Using undetermined coefficients for `tau*x' + x = dP0/R*(1-t/T_ramp)`, the correct particular solution is `x_p = (dP0/R)*(1 + tau/T_ramp - t/T_ramp)`. The plan's formula `(1 - t/T_ramp - tau/T_ramp*(1-exp(-t/tau)))` was wrong — it would give `-0.05` but the correct answer is `+0.05` at T_ramp.

- **Two-system approach for callable T_wall ICs:** `SteadyStateProblem` cannot handle time-dependent callable parameters. The fix uses `build_loop_transient(T_wall_0=...)` for the steady-state solve (scalar wall temp), then `build_loop_transient(T_wall_fn=...)` for the transient. This is a clean pattern.

- **`Pair{Any,Any}` op vector:** Julia's type inference creates `Vector{Pair{Num,Float64}}` from `[sym => 1.0, ...]`. `push!(op, callable_sym => fn)` fails with type conversion error. Fix: explicitly type the vector as `Pair{Any,Any}[...]`.

- **Two thermal anchors in PUMP-03:** In a pure hydraulics-only closed loop (Pump + Inertia + Resistor with no HeatExchanger), the MTK `instream()` equations are degenerate. A single `pump.inlet.T ~ 313.15` leaves `ine.outlet.T` undetermined (1 unknown, 0 equations). Adding `ine.outlet.T ~ 313.15` gives exactly 1 unknown (mdot), 1 equation — correct ODE structure.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected analytical solution formula for PUMP-03**
- **Found during:** Task 1 (PUMP-03 test execution)
- **Issue:** The plan's formula `mdot(t) = (dP0/R)*(1 - t/T_ramp - tau/T_ramp*(1-exp(-t/tau)))` gave `-0.05` at t=T_ramp, but the ODE solver gave `+0.05`. Re-deriving via undetermined coefficients confirmed `+0.05` is correct.
- **Fix:** Replaced formula with `(dP0/R)*(1 + tau/T_ramp - t/T_ramp - (tau/T_ramp)*exp(-t/tau))`
- **Files modified:** test/test_pump.jl
- **Verification:** isapprox(0.050, 0.050; rtol=0.01) passes at t=T_ramp and t=T_ramp/2
- **Committed in:** eb2d629 (Task 1 commit)

**2. [Rule 3 - Blocking] Added second thermal anchor to PUMP-03 closed loop**
- **Found during:** Task 1 (PUMP-03 mtkcompile)
- **Issue:** `mtkcompile(sys)` raised `ExtraVariablesSystemException: 18 variables, 17 equations`. `ine.outlet.T` was underdetermined due to circular instream in hydraulics-only loop.
- **Fix:** Added `ine.outlet.T ~ 313.15` to connections alongside existing `pump.inlet.T ~ 313.15`
- **Files modified:** test/test_pump.jl
- **Verification:** `mtkcompile(sys; fully_determined=false)` produces 1 unknown (mdot), 1 equation
- **Committed in:** eb2d629 (Task 1 commit)

**3. [Rule 3 - Blocking] Two-system approach for callable T_wall steady-state ICs**
- **Found during:** Task 2 (SOLV-02 execution)
- **Issue:** `solve_steady(ssys_with_callable, op_guess)` raised `ArgumentError` — `SteadyStateProblem` cannot handle time-dependent callable parameters
- **Fix:** Use `build_loop_transient(T_wall_0=...)` (scalar wall) for steady-state solve; `build_loop_transient(T_wall_fn=...)` for transient; transfer SS solution as IC
- **Files modified:** test/test_solvers.jl, test/test_validation.jl
- **Verification:** SOLV-02 and VAL-02 transient tests pass
- **Committed in:** 18190c0 (Task 2 commit)

**4. [Rule 3 - Blocking] Fixed T_wall_callable parameter access and Pair{Any,Any} op vector**
- **Found during:** Task 2 (SOLV-02 execution)
- **Issue:** (a) `ssys.sys.T_wall_callable` raised "variable sys does not exist" — correct path is `ssys.T_wall_callable` but this returns `CallAndWrap{Num}`, not `Num`. (b) `push!(op_ic, T_wall_callable => fn)` failed with type conversion error on `Vector{Pair{Num,Float64}}`
- **Fix:** Use `last(parameters(ssys))` to get the raw sym; use `Pair{Any,Any}[...]` for op vector
- **Files modified:** test/test_solvers.jl, test/test_validation.jl
- **Verification:** Both SOLV-02 and VAL-02 transient tests pass with `retcode == Success`
- **Committed in:** 18190c0 (Task 2 commit)

**5. [Rule 3 - Blocking] Fixed 23 Pump(dP_pump=X) keyword call sites across test suite**
- **Found during:** Before Task 2 (full suite run showed test_channel.jl failing first)
- **Issue:** All test files except test_pump.jl still used old `Pump(dP_pump=X)` keyword syntax which no longer exists after Plan 01's API change
- **Fix:** `sed` replaced all instances in test_channel.jl, test_correlations.jl, test_composition.jl, test_validation.jl
- **Files modified:** test/test_channel.jl, test/test_correlations.jl, test/test_composition.jl, test/test_validation.jl
- **Verification:** Full suite runs; all tests pass (except pre-existing flaky VAL-01 Fourier)
- **Committed in:** 18190c0 (Task 2 commit)

---

**Total deviations:** 5 auto-fixed (1 Rule 1 - Bug, 4 Rule 3 - Blocking)
**Impact on plan:** All fixes necessary for correctness and to unblock plan verification. The analytical formula fix was required for PUMP-03 to pass; all blocking fixes were needed for the test suite to run.

## Issues Encountered

- Pre-existing flaky test `VAL-01: HeatDiffusion transient — Fourier series validation` fails intermittently — documented in STATE.md before this plan; not caused by v0.6 changes; excluded from suite pass criteria.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Full test suite (excluding pre-existing VAL-01 Fourier flaky test) passes
- PUMP-01/02/03 requirements complete
- Phase 22 (Time-Varying Pump) is fully complete
- Phase 23 (Flapper) can start — `callbacks` kwarg pre-wired in `solve_transient`; callable parameter pattern established for `dP_pump_fn`

## Self-Check: PASSED

- test/test_pump.jl: FOUND
- test/test_solvers.jl: FOUND
- test/test_validation.jl: FOUND
- SUMMARY.md: FOUND
- commit eb2d629: FOUND
- commit 18190c0: FOUND

---
*Phase: 22-time-varying-pump*
*Completed: 2026-03-18*
