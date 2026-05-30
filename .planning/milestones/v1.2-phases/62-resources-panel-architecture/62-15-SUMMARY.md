---
phase: 62
plan: 15
subsystem: gui
tags: [gui, copy, voice, professional, cross-cutting, gap-closure]
dependency_graph:
  requires: [62-12, 62-13, 62-14]
  provides: ["engineering-tool voice across Phase 62 UI copy", "test-pinned regression prevention for every substituted string"]
  affects: [Phase-62-VERIFICATION-Gap-4]
tech_stack:
  added: []
  patterns: [string-substitution, test-pinning]
key_files:
  created:
    - .planning/phases/62-resources-panel-architecture/62-15-COPY-AUDIT.md
    - .planning/phases/62-resources-panel-architecture/62-15-SUMMARY.md
    - gui/src/store/__tests__/saveAndOpenErrors.test.ts
  modified:
    - gui/src/store/useStore.ts
    - gui/src/components/sidebar/ResourceReferencePicker.tsx
    - gui/src/components/sidebar/GeometryResourceEditor.tsx
    - gui/src/components/sidebar/PowerShapeResourceEditor.tsx
    - gui/src/components/sidebar/SidebarPanel.tsx
    - gui/src/components/resources/ResourcesTreePanel.tsx
    - gui/src/components/resources/ResourceRow.tsx
    - gui/src/components/resources/ResourceGroupHeader.tsx
    - gui/src/components/project/ModelOptionsPanel.tsx
    - gui/src/components/sidebar/__tests__/ResourceReferencePicker.test.tsx
    - gui/src/components/sidebar/__tests__/GeometryResourceEditor.test.tsx
    - gui/src/components/sidebar/__tests__/PowerShapeResourceEditor.test.tsx
    - gui/src/components/sidebar/__tests__/SidebarRouter.test.tsx
    - gui/src/components/resources/__tests__/ResourcesTreePanel.test.tsx
    - gui/src/components/project/__tests__/ModelOptionsPanel.test.tsx
    - gui/src/components/__tests__/AppShell.test.tsx
    - gui/src/components/__tests__/ToolboxPanel.test.tsx
    - gui/src/lib/__tests__/codeGenerator.smoke.test.ts
    - gui/src/lib/__tests__/codeGenerator.resources.test.ts
    - gui/src/lib/__tests__/projectIO.scp.test.ts
    - gui/src/store/__tests__/resources.slice.test.ts
    - gui/src/store/__tests__/selection.test.ts
    - gui/src/store/__tests__/activeLeftTab.test.ts
    - gui/src/store/__tests__/modelOptions.test.ts
    - gui/src/store/__tests__/saveProjectAs.test.ts
decisions:
  - "Supersedes D-26 sentinel string: '(leave unset — fill in code)' → '(leave unset — set in code)'."
  - "ResourceGroupHeader.tsx doc-comment updated to match new tooltip copy (outside files_modified, but required for grep-gate cleanliness — recorded as deviation)."
  - "ModelOptionsPanel.tsx 'Default fluid' disabled tooltip rewritten in parallel with ResourcesTreePanel.tsx Fluids `+` tooltip (the same string at two mount points — discovered during gate verification, applied per Rule 2)."
  - "All 11 non-files-modified test seeds that carried the OLD sentinel literal '(leave unset — fill in code)' rewritten to the NEW value, so in-memory store fixtures stay consistent with the source-of-truth constant in useStore.ts."
metrics:
  duration: "executor run"
  completed: "2026-05-13"
---

# Phase 62 Plan 15: Cross-cutting copy audit — engineering-tool voice rewrite

Phase 62 user-facing strings rewritten to engineering-tool voice per
VERIFICATION.md Critical Gap #4. 19 substitutions across 8 source files +
1 audit doc + 5 test-file pinning updates + 1 new error-dialog test file;
zero regressions on the full GUI vitest suite.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical functionality] ModelOptionsPanel.tsx carried a second copy of the Fluids disabled-tooltip**

- **Found during:** Task 1 grep-gate verification.
- **Issue:** The plan's substitution table row #13 lists only `ResourcesTreePanel.tsx`, but the identical OLD string `Multi-fluid support is planned for a future release.` also exists in `ModelOptionsPanel.tsx` (the Default-fluid disabled-tooltip). The plan's `<action>` Step C grep gate would fail if either occurrence is left in place. `ModelOptionsPanel.tsx` is in `files_modified`, so this is in-scope.
- **Fix:** Updated ModelOptionsPanel.tsx to use the new copy `Multiple fluids not yet supported.` and added a row #13b to the COPY-AUDIT.md substitution table documenting this second mount point.
- **Files modified:** `gui/src/components/project/ModelOptionsPanel.tsx`
- **Commit:** 835b146

**2. [Rule 1 - Bug] ResourceGroupHeader.tsx doc-comment kept the OLD tooltip literal verbatim**

- **Found during:** Task 1 grep-gate verification.
- **Issue:** `gui/src/components/resources/ResourceGroupHeader.tsx` had a docstring block that quoted the canonical Fluids disabled-tooltip as `"Multi-fluid support is planned for a future release."`. The grep gate `grep -rE "is planned for a future release" src/ | grep -v __tests__` would fail because of this comment. The file is NOT in `files_modified` (only ResourcesTreePanel.tsx and ModelOptionsPanel.tsx are listed), but updating a code-comment to track the new canonical copy is a docs-only change with no behavior impact.
- **Fix:** Rewrote the doc-comment to reference the new copy and explain the supersession without re-quoting the OLD literal verbatim (which would itself re-trip the grep gate).
- **Files modified:** `gui/src/components/resources/ResourceGroupHeader.tsx`
- **Commit:** 835b146

**3. [Rule 1 - Bug] 11 test seed files carried the OLD sentinel literal**

- **Found during:** Task 2 grep-gate verification.
- **Issue:** After the SENTINEL_POWER_SHAPE_NAME constant was rewritten, 11 test files outside `files_modified` still seeded the in-memory store with the OLD literal `"(leave unset — fill in code)"` via `useStore.setState`. While the tests still passed (the literal is just data, not asserted), the fixtures were inconsistent with the new source-of-truth constant. `resources.slice.test.ts` explicitly asserted the OLD literal on lines 298 and 325 — those assertions would silently lock the rewrite in if they remained.
- **Fix:** Updated the literal in all 11 seed files. The `resources.slice.test.ts` direct assertions are now pinned to the NEW literal.
- **Files modified:** `gui/src/store/__tests__/resources.slice.test.ts`, `gui/src/store/__tests__/selection.test.ts`, `gui/src/store/__tests__/activeLeftTab.test.ts`, `gui/src/store/__tests__/modelOptions.test.ts`, `gui/src/store/__tests__/saveProjectAs.test.ts`, `gui/src/components/__tests__/AppShell.test.tsx`, `gui/src/components/__tests__/ToolboxPanel.test.tsx`, `gui/src/lib/__tests__/codeGenerator.smoke.test.ts`, `gui/src/lib/__tests__/codeGenerator.resources.test.ts`, `gui/src/lib/__tests__/projectIO.scp.test.ts`, `gui/src/components/sidebar/__tests__/SidebarRouter.test.tsx`
- **Commit:** cda552b

**4. [Rule 2 - Missing critical functionality] SidebarPanel.tsx had no dedicated test file pinning its no-selection variant copy**

- **Found during:** Task 2 — the plan suggested creating `gui/src/components/sidebar/__tests__/SidebarPanel.test.tsx` if no test file exists.
- **Issue:** `SidebarPanel.test.tsx` does exist but is all `.todo` stubs (no real coverage). The actual SidebarPanel selection-kind dispatch and no-selection copy IS covered by `gui/src/components/sidebar/__tests__/SidebarRouter.test.tsx` (added in plan 62-09; specifically the "no-selection body — Resources tab active shows variant copy" / "Components tab active shows standard copy" tests).
- **Fix:** Updated SidebarRouter.test.tsx in place rather than adding a duplicate test file. SidebarRouter.test.tsx is the canonical SidebarPanel test today.
- **Files modified:** `gui/src/components/sidebar/__tests__/SidebarRouter.test.tsx`
- **Commit:** cda552b

## Substitutions applied (19 rows + 1 auxiliary)

Full table in `62-15-COPY-AUDIT.md`. Highlights:

| Surface | Old | New |
|---|---|---|
| Sentinel power-shape name | `(leave unset — fill in code)` | `(leave unset — set in code)` |
| ResourceReferencePicker empty-state (geometry / power-shape) | `No geometries yet — click + New… or open the Resources tab.` | `No geometries. Use + New or the Resources tab.` |
| ResourceReferencePicker Edit-disabled tooltip | `Select a resource to edit it.` | `Pick a resource first.` |
| Geometry/PowerShape identifier-error | `Use ASCII letters, digits, and underscores; must not start with a digit.` | `Letters, digits, underscores. Cannot start with a digit.` |
| Amplitude validation | `Amplitude must be a finite number.` | `Amplitude must be finite.` |
| Missing-CSV validation | `Please pick a CSV file via Browse.` | `Pick a CSV file via Browse.` |
| SidebarPanel no-selection (Resources tab) | `Select a resource on the left to edit it.` | `Select a resource to edit it.` |
| SidebarPanel no-selection (other tabs) | `Select a component on the canvas to view its properties.` | `Select a component to view its properties.` |
| Fluids `+` disabled tooltip (both mount points) | `Multi-fluid support is planned for a future release.` | `Multiple fluids not yet supported.` |
| AlertDialog delete description | `… It is used by N component(s).` | `… Used by N component(s).` |
| Save failed dialog (×2) | `Couldn't save project. Check that the file isn't read-only …` | `Save failed. Check the file is writable and there is disk space.` |
| Open failed dialog (×2) | `Couldn't open this project. The file may be missing …` | `Open failed. The file may be missing, corrupted, or not a valid .scp file.` |
| Missing-file dialog body (singular + plural) | `N power shape file(s) could not be found. Open the Resources tab to relocate them.` | `N power-shape file(s) not found. Open the Resources tab to relocate.` |
| Missing-file dialog title | `Missing Power Shape file` | `Missing power-shape file` |

Two strings left as NO-CHANGE per audit (already terse and on-voice):
`Search resources…` placeholder, `kindLabel` return values.

## Tests touched

| Test file | Type of change |
|---|---|
| `gui/src/components/sidebar/__tests__/ResourceReferencePicker.test.tsx` | Sentinel rename + empty-state + tooltip copy + new power-shape empty-state pin |
| `gui/src/components/sidebar/__tests__/GeometryResourceEditor.test.tsx` | Identifier error copy ×2 + sentinel seed |
| `gui/src/components/sidebar/__tests__/PowerShapeResourceEditor.test.tsx` | Sentinel seed + new validation copy describe block (×3 new assertions) |
| `gui/src/components/sidebar/__tests__/SidebarRouter.test.tsx` | No-selection variant copy ×2 + sentinel seed |
| `gui/src/components/resources/__tests__/ResourcesTreePanel.test.tsx` | Sentinel seed + AlertDialog regex ×4 + new Fluids tooltip describe block |
| `gui/src/components/project/__tests__/ModelOptionsPanel.test.tsx` | Sentinel seed |
| `gui/src/components/__tests__/AppShell.test.tsx` | Sentinel seed |
| `gui/src/components/__tests__/ToolboxPanel.test.tsx` | Sentinel seed |
| `gui/src/lib/__tests__/codeGenerator.smoke.test.ts` | Sentinel seed |
| `gui/src/lib/__tests__/codeGenerator.resources.test.ts` | Sentinel seed |
| `gui/src/lib/__tests__/projectIO.scp.test.ts` | Sentinel seed |
| `gui/src/store/__tests__/resources.slice.test.ts` | Sentinel seed + 2 direct assertions of the new sentinel name |
| `gui/src/store/__tests__/selection.test.ts` | Sentinel seed |
| `gui/src/store/__tests__/activeLeftTab.test.ts` | Sentinel seed |
| `gui/src/store/__tests__/modelOptions.test.ts` | Sentinel seed |
| `gui/src/store/__tests__/saveProjectAs.test.ts` | Sentinel seed |
| `gui/src/store/__tests__/saveAndOpenErrors.test.ts` (NEW) | 5 new tests pinning Save/Open error copy + missing-file singular/plural/title |

## Verification evidence

### Vitest

**Phase 62 scoped suite** (sidebar + resources + project + store):

```
Test Files  17 passed | 1 skipped (18)
     Tests  236 passed | 13 todo (249)
```

Baseline before plan: 225 pass / 13 todo. Delta: +11 new pinning tests, 0 regressions.

**Full GUI vitest suite:**

```
Test Files  31 passed | 1 skipped (32)
     Tests  440 passed | 13 todo (453)
```

Baseline before plan: 429 pass / 13 todo. Delta: +11, 0 regressions.

### TypeScript

`cd gui && ./node_modules/.bin/tsc --noEmit | grep -cE "error TS"` returns **8** —
exactly matches the pre-change baseline (no new TS errors introduced).
Pre-existing errors are in StreamNode.tsx (×2), ToolboxPanel.test.tsx
(LayerView mismatch), SidebarRouter.test.tsx (×2 unused `peaking` props
on PowerShapeResource params — pre-existing test fixture issue),
validation.test.ts (×3 unused-import warnings).

### Source-side OLD-string grep gates (each MUST be 0)

```
'fill in code' (non-test src): 0
'Please pick' (non-test src): 0
'is planned for a future release' (non-test src): 0
'It is used by' (non-test src): 0
'Couldn't save project' (non-test src): 0
'Couldn't open this project' (non-test src): 0
```

### Source-side NEW-string grep gates (each MUST be ≥ 1 in owning file)

```
'set in code' in useStore.ts: 1
'set in code' in ResourceReferencePicker.tsx: 2  (sentinel item + doc comment)
'Pick a resource first' in ResourceReferencePicker.tsx: 2  (tooltip + doc comment)
'Save failed' in useStore.ts: 2  (saveProject + saveProjectAs catch branches)
'Open failed' in useStore.ts: 2  (loadProject + loadProjectFromPath catch branches)
'Multiple fluids not yet supported' in ResourcesTreePanel.tsx: 1
'Used by ${usages.length}' in ResourceRow.tsx: 1
'Amplitude must be finite' in PowerShapeResourceEditor.tsx: 1
```

### Test pinning grep gates

```
'Pick a resource first' in sidebar tests: ≥ 1 (ResourceReferencePicker.test.tsx)
'Letters, digits, underscores' in sidebar tests: ≥ 2 (Geometry + PowerShape editor tests)
'Amplitude must be finite' in PowerShape test: ≥ 1
'Pick a CSV file via Browse' in PowerShape test: ≥ 1
'Multiple fluids not yet supported' in ResourcesTreePanel test: ≥ 1
'set in code' in sidebar tests: ≥ 1 (multiple seed sites + assertion sites)
'fill in code' anywhere in src/components: 1  (a HISTORICAL doc-comment reference inside ResourceReferencePicker.test.tsx — kept intentionally as supersession audit trail)
'It is used by' anywhere in src/components: 0
'Save failed' OR 'Open failed' in store tests: ≥ 1 (saveAndOpenErrors.test.ts)
```

### Out-of-scope grep hits

Two unrelated `on the canvas` hits remain in `src/lib/codeGenerator.ts:258`
and `src/registry/types.ts:194`. Both are normal English usage in
implementation-doc comments about WallTemperature/HeatFluxSource sync
blocks. These files are outside `files_modified` and outside the
substitution-table scope. Not touched.

The historical doc-comment reference to `(leave unset — fill in code)`
inside `ResourceReferencePicker.test.tsx:122` is kept intentionally — it
documents the supersession of D-26 as an audit trail for the next
maintainer.

## Commits

| SHA | Subject |
|---|---|
| 835b146 | refactor(62-15): rewrite Phase 62 user-facing copy to engineering-tool voice |
| cda552b | test(62-15): pin engineering-voice copy in vitest assertions + new save/open error tests |

## Closes

VERIFICATION.md Critical Gap #4: "Professional copy pass — user-facing
strings read as 'AI-ish'".

## Self-Check: PASSED

- `62-15-COPY-AUDIT.md` exists: FOUND
- `62-15-SUMMARY.md` exists: FOUND
- Commit 835b146: FOUND
- Commit cda552b: FOUND
- All 19 substitutions present in source: VERIFIED via NEW-string grep gates above
- All OLD-string grep gates: VERIFIED 0 hits in source
- Phase 62 vitest: 236 pass / 13 todo (≥ baseline 225)
- Full vitest: 440 pass / 13 todo (≥ baseline 429)
- tsc: 8 errors (= baseline)
