---
phase: 65-interaction-model-overhaul
plan: "05"
subsystem: ui
tags: [gui, context-menu, shadcn, canvas, popover, phase-65]

# Dependency graph
requires:
  - "65-03: useRightClickContextMenu hook + rcMenu.state (screenX/Y/kind/targetId)"
  - "65-04: pasteFromClipboard/duplicateSelection/copySelection store actions"
provides:
  - "NodeContextMenu: Rename/Duplicate/Show generated Julia code/Delete (Phase 71 TODO for Show errors)"
  - "EdgeContextMenu: Delete"
  - "CanvasContextMenu: Paste/Auto-Layout (future, disabled)/Add Component submenu"
  - "AddComponentSubmenu: registry components grouped by category, addNode at flow coords"
  - "CanvasPanel: Popover-hosted menus at rcMenu.state screen coords"
  - "InstanceNameField: stream:focus-instance-name event listener for W7 rename path"
  - "context-menu.tsx: PopoverMenuItem/PopoverMenuSeparator/PopoverMenuSub* primitives (context-free)"
affects:
  - 65-TASK4-manual-smoke

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "PopoverMenuItem pattern: Radix-context-free menu item primitives styled to match ContextMenuItem — needed because ContextMenuItem requires MenuContentContext (ContextMenu.Root) which is unavailable inside a Popover"
    - "Popover-as-host (D-11): PopoverAnchor 1x1 fixed at screenX/Y anchors PopoverContent positioning"
    - "stream:focus-instance-name CustomEvent: NodeContextMenu Rename dispatches; InstanceNameField listens (W7 rename path)"
    - "stream:show-code-for CustomEvent: NodeContextMenu Show code dispatches; Phase 66 will listen"

key-files:
  created:
    - gui/src/components/canvasMenus/NodeContextMenu.tsx
    - gui/src/components/canvasMenus/EdgeContextMenu.tsx
    - gui/src/components/canvasMenus/CanvasContextMenu.tsx
    - gui/src/components/canvasMenus/AddComponentSubmenu.tsx
    - gui/src/components/canvasMenus/__tests__/contextMenus.test.tsx
  modified:
    - gui/src/components/CanvasPanel.tsx
    - gui/src/components/sidebar/InstanceNameField.tsx
    - gui/src/components/ui/context-menu.tsx

key-decisions:
  - "D-11 implemented: Popover as context-menu host; PopoverAnchor 1x1 fixed at right-click coords; PopoverContent wraps node/edge/pane menus"
  - "D-14 implemented: Show errors HIDDEN (Phase 71 TODO comments); Auto-Layout grayed-out with explicit (future) suffix; Show generated Julia code opens bottom panel + dispatches stream:show-code-for"
  - "W10 deviation: ContextMenuItem requires Radix MenuContentContext unavailable in Popover; added PopoverMenuItem/PopoverMenuSub* context-free primitives to context-menu.tsx with identical Tailwind styling"
  - "stream:focus-instance-name CustomEvent co-locates rename focus logic in InstanceNameField.tsx (W7 lock)"

requirements-completed: []

# Metrics
duration: ~65min
completed: 2026-05-14
---

# Phase 65 Plan 05: Context Menus Wired to Canvas Surfaces Summary

**One-liner:** shadcn/Radix Popover hosts three canvas context menus (node/edge/pane) at right-click screen coords; items dispatch Plans 03+04 store actions; PopoverMenuItem primitives added to context-menu.tsx to sidestep Radix MenuContentContext constraint.

## Performance

- **Duration:** ~65 min
- **Started:** 2026-05-14T13:45:00Z
- **Completed:** 2026-05-14T14:51:32Z
- **Tasks:** 3 of 4 automated (Task 4 is checkpoint:human-verify)
- **Files modified:** 8

## Accomplishments

### Task 1: NodeContextMenu + EdgeContextMenu

- `NodeContextMenu({nodeId, onClose})`: Rename (stream:focus-instance-name dispatch + selectNode), Duplicate (selectNode + duplicateSelection), Show generated Julia code (bottomPanel open guard + stream:show-code-for dispatch), Delete (removeNode). Show errors HIDDEN per D-14.
- `EdgeContextMenu({edgeId, onClose})`: Delete via `onEdgesChange([{id, type:'remove'}])`. Show errors HIDDEN.

### Task 2: CanvasContextMenu + AddComponentSubmenu + InstanceNameField

- `CanvasContextMenu({flowPosition, onClose})`: Paste (pasteFromClipboard), Auto-Layout (future) (disabled), Add Component submenu.
- `AddComponentSubmenu({flowPosition, onClose})`: iterates `getAllComponents()`, groups by category (alphabetical), renders per-category `PopoverMenuSub` with per-component `PopoverMenuItem` calling `addNode(id, flowPosition)`.
- `InstanceNameField`: added `useRef<HTMLInputElement>`, `data-instance-name-input` attribute, `useEffect` listening for `stream:focus-instance-name` CustomEvent → `inputRef.current?.focus(); inputRef.current?.select()`. No changes to SidebarPanel.tsx.

### Task 3: CanvasPanel wiring + vitest coverage

- `CanvasPanel`: imports 3 menu components + Popover primitives; computes `flowPosition` via `screenToFlowPosition` for pane menus; renders `<Popover open={rcMenu.state.kind !== null}>` with `<PopoverAnchor style={{position:'fixed', left:screenX, top:screenY, width:1, height:1}}/>` and `<PopoverContent>` switching on `rcMenu.state.kind`.
- `context-menu.tsx`: added `PopoverMenuItem`, `PopoverMenuSeparator`, `PopoverMenuSub`, `PopoverMenuSubTrigger`, `PopoverMenuSubContent` — Radix-context-free primitives styled to match ContextMenuItem (same Tailwind classes).
- `contextMenus.test.tsx`: 4 vitest cases — NodeContextMenu item set (Rename/Duplicate/Show code/Delete, no Show errors), Delete click-through (onClose + store mutation), EdgeContextMenu Delete only, CanvasContextMenu Paste+disabled Auto-Layout+Add Component. **4/4 pass**.

## Task Commits

| Task | Description | Commit |
|------|-------------|--------|
| 1 | NodeContextMenu + EdgeContextMenu | `680fc89` |
| 2 | CanvasContextMenu + AddComponentSubmenu + InstanceNameField | `a9b0f07` |
| 3 | CanvasPanel wiring + PopoverMenuItem* + tests | `638a733` |

## Verification Results

| Check | Expected | Actual | Pass? |
|-------|----------|--------|-------|
| `tsc --noEmit` new errors in touched files | 0 | 0 | Yes |
| `vitest run contextMenus.test.tsx` | 4/4 | 4/4 | Yes |
| Full `vitest run` new failures | 0 | 0 (1 pre-existing SidebarPanel.anchors unchanged) | Yes |
| NodeContextMenu: duplicateSelection | 1 | 2 (call + comment) | Yes (≥1) |
| NodeContextMenu: stream:focus-instance-name | 1 | 1 | Yes |
| NodeContextMenu: Show errors NOT active | 0 | 0 | Yes |
| EdgeContextMenu: onEdgesChange | ≥1 | 1 | Yes |
| CanvasContextMenu: pasteFromClipboard | 1 | 1 | Yes |
| CanvasContextMenu: Auto-Layout (future) | 1 | 1 | Yes |
| CanvasContextMenu: disabled | ≥1 | 1 | Yes |
| AddComponentSubmenu: getAllComponents | ≥1 | 2 (import+call) | Yes |
| AddComponentSubmenu: addNode | 1 | 1 | Yes |
| InstanceNameField: data-instance-name-input | ≥1 | 1 | Yes |
| InstanceNameField: stream:focus-instance-name | 1 | 3 (event name in useEffect/dispatch/handler) | Yes |
| SidebarPanel: no wiring | 0 | 0 | Yes |
| CanvasPanel: NodeContextMenu/EdgeContextMenu/CanvasContextMenu | ≥3 | 8 (import+render) | Yes |
| CanvasPanel: rcMenu.state.kind | ≥1 | 5 | Yes |
| CanvasPanel: rcMenu.close | ≥1 | 6 | Yes |

## Deviations from Plan

### Auto-fixed: Radix MenuContentContext constraint

**[Rule 1 - Bug] ContextMenuItem cannot render inside Popover without ContextMenu.Root ancestor**

- **Found during:** Task 3 (first test run)
- **Issue:** `ContextMenuItem` wraps `ContextMenuPrimitive.Item` which calls `useContext(MenuContentContext)` and throws: `"MenuItem must be used within MenuContent"`. The plan assumed items would "render as styled div[role=menuitem] elements that work fine inside a Popover" — this assumption was incorrect for Radix v1.
- **Fix:** Added `PopoverMenuItem`, `PopoverMenuSeparator`, `PopoverMenuSub`, `PopoverMenuSubTrigger`, `PopoverMenuSubContent` to `gui/src/components/ui/context-menu.tsx` — pure HTML + Tailwind styled identically to their ContextMenu* counterparts. All four menu components (`NodeContextMenu`, `EdgeContextMenu`, `CanvasContextMenu`, `AddComponentSubmenu`) switched to these context-free primitives. The `ContextMenuInlineContent` intermediate attempt was also removed (superseded by PopoverMenuItem approach).
- **Files modified:** `gui/src/components/ui/context-menu.tsx`, all four canvasMenus components
- **Commit:** `638a733`

## Known Stubs

- `stream:show-code-for` CustomEvent: dispatched by NodeContextMenu "Show generated Julia code" but no listener exists yet. Phase 66 will add the CodePreview scroll-to-section listener. Comment in NodeContextMenu.tsx: `// TODO: Phase 66 — listen to stream:show-code-for and scroll the CodePreview to the matching section.`
- Task 4 (checkpoint:human-verify): manual smoke test pending.

## Threat Flags

No new security-relevant surface. T-65-07 (addNode from registry — trusted source) is accept disposition per plan threat model. No untrusted-input path introduced.

## Self-Check: PASSED

| Item | Status |
|------|--------|
| `gui/src/components/canvasMenus/NodeContextMenu.tsx` | FOUND |
| `gui/src/components/canvasMenus/EdgeContextMenu.tsx` | FOUND |
| `gui/src/components/canvasMenus/CanvasContextMenu.tsx` | FOUND |
| `gui/src/components/canvasMenus/AddComponentSubmenu.tsx` | FOUND |
| `gui/src/components/canvasMenus/__tests__/contextMenus.test.tsx` | FOUND |
| `gui/src/components/sidebar/InstanceNameField.tsx` | FOUND |
| `gui/src/components/CanvasPanel.tsx` | FOUND |
| `gui/src/components/ui/context-menu.tsx` | FOUND |
| commit `680fc89` (Task 1) | FOUND |
| commit `a9b0f07` (Task 2) | FOUND |
| commit `638a733` (Task 3) | FOUND |
| `vitest run contextMenus.test.tsx` | 4/4 PASS |
| Full `vitest run` new failures | 0 (1 pre-existing) |
| `tsc --noEmit` new errors | 0 |

---
*Phase: 65-interaction-model-overhaul*
*Completed: 2026-05-14*
