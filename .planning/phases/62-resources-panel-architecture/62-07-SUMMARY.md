---
phase: 62
plan: 07
subsystem: gui
tags: [gui, project-tab, model-options, form, d-04, cd-04]
requires: [62-02, 62-05]
provides: [model-options-form, project-tab-body]
affects: [gui/src/App.tsx]
tech_stack:
  added: []
  patterns: [local-edit-buffer + onBlur commit; useEffect re-sync for undo/load; shallow merge on solver subtree]
key_files:
  created:
    - gui/src/components/project/ModelOptionsPanel.tsx
    - gui/src/components/project/__tests__/ModelOptionsPanel.test.tsx
  modified:
    - gui/src/App.tsx
decisions:
  - "Description rendered as a plain styled <textarea>, NOT a new shadcn `textarea.tsx` shim — single use site doesn't justify a reusable primitive yet."
  - "Built form rows inline with <Input> + <Label> + local state instead of reusing sidebar NumericField / InstanceNameField — those primitives are coupled to the registry Parameter shape and Julia-identifier validation respectively; neither contract fits this form."
  - "dtmax blank-string → null on blur (no-cap semantics per CD-04 + UI-SPEC §Solver defaults exposure). abstol / reltol blank → revert to current store value (those cannot be null)."
  - "Solver-subobject commits use shallow merge: setModelOptions({ solver: { ...modelOptions.solver, [key]: n } }) so editing one solver field never zaps the other two."
metrics:
  duration: "~25 minutes (single-session execution)"
  tasks_completed: 2
  files_changed: 3
  commits: 2
  tests_added: 17
---

# Phase 62 Plan 07: ModelOptionsPanel (Project Tab Body) Summary

One-liner: Project tab body wired as the Model Options form per D-04 + CD-04, with Name / Description / read-only Default fluid / Default g / Solver Defaults (abstol, reltol, dtmax) committing on blur to the existing `modelOptions` store slice.

## What Shipped

- `gui/src/components/project/ModelOptionsPanel.tsx` — entire Project-tab body. No inner selection step (D-04). All editable fields use a local edit-buffer (`useState`) mirroring the store, with `useEffect` re-syncing on outside changes (undo / redo / project load). Each field commits on `onBlur` through `useStore.setModelOptions(patch)`, which already calls `_pushSnapshot()` and flips `isDirty` (wired by plan 62-02).
- `gui/src/App.tsx` — `<TabsContent value="Project">` now mounts `<ModelOptionsPanel />` (replaces the 62-05 stub `<div>Project panel — coming in plan 62-07</div>`).
- `gui/src/components/project/__tests__/ModelOptionsPanel.test.tsx` — 17 vitest cases covering render shape (D-04 heading + every field + Solver Defaults subsection), default values, exact CD-04 solver field set (negative coverage: no `alg` / `progress_callback` / `maxiters` / `saveat`), read-only Default fluid, on-blur commits for Name + Description + Default g, solver shallow-merge correctness (abstol commit leaves reltol & dtmax untouched), dtmax blank ↔ null semantics, and undo snapshot push on field commit.

## Decisions Made

### Description rendering: plain `<textarea>`, not a new shadcn shim

UI-SPEC §"Project tab body — Fields" left this to executor discretion: `Description (Textarea — needs new textarea.tsx shim, or reuse Input with as="textarea" if available — executor picks)`. The implementation inlines a plain `<textarea>` element with the same Tailwind className spine as `<Input>`. Rationale:
- Single use site — Description is the only multi-line field anywhere in Phase 62.
- A real shadcn `textarea.tsx` would add a fourth `ui/` primitive that nothing else consumes.
- The inlined `<textarea>` is ~12 lines including the className; a shim file would not be materially smaller.

If a future plan adds a second textarea consumer (e.g. CHF rationale notes, project change-log field), promote to `gui/src/components/ui/textarea.tsx` at that point and migrate both call sites.

### Field primitives: inline rather than reusing sidebar/NumericField + InstanceNameField

The plan suggested reusing `NumericField` and `InstanceNameField`, but their existing signatures are coupled to:
- `NumericField` — registry `Parameter` shape (`{name, type, default, unit?, description?, ...}`). Model Options fields are NOT registry parameters — there is no `Parameter` record.
- `InstanceNameField` — Julia-identifier validation (`/^[a-zA-Z_][a-zA-Z0-9_]*$/`). Project Name is a free string, not a Julia identifier.

Forcing those primitives onto this form would mean either (a) inventing fake `Parameter` records per field (a lie that future readers would have to decode) or (b) widening the primitive APIs purely to satisfy one consumer. Inline `<Input>` + `<Label>` + local state + onBlur is cleaner; the `FieldRow` helper at the top of the file deduplicates the label-with-info-tooltip pattern.

### dtmax blank ↔ null

UI-SPEC says `dtmax (default nothing / blank — interpreted as no cap)`. Implementation:
- Initial render: `useState(stringifyNumber(modelOptions.solver.dtmax))` → empty string when the store holds `null`.
- On blur: if the trimmed input is `""`, commit `{ solver: { ...solver, dtmax: null } }`; if it parses to a finite number, commit that number; otherwise revert.
- `abstol` and `reltol` cannot be null (they are `number`, not `number | null`); a blank entry reverts to the previous store value rather than committing.

### Solver subobject shallow merge

`setModelOptions({ solver: <object> })` REPLACES the solver subtree because the top-level patch merge is shallow. To preserve sibling solver fields when editing one, the component splats the existing solver: `setModelOptions({ solver: { ...modelOptions.solver, [key]: n } })`. The test `CD-04: abstol blur commits to solver.abstol; reltol & dtmax unchanged` locks this behavior so a future refactor cannot regress to a destructive write.

## UX Gap Surfaced

The form is fire-and-forget per field — there is no Save button, and no visible signal *inside the Project tab body itself* that a commit just happened or that Ctrl+Z is now armed. UI-SPEC accepts this (per §"Save behavior — Form-level — values are written to modelOptions store slice on field blur"); the undo affordance lives in the toolbar (already wired by 62-02). If user testing flags the "did my blur actually save?" question, candidates for a follow-up plan:
- Toast on commit ("Project options saved.") — heavyweight for a form.
- Subtle dirty-dot near the field label until the blur lands — lightweight.
- Title-bar `*` suffix when `isDirty` (probably already present via 62-02's `isDirty` plumbing — out of scope here).

This is **not** flagged as a deviation; it is documented per the plan's `<output>` request.

## Deviations from Plan

None. The plan's `<read_first>` listed `NumericField` and `InstanceNameField`; reading them revealed their existing APIs don't match the plan's suggested signatures, and the plan itself explicitly granted executor discretion on field primitive choice (§"Existing field primitives" — "executor picks"). The inline-primitive route is the chosen taste.

## Verification

- `cd gui && npx tsc --noEmit` scoped to `src/components/project/**` and `src/App.tsx`: 0 errors (pre-existing baseline errors in `StreamNode.tsx`, `ToolboxPanel.test.tsx`, `validation.test.ts` are unrelated to this plan — file paths confirm no overlap with files modified here).
- `cd gui && npx vitest run src/components/project/`: **17 passed, 0 failed.**

## Commits

| Hash | Subject |
|------|---------|
| `e192de2` | feat(62-07): add ModelOptionsPanel as Project tab body (D-04, CD-04) |
| `dbd3d94` | test(62-07): ModelOptionsPanel render + on-blur commit + solver field set |

## Requirements Addressed

- **D-04** — Project tab body IS the Model Options form (no inner selection step). The right Properties panel still shows its no-selection state when Project is active; that wiring lives in 62-09 (router) per the plan's `<objective>` note.
- **CD-04** — Solver defaults expose exactly `{abstol, reltol, dtmax}`. Negative test coverage locks the field set against scope creep.

## Self-Check: PASSED

- `gui/src/components/project/ModelOptionsPanel.tsx` exists.
- `gui/src/components/project/__tests__/ModelOptionsPanel.test.tsx` exists.
- `gui/src/App.tsx` imports `ModelOptionsPanel` and mounts it under `<TabsContent value="Project">`.
- Commits `e192de2` and `dbd3d94` present in `git log`.
- 17 vitest cases green; no pre-existing test regressions touched by these changes.
