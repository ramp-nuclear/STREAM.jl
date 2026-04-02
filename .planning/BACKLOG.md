# STREAM Project Backlog

Deferred items, polish tasks, and future work captured during development.

---

## Edge handle visual bugs (from Phase 36 UAT)
- Hover over edge drag buttons causes mouse cursor glitches or disappearance
- Dragging an edge handle to nowhere produces weird cursor states
- Source: React Flow internals, not custom code
- Priority: low (cosmetic)
- When to fix: UI polish phase (Phase 38 or similar)

---

## Resizable panels (from Phase 36 UAT)
- User wants draggable dividers between panels (canvas <-> bottom panel, canvas <-> sidebar)
- Currently all panel sizes are fixed
- Implementation: use a drag-handle component or CSS `resize`, applied consistently to all panels
- Priority: medium (quality of life)
- When to fix: UI polish phase (Phase 38 or similar)

---

## Edge arrowheads and loop routing (from Phase 36 post-UAT)
- Root cause: React Flow renders edges in SVG, nodes in HTML on top — arrowheads at node
  borders get clipped by the node background
- Loop routing (pump above channel): both edges travel right-to-left through same space,
  smoothstep routes them distinctly but without arrowheads
- Fix option A: floating handles — position handles ~8px outside the node bounding box so
  arrowheads and endpoints sit outside the HTML layer
- Fix option B: midpoint arrowhead — compute bezier midpoint + tangent, draw arrowhead as
  an SVG path element (not a marker) at that point, always away from node borders
- Priority: medium
- When to fix: UI polish phase (Phase 38 or similar)
