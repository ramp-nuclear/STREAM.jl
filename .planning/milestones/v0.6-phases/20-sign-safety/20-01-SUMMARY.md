---
phase: 20-sign-safety
plan: "01"
subsystem: components
tags: [mtk, ifelse, upwinding, flow-reversal, channel, thermal-channel]

# Dependency graph
requires:
  - phase: 19-docstrings-polish
    provides: finalized channel.jl and thermal_channel.jl source files
provides:
  - ifelse() upwinding in Channel, ChannelAndContacts, and ChannelHeatFlux energy loops
  - inlet.T ~ T[1] in Channel constructor and _channel_base_eqs
  - unsigned velocity[i] observable in ChannelAndContacts
affects: [20-sign-safety, 21-flapper-valve, test_sign_safety]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Bidirectional upwind: T_inlet_fwd/T_inlet_rev declared before loop, ifelse(mdot>=0) per-cell"
    - "inlet.T ~ T[1] as outflow equation (not instream(outlet.T))"

key-files:
  created: []
  modified:
    - src/components/channel.jl
    - src/components/thermal_channel.jl

key-decisions:
  - "ifelse(inlet.mdot >= 0, T_up_fwd, T_up_rev) — same MTK ifelse idiom already used in dP formula and regime_dependent"
  - "inlet.T ~ T[1] replaces inlet.T ~ instream(outlet.T) — T[1] is the correct MTK outflow temperature for inlet"
  - "_channel_base_eqs inlet.T fix propagates to ChannelAndContacts and ChannelHeatFlux automatically; Channel has its own copy and was fixed separately"
  - "velocity[i] changed to abs(mdot)/(rho*A) (speed magnitude); v[i] stays signed as intended"

patterns-established:
  - "Pattern: Per-cell bidirectional upwind — declare T_inlet_fwd/T_inlet_rev before loop, compute T_up_fwd/T_up_rev inside loop, select with ifelse"

requirements-completed: [SIGN-01, SIGN-02, SIGN-03]

# Metrics
duration: 2min
completed: 2026-03-17
---

# Phase 20 Plan 01: Sign Safety — Source Fixes Summary

**ifelse() bidirectional upwinding and inlet.T ~ T[1] fix applied to all three channel variants (Channel, ChannelAndContacts, ChannelHeatFlux)**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-03-17T13:04:12Z
- **Completed:** 2026-03-17T13:06:15Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Fixed forward-only upwind formula in all three channel constructors — energy balance now selects upstream temperature based on mdot sign via ifelse()
- Fixed inlet.T stream equation in Channel constructor and _channel_base_eqs — replaced wrong instream(outlet.T) with correct T[1]
- Fixed velocity[i] observed variable in ChannelAndContacts to use abs(mdot) (unsigned speed magnitude)
- Package loads clean after all changes (precompilation successful)

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix Channel constructor and _channel_base_eqs in channel.jl** - `c23c0b0` (fix)
2. **Task 2: Fix ChannelAndContacts and ChannelHeatFlux in thermal_channel.jl** - `84f7f39` (fix)

**Plan metadata:** (docs commit follows)

## Files Created/Modified
- `src/components/channel.jl` - Renamed T_inlet to T_inlet_fwd, added T_inlet_rev; added ifelse() upwinding loop in Channel; fixed inlet.T in Channel constructor (line 94) and _channel_base_eqs (line 159)
- `src/components/thermal_channel.jl` - Added T_inlet_fwd/T_inlet_rev + ifelse() upwinding in ChannelAndContacts energy loop; same in ChannelHeatFlux energy loop; changed velocity[i] obs to abs(mdot)

## Decisions Made
- Used ifelse(inlet.mdot >= 0, T_up_fwd, T_up_rev) per-cell — consistent with existing dP formula pattern `mdot * abs(mdot)` and regime_dependent correlation switcher; avoids tanh blend tuning parameters
- inlet.T ~ T[1]: outflow from this component through inlet is at T[1] (first cell temperature); the old instream(outlet.T) equation was silent under forward flow (zero weight) but wrong under reverse flow
- No changes to _channel_base_eqs energy balance — it contains none; upwinding belongs in each constructor's own energy loop

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Source fixes complete for SIGN-01, SIGN-02, SIGN-03
- Plan 20-02 can now add test_sign_safety.jl to validate the fixes with actual negative-mdot simulations (SIGN-04)

---
*Phase: 20-sign-safety*
*Completed: 2026-03-17*
