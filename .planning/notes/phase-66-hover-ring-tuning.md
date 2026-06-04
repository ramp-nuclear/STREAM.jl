# Phase 66 → Phase 72 Handoff — Canvas Hover / Pin Ring Visual Tuning

**Status:** Canonical handoff artifact for Phase 72 (GUI visual polish).
**Source decisions:** Phase 66 CONTEXT.md D-05 (hover ring is visually
distinct from selection ring), D-09 (jump-to-code pins the source), D-11
(ephemeral session state — not persisted).
**Scope:** This doc captures the Phase 66 placeholder styling for the
code-panel ↔ canvas bidirectional traceability ring, and the surface area
Phase 72 is expected to re-tune. It does NOT change the wiring contract:
the class names and selectors are stable; only the visual properties (color,
stroke, animation) are in scope for re-tuning.

---

## What Phase 66 shipped

Phase 66 wires `gui/src/components/StreamNode.tsx` to two ephemeral Zustand
slices (`hoveredSourceIds`, `pinnedSourceIds`) via per-node primitive-boolean
selectors. Each StreamNode root `<div>` carries one of:

- `stream-node--code-hover` when the node id is in `hoveredSourceIds`
- `stream-node--code-pinned` when the node id is in `pinnedSourceIds`

Both can coexist. The current CSS placeholder in `gui/src/index.css` is:

```css
.stream-node--code-hover {
  outline: 2px solid var(--stream-code-hover-ring-color, #38bdf8);  /* sky-400 */
  outline-offset: 2px;
}
.stream-node--code-pinned {
  outline: 2px solid var(--stream-code-pinned-ring-color, #0ea5e9);  /* sky-500 */
  outline-offset: 2px;
}
```

`outline` (not `border`) by intent: outline does NOT contribute to box
dimensions, so Phase 64's autoflip handle-position math stays correct.
`outline-offset: 2px` keeps the new ring distinct from ReactFlow's
box-shadow-based selection ring.

---

## What Phase 72 should re-tune

Each bullet says WHERE (file or CSS variable) and WHAT to consider.

- **Color** — CSS variables `--stream-code-hover-ring-color` and
  `--stream-code-pinned-ring-color`. Set in `gui/src/index.css` as fallbacks
  (sky-400 / sky-500); override at `:root` (or `.dark`) when Phase 72 locks
  the v1.2 accent palette. Keep hover ≠ pinned (the distinction is the
  whole reason both classes exist).

- **Stroke width and style** — currently solid 2px. Dashed for one of the
  two states is worth considering; would make hover-vs-pin distinguishable
  even at the same hue. Live in the same CSS rules in `gui/src/index.css`.

- **Flash animation** — when a `stream:show-code-for` CustomEvent fires,
  `CodePreview.tsx` currently toggles a `data-flash="true"` attribute on
  the target sub-block for 1.5s (handled with a `setTimeout`). The canvas
  side has no flash today — only the sticky outline from the pin. Phase 72
  may want a brief CSS `@keyframes` pulse on `stream-node--code-pinned` on
  first apply, or a one-shot `@keyframes` rule scoped via a transient class.

- **Layer-aware un-dim (Phase 68 forward-compat)** — when Phase 68 lands
  the four-layer dim mechanism (`stream-node--layer-dimmed` /
  `stream-node--layer-hidden`), the dim logic in `StreamNode.tsx` MUST
  check `hoveredSourceIds` / `pinnedSourceIds` to suppress dimming for
  rings-on nodes (a dimmed node with a ring is visually noisy and defeats
  the traceability cue). Phase 66 explicitly does NOT change layer behavior
  per CONTEXT.md D-05; the un-dim is Phase 68's responsibility.

- **Outline-offset vs ring stacking** — when a node is simultaneously
  selected (ReactFlow's `selected` prop → `ring-2 ring-[var(--ring)]`),
  errored (`outline outline-2 ... ring-destructive`), AND pinned, three
  rings can stack. Phase 72 should decide the visual priority. Today the
  cascade resolves to the most-specific rule by source order, which is
  acceptable for the placeholder but not the final UX.

---

## Verification path after Phase 72 re-tunes

The class-level wiring tests are visual-property-agnostic, so they survive
any color/stroke/animation change:

- `gui/src/components/__tests__/StreamNode.codeHover.test.tsx` — asserts
  the class application (presence/absence of `stream-node--code-hover` /
  `stream-node--code-pinned`), not specific colors or widths.
- `gui/src/components/__tests__/CodePreview.textSelection.test.tsx` — asserts
  the code-panel side stays text-selectable across sub-block boundaries.

If Phase 72 changes the class names themselves (DO NOT), both tests would
need to update. As long as the class names stay, both tests stay GREEN.
