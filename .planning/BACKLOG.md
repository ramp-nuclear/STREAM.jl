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
