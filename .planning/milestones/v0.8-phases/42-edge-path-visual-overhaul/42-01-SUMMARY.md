---
phase: 42-edge-path-visual-overhaul
plan: 01
subsystem: gui/store
tags: [edge-rendering, arrowheads, bidirectional-offset, xyflow]
dependency_graph:
  requires: []
  provides: [enrichEdges, hydraulic-arrowheads, parallel-edge-offset]
  affects: [gui/src/store/useStore.ts, gui/src/components/CanvasPanel.tsx]
tech_stack:
  added: []
  patterns: [MarkerType.ArrowClosed, pathOptions.offset, enrichEdges pure function]
key_files:
  created: []
  modified:
    - gui/src/store/useStore.ts
    - gui/src/store/__tests__/useStore.test.ts
decisions:
  - "Bidirectional pair detection matches on node IDs only (not handles) -- real loops use different port names on each direction (outlet->inlet vs outlet->inlet)"
  - "enrichEdges is a pure exported function (not a store method) for testability and reuse in loadProjectFromPath"
  - "Thermal edges explicitly strip markerEnd to handle re-enrichment of saved projects that may have stale markers"
metrics:
  duration_seconds: 197
  completed: "2026-04-03T20:17:40Z"
---

# Phase 42 Plan 01: Arrowheads and Parallel Edge Offset Summary

Hydraulic edges display filled ArrowClosed markers at target end; bidirectional pairs get +/-10px lateral offset via pathOptions; thermal edges remain unmarked; enrichEdges re-applies on project load.

## What Was Done

### Task 1: Arrowheads and parallel edge offset in addEdge + offset cleanup
- Added `MarkerType` import from `@xyflow/react`
- Created `enrichEdges(edges, nodes)` pure function that:
  - Applies `MarkerType.ArrowClosed` markerEnd to hydraulic edges (FlowPort connections)
  - Strips markerEnd from thermal edges (ThermalPort connections)
  - Detects bidirectional pairs (same two nodes, opposite directions) and applies `pathOptions: { offset: +/-10 }`
  - Strips stale offset from edges whose partner no longer exists
- Modified `addEdge` to call `enrichEdges` after thermal styling
- Modified `onEdgesChange` to clean up partner offset when an edge with offset is removed
- Modified `removeEdge` to clean up partner offset on the surviving edge
- Modified `loadProjectFromPath` to call `enrichEdges` on loaded edges (handles pre-Phase-42 saves)
- Added 5 new tests covering arrowheads, no-thermal-marker, offset, offset-cleanup, and enrichEdges purity
- **Commit:** 6cfc46c

### Task 2: Verify CanvasPanel enrichedEdges preserves markerEnd and pathOptions
- Confirmed `defaultEdgeOptions = { type: "smoothstep" }` does NOT contain markerEnd
- Confirmed `enrichedEdges` useMemo spreads `...edge` then only overrides `style` -- markerEnd and pathOptions are preserved
- No code changes needed -- verification only

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Bidirectional pair detection used handle matching**
- **Found during:** Task 1
- **Issue:** Plan specified `other.sourceHandle === e.targetHandle && other.targetHandle === e.sourceHandle` for reverse detection. Real bidirectional pairs (e.g., Pump.outlet->Channel.inlet and Channel.outlet->Pump.inlet) have different handle names on each direction, so handle matching fails.
- **Fix:** Changed bidirectional detection to match on node IDs only (source/target swapped), ignoring handles. Applied same fix to offset cleanup in onEdgesChange and removeEdge.
- **Files modified:** gui/src/store/useStore.ts
- **Commit:** 6cfc46c

## Verification

- `npx vitest run` -- 228 tests pass, 0 failures
- All acceptance criteria met:
  - useStore.ts contains MarkerType import and ArrowClosed usage
  - useStore.ts contains pathOptions offset +10 and -10
  - useStore.ts contains enrichEdges function definition
  - loadProjectFromPath calls enrichEdges before set()
  - Tests cover arrowheads, offset, and cleanup

## Self-Check: PASSED
