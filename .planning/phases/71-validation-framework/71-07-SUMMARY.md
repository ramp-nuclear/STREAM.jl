---
phase: 71-validation-framework
plan: "07"
subsystem: gui-validation-rules
tags: [validation, rules, loop, gravity, physics, tdd]
dependency_graph:
  requires: [71-01, 71-02, 71-06]
  provides: [loopClosure-rule, gravitySumPerLoop-rule]
  affects: [validation-registry, validation-panel]
tech_stack:
  added: []
  patterns:
    - pure-function validator with findHydraulicLoops dependency
    - sourceHandle-based signed gravity traversal convention
key_files:
  created:
    - gui/src/lib/validation/rules/loopClosure.ts
    - gui/src/lib/validation/rules/__tests__/loopClosure.test.ts
    - gui/src/lib/validation/rules/gravitySumPerLoop.ts
    - gui/src/lib/validation/rules/__tests__/gravitySumPerLoop.test.ts
  modified:
    - gui/src/lib/validation/index.ts
decisions:
  - signed-gravity-convention: sourceHandle of the Gravity node's outgoing loop edge
    (port_out = forward = +H; port_in = backward = -H) rather than per-edge source/target
    accumulation, because per-edge accumulation always sums to zero for interior nodes
metrics:
  duration_minutes: 25
  completed_date: "2026-05-21"
  tasks_completed: 2
  files_created: 4
  files_modified: 1
---

# Phase 71 Plan 07: Loop Physics Validators Summary

Two loop-physics validators ship per D-15 (§3.9 rules 7 and 8): `loopClosure` and
`gravitySumPerLoop`. Both consume Plan 02's `findHydraulicLoops` helper without
re-implementing graph traversal.

## What Was Built

**loopClosure** (`gui/src/lib/validation/rules/loopClosure.ts`)

Fires when the model has at least one driving element (Pump or Gravity by componentId)
but `findHydraulicLoops` returns no closed loops. Emits a single `ValidationResult`
with id `loop_closure::system`, severity `error`, targeting all hydraulic-capable
nodes (so the canvas red-rings every FlowPort-capable component in the unclosed graph).
Description includes the driving element count: "N driving element(s) but no closed
hydraulic loop. Fluid cannot circulate."

Thermal-only models (no Pump or Gravity) produce no result — correct behavior.

**gravitySumPerLoop** (`gui/src/lib/validation/rules/gravitySumPerLoop.ts`)

For every closed hydraulic loop, computes the signed sum of Gravity H values. Fires
with severity `error` when |net| >= 1e-6. Emits one result per offending loop.
Targets include `{kind:'field', fieldPath:'H'}` for each Gravity node in the loop,
bridging to the property-panel red-highlight (D-12).

Stable result id: `gravity_sum_per_loop::${sortedLoopNodeIds.join(',')}`.

## Test Coverage

| Rule | Test file | it() count | All pass? |
|------|-----------|-----------|-----------|
| loopClosure | rules/__tests__/loopClosure.test.ts | 5 | yes |
| gravitySumPerLoop | rules/__tests__/gravitySumPerLoop.test.ts | 5 | yes |

loopClosure test cases: closed loop (no emit), open chain + Pump (1 error), thermal-only
(no emit), Gravity as driving element (1 error), two disjoint closed loops (no emit).

gravitySumPerLoop test cases: balanced H=+10/H=-10 (no emit), unbalanced H=+10 only
(1 error with field targets), no Gravity in loop (no emit), backward-traversed Gravity
balances forward-traversed (no emit), stable id assertion.

## Registry State After Plan 07

`gui/src/lib/validation/index.ts` now registers **9 rules**:
portType, requiredConnections, danglingFlowPort, zNMatch, lengthMatch,
geometryConsistency, nMatch, loopClosure, gravitySumPerLoop.

## Signed-Gravity Traversal Convention

**Convention chosen:** `sourceHandle` of the Gravity node's outgoing loop edge.

- `sourceHandle === 'port_out'` → forward traversal (port_in → port_out) → `+H`
- `sourceHandle === 'port_in'`  → backward traversal (port_out → port_in) → `-H`

**Justification:** The per-edge source/target accumulation convention (described in
the plan's pitfall note) always yields `+H - H = 0` net per Gravity node in a simple
loop, because each hydraulic node appears exactly once as edge source and once as edge
target. The component-level sourceHandle convention is the only approach that produces
a non-zero result for a single unbalanced Gravity in a loop, matching the plan's
`<behavior>` spec ("one Gravity(H=+10) alone → net = +10 ≠ 0 → error").

## TSC Errors

Baseline: 13 pre-existing errors (unchanged — no regression introduced).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Test case 4 rewritten for sourceHandle convention**

- **Found during:** Task 2 (GREEN phase)
- **Issue:** The original test case 4 ("respects traversal direction") was written
  assuming the per-edge source/target accumulation convention. Under that convention,
  a 4-node loop with two gravity nodes (both H=+10, both forward-traversed) would
  always net to 0 — which happens to match the test's expectation but contradicts the
  plan's unbalanced-loop behavior (test 2 would also net to 0 under that convention).
- **Fix:** Rewrote test 4 to explicitly test the `sourceHandle` convention: one
  Gravity with `sourceHandle=port_out` (+H) balanced by one with `sourceHandle=port_in`
  (-H). This is the only convention consistent with both the plan's behavior spec
  and the physics intent.
- **Files modified:** `gui/src/lib/validation/rules/__tests__/gravitySumPerLoop.test.ts`
- **Commit:** 1ac1217 (RED), a569cd7 (GREEN)

## Self-Check: PASSED

- gui/src/lib/validation/rules/loopClosure.ts — FOUND
- gui/src/lib/validation/rules/gravitySumPerLoop.ts — FOUND
- gui/src/lib/validation/rules/__tests__/loopClosure.test.ts — FOUND
- gui/src/lib/validation/rules/__tests__/gravitySumPerLoop.test.ts — FOUND
- Commit 7e1397a (RED loopClosure test) — FOUND
- Commit e7193bf (GREEN loopClosure impl) — FOUND
- Commit 1ac1217 (RED gravitySumPerLoop test) — FOUND
- Commit a569cd7 (GREEN gravitySumPerLoop impl + registry) — FOUND
