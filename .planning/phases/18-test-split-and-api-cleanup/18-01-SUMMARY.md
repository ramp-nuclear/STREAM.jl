---
phase: 18-test-split-and-api-cleanup
plan: "01"
subsystem: test
tags: [test-split, refactoring, orchestrator]
dependency_graph:
  requires: []
  provides: [test/test_geometry.jl, test/test_connectors.jl, test/test_fluids.jl, test/test_channel.jl, test/test_pump.jl, test/test_resistors.jl, test/test_misc.jl, test/test_heat_diffusion.jl, test/test_correlations.jl, test/test_composition.jl, test/test_solvers.jl, test/test_validation.jl, test/test_examples.jl]
  affects: [test/runtests.jl]
tech_stack:
  added: []
  patterns: [Julia include-based test orchestration, self-contained test files with per-file using blocks]
key_files:
  created:
    - test/test_geometry.jl
    - test/test_connectors.jl
    - test/test_fluids.jl
    - test/test_channel.jl
    - test/test_pump.jl
    - test/test_resistors.jl
    - test/test_misc.jl
    - test/test_heat_diffusion.jl
    - test/test_correlations.jl
    - test/test_composition.jl
    - test/test_solvers.jl
    - test/test_validation.jl
    - test/test_examples.jl
  modified:
    - test/runtests.jl
decisions:
  - "ModelingToolkitBase accessed as ModelingToolkit.ModelingToolkitBase (not available as standalone package in this environment)"
  - "const SciMLBase placed in test_misc.jl (RL-decay test) and test_validation.jl (Fourier transient test)"
  - "COMPAT test moved to test_examples.jl per CLAUDE.md layout"
  - "import STREAM: check_gravity_mismatch, port dropped from test_composition.jl (using STREAM sufficient)"
metrics:
  duration: "~14 minutes"
  completed: "2026-03-16"
  tasks_completed: 2
  files_created: 13
  files_modified: 2
---

# Phase 18 Plan 01: Test Split Summary

Split 1805-line runtests.jl monolith into 13 self-contained test_*.jl files matching CLAUDE.md canonical test layout, with runtests.jl reduced to 13 include() calls.

## What Was Built

The 1805-line `test/runtests.jl` monolith was mechanically split into 13 dedicated test files. Each file is self-contained with its own `using` block. The test suite runs green with all tests passing.

**runtests.jl:** Reduced from 1805 lines to 15 lines — 13 `include()` calls only, no `using` statements, no `@testset` blocks, no test logic.

**13 new test files created:**
- `test_geometry.jl` — PHY-01 PipeGeometry tests
- `test_connectors.jl` — FOUND-01, CONN-01/02 FlowPort/ThermalPort tests
- `test_fluids.jl` — FOUND-02 fluid property tests
- `test_channel.jl` — COMP-01 Channel, GRAV-*, CHAN-*, THERM-* tests
- `test_pump.jl` — PHY-05 Pump tests
- `test_resistors.jl` — NET-* Resistor/network tests
- `test_misc.jl` — COMP-01/02 Inertia/HeatExchanger tests
- `test_heat_diffusion.jl` — HDIFF-01..05 HeatDiffusion tests
- `test_correlations.jl` — PHY-02/03/04 correlation tests
- `test_composition.jl` — QOL-01..03, COMP-01..04 composition helper tests
- `test_solvers.jl` — SYS-*, SOLV-* solver integration tests
- `test_validation.jl` — all VAL-* quantitative cross-validation tests
- `test_examples.jl` — COMPAT smoke test

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] ModelingToolkitBase not available as standalone package**
- **Found during:** Task 2 (test suite run)
- **Issue:** `using ModelingToolkitBase` in test_connectors.jl caused LoadError — package not in project manifest as standalone
- **Fix:** Replaced `using ModelingToolkitBase` with `const ModelingToolkitBase = ModelingToolkit.ModelingToolkitBase` — the submodule is accessible via ModelingToolkit
- **Files modified:** test/test_connectors.jl
- **Commit:** e31e622

## Requirements Satisfied

- TEST-01: runtests.jl is a thin orchestrator of 13 include() calls; all test logic in dedicated files
- QOL-02: VAL-03 not orphaned — real content (one-sided MTR adiabatic) preserved in test_validation.jl

## Self-Check
- All 13 test_*.jl files exist: PASSED
- runtests.jl has 13 include() calls, 0 using, 0 @testset: PASSED
- Full test suite green: PASSED
- VAL-03 content in test_validation.jl: PASSED
- const SciMLBase in test_misc.jl: PASSED
- COMPAT in test_examples.jl: PASSED
