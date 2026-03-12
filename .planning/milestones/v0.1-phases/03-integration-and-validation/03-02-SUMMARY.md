---
phase: 03-integration-and-validation
plan: "02"
subsystem: solvers
tags: [julia, modelingtoolkit, sundials, differentialequations, transient, dae, callback, rodas5p]

# Dependency graph
requires:
  - phase: 03-integration-and-validation
    plan: "01"
    provides: "build_loop, solve_steady, steady_state_guess; closed-loop compiling with TempBC pattern"
provides:
  - "src/solvers.jl: build_loop_transient (T_wall as @parameters symbol)"
  - "src/solvers.jl: solve_transient fully implemented (replaces stub)"
  - "T_wall step-change simulation via PresetTimeCallback + ModelingToolkit.setp"
  - "SOLV-02 test block in runtests.jl (48 total tests green)"
affects:
  - 03-03-validation

# Tech tracking
tech-stack:
  added:
    - "Rodas5P (stiff implicit Runge-Kutta from OrdinaryDiffEqRosenbrock — supports mass-matrix ODE)"
    - "PresetTimeCallback (DifferentialEquations — fires at fixed time to modify parameters)"
    - "ModelingToolkit.setp (not exported; creates parameter setter for compiled MTK system)"
    - "SciMLBase.NoInit (bypass MTK initialization for rough-guess initial conditions)"
  patterns:
    - "build_loop_transient uses @parameters T_wall to enable setp modification at runtime"
    - "T_wall stepped (not Q_wall) because Channel energy balance uses thermal.T, not Q_flow"
    - "Rodas5P + NoInit pattern for mass-matrix DAE transient simulation from MTK"
    - "PresetTimeCallback([t_step], integrator -> setter(integrator, new_val)) for step change"

key-files:
  created:
    - "test/test_transient_tdd.jl"
  modified:
    - "src/solvers.jl (build_loop_transient + full solve_transient replacing stub)"
    - "src/STREAM.jl (added build_loop_transient export)"
    - "test/runtests.jl (added SOLV-02 test block)"

key-decisions:
  - "T_wall is the stepped parameter (not Q_wall) — Channel energy balance uses thermal.T via h_tc*dz*(thermal.T - T[i]), not Q_flow directly"
  - "Rodas5P chosen over IDA/CVODE_BDF — IDA needs DAEProblem+du0, CVODE_BDF cannot use mass matrices; Rodas5P handles mass-matrix ODEProblem"
  - "SciMLBase.NoInit required — MTK initialization fails for rough guess (29 eqs for 1 unknown); NoInit trusts caller's op dict"
  - "ModelingToolkit.setp not in public namespace — must use ModelingToolkit.setp explicitly"
  - "build_loop_transient keeps TempBC (same as build_loop) — required for closed-loop instream() T injection"

patterns-established:
  - "T_wall step-change pattern: @parameters T_wall = T_wall_0 in top-level System, ch.thermal.T ~ ps[1] in connections, ModelingToolkit.setp(ssys, ps[1]) for callback setter"
  - "Mass-matrix DAE transient pattern: ODEProblem(ssys, op, tspan; warn_initialize_determined=false) + solve(prob, Rodas5P(); initializealg=SciMLBase.NoInit())"

requirements-completed: [SOLV-02]

# Metrics
duration: 18min
completed: 2026-03-12
---

# Phase 3 Plan 02: Transient Solver Summary

**Transient DAE solver with T_wall step change via PresetTimeCallback + Rodas5P; T_outlet rises from 318K to 331K in 30s simulation after T_wall step at t=10s**

## Performance

- **Duration:** 18 min
- **Started:** 2026-03-12T12:33:44Z
- **Completed:** 2026-03-12T12:52:43Z
- **Tasks:** 1 (+ TDD RED phase)
- **Files modified:** 4

## Accomplishments

- Replaced `solve_transient` stub with full implementation using Rodas5P ODE solver
- Added `build_loop_transient()` returning (ssys, T_wall_sym) — T_wall as modifiable parameter
- Confirmed step-change simulation: T_outlet rises from 318.03 K to 330.77 K after T_wall step 373→393 K at t=10s
- All 48 tests green (25 Phase 1 + 9 Phase 2 + 14 Phase 3)
- Discovered and documented correct solver stack for MTK mass-matrix DAE transient problems

## Task Commits

1. **TDD RED: Failing tests for transient solver** - `475d1df` (test)
2. **Task 1: Full solve_transient + build_loop_transient implementation** - `6a3be95` (feat)

## Files Created/Modified

- `src/solvers.jl` — Added `build_loop_transient` and full `solve_transient` (replacing stub)
- `src/STREAM.jl` — Added `build_loop_transient` export
- `test/test_transient_tdd.jl` — TDD test file for transient solver
- `test/runtests.jl` — Added SOLV-02 test block with build/solve/T_outlet tests

## Decisions Made

1. **T_wall as the modifiable parameter (not Q_wall):** Channel's energy balance uses `h_tc[i] * (π * Dh) * dz * (thermal.T - T[i])` — the wall temperature drives heat transfer. `thermal.Q_flow` is only an observable (`q_wall[i] ~ thermal.Q_flow / n`), not part of the energy balance. Stepping T_wall is physically equivalent to stepping Q_wall (both change the heat input), and is the only approach that works with the existing Channel component without modification.

2. **Rodas5P instead of IDA:** MTK's `mtkcompile` produces a mass-matrix ODE (`M * du = f(u, p, t)`). IDA requires `DAEProblem` with explicit `du0` (initial derivatives) and `CVODE_BDF` cannot use mass matrices. `Rodas5P` is a stiff implicit Runge-Kutta solver from `OrdinaryDiffEqRosenbrock` that natively supports mass-matrix ODEProblems.

3. **SciMLBase.NoInit for initialization:** MTK initialization sees 29 equations for 1 unknown (T_wall param, similar to plan 03-01's 22-eq overdetermination). Default initialization causes `InitialFailure`. Using `NoInit` bypasses this and trusts the caller's op dict. The rough guess (steady_state_guess + mdot physics estimate) is close enough for Rodas5P to integrate from.

4. **ModelingToolkit.setp explicit namespace:** `setp` is defined in `SymbolicIndexingInterface` and re-exported through `ModelingToolkit` (as `isdefined(ModelingToolkit, :setp) == true`), but it is NOT in ModelingToolkit's public export list. Must use `ModelingToolkit.setp(ssys, sym)` explicitly.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] IDA solver incompatible with MTK's ODEProblem mass-matrix form**
- **Found during:** Task 1 (solve_transient implementation)
- **Issue:** Research doc and plan specified `ODEProblem + IDA()`. IDA requires `DAEProblem` with explicit `du0`; when given an `ODEProblem` it errors: "Problem types compatible with the chosen solver: SciMLBase.DAEProblem"
- **Fix attempt 1:** Switched to `DAEProblem(ssys, op, tspan)` — errors: "Initial condition underdefined. Some are missing: fr₊port_in₊mdotˍt(t), fr₊Reˍt(t)"
- **Fix attempt 2:** Switched to `CVODE_BDF()` with `ODEProblem` — errors: "This solver is not able to use mass matrices"
- **Fix attempt 3 (final):** Switched to `Rodas5P()` — supports mass-matrix ODEProblems natively. Confirmed working.
- **Files modified:** src/solvers.jl
- **Verification:** `sol.retcode == Success`, 23 time points, T_outlet 318→331 K range
- **Committed in:** `6a3be95` (Task 1 commit)

**2. [Rule 1 - Bug] setp not in ModelingToolkit public namespace**
- **Found during:** Task 1 (PresetTimeCallback setup)
- **Issue:** `setp(ssys, sym)` errors: "UndefVarError: setp not defined in STREAM"
- **Fix:** Use `ModelingToolkit.setp(ssys, sym)` with explicit module qualification
- **Files modified:** src/solvers.jl
- **Committed in:** `6a3be95` (Task 1 commit)

**3. [Rule 1 - Bug] InitialFailure with default MTK initialization**
- **Found during:** Task 1 (transient simulation)
- **Issue:** `sol.retcode == InitialFailure`, `length(sol.t) == 1` — MTK initialization system has 29 equations for 1 unknown (T_wall parameter default), overdetermined init fails
- **Fix:** Add `initializealg=SciMLBase.NoInit()` to bypass MTK initialization for rough initial guess
- **Files modified:** src/solvers.jl
- **Committed in:** `6a3be95` (Task 1 commit)

---

**Total deviations:** 3 auto-fixed (all Rule 1 — solver API compatibility bugs)
**Impact on plan:** The IDA solver replacement was the key deviation — the research doc confirmed IDA availability but not its incompatibility with MTK's mass-matrix ODEProblem form. Rodas5P is the correct solver for this problem class.

## Issues Encountered

- **IDA/CVODE_BDF solver incompatibility with MTK mass-matrix ODE:** Three solver attempts before finding Rodas5P. The MTK `mtkcompile` pipeline produces a mass-matrix ODE (not a "true DAE" in the IDA sense) — documented for future reference.
- **setp not publicly exported by ModelingToolkit:** Despite `isdefined(ModelingToolkit, :setp) == true`, it requires explicit namespace access. The research doc noted "MEDIUM confidence" for this API — the concern was warranted.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `build_loop_transient()` and `solve_transient()` are production-ready
- Physical transient confirmed: T_outlet rises 318→331 K in 30s after T_wall step 373→393 K at t=10s
- Plan 03-03 (validation) can use `build_loop` + `solve_steady` for steady-state validation against Python STREAM reference values
- VAL-01 (steady-state T_outlet/mdot within 1% of Python STREAM) and VAL-02 (transient T_outlet[end] > T_outlet[1]) are the validation targets

---
*Phase: 03-integration-and-validation*
*Completed: 2026-03-12*

## Self-Check: PASSED

- FOUND: src/solvers.jl
- FOUND: src/STREAM.jl
- FOUND: test/test_transient_tdd.jl
- FOUND: test/runtests.jl
- FOUND: .planning/phases/03-integration-and-validation/03-02-SUMMARY.md
- FOUND: commit 475d1df (TDD RED)
- FOUND: commit 6a3be95 (feat: transient solver)
