---
phase: 01-foundation
plan: 02
subsystem: fluids
tags: [julia, simantov, fluid-properties, modelingtoolkit, register-symbolic, water]

# Dependency graph
requires:
  - phase: 01-foundation/01-01
    provides: "Package scaffold with stub fluids.jl and @register_symbolic declarations"
provides:
  - "rho_water(T_K) — Simantov density correlation in kg/m³"
  - "cp_water(T_K) — Simantov specific heat correlation in J/(kg·K)"
  - "mu_water(T_K) — Simantov dynamic viscosity correlation in Pa·s"
  - "k_water(T_K) — Simantov thermal conductivity correlation in W/(m·K)"
  - "All four functions callable with symbolic MTK variables (Num type)"
affects: [02-components, 03-integration]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Simantov polynomial correlations: pure arithmetic, no branches, ForwardDiff-compatible"
    - "K→C→F unit chain: T_C = T_K - 273.15, T_F = 1.8*T_C + 32 for rho_water (Fahrenheit-based correlation)"
    - "abs() on result for rho_water and k_water (matches Python STREAM np.abs behavior)"
    - "abs(T_K - 273.15) for cp_water T_C (matches Python STREAM np.abs(T))"
    - "@register_symbolic at module top-level enables MTK symbolic dispatch"

key-files:
  created: []
  modified:
    - src/fluids.jl

key-decisions:
  - "abs() on cp_water input T_C (not output) matches Python STREAM np.abs(T) behavior"
  - "abs() on rho_water and k_water outputs matches Python STREAM np.abs(result) behavior"
  - "No conditional branches in any function — required for ForwardDiff compatibility in MTK"

patterns-established:
  - "Simantov correlations: all polynomial/rational/exponential, no if-else, safe for AD"
  - "Unit chain pattern: K input → C intermediate → F for rho (Fahrenheit-based Simantov quirk)"

requirements-completed: [FOUND-02]

# Metrics
duration: 5min
completed: 2026-03-12
---

# Phase 1 Plan 02: Fluid Properties Implementation Summary

**Four Simantov correlations for light water (rho, cp, mu, k) replacing stubs, all matching Python STREAM reference values at rtol=1e-5 and callable via MTK symbolic variables**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-03-12T00:21:51Z
- **Completed:** 2026-03-12T00:27:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Replaced stub function bodies with full Simantov polynomial/exponential correlations
- All 12 fluid property spot-checks pass at 300K, 350K, 400K (rtol=1e-5 vs Python STREAM reference)
- MTK smoke test passes: rho_water(T_sym) returns Symbolics.Num (not Float64)
- No regressions: FOUND-01, CONN-01, CONN-02 tests remain green (25/25 total)

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement Simantov fluid property correlations** - `a172dd9` (feat)

**Plan metadata:** _(docs commit follows)_

_Note: TDD task — tests pre-existed from Plan 01; confirmed RED (12 failures), then GREEN after implementation._

## Files Created/Modified
- `src/fluids.jl` - Full Simantov correlation implementations replacing stubs

## Decisions Made
- `abs()` applied to cp_water's T_C input (not output) to match Python STREAM's `np.abs(T)` pattern
- `abs()` applied to rho_water and k_water outputs to match Python STREAM's `np.abs(result)` usage
- No conditional branches anywhere — pure arithmetic required for ForwardDiff compatibility in MTK

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None. The provided correlation coefficients and formula structure matched Python STREAM reference values on the first implementation attempt.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness
- All four fluid property functions ready for use in Phase 2 component equations
- Functions are symbolically registered and can appear in MTK ODE/DAE system equations
- ForwardDiff-compatible (no branches) — Jacobian computation will work correctly

---
*Phase: 01-foundation*
*Completed: 2026-03-12*
