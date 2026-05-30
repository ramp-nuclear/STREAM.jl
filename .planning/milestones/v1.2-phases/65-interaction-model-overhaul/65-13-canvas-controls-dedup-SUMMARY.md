---
phase: 65-interaction-model-overhaul
plan: 13
subsystem: ui
tags: [reactflow, canvas-overlay, zustand, gap-closure, phase-65, lucide]

requires:
  - phase: 65-interaction-model-overhaul
    provides: SnapToGridButton overlay (Plan 06) — pattern mirrored by the four new buttons
provides:
  - "ReactFlow built-in <Controls /> panel removed; replaced by top-right overlay buttons"
  - "Top-right overlay now contains 5 icon buttons (ZoomIn, ZoomOut, FitView, InteractiveLock, SnapToGrid) in a flex column"
  - "interactiveLocked zustand boolean (session-only) freezes nodesDraggable/nodesConnectable/elementsSelectable/panOnDrag"
affects: [phase-65, gui-redesign, canvas-overlay]

tech-stack:
  added: []
  patterns:
    - "Session-only viewport-state field (not persisted in .scp; does not set isDirty)"
    - "Overlay icon button mirrors SnapToGridButton 8×8 rounded-border / bg-primary-on-active shape"

key-files:
  created:
    - gui/src/components/canvasMenus/ZoomInButton.tsx
    - gui/src/components/canvasMenus/ZoomOutButton.tsx
    - gui/src/components/canvasMenus/FitViewButton.tsx
    - gui/src/components/canvasMenus/InteractiveLockButton.tsx
    - gui/src/store/__tests__/interactiveLocked.test.ts
  modified:
    - gui/src/store/useStore.ts
    - gui/src/components/CanvasPanel.tsx

key-decisions:
  - "interactiveLocked is session-only — NOT persisted in .scp, NOT in newProject/loadProject/saveProject"
  - "setInteractiveLocked deliberately does NOT set isDirty (viewport preference != project state)"
  - "InteractiveLockButton uses a single Lock icon with bg-primary active-state styling (mirrors SnapToGridButton); no Lock/Unlock icon swap"
  - "panOnDrag fully disabled when locked (false vs [2]); selectionOnDrag stays on but elementsSelectable=false makes it a no-op"

patterns-established:
  - "Session-only zustand fields go in interface/init/action ONLY — never in serialize/deserialize/newProject paths"
  - "Plan 06 SnapToGridButton overlay pattern is the canonical template for canvas-corner icon buttons"

requirements-completed: []

duration: ~7min
completed: 2026-05-15
---

# Phase 65 Plan 13: canvas-controls-dedup Summary

**Removed ReactFlow's built-in `<Controls />` panel and replaced its four functions (zoom in/out, fit view, interactive lock) with top-right overlay icon buttons backed by `useReactFlow()` helpers and a new session-only `interactiveLocked` zustand boolean.**

## Performance

- **Duration:** ~7 min
- **Started:** 2026-05-15T17:46:00Z (approx — worktree spawn)
- **Completed:** 2026-05-15T14:52:45Z (UTC clock skew on host; wall-clock ~7 min)
- **Tasks:** 2 auto + 1 human-verify (deferred to live shell)
- **Files modified:** 2 (useStore.ts, CanvasPanel.tsx)
- **Files created:** 5 (4 buttons + 1 vitest)

## Accomplishments
- ReactFlow `<Controls />` import + render removed from CanvasPanel.tsx
- Four new icon buttons created (ZoomIn, ZoomOut, FitView, InteractiveLock) mirroring SnapToGridButton structure
- Top-right overlay converted to a 5-child flex column
- `interactiveLocked` field + `setInteractiveLocked` action added to useStore — session-only, not persisted in .scp, does not set isDirty
- ReactFlow `nodesDraggable` / `nodesConnectable` / `elementsSelectable` / `panOnDrag` wired to respond to `interactiveLocked`
- Three new vitest cases added and passing (`gui/src/store/__tests__/interactiveLocked.test.ts`)

## Task Commits

1. **Task 1 RED — failing vitest for interactiveLocked** — `6bc87a1` (test)
2. **Task 1 GREEN — interactiveLocked field + setter** — `eeb9cfb` (feat)
3. **Task 2 — replace Controls with overlay buttons + wire interactiveLocked** — `d9cb179` (feat)
4. **Deferred-items log** — `42988ee` (docs)

## Files Created/Modified
- `gui/src/store/useStore.ts` — added `interactiveLocked: boolean` and `setInteractiveLocked` action; not in serialize paths
- `gui/src/store/__tests__/interactiveLocked.test.ts` — 3 vitest cases (default false, setter does not dirty, regex-bound containment)
- `gui/src/components/canvasMenus/ZoomInButton.tsx` — Lucide `ZoomIn`, calls `useReactFlow().zoomIn()`
- `gui/src/components/canvasMenus/ZoomOutButton.tsx` — Lucide `ZoomOut`, calls `useReactFlow().zoomOut()`
- `gui/src/components/canvasMenus/FitViewButton.tsx` — Lucide `Maximize`, calls `useReactFlow().fitView()`
- `gui/src/components/canvasMenus/InteractiveLockButton.tsx` — Lucide `Lock`, toggles `interactiveLocked`, bg-primary when active
- `gui/src/components/CanvasPanel.tsx` — removed `Controls` import + render; added 4 button imports; added primitive `interactiveLocked` selector; wired 4 ReactFlow props; restructured top-right overlay to flex-col with 5 children

## Decisions Made
- **interactiveLocked is session-only.** It's a viewport-state preference and intentionally does not survive a project reload (mirrors ReactFlow's old Controls-lock semantics). Skipped serialize/deserialize/newProject/loadProject paths entirely.
- **No `isDirty: true` on toggle.** Confirmed in vitest case 2: dirty stays false through lock/unlock.
- **Single-icon toggle for the Lock button.** Mirrors SnapToGridButton — `bg-primary` swap conveys state; no Lock/Unlock icon swap (keeps visual consistency with the other corner toggle).
- **`panOnDrag` collapsed to `false` when locked.** When unlocked, right-mouse pan (`[2]`) remains active (preserves Plan 03 behavior).

## Deviations from Plan

None substantive — plan executed as written.

### Minor deviations (documentation-only)

- **Doc-comment phrasing.** The in-code comment in CanvasPanel.tsx originally contained the literal text `<Controls />` inside braces, which made the `<Controls />` JSX-search verify check report 1 hit. Reworded to "ReactFlow built-in Controls panel" so the automated check returns 0. No functional impact.
- **Deferred items logged.** One pre-existing vitest failure (`SidebarPanel.anchors.test.tsx` — `expected getByText("Symmetric (L = R)")`) and 12 pre-existing tsc errors (StreamNode Handle props, BCsTabForm cast, SidebarRouter `peaking`, validation.test.ts unused imports) were reproduced on the pre-edit base. Logged to `deferred-items.md` and committed separately (`42988ee`). Plan baseline mention of "11 tsc errors" was off by one — actual baseline at plan-13 base is 12.

## Issues Encountered
- **gui/node_modules missing in worktree.** Worktree spawn does not copy node_modules. Created a relative symlink to `/home/itay/projects/Julia-STREAM/gui/node_modules` (already covered by `gui/.gitignore: node_modules`, so not staged). Vitest then ran successfully.

## User Setup Required
None.

## Next Phase Readiness
- Plan ready for visual + functional verification (Task 3 checkpoint). Required manual checks (run in `npm run tauri dev`):
  1. No bottom-left Controls panel
  2. Top-right shows 5 icon buttons in column (ZoomIn / ZoomOut / FitView / Lock / Grid)
  3. ZoomIn / ZoomOut / FitView buttons work
  4. Lock button freezes node drag / right-pan / selection; unlock restores them
  5. SnapToGridButton still works (Plan 06 regression check)
- 9 sibling gap-closure plans (09–14) in this wave may surface further interaction tweaks.

## Self-Check: PASSED

Verified:
- [x] `gui/src/components/canvasMenus/ZoomInButton.tsx` exists
- [x] `gui/src/components/canvasMenus/ZoomOutButton.tsx` exists
- [x] `gui/src/components/canvasMenus/FitViewButton.tsx` exists
- [x] `gui/src/components/canvasMenus/InteractiveLockButton.tsx` exists
- [x] `gui/src/store/__tests__/interactiveLocked.test.ts` exists
- [x] `<Controls />` removed from CanvasPanel (grep count = 0)
- [x] `Controls` no longer imported from @xyflow/react
- [x] `interactiveLocked` selector + props wired in CanvasPanel
- [x] 3/3 vitest cases pass in `src/store/__tests__/interactiveLocked.test.ts`
- [x] Commits `6bc87a1`, `eeb9cfb`, `d9cb179`, `42988ee` exist in git log

---
*Phase: 65-interaction-model-overhaul*
*Plan: 13*
*Completed: 2026-05-15*
