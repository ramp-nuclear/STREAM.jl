---
status: partial
phase: 64-connection-routing
source: [64-VERIFICATION.md]
started: 2026-05-14T14:09:00Z
updated: 2026-05-14T14:09:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. Per-port autoflip on simple_loop
expected: Open `gui/export_examples/simple_loop.scp` (or build a pump-CAC-pump loop) and confirm each FlowPort handle visually sits on the side facing its connected neighbor (no more ugly arrows from the §3.3 example_*.png screenshots). Handles face their neighbors; CAC thermal pair lands on opposing top/bottom faces; brief 1-pixel flicker at 45° dominant-axis transition is acceptable per D-14.
result: [pending]

### 2. Anti-parallel ±8px bow on bidirectional pump pair
expected: Wire two pumps with bidirectional hydraulic edges (`pump1.port_out → pump2.port_in` and `pump2.port_out → pump1.port_in`) and confirm the two edges render as a ±8px parallel offset instead of overlapping on a single midline (Example-1 X-cross fix). Two clearly separated parallel paths; deterministic direction (smaller-id bow on one side, larger-id on the other); no flicker on re-render.
result: [pending]

### 3. Live drag autoflip recomputation
expected: Drag a node around and confirm autoflip recomputes live (handles flip as the dominant axis to the neighbor changes) without sticky edges. If sticky-edge race surfaces during rapid drag, switch the per-handle `useEffect` body to `setTimeout(() => updateNodeInternals(nodeId), 0)` per Pitfall 2 (inline comment in `StreamNode.tsx` flags the location). Edges follow handles fluidly during drag; `useUpdateNodeInternals` keeps the wires attached to the live handle positions.
result: [pending]

### 4. D-05 layer switch dims, does not re-route
expected: Switch active layer from Hydraulic to Thermal and back. Confirm edges DIM but do NOT re-route (D-05 invariant). Visual dimming applied via `dimFlowHandles` / `dimThermalHandles` opacity; edge paths remain identical across layer switches.
result: [pending]

### 5. D-15 amber topology-hint chip without red ring
expected: Trigger D-15 by arranging a CAC with hydraulic neighbor on one side AND a thermal neighbor on the SAME horizontal axis. Confirm the amber chip "Hydraulic and thermal neighbors on same axis — consider repositioning." appears at the bottom-right of the CAC and the red ring does NOT light up. Chip is non-blocking; node root has NO `ring-destructive` class when only the topology hint fires.
result: [pending]

## Summary

total: 5
passed: 0
issues: 0
pending: 5
skipped: 0
blocked: 0

## Gaps
