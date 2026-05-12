---
phase: 61-registry-audit-rewrite-for-v1-1
plan: 05
subsystem: gui/registry
tags: [gui, registry, tests, consumer-reconciliation, verification]
dependency-graph:
  requires:
    - .planning/phases/61-registry-audit-rewrite-for-v1-1/61-01-SUMMARY.md (schema vocabulary extension)
    - .planning/phases/61-registry-audit-rewrite-for-v1-1/61-02-SUMMARY.md (channel-family rewrite)
    - .planning/phases/61-registry-audit-rewrite-for-v1-1/61-03-SUMMARY.md (4 new component entries + categories)
    - .planning/phases/61-registry-audit-rewrite-for-v1-1/61-04-SUMMARY.md (unchanged-component drift audit)
  provides:
    - "v1.1-aligned registry test suite — 21 tests in registry.test.ts (was 14), 7 new"
    - "FK / array_size / pair_with / BCPort-scope / Resource-shape cross-validation tests (T-61-12 mitigation)"
    - "Documented Phase 66 deferral for external_inputs codegen path"
  affects:
    - "Phase 62 navigator-tree (Resources visibility test fixtures unaffected)"
    - "Phase 63 BCs-tab property panel (will consume the FK structure these tests now lock)"
    - "Phase 66 codegen rewrite (TODO markers in codeGenerator.ts point here)"
    - "Phase 71 TypeScript reconciliation (owns the 7 pre-existing tsc errors)"
tech-stack:
  added: []
  patterns:
    - "Cross-validation invariants encoded as vitest assertions — FK / array_size / pair_with drift becomes a CI-time failure, not a runtime crash"
    - "Comment-in-code Phase 66 TODO markers in codeGenerator.ts emitComponentDeclaration — defers external_inputs MTK wiring without blocking compilation"
    - "Zero source edits to validation.ts / useStore.ts / ParameterForm.tsx — earlier plans already absorbed the structural changes"
key-files:
  created:
    - .planning/phases/61-registry-audit-rewrite-for-v1-1/61-05-SUMMARY.md
  modified:
    - gui/src/registry/__tests__/registry.test.ts
    - gui/src/lib/codeGenerator.ts
decisions:
  - "Task 2 made ZERO behavioral edits to validation.ts, useStore.ts, ParameterForm.tsx — only documentation. Plan 01 had already widened getPortTypeFromDef return type to include BCPort; Plan 02 already extended the array-port predicate to recognise array_size alongside legacy array+arrayParam; Plan 01 deliberately kept constructorModes REQUIRED on ComponentDefinition (all 16 v1.1 entries set it), so the optional-chain guards proposed by the plan body are not needed. validation.ts filters on port.type === 'FlowPort' (BCPort is excluded by the narrow filter; no exhaustive switch); useStore.ts already uses `component?.constructorModes[0]?.mode ?? 'default'` optional chaining; ParameterForm.tsx already uses `modeSpec?.parameters ?? component.parameters.map(...)` as the missing-mode fallback. Documenting the absence-of-changes here so a future reader does not search for a phantom edit."
  - "Did NOT touch StreamNode.tsx in this plan. The 2 pre-existing tsc errors on lines 73/88 (`Property 'data' does not exist on type ... <Handle>`) are a `@xyflow/react` major-version typing change orthogonal to the registry schema. They are documented in deferred-items.md and explicitly owned by a future GUI-hygiene plan (likely Phase 71). Touching them here would expand scope past the 'minimum to keep build+test green' boundary the plan body sets."
  - "Did NOT touch validation.ts despite the plan body suggesting potential BCPort discriminated-union narrowing. The existing code path is a `port.type === 'FlowPort'` filter — BCPort is silently excluded, which is the correct v1.1 behavior (BCPort connections are not validated as flow connections). No exhaustive switch / discriminant narrowing exists in validation.ts as written, so no guards are needed."
  - "Task 3 (checkpoint:human-verify) is NOT executed by this parallel-executor agent. Per the parallel_execution prompt the agent has no `npm run dev` + browser access; the human owns the visual smoke. The checkpoint stays open and is documented below for the orchestrator to surface to the user as the wave-completion gate."
  - "Marked Phase 66 codegen deferral with two TODO: Phase 66 comments in codeGenerator.ts:emitComponentDeclaration. Plan acceptance criterion offered comment-in-code OR doc-in-summary; chose both (comment for future grep-discoverability, summary for review)."
metrics:
  duration: "~12m"
  completed: 2026-05-12
  tasks_completed: 2  # Task 1 + Task 2; Task 3 is human-verify, see Checkpoint Status
  files_changed: 2
  files_created: 1
---

# Phase 61 Plan 05: Test reconciliation + downstream-consumer compatibility — Summary

**One-liner:** Locked in the v1.1 registry invariants (16 components, new categories, BCPort scope, FK / array_size / pair_with referent resolution) as vitest assertions; added 7 new cross-validation tests; documented Phase 66 codegen deferral with TODO markers; full vitest suite climbed from 232 → 239 passing while build error count stayed flat at the baseline 7.

## What shipped

### Task 1 — Update registry.test.ts for v1.1 + add cross-validation (commit `08ca789`)

**Edited assertions:**

1. `'contains all expected component IDs'` — `expected` array grew from 12 to 16 names. Adds `WallTemperature`, `HeatFluxSource`, `PointKinetics`, `ReactivityController`.

2. `'getComponentsByCategory filters correctly'` — extended to assert per-category counts across all 5 v1.1 categories and check that they form an exhaustive partition: Hydraulic 10 + Thermal 2 + Sources 2 + Reactor Physics 1 + Resources 1 = `getAllComponents().length`.

3. `'adding a component requires only JSON'` (SCAF-04) — added assertions for the 4 new IDs so the data-driven path is proven across the entire v1.1 surface, not just the pre-v1.1 set.

**Added tests:**

4. `Channel has no ThermalPort and declares T_wall_left/T_wall_right external_inputs (D-03/D-18)` — mirrors the existing ChannelHeatFlux test. Asserts no `ThermalPort` in `Channel.ports`, no `htc_correlation` parameter, and that `external_inputs[]` lists `T_wall_left` then `T_wall_right`, both pointing at `WallTemperature.T_wall_out`.

5. `every external_inputs[].source_component resolves to a registered component id` — iterates all entries, every FK lands in the master id set.

6. `every external_inputs[].source_port resolves to a port on its source_component` — iterates all FKs, every named source port exists on the named source component.

7. `every port array_size references a sibling parameter on the same component` — iterates all ports with `array_size`, checks the value matches a sibling `parameters[].name`. Currently 5 such ports (CAC × 2, HD × 2, WallTemperature × 1 — wait, 7 across the registry: CAC.thermal_left/right with `n`, HD.thermal_left/right with `nz`, WallTemperature.T_wall_out with `n`, HeatFluxSource.q_out with `n`). All resolve correctly.

8. `every pair_with port reference resolves to a sibling port and is symmetric` — for every port with `pair_with`, asserts (a) the named port exists on the same component, AND (b) the back-reference matches (if `A.pair_with === B`, then `B.pair_with === A`). The 4 CAC + HD thermal pairs all pass.

9. `BCPort is only used by Sources category components (D-14/D-15)` — every entry that carries a BCPort is required to be in the `Sources` category. Currently `WallTemperature.T_wall_out` and `HeatFluxSource.q_out`.

10. `ReactivityController has resource_kind and no canvas ports (D-13)` — pins the D-13 Resource invariant.

**Audit grep results (acceptance criteria):**

| Pattern | Count | Required |
|---------|-------|----------|
| `toHaveLength(16)` | 1 | ≥ 1 |
| `WallTemperature|HeatFluxSource|PointKinetics|ReactivityController` | 14 | ≥ 4 |
| `external_inputs` | 12 | ≥ 2 |
| `pair_with` | 12 | ≥ 1 |
| `array_size` | 11 | ≥ 1 |
| `BCPort` | 5 | ≥ 1 |

### Task 2 — Reconcile downstream consumers (commit `45963b3`)

**The only edit:** 13 lines of `TODO: Phase 66` comments in `gui/src/lib/codeGenerator.ts` (`emitComponentDeclaration` JSDoc + inline placeholder marker).

**Why so little:**

- `validation.ts` filters `port.type === 'FlowPort'`. BCPort and ThermalPort are silently excluded — no exhaustive `switch` / discriminated-union narrowing exists, so no compile fix is needed. The v1.1 schema is silently absorbed.
- `useStore.ts` already uses `component?.constructorModes[0]?.mode ?? 'default'` optional-chain access at line 315 and `srcComp?.ports.find(...)` style port lookups everywhere else. Compatible with the v1.1 schema as-is.
- `ParameterForm.tsx` line 26 already uses `component.constructorModes.find((m) => m.mode === activeMode)` followed by `modeSpec?.parameters ?? component.parameters.map(...)` — the missing-mode case is handled by the fallback expression. Since Plan 01 deliberately kept `constructorModes` REQUIRED on `ComponentDefinition` (all 16 entries set it), no schema-side optional-chain guards are required at this consumer.
- The 7 pre-existing tsc errors in StreamNode.tsx (2), codeGenerator.ts (2), and validation.test.ts (3) are unchanged. They are NOT registry-schema bugs — they are a `@xyflow/react` major-version typing drift (StreamNode) and unused-import lints (codeGenerator, validation.test.ts). Per the plan body and the parallel_execution prompt's explicit baseline, Phase 71 owns their cleanup.

**TODO marker placement:**

```ts
// codeGenerator.ts:169–183 (emitComponentDeclaration JSDoc)
 * TODO: Phase 66 — wire external_inputs[] into MTK equations.
 * v1.1 Channel and ChannelHeatFlux carry an `external_inputs[]` array (T_wall_left /
 * T_wall_right for Channel; q_left / q_right for ChannelHeatFlux) that this codegen
 * currently ignores. The full BC-to-MTK wiring path (bc_modes "Value" / "Profile" /
 * "Function" / "Mark" / "Source", plus the Source-mode dashed-edge resolution to a
 * WallTemperature or HeatFluxSource block on the canvas) is owned by Phase 66.

// codeGenerator.ts inside function body
  // TODO: Phase 66 — when the active component has external_inputs[], emit a per-BC
  // `# TODO: bind <name>` placeholder block before the @named line. For now the
  // shape is locked in the registry but not yet honored by the generator.
```

`grep -c "TODO: Phase 66" gui/src/lib/codeGenerator.ts` = 2 (acceptance ≥ 1 ✓).

## Verification

| Check | Required | Result |
|-------|----------|--------|
| `npx vitest run src/registry/__tests__/registry.test.ts` | 0 failures | **21/21 passing** (was 14) |
| `npx vitest run` (full) | ≥ 232 passing, 0 failed | **239 passing, 17 todo, 1 file skipped, 0 failed** |
| `npm run build` new errors | 0 new beyond baseline | **0 new** (still exactly 7 baseline errors per `deferred-items.md`) |
| `grep -c "toHaveLength(16)"` in registry.test.ts | ≥ 1 | 1 |
| `grep -c "WallTemperature\|HeatFluxSource\|PointKinetics\|ReactivityController"` in registry.test.ts | ≥ 4 | 14 |
| `grep -c "external_inputs"` in registry.test.ts | ≥ 2 | 12 |
| `grep -c "pair_with"` in registry.test.ts | ≥ 1 | 12 |
| `grep -c "array_size"` in registry.test.ts | ≥ 1 | 11 |
| `grep -c "BCPort"` in registry.test.ts | ≥ 1 | 5 |
| `grep -c "TODO: Phase 66" gui/src/lib/codeGenerator.ts` | ≥ 1 | 2 |
| Files modified outside `files_modified` list | 0 | 0 (only `gui/src/registry/__tests__/registry.test.ts` and `gui/src/lib/codeGenerator.ts`) |

## Deviations from Plan

None of the deviation rules (1-4) triggered. The plan executed essentially as written, with two structural simplifications justified by what Plans 01-04 had already accomplished:

1. **Task 2 turned out to be near-empty.** The plan body anticipated optional-chain guards in `validation.ts`, `useStore.ts`, and `ParameterForm.tsx`. None were needed — see Decisions for the reasoning. This is not a deviation from intent; it is the plan body slightly over-estimating the remaining gap because the earlier plans (especially Plan 01's `getPortTypeFromDef` widening and Plan 02's `array_size` predicate extension) had already absorbed the structural changes.

2. **Task 3 is not executable by a parallel-executor agent.** The checkpoint requires `npm run dev` plus a browser; the worktree-isolated executor has no such access. This is a known limitation of the agent topology, not a plan deviation. See Checkpoint Status.

### Auth gates

None.

## Checkpoint Status

**Task 3 (`checkpoint:human-verify`) — PENDING.**

The plan's third task is a human-only smoke test: start the GUI (`cd gui && npm run dev`), open the browser, count 16 components in the toolbox, drag a Channel and a WallTemperature block, confirm no console errors, confirm property panels render the expected fields and the BCPort handle on `WallTemperature.T_wall_out`.

This executor agent runs in a worktree with no GUI / browser access. The checkpoint stays open for the orchestrator to surface to the user as the wave-completion gate. The 7-step `<how-to-verify>` block in `61-05-PLAN.md` is the script; recommend the user run it after the orchestrator merges the worktree back into the working branch.

If the human approves: phase 61 is complete pending the final phase-completion roll-up.
If the human reports issues: a gap-closure plan should be spawned that targets the specific failure (likely a missing icon, an unwired BCs-tab field, or a navigator-tree visibility bug — all owned by Phase 62/63/68/71).

## Threat Flags

None — this plan only adds test assertions and documentation comments. No new network endpoints, auth paths, file-access patterns, or trust-boundary surface.

The new tests are themselves a mitigation (T-61-12, T-61-14): they shift FK / array_size / pair_with drift from runtime crashes to CI failures. T-61-13 (GUI startup with malformed registry) and T-61-15 (handwave human verify) are addressed by the human-verify checkpoint procedure documented in the plan body — those remain pending the human.

## Deferred Issues

The same 7 baseline tsc errors documented in `.planning/phases/61-registry-audit-rewrite-for-v1-1/deferred-items.md` carry forward unchanged. They are:

- StreamNode.tsx lines 73 & 88: `<Handle data={...}>` typing drift after `@xyflow/react` major-version upgrade (×2)
- codeGenerator.ts lines 328 & 753: unused `nodes` and `singlePort` parameters (×2). Line numbers shifted from 315/740 by +13 due to the Phase 66 TODO comment block this plan added, but the underlying unused-variable lints are the same.
- validation.test.ts lines 6/7/8: unused type imports (`TopologyResult`, `NodeError`, `SystemError`) (×3)

All 7 are explicitly outside Phase 61's scope per the parallel_execution prompt and CONTEXT §3.11; Phase 71 owns the TypeScript reconciliation pass.

## Self-Check

```bash
[ -f gui/src/registry/__tests__/registry.test.ts ] && echo FOUND || echo MISSING            # FOUND
[ -f gui/src/lib/codeGenerator.ts ] && echo FOUND || echo MISSING                            # FOUND
[ -f .planning/phases/61-registry-audit-rewrite-for-v1-1/61-05-SUMMARY.md ] && echo FOUND || echo MISSING  # written by this commit
git log --oneline | grep -q 08ca789 && echo FOUND || echo MISSING                            # FOUND (Task 1)
git log --oneline | grep -q 45963b3 && echo FOUND || echo MISSING                            # FOUND (Task 2)
```

## Self-Check: PASSED

All claimed files exist on disk; both task commits (`08ca789`, `45963b3`) are present in the worktree branch history. Vitest 239/239 passing; tsc baseline 7 errors preserved (0 new).
