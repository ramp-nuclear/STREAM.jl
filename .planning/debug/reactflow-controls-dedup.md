---
status: diagnosed
trigger: "Phase 65 Plan 06 UAT Test 14 / Gap: hide ReactFlow's built-in bottom-left Controls (zoom/fit/lock) — they feel redundant alongside the new top-right canvas overlay."
created: 2026-05-15
updated: 2026-05-15
---

## Current Focus

hypothesis: ReactFlow `<Controls />` is rendered unconditionally inside CanvasPanel.tsx and the top-right overlay currently has only SnapToGridButton — no replacement for zoom/fit/lock.
test: Read CanvasPanel.tsx and SnapToGridButton.tsx; grep for any other top-right overlay buttons under `gui/src/`.
expecting: Confirm a single `<Controls />` render site and a top-right overlay container with one child.
next_action: Diagnosis complete — return ROOT CAUSE FOUND.

## Symptoms

expected: Canvas shows only the new top-right overlay buttons; ReactFlow's bottom-left built-in `<Controls />` (zoom in/out, fit-view, interactive-lock) is hidden.
actual: Both render. Bottom-left ReactFlow Controls + top-right overlay (currently just SnapToGridButton) are both visible — redundant chrome.
errors: (none — cosmetic / UX)
reproduction: Phase 65-UAT.md Test 14 — open Composer GUI with any project loaded; observe both bottom-left ReactFlow Controls and top-right SnapToGridButton are present.
started: Pre-existing (default `<Controls />` was never hidden); UAT flagged it once Plan 06 added the top-right overlay.

## Eliminated

(none — diagnosis was direct read of the render tree)

## Evidence

- timestamp: 2026-05-15
  checked: gui/src/components/CanvasPanel.tsx imports and JSX
  found: Line 4 imports `Controls` from `@xyflow/react`. Line 328 renders `<Controls />` unconditionally as a child of `<ReactFlow>` with no props (so all default sub-controls render: zoom-in, zoom-out, fit-view, interactive-lock).
  implication: Single render site. Hiding is a one-line removal.

- timestamp: 2026-05-15
  checked: gui/src/components/CanvasPanel.tsx lines 332-335 (top-right overlay div)
  found: `<div className="absolute top-2 right-2 z-10">` contains exactly one child: `<SnapToGridButton />`. No zoom/fit/lock buttons currently in the top-right overlay.
  implication: If `<Controls />` is removed without adding replacements, the user loses zoom-in/out, fit-view, and interactive-lock buttons entirely. Keyboard/mouse-wheel zoom and trackpad pan still work via ReactFlow defaults, but explicit fit-view and interactive-lock have no other entry point.

- timestamp: 2026-05-15
  checked: gui/src/components/canvasMenus/ directory + grep for "top-2 right-2" across gui/src/
  found: canvasMenus/ contains AddComponentSubmenu, CanvasContextMenu, EdgeContextMenu, NodeContextMenu, SnapToGridButton. Only one `.absolute.top-2.right-2.z-10` container in the codebase (CanvasPanel.tsx:333). No latent zoom/fit/lock buttons.
  implication: Confirms gap — no existing replacements anywhere.

- timestamp: 2026-05-15
  checked: .planning/phases/65-interaction-model-overhaul/65-UAT.md lines 78, 82, 171, 178
  found: Truth and note explicitly say "remove" or "either remove it or render Controls without the built-in buttons we duplicate" — but only SnapToGridButton is in the top-right today, so nothing is actually duplicated yet.
  implication: User's stated wording leans toward (a) just remove; planner should make explicit choice.

## Resolution

root_cause: |
  In `gui/src/components/CanvasPanel.tsx` line 328, the ReactFlow `<Controls />` element is rendered unconditionally as a child of `<ReactFlow>` with no props, producing the default bottom-left panel with zoom-in / zoom-out / fit-view / interactive-lock buttons. The new top-right overlay container at line 333 (`<div className="absolute top-2 right-2 z-10">`) contains only `<SnapToGridButton />` — it does NOT duplicate any of the four bottom-left functions, so the redundancy the UAT note implies does not actually exist yet. Removing `<Controls />` is mechanically trivial (delete one line), but doing so without compensating in the top-right overlay forfeits zoom/fit/lock UI entry points entirely.
fix: (pending — planner to choose path a or b)
verification: (pending)
files_changed: []
