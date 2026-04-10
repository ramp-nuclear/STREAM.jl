---
phase: 50-open-source-readiness
plan: 02
subsystem: testing, infra
tags: [julia, github-actions, ci, nonlinear-solve, heat-diffusion, ode]

# Dependency graph
requires:
  - phase: 50-open-source-readiness
    provides: Project.toml metadata, MIT license, README
provides:
  - NET-03 Cube flow test passing with RobustMultiNewton solver
  - VAL-01 Fourier series transient test passing without NoInit flakiness
  - GitHub Actions CI workflow triggering on push/PR to main
affects: [future test additions, CI integration, open-source publishing]

# Tech tracking
tech-stack:
  added: [julia-actions/setup-julia@v2, julia-actions/cache@v2, julia-actions/julia-buildpkg@v1, julia-actions/julia-runtest@v1, NonlinearSolve.RobustMultiNewton]
  patterns: [expanded initial guess for multi-variable nonlinear systems, remove NoInit from pure ODE solves]

key-files:
  created: [.github/workflows/ci.yml]
  modified: [test/test_resistors.jl, test/test_validation.jl]

key-decisions:
  - "NET-03: RobustMultiNewton over KINSOL for multi-variable resistor network — expanded 12-variable initial guess required alongside solver swap"
  - "VAL-01: Remove NoInit from pure ODE (HeatDiffusion + ConstantTemperature) and tighten tolerances to 1e-8/1e-10 for reliable Fourier convergence at t=0.5*tau"
  - "CI: Julia stable only (version: '1'), ubuntu-latest only — no multi-version or multi-platform matrix per D-12"
  - "CI concurrency: cancel-in-progress on PR branches only, not on main pushes"

patterns-established:
  - "RobustMultiNewton for large nonlinear networks: pass solver=SSRootfind(RobustMultiNewton()) to solve_steady"
  - "Expanded initial guess: provide all unknown variables in op dict, not just pump mdot"

requirements-completed: [D-12, D-13, D-14]

# Metrics
duration: 10min
completed: 2026-04-10
---

# Phase 50 Plan 02: Fix Failing Tests + GitHub Actions CI Summary

**NET-03 Cube flow fixed with RobustMultiNewton + expanded 12-variable initial guess; VAL-01 Fourier fixed by removing NoInit from pure ODE; GitHub Actions CI added targeting Julia stable on ubuntu-latest**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-04-10T07:48:00Z
- **Completed:** 2026-04-10T07:52:14Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Fixed NET-03 Cube flow test: KINSOL was receiving a single-variable initial guess for a 12-resistor system; replaced with RobustMultiNewton and an expanded op dict covering all 12 resistors
- Fixed VAL-01 Fourier series test: removed `SciMLBase.NoInit()` from pure ODE solve (HeatDiffusion + ConstantTemperature) and tightened tolerances from 1e-6/1e-8 to 1e-8/1e-10 to eliminate first-step inaccuracy at t=0.5*tau
- Added `.github/workflows/ci.yml` with julia-actions stack (setup-julia, cache, buildpkg, runtest) triggering on push/PR to main

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix NET-03 and VAL-01 test failures** - `0a6db22` (fix)
2. **Task 2: Add GitHub Actions CI workflow** - `03ae9d8` (ci)

## Files Created/Modified

- `test/test_resistors.jl` - Added `using NonlinearSolve`; replaced single-variable NET-03 initial guess with 12-entry op dict + RobustMultiNewton solver
- `test/test_validation.jl` - Removed `initializealg=SciMLBase.NoInit()` from VAL-01 Fourier solve; tightened reltol/abstol to 1e-8/1e-10
- `.github/workflows/ci.yml` - New file: GitHub Actions workflow, Julia stable, ubuntu-latest, concurrency cancellation for PR branches

## Decisions Made

- RobustMultiNewton chosen over KINSOL for multi-variable resistor network: KINSOL requires the initial guess dimension to match the system, and the prior single-variable guess caused convergence failure
- NoInit removal from VAL-01: the system is a pure ODE (no algebraic constraints) — NoInit bypasses consistent initialization and causes inaccurate first adaptive steps; removed to restore correct behavior
- Tolerance tightened to 1e-8/1e-10 to ensure 1% tolerance holds at the steep t=0.5*tau checkpoint
- CI uses minimal matrix (one OS, one Julia version) per D-12; no codecov per D-14

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All pre-existing test failures resolved; CI workflow is in place and will run on first push to main
- Plan 50-03 (file audit) can proceed without blocked test failures

---
*Phase: 50-open-source-readiness*
*Completed: 2026-04-10*
