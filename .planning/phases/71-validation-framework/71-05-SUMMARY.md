---
phase: 71-validation-framework
plan: "05"
subsystem: gui-validation
tags: [validation, rules, geometry, dimensional, z-n-match, length-match, geometry-consistency, fix-action, tdd]

dependency_graph:
  requires: ["71-01", "71-04"]
  provides:
    - "zNMatch: Validator (CAC.n vs HD.nz; lossless-sync FixAction)"
    - "lengthMatch: Validator (CAC.geometry.L vs HD.Lz; value-transfer-picker FixAction)"
    - "geometryConsistency: Validator (shared-coupling geometry coherence; navigation-only FixAction)"
  affects:
    - "gui/src/lib/validation/index.ts (3 new registrations)"
    - "Plan 09 ValidationPanel (consumes FixAction buttons at click time)"
    - "Plan 11 data-field-path bridge (fieldPath 'n', 'nz', 'geometry', 'Lz')"

tech_stack:
  added: []
  patterns:
    - "TDD RED→GREEN→REFACTOR per plan spec"
    - "Pure-function validators (D-06): no useStore import; snapshot-in, results-out"
    - "FixAction apply closures bound to primitives only; (set,get) injected at click time (Pitfall 7 mitigation)"
    - "Resource-FK UUID resolution: CAC.geometry → snapshot.resources.geometries[uuid].params.L"

key_files:
  created:
    - gui/src/lib/validation/rules/zNMatch.ts
    - gui/src/lib/validation/rules/lengthMatch.ts
    - gui/src/lib/validation/rules/geometryConsistency.ts
    - gui/src/lib/validation/rules/__tests__/zNMatch.test.ts
    - gui/src/lib/validation/rules/__tests__/lengthMatch.test.ts
    - gui/src/lib/validation/rules/__tests__/geometryConsistency.test.ts
  modified:
    - gui/src/lib/validation/index.ts

decisions:
  - "zNMatch: winning n = Math.max(cac.n, hd.nz); single Sync button propagates to both sides"
  - "lengthMatch: CAC.geometry is a Resource-FK UUID (Phase 62 reinterpretation); field target is 'geometry' not 'geom.L'"
  - "geometryConsistency: navigation-only (planner discretion) — multi-field mismatch with no single canonical winner"
  - "FixAction apply closures capture primitives (cacId, hdId, winningN, geomUuid) not snapshot refs"
  - "updateResource('geometry', uuid, { params: {...existing.params, L: hdLz} }) — preserves non-L geometry fields"

metrics:
  duration: "~20 minutes"
  completed: "2026-05-21T11:57:50Z"
  tasks_completed: 3
  files_created: 6
  files_modified: 1
---

# Phase 71 Plan 05: Geometry/Shape Validators Summary

Three pure-function geometry validators ship per D-15 (§3.9 rules 1, 2, 9), each emitting
a FixAction per the §3.9 assignment: lossless-sync, value-transfer-picker, navigation-only.

## Tasks Completed

| Task | Rule | FixAction Kind | Tests | Commit |
|------|------|----------------|-------|--------|
| 1 | zNMatch | lossless-sync | 6 pass | 1fd99d4 |
| 2 | lengthMatch | value-transfer-picker | 6 pass | 5639524 |
| 3 | geometryConsistency | navigation-only | 6 pass | 4e40da2 |
| fix | tsc: required/positional + unused var | — | — | fd941a4 |

**Total tests: 18 / 18 pass**
**tsc --noEmit: 13 errors (all pre-existing; baseline held)**

## Rule Details

### zNMatch (`z_n_match`)

- **Trigger:** CAC.n != HD.nz on any thermal edge between them
- **Severity:** error
- **Targets:** edge + field('n') on CAC + field('nz') on HD + both node targets
- **FixAction label:** `Sync n to 5` (where 5 = Math.max(cac.n, hd.nz))
- **apply closure:** `live.updateNodeParams(cacId, { parameters: { n: winningN } })` and `live.updateNodeParams(hdId, { parameters: { nz: winningN } })`
- **Store mutator used:** `updateNodeParams(nodeId, { parameters: { ... } })`
- **Dedup:** one result per unordered (cacId, hdId) pair regardless of edge count

### lengthMatch (`length_match`)

- **Trigger:** CAC geometry resource L != HD.Lz on a thermal coupling
- **Severity:** error
- **Resource resolution:** `cac.parameters.geometry` (UUID string) → `snapshot.resources.geometries[uuid].params.L`
- **Targets:** edge + field('geometry') on CAC + field('Lz') on HD + both node targets
- **fieldPath choice:** `'geometry'` (not `'geom.L'`) — Phase 62 reinterpretation: CAC.geometry is a Resource-FK UUID, so the property panel highlights the geometry-picker, not a nested field
- **FixAction leftLabel:** `Use 0.5` (CAC's L wins → writes to HD.Lz)
- **FixAction rightLabel:** `Use 0.6` (HD's Lz wins → writes to CAC geometry resource)
- **applyLeft:** `live.updateNodeParams(hdId, { parameters: { Lz: cacL } })`
- **applyRight:** `live.updateResource("geometry", uuid, { params: { ...currentParams, L: hdLz } })` — reads live geometry resource first to preserve W/H/D fields
- **Store mutators used:** `updateNodeParams` and `updateResource("geometry", uuid, patch)`

### geometryConsistency (`geometry_consistency`)

- **Trigger:** 2+ CACs share one HD plate (each thermally connected) and their geometry resources disagree on any numeric field (L, W, H, D)
- **Severity:** warning (Julia solver tolerates this; it's a config smell not a hard invariant)
- **Targets:** edge (first CAC's) + field('geometry') for each CAC + node targets for all CACs + HD
- **FixAction label:** `Go to components`
- **No apply closure:** navigation-only has no mechanical fix (multi-field mismatch, no canonical winner)
- **Planner-discretion rationale:** §3.9 does not explicitly assign a FixAction kind to this rule; navigation-only chosen because geometry has multiple fields (Dh, L, Wz), a value-transfer-picker would need N button pairs, and the Julia solver doesn't hard-fail here

## Registered Validators After Plan 05

`gui/src/lib/validation/index.ts` now contains 6 validators:
1. portType (Plan 04)
2. requiredConnections (Plan 04)
3. danglingFlowPort (Plan 04)
4. zNMatch (Plan 05)
5. lengthMatch (Plan 05)
6. geometryConsistency (Plan 05)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Missing required/positional fields on Parameter fixtures in tests**
- **Found during:** tsc --noEmit check after all tasks
- **Issue:** `Parameter` interface requires `required: boolean` and `positional: boolean`; test fixtures omitted both
- **Fix:** Added `required: true, positional: false` to all parameter objects in all three test files
- **Files modified:** zNMatch.test.ts, lengthMatch.test.ts, geometryConsistency.test.ts
- **Commit:** fd941a4

**2. [Rule 1 - Bug] Unused variable `cacIdCapture` in lengthMatch.ts**
- **Found during:** tsc --noEmit check (TS6133)
- **Issue:** `cacIdCapture` captured but never referenced in closures (applyLeft/applyRight only need hdId and geomUuid)
- **Fix:** Removed the unused variable
- **Files modified:** lengthMatch.ts
- **Commit:** fd941a4

## Known Stubs

None — all three rules fire on real snapshot data. No hardcoded empty values, no placeholders.

## Threat Flags

None — these are pure-function validators operating on in-memory model data. No new network endpoints, auth paths, file access patterns, or schema changes at trust boundaries.

## Self-Check: PASSED

Files created:
- gui/src/lib/validation/rules/zNMatch.ts: FOUND
- gui/src/lib/validation/rules/lengthMatch.ts: FOUND
- gui/src/lib/validation/rules/geometryConsistency.ts: FOUND
- gui/src/lib/validation/rules/__tests__/zNMatch.test.ts: FOUND
- gui/src/lib/validation/rules/__tests__/lengthMatch.test.ts: FOUND
- gui/src/lib/validation/rules/__tests__/geometryConsistency.test.ts: FOUND

Commits verified:
- 1fd99d4 (zNMatch + tests + index registration)
- 5639524 (lengthMatch + tests + index registration)
- 4e40da2 (geometryConsistency + tests + index registration)
- fd941a4 (tsc fixes)

All 18 tests pass. tsc: 13 errors (pre-existing baseline, no new errors introduced).
