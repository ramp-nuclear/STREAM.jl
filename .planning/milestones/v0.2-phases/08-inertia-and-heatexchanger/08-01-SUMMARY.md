---
phase: 08-inertia-and-heatexchanger
plan: 01
subsystem: components
tags: [modelingtoolkit, inertia, ode, fluid-inertia, tdd, rl-decay]

# Dependency graph
requires:
  - phase: 07-network-architecture
    provides: Resistor component used in RL-decay validation circuit

provides:
  - Inertia(; name, L_over_A) component in src/components.jl
  - Inertia exported from STREAM module
  - Phase 8 testset with COMP-01 (green) and COMP-02 (red stubs) in test/runtests.jl

affects:
  - 08-02-PLAN (COMP-02 HeatExchanger — regression test already written in Phase 8 testset)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Inertia ODE component: Differential(t)(inlet.mdot) as implicit state promoted by MTK"
    - "fully_determined=false + check_length=false pattern for underdetermined T variables in pure pressure circuits"
    - "RL-decay transient validation: Inertia + Resistor loop, IC mdot=1 kg/s, analytical mdot(t)=exp(-t/tau)"

key-files:
  created: []
  modified:
    - src/components.jl
    - src/STREAM.jl
    - test/runtests.jl

key-decisions:
  - "Inertia uses empty vars=[] — MTK auto-promotes inlet.mdot as differential state via Dt(inlet.mdot)"
  - "RL-decay test requires fully_determined=false (T stream vars underdetermined in pure pressure circuit)"
  - "ODEProblem requires check_length=false + explicit T ICs because T unknowns have no equations in RL circuit"
  - "T ICs set to 300.0 K (arbitrary, no heat exchange) alongside mdot=1.0 kg/s IC"

patterns-established:
  - "ODE component pattern: Dt = Differential(t); eqs include Dt(inlet.mdot) term; vars=[]; MTK auto-promotes"
  - "Pure pressure circuit test: mtkcompile with fully_determined=false; ODEProblem with check_length=false"

requirements-completed: [COMP-01]

# Metrics
duration: 19min
completed: 2026-03-13
---

# Phase 8 Plan 01: Inertia Component (COMP-01) Summary

**Inertia lumped ODE component (L_over_A * D(mdot) pressure drop) validated against analytical RL-decay: mdot(t) = exp(-t/tau) within 2.6e-6 rtol**

## Performance

- **Duration:** 19 min
- **Started:** 2026-03-13T16:01:26Z
- **Completed:** 2026-03-13T16:20:30Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Inertia component implemented in src/components.jl following the Resistor pattern, substituting the algebraic pressure drop equation with the ODE `inlet.P - outlet.P ~ L_over_A * Dt(inlet.mdot)`
- Inertia exported from STREAM module
- RL-decay transient validation passes: mdot(t) matches exp(-t/tau) within 2.6e-6 rtol at all 5 time points (t = 0, 500, 1000, 2000, 5000 s)
- Phase 8 testset written with COMP-01 (green) and COMP-02 stubs (red, for Plan 02)

## Task Commits

Each task was committed atomically:

1. **Task 1: Write Phase 8 test stubs (RED state)** - `2ceef20` (test)
2. **Task 2: Implement Inertia component (GREEN — COMP-01)** - `6b996df` (feat)

_Note: TDD plan — test commit followed by implementation commit_

## Files Created/Modified
- `src/components.jl` — Added Inertia function after Resistor (ODE pressure drop with Differential(t))
- `src/STREAM.jl` — Added Inertia to export list
- `test/runtests.jl` — Updated imports (DifferentialEquations unqualified, Inertia + HeatExchanger added); added Phase 8 testset

## Decisions Made
- Inertia uses `vars = []` (empty) — MTK auto-promotes `inlet.mdot` as a differential state variable because it appears inside `Dt(inlet.mdot)`; adding an explicit `mdot(t)` state would overconstrain the system
- Temperature passthrough equations identical to Resistor/Gravity pattern (no heat exchange semantics)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed mtkcompile call in RL-decay test: added fully_determined=false**
- **Found during:** Task 2 (Implement Inertia component)
- **Issue:** Plan wrote `ssys = mtkcompile(sys)` without `fully_determined=false`. The RL circuit (Inertia + Resistor, no heat exchange) has T stream variables that are underdetermined — `mtkcompile` raises `ExtraVariablesSystemException` (12 variables, 10 equations)
- **Fix:** Changed to `mtkcompile(sys; fully_determined=false)` to allow the underdetermined T variables
- **Files modified:** test/runtests.jl
- **Verification:** mtkcompile succeeds; 3 unknowns retained: `L_comp.inlet.mdot`, `L_comp.outlet.T`, `L_comp.inlet.T`
- **Committed in:** 6b996df

**2. [Rule 1 - Bug] Fixed ODEProblem construction: added T ICs and check_length=false**
- **Found during:** Task 2 (Implement Inertia component)
- **Issue:** Plan wrote `op = [ssys.L_comp.inlet.mdot => 1.0]` with no T ICs. After mtkcompile with `fully_determined=false`, the system has 3 unknowns (mdot + 2 T vars) but only 1 equation. `ODEProblem` raises `ArgumentError: Equations (1), unknowns (3), and initial conditions (3) are of different lengths` even when all 3 ICs provided — requires `check_length=false`
- **Fix:** Added T ICs (`L_comp.outlet.T => 300.0`, `L_comp.inlet.T => 300.0`) and `check_length=false` keyword to `ODEProblem` constructor
- **Files modified:** test/runtests.jl
- **Verification:** ODEProblem constructs successfully; Rodas5P integrates to ReturnCode.Success; RL-decay matches analytical within 2.6e-6 rtol
- **Committed in:** 6b996df (same commit as fix 1)

---

**Total deviations:** 2 auto-fixed (2 × Rule 1 - Bug)
**Impact on plan:** Both fixes necessary for the RL-decay test to run. The Inertia component implementation itself matches the plan exactly; only the test scaffolding needed correction. The `fully_determined=false` + `check_length=false` pattern is a documented MTK pattern for underdetermined systems and consistent with isolated component testing established in Phase 7.

## Issues Encountered
- T stream variables in a pure pressure circuit (no heat exchange) are algebraically free — MTK keeps them as unknowns after mtkcompile. This is structurally correct (T could evolve if heat were added) but requires the `check_length=false` ODEProblem workaround. Documented in test comments.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Plan 02 (HeatExchanger) can proceed immediately — COMP-02 stubs are already written (RED state) and the regression test (`build_loop compiles after HeatExchanger rename`) is in place
- COMP-01 requirement satisfied; Inertia is production-ready for use in network topologies

---
*Phase: 08-inertia-and-heatexchanger*
*Completed: 2026-03-13*
