---
phase: 04-tech-debt-cleanup
plan: "01"
subsystem: components
tags: [julia, modelingtoolkit, tech-debt, bugfix, parameter-rename, test-cleanup]

# Dependency graph
requires:
  - phase: 03-integration-and-validation
    plan: "03"
    provides: "54-test baseline, validated build_loop topology, 03-03-SUMMARY.md"
provides:
  - "src/components.jl: Gravity BUG-01 fixed (H MTK param not Julia kwarg), Channel/Friction param renames"
  - "src/solvers.jl: BUG-02 solve_steady docstring corrected (no stale fr.* references)"
  - "test/runtests.jl: COMP-04 test updated for new Gravity(H=...) signature"
  - "Deleted stale TDD test files: test_comp_tdd.jl, test_transient_tdd.jl, test_solvers_tdd.jl"
  - "03-03-SUMMARY.md frontmatter: requirements-completed field added"
  - "All 54 tests still green after cleanup"
affects: [phase-05-validation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "MTK parameter H declared as @parameters H = H so equation body references symbolic H not Julia Float64 kwarg"
    - "Channel and Friction MTK param names now match Python STREAM convention (L, A not L_ch, A_ch, L_f, A_f)"

key-files:
  created: []
  modified:
    - "src/components.jl — Gravity BUG-01 fix, Channel L/A rename, Friction L/A rename"
    - "src/solvers.jl — BUG-02 docstring fix (remove stale ssys.fr.* lines)"
    - "test/runtests.jl — COMP-04 Gravity test updated to Gravity(H=3.0)"
    - ".planning/phases/03-integration-and-validation/03-03-SUMMARY.md — requirements-completed added"
  deleted:
    - "test/test_comp_tdd.jl"
    - "test/test_transient_tdd.jl"
    - "test/test_solvers_tdd.jl"

key-decisions:
  - "Gravity @parameters H = H: single-parameter form shadows Julia Float64 kwarg in equation scope — confirmed correct MTK behavior"
  - "Parameter renames (L_ch→L, A_ch→A, L_f→L, A_f→A) are safe: equation bodies use Julia locals not MTK param names"
  - "Stale TDD files (test_comp_tdd.jl, test_transient_tdd.jl, test_solvers_tdd.jl) deleted — not in runtests.jl, crash if run directly"

requirements-completed: []

# Metrics
duration: 4min
completed: 2026-03-12
---

# Phase 4 Plan 01: Tech Debt Cleanup Summary

**v0.1 audit resolved: Gravity MTK BUG-01 fixed (H symbolic param), Channel/Friction param renames to L/A, solve_steady docstring BUG-02 corrected, three stale TDD files deleted — all 54 tests green**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-03-12T21:06:05Z
- **Completed:** 2026-03-12T21:10:00Z
- **Tasks:** 3
- **Files modified:** 4 modified + 3 deleted

## Accomplishments

- Fixed BUG-01: Gravity component now declares `@parameters H = H` so the pressure equation `rho_water(T_in) * 9.80665 * H` references the MTK symbolic parameter (modifiable via `setp` post-compilation), not the captured Julia Float64 kwarg
- Fixed BUG-02: Removed stale `ssys.fr.inlet.mdot` and `ssys.fr.Re` references from `solve_steady` docstring (Friction removed from build_loop in phase 3, commit 2e5ed5c)
- Renamed Channel `@parameters` `L_ch` → `L`, `A_ch` → `A` and Friction `@parameters` `L_f` → `L`, `A_f` → `A` to align MTK symbolic paths with Python STREAM convention
- Deleted three dead TDD scaffolding files (`test_comp_tdd.jl`, `test_transient_tdd.jl`, `test_solvers_tdd.jl`) that referenced the removed Friction component and were not included in `runtests.jl`
- Added `requirements-completed: [VAL-01, VAL-02, VAL-03]` to 03-03-SUMMARY.md frontmatter for GSD tooling
- Confirmed all 54 tests still pass after cleanup

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix components.jl BUG-01, param renames, COMP-04 test** - `8bfede0` (fix)
2. **Task 2: BUG-02 docstring fix, delete stale TDD files, SUMMARY frontmatter** - `1c9b1a6` (fix)
3. **Task 3: Config.json sync after test verification** - `350e62a` (chore)

## Files Created/Modified

- `/home/itay/projects/Julia-STREAM/src/components.jl` — Gravity: `A_grav` kwarg removed, `H_grav` → `@parameters H = H`; Channel: `L_ch` → `L`, `A_ch` → `A`; Friction: `L_f` → `L`, `A_f` → `A`
- `/home/itay/projects/Julia-STREAM/src/solvers.jl` — `solve_steady` docstring: replaced `ssys.fr.inlet.mdot` and `ssys.fr.Re` lines with `ssys.ch.inlet.mdot` reference
- `/home/itay/projects/Julia-STREAM/test/runtests.jl` — COMP-04 test: `Gravity(H=3.0, A_grav=7.85e-5)` → `Gravity(H=3.0)`
- `/home/itay/projects/Julia-STREAM/.planning/phases/03-integration-and-validation/03-03-SUMMARY.md` — Added `requirements-completed: [VAL-01, VAL-02, VAL-03]`
- **Deleted:** `test/test_comp_tdd.jl`, `test/test_transient_tdd.jl`, `test/test_solvers_tdd.jl`

## Decisions Made

1. **Gravity single-param form is correct MTK behavior**: In MTK, `@parameters H = H` creates symbolic `H` in the local scope; subsequent equation `9.80665 * H` resolves to the symbolic, not the captured Float64 kwarg. Verified by loading `STREAM` and calling `Gravity(; name=:g, H=1.0)` — construct succeeds cleanly.

2. **Parameter renames are equation-safe**: Channel and Friction equation bodies use Julia local variables (`L`, `A`, `Dh`, `D`) bound at function entry — these are unaffected by `@parameters` name changes. Only the MTK symbolic path (e.g., `ssys.ch.L` vs `ssys.ch.L_ch`) changes.

3. **Stale TDD files deleted, not archived**: All three files referenced the removed `Friction` component and would crash if run directly. Since they are excluded from `runtests.jl`, they provide no test coverage value — deletion is correct.

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None. All changes were straightforward targeted edits with no unexpected complications.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- src/components.jl is clean: no stale parameter names, Gravity BUG-01 resolved
- src/solvers.jl docstring is accurate
- test/ directory contains only active test files
- 54/54 tests pass — Phase 5 validation baseline is clean

---
*Phase: 04-tech-debt-cleanup*
*Completed: 2026-03-12*
