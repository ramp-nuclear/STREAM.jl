---
phase: 41-layered-canvas
plan: 01
subsystem: ui
tags: [zustand, reactflow, layer-detection, project-schema]

# Dependency graph
requires:
  - phase: 40-thermal-composition
    provides: ThermalPort handles, connection validation, thermal edge styling
provides:
  - LayerView type and 4 pure layer detection utilities (getComponentLayers, isComponentVisibleInLayer, isNodeDimmed, isEdgeDimmed)
  - activeLayer store state with setActiveLayer and cycleLayer actions
  - StreamProject v2 schema with activeLayer field and v1 backwards compatibility
affects: [41-02-layer-ui-wiring, 42-minimap-toolbar]

# Tech tracking
tech-stack:
  added: []
  patterns: [layer-detection-pure-functions, project-schema-versioning, view-state-persisted-not-undoable]

key-files:
  created:
    - gui/src/lib/layers.ts
    - gui/src/lib/__tests__/layers.test.ts
  modified:
    - gui/src/store/useStore.ts
    - gui/src/store/__tests__/useStore.test.ts
    - gui/src/lib/projectIO.ts
    - gui/src/lib/__tests__/projectIO.test.ts

key-decisions:
  - "activeLayer sets isDirty (persisted in .streamgui) unlike toolboxCollapsed (session-only)"
  - "cycleLayer order: Hydraulic->Both->Thermal->Hydraulic"
  - "v1->v2 migration defaults activeLayer to Both via deserializeProject"
  - "Existing version assertions updated from 1 to 2 (breaking change to serialization format)"

patterns-established:
  - "Layer detection as pure functions taking ComponentDefinition, decoupled from DOM/React"
  - "Project schema versioning with backwards-compatible deserialization"
  - "View state persisted in project file but excluded from undo stack"

requirements-completed: [LAYR-01, LAYR-02, LAYR-03, LAYR-04, LAYR-05]

# Metrics
duration: 3min
completed: 2026-04-03
---

# Phase 41 Plan 01: Layered Canvas Logic Summary

**Pure layer detection utilities (4 functions), activeLayer store state with cycleLayer, and StreamProject v2 schema with v1 backwards compatibility**

## Performance

- **Duration:** 3 min
- **Started:** 2026-04-03T18:12:01Z
- **Completed:** 2026-04-03T18:15:23Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- Created `gui/src/lib/layers.ts` with 4 exported pure functions and LayerView type for port-based layer detection
- Extended Zustand store with activeLayer state, setActiveLayer, and cycleLayer (Hydraulic->Both->Thermal rotation)
- Upgraded StreamProject to v2 with activeLayer field; deserializeProject migrates v1 files automatically
- 34 new tests (29 layer tests + 5 projectIO v2 tests) plus 5 new store tests, all passing

## Task Commits

Each task was committed atomically:

1. **Task 1: Create layer detection utility and tests** - `b62ad7f` (feat)
2. **Task 2: Extend store (activeLayer) and projectIO (v2 schema)** - `ef98103` (feat)

## Files Created/Modified
- `gui/src/lib/layers.ts` - LayerView type, getComponentLayers, isComponentVisibleInLayer, isNodeDimmed, isEdgeDimmed
- `gui/src/lib/__tests__/layers.test.ts` - 29 tests for all layer utility functions
- `gui/src/store/useStore.ts` - activeLayer state, setActiveLayer, cycleLayer, save/load/new integration
- `gui/src/store/__tests__/useStore.test.ts` - 5 new activeLayer tests (default, set, dirty, cycle, undo isolation)
- `gui/src/lib/projectIO.ts` - StreamProject v2 interface, serializeProject writes v2+activeLayer, deserializeProject migrates v1
- `gui/src/lib/__tests__/projectIO.test.ts` - 5 new v2 tests, 2 updated assertions (version 1->2)

## Decisions Made
- activeLayer sets isDirty because it is persisted in .streamgui (unlike toolboxCollapsed which is session-only UI state)
- Updated existing tests that asserted version===1 to assert version===2 since serializeProject now always writes v2
- cycleLayer order chosen as Hydraulic->Both->Thermal matching the plan spec

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Updated existing version assertions from 1 to 2**
- **Found during:** Task 2
- **Issue:** Two pre-existing tests ("includes version 1", "parses valid JSON...") expected version 1 but serializeProject now writes version 2
- **Fix:** Updated expected values from 1 to 2
- **Files modified:** gui/src/lib/__tests__/projectIO.test.ts
- **Verification:** Full test suite passes (223 tests)
- **Committed in:** ef98103 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Necessary update to existing tests for v2 schema change. No scope creep.

## Issues Encountered
- npm dependencies not installed in worktree; resolved with `npm install` before running tests

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Layer detection utilities ready for Plan 02 to wire into UI (node opacity, edge dimming, toolbar toggle)
- Store activeLayer state ready for toolbar button and keyboard shortcut binding
- Project file format v2 ready; existing v1 files auto-migrate on load

---
*Phase: 41-layered-canvas*
*Completed: 2026-04-03*
