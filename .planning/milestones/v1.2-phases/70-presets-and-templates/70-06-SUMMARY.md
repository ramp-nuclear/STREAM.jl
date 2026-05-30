---
phase: 70-presets-and-templates
plan: "06"
subsystem: gui
tags: [presets, keybind, file-menu, context-menu, canvas-drop, custom-event, tauri]
dependency_graph:
  requires:
    - 70-04 (PresetsPanel component)
    - 70-05 (SavePresetModal component, stream:open-save-preset event contract)
    - 70-03 (loadPresetAtPosition, loadPresetFromPath store actions)
    - 70-02 (autoExtendSelection, presetIO)
  provides:
    - gui/src/App.tsx — Ctrl+4 keybind, 4th Presets tab, SavePresetModal top-level mount
    - gui/src/components/FileMenu.tsx — Load preset… + Save selection as preset… menu items
    - gui/src/components/canvasMenus/NodeContextMenu.tsx — Save selection as preset… context item
    - gui/src/components/CanvasPanel.tsx — application/stream-preset drop handler
  affects:
    - gui/src/App.tsx (modified)
    - gui/src/components/FileMenu.tsx (modified)
    - gui/src/components/canvasMenus/NodeContextMenu.tsx (modified)
    - gui/src/components/CanvasPanel.tsx (modified)
tech_stack:
  added: []
  patterns:
    - "Custom DOM event stream:open-save-preset dispatched from FileMenu + NodeContextMenu, handled in App.tsx (mirrors gsd:open-command-palette / stream:focus-instance-name pattern)"
    - "Dynamic import of presetIO.autoExtendSelection in trigger sites to pre-paint amber outline before modal opens"
    - "async onDrop callback in CanvasPanel for await loadPresetAtPosition"
    - "useReactFlow().getViewport() viewport-center math in FileMenu (D-17)"
key_files:
  created: []
  modified:
    - gui/src/App.tsx
    - gui/src/components/FileMenu.tsx
    - gui/src/components/canvasMenus/NodeContextMenu.tsx
    - gui/src/components/CanvasPanel.tsx
decisions:
  - "SavePresetModal lifted to App.tsx (option a) — custom event stream:open-save-preset keeps FileMenu + NodeContextMenu decoupled; mirrors CommandPalette pattern already in App.tsx"
  - "Dynamic import of autoExtendSelection in trigger sites avoids pulling presetIO into FileMenu/NodeContextMenu module graphs eagerly; acceptable since open-modal is not a hot path"
  - "onDrop promoted to async in CanvasPanel to await loadPresetAtPosition; React.DragEventHandler accepts async callbacks without type issues"
  - "selectionCount read via useStore selector (not getState()) in NodeContextMenu — ensures re-render on selection change (Pitfall 9)"
  - "ResponsiveTabsList.value typed as generic string — no union widening needed (Task 2 no-op)"
metrics:
  duration: "~25 minutes"
  completed_date: "2026-05-20"
  tasks_completed: 5
  tasks_total: 6
  files_created: 0
  files_modified: 4
---

# Phase 70 Plan 06: UI Wiring — Triggers, Tabs, Drop Handler Summary

## One-liner

Wire all Phase 70 entry points: Ctrl+4 + 4th Presets tab in App.tsx, File menu Load/Save entries, node context-menu Save item, and canvas drop handler for `application/stream-preset`.

## What Was Built

### Task 1 — App.tsx: Ctrl+4, 4th tab, SavePresetModal mount (commit 2d10200)

Five surgical changes to `gui/src/App.tsx`:

1. **Imports**: Added `BookMarked` from lucide-react; added `PresetsPanel` and `SavePresetModal` component imports.

2. **Ctrl+4 keybind**: Extended `handleLeftTabKey` effect with an `else if (e.key === "4")` branch calling `setActiveLeftTab("Presets")`. Matches the bare-Ctrl pattern of Ctrl+1/2/3 (no Shift/Alt/Meta, matches D-01).

3. **onValueChange casts**: Both `Tabs onValueChange` and `ResponsiveTabsList onValueChange` cast strings widened from `"Components" | "Resources" | "Project"` to `"Components" | "Resources" | "Project" | "Presets"`.

4. **4th tab**: Added `{ value: "Presets", label: "Presets", icon: BookMarked }` as 4th entry in the `tabs` array, and a corresponding `<TabsContent value="Presets">` mounting `<PresetsPanel />`.

5. **SavePresetModal mount**: Lifted `savePresetOpen` boolean state into App with a `useEffect` listener for `window.addEventListener("stream:open-save-preset", ...)`. Mounted `<SavePresetModal open={savePresetOpen} onOpenChange={setSavePresetOpen} />` as a sibling to `<CommandPalette>` inside `<TooltipProvider>` (inside `<ReactFlowProvider>` — required for any descendant `useReactFlow()` calls).

### Task 2 — ResponsiveTabsList type check (no-op)

`ResponsiveTab.value` is typed as `string` (not a constrained union), so App.tsx's `"Presets"` entry passes without modification. Confirmed via `tsc --noEmit` showing zero ResponsiveTabsList errors. No file changed.

### Task 3 — FileMenu.tsx: two new menu items (commit a1e05e1)

Added to `gui/src/components/FileMenu.tsx`:

- **`useReactFlow` import** — for `getViewport()` viewport-center math (D-17).
- **`selectedNodeCount` selector** — `useStore((s) => s.nodes.filter((n) => n.selected).length)` drives the `disabled` prop.
- **`handleSaveSelectionAsPreset`** — dynamic-imports `autoExtendSelection` from `presetIO`, computes the `extras` set (BC-hop-only auto-extended IDs not in the original selection), sets `data.autoExtended = true` on those nodes via `useStore.setState`, then dispatches `new CustomEvent("stream:open-save-preset")`.
- **`handleLoadPreset`** — reads viewport via `getViewport()`, computes `centerX/centerY` using the `(-vp.x + innerWidth/2) / vp.zoom` formula (RESEARCH.md Q6 Option A), and calls `useStore.getState().loadPresetFromPath({ x: centerX, y: centerY })`.
- **Menu item order** (UI-SPEC Surface 7): existing `MenubarSeparator` → `Load preset…` → `Save selection as preset… (disabled when < 2)` → new `MenubarSeparator` → `Export to Julia…`.

### Task 4 — NodeContextMenu.tsx: Save selection as preset… item (commit 3771342)

Added to `gui/src/components/canvasMenus/NodeContextMenu.tsx`:

- **`selectionCount` selector** — `useStore((s) => s.nodes.filter((n) => n.selected).length)` read at render time (Pitfall 9: reactive to selection changes, not stale `getState()`).
- **`handleSaveSelectionAsPreset`** — identical logic to FileMenu's handler: dynamic-import `autoExtendSelection`, pre-paint `data.autoExtended` on extras, dispatch `"stream:open-save-preset"`, call `onClose()`.
- **Render guard** — `{selectionCount >= 2 && (<DropdownMenuItem onSelect={handleSaveSelectionAsPreset}>Save selection as preset…</DropdownMenuItem>)}` inserted between "Show generated Julia code" and `<DropdownMenuSeparator />`. Per UI-SPEC Surface 6: render guard (not `disabled`) — item is invisible when < 2 nodes selected.

### Task 5 — CanvasPanel.tsx: application/stream-preset drop handler (commit f3eccda)

Modified `onDrop` in `gui/src/components/CanvasPanel.tsx`:

- **Promoted to `async`** to support `await loadPresetAtPosition(...)`.
- **New branch** added BEFORE the existing `application/streamcomponent` branch:
  ```
  const presetRaw = event.dataTransfer.getData("application/stream-preset");
  if (presetRaw) {
    // parse { filePath, store } with try/catch (T-70-23)
    // translate clientX/Y → flow coords via screenToFlowPosition
    // await loadPresetAtPosition(filePath, { x: flowPos.x, y: flowPos.y })
    return;
  }
  ```
  The `return` after the preset branch prevents fall-through to the component branch. MIME types are disjoint (`application/stream-preset` vs `application/streamcomponent`) so no interference in either direction.
- **`onDragOver`** already calls `event.preventDefault()` unconditionally — no change needed to allow preset drops.

### Task 6 — Manual UAT (pending)

Task 6 is a `checkpoint:human-verify` requiring a full Tauri rebuild (`cd gui && npm run tauri dev`) to activate the `watch` feature flag from plan 70-01. The 16-step UAT exercises every Phase 70 surface end-to-end. This task is not automated — it awaits user execution. No code changes in this task.

## Deviations from Plan

None — plan executed exactly as written.

The Task 3 plan showed `handleLoadPreset` calling `loadPresetFromPath({ centerX, centerY })` with named properties, but the store signature (plan 70-03) is `loadPresetFromPath(anchor: { x: number; y: number })`. Used `{ x: centerX, y: centerY }` to match the actual store interface. This is a trivial property-name reconciliation, not a deviation.

## Threat Model Compliance

| Threat ID | Status | Notes |
|-----------|--------|-------|
| T-70-22 | ACCEPTED | `stream:open-save-preset` custom event — Tauri WebView is same-origin; modal is harmless on its own. |
| T-70-23 | MITIGATED | `JSON.parse` inside try/catch in `onDrop`; result passed to `loadPresetAtPosition` which calls `deserializePreset` (strict version/kind check). |
| T-70-24 | MITIGATED | `deserializePreset` enforces `format_version` and `kind` in `loadPresetFromPath`. |
| T-70-25 | ACCEPTED | Reveal-in-Finder scope already bounded by plan 70-01 ACL. |
| T-70-SC | N/A | No new npm/cargo installs in this plan. |

## Known Stubs

None — all trigger surfaces are fully wired. Task 6 (UAT) is the only remaining step and it is a manual verification task, not a code stub.

## Threat Flags

None — no new network endpoints, auth paths, file-access patterns, or schema changes at trust boundaries beyond what is in the plan's threat model.

## Self-Check: PASSED

- [x] `grep -E "e.key === \"4\"" gui/src/App.tsx` — Ctrl+4 handler present
- [x] `grep -E "value=\"Presets\"" gui/src/App.tsx` — TabsContent slot present
- [x] `grep -E "stream:open-save-preset" gui/src/App.tsx` — event listener present
- [x] `grep -E "SavePresetModal" gui/src/App.tsx` — modal mounted
- [x] `grep -E "BookMarked" gui/src/App.tsx` — icon imported and used in tabs array
- [x] `grep -E "Load preset…" gui/src/components/FileMenu.tsx` — menu item present
- [x] `grep -E "Save selection as preset…" gui/src/components/FileMenu.tsx` — menu item present
- [x] `grep -E "disabled=\{selectedNodeCount < 2\}" gui/src/components/FileMenu.tsx` — disabled guard present
- [x] `grep -E "selectionCount >= 2" gui/src/components/canvasMenus/NodeContextMenu.tsx` — render guard present
- [x] `grep -E "Save selection as preset…" gui/src/components/canvasMenus/NodeContextMenu.tsx` — item present
- [x] `grep -E "application/stream-preset" gui/src/components/CanvasPanel.tsx` — drop handler present
- [x] `grep -E "loadPresetAtPosition" gui/src/components/CanvasPanel.tsx` — store action called
- [x] No tsc errors in App.tsx, FileMenu.tsx, NodeContextMenu.tsx, CanvasPanel.tsx
- [x] Commit 2d10200 exists (Task 1 — App.tsx)
- [x] Commit a1e05e1 exists (Task 3 — FileMenu.tsx)
- [x] Commit 3771342 exists (Task 4 — NodeContextMenu.tsx)
- [x] Commit f3eccda exists (Task 5 — CanvasPanel.tsx)
- [x] ResponsiveTabsList already generic — no edit required (Task 2)
</content>
</invoke>