---
phase: 40-thermal-composition
plan: 02
subsystem: ui
tags: [code-generation, thermal-topology, composition-helpers, reactflow]

# Dependency graph
requires:
  - phase: 40-01
    provides: ThermalPort handles, connection validation, edge styling
  - phase: 36-code-generation
    provides: Existing codeGenerator.ts with ODESystem generation
provides:
  - detectThermalTopology function classifying canvas thermal edges
  - Code generation emitting symmetric_plate, plate, one_sided_connection helper calls
  - compose_systems top-level system emission when thermal assemblies present
  - Dotted assembly path resolution for hydraulic connects to consumed nodes
affects: [gui-code-export, thermal-composition-workflow]

# Tech tracking
tech-stack:
  added: []
  patterns: [thermal-topology-detection, assembly-path-resolution, compose-systems-emission]

key-files:
  created: []
  modified:
    - gui/src/lib/codeGenerator.ts
    - gui/src/lib/codeGenerator.test.ts

key-decisions:
  - "detectThermalTopology groups thermal edges by HeatDiffusion node and classifies by CAC connection count and port pattern"
  - "Assembly path resolution prefixes consumed node instance names with assembly_N for hydraulic connect() calls"
  - "ConstantTemperature-to-array-ThermalPort emits per-cell connect with port() helper comprehension"
  - "Unknown topology (no matching pattern) falls through to TODO comment without assembly creation"

patterns-established:
  - "Thermal edge partitioning: edges classified by port type lookup from registry before processing"
  - "Assembly consumption model: nodes in assemblies tracked in consumedNodeIds set, used for path resolution and system list"

requirements-completed: [THERM-03]

# Metrics
duration: 3min
completed: 2026-04-03
---

# Phase 40 Plan 02: Thermal Topology Detection and Code Generation Summary

**Canvas thermal edge classification into symmetric_plate/plate/one_sided_connection helpers with compose_systems top-level emission and dotted assembly paths**

## Performance

- **Duration:** 3 min
- **Started:** 2026-04-03T13:49:13Z
- **Completed:** 2026-04-03T13:52:42Z
- **Tasks:** 1 (TDD: RED + GREEN)
- **Files modified:** 2

## Accomplishments

- `detectThermalTopology` function classifies canvas thermal edges into symmetric_plate, plate, one_sided_connection, or unknown assembly types
- Code generator emits correct STREAM.jl composition helper calls matching `src/composition/helpers.jl` signatures
- Hydraulic `connect()` calls use dotted assembly paths (`assembly_1.cac_1.port_in`) when CAC is consumed by a thermal assembly
- `compose_systems()` replaces `ODESystem()` as the top-level system builder when thermal assemblies exist
- nz/n parameter mismatch emits `# NOTE` warning comment
- Unknown thermal topologies emit `# TODO: verify thermal wiring` fallback comment
- ConstantTemperature connected to array ThermalPort emits per-cell `connect(ct.thermal, port(cac, :thermal_left, i))` comprehension
- Zero thermal edges produces identical Phase 36 format (backward compatible)
- All 32 codeGenerator tests pass (23 existing + 9 new thermal), 184 total tests pass

## Task Commits

1. **Task 1 RED: Failing tests** - `139537b` (test) - 9 new thermal topology tests
2. **Task 1 GREEN: Implementation** - `f177f76` (feat) - detectThermalTopology + generateCode thermal path

## Files Modified

- `gui/src/lib/codeGenerator.ts` - Added ThermalAssembly interface, detectThermalTopology, getPortTypeFromDef, resolveInstancePath; restructured generateCode for thermal assembly detection and emission
- `gui/src/lib/codeGenerator.test.ts` - Added cacDef, hdDef, ctDef mock component definitions; 9 new tests covering all topology patterns

## Decisions Made

- detectThermalTopology exported for testability and potential reuse
- Edge partitioning uses registry port type lookup (getPortTypeFromDef) rather than handle name heuristics
- Assembly naming uses sequential counter (assembly_1, assembly_2) rather than component-derived names
- plate() argument order follows helpers.jl: ch_left (connected to HD.thermal_left) first, ch_right second

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

None - all generated code paths produce complete output.

## Self-Check: PASSED
