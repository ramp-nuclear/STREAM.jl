---
phase: 25-argument-structure-audit
plan: 01
subsystem: api
tags: [julia, mtk, refactoring, argument-conventions]

# Dependency graph
requires: []
provides:
  - "Positional argument signatures for Resistor(R; name), Gravity(H; name), Inertia(L_over_A; name), HeatExchanger(T_bc; name), ConstantTemperature(T; name), laminar_friction(aspect_ratio::Real)"
  - "Two-tier positional/keyword convention documented in CLAUDE.md"
  - "All ~60 call sites across src/ and test/ migrated to positional syntax"
affects: [all future component authoring, test authoring, documentation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Positional single-param components: Resistor(R; name), Gravity(H; name) etc."
    - "Keyword multi-param constructors: Channel(; name, n, geometry, ...) etc."
    - "name kwarg always keyword-only (required by @named macro)"

key-files:
  created: []
  modified:
    - src/components/resistors.jl
    - src/components/misc.jl
    - src/physical_models/correlations.jl
    - src/examples.jl
    - test/test_resistors.jl
    - test/test_misc.jl
    - test/test_channel.jl
    - test/test_composition.jl
    - test/test_correlations.jl
    - test/test_flapper.jl
    - test/test_pump.jl
    - test/test_sign_safety.jl
    - test/test_heat_diffusion.jl
    - test/test_validation.jl
    - test/test_loss_of_flow.jl
    - examples/lof_transient.jl
    - CLAUDE.md

key-decisions:
  - "No backward-compatibility shims: old keyword form deleted, MethodError forces migration (D-03)"
  - "laminar_friction changed from keyword factory to positional (aspect_ratio::Real is unambiguous from function name)"
  - "ConstantTemperature array comprehension pattern: ConstantTemperature(T_val; name=Symbol(...)) -- T positional, name stays keyword"

patterns-established:
  - "Two-tier API rule: positional for single-param components, keyword for multi-param constructors"
  - "The @named macro injects name=:varname as keyword -- name arg must always be keyword-only"

requirements-completed: []

# Metrics
duration: 15min
completed: 2026-03-26
---

# Phase 25 Plan 01: Argument Structure Audit Summary

**Migrated 6 component signatures from keyword-only to positional (Resistor, Gravity, Inertia, HeatExchanger, ConstantTemperature, laminar_friction) across 16 files with zero test failures**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-03-26T18:51:00Z
- **Completed:** 2026-03-26T19:06:06Z
- **Tasks:** 2
- **Files modified:** 17

## Accomplishments

- Changed 6 function signatures from keyword-only to positional in 3 source files
- Migrated all ~60 call sites across 13 test files, src/examples.jl, and examples/lof_transient.jl
- Updated CLAUDE.md with the two-tier positional/keyword convention rule
- Full test suite passes with zero failures (all 161+ tests green)

## Task Commits

1. **Task 1: Change 6 signatures and update all call sites** - `38a2f61` (refactor)
2. **Task 2: Update CLAUDE.md with two-tier convention rule** - `d59c52a` (docs)

## Files Created/Modified

- `src/components/resistors.jl` - Gravity(H; name) and Resistor(R; name) positional signatures
- `src/components/misc.jl` - Inertia(L_over_A; name), HeatExchanger(T_bc; name), ConstantTemperature(T; name) positional signatures
- `src/physical_models/correlations.jl` - laminar_friction(aspect_ratio::Real) positional signature
- `src/examples.jl` - Updated all call sites: HeatExchanger(T_inlet), Gravity(H), Resistor(R), Inertia(L_over_A)
- `test/test_resistors.jl` - Resistor(1.0e5) positional calls
- `test/test_misc.jl` - Inertia(1e3), HeatExchanger(313.15) positional calls
- `test/test_channel.jl` - Gravity(3.0), HeatExchanger(T_inlet), ConstantTemperature(T_wall; name=...) calls
- `test/test_composition.jl` - HeatExchanger(600.0), ConstantTemperature(T_wall_qol; name=...), laminar_friction(0.0025/0.070) calls
- `test/test_correlations.jl` - laminar_friction(0.01814), HeatExchanger(T_inlet), ConstantTemperature(T_wall; name=...) calls
- `test/test_flapper.jl` - Resistor(1e5), Inertia(L_over_A) positional calls
- `test/test_pump.jl` - HeatExchanger(313.15), Inertia(L_over_A), Resistor(R_val) positional calls
- `test/test_sign_safety.jl` - HeatExchanger(T_inlet_sign), ConstantTemperature(T_wall_sign; name=...) calls
- `test/test_heat_diffusion.jl` - ConstantTemperature(T_bc; name=...) calls (5 comprehensions)
- `test/test_validation.jl` - HeatExchanger(T_in), ConstantTemperature(T_wall; name=...) calls
- `test/test_loss_of_flow.jl` - HeatExchanger(BYPASS_T_INLET) call
- `examples/lof_transient.jl` - HeatExchanger(T_inlet) call
- `CLAUDE.md` - Two-tier positional/keyword convention rule

## Decisions Made

- No backward-compatibility shims: old keyword form deleted, MethodError forces migration. Matches the pattern established in v0.4 for PipeGeometry factory functions.
- `laminar_friction` changed from kwarg-only factory to positional since `aspect_ratio::Real` is unambiguous from the function name and a single scalar argument.
- `ConstantTemperature(T_val; name=Symbol(:prefix, i))` — T is positional, name stays keyword in array comprehensions where `@named` cannot be used.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Argument structure audit complete for all targeted components
- CLAUDE.md two-tier convention rule in place for future authors
- v0.6 components (Flapper, natural convection) already use positional pattern for single-param args

---
*Phase: 25-argument-structure-audit*
*Completed: 2026-03-26*
