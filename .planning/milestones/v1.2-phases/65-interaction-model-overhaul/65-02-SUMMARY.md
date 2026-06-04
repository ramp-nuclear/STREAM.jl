---
phase: 65-interaction-model-overhaul
plan: "02"
subsystem: gui/sidebar
tags: [gui, sidebar, reset-to-empty, registry-default, numericfield, phase-65]
dependency_graph:
  requires: []
  provides:
    - "Three-branch blank-on-blur reset rule in NumericField (§3.5)"
    - "Same rule in ParameterForm.ScalarInput for type_union params"
    - "BCsTabForm.ValueModeEditor correctly typed for number | undefined onChange"
    - "Vitest coverage: fixtures A-E in ParameterForm.resetToEmpty.test.tsx"
  affects:
    - "gui/src/components/sidebar/NumericField.tsx"
    - "gui/src/components/sidebar/ParameterForm.tsx"
    - "gui/src/components/sidebar/BCsTabForm.tsx"
tech_stack:
  added: []
  patterns:
    - "Three-branch blank-on-blur: default → restore, required+no-default → error, optional+no-default → onChange(undefined)"
    - "NumericField.onChange widened to (number | undefined) to support optional-omit semantics"
key_files:
  created:
    - gui/src/components/sidebar/__tests__/ParameterForm.resetToEmpty.test.tsx
  modified:
    - gui/src/components/sidebar/NumericField.tsx
    - gui/src/components/sidebar/ParameterForm.tsx
    - gui/src/components/sidebar/BCsTabForm.tsx
decisions:
  - "NumericField.onChange type widened to (number | undefined): required to support Branch 3 (optional-no-default → omit from code-gen). All existing callers already pass onChange callbacks that accept number; TypeScript is satisfied because the implementation only calls with undefined in Branch 3."
  - "BCsTabForm.ValueModeEditor wraps onChange in a guard (if v !== undefined) because param.default is always set to the current numeric value so undefined is structurally unreachable, but the guard is needed for type-correctness."
  - "Fixture D uses a mock WallTemperature definition with default: 300 rather than the live registry (which has no default on T_wall). The live registry entry is required: true with no default — clearing it should show a required error, not reset to 300. The mock correctly captures the plan spec 'with default: 300.0'."
metrics:
  duration: "~25 minutes"
  completed: "2026-05-14"
  tasks_completed: 2
  files_changed: 4
---

# Phase 65 Plan 02: Reset-to-Empty Rule — §3.5 Blank-on-Blur Summary

Centralized three-branch blank-on-blur reset handler across all sidebar numeric property
editors: NumericField (Int/Real), ParameterForm.ScalarInput (type_union scalar path), and
BCsTabForm.ValueModeEditor — replacing the silent no-op that left fields in an ambiguous
empty state.

## What Was Built

### Task 1: NumericField + ParameterForm.ScalarInput (commit 99ade61)

`NumericField.handleBlur` now implements the §3.5 reset-to-empty rule:

```
if trim === '':
  Branch 1 — param.default != null:  onChange(default); setLocalValue(String(default)); clearError
  Branch 2 — param.required === true: setError('required')
  Branch 3 — else:                    onChange(undefined); clearError
else:
  validateReal/validateInt pipeline (unchanged)
```

`ParameterForm.ScalarInput` receives two new props (`paramDefault?: number`, `paramRequired?: boolean`) and implements the same three-branch logic in its `handleBlur`. Both TypeUnionField call sites (non-Sources scalar path at line ~89 and Sources value-mode path at line ~134) now pass `paramDefault: typeof param.default === 'number' ? param.default : undefined` and `paramRequired: param.required ?? false`.

`NumericField.onChange` type widened from `(value: number) => void` to `(value: number | undefined) => void` to support Branch 3's optional-omit semantics.

### Task 2: BCsTabForm.ValueModeEditor + vitest coverage (commit 2b17fb5)

`BCsTabForm.ValueModeEditor` delegates to `NumericField` (already the case before this plan). The fix here was adapting the `onChange` prop wrapper to accept `number | undefined` from the widened NumericField signature. Since `ValueModeEditor` always sets `param.default = value` (the current numeric value), Branch 3 (undefined) is structurally unreachable — but the guard is necessary for type-correctness.

`gui/src/components/sidebar/__tests__/ParameterForm.resetToEmpty.test.tsx` created with 5 fixtures:

| Fixture | Surface | Scenario | Expected |
|---------|---------|----------|----------|
| A | NumericField | default=5.0, required=false | onChange(5.0); field shows "5" |
| B | NumericField | default=null, required=true | destructive error; no numeric onChange |
| C | NumericField | default=null, required=false | onChange(undefined); no error |
| D | TypeUnionField (Sources) | default=300, value-mode | SourceValueEntry {mode:'value',value:300} |
| E | BCsTabForm ValueModeEditor | value=300 | field resets to "300"; no error |

## Verification

- `npx vitest run src/components/sidebar/__tests__/ParameterForm.resetToEmpty.test.tsx`: 5/5 PASS
- `npm run test -- --run`: 1 failed (pre-existing `SidebarPanel.anchors "Symmetric (L = R)"`), 651 passed — no new failures
- `npx tsc --noEmit`: 12 errors (same 12 pre-existing errors as before this plan; 0 new)
- `grep -nE 'paramDefault|param\.default' NumericField.tsx | grep -c .` → 3
- `grep -nE 'paramDefault|param\.default' ParameterForm.tsx | grep -c .` → 10

## Deviations from Plan

### Auto-adjusted: Fixture D uses mock component instead of live WallTemperature

**Found during:** Task 2 test authoring
**Issue:** The plan specified "TypeUnionField for WT.T_wall in value mode with `default: 300.0`" but the live WallTemperature registry entry has no `default` on T_wall (it is `required: true, default: undefined`). Using the live registry for Fixture D would have tested the required-error branch (B), not the default-restore branch.
**Fix:** Fixture D uses a `mockWallTemperatureWithDefault` ComponentDefinition that explicitly sets `default: 300` on `T_wall`. This correctly captures the plan spec's "with default: 300.0" intent.
**Files modified:** `ParameterForm.resetToEmpty.test.tsx` only — no production change.

## Known Stubs

None — all five test fixtures exercise production code paths with real assertions. No placeholder text or hardcoded empty values in the modified production files.

## Threat Flags

None — pure UI state mutation. The reset path writes a registry constant (param.default) through the existing validateReal pipeline. No new network endpoints, auth paths, or schema changes.

## Self-Check: PASSED

- FOUND: `.planning/phases/65-interaction-model-overhaul/65-02-SUMMARY.md`
- FOUND: commit `99ade61` (Task 1 — NumericField + ParameterForm)
- FOUND: commit `2b17fb5` (Task 2 — BCsTabForm + tests)
- FOUND: `gui/src/components/sidebar/__tests__/ParameterForm.resetToEmpty.test.tsx` (5 tests, all pass)
- FOUND: `gui/src/components/sidebar/NumericField.tsx` (3 occurrences of paramDefault/param.default)
- FOUND: `gui/src/components/sidebar/ParameterForm.tsx` (10 occurrences of paramDefault/param.default)
