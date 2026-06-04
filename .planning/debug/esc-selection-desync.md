---
status: resolved
resolved: 2026-05-21
resolved_in: "Phase 65 Plan 10 — SidebarPanel.tsx:103-131 now mirrors CanvasPanel.tsx:266-275 input-focus guard (HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement | isContentEditable → return early). With both Esc handlers skipping on input focus, Esc-in-input is a no-op and the zustand selection slice + ReactFlow nodes[].selected flag stay in lockstep."
trigger: "Esc inside text input clears properties panel but leaves canvas outline — state desync between two selection sources"
created: 2026-05-15T00:00:00Z
updated: 2026-05-21
---

## Current Focus

hypothesis: CONFIRMED — SidebarPanel.tsx document-level Esc keydown listener (lines 80-95) does NOT check `e.target` / activeElement and unconditionally calls `clearSelection()`. CanvasPanel.tsx window listener (line 266+) DOES check input focus and skips. Result: when Esc fires inside an input, only the zustand half (`selectionKind`/`selectedNodeId`) is cleared; ReactFlow's `nodes[].selected` flag (which drives StreamNode's `ring-2 ring-[var(--ring)]` outline on line 361) is left set.
test: traced both Esc handlers, verified input components have no Esc handling, verified clearSelection() does not touch ReactFlow per-node flags.
expecting: diagnosis complete.
next_action: emit ROOT CAUSE FOUND.

## Symptoms

expected: Esc inside a focused text input does NOT change selection (properties panel and canvas stay aligned with previously selected node).
actual: Esc clears the properties panel (shows "nothing selected") but the canvas still shows a selection outline around the previously selected node — state desync.
errors: none — visual/state mismatch only.
reproduction: Test 7 in .planning/phases/65-interaction-model-overhaul/65-UAT.md. Focus a text input in sidebar, press Esc, observe canvas outline persists while sidebar shows no selection.
started: After Plan 65-03 (interaction model overhaul) introduced Esc handler in CanvasPanel keydown useEffect.

## Eliminated

- hypothesis: Browser default Esc-in-input behavior (blur input → cascade clears selection)
  evidence: SidebarPanel.tsx:80-95 has an explicit document-level keydown listener that unconditionally calls clearSelection() on Escape when selectionKind != "none". This is the proximate cause, not browser default behavior. Inputs (InstanceNameField, NumericField) have no onKeyDown handlers — Esc bubbles unhandled directly to the SidebarPanel document listener.
  timestamp: 2026-05-15

- hypothesis: CanvasPanel Esc handler (Plan 03) is missing the activeElement check
  evidence: CanvasPanel.tsx:266-275 correctly checks e.target for HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement | isContentEditable and returns early. The Plan 03 handler is fine; the bug is in a separate (older, Phase 62-09) document-level listener in SidebarPanel that was never updated to match.
  timestamp: 2026-05-15

## Evidence

- timestamp: 2026-05-15
  checked: All `Escape` / `'Esc'` handlers across gui/src
  found: Three relevant handlers — (1) CanvasPanel.tsx:266 window listener (input-aware, correct); (2) SidebarPanel.tsx:80 document listener (input-blind, the bug); (3) AutoRecoverRestoreModal + ResourceCreationPopover + PopoverContent in CanvasPanel onEscapeKeyDown — all scoped to Radix overlays that aren't open during plain sidebar-input editing.
  implication: Only SidebarPanel.tsx:80 fires on Esc-in-sidebar-input. It is the desync source.

- timestamp: 2026-05-15
  checked: SidebarPanel.tsx:80-95 keydown listener
  found: ```ts
  const handler = (e: KeyboardEvent) => {
    if (e.defaultPrevented) return;
    if (e.key !== "Escape") return;
    if (useStore.getState().selectionKind !== "none") {
      useStore.getState().clearSelection();
    }
  };
  document.addEventListener("keydown", handler);
  ```
  No target/activeElement check. The `e.defaultPrevented` guard is dead in this context — sidebar Inputs don't call `preventDefault()` on Esc. The "Esc precedence cascade" comment (lines 27-36) explicitly says higher layers (popover, inline-rename, context-menu) preventDefault on Esc — but plain text inputs in the Properties form are NOT in that cascade and therefore do not block this tail.
  implication: This handler fires on every Esc keystroke, regardless of focus target.

- timestamp: 2026-05-15
  checked: useStore.ts:1762 clearSelection action
  found: ```ts
  clearSelection: () =>
    set({
      selectedNodeId: null,
      selectedResourceId: null,
      selectedResourceKind: null,
      selectionKind: "none",
    }),
  ```
  Mutates only zustand selection slice. Does NOT call setNodes / does NOT touch the `nodes[].selected` flag.
  implication: After clearSelection() runs, ReactFlow's internal per-node `selected: true` flag is still set on the previously-selected node.

- timestamp: 2026-05-15
  checked: StreamNode.tsx:361 outline rendering
  found: `className={... ${selected ? "ring-2 ring-[var(--ring)]" : ""} ...}` — the `selected` prop comes from ReactFlow's NodeProps (i.e., from `node.selected` in the nodes array, not from zustand).
  implication: The canvas outline persists because `node.selected` is still true. The two sources of selection state (zustand selection slice vs ReactFlow per-node flag) are independent.

- timestamp: 2026-05-15
  checked: CanvasPanel.tsx:266-280 Esc handler (Plan 03)
  found: When Esc fires WITHOUT an input focused, this handler does the full job — `selectNode(null)` AND `setNodes((ns) => ns.map((n) => (n.selected ? { ...n, selected: false } : n)))` AND the equivalent for edges. Both stores are cleared. But when an input IS focused, it returns early on line 274 (correct skip), leaving the work to whoever else handles Esc — which is SidebarPanel's input-blind clearSelection-only listener.
  implication: The canvas handler does both halves; the sidebar handler does only one. When the input-skip path fires in CanvasPanel, the sidebar handler still runs and creates the desync.

- timestamp: 2026-05-15
  checked: useStore.ts:1015-1028 D-22 selection sync
  found: ReactFlow → zustand sync exists (`onNodesChange` detects `c.type === "select"` and calls `selectNode(c.id)` / `selectNode(null)`). This is one-way.
  implication: There is no reverse sync (zustand → ReactFlow per-node flag). So clearing zustand-only via clearSelection() will not propagate back to `nodes[].selected`. This is by design (sync would loop), but it means any code path that wants to "deselect" must clear both sides.

## Resolution

root_cause: |
  Esc-key handling for selection-clearing is split across two independent listeners that operate on two independent state sources, and the older listener does not perform the input-focus guard that the newer one does:

  (A) Zustand selection slice: `selectedNodeId` + `selectionKind` — drives SidebarPanel (Properties panel body).
  (B) ReactFlow per-node `selected` flag: `nodes[i].selected` — drives StreamNode's `ring-2 ring-[var(--ring)]` outline on the canvas (StreamNode.tsx:361).

  - CanvasPanel.tsx:266-280 (Plan 65-03) is the canonical Esc handler: it (i) checks `e.target instanceof HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement | isContentEditable` and returns early if so, (ii) when it does fire, it clears BOTH (A) via `selectNode(null)` and (B) via `setNodes(... selected: false ...)`.
  - SidebarPanel.tsx:80-95 (Phase 62-09 Esc cascade tail, predates Plan 03) is a document-level Esc listener that (i) does NOT check `e.target` / `document.activeElement`, and (ii) only clears (A) via `clearSelection()`.

  When the user presses Esc while a sidebar text input has focus:
   1. SidebarPanel's document listener fires, clears (A) → Properties panel shows "No selection".
   2. CanvasPanel's window listener fires, sees `HTMLInputElement` target, returns early → (B) untouched, ReactFlow keeps `node.selected = true`.
   3. StreamNode re-renders with `selected=true` still → outline persists on canvas.

   That is exactly the symptom: Properties panel deselected, canvas outline retained.

  Secondary contributor: `useStore.clearSelection()` (useStore.ts:1762-1768) is intentionally narrow (no setNodes side-effect), so any caller relying on it alone — like the SidebarPanel listener — leaves (B) dangling. The reverse-sync path that does exist (D-22 at useStore.ts:1015-1028) is ReactFlow → zustand, not zustand → ReactFlow.

fix:
verification:
files_changed: []
