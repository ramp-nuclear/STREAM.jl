# Phase 43: UI Polish & Redesign - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the discussion.

**Date:** 2026-04-04
**Phase:** 43-ui-polish-redesign
**Mode:** discuss

## Areas Discussed

All four gray areas were selected: Bottom panel resize, Parameter descriptions, Thermal handle proportions, Button & spacing audit.

## Decisions Made

### Bottom panel resize
- **Selected:** Drag handle at top border, height stored in Zustand (`bottomPanelHeight`), min ~120px, max ~60% viewport.

### Parameter descriptions
- **Selected:** Extend Info icon + tooltip to all field types (PipeGeometryPicker, FunctionSelect, MatrixBadge, Bool toggle), matching the NumericField pattern already in place.

### Thermal handle proportions
- **Correction:** User clarified that ChannelAndContacts has **one handle per side** (Phase 40 D-01), never n per cell. The "density" gray area was invalid — the question assumed per-cell handles exist, which they don't. Confirmed that Phase 40 decision stands: `array: true` is code-gen only.
- **Result:** Thermal handle size/proportion is Claude's discretion (minor size tweak if needed for visual balance).

### Button & spacing audit
- **Selected:** Toolbar + sidebar only. Dialogs/menus excluded.

## Corrections Made

### Thermal handle rendering assumption
- **Original assumption presented:** ChannelAndContacts with n=10 cells might have 10 stacked thermal diamonds
- **User correction:** Confirmed Phase 40 D-01 — one handle per side, period. The n-cell detail is abstracted away entirely in the GUI.
- **Impact:** Removes a non-existent problem from scope; no special density handling needed.
