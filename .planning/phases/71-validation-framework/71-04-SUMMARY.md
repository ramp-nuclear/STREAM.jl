---
phase: 71-validation-framework
plan: 04
subsystem: ui
tags: [validation, typescript, vitest, rules, port-type, required-connections, dangling-flow-port]

# Dependency graph
requires:
  - phase: 71-validation-framework
    plan: 01
    provides: "Validator + ValidationResult + ValidationSnapshot types; validation/index.ts skeleton"

provides:
  - "portType: Validator — port-type compatibility rule; D-19 single source of truth for onConnect hard-block"
  - "requiredConnections: Validator — required port connectivity rule (D-15 rule 4)"
  - "danglingFlowPort: Validator — unconnected FlowPort rule (VALD-01 fold per D-16)"
  - "All three rules registered in validation/index.ts (D-07 explicit array)"

affects:
  - "71-13 (CanvasPanel onConnect reroute) — portType.run() is the D-19 single source of truth"
  - "71-13 (validation.ts deletion) — danglingFlowPort folds VALD-01; dangling + pressureBoundaryRequired + drivingElementRequired together allow validation.ts deletion"
  - "All Wave-3+ plans consuming ValidationResult targets"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "One file per rule under gui/src/lib/validation/rules/ with co-located __tests__/ (D-08)"
    - "Pure-function Validator: no useStore imports, no React imports, snapshot-in + results-out"
    - "TDD RED/GREEN per task: failing import test → passing implementation"
    - "D-14 symmetric emission: edge-level rules emit [{kind:edge}, {kind:port,src}, {kind:port,tgt}]"
    - "D-11 stable result id: <validatorId>::<edge.id> or <validatorId>::<nodeId>::<portName>"

key-files:
  created:
    - "gui/src/lib/validation/rules/portType.ts (103 lines)"
    - "gui/src/lib/validation/rules/requiredConnections.ts (121 lines)"
    - "gui/src/lib/validation/rules/danglingFlowPort.ts (67 lines)"
    - "gui/src/lib/validation/rules/__tests__/portType.test.ts"
    - "gui/src/lib/validation/rules/__tests__/requiredConnections.test.ts"
    - "gui/src/lib/validation/rules/__tests__/danglingFlowPort.test.ts"
  modified:
    - "gui/src/lib/validation/index.ts — 3 rule imports + array entries added"

key-decisions:
  - "Array-shaped ThermalPort cells (thermal_left[i]) use handle name portBase[i] for edge matching in requiredConnections"
  - "danglingFlowPort is FlowPort-only (mirrors legacy validateTopology VALD-01); ThermalPort cells covered by requiredConnections; coexistence documented in JSDoc"
  - "portType consults isAllowedBCConnection for BCPort→BCPort pairs; mixed BCPort+non-BCPort always invalid"
  - "BCPort is never required in requiredConnections heuristic (WallTemperature/HeatFluxSource are optional)"

requirements-completed: [D-07, D-08, D-14, D-15, D-16, D-19]

# Metrics
duration: 30min
completed: 2026-05-21
---

# Phase 71 Plan 04: Structural port-graph validators (portType, requiredConnections, danglingFlowPort)

**Three pure-function Validator rules covering port-type mismatch (D-19 onConnect hook), required-port connectivity, and dangling FlowPort (VALD-01 fold), registered in the explicit validation array; 20 vitest tests all pass**

## Performance

- **Duration:** 30 min
- **Started:** 2026-05-21T14:30:00Z
- **Completed:** 2026-05-21T14:36:00Z
- **Tasks:** 3
- **Files modified:** 7

## Accomplishments

- portType validator: 103-line pure function covering FlowPort/ThermalPort type mismatch + BCPort allow-list delegation; 8 tests; D-19 single source of truth for Plan 13's onConnect reroute
- requiredConnections validator: 121-line pure function iterating scalar + array-shaped required ports (FlowPort always required, ThermalPort required, BCPort never required); 5 tests including CAC and HeatDiffusion per-cell checking
- danglingFlowPort validator: 67-line pure function folding VALD-01 from validation.ts verbatim; FlowPort-only; 7 tests ported from legacy validation.test.ts + BCPort/ThermalPort exclusion cases
- Registry array in index.ts now lists 3 rules (portType, requiredConnections, danglingFlowPort)

## Task Commits

Each task was committed atomically via TDD (RED → GREEN):

1. **Task 1: portType rule + tests** - `e3ccff7` (feat)
2. **Task 2: requiredConnections rule + tests** - `5effe5b` (feat)
3. **Task 3: danglingFlowPort rule + tests** - `1628f47` (feat)

## Files Created/Modified

- `gui/src/lib/validation/rules/portType.ts` (103 lines) — Port-type compatibility rule; consults `isAllowedBCConnection` for BCPort pairs; D-19 single source of truth
- `gui/src/lib/validation/rules/requiredConnections.ts` (121 lines) — Required-port rule; handles scalar and array-shaped ports; BCPort never required
- `gui/src/lib/validation/rules/danglingFlowPort.ts` (67 lines) — VALD-01 fold; FlowPort-only; JSDoc documents coexistence with requiredConnections
- `gui/src/lib/validation/rules/__tests__/portType.test.ts` — 8 tests
- `gui/src/lib/validation/rules/__tests__/requiredConnections.test.ts` — 5 tests
- `gui/src/lib/validation/rules/__tests__/danglingFlowPort.test.ts` — 7 tests (ported from validation.test.ts VALD-01 section)
- `gui/src/lib/validation/index.ts` — 3 rule imports + array entries

## Decisions Made

- Array-shaped ThermalPort cells: used `portBase[i]` handle name convention (e.g., `thermal_left[1]`) for edge matching in requiredConnections, matching the ReactFlow handle ID scheme used by ChannelAndContacts and HeatDiffusion
- danglingFlowPort is FlowPort-only intentionally: it mirrors the legacy validateTopology VALD-01 behavior; requiredConnections is the broader rule covering ThermalPort cells too; both rules coexist with distinct IDs and descriptions
- BCPort always excluded from requiredConnections: WallTemperature and HeatFluxSource are optional value-source blocks

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None. All 20 tests pass on first GREEN run. TypeScript error count held at 13 (baseline from Plan 01; no new errors introduced).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- portType is ready for Plan 13's D-19 onConnect reroute (`portType.run(syntheticSnapshot)` replaces the inline `getPortType()` call)
- danglingFlowPort folds VALD-01 — Plan 13 can delete `gui/src/lib/validation.ts` once VALD-02/VALD-03 are folded by pressureBoundaryRequired and drivingElementRequired rules
- Registry array has 3 of ~11 eventual rules; Wave-2 store refactor (Plan 02) and remaining rule plans proceed independently

## Known Stubs

None. All three rules are fully wired pure functions with no placeholder data or hardcoded returns.

## Threat Flags

None. These are pure-function validators operating on in-memory model data. No new network endpoints, auth paths, file access, or schema changes at trust boundaries.

## Self-Check: PASSED

- [x] `gui/src/lib/validation/rules/portType.ts` exists
- [x] `gui/src/lib/validation/rules/requiredConnections.ts` exists
- [x] `gui/src/lib/validation/rules/danglingFlowPort.ts` exists
- [x] All 20 tests pass (`npm run test -- --run src/lib/validation/rules`)
- [x] `tsc --noEmit`: 13 errors (= Plan 01 baseline, no regressions)
- [x] Commits e3ccff7, 5effe5b, 1628f47 verified in git log
- [x] No useStore/React imports in any rule file
- [x] 3 rule imports + 3 array entries in index.ts

---
*Phase: 71-validation-framework*
*Completed: 2026-05-21*
