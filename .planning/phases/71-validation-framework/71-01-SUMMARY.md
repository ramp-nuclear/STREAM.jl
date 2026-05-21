---
phase: 71-validation-framework
plan: "01"
subsystem: gui-validation
tags: [validation, registry, store, refactor, typescript, react]
dependency_graph:
  requires: []
  provides:
    - gui/src/lib/validation/types.ts (Validator, ValidationResult, Target, FixAction)
    - gui/src/lib/validation/snapshot.ts (ValidationSnapshot, buildValidationSnapshot)
    - gui/src/lib/validation/runner.ts (runValidators)
    - gui/src/lib/validation/index.ts (validators[] registry)
    - gui/src/lib/validation/fields.ts (field helper functions)
    - store validationResults slice + activeBottomTab slice + initValidation()
  affects:
    - gui/src/store/useStore.ts (new slices, subscription, D-18 errorNodeIds cleanup)
    - gui/src/components/sidebar/NumericField.tsx (import path)
    - gui/src/components/sidebar/InstanceNameField.tsx (import path)
    - gui/src/components/sidebar/ParameterForm.tsx (import path)
    - gui/src/lib/codeGenerator.ts (import path)
tech_stack:
  added: []
  patterns:
    - Discriminated-union FixAction with store-handle-parameterized apply closures (Pitfall 7 mitigation)
    - Debounced zustand subscribe pattern (mirrors initAutoRecover)
    - Pure-function validator registry (D-06 purity invariant)
key_files:
  created:
    - gui/src/lib/validation/types.ts
    - gui/src/lib/validation/snapshot.ts
    - gui/src/lib/validation/runner.ts
    - gui/src/lib/validation/index.ts
    - gui/src/lib/validation/fields.ts
    - gui/src/lib/validation/__tests__/runner.test.ts
    - gui/src/lib/validation/__tests__/fields.test.ts
  modified:
    - gui/src/store/useStore.ts
    - gui/src/components/sidebar/NumericField.tsx
    - gui/src/components/sidebar/InstanceNameField.tsx
    - gui/src/components/sidebar/ParameterForm.tsx
    - gui/src/lib/codeGenerator.ts
decisions:
  - "FixAction uses store-handle-parameterized apply closures (StoreSetter/StoreGetter) rather than plain () => void — prevents Pitfall 7 stale closure capture"
  - "AppState exported from useStore.ts to allow import type in types.ts (required for StoreSetter/StoreGetter type aliases)"
  - "validationResults: [] write count = 8 (N_RESET=6 resets + 1 interface + 1 initValidation subscriber write) — plan formula N_RESET+1=7 did not account for subscriber write site"
  - "validation/ purity invariant: snapshot.ts uses import type from store (zero runtime emission), runner/index/types/fields have no store imports at all"
metrics:
  duration_minutes: 70
  completed_date: "2026-05-21"
  tasks_completed: 3
  tasks_total: 3
  files_created: 7
  files_modified: 5
---

# Phase 71 Plan 01: Validation Framework Foundation Summary

Laid the validation-framework foundation: Validator interface, ValidationResult schema with FixAction 3-kind discriminated union (store-handle-parameterized apply closures), ValidationSnapshot + runner, empty validator registry, migrated field helpers, rewired importers, and wired store slices + debounced initValidation() subscription.

## What Was Built

**New `gui/src/lib/validation/` directory** (5 source files + 2 test files):

- **types.ts** — Validator, ValidationResult, Target (node/field/edge/port), FixAction (3-kind: lossless-sync, value-transfer-picker, navigation-only) with StoreSetter/StoreGetter store-handle-parameterized apply closures per RESEARCH §Pitfall 7. Severity type alias.
- **snapshot.ts** — ValidationSnapshot interface (nodes, edges, anchors, bcMode, resources, getComponentDef) + buildValidationSnapshot(state) helper.
- **runner.ts** — runValidators(snapshot) pure function; flat-maps over validators[].
- **index.ts** — empty validators: Validator[] registration array with D-07 doc convention (explicit imports, no import.meta.glob).
- **fields.ts** — validateInt, validateReal, validatePositiveReal, validateJuliaIdentifier copied verbatim from validation.ts; result types renamed FieldValidationResult/FieldStringValidationResult to avoid D-11 collision.
- **__tests__/runner.test.ts** — 3 tests: empty registry, stub validator, FixAction lossless-sync apply contract pin.
- **__tests__/fields.test.ts** — 26 field-validator tests (from validation.test.ts, import path updated).

**Import rewires** (Task 2): NumericField, InstanceNameField, ParameterForm → `@/lib/validation/fields`; codeGenerator → `./validation/fields`. No behavior change.

**Store changes** (Task 3):
- AppState now exported (required for StoreSetter/StoreGetter type aliases in types.ts).
- New imports: runValidators, buildValidationSnapshot, ValidationResult.
- AppState interface: `validationResults: ValidationResult[]`, `activeBottomTab: 'code' | 'validation'`, `setActiveBottomTab` action.
- Initial state + 6 reset blocks: `validationResults: []` + `activeBottomTab: 'code'` added alongside each `validationResult: null`.
- `setActiveBottomTab` action (session-only, no isDirty).
- `initValidation()` exported: debounced 150ms subscribe on 5 fields; writes validationResults + errorNodeIds atomically.
- Removed ad-hoc errorNodeIds mutation from addEdge (D-18 single-source compliance).
- validateAndGate, clearValidation, validationResult legacy slice all kept in place for Plans 12/13.

## Baseline Measurements

- **Typecheck baseline (pre-flight):** 13 `error TS` occurrences (all pre-existing; not introduced by this plan).
- **Typecheck post-plan:** 13 (unchanged — at baseline).
- **N_OLD (pre-flight `validationResult\b` count):** 9 sites in useStore.ts.
- **N_OLD post-task:** 9 (unchanged — no legacy sites added or removed).
- **Test count:** 462 passing / 9 todo across 39 test files (all validation, store, sidebar, codeGenerator tests pass).

## FixAction Discriminant Verification

| Grep | Count |
|------|-------|
| `lossless-sync` in types.ts | 1 |
| `value-transfer-picker` in types.ts | 2 (kind literal + type body comment) |
| `navigation-only` in types.ts | 2 (kind literal + type body comment) |
| `applyLeft\|applyRight` in types.ts | 3 |
| `StoreSetter\|StoreGetter` in types.ts | 8 |

All three FixAction kinds present with correct shape. navigation-only has no apply closure (confirmed).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] AppState not exported from useStore.ts**
- **Found during:** Task 1 typecheck
- **Issue:** `types.ts` uses `import type { AppState }` to lift StoreSetter/StoreGetter signatures from zustand, but AppState was declared as `interface AppState` (unexported). TypeScript errored: "Module has no exported member 'AppState'".
- **Fix:** Added `export` to `interface AppState` declaration (line 182 of useStore.ts).
- **Files modified:** gui/src/store/useStore.ts
- **Commit:** 0d2136a (included in Task 1 commit)

**2. [Rule 1 - Bug] vi.mock hoisting in runner.test.ts caused ReferenceError**
- **Found during:** Task 1 test run
- **Issue:** vitest hoists `vi.mock()` calls to the top of the module, but the mock factory referenced a local `stubValidator` variable that wasn't defined at hoist time.
- **Fix:** Restructured test to use a module-level mutable `_validators` array with a getter-based mock factory; tests manipulate `_validators` directly in beforeEach/test body.
- **Files modified:** gui/src/lib/validation/__tests__/runner.test.ts

**3. [Rule 1 - Bug] TS2352 type assertion in runner.test.ts apply closure**
- **Found during:** Task 1 typecheck
- **Issue:** `set({ nodes: [] } as Parameters<typeof set>[0]` emitted TS2352 because `{ nodes: never[] }` doesn't sufficiently overlap with the full AppState shape.
- **Fix:** Changed to `(set as any)({ nodes: [] })` — the test only needs to verify mockSet is called; exact type conformance is enforced at the declaration site in types.ts.

### Count Deviation (expected)

The acceptance criterion formula `grep -c "validationResults:" = N_RESET + 1 = 7` expected 7, but the actual count is 8. The extra occurrence is the `useStore.setState({ validationResults: results, ... })` write inside `initValidation()`'s subscriber callback — which is required for the subscription to work. The plan formula only counted "interface declaration + reset blocks" and did not account for the subscriber write site. This is a planner oversight, not an implementation error.

## Known Stubs

None. This plan adds scaffold and wiring only; no UI is rendered. The `validators: Validator[] = []` empty array is the intentional starting state (rules plans 04-08 populate it). No data flows to UI surfaces from this plan.

## Threat Flags

None. Pure TypeScript/in-memory logic. No new network endpoints, auth paths, file access, or schema changes at trust boundaries.

## Self-Check

**Files created:**
- FOUND: gui/src/lib/validation/types.ts
- FOUND: gui/src/lib/validation/snapshot.ts
- FOUND: gui/src/lib/validation/runner.ts
- FOUND: gui/src/lib/validation/index.ts
- FOUND: gui/src/lib/validation/fields.ts
- FOUND: gui/src/lib/validation/__tests__/runner.test.ts
- FOUND: gui/src/lib/validation/__tests__/fields.test.ts

**Commits:**
- FOUND: 0d2136a (Task 1: scaffold validation/ directory)
- FOUND: 3d2f4e1 (Task 2: rewire field-helper imports)
- FOUND: 2598853 (Task 3: store slices + initValidation)

## Self-Check: PASSED
