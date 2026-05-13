---
created: 2026-05-13
title: Left and right panel resize handles let content escape viewport bounds
area: layout
resolves_phase: 72
files:
  - gui/src/App.tsx
  - gui/src/components/sidebar/SidebarPanel.tsx
  - gui/src/components/ToolboxPanel.tsx
---

## Problem

Both the left navigator (Components / Resources / Project tabs) and the right Properties panel can be resized in ways that hide content. When the user drags a panel narrower than its minimum sensible width:
- Form controls (e.g., `+ New…` button, picker rows) overflow horizontally and get clipped at the panel edge.
- Long resource names / component labels get truncated without ellipsis.
- The user cannot drag the panel *wider* enough to reveal the clipped content because the resize handle behavior is bounded by the viewport, not by the content.

User feedback verbatim:
> "the tabs on the left and right are designed poorly, some stuff goes out of frame and you can't even see because you can't drag them all the way. This has to be fixed in a way that stuff doesn't go out of frame. never. maybe detect it and make stuff fit by going down or getting smaller. Whatever solution is best, but we have to figure this out at some point."

## Solution

In Phase 72 (Design system / interaction contract):
1. Establish min/max panel widths in the design contract.
2. Make panel content responsive: at narrow widths, wrap form rows vertically (label above field above button) instead of clipping; at wide widths, lay out horizontally.
3. Ensure resize handles clamp to viewport bounds with a minimum content width below which the panel auto-collapses to a single icon/strip rather than clipping.
4. Apply overflow-aware truncation (CSS `text-overflow: ellipsis` on rows, `whitespace-nowrap` only where it's safe).
5. Audit-and-apply pass across every panel per Phase 72's stated scope.

## Notes

- Surfaced during Phase 62 human-verify checkpoint (62-11), 2026-05-13.
- Phase 62 gap closure addresses the `+ New…` button overflow as a quick fix at default widths (right panel ≥ 320px). The systemic bounded-resize fix is Phase 72.
- Related Phase 62 gap: ResourceReferencePicker button row layout.
