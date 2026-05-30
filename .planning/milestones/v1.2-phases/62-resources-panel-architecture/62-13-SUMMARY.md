---
phase: 62
plan: 13
subsystem: gui-resources
tags: [gui, resources, alert-dialog, usage-detection, gap-closure, tdd]
gap_closure: true
gap_source: 62-VERIFICATION.md
gap_step: 11
root_plan: 62-06
requires:
  - 62-06  # AlertDialog JSX, handleDelete branching
  - 62-08  # ParameterForm writes uuid under registry param name
provides:
  - "Dual-key usage detection (registry-name OR _ref-suffixed) in ResourceRow.tsx"
  - "5 new vitest cases pinning live + legacy + mixed paths, Cancel focus, destructive variant"
affects:
  - "Right-click → Delete on USED resource now correctly opens AlertDialog in the running app"
tech-stack:
  added: []
  patterns:
    - "Dual-key fallback (mirrors codeGenerator.ts:803 `power_shape_ref ?? power_shape`)"
key-files:
  created: []
  modified:
    - gui/src/components/resources/ResourceRow.tsx
    - gui/src/components/resources/__tests__/ResourcesTreePanel.test.tsx
decisions:
  - "OR-scan across both key forms (not data migration). Keeps existing .scp / fixtures / codeGenerator working without forcing a rewrite of legacy data."
  - "Module-level PARAM_KEY_BY_KIND const for auditability over inline conditional."
metrics:
  duration: "~8 minutes"
  completed: "2026-05-13"
  vitest_pass: 22
  vitest_fail: 0
  tsc_baseline_errors: 8
  tsc_new_errors: 0
commits:
  red: 3abc0bc
  green: f9cfd9d
---

# Phase 62 Plan 13: Delete AlertDialog Usage Detection Gap Closure Summary

One-liner: Fixed live AlertDialog never firing by OR-scanning both `parameters[name]` (live ParameterForm) and `parameters[name + "_ref"]` (legacy fixtures) in ResourceRow's usage-detection useMemo.

## Root Cause

The AlertDialog UI from Plan 62-06 was correct, but its trigger condition `usages.length > 0` was always 0 in the running app. Two reasons:

1. **Data-write path (ParameterForm.tsx lines 91-131, Plan 62-08):** `onParamChange(param.name, uuid)` is called with `param.name = "geometry"` or `param.name = "power_shape"` (registry parameter name from `components.json`). So nodes have `data.parameters.geometry === <uuid>`.
2. **Data-read path (ResourceRow.tsx lines 77-91, Plan 62-06):** The `refKey` useMemo built `"geometry_ref"` / `"power_shape_ref"` and filtered nodes by that suffixed key only. The `_ref` suffix never matched the live data.

The mismatch was masked by the existing vitest case at line 313 which seeded `parameters.geometry_ref: uuid` — a fixture key, not the live key — so CI stayed green while the app silently bypassed the dialog.

The codebase already had a precedent for the dual-key pattern at `gui/src/lib/codeGenerator.ts:803`: `data.parameters["power_shape_ref"] ?? data.parameters["power_shape"]`. The fix mirrors that discipline.

## Fix Pattern

A module-level constant `PARAM_KEY_BY_KIND: Record<ResourceKind, readonly string[]>` maps each kind to an ordered list of param keys to scan:

```ts
const PARAM_KEY_BY_KIND: Record<ResourceKind, readonly string[]> = {
  geometry: ["geometry", "geometry_ref"],
  powerShape: ["power_shape", "power_shape_ref"],
  fluid: [],
};
```

The `usages` useMemo now OR-scans across all keys:

```ts
return paramKeys.some((k) => params[k] === resource.uuid);
```

The old `refKey` useMemo is subsumed and removed. The AlertDialog JSX, `handleDelete`, `handleConfirmedDelete`, and copy text are unchanged — the fix is purely in the data-read path.

## TDD Cycle

| Phase | Commit  | Result                                                  |
| ----- | ------- | ------------------------------------------------------- |
| RED   | 3abc0bc | 5 new vitest cases added; 5 failed, 17 baseline passed |
| GREEN | f9cfd9d | usage useMemo fixed; all 22 cases pass                 |

No REFACTOR phase needed — the implementation landed clean.

## Test Coverage Added

1. **Live path — geometry**: node with `parameters: { geometry: uuid }` opens AlertDialog with description `Delete geometry g_live? It is used by 1 component(s).` and Cancel preserves the resource.
2. **Live path — power shape**: node with `parameters: { power_shape: uuid }` opens AlertDialog with description `Delete power shape ps_live? It is used by 1 component(s).`
3. **Mixed keys**: two nodes, one under `geometry`, one under `geometry_ref` → description `used by 2 component(s)`.
4. **Default focus**: after dialog opens, `document.activeElement.textContent === "Cancel"` (Radix first-focusable behavior pinned).
5. **Destructive variant**: "Delete anyway" button has `data-variant="destructive"` or className containing `destructive`.

The existing test at line 313 (legacy `geometry_ref` fixture path) and the zero-usages immediate-delete test at line 296 both continue to pass unchanged.

## Acceptance Criteria

| Criterion                                                                                | Result |
| ---------------------------------------------------------------------------------------- | ------ |
| Vitest scoped to ResourcesTreePanel: 22/22 pass                                          | PASS   |
| `grep -cE "PARAM_KEY_BY_KIND" ResourceRow.tsx` ≥ 1                                       | 3      |
| `grep -cE "geometry_ref" ResourceRow.tsx` ≥ 1                                            | 2      |
| `grep -cE "power_shape_ref" ResourceRow.tsx` ≥ 1                                         | 3      |
| `grep -cE "Phase 62-13" ResourceRow.tsx` ≥ 1                                             | 2      |
| `grep -cE "parameters: \\{ geometry:" test file` ≥ 1                                     | 4      |
| `grep -cE "parameters: \\{ power_shape:" test file` ≥ 1                                  | 1      |
| `grep -cE "activeElement" test file` ≥ 1                                                 | 1      |
| `grep -cE "destructive" test file` ≥ 1                                                   | 6      |
| `npx tsc --noEmit` errors ≤ baseline 8                                                   | 8 (unchanged) |

## Deviations from Plan

None — plan executed exactly as written.

## Files Modified

- `gui/src/components/resources/ResourceRow.tsx` (+22, −10 lines)
- `gui/src/components/resources/__tests__/ResourcesTreePanel.test.tsx` (+200, −1 lines)

## Commits

- `3abc0bc` — `test(62-13): RED — failing tests for live-path AlertDialog usage detection`
- `f9cfd9d` — `feat(62-13): GREEN — usage detection scans both registry-name and _ref keys`

## Follow-up / Verification

Closes VERIFICATION.md Critical Gap #2. Human-verify re-run of VERIFICATION Step 11 (right-click a used Geometry resource in the live app → AlertDialog should now appear) is deferred to the post-gap-closure checkpoint plan as specified in the plan's `<verification>` section.

## Self-Check: PASSED

- `gui/src/components/resources/ResourceRow.tsx` modified: confirmed via git diff.
- `gui/src/components/resources/__tests__/ResourcesTreePanel.test.tsx` modified: confirmed via git diff.
- RED commit `3abc0bc`: present in `git log`.
- GREEN commit `f9cfd9d`: present in `git log`.
- 22 vitest cases pass scoped to ResourcesTreePanel.test.tsx (verified).
- tsc baseline preserved at 8 errors (verified, zero new errors).
