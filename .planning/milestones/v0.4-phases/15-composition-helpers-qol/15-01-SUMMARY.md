---
phase: 15-composition-helpers-qol
plan: 01
subsystem: components
tags: [julia, mtk, modelingtoolkit, observed-variables, qol, helpers]

# Dependency graph
requires:
  - phase: 14-laminar-correlations
    provides: ChannelAndContacts with pluggable htc/friction correlations; PHY-02/03/04 passing
provides:
  - ChannelAndContacts with observed= kwarg exposing Re, Nu, velocity, Pe, h_tc_left/right, T_wall_left/right, q_wall_left/right (10 new observed variables)
  - src/helpers.jl with port() and check_gravity_mismatch() QoL helpers
  - Wave 0 test stubs for COMP-01/02/03/04 (pending 15-02-PLAN.md)
  - STREAM exports: check_gravity_mismatch, port
affects:
  - 15-02-composition-helpers-qol (plan 02 adds composition helpers to helpers.jl)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "MTK observed= kwarg for non-solver diagnostic variables: pass Equation[] vector to System constructor"
    - "Observed-chain avoidance: h_tc inlined without Nu MTK symbol reference"
    - "_channel_base_eqs observed_mode flag: skip Re/Nu/v push! when caller builds obs vector"
    - "Port helper: getproperty(sys, Symbol(face, i)) is the correct MTK indexed-port syntax"
    - "Parameter inspection in helpers: local_name() extracts suffix after ₊ separator"

key-files:
  created:
    - src/helpers.jl
  modified:
    - src/components.jl
    - src/STREAM.jl
    - test/runtests.jl

key-decisions:
  - "Re/Nu/v moved from all_vars to observed= in ChannelAndContacts; h_tc stays as unknown (referenced by energy balance)"
  - "h_tc equation inlined in observed_mode to avoid MTK observed-chain resolution issues with Nu"
  - "Simpler approach chosen: build obs vector in ChannelAndContacts body, not inside _channel_base_eqs"
  - "check_gravity_mismatch uses parameter inspection (H and g_acc defaults) not symbolic substitution — sufficient for balanced loop detection"
  - "QOL-03 test uses nameof() equivalence not === identity — MTK getproperty returns equivalent but not identical objects"
  - "QOL-01 test uses rectangular geometry (dP=3e4, T=313K) matching PHY-04 setup for reliable convergence"

patterns-established:
  - "observed_mode flag in shared _channel_base_eqs: backward-compatible opt-in for observed refactor"
  - "Wave 0 stubs as @test false broken=true: Nyquist compliance before implementation"

requirements-completed: [QOL-01, QOL-02, QOL-03]

# Metrics
duration: 46min
completed: 2026-03-15
---

# Phase 15 Plan 01: QoL Observed Variables and Helpers Summary

**ChannelAndContacts gains 10 MTK @observed variables (Re, Nu, velocity, Pe, h_tc_left/right, T_wall_left/right, q_wall_left/right) via observed= kwarg; new src/helpers.jl adds port() and check_gravity_mismatch() QoL helpers**

## Performance

- **Duration:** 46 min
- **Started:** 2026-03-15T17:04:38Z
- **Completed:** 2026-03-15T17:50:38Z
- **Tasks:** 3
- **Files modified:** 4 (components.jl, STREAM.jl, helpers.jl created, runtests.jl)

## Accomplishments
- Refactored ChannelAndContacts to expose Re, Nu, velocity, Pe, h_tc_left/right, T_wall_left/right, q_wall_left/right as MTK @observed variables — solver unknown vector reduced (Re/Nu/v removed)
- Created src/helpers.jl with port() (indexed port access) and check_gravity_mismatch() (gravity balance validation)
- Wave 0 stubs added for COMP-01/02/03/04 (pending plan 02); QOL-01/02/03 fully green

## Task Commits

Each task was committed atomically:

1. **Task 1: Wave 0 test stubs for QOL-01/02/03 and COMP-01/02/03/04** - `a8e53ee` (test)
2. **Task 2: Refactor ChannelAndContacts — Re/Nu/v to @observed + 8 new observed variables** - `e440838` (feat)
3. **Task 3: Create helpers.jl with port() and check_gravity_mismatch(); wire QOL tests green** - `a79310f` (feat)

**Plan metadata:** (this commit)

## Files Created/Modified
- `/home/itay/projects/Julia-STREAM/src/components.jl` - ChannelAndContacts refactored with observed= kwarg; _channel_base_eqs gains observed_mode flag; 10 new @variables declared
- `/home/itay/projects/Julia-STREAM/src/helpers.jl` - New file: port() and check_gravity_mismatch() QoL helpers
- `/home/itay/projects/Julia-STREAM/src/STREAM.jl` - include helpers.jl; export check_gravity_mismatch, port
- `/home/itay/projects/Julia-STREAM/test/runtests.jl` - 7 new testsets (QOL-01/02/03 green, COMP-01/02/03/04 Broken stubs)

## Decisions Made
- Re/Nu/v removed from all_vars (solver unknowns); h_tc stays unknown — energy balance references h_tc directly
- h_tc equation inlined (no Nu MTK symbol) to avoid MTK observed-chain resolution issue
- obs vector built in ChannelAndContacts body (not inside _channel_base_eqs) for cleaner separation
- check_gravity_mismatch inspects parameter defaults: finds H (Gravity component) and g_acc (channel) params; returns :mismatch if g_acc > 0 but no H param found
- QOL-03 test uses nameof() equivalence instead of === identity (MTK getproperty doesn't guarantee object identity)
- QOL-01 test uses rectangular geometry/dP=3e4/T=313K (same as PHY-04 turbulent) for reliable solver convergence

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] PipeGeometry_circular called with keyword args in plan's test stub template**
- **Found during:** Task 1 (writing test stubs)
- **Issue:** Plan template showed `PipeGeometry_circular(D=0.01, L=0.6)` but the API is positional `PipeGeometry_circular(L, D)`
- **Fix:** Used correct positional call `PipeGeometry_circular(0.6, 0.01)` in test bodies
- **Files modified:** test/runtests.jl
- **Verification:** Test runs without MethodError
- **Committed in:** a79310f

**2. [Rule 1 - Bug] @test_broken true caused Unexpected Pass error for COMP stubs**
- **Found during:** Task 1 (first test run)
- **Issue:** Plan suggested `@test_broken true` for COMP stubs, but `true` always passes → "Unexpected Pass" error in Julia Test
- **Fix:** Changed to `@test false broken=true` which correctly shows as Broken
- **Files modified:** test/runtests.jl
- **Verification:** COMP stubs show as Broken in test output
- **Committed in:** a8e53ee

**3. [Rule 1 - Bug] Solution indexing with `, end` fails for NonlinearSolution**
- **Found during:** Task 3 (QOL-01 test debugging)
- **Issue:** `sol[ssys.ch.Re[1], end]` syntax is for ODE time-series; NonlinearSolution from solve_steady uses `sol[ssys.ch.Re[1]]`
- **Fix:** Removed `, end` from all solution indexing in QOL-01 test
- **Files modified:** test/runtests.jl
- **Verification:** All 12 QOL-01 assertions pass
- **Committed in:** a79310f

**4. [Rule 1 - Bug] QOL-01 test with dP=1e4 and T=600K produced NaN solution**
- **Found during:** Task 3 (QOL-01 test debugging)
- **Issue:** Initial test setup (circular pipe, T=600K, dP=1e4) didn't converge — solver returned NaN with retcode=Success
- **Fix:** Switched to rectangular geometry matching PHY-04 turbulent test (T=313K, dP=3e4, mdot=0.25) which is a known-working convergent case
- **Files modified:** test/runtests.jl
- **Verification:** sol.u is non-NaN; Re[1] > 2300, all 12 assertions pass
- **Committed in:** a79310f

---

**Total deviations:** 4 auto-fixed (all Rule 1 — bugs in test body templates or incorrect assumptions)
**Impact on plan:** All auto-fixes were test/fixture corrections; no production code logic was changed beyond what was planned.

## Issues Encountered
- MTK compiled systems flatten parameter names with ₊ prefix (e.g., `grav₊H` not `H`). check_gravity_mismatch required a local_name() helper to strip the prefix before matching
- `===` identity check fails for MTK subsystems returned by getproperty (they are re-created on each call); switched QOL-03 to `nameof()` equivalence

## Next Phase Readiness
- 15-02-PLAN.md can proceed immediately: helpers.jl has structure with clear section comment for composition helpers
- COMP-01/02/03/04 stubs are in place as @test false broken=true (will turn green after 15-02 implements symmetric_plate, plate, one_sided_connection, compose_systems)
- All 142 prior tests pass (regression-clean)

---
*Phase: 15-composition-helpers-qol*
*Completed: 2026-03-15*
