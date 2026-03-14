---
phase: 11-heatdiffusion-component
plan: 01
subsystem: components
tags: [modelingtoolkit, heat-diffusion, finite-difference, thermalport, solid-plate]

# Dependency graph
requires:
  - phase: 10-channelandcontacts-upgrade
    provides: ChannelAndContacts two-sided ThermalPort arrays — the interface HeatDiffusion connects to
provides:
  - _diffusion_eqs helper: mutates equation vector with 2*nz Q_flow + nz*nx ODE equations for a 2D FD solid plate
  - HeatDiffusion constructor: nz x nx MTK System with dual ThermalPort arrays (thermal_left[1:nz], thermal_right[1:nz])
  - HeatDiffusion exported from STREAM module
affects:
  - 12-mtr-validation (will connect HeatDiffusion to two ChannelAndContacts for MTR fuel assembly model)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Half-cell boundary flux scheme: boundary cell uses thermal_port.T as virtual neighbor at dx/2"
    - "vec(collect(T)) flattens 2D MTK array state to 1D for System() constructor"
    - "only(pars) extracts single MTK parameter symbol from @parameters block"
    - "Adiabatic top/bottom by omission: no z-diffusion equations written at all"
    - "power_shape[i,j] not normalized internally — caller's responsibility"

key-files:
  created: []
  modified:
    - src/components.jl
    - src/STREAM.jl

key-decisions:
  - "Material properties (rho_s, cp_s, k_s) are plain Float64 not MTK parameters in v0.3 — simplifies system assembly"
  - "power is MTK @parameters (tunable via remake()) — allows power sweeps without recompile"
  - "Option B chosen for boundary cells: ODE for ALL nz*nx cells including j=1 and j=nx — consistent half-cell flux scheme"
  - "CHAN-03 test error is pre-existing (confirmed via git stash check); not introduced by this plan"

patterns-established:
  - "_diffusion_eqs follows _channel_base_eqs mutation pattern: takes eqs::Vector{Equation} and push!s into it"
  - "HeatDiffusion follows ChannelAndContacts constructor pattern: explicit ThermalPort name=Symbol(:port, i)"

requirements-completed: [HDIFF-01, HDIFF-02, HDIFF-03, HDIFF-04]

# Metrics
duration: 7min
completed: 2026-03-14
---

# Phase 11 Plan 01: HeatDiffusion Component Summary

**2D finite-difference solid fuel plate (_diffusion_eqs + HeatDiffusion) with dual ThermalPort arrays, x-direction FD diffusion, half-cell boundary flux scheme, and volumetric heat source; bare mtkcompile verified.**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-14T00:07:52Z
- **Completed:** 2026-03-14T00:15:28Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Implemented `_diffusion_eqs`: appends 2*nz Q_flow equations (left/right boundary fluxes) and nz*nx temperature ODEs using half-cell boundary flux scheme for boundary cells and standard 2nd-order FD for interior cells
- Implemented `HeatDiffusion` constructor producing an MTK System with state `T(t)[1:nz, 1:nx]`, parameter `power`, and dual ThermalPort arrays `thermal_left[1:nz]` / `thermal_right[1:nz]`
- Exported `HeatDiffusion` from STREAM module; `mtkcompile(hd; fully_determined=false)` verified on bare (unconnected) instance

## Task Commits

Each task was committed atomically:

1. **Task 1+2: _diffusion_eqs helper and HeatDiffusion constructor** - `7b965ca` (feat)
2. **Task 2: Export HeatDiffusion from STREAM module** - `5c97787` (feat)

**Plan metadata:** (docs commit follows)

## Files Created/Modified
- `src/components.jl` - Added `_diffusion_eqs` private helper and `HeatDiffusion` public constructor (106 lines)
- `src/STREAM.jl` - Added `HeatDiffusion` to export list

## Decisions Made
- Material properties (rho_s, cp_s, k_s) as plain Float64: simplifies system assembly for v0.3; v0.4 can promote to parameters
- `power` as MTK `@parameters`: enables remake()-based power sweeps without recompilation
- Half-cell boundary flux scheme (Option B): boundary cells j=1 and j=nx have ODEs that reference thermal port temperatures as virtual neighbors at dx/2 — physically consistent and avoids algebraic loop
- `only(pars)` used to extract single power parameter symbol rather than `pars[1]` — clearer intent

## Deviations from Plan

None - plan executed exactly as written.

The pre-existing CHAN-03 test error (1 errored, 17 passed) was confirmed via `git stash` to exist before any changes in this plan. It is out of scope.

## Issues Encountered
- Task 2 verification command in plan uses `@named` macro which requires `ModelingToolkit` import in `Main` scope. Fixed by adding `using ModelingToolkit` to the verification command. No code changes needed.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- `HeatDiffusion` is instantiable and mtkcompiles bare; ready to be wired to two `ChannelAndContacts` systems in Phase 12 (MTR validation)
- Phase 12 will use `connect()` and `compose()` to form the full MTR fuel assembly model
- Outstanding: CHAN-03 test error should be investigated before Phase 12 validation (pre-existing, out of scope here)

---
*Phase: 11-heatdiffusion-component*
*Completed: 2026-03-14*
