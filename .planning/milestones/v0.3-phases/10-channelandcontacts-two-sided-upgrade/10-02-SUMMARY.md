---
phase: 10-channelandcontacts-two-sided-upgrade
plan: "02"
subsystem: thermal-hydraulics
tags: [julia, modelingtoolkit, tdd, thermal-ports, two-sided-heating, ChannelAndContacts, THERM-03, CHAN-03]

# Dependency graph
requires:
  - phase: 10-channelandcontacts-two-sided-upgrade
    provides: "Plan 01: ChannelAndContacts dual thermal_left/right ports, ConstantTemperature boundary component"
provides:
  - THERM-01 updated to loop over i in 1:5 for both thermal_left and thermal_right port assertions
  - THERM-03 rewritten as two-sided CAC vs ChannelHeatFlux comparison (DEBT-02 cleared)
  - CHAN-03 testset verifying unconnected thermal_right has Q_flow==0 at steady state
  - ChannelAndContacts port Q_flow equations (thermal_left/right.Q_flow ~ h_tc*...) added to fix underdetermined system
  - Full test suite green: 102 tests all passing
affects:
  - 11-heatdiffusion (interface contract fully validated by test suite)
  - 12-mtr-validation (depends on correct ChannelAndContacts behavior)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "MTK port array access in connections: use getproperty(sys, Symbol(:thermal_left, i)) not sys.thermal_left[i]"
    - "ThermalPort Q_flow equations required: thermal.Q_flow ~ h_tc*(pi*Dh/2)*dz*(T_wall - T[i]) for proper acausal wiring"
    - "Two-sided CAC validation pattern: connect both thermal_left and thermal_right to same T_wall with same D; sum recovers full CHF perimeter"
    - "CHAN-03 adiabatic pattern: unconnected MTK Flow variable defaults to 0; getproperty(ssys.cac, Symbol(:thermal_right, i)).Q_flow extracts per-port result"

key-files:
  created:
    - .planning/phases/10-channelandcontacts-two-sided-upgrade/10-02-SUMMARY.md
  modified:
    - test/runtests.jl
    - src/components.jl

key-decisions:
  - "THERM-03 uses two-sided CAC (both left+right connected) vs CHF with same D=0.01 — equalizes h_tc and heated perimeter for clean 0.1% match"
  - "One-sided (D_cac=2*D_chf) approach from plan fails: h_tc depends on Dh via Re and Nu; different D gives different h_tc breaking the 0.1% tolerance"
  - "ChannelAndContacts port Q_flow equations added: thermal_left/right.Q_flow ~ h_tc*(pi*Dh/2)*dz*(T-T[i]) — without these the system was underdetermined when right side unconnected"
  - "MTK array port access: sys.thermal_left[i] fails at connection time; use getproperty(sys, Symbol(:thermal_left, i)) for named subsystem access"
  - "CHAN-03 uses named subsystem fallback: getproperty(ssys.cac2, Symbol(:thermal_right, i)) — works with current MTK version"

patterns-established:
  - "Port Q_flow definition pattern: every ThermalPort in an acausal component must have an equation defining Q_flow in terms of heat transfer; without it the system is underdetermined when port is unconnected"
  - "Two-sided CAC equivalence: both sides at T_wall with D_cac=D_chf gives h_tc*(pi*D_cac/2)*2 = h_tc*(pi*D_chf) — exact CHF equivalence"

requirements-completed: [DEBT-02, CHAN-03]

# Metrics
duration: 22min
completed: 2026-03-13
---

# Phase 10 Plan 02: Test Suite Update for Two-Sided ChannelAndContacts Summary

**THERM-01 loop assertion updated to n=5, THERM-03 rewritten as two-sided CAC vs CHF validation (DEBT-02), CHAN-03 added confirming adiabatic right-side default, and ChannelAndContacts port Q_flow equations fixed for proper acausal wiring**

## Performance

- **Duration:** ~22 min
- **Started:** 2026-03-13T22:35:06Z
- **Completed:** 2026-03-13T22:57:45Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- THERM-01 updated: replaced manual n=2 enumeration with loop over i in 1:5, verifying both `thermal_left_i` and `thermal_right_i` in subsys_names; asserts old `Symbol(:thermal, 1)` absent
- THERM-03 rewritten: two-sided CAC (both left+right connected to ConstantTemperature at T_wall) vs ChannelHeatFlux with same D=0.01; T_outlet matches within 0.1% — DEBT-02 cleared
- CHAN-03 added: n=5 one-sided CAC (thermal_left connected, thermal_right free); asserts `thermal_right_i.Q_flow == 0.0` (atol=1e-8) for all i — adiabatic default confirmed
- ChannelAndContacts bug fixed: added `thermal_left[i].Q_flow ~ h_tc*(pi*Dh/2)*dz*(T_left-T[i])` and `thermal_right[i].Q_flow ~ ...` equations; without these the system was underdetermined when a port was unconnected
- All 102 tests pass (up from 97 in Plan 01)

## Task Commits

Each task was committed atomically:

1. **Task 1: Update THERM-01 port name assertions** - `19b238a` (test)
2. **Task 2: Rewrite THERM-03 as CAC-vs-CHF and add CHAN-03 adiabatic test** - `b2fbea8` (feat)

## Files Created/Modified
- `test/runtests.jl` - THERM-01 loop updated; THERM-03 replaced with two-sided CAC vs CHF; CHAN-03 adiabatic testset added; ConstantTemperature added to top-level import
- `src/components.jl` - ChannelAndContacts: added port Q_flow equations for thermal_left and thermal_right (auto-fix for underdetermined system)

## Decisions Made
- **Two-sided vs one-sided THERM-03:** Plan specified one-sided CAC (D_cac=2*D_chf) vs CHF. This fails the 0.1% criterion because h_tc depends on Dh; with D_cac=2*D_chf, Re_cac=2*Re_chf, Nu_cac≈1.74*Nu_chf, h_tc_cac≈0.87*h_tc_chf, giving ~0.76% T_outlet difference. Switched to two-sided CAC with same D: h_tc*(pi*D/2)*2 = h_tc*(pi*D), exactly matching CHF. The one-sided test of the ENERGY BALANCE is replaced by a two-sided test that achieves the same validation goal (DEBT-02). CHAN-03 separately validates the adiabatic right side.
- **Port Q_flow equations:** ChannelAndContacts was missing `thermal_right[i].Q_flow ~ h_tc*(pi*Dh/2)*dz*(T_right-T[i])` equations. Without these, the unconnected right-side port's T was a free variable, making the system underdetermined. Adding these equations allows MTK to use the Flow variable default (0 when unconnected) to infer `T_right = T[i]` (adiabatic).
- **MTK port array access:** `cac.thermal_left[i]` in connect() calls fails with "variable thermal_left does not exist". Correct pattern: `getproperty(cac, Symbol(:thermal_left, i))`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] ChannelAndContacts missing port Q_flow equations**
- **Found during:** Task 2 (THERM-03 rewrite)
- **Issue:** `mtkcompile` raised `ExtraVariablesSystemException` (117 vars, 97 eqs) when thermal_right was unconnected. Root cause: no equation in ChannelAndContacts defining `thermal_right[i].Q_flow` in terms of heat transfer. The energy balance used `thermal_right[i].T` but never constrained `thermal_right[i].Q_flow`, leaving both T and Q_flow of unconnected right ports free.
- **Fix:** Added `thermal_left[i].Q_flow ~ h_tc[i]*(π*Dh/2)*dz*(thermal_left[i].T - T[i])` and `thermal_right[i].Q_flow ~ h_tc[i]*(π*Dh/2)*dz*(thermal_right[i].T - T[i])` per-cell equations. With Q_flow constrained by MTK Flow default (0 when unconnected), T_right is then determined as T[i] (adiabatic).
- **Files modified:** src/components.jl
- **Verification:** CHAN-03 passes (Q_flow == 0 for all 5 right ports), THERM-03 passes
- **Committed in:** b2fbea8 (Task 2 commit)

**2. [Rule 3 - Blocking] Plan's THERM-03 geometry assumption physically incorrect**
- **Found during:** Task 2 (THERM-03 verification)
- **Issue:** Plan specified D_cac=2*D_chf to equalize heated perimeter. This is geometrically correct but physically incorrect: Dh changes h_tc via Re=mdot*Dh/(A*mu) and Nu. With D_cac=0.02 vs D_chf=0.01: h_tc_cac ≈ 0.87*h_tc_chf, giving 0.76% T_outlet mismatch (10x over the 0.1% limit).
- **Fix:** Changed THERM-03 to two-sided CAC (both thermal_left and thermal_right connected to T_wall) with D_cac=D_chf=0.01. Same D ensures identical h_tc; both sides sum to π*D = CHF's full perimeter. T_outlet matches within solver precision (<0.1%).
- **Files modified:** test/runtests.jl
- **Verification:** THERM-03 passes with rtol=1e-3
- **Committed in:** b2fbea8 (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (1 Bug, 1 Blocking)
**Impact on plan:** Both auto-fixes required for correctness. Bug fix ensures ChannelAndContacts is properly specified as an acausal component. Geometry fix changes THERM-03 from one-sided to two-sided validation — preserves DEBT-02 intent (direct CAC validation) while using physically correct geometry. CHAN-03 fills the one-sided validation role. No scope creep.

## Issues Encountered
- MTK array port indexing (`cac.thermal_left[i]` in connect()) fails — must use `getproperty(cac, Symbol(:thermal_left, i))`. This is consistent with the MTK design where ports are named subsystems, not indexable arrays at the Julia level.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All Phase 10 requirements satisfied: DEBT-01 (10-01), DEBT-02 (THERM-03 rewritten), DEBT-03 (10-01), CHAN-01 (10-01), CHAN-02 (10-01), CHAN-03 (this plan)
- Interface contract locked: thermal_left[1:n] and thermal_right[1:n] validated end-to-end; Q_flow equations confirmed correct
- ChannelAndContacts properly specified as acausal MTK component (port Q_flow equations present)
- Phase 11 (HeatDiffusion) can connect to the dual port arrays with confidence
- Known MTK access pattern: use `getproperty(sys, Symbol(:thermal_left, i))` for connection wiring

## Self-Check: PASSED

- FOUND: .planning/phases/10-channelandcontacts-two-sided-upgrade/10-02-SUMMARY.md
- FOUND: test/runtests.jl
- FOUND: src/components.jl
- FOUND commit: 19b238a (test(10-02): update THERM-01)
- FOUND commit: b2fbea8 (feat(10-02): rewrite THERM-03 and add CHAN-03)

---
*Phase: 10-channelandcontacts-two-sided-upgrade*
*Completed: 2026-03-13*
