---
status: complete
phase: 68-layers-system-overhaul
source: [68-01-SUMMARY.md, 68-02-SUMMARY.md, 68-03-SUMMARY.md, 68-04-SUMMARY.md, 68-05-SUMMARY.md]
started: 2026-05-17T00:00:00Z
updated: 2026-05-17T01:50:00Z
---

## Current Test

[testing complete]

## Tests

### 1. LayersChip visible top-right with 4 colored squares — SUPERSEDED
expected: Top-right of canvas shows "Layers" chip with 4 colored squares (Blue/Amber/Purple/Red), all at full brightness on cold start.
result: issue
reported: "Right now it looks horrible. Don't love the position [chip dangles below the vertical icon column instead of joining it; horizontal pill in a vertical stack breaks the visual rhythm]. Does not look like a professional scientific tool."
severity: cosmetic
resolution: |
  Original chip deleted (commit 3ffaff2). Replaced by `LayersPanel` docked
  at the bottom of the left sidebar — selected from a 3-way candidate
  comparison (titlebar strip / canvas-overlay row pill / sidebar panel).
  Reasons C won: full layer names, Eye/EyeOff icon as colorblind-safe
  state cue, matches existing sidebar section-header treatment, mirrors
  the docked-panel pattern of every serious engineering tool.
  Re-verify under Test 1' below.

### 1'. LayersPanel docked at bottom of left sidebar — REPLACES Test 1
expected: |
  With the left sidebar expanded (default), the very bottom of the left
  sidebar shows a "LAYERS" section (uppercase muted header matching the
  HYDRAULIC/THERMAL/SOURCES group headers above). Below the header: 4
  rows with colored dot + full layer name + Eye icon, one per layer
  (Hydraulic / Thermal / Sources / Reactor Physics). All 4 rows show
  the Eye icon (not EyeOff) on cold start. Below the rows is a single
  "Off-layer  Dim" cycle-toggle line. The canvas-overlay column on the
  right has only 5 monochrome icons (ZoomIn / ZoomOut / FitView / Lock
  / Grid) — no Layers control there anymore. The titlebar shows only
  the menu (File/Edit/View/Help) and "Untitled" — no Layers control there.
result: pass

### 2. Popover opens with 4 checkboxes + Dim/Hide toggle — SUPERSEDED
expected: Click the LayersChip. A popover opens containing 4 checkboxes labeled Hydraulic / Thermal / Sources / Reactor Physics (each with its color square), all checked by default. Below them is a Dim/Hide toggle pair (Dim selected by default). Click outside → popover closes.
result: issue
reported: "Don't love how much space it takes when open. Dim/Hide doesn't need to be there at all in the final version — okay for now since we don't have preferences yet, but it'll move to Settings later. Popover front-loads too much chrome (header, color squares, checkboxes, OFF-LAYER section, segmented control) for 4 toggles."
severity: cosmetic
resolution: |
  Popover gone — controls are now always-visible in the docked LayersPanel
  (no open/close interaction needed). Dim/Hide cycle-toggle still lives in
  the panel footer per UAT discussion ("we don't have preferences yet so I
  get it for now") and will migrate to Settings dialog in Phase 72.
  Re-verify under Test 2' below.

### 2'. Click any layer row in LayersPanel toggles it — REPLACES Test 2
expected: |
  Click a row in the LAYERS panel (say "Thermal"). The Thermal dot dims
  to ~25% opacity, the "Thermal" label dims to 50% opacity, and the Eye
  icon swaps to EyeOff. Click the same row again → returns to full
  opacity + Eye icon. Each row toggles only its own layer (clicking
  Thermal doesn't change Hydraulic etc.). Hover background appears on
  the row under the cursor and clears when the cursor leaves; no sticky
  highlight after click release.
result: pass

### 3. Toggling a layer off dims off-layer items (Dim mode)
expected: With Dim mode active, drop a Channel and a HeatDiffusion onto the canvas (or open a project that has them). Click "Thermal" in the LayersPanel to turn it off. All Thermal-layer edges/nodes dim to ~20% opacity but remain visible. Click Thermal again → opacity restores.
result: pass

### 4. Switching to Hide mode hides off-layer items
expected: With Thermal still off, click the "Off-layer" footer to cycle Dim → Hide. The previously-dimmed Thermal items disappear entirely (hidden, not just dimmed). Click footer again → returns to Dim, items reappear at low opacity.
result: pass

### 5. Off-layer nodes are non-interactive
expected: With one layer off in Dim mode, try to click a dimmed node — selection ring does NOT appear. Try to drag a dimmed node — it does NOT move. Try to draw a connection FROM a dimmed node's handle — handle does NOT initiate a drag.
result: pass

### 6. Dual-layer node: per-handle dim (ChannelAndContacts)
expected: Drop a ChannelAndContacts onto the canvas (it's both Hydraulic and Thermal). Turn Thermal OFF (keep Hydraulic ON). The CAC node stays fully visible. Its FlowPort handles (left/right edges, top/bottom of body) stay interactive at full opacity. Its ThermalPort handles dim to ~20% and refuse to start a drag.
result: pass

### 7. Layer-aware connect auto-enables hidden layer
expected: Turn Thermal OFF. Drag a connection from a thermal-port handle on one visible node to a thermal-port handle on another visible node (e.g., between two CAC nodes' thermal sides). On completion: the connection is created AND the Thermal layer auto-enables (the row's Eye icon comes back, dot returns to full opacity). No modal, no blocking prompt.
result: pass

### 8. Tab key on canvas does nothing
expected: Click on empty canvas to give it focus. Press Tab. No layer cycling happens. (Tab may still move focus per browser default but does NOT cycle layer state in the LayersPanel.)
result: pass

### 9. ToolboxPanel ignores layer state
expected: Turn any layer OFF in the LayersPanel. Look at the Components tab above. All component categories (Sources / Hydraulic / Thermal / Resources / Reactor Physics) remain visible and draggable in the toolbox regardless of layer state. Toolbox is a stable drag palette, not filtered by layer (D-11).
result: pass

### 10. SecondaryToolbar physically gone
expected: There is NO second strip below the titlebar. The previous Phase 67 layout had two strips (titlebar + secondary holding Layer/Code/Export buttons); now there's only the titlebar. Canvas has ~32px more vertical space.
result: pass

### 11. File menu → "Export to Julia…"
expected: Open the File menu. Below "Save As" and a separator, there's a new "Export to Julia…" item. Click it with any non-empty project — it generates and writes the Julia file via the existing exportCode path (same behavior as the old SecondaryToolbar Export button).
result: pass

### 12. View menu → Toggle Code Preview with Ctrl+`
expected: Open the View menu. There's a "Toggle Code Preview" item with the shortcut "Ctrl+`" shown on the right. Click it → bottom code preview panel toggles. The old "Layer" radio submenu is GONE (only Theme submenu + Toggle Code Preview remain).
result: pass
notes: |
  Also surfaced 3 pre-existing titlebar menu bugs (visible-only after
  Phase 68 increased menu use): 8px dead zone between trigger and submenu,
  trigger highlight stuck after Radix re-focused on close, mouse-leave
  auto-close fired mid-traverse. All three fixed in commit 018f038 —
  shadcn MenubarContent sideOffset 8→0 / alignOffset -4→0, MenubarTrigger
  focus: styling stripped (data-[state=open] is the only highlight),
  CustomTitlebar mouse-leave gets a 200ms grace period.

### 13. Ctrl+` keyboard shortcut toggles code preview globally
expected: With focus on the canvas (not a text input), press Ctrl+` (backtick). Bottom panel toggles open/closed. Press again → toggles back. While typing in a text input (e.g., rename), Ctrl+` does NOT trigger (input-focus guard).
result: pass

### 14. BottomPanel collapse button when open
expected: With the code preview panel open, look at its tab header. There's a chevron-down (or ×) ghost-icon button on the right side with a tooltip "Collapse (Ctrl+`)". Click it → panel closes.
result: pass

### 15. Persistent stub strip when BottomPanel is closed
expected: With the code preview closed, the very bottom of the window shows a thin (~20px) strip labeled "Code" with a ChevronUp icon. Hovering shows a subtle indication it's clickable. Click anywhere on the strip → the panel re-opens.
result: pass

### 16. .scp round-trip preserves layer state + dim/hide setting
expected: Toggle Thermal OFF and Reactor Physics OFF. Switch Dim/Hide pair to Hide. Save the project (File → Save / Save As). Close and reopen (or open the saved .scp). On load: Thermal and Reactor Physics are still unchecked; Hide mode is still selected; layer state persists exactly.
result: pass

### 17. Legacy .scp with old active_layer string loads correctly
expected: Open one of the legacy export samples (e.g., `gui/export_examples/test.scp`, `project.streamgui` — anything saved before Phase 68). On load: the legacy `layout.active_layer` string maps to the new 4-layer state ("Both" → all on; "Hydraulic" → Hydraulic on + others off; "Thermal" → Thermal on + others off). hideOffLayer defaults to false (Dim mode). No crash, no console error about the missing field.
result: pass

## Summary

total: 19
passed: 17
issues: 2
pending: 0
skipped: 0
blocked: 0

## Gaps

- truth: "Layer control sits cleanly in the GUI and reads as a professional scientific tool"
  status: resolved
  reason: "User reported (test 1): 'Right now it looks horrible. Don't love the position [chip dangles below the vertical icon column instead of joining it; horizontal pill in a vertical stack breaks the visual rhythm]. Does not look like a professional scientific tool.' Screenshots in ~/projects/temp_screenshots/layers.png."
  severity: cosmetic
  test: 1
  artifacts: []
  missing: []
  root_cause: "Single 32×32 button in the canvas overlay column couldn't carry both per-layer state AND identity for 4 distinct items; icon-only encoding is illegible and color-only fails colorblind users."
  resolution: "Redesigned through a 3-way candidate comparison (titlebar strip / canvas-overlay row pill / docked sidebar panel). User picked C; chip + 4-bar-icon iteration deleted. New permanent home: LayersPanel docked at bottom of left sidebar — full names + Eye/EyeOff icons + matches existing sidebar section-header treatment. Commit 3ffaff2."

- truth: "Layer control surface is compact and shows only what's needed"
  status: resolved
  reason: "User reported (test 2): 'Don't love how much space it takes when open. Dim/Hide doesn't need to be there at all in the final version — okay for now since we don't have preferences yet, but it'll move to Settings later. Popover front-loads too much chrome (header, color squares, checkboxes, OFF-LAYER section, segmented control) for 4 toggles.' Screenshots in ~/projects/temp_screenshots/layers_open.png."
  severity: cosmetic
  test: 2
  artifacts: []
  missing: []
  root_cause: "Popover-based toggle UX layered chrome (header + section headers + segmented controls) on top of 4 simple toggles."
  resolution: "Popover deleted entirely — all 4 toggles + Dim/Hide cycle-toggle are now always-visible click-rows in the LayersPanel. Single-click toggle. No popover open/close interaction. Dim/Hide stays in the panel footer until Settings dialog ships in Phase 72. Commit 3ffaff2."
