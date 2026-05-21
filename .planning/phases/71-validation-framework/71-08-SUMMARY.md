---
phase: 71-validation-framework
plan: "08"
subsystem: gui/src/lib/validation
tags: [validation, rules, system, pressure-boundary, driving-element, vald-02, vald-03, tdd]
dependency_graph:
  requires: ["71-01", "71-04", "71-07"]
  provides: ["pressureBoundaryRequired", "drivingElementRequired", "complete-rule-registry"]
  affects: ["gui/src/lib/validation/index.ts"]
tech_stack:
  added: []
  patterns: ["minimal-validator-shape", "system-level-targets-empty"]
key_files:
  created:
    - gui/src/lib/validation/rules/pressureBoundaryRequired.ts
    - gui/src/lib/validation/rules/drivingElementRequired.ts
    - gui/src/lib/validation/rules/__tests__/pressureBoundaryRequired.test.ts
    - gui/src/lib/validation/rules/__tests__/drivingElementRequired.test.ts
  modified:
    - gui/src/lib/validation/index.ts
decisions:
  - "VALD-02 description exactly mirrors validateTopology.ts:110 ('No pressure boundary condition') plus the help text"
  - "VALD-03 description ends with period to match plan spec ('No driving element (add a Pump or Gravity component).')"
  - "drivingElementRequired heuristic (componentId === 'Pump' || 'Gravity') matches loopClosure.ts verbatim — single definition of driving element"
  - "Both rules use targets=[] (system-level, no specific node) per must_haves"
  - "pressureBoundaryRequired id result: 'pressure_boundary_required::system'; drivingElementRequired: 'driving_element_required::system'"
metrics:
  duration: "~6 minutes"
  completed: "2026-05-21"
  tasks_completed: 2
  files_changed: 5
---

# Phase 71 Plan 08: pressureBoundaryRequired + drivingElementRequired Summary

VALD-02 and VALD-03 lifted from `validateTopology()` into the registry as pure-function validators with system-level empty-targets, completing the full 11-rule §3.9 registry.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 (RED) | pressureBoundaryRequired test | c5ca530 | `__tests__/pressureBoundaryRequired.test.ts` |
| 1 (GREEN) | pressureBoundaryRequired rule + registry | a7880f6 | `pressureBoundaryRequired.ts`, `index.ts` |
| 2 (RED) | drivingElementRequired test | 3177a20 | `__tests__/drivingElementRequired.test.ts` |
| 2 (GREEN) | drivingElementRequired rule + registry | 00bf651 | `drivingElementRequired.ts`, `index.ts` |

## Per-Rule Details

### pressureBoundaryRequired (VALD-02)

- **id:** `pressure_boundary_required`
- **severity:** `error`
- **scope:** `['anchors']`
- **logic:** `Object.keys(snapshot.anchors).length === 0` → emit one result
- **result id:** `pressure_boundary_required::system`
- **targets:** `[]` (system-level)
- **description:** `"No pressure boundary condition. Set a pressure anchor on a FlowPort."`
- **test count:** 2 (empty anchors → 1 error; non-empty → 0 results)

### drivingElementRequired (VALD-03)

- **id:** `driving_element_required`
- **severity:** `error`
- **scope:** `['nodes']`
- **logic:** `snapshot.nodes.some(n => componentId === 'Pump' || 'Gravity')` — same heuristic as `loopClosure.ts`
- **result id:** `driving_element_required::system`
- **targets:** `[]` (system-level)
- **description:** `"No driving element (add a Pump or Gravity component)."`
- **test count:** 4 (empty nodes → error; Pump present → pass; Gravity present → pass; Channel+HX only → error)

## Final Registered Rule Set (11 validators)

Extracted from `gui/src/lib/validation/index.ts`:

```
port_type                   (portType.ts)
required_connections        (requiredConnections.ts)
dangling_flow_port          (danglingFlowPort.ts)       ← VALD-01 fold (Plan 04)
z_n_match                   (zNMatch.ts)
length_match                (lengthMatch.ts)
geometry_consistency        (geometryConsistency.ts)
n_match                     (nMatch.ts)
loop_closure                (loopClosure.ts)
gravity_sum_per_loop        (gravitySumPerLoop.ts)
pressure_boundary_required  (pressureBoundaryRequired.ts) ← VALD-02 fold (this plan)
driving_element_required    (drivingElementRequired.ts)   ← VALD-03 fold (this plan)
```

## Scope Declarations

| Rule | scope |
|------|-------|
| portType | `['edges']` |
| requiredConnections | `['nodes', 'edges']` |
| danglingFlowPort | `['nodes', 'edges']` |
| zNMatch | `['nodes', 'edges']` |
| lengthMatch | `['nodes', 'edges']` |
| geometryConsistency | `['nodes', 'edges']` |
| nMatch | `['nodes', 'edges', 'bcMode']` |
| loopClosure | `['nodes', 'edges']` |
| gravitySumPerLoop | `['nodes', 'edges']` |
| pressureBoundaryRequired | `['anchors']` |
| drivingElementRequired | `['nodes']` |

## Verification Results

- All 11 rule test files pass: `62 tests passed` (11 test files)
- `npx tsc --noEmit`: 13 errors — exactly at baseline (no regression)
- `grep -c "^import"` in index.ts: 12 (1 type + 11 rules)
- VALD-01 + VALD-02 + VALD-03 all covered; Plan 13 can delete `validation.ts`

## Legacy Coverage Confirmation

`validateTopology()` in `gui/src/lib/validation.ts` had three checks:
- VALD-01: FlowPort unconnected → `danglingFlowPort` (Plan 04) ✓
- VALD-02: No anchors → `pressureBoundaryRequired` (this plan) ✓
- VALD-03: No Pump/Gravity → `drivingElementRequired` (this plan) ✓

Plan 13 now has a clean path to `rm gui/src/lib/validation.ts`.

## Deviations from Plan

None - plan executed exactly as written.

## TDD Gate Compliance

Both tasks followed RED → GREEN protocol:
1. RED commit (failing test) made before implementation
2. GREEN commit (rule + registry) made after tests pass

## Self-Check: PASSED

- `gui/src/lib/validation/rules/pressureBoundaryRequired.ts` — FOUND
- `gui/src/lib/validation/rules/drivingElementRequired.ts` — FOUND
- `gui/src/lib/validation/rules/__tests__/pressureBoundaryRequired.test.ts` — FOUND
- `gui/src/lib/validation/rules/__tests__/drivingElementRequired.test.ts` — FOUND
- Commits c5ca530, a7880f6, 3177a20, 00bf651 — all present in git log
