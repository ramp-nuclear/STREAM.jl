---
phase: 50-open-source-readiness
plan: "05"
subsystem: test-infrastructure, examples
tags: [gap-closure, test-environment, mtr-assembly, heat-diffusion]
dependency_graph:
  requires: []
  provides: [direct-test-invocation, fully-determined-mtr-assembly]
  affects: [test/runtests.jl, examples/mtr_assembly.jl]
tech_stack:
  added: []
  patterns: [julia-test-project-toml, mtk-fully-determined-system]
key_files:
  created:
    - test/Project.toml
  modified:
    - examples/mtr_assembly.jl
decisions:
  - "test/Project.toml [deps] section enables direct `julia --project=. test/runtests.jl` without Pkg.test(); [extras]/[targets] in root Project.toml coexist for CI"
  - "HeatDiffusion power is an MTK @variables unknown (not a parameter); constructor arg is initial guess only; rods.hd.power ~ POWER is required governing equation"
  - "Removed fully_determined=false workaround from mtkcompile call so equation count mismatches fail fast"
metrics:
  duration_minutes: 5
  completed_date: "2026-04-10"
  tasks_completed: 2
  files_changed: 2
---

# Phase 50 Plan 05: Gap Closure — test/Project.toml + MTR Assembly Power Equation Summary

**One-liner:** Created test/Project.toml for direct test invocation and added missing `rods.hd.power ~ POWER` governing equation to mtr_assembly.jl, making the HeatDiffusion system fully determined (93 equations, 93 unknowns).

## What Was Built

Two targeted fixes that close the final two UAT gaps (tests 4 and 6) before Phase 50 is complete.

### Task 1: test/Project.toml

Created `test/Project.toml` with NonlinearSolve and Test in `[deps]`. The `[extras]/[targets]` mechanism in the root Project.toml only activates for `Pkg.test()`. Direct invocations (`julia --project=. test/runtests.jl`) need a separate `test/Project.toml` to resolve NonlinearSolve. Both mechanisms coexist — CI (julia-actions/julia-runtest) uses `Pkg.test()`, developers use direct invocation.

### Task 2: mtr_assembly.jl power equation

Added `rods.hd.power ~ POWER` to the `conns` array and removed `fully_determined=false` from the `mtkcompile` call.

Root cause: `HeatDiffusion` declares `power` as an MTK `@variables` unknown. The constructor argument `power=POWER` provides only an initial guess, not a governing equation. Without the explicit `rods.hd.power ~ POWER` connection, the system had 92 equations but 93 unknowns (power was unconstrained), causing an under-determined error at solve time. The `fully_determined=false` flag was a workaround that suppressed this error — removing it ensures future equation count mismatches surface immediately.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1    | 0e6a6f2 | chore(50-05): add test/Project.toml for direct test invocation |
| 2    | 0ab2d09 | fix(50-05): add missing power equation and remove fully_determined workaround |

## Verification

All checks pass:

```
NonlinearSolve = "8913a72c-1f9b-4ce2-8d82-65094dcecaec"  ✓
Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"             ✓
rods.hd.power ~ POWER (line 99)                           ✓
fully_determined: not found                               ✓
```

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None.

## Threat Flags

None.

## Self-Check: PASSED

- `test/Project.toml` exists: FOUND
- `examples/mtr_assembly.jl` contains `rods.hd.power ~ POWER`: FOUND
- `fully_determined=false` removed: CONFIRMED
- Commits 0e6a6f2 and 0ab2d09: FOUND
