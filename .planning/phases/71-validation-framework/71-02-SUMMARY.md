---
phase: 71-validation-framework
plan: "02"
subsystem: gui-validation
tags: [validation, graph, loop, traversal, typescript, tdd]
dependency_graph:
  requires: []
  provides: [loopTraversal.ts]
  affects:
    - "gui/src/lib/validation/rules/loopClosure.ts (Plan 07)"
    - "gui/src/lib/validation/rules/gravitySumPerLoop.ts (Plan 07)"
tech_stack:
  added: []
  patterns:
    - "Tarjan strongly-connected-components (SCC) algorithm for cycle detection"
    - "TDD RED/GREEN cycle: failing tests committed before implementation"
    - "Pure function graph utility: no React/zustand/DOM dependencies"
key_files:
  created:
    - gui/src/lib/validation/loopTraversal.ts
    - gui/src/lib/validation/__tests__/loopTraversal.test.ts
  modified: []
decisions:
  - "Tarjan SCC over simple DFS-with-backtracking: Tarjan finds all SCCs in a single O(V+E) pass without retrying from each node, and correctly handles multi-loop graphs in one traversal."
  - "Sort nodeIds before building adjacency map and before DFS iteration to guarantee deterministic output regardless of Map insertion order."
  - "Edge collection for SCC: after SCC members are identified, edges internal to the SCC are gathered by a second pass over adj entries — simpler than threading edgeIds through the DFS stack."
metrics:
  duration_minutes: 3
  completed_date: "2026-05-21"
  tasks_completed: 1
  tasks_total: 1
  files_created: 2
  files_modified: 0
---

# Phase 71 Plan 02: loopTraversal.ts Summary

**One-liner:** Pure Tarjan-SCC hydraulic loop traversal utility with 8 vitest tests covering empty graph, open chain, 2-node, 3-node, two-disjoint, thermal-only-ignored, CAC mixed-port, and referential-inequality cases.

## What Was Built

`gui/src/lib/validation/loopTraversal.ts` exports:

- `HydraulicLoop` interface: `{ nodeIds: string[]; edgeIds: string[] }`
- `findHydraulicLoops(nodes, edges, getComponentDef)` — pure, deterministic, zero side-effects

The function filters the ReactFlow graph to only FlowPort edges (both source and target handles must resolve to `type: "FlowPort"` in the component registry) and only hydraulic nodes (at least one FlowPort in definition). It then runs Tarjan's SCC algorithm to find all strongly-connected components of size ≥ 2 — each SCC is one `HydraulicLoop`.

**Algorithm choice — Tarjan SCC vs simple DFS:**
Tarjan SCC was chosen because it finds all loops in a single O(V+E) traversal, avoids the O(V × (V+E)) worst-case of restarting DFS from every node, and correctly handles graphs with multiple disjoint loops without a separate "visited" bookkeeping pass. For STREAM's typical 5-50 node models the performance difference is negligible, but the single-pass correctness guarantee makes the code simpler to reason about.

## TDD Gate Compliance

- RED commit `45bc358`: 8 failing tests (module not yet created)
- GREEN commit `0e3ffe6`: 8 passing tests after implementation

## Test Results

```
Test Files  1 passed (1)
     Tests  8 passed (8)
  Duration  ~116ms
```

Test cases:
1. Empty graph returns `[]`
2. Open chain (Pump→Channel→HX, no return edge) returns `[]`
3. Two-node closed loop returns 1 `HydraulicLoop` with correct nodeIds + edgeIds
4. Three-node closed loop returns 1 loop with all 3 nodes
5. Two disjoint loops return exactly 2 loops with disjoint nodeId sets
6. Thermal-only node (HeatDiffusion) ignored even with thermal edges
7. CAC (mixed FlowPort + ThermalPort) — thermal edge excluded from loop edgeIds
8. Two consecutive calls return different array references (no shared state)

## Module Size

`loopTraversal.ts`: 200 lines (at the plan's <200 line guidance; includes JSDoc block and inline algorithm comments).

## Acceptance Criteria Verification

- `findHydraulicLoops` exported: YES
- `HydraulicLoop` interface exported: YES
- Test file has ≥ 6 `it(` blocks: YES (8 blocks)
- `npm run test -- --run src/lib/validation/__tests__/loopTraversal.test.ts` exits 0: YES
- No store/React/DOM imports in loopTraversal.ts: YES (grep returns 0)
- Returns new array per call: YES (test 8 asserts referential inequality)

## TypeScript Baseline

`npx tsc --noEmit` reports 14 errors — all in pre-existing files not touched by this plan (StreamNode.tsx ×4, BCsTabForm.test.tsx ×3, SidebarRouter.test.tsx ×2, validation.test.ts ×3, validation/types.ts ×1 from Plan 01, saveProjectAs.test.ts ×1). Zero new errors introduced by loopTraversal.ts or its test.

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

- [x] `gui/src/lib/validation/loopTraversal.ts` exists
- [x] `gui/src/lib/validation/__tests__/loopTraversal.test.ts` exists
- [x] RED commit `45bc358` exists
- [x] GREEN commit `0e3ffe6` exists
- [x] 8 tests pass
- [x] Zero store/React/DOM imports
