# Phase 34: Canvas & Node Editor - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the discussion.

**Date:** 2026-04-02
**Phase:** 34-canvas-node-editor
**Mode:** discuss
**Areas discussed:** Node visual design, Toolbox interaction, Edge & port validation, Undo/redo

---

## Gray Areas Presented

| Area | Options | Selection |
|------|---------|-----------|
| Node visual design | Minimal card / Category-colored / Full labeled handles | Minimal card (functional) |
| Toolbox interaction | HTML5 drag-and-drop / Click-to-place | HTML5 drag-and-drop |
| Edge & port validation | Strict (source/target) / Permissive | Strict: FlowPort-out → FlowPort-in only |
| Undo/redo | zundo library / Custom history stack | zundo library (with explicit fallback note) |

---

## Decisions Made

### Node visual design
- **Decision:** Minimal card — neutral background, type label (small), instance name (bold). No icons, no colors.
- **Rationale:** Phase 38 is the UI design pass; Phase 34 just needs functional nodes. Keeping it unstyled prevents double-work.
- **Handle placement:** From `port.side` in registry — no hardcoding. ThermalPort handles deferred to Phase 40.

### Toolbox interaction
- **Decision:** HTML5 drag-and-drop.
- **Rationale:** ReactFlow's documented standard pattern. Most natural interaction for a spatial node editor.

### Edge & port validation
- **Decision:** Strict source/target enforcement via ReactFlow `isValidConnection` and handle `type`.
- **Rationale:** Simple to implement, prevents basic topology mistakes at draw time. Higher-level validation (missing BC, unconnected ports) is Phase 39's job.

### Undo/redo
- **Decision:** zundo library. Fallback to custom `past[]`/`future[]` snapshot stack if zundo causes issues.
- **User note:** "I guess but we have to test this. If it doesn't work for us we switch approach."
- **Implication:** Execution agent should implement zundo first, test ≥10 sequential ops, and document clearly if switching to fallback.

---

## No Corrections Made

All selected options were accepted as-is.
