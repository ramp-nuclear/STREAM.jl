---
created: 2026-05-13
title: GUI visual design pass — current shell looks unpolished
area: design
resolves_phase: 72
files:
  - gui/src/**
---

## Problem

The functional shell of the Composer is complete (tabbed navigator, Resources tab, Model Options form, selection-kind router, codegen). But the visual treatment is rough — spacing, typography, color accents, hover/focus states, density, and overall feel do not yet read as a "professional engineering tool" per the project's stated discipline (Phase 72 goal: "professional engineering tool, not consumer SaaS playground").

User feedback verbatim:
> "It is still ugly design. I think there is a redesign phase later, but making sure. Because right now it just does not look that good."

This is the explicit Phase 72 mandate. Capturing as a todo so it is not lost across the remaining phases (63–71).

## Solution

In Phase 72 (Design system / interaction contract):
1. Write the rules document (spatial / interaction / feedback / defaults / visual-restraint).
2. Audit-and-apply pass over every existing panel per the deliverables list:
   - Thermal port handle restyle (outlined circle + chain-link state icons)
   - Tooltip system
   - Settings dialog (modal with left-nav categories)
   - Canvas cheatsheet (auto-generated demo component with numbered legend)
   - Accent palette for Sources and Reactor Physics layers
   - Density expectations
   - Visual style commitments (font, color, shadow, radius scales)
3. Cover the Phase 62 surfaces specifically:
   - Tabbed left navigator
   - Resources tab tree
   - Model Options form
   - Selection-kind right panel
   - Reference picker popover

## Notes

- Surfaced during Phase 62 human-verify checkpoint (62-11), 2026-05-13.
- Project memory: `project_gui_redesign.md` confirms a dedicated redesign phase was planned; Phase 72 is that phase.
- The Phase 62 copy-pass gap-closure plan (in progress) handles the most egregious wording. Visual polish is Phase 72's job.
