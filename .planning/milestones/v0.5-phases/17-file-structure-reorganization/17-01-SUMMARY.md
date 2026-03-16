---
phase: 17-file-structure-reorganization
plan: 01
subsystem: infra
tags: [julia, modelingtoolkit, file-structure, refactor]

# Dependency graph
requires: []
provides:
  - "src/geometry.jl: PipeGeometry struct + PipeGeometry_rectangular + PipeGeometry_circular"
  - "src/components/channel.jl: Channel + _channel_base_eqs helper"
  - "src/components/pump.jl: Pump component"
  - "src/components/resistors.jl: Friction, Gravity, Resistor"
  - "src/components/misc.jl: Inertia, HeatExchanger, ConstantTemperature"
  - "src/components/thermal_channel.jl: ChannelAndContacts, ChannelHeatFlux"
  - "src/components/heat_diffusion.jl: _diffusion_eqs + HeatDiffusion"
affects: [17-02]

# Tech tracking
tech-stack:
  added: []
  patterns: ["Component files contain NO export/using/include statements — MTK symbols in module scope via STREAM.jl"]

key-files:
  created:
    - src/geometry.jl
    - src/components/channel.jl
    - src/components/pump.jl
    - src/components/resistors.jl
    - src/components/misc.jl
    - src/components/thermal_channel.jl
    - src/components/heat_diffusion.jl
  modified:
    - src/STREAM.jl

key-decisions:
  - "misc.jl receives two non-adjacent sections from components.jl (lines 261-296 Inertia/HeatExchanger + lines 539-545 ConstantTemperature) — merged in document order"
  - "channel.jl receives two non-adjacent sections (_channel_base_eqs helper at lines 298-355 placed after Channel function) — must be in channel.jl not thermal_channel.jl"
  - "STREAM.jl updated to 11-include interim list; correlations.jl and helpers.jl remain at current paths until Plan 02 moves them"
  - "VAL-01 Fourier series test is a pre-existing flaky failure unrelated to file structure — confirmed by running tests on prior commit"

patterns-established:
  - "Component file pattern: header comment, component functions, no export/using/include"
  - "Include order: fluids -> connectors -> geometry -> correlations -> components/* -> helpers -> solvers"

requirements-completed: [STR-01, STR-02]

# Metrics
duration: 23min
completed: 2026-03-16
---

# Phase 17 Plan 01: File Structure Reorganization — Geometry + Components Split Summary

**Monolithic src/components.jl (656 lines) split into src/geometry.jl and 6 focused component files under src/components/, aligning the codebase with the canonical CLAUDE.md layout**

## Performance

- **Duration:** 23 min
- **Started:** 2026-03-16T10:07:04Z
- **Completed:** 2026-03-16T10:30:00Z
- **Tasks:** 2
- **Files modified:** 8 (1 modified, 7 created, 1 deleted)

## Accomplishments
- Extracted PipeGeometry struct and factory functions into dedicated `src/geometry.jl`
- Split 656-line monolithic `src/components.jl` into 6 single-concern component files under `src/components/`
- Updated `src/STREAM.jl` include list from 6 includes to 11-include interim layout
- All 12 public component symbols accessible from STREAM module after reorganization
- Zero test regressions introduced (pre-existing VAL-01 failure confirmed on prior commit)

## Task Commits

Each task was committed atomically:

1. **Task 1: Extract PipeGeometry into src/geometry.jl (STR-01)** - `4a28855` (feat)
2. **Task 2: Split components.jl into 6 component files (STR-02)** - `d344a40` (feat)

## Files Created/Modified
- `src/geometry.jl` — PipeGeometry struct, PipeGeometry_rectangular, PipeGeometry_circular (new)
- `src/components/channel.jl` — Channel function + _channel_base_eqs helper (new)
- `src/components/pump.jl` — Pump component (new)
- `src/components/resistors.jl` — Friction, Gravity, Resistor components (new)
- `src/components/misc.jl` — Inertia, HeatExchanger, ConstantTemperature components (new)
- `src/components/thermal_channel.jl` — ChannelAndContacts, ChannelHeatFlux components (new)
- `src/components/heat_diffusion.jl` — _diffusion_eqs helper + HeatDiffusion component (new)
- `src/STREAM.jl` — include list updated from 6-include to 11-include interim layout (modified)
- `src/components.jl` — deleted (replaced by the 6 files above)

## Decisions Made
- Merged the two non-adjacent `misc.jl` sections (Inertia/HeatExchanger from lines 261-296, ConstantTemperature from lines 539-545) in document order with a blank line separator
- `_channel_base_eqs` placed in `channel.jl` (not `thermal_channel.jl`) per the plan mandate — `thermal_channel.jl` must be included after `channel.jl` for forward-reference correctness
- STREAM.jl written with full 11-include list in Task 1 so Task 2 only needed to create files

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- VAL-01 (HeatDiffusion Fourier series validation) test fails consistently. Confirmed pre-existing by running `Pkg.test()` on the prior commit (af4f030) which also shows the same failure. This is a numerical timing/tolerance issue in the test, not caused by file structure changes. Logged to deferred-items.

## Next Phase Readiness
- File structure is now aligned with CLAUDE.md canonical layout for all component files
- Plan 02 can proceed to move correlations.jl to physical_models/correlations.jl and helpers.jl to composition/helpers.jl

## Self-Check: PASSED

All created files confirmed on disk. Both task commits (4a28855, d344a40) confirmed in git log.

---
*Phase: 17-file-structure-reorganization*
*Completed: 2026-03-16*
