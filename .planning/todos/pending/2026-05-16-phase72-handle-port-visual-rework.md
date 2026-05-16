---
created: 2026-05-16T10:56:45Z
title: Phase 72 — handle/port visual rework (color, shape, size, same-side stacking)
area: ui
files:
  - gui/src/components/StreamNode.tsx
---

## Problem

Surfaced during Phase 64 UAT. CAC node handles have multiple visual problems:
- Amber/orange color is wrong
- Diamond shape is wrong
- Connector size is wrong
- Movement behavior is wrong
- When FlowPort and thermal handles land on the same side of a CAC node, it looks horrible
- The topology-hint chip (amber chip warning about same-axis neighbors) should be removed entirely — owner does not want it

## Solution

Phase 72 (Design system / interaction contract) deliverable. Rethink:
- Handle color (not amber/orange)
- Handle shape (not diamond)
- Handle size
- Handle movement/animation behavior
- Same-side stacking — needs a layout/visual strategy so mixed-type handles on the same side don't look broken
- Remove topology-hint chip code from StreamNode.tsx entirely
