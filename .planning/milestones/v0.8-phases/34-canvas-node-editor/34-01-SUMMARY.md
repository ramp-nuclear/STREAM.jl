---
phase: 34-canvas-node-editor
plan: 01
subsystem: ui
tags: [zustand, zundo, reactflow, undo-redo, drag-drop, custom-node]

# Dependency graph
requires:
  - phase: 33-project-scaffold
    provides: Zustand store with ReactFlow wiring, component registry with Port metadata
provides:
  - Zustand store with temporal undo/redo middleware and 4 canvas actions
  - StreamNodeData type for node data contract
  - StreamNode custom ReactFlow node component with registry-driven FlowPort handles
  - ToolboxItem draggable component with HTML5 drag API
affects: [34-02 canvas-wiring, 35-parameter-sidebar, 36-code-generation]

# Tech tracking
tech-stack:
  added: [zundo]
  patterns: [temporal-middleware-partialize, registry-driven-node-rendering, html5-drag-payload]

key-files:
  created:
    - gui/src/components/StreamNode.tsx
    - gui/src/components/ToolboxItem.tsx
  modified:
    - gui/src/store/useStore.ts
    - gui/package.json
    - gui/package-lock.json

key-decisions:
  - "Per-type non-decreasing instance counters at module level (outside zundo tracking) for comp_type_N naming"
  - "crypto.randomUUID() for node IDs instead of timestamp-based to avoid collision"
  - "FlowPort handle type derived from port name convention: 'out' in name = source, otherwise target"

patterns-established:
  - "Temporal middleware: partialize excludes action functions, limit 50 history entries"
  - "StreamNodeData interface as the node.data contract for all canvas nodes"
  - "sideToPosition map converts registry port.side to ReactFlow Position enum"

requirements-completed: [CANV-01, CANV-02, CANV-05, CANV-06, CANV-07]

# Metrics
duration: 1min
completed: 2026-04-02
---

# Phase 34 Plan 01: Store Extension & Component Creation Summary

**Zustand store with zundo temporal undo/redo, 4 canvas actions (addNode/removeNode/addEdge/removeEdge), StreamNode custom node with registry-driven FlowPort handles, and ToolboxItem HTML5 drag component**

## Performance

- **Duration:** 1 min
- **Started:** 2026-04-01T22:22:46Z
- **Completed:** 2026-04-01T22:23:57Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Extended Zustand store with zundo temporal middleware (limit 50, partialize excluding functions) and 4 new canvas actions
- Created StreamNode custom ReactFlow node that renders component type label, instance name, and FlowPort handles from registry metadata
- Created ToolboxItem draggable component with HTML5 drag API carrying componentId payload
- Per-type instance counters for default naming (pump_1, channel_2) outside zundo tracking

## Task Commits

Each task was committed atomically:

1. **Task 1: Install zundo and extend Zustand store** - `0db8701` (feat)
2. **Task 2: Create StreamNode and ToolboxItem components** - `1f8ea72` (feat)

## Files Created/Modified
- `gui/src/store/useStore.ts` - Zustand store with temporal undo/redo, StreamNodeData export, 4 canvas actions
- `gui/src/components/StreamNode.tsx` - Custom ReactFlow node with registry-driven FlowPort handles and selected state styling
- `gui/src/components/ToolboxItem.tsx` - Draggable toolbox item with application/streamcomponent drag payload
- `gui/package.json` - Added zundo dependency
- `gui/package-lock.json` - Lock file updated

## Decisions Made
- Per-type non-decreasing instance counters stored at module level (not in Zustand state, not tracked by zundo) to avoid name reuse after undo
- Used crypto.randomUUID() for node IDs instead of componentId-timestamp pattern to avoid millisecond collision
- Handle type derived from registry port name convention: port names containing "out" are sources, others are targets

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Store has all actions needed for Plan 02 to wire CanvasPanel (onDrop, nodeTypes, isValidConnection, deleteKeyCode)
- StreamNode component ready for nodeTypes registration in CanvasPanel
- ToolboxItem component ready for ToolboxPanel population with registry data

## Self-Check: PASSED

All files verified present. All commit hashes verified in git log.

---
*Phase: 34-canvas-node-editor*
*Completed: 2026-04-02*
