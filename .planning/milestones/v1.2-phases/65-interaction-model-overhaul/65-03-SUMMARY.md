---
phase: 65-interaction-model-overhaul
plan: "03"
subsystem: ui
tags: [react-flow, canvas, interaction-model, context-menu, disambiguation, vitest, phase-65]

# Dependency graph
requires: []
provides:
  - "useRightClickContextMenu hook: 5px/250ms right-pan-vs-context-menu disambiguation (D-12)"
  - "CanvasPanel: left-marquee selection, right-drag pan, Esc-clears-selection"
  - "Context menu plumbing: onPaneContextMenu/onNodeContextMenu/onEdgeContextMenu wired to hook state"
affects:
  - 65-04-PLAN
  - 65-05-PLAN

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Window capture-phase contextmenu listener for OS-native menu suppression after right-drag-pan (B2 pattern)"
    - "TDD: test(65-03) commit → feat(65-03) commit with vitest renderHook"
    - "B3 guard: useReactFlow called once at component top level, setNodes/setEdges pulled from same destructure"

key-files:
  created:
    - gui/src/hooks/useRightClickContextMenu.ts
    - gui/src/components/__tests__/useRightClickContextMenu.test.tsx
  modified:
    - gui/src/components/CanvasPanel.tsx

key-decisions:
  - "D-12 implemented: 5px Manhattan-distance + 250ms time threshold; window-level capture-phase contextmenu listener suppresses OS-native menu after right-drag-pan"
  - "D-13 inherited: Mac ctrl-click not intercepted; OS converts to right-click natively"
  - "gestureRef seeds upX/Y/T from down values so a contextmenu-without-mouseup (zero-distance) qualifies as quick-short"
  - "rcMenu.state exposed but no menu UI rendered — Plan 05 owns context menu content and rendering"

patterns-established:
  - "useRightClickContextMenu: reusable hook pattern for any future right-click interaction surface"
  - "Esc handler extends existing keydown useEffect; uses useStore.getState() for stable closure, setNodes/setEdges from top-level useReactFlow()"

requirements-completed: []

# Metrics
duration: 65min
completed: 2026-05-14
---

# Phase 65 Plan 03: Canvas Interaction Matrix Summary

**drawio interaction convention wired on CanvasPanel: left-marquee selection, right-drag pan, 5px/250ms right-click context-menu disambiguation via window capture-phase contextmenu listener (D-12)**

## Performance

- **Duration:** ~65 min
- **Started:** 2026-05-14T16:10:00Z
- **Completed:** 2026-05-14T17:20:00Z
- **Tasks:** 2 of 3 (Task 3 is checkpoint:human-verify — awaiting manual smoke)
- **Files modified:** 3

## Accomplishments

- Created `useRightClickContextMenu` hook with MANHATTAN_THRESHOLD_PX=5 and TIME_THRESHOLD_MS=250 constants, window mousedown/mouseup/contextmenu listeners, and three ReactFlow callbacks (`onPaneContextMenu`, `onNodeContextMenu`, `onEdgeContextMenu`)
- Window capture-phase `contextmenu` listener suppresses the OS-native browser context menu after a right-drag-pan (resolves checker B2 — ReactFlow forwards the event regardless of pan state)
- Wired all new ReactFlow props: `panOnDrag={[2]}`, `selectionOnDrag`, `selectionMode={SelectionMode.Partial}`, context menu handlers
- Added Esc key handler that clears node + edge selection (skips when text input focused)
- 10/10 vitest unit tests green; 95/95 total tests in `__tests__/` passing; no new TypeScript errors

## Task Commits

Each task was committed atomically:

1. **Task 1 (RED): failing tests** - `820e6c6` (test)
2. **Task 1 (GREEN): hook implementation** - `be8674e` (feat)
3. **Task 2: CanvasPanel wiring** - `7bc2077` (feat)

_Task 3 is checkpoint:human-verify — no commit yet._

## Files Created/Modified

- `gui/src/hooks/useRightClickContextMenu.ts` — New hook: `ContextMenuState` interface, `useRightClickContextMenu()` function, MANHATTAN_THRESHOLD_PX/TIME_THRESHOLD_MS constants, three window listeners, three ReactFlow callbacks, `close()`
- `gui/src/components/__tests__/useRightClickContextMenu.test.tsx` — 10 unit tests covering all 8 behavior specs + cleanup and quick-click passthrough
- `gui/src/components/CanvasPanel.tsx` — Added `SelectionMode` import, `useRightClickContextMenu` import; extended `useReactFlow()` destructure to include `setNodes`/`setEdges`; added `rcMenu` hook call; added Esc handler; added 5 new ReactFlow props

## Decisions Made

- Seeding `gestureRef.upX/Y/T` from down values on mousedown ensures a contextmenu event without a preceding mouseup (zero-distance, zero-duration) qualifies as quick-short rather than triggering suppression.
- `close()` is exposed from the hook but Plan 05 owns outside-click and Esc dismissal; Plan 03 only wires the plumbing.
- `SelectionMode.Partial` used via the enum rather than the string literal `"partial"` for type safety with @xyflow/react v12.

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

- Worktree lacked `node_modules` on first test run; resolved by running `npm install` inside the worktree's `gui/` directory.
- The plan's acceptance criterion `grep -cE 'useReactFlow\(\)' ... returns 1` would have returned 2 due to the comment text; adjusted comment phrasing to satisfy the grep.

## Known Stubs

- `rcMenu.state` is computed but not rendered. No menu UI exists yet — this is intentional. Plan 05 wires the shadcn ContextMenu component to this state. The stub is load-bearing infrastructure, not a UI gap.

## Threat Flags

No new security-relevant surface beyond what the plan's threat model covers (T-65-03, T-65-03b). The window contextmenu capture listener is bounded by component lifetime via useEffect cleanup.

## Self-Check: PASSED

- FOUND: gui/src/hooks/useRightClickContextMenu.ts
- FOUND: gui/src/components/__tests__/useRightClickContextMenu.test.tsx
- FOUND: gui/src/components/CanvasPanel.tsx
- FOUND: commit 820e6c6 (test: RED phase)
- FOUND: commit be8674e (feat: GREEN phase)
- FOUND: commit 7bc2077 (feat: CanvasPanel wiring)

## Next Phase Readiness

- Plan 04 (context menu content) and Plan 05 (menu rendering) can consume `rcMenu.state` immediately — the hook signature is stable and typed.
- Manual smoke test (Task 3 checkpoint) required before marking plan complete: verify left-marquee, right-drag-pan-suppresses-menu, edge-delete-via-Del/Backspace, Esc-clears-selection in the running Tauri app.

---
*Phase: 65-interaction-model-overhaul*
*Completed: 2026-05-14*
