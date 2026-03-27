---
phase: 21-fluid-properties-natural-convection
plan: 01
subsystem: fluids
tags: [julia, mtk, dimensionless, natural-convection, fluid-properties, htc-interface]

# Dependency graph
requires:
  - phase: 20-sign-safety
    provides: abs(mdot) energy balance, sign-safe channel components
provides:
  - beta_water fluid property with @register_symbolic (MTK-callable)
  - dimensionless.jl with Gr, Ra, Re, Re_vel, Pr, Nu, Pe utilities
  - 4-arg HTC interface (Re, Pr, T_bulk, T_wall) across all correlations and channels
affects:
  - 21-02 (Elenbaas natural convection correlation uses beta_water, Gr, Ra, and 4-arg interface)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "HTC correlation closures accept (Re, Pr, T_bulk, T_wall) via args... splatting for backward compat"
    - "regime_dependent forwards all 4 args explicitly to sub-correlations (not args...)"
    - "dimensionless.jl: plain Julia arithmetic, no @register_symbolic — MTK traces through"

key-files:
  created:
    - src/physical_models/dimensionless.jl
  modified:
    - src/fluids.jl
    - src/STREAM.jl
    - src/physical_models/correlations.jl
    - src/components/channel.jl
    - src/components/thermal_channel.jl
    - test/test_fluids.jl
    - test/test_correlations.jl

key-decisions:
  - "Re, Pr, Nu, Pe NOT exported as standalone names to avoid conflict with @variables names inside component functions; use STREAM.Re(...) for utility access"
  - "elenbaas_nusselt and elenbaas_htc pre-exported in STREAM.jl so Plan 02 does not need to touch exports"
  - "regime_dependent uses explicit 4-arg signature (not args...) because it must forward T_bulk/T_wall to sub-correlations"
  - "dittus_boelter and constant_Nusselt use args... splatting to accept and discard the extra 2 args"
  - "Gr reference test values corrected: inputs 3.851798e-04, 6.5766e-07 give 2863.260, not 2862.302086 as in plan draft"

patterns-established:
  - "HTC pattern: all closures accept (Re, Pr, T_bulk, T_wall); Elenbaas can use T_wall to compute dT"
  - "Channel call sites: always pass 4 args; T_wall=T_bulk for single-sided contacts (Channel, ChannelHeatFlux)"
  - "ChannelAndContacts: T_wall_cells built from thermal_left ports, passed to _channel_base_eqs"

requirements-completed: [FLUID-01, FLUID-02, FLUID-03]

# Metrics
duration: 27min
completed: 2026-03-17
---

# Phase 21 Plan 01: Fluid Properties and HTC Interface Foundation Summary

**beta_water with @register_symbolic, Gr/Ra/Re/Pe dimensionless utilities, and 4-arg HTC interface (Re, Pr, T_bulk, T_wall) extended across all correlation closures and channel components**

## Performance

- **Duration:** ~27 min
- **Started:** 2026-03-17T17:23:15Z
- **Completed:** 2026-03-17T17:50:43Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments
- Added beta_water(T_K) using Simantov density derivative; verified at 3 reference temperatures (293.15K, 323.15K, 373.15K) within rtol=1e-6; MTK-symbolic callable via @register_symbolic
- Created src/physical_models/dimensionless.jl with Gr, Ra, Re, Re_vel, Pr, Nu, Pe as plain Julia arithmetic functions (no @register_symbolic needed — MTK traces through)
- Extended HTC correlation interface from 2-arg to 4-arg: dittus_boelter and constant_Nusselt use args... splatting; regime_dependent forwards all 4 args explicitly; all channel call sites updated
- Full test suite (161+ tests) passes with zero regressions

## Task Commits

1. **Task 1: Add beta_water, create dimensionless.jl, update exports** - `1297571` (feat)
2. **Task 2: Extend HTC interface to 4-arg and update all channel call sites** - `8b67f99` (feat)

## Files Created/Modified
- `src/fluids.jl` - Added beta_water function and @register_symbolic registration
- `src/physical_models/dimensionless.jl` - New file: Gr, Ra, Re, Re_vel, Pr, Nu, Pe utilities
- `src/STREAM.jl` - Added include for dimensionless.jl; exported beta_water, Gr, Ra, Re_vel, Pe, elenbaas_nusselt, elenbaas_htc
- `src/physical_models/correlations.jl` - dittus_boelter and constant_Nusselt accept args...; regime_dependent uses 4-arg explicit forwarding
- `src/components/channel.jl` - Channel call site passes (Re[i], Pr_i, T[i], T[i]); _channel_base_eqs adds T_wall_cells kwarg and T_w_i selection
- `src/components/thermal_channel.jl` - ChannelAndContacts builds _T_wall_cells from thermal_left; obs block uses (Re_i, Pr_i, T[i], thermal_left[i].T)
- `test/test_fluids.jl` - Added FLUID-01 (beta_water), FLUID-02 (Gr), FLUID-03 (Ra) testsets
- `test/test_correlations.jl` - Updated regime_dependent test to use 4-arg call: rd.htc(Re, Pr, T_bulk, T_wall)

## Decisions Made
- Re, Pr, Nu, Pe not exported as standalone names to avoid collision with @variables names used inside component functions (Re[i], Nu[i], Pe[i] are MTK symbolic arrays, not the utility functions). Users who need utilities call STREAM.Re(...) explicitly.
- elenbaas_nusselt and elenbaas_htc pre-exported in STREAM.jl now so Plan 02 only needs to add the functions, not touch exports.
- Gr reference test value corrected from plan draft: inputs beta=3.851798e-04, nu=6.5766e-07 compute to 2863.260 (not 2862.302086). The plan's must_haves used rounded inputs; the test uses the more precise inputs with matching expected output.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Updated regime_dependent tests to use 4-arg interface**
- **Found during:** Task 2 (full test suite run)
- **Issue:** test_correlations.jl called rd.htc(Re, Pr) with 2 args; after regime_dependent's closure signature changed to 4-arg explicit, this caused MethodError
- **Fix:** Updated test calls to rd.htc(Re, Pr, T_bulk, T_wall) with representative temperature values
- **Files modified:** test/test_correlations.jl
- **Verification:** Full test suite passes, 0 failures
- **Committed in:** 8b67f99 (Task 2 commit)

**2. [Rule 1 - Bug] Corrected Gr test reference value**
- **Found during:** Task 1 verification
- **Issue:** Plan action specified expected Gr=2862.302086 for inputs (3.851798e-04, 9.81, 20.0, 0.00254, 6.5766e-07); actual computed value is 2863.260. The plan's must_haves used rounded inputs (3.85e-4, 6.58e-7) which give a different value.
- **Fix:** Updated test expected value to 2863.260 (and Ra accordingly) to match actual Julia computation
- **Files modified:** test/test_fluids.jl
- **Verification:** FLUID-02 and FLUID-03 tests pass
- **Committed in:** 1297571 (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (2 Rule 1 bugs)
**Impact on plan:** Both fixes corrected test-vs-implementation mismatches. No scope creep. Formula and logic are correct.

## Issues Encountered
- Gr reference value inconsistency in plan draft: must_haves section and action section used slightly different input precision, producing different expected values. Resolved by computing directly from the inputs specified in the action section.

## Next Phase Readiness
- Plan 02 (Elenbaas correlation) can proceed: beta_water is callable from MTK, Gr and Ra are available, HTC 4-arg interface is in place across all call sites
- elenbaas_nusselt and elenbaas_htc are already exported — Plan 02 only needs to implement and test the functions

---
*Phase: 21-fluid-properties-natural-convection*
*Completed: 2026-03-17*
