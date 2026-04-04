# Phase 42: Edge & Path Visual Overhaul - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the discussion.

**Date:** 2026-04-03
**Phase:** 42-edge-path-visual-overhaul
**Mode:** discuss

## Gray Areas Presented

- Arrowhead style — hydraulic edge markerEnd, thermal edge treatment
- Parallel edge routing — how loop edges route without overlapping
- Thermal edge treatment — visual sufficiency of amber + dashed
- (User-added) Port polarity coloring — port_in vs port_out distinct colors

## Decisions Made

### Arrowheads
| Question | Answer |
|----------|--------|
| Hydraulic arrowhead style | Filled arrowhead (MarkerType.ArrowClosed) at target end only |
| Thermal arrowheads | None — symmetric coupling, arrowheads would mislead |

### Parallel Edge Routing
| Question | Answer |
|----------|--------|
| Routing approach | Smoothstep kept; auto-detect bidirectional pairs, apply ~20px offset |

### Thermal Edge Treatment
| Question | Answer |
|----------|--------|
| Additional visual treatment | None — amber dashed is sufficient once routing is fixed |

### Port Polarity Coloring
| Question | Answer |
|----------|--------|
| Fold into Phase 42? | Yes — port_in and port_out handles get distinct colors |
| Draggable edge endpoints (user idea) | Out of scope — just colored handles, no endpoint repositioning |

## Engineering Fixes (No User Input)
- Cursor glitch on edge drag: CSS/pointer-events fix, Claude investigates root cause
- Rename counter reconstruction: use componentId-aware key instead of generic regex prefix

## Deferred Ideas
- Floating/draggable edge endpoints — noted for backlog
- Edge waypoints / manual path bending — noted for backlog
