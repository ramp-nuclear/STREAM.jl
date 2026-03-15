---
phase: 14-laminar-correlations
plan: 02
subsystem: physics
tags: [julia, mtk, correlations, laminar, friction, nusselt, pluggable, channel]

# Dependency graph
requires:
  - phase: 14-01
    provides: correlations.jl with dittus_boelter, blasius_friction, constant_Nusselt, laminar_friction, regime_dependent
provides:
  - _channel_base_eqs accepts htc_correlation/friction_correlation kwargs (defaults to dittus_boelter/blasius_friction)
  - Channel, ChannelAndContacts, ChannelHeatFlux each accept and forward the two correlation kwargs
  - PHY-02 integration test: constant_Nusselt(Nu=8.235) in solved CAC system gives Nu≈8.235
  - PHY-03 integration test: laminar_friction plugged into CAC system; solver converges, Re<2300
  - PHY-04 integration tests: regime_dependent exercises laminar branch (Re<2300) and turbulent branch (Re>2300)
affects: [15-pump-mdot0, 16-composability-helpers]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Correlation pluggability: channel components accept (Re,Pr)->Nu and (Re)->f closures as kwargs with defaults"
    - "Laminar integration test pattern: dP=30Pa forces Re<<2300 without bifurcation issues"
    - "PHY-03 uses constant_Nusselt + laminar_friction together to isolate friction pluggability"

key-files:
  created: []
  modified:
    - src/components.jl
    - test/runtests.jl

key-decisions:
  - "Pr_i computed inline as cp*mu/k — a symbolic expression, NOT a new MTK variable"
  - "PHY-03 test pairs laminar_friction with constant_Nusselt (not dittus_boelter) to keep system well-conditioned at low Re"
  - "PHY-03 pump dP=30Pa with mdot initial guess 8.8e-4 kg/s from Hagen-Poiseuille estimate"
  - "PHY-04 laminar test uses same dP=30Pa approach as PHY-04-lam; turbulent at dP=30kPa standard MTR"

patterns-established:
  - "Pluggable correlation pattern: (Re, Pr) -> Nu and (Re) -> f closures; defaults preserve existing behavior"
  - "Integration test pattern for laminar regime: tiny dP pump + small mdot initial guess"

requirements-completed: [PHY-02, PHY-03, PHY-04]

# Metrics
duration: 11min
completed: 2026-03-15
---

# Phase 14 Plan 02: Laminar Correlations — Component Wiring Summary

**Channel components refactored to accept pluggable HTC/friction correlation closures; PHY-02/03/04 integration tests verify constant_Nusselt, laminar_friction, and regime_dependent in fully solved systems**

## Performance

- **Duration:** 11 min
- **Started:** 2026-03-15T09:24:04Z
- **Completed:** 2026-03-15T09:35:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Refactored `_channel_base_eqs`, `Channel`, `ChannelAndContacts`, and `ChannelHeatFlux` with 6 targeted edits to accept `htc_correlation`/`friction_correlation` kwargs (defaults: `dittus_boelter`/`blasius_friction`); zero regression in 151 prior tests
- Added 11 new integration tests (PHY-02/03/04 testsets) verifying correlations work end-to-end in fully solved systems including both laminar and turbulent regime branches of `regime_dependent`
- Total suite: 179 tests, all passing

## Task Commits

1. **Task 1: Refactor channel components to accept pluggable correlation kwargs** - `f1f84bc` (feat)
2. **Task 2: Add PHY-02/03/04 integration tests for pluggable correlations** - `8ee2a65` (test)

**Plan metadata:** (docs commit to follow)

## Files Created/Modified
- `/home/itay/projects/Julia-STREAM/src/components.jl` - 6 edits: `_channel_base_eqs` signature + Nu/f_ch replacement; `Channel` kwargs + inline replacements; `ChannelAndContacts` + `ChannelHeatFlux` kwargs and forwarding
- `/home/itay/projects/Julia-STREAM/test/runtests.jl` - 177 lines added: PHY-02 (constant_Nusselt integration), PHY-03 (laminar_friction integration at 30Pa), PHY-04 laminar branch, PHY-04 turbulent branch

## Decisions Made
- PHY-03 test pairs `laminar_friction` with `constant_Nusselt` (not `dittus_boelter`) to keep the system well-conditioned at low Re where Dittus-Boelter extrapolates poorly
- PHY-03 uses `dP_pump=30Pa` and `mdot=8.8e-4 kg/s` initial guess (from Hagen-Poiseuille estimate for MTR rectangular geometry at 30Pa, 313K)
- `Pr_i` computed inline as a symbolic expression (`cp_water(T[i]) * mu_water(T[i]) / k_water(T[i])`) — not a new MTK variable

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] PHY-03 initial approach failed to converge**
- **Found during:** Task 2 (PHY-03 integration test)
- **Issue:** Using circular geometry + Blasius initial guess (mdot=0.490) for a laminar_friction test caused KINSOL to diverge (5 consecutive step-length failures). The high-Re initial point is far from the laminar solution at 30Pa.
- **Fix:** Switched to MTR rectangular geometry (which K_R is calibrated for), paired `laminar_friction` with `constant_Nusselt` to decouple HTC conditioning, and used physics-based initial guess `mdot=8.8e-4` from Hagen-Poiseuille estimate.
- **Files modified:** test/runtests.jl
- **Verification:** Test passes with `retcode==Success`, `Re[1]<2300`, `dP>0`
- **Committed in:** 8ee2a65 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - convergence bug in test design)
**Impact on plan:** Required redesigning the PHY-03 test approach. Plan intent (laminar_friction pluggable in solved system) fully achieved; test design is now more physically principled.

## Issues Encountered
- KINSOL convergence with `laminar_friction` at 30Pa required careful initial guess selection; solved by physics-based estimate from Hagen-Poiseuille formula for rectangular duct

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All three correlation types (constant, laminar, regime-switching) are wired into the channel components and verified in solved systems
- Phase 15 (if it exists) can use pluggable correlations in any channel component
- Ready for composability helpers (symmetric_plate, plate, compose_systems) in v0.4

---
*Phase: 14-laminar-correlations*
*Completed: 2026-03-15*

## Self-Check: PASSED

- FOUND: /home/itay/projects/Julia-STREAM/.planning/phases/14-laminar-correlations/14-02-SUMMARY.md
- FOUND: commit f1f84bc (feat(14-02): refactor channel components)
- FOUND: commit 8ee2a65 (test(14-02): add PHY-02/03/04 integration tests)
- FOUND: commit 2266b6c (docs(14-02): final metadata commit)
- All 179 tests pass: `julia --project=. -e "include(\"test/runtests.jl\")"` — no failures
