---
phase: 14-laminar-correlations
plan: "01"
subsystem: physics
tags: [correlations, heat-transfer, friction, laminar, turbulent, regime-switching, MTK]

# Dependency graph
requires:
  - phase: 12.1-pipegeometry
    provides: PipeGeometry factory constructors and struct
  - phase: 13-physics-foundation
    provides: Dh fix, correct wet_perimeter, MTK-compatible fluid properties
provides:
  - src/correlations.jl with six correlation functions/factories
  - PipeGeometry width/depth fields for aspect_ratio derivation
  - dittus_boelter, blasius_friction as named standalone functions
  - constant_Nusselt factory returning (Re, Pr) -> Nu constant
  - laminar_friction factory using KAERI rectangular_laminar_correction
  - regime_dependent factory with ifelse() laminar/turbulent switching
affects:
  - 14-02 (Plan 02): channels will consume htc_correlation/friction_correlation kwargs

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Correlation factory pattern: construction-time scalars captured in closure, inner fn takes symbolic Re/Pr"
    - "ifelse() for MTK-compatible regime switching (established pattern from flow reversal)"
    - "Named standalone functions as default kwarg values (dittus_boelter, blasius_friction)"
    - "correlations.jl included before components.jl so defaults are in scope"

key-files:
  created:
    - src/correlations.jl
  modified:
    - src/components.jl
    - src/STREAM.jl
    - test/runtests.jl

key-decisions:
  - "No @register_symbolic on correlation functions — plain arithmetic; MTK traces symbolically"
  - "laminar_friction aspect_ratio kwarg is REQUIRED (no default) — callers must be explicit"
  - "Re_transition converted to Float64 immediately in regime_dependent — avoids Int/Symbolic type promotion error"
  - "constant_Nusselt returns plain (Re, Pr) -> Nu closure — Nu constant in Nu[i]~8.235 is valid MTK algebraic eq"
  - "circular Dh formula K_R(1.0) ≈ 1.1246 means laminar_friction(aspect_ratio=1.0) gives ~56.9/Re, not 64/Re"

patterns-established:
  - "Factory pattern: capture geometry correction at construction time, expose (Re) or (Re,Pr) interface"
  - "Correlation pluggability: all channel variants will accept htc_correlation/friction_correlation kwargs"

requirements-completed: [PHY-02, PHY-03, PHY-04]

# Metrics
duration: 18min
completed: 2026-03-15
---

# Phase 14 Plan 01: Laminar Correlations Summary

**Six pluggable HTC/friction correlation functions extracted into src/correlations.jl with KAERI rectangular_laminar_correction (K_R(0.01814)=0.68544), regime_dependent ifelse() switching, and PipeGeometry width/depth fields for aspect_ratio derivation.**

## Performance

- **Duration:** ~18 min
- **Started:** 2026-03-15T00:00:00Z
- **Completed:** 2026-03-15T00:18:00Z
- **Tasks:** 2
- **Files modified:** 4 (created 1)

## Accomplishments
- Created `src/correlations.jl` with all six public functions/factories (dittus_boelter, blasius_friction, rectangular_laminar_correction, constant_Nusselt, laminar_friction, regime_dependent)
- Verified rectangular_laminar_correction against Python STREAM reference values (4 aspect ratios, all within 1e-4)
- Extended PipeGeometry struct with `width` and `depth` fields; both factory constructors updated (rect: max/min of edges; circ: D)
- Wired correlations.jl into STREAM.jl (include before components.jl, 6 new exports)
- Added 17 PHY-02/03/04 tests; full suite green (160 tests, no failures)

## Task Commits

Each task was committed atomically:

1. **TDD RED: PHY correlation tests (failing)** - `70d3a82` (test)
2. **Task 1: Create src/correlations.jl + wire STREAM.jl** - `f2407c9` (feat)
3. **Task 2: PipeGeometry width/depth extension** - `4c892bf` (feat)

## Files Created/Modified
- `/home/itay/projects/Julia-STREAM/src/correlations.jl` — New file: six correlation functions/factories with docstrings
- `/home/itay/projects/Julia-STREAM/src/components.jl` — PipeGeometry struct +2 fields (width, depth); both constructors updated
- `/home/itay/projects/Julia-STREAM/src/STREAM.jl` — include("correlations.jl") added before components.jl; 6 new exports
- `/home/itay/projects/Julia-STREAM/test/runtests.jl` — PHY-02/03/04 testset appended (17 tests)

## Decisions Made
- No `@register_symbolic` on any correlation function — they are plain arithmetic; MTK traces symbolically through them (unlike fluid property splines which need opaque registration)
- `laminar_friction` `aspect_ratio` kwarg has no default — callers must explicitly provide geometry context
- `Re_transition` is immediately converted to `Float64` in `regime_dependent` body to avoid `Int` vs `Symbolics.Num` type-promotion error at system build time
- `constant_Nusselt` returns `(Re, Pr) -> Nu` where `Nu` is a captured `Float64`; this is valid because `Nu[i] ~ 8.235` is a legal MTK algebraic equation

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None — all reference values matched Python STREAM on first attempt.

## User Setup Required

None - no external service configuration required.

## Self-Check

- [x] `src/correlations.jl` exists: FOUND
- [x] `rectangular_laminar_correction(0.01814) ≈ 0.68544`: VERIFIED
- [x] `PipeGeometry_rectangular` sets width=max, depth=min: VERIFIED
- [x] `PipeGeometry_circular` sets width=depth=D: VERIFIED
- [x] All 6 symbols importable from STREAM: VERIFIED
- [x] Full test suite green (160 tests, 0 failures): VERIFIED
- [x] Commits exist: 70d3a82, f2407c9, 4c892bf — FOUND

## Self-Check: PASSED

## Next Phase Readiness
- All six correlation functions/factories ready for Plan 02 to plug into channel components
- `dittus_boelter` and `blasius_friction` are in scope (correlations.jl loaded before components.jl) so they can be default kwarg values in `_channel_base_eqs`
- `PipeGeometry.width` and `PipeGeometry.depth` allow users to derive `aspect_ratio = geom.depth / geom.width` for laminar_friction construction

---
*Phase: 14-laminar-correlations*
*Completed: 2026-03-15*
