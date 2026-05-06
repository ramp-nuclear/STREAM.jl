---
phase: 06-gravity-validation
plan: 01
subsystem: simulation
tags: [julia, modelingtoolkit, gravity, steady-state, DAE, thermal-hydraulics]

# Dependency graph
requires:
  - phase: v0.1 foundation
    provides: Channel with g_acc parameter, Gravity component, build_loop, solve_steady
provides:
  - build_loop_vertical() in src/solvers.jl — vertical closed loop with Channel(g_acc) + Gravity(H)
  - GRAV-01 test: vertical loop mtkcompiles and solve_steady returns ReturnCode.Success
  - GRAV-02 test: gravity cancellation within 1% of horizontal reference loop
  - Correct Gravity wiring convention documented in code comments
affects:
  - NET phases (multi-branch networks with gravity)
  - Any phase requiring vertical loop topology

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Gravity wiring: connect ch.outlet->grav.outlet, grav.inlet->pump.inlet for return-leg descending flow
    - Gravity cancellation: Channel g_acc=9.80665 + Gravity H=L_ch gives net-zero gravity effect

key-files:
  created: []
  modified:
    - src/solvers.jl
    - src/STREAM.jl
    - test/runtests.jl

key-decisions:
  - "Gravity wiring must be reversed from flow direction: grav.inlet at bottom (pump inlet), grav.outlet at top (channel outlet) — not in flow order — because inlet.P > outlet.P in Gravity equation means inlet is the high-pressure bottom end"
  - "Cancellation tolerance 1% (rtol=0.01) accounts for density evaluation at different temperatures (Channel uses T[i_mid], Gravity uses T_in)"

patterns-established:
  - "Vertical loop pattern: Channel(g_acc=9.80665) for upward leg + Gravity(H=L_ch) wired in reverse for downward return leg"

requirements-completed: [GRAV-01, GRAV-02]

# Metrics
duration: 9min
completed: 2026-03-13
---

# Phase 6 Plan 01: Gravity Validation Summary

**Closed-loop gravity validation via Channel(g_acc=9.80665) + Gravity(H=L_ch) with reversed port wiring proving hydrostatic cancellation within 1%**

## Performance

- **Duration:** 9 min
- **Started:** 2026-03-13T12:33:00Z
- **Completed:** 2026-03-13T12:42:06Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- `build_loop_vertical()` added to `src/solvers.jl`: assembles Channel(g_acc=9.80665) + Gravity(H) in a vertical closed loop, mtkcompiles to 11 equations / 11 unknowns
- GRAV-01 test passes: vertical loop mtkcompiles and solve_steady returns ReturnCode.Success with positive mdot
- GRAV-02 test passes: gravity cancellation loop (g_acc=9.80665, H_return=L_ch) matches horizontal reference mdot within 1%
- Discovered and fixed incorrect Gravity port wiring (Rule 1 bug fix — Gravity was adding to losses instead of cancelling them)
- All 58 tests pass (54 existing + 4 new Phase 6 tests), zero regressions

## Task Commits

Each task was committed atomically:

1. **Task 1: Add build_loop_vertical to solvers.jl** - `15274d4` (feat)
2. **Task 2: Add GRAV-01 and GRAV-02 tests to runtests.jl** - `8c48067` (feat, includes bug fix for Gravity wiring)

**Plan metadata:** (docs commit — see below)

_Note: Task 2 includes the Rule 1 auto-fix for the Gravity wiring bug discovered during TDD verification._

## Files Created/Modified

- `src/solvers.jl` — Added `build_loop_vertical()` function (67 lines including docblock)
- `src/STREAM.jl` — Added `build_loop_vertical` to export list
- `test/runtests.jl` — Added `build_loop_vertical` to import line; appended Phase 6 test block (GRAV-01 + GRAV-02)

## Decisions Made

- **Gravity port wiring convention**: Gravity's equation is `inlet.P - outlet.P ~ rho*g*H`, so `inlet` is the high-pressure bottom end. For the return leg (fluid descends from channel top to pump inlet), the correct wiring is `ch.outlet -> grav.outlet` (top, low pressure) and `grav.inlet -> pump.inlet` (bottom, high pressure) — reverse of the naive flow-direction wiring. Loop balance becomes `dP_pump = friction + rho*g*L_ch - rho*g*H`, giving cancellation at H = L_ch.

- **1% cancellation tolerance**: The Channel dP uses `rho_water(T[i_mid])` (midpoint temperature) while Gravity uses `rho_water(T_in)` (inlet temperature). These differ slightly, so exact machine-precision cancellation is not expected. The 1% rtol is physically justified and the test passes comfortably.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Reversed Gravity port wiring for correct physics**

- **Found during:** Task 2 (GRAV-02 test execution)
- **Issue:** Initial implementation wired Gravity in naive flow direction (`ch.outlet -> grav.inlet`, `grav.outlet -> pump.inlet`). This caused Gravity to ADD pressure loss (same direction as Channel), giving mdot_vertical = 0.459 vs mdot_horizontal = 0.607 (24% difference) instead of cancellation.
- **Root cause:** Gravity equation `inlet.P - outlet.P ~ rho*g*H` means inlet is the HIGH-pressure bottom. Wiring in flow direction for the descending return leg puts the low-pressure top at inlet, making Gravity act as an additional sink.
- **Fix:** Reversed connection: `connect(ch.outlet, grav.outlet)` and `connect(grav.inlet, pump.inlet)`. Loop balance: `dP_pump = friction + rho*g*L_ch - rho*g*H`, cancelling at H = L_ch.
- **Files modified:** src/solvers.jl
- **Verification:** GRAV-02 passes with mdot cancellation well within 1% rtol
- **Committed in:** 8c48067 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - Bug)
**Impact on plan:** Auto-fix was necessary for correct physics. The plan's interface documentation actually hinted at this ambiguity but concluded "let MTK sort out signs" — the fix resolves the ambiguity definitively.

## Issues Encountered

The plan's context section contained extensive analysis of the Gravity wiring ambiguity and concluded with "connect in flow direction, MTK will handle sign bookkeeping." This turned out to be incorrect — the physical sign must be handled by the caller (port connection order), not MTK. Documented the correct convention in code comments for future reference.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- GRAV-01 and GRAV-02 requirements satisfied; vertical loop topology validated end-to-end
- Gravity wiring convention established and documented — future phases using Gravity components should follow the same reversed-wiring pattern for descending return legs
- Phase 6 has 1 plan; if complete, v0.2 Phase 6 is done

---
*Phase: 06-gravity-validation*
*Completed: 2026-03-13*

## Self-Check: PASSED

- src/solvers.jl: FOUND
- src/STREAM.jl: FOUND
- test/runtests.jl: FOUND
- Commit 15274d4: FOUND
- Commit 8c48067: FOUND
- All 58 tests pass (verified via Pkg.test())
