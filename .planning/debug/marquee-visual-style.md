---
status: resolved
resolved: 2026-05-21
resolved_in: "Phase 65 follow-up — gui/src/index.css now contains both override blocks (.react-flow__selection at line 161 with solid color-mix border + .react-flow__nodesselection-rect display:none at line 173). Marquee renders with solid theme-aligned border; post-release bounding box is suppressed."
trigger: "Two cosmetic UX issues with left-marquee selection: (1) dotted border on selection rectangle, (2) bounding box wraps selected nodes after release"
created: 2026-05-15T13:22:18Z
updated: 2026-05-21
---

## Current Focus

hypothesis: Default `@xyflow/react` v12 styles are in effect with no project-level overrides. `.react-flow__selection` controls the in-drag marquee rectangle (dotted); `.react-flow__nodesselection-rect` controls the post-selection bounding box around selected nodes.
test: Find the file importing ReactFlow's CSS, grep for any existing overrides, confirm v12 class names by reading node_modules.
expecting: Confirmation that no overrides exist for either class; identification of the file:line where the override CSS should be added.
next_action: Read 65-UAT.md Test 4, 65-03-SUMMARY.md, CanvasPanel.tsx, locate ReactFlow CSS import, grep for selection class overrides.

## Symptoms

expected:
- A. Marquee selection rectangle border: full line, slightly brighter than fill, fits the GUI theme (currently dotted/default).
- B. After releasing marquee selection, NO bounding box wraps the selected nodes — selection is conveyed only by per-node highlight.

actual:
- Selection rectangle border is dotted (default `@xyflow/react` styling).
- After releasing, a bounding box wraps all selected nodes.

errors: none (cosmetic only)
reproduction: Phase 65 UAT Test 4 — marquee-select multiple nodes on canvas.
started: Phase 65 Plan 03 added `selectionOnDrag` + `SelectionMode.Partial` ReactFlow props without custom CSS.

## Eliminated

(none yet)

## Evidence

- timestamp: 2026-05-15T13:23:00Z
  checked: gui/src/components/CanvasPanel.tsx import section (lines 1-17)
  found: ReactFlow default stylesheet is imported at CanvasPanel.tsx:17 — `import "@xyflow/react/dist/style.css";`. This is the only ReactFlow CSS import in the codebase (grep for `@xyflow/react/dist/style` returned exactly one hit).
  implication: All marquee/selection styling currently comes from this default stylesheet. Any project-level override must come from a CSS file loaded after it (index.css works — both are bundled by Vite, and our overrides are written with higher specificity / later cascade source).

- timestamp: 2026-05-15T13:23:10Z
  checked: grep for `react-flow__selection` and `nodesselection` across `gui/src/`
  found: ZERO matches. No project-level override exists for either class. The only `.react-flow__*` overrides in the project are `.react-flow__handle` (cursor fix) at gui/src/index.css:126-132.
  implication: Adding new rules for `.react-flow__selection` and `.react-flow__nodesselection-rect` is purely additive — no existing rules to compete with or refactor.

- timestamp: 2026-05-15T13:23:25Z
  checked: gui/node_modules/@xyflow/react/dist/style.css (version 12.10.2, confirmed via gui/package.json `"@xyflow/react": "^12.10.2"`)
  found: v12 class names are exactly `.react-flow__selection` (in-drag marquee, z-index 6) and `.react-flow__nodesselection-rect` (post-selection bounding box, child of `.react-flow__nodesselection` wrapper at z-index 3). Lines 486-490 define the shared default styling for both:
    background: var(--xy-selection-background-color, var(--xy-selection-background-color-default));
    border:     var(--xy-selection-border,           var(--xy-selection-border-default));
  Default token values (lines 39-40 light, 85-86 dark):
    light: background rgba(0, 89, 220, 0.08),   border 1px dotted rgba(0, 89, 220, 0.8)
    dark:  background rgba(200, 200, 220, 0.08), border 1px dotted rgba(200, 200, 220, 0.8)
  implication: The "dotted border" complaint is literally the default `1px dotted ...` value of `--xy-selection-border-default`. Two override strategies are available:
    1) Override the CSS variables `--xy-selection-background-color` / `--xy-selection-border` (theme-style, cascades into the default rule cleanly).
    2) Override the rules `.react-flow__selection { ... }` and `.react-flow__nodesselection-rect { display:none }` directly.
  Strategy (1) is cleaner for the marquee color/border, strategy (2) is required for hiding the post-selection rect (display:none cannot be expressed via the variable).

- timestamp: 2026-05-15T13:23:35Z
  checked: gui/src/components/CanvasPanel.tsx lines 295-326 (ReactFlow props)
  found: The Plan-03 selection props are `selectionOnDrag` (line 320) and `selectionMode={SelectionMode.Partial}` (line 321). There is NO @xyflow/react v12 prop to disable rendering of the post-selection `<NodesSelection>` overlay — it's an internal component that always renders when 2+ nodes are selected. CSS `display: none` on `.react-flow__nodesselection-rect` (or its `.react-flow__nodesselection` parent) is the documented community workaround in v12.
  implication: Truth B (no bounding box after release) must be implemented via CSS, not by toggling a prop. The per-node selection highlight (controlled by node-component styling in StreamNode) is unaffected by hiding `.react-flow__nodesselection-rect`.

- timestamp: 2026-05-15T13:23:50Z
  checked: gui/src/index.css (full file), gui/src/App.css (1 line, empty), gui/package.json dependencies
  found: Project uses Tailwind v4 CSS-first config (`@import "tailwindcss"` at index.css:1, no `tailwind.config.js` file — confirmed by `find`). Design tokens are CSS custom properties on `:root` and `.dark` (lines 6-74). Relevant tokens for the override:
    - `--primary` (oklch(0.205 0 0) light / oklch(0.73 0.012 250) dark) — likely candidate for the brighter border
    - `--ring` (oklch(0.708 0 0) light / oklch(0.50 0.01 250) dark) — alternative for selection accents
    - `--accent` / `--secondary` — neutral surface tokens
  Existing convention: `.react-flow__handle` override at lines 126-132 shows where to place new ReactFlow class overrides — append after this block.
  implication: Override should harmonize with the existing design system. A semi-transparent fill of `--primary` (or a fixed brand accent) with a solid 1px border of the same color at higher alpha matches the user's request ("full line a little brighter than the fill") and respects light/dark themes via `@custom-variant dark`.

## Resolution

root_cause: |
  Two cosmetic defects, both rooted in the same cause: the default `@xyflow/react@12.10.2` stylesheet (imported at gui/src/components/CanvasPanel.tsx:17) ships with (a) a `1px dotted` border on both `.react-flow__selection` and `.react-flow__nodesselection-rect`, and (b) renders a `<NodesSelection>` overlay (`.react-flow__nodesselection-rect`) whenever 2+ nodes are selected. The project has zero CSS overrides for either class — only the default styling is in effect. Plan 03 enabled `selectionOnDrag` + `SelectionMode.Partial` (CanvasPanel.tsx:320-321) without adding accompanying CSS, so the defaults surfaced to the user.

fix: |
  CSS-only change in gui/src/index.css, appended after the existing `.react-flow__handle` block (after line 132). Two rule groups:

    /* Phase 65 — marquee selection rectangle (during drag) */
    .react-flow__selection {
      background: color-mix(in oklch, var(--primary) 12%, transparent);
      border: 1px solid color-mix(in oklch, var(--primary) 55%, transparent);
      border-radius: 2px;
    }

    /* Phase 65 — hide the post-selection bounding-box overlay.
       Selection state is conveyed by per-node highlight (StreamNode .selected). */
    .react-flow__nodesselection-rect {
      display: none;
    }

  Notes:
    - `color-mix(in oklch, ...)` ties the override to the existing `--primary` design token, so it auto-adapts to light/dark via the `.dark` class on `:root`.
    - A fixed-color alternative (e.g. `rgba(99, 102, 241, 0.12)` fill + `rgba(99, 102, 241, 0.7)` border) is also viable if the team prefers a dedicated marquee accent rather than reusing `--primary`.
    - `display: none` on `.react-flow__nodesselection-rect` is the v12 community-standard workaround — there is no ReactFlow prop to disable the NodesSelection overlay. The parent `.react-flow__nodesselection` wrapper already has `pointer-events: none` (style.css:237), so hiding the child rect does not break node dragging or per-node selection state.

verification: deferred — diagnose-only mode (find_root_cause_only).

files_changed: []  # diagnose-only; no edits applied
