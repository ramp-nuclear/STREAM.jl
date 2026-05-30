---
phase: 62
plan: 02
subsystem: gui-state
tags:
  - gui
  - zustand
  - state
  - foundation
  - resources
  - model-options
requires:
  - "62-01 (UI-SPEC contract — verbatim copy strings, sentinel name)"
provides:
  - "Resources slice (geometries, powerShapes, fluids) UUID-keyed records"
  - "ModelOptions slice (D-04, CD-04 solver fields)"
  - "activeLeftTab state (D-08 default 'Components')"
  - "Selection-kind discriminator (D-05 mutual exclusivity)"
  - "SENTINEL_UNSET_POWER_SHAPE exported const (D-26)"
  - "SENTINEL_LIGHT_WATER_FLUID exported const"
  - "nextResourceName() lowest-free-positive-integer helper (D-19)"
  - "Extended CanvasSnapshot (resources + modelOptions undoable)"
affects:
  - "All Wave 2 UI plans (62-05 Resources tab, 62-06 Resource editor, 62-08 ReferencePicker, 62-04 .scp serialization)"
tech-stack:
  added: []
  patterns:
    - "Module-level resource-name helpers (parallel to instance counters)"
    - "Validation-then-snapshot-then-mutate discipline (RESEARCH Pitfall 2)"
    - "Sentinel UUIDs as deterministic constants (not runtime-minted)"
key-files:
  created:
    - "gui/src/store/__tests__/resources.slice.test.ts"
    - "gui/src/store/__tests__/modelOptions.test.ts"
    - "gui/src/store/__tests__/activeLeftTab.test.ts"
    - "gui/src/store/__tests__/selection.test.ts"
  modified:
    - "gui/src/store/useStore.ts"
decisions:
  - "Sentinel rename/remove: NO-OP (not throw) — UI never surfaces the affordance; throwing would force every caller to wrap. Rationale: defensive guard for a path users cannot trigger."
  - "Sentinel duplicate: THROW — duplicating a placeholder is semantically nonsense; throwing surfaces a clear error if a higher layer ever wires this."
  - "Fluids placeholder UUID: deterministic constant 00000000-0000-0000-0000-000000000001 (not runtime-minted). Rationale: .scp files written on one machine that reference the placeholder fluid by UUID must remain readable on another machine / fresh process."
  - "selectionKind synced as explicit state inside selectNode/selectResource/clearSelection (RESEARCH Pattern 4) — zustand selectors do not auto-recompute on dependent state changes."
  - "Validation runs BEFORE _pushSnapshot — rejected adds/renames do not consume an undo slot."
  - "renameResource on the same name (uuid === ignoreUuid) is a no-op-pass — the uniqueness check excludes the record being renamed, matching the common UX of 'save without changes'."
metrics:
  duration: "~25 min (interactive)"
  completed: "2026-05-13"
  tasks: 3
  commits: 3
  tests-added: 71
  tests-total-store: 107
---

# Phase 62 Plan 02: Resources / ModelOptions / Tabs / Selection — Foundation Summary

State-layer foundation Wave 2 rides on: four new zustand slices in `useStore.ts`
plus the snapshot/undo/redo extension that makes Resource and ModelOptions
mutations undoable. No UI surfaces in this plan — pure state expansion.

## What Shipped

### Module-level constants

- `SENTINEL_UNSET_POWER_SHAPE = "00000000-0000-0000-0000-000000000000"` (exported)
- `SENTINEL_LIGHT_WATER_FLUID = "00000000-0000-0000-0000-000000000001"` (exported)
- `SENTINEL_POWER_SHAPE_NAME = "(leave unset — fill in code)"` (UI-SPEC verbatim)
- `DEFAULT_FLUID`, `DEFAULT_G`, `DEFAULT_SOLVER` initial values
- `JULIA_IDENT_RE` for identifier validation

### New types

```ts
interface GeometryResource   { uuid; name; kind: "rectangular"|"circular"; params: {L; W?; H?; D?} }
interface PowerShapeResource { uuid; name; kind: "uniform"|"z_cosine"|"file_loaded"|"unset"; params: {amplitude?; path?} }
interface FluidResource      { uuid; name }
interface ResourcesSliceState   { geometries; powerShapes; fluids }
interface ModelOptionsSliceState { name; description; default_fluid; g_default; solver: {abstol, reltol, dtmax} }
type ActiveLeftTab     = "Components" | "Resources" | "Project"
type SelectionKind     = "none" | "component" | "resource" | "project"
type SelectedResourceKind = "geometry" | "powerShape" | "fluid" | null
```

`CanvasSnapshot` extended with `resources` and `modelOptions`. `activeLeftTab`
intentionally NOT in snapshot (UI state, mirrors `selectedNodeId` / `activeLayer`).

### New actions

- Resources: `addGeometry`, `addPowerShape`, `renameResource`, `updateResource`,
  `removeResource`, `duplicateResource` — each pushes a snapshot BEFORE
  mutation (RESEARCH Pitfall 2 mitigated structurally), sets `isDirty: true`
- ModelOptions: `setModelOptions` (shallow merge + snapshot + dirty)
- Tabs: `setActiveLeftTab` (sets `isDirty` per D-29 layout-block resolution;
  does NOT push a snapshot)
- Selection: `selectResource`, `clearSelection`; `selectNode` MODIFIED to clear
  `selectedResourceId` per D-05 mutual exclusivity
- Helpers: `nextResourceName(kind, existingNames)` — lowest-free positive
  integer per D-19; `validateResourceName(kind, name, bucket, ignoreUuid?)`
  for Julia-identifier + per-kind uniqueness checks

### Initial state baked

- Sentinel PowerShape present in `state.resources.powerShapes` from boot
- Single non-editable `light_water` fluid present in `state.resources.fluids`
- `modelOptions` populated with D-04 / CD-04 defaults
- `activeLeftTab: "Components"`
- Selection all-null with `selectionKind: "none"`

## Decisions Made

### Sentinel rename / remove: NO-OP (not throw)

`renameResource("powerShape", SENTINEL_UNSET_POWER_SHAPE, ...)` and
`removeResource("powerShape", SENTINEL_UNSET_POWER_SHAPE)` are silent no-ops.

**Rationale:** the UI never surfaces a rename or delete affordance on the
sentinel row (it lives only in the picker dropdown, not in the Resources
tab Power Shapes group). Reaching these branches is defensive guard for
a path users cannot trigger. Throwing would force every caller to wrap.

### Sentinel duplicate: THROW

`duplicateResource("powerShape", SENTINEL_UNSET_POWER_SHAPE)` throws
`"The unset Power Shape sentinel cannot be duplicated."`

**Rationale:** duplicating a placeholder is semantically nonsense (the
new record would inherit `kind: "unset"`, which `addPowerShape` already
rejects). Throwing surfaces a clear error if a higher layer ever wires
this path.

### Fluids placeholder UUID: deterministic constant

`SENTINEL_LIGHT_WATER_FLUID = "00000000-0000-0000-0000-000000000001"`
(not runtime-minted via `crypto.randomUUID()`).

**Rationale:** `.scp` files written on one machine that reference the
placeholder fluid by UUID must remain readable on another machine or
fresh process. A runtime-minted UUID would drift across processes.
Phase 62 ships fluids as a single non-editable placeholder per D-03 +
UI-SPEC; the full multi-fluid plan lands in v0.6+.

### selectionKind synced as explicit state

`selectionKind` is maintained as explicit state inside `selectNode`,
`selectResource`, `clearSelection`, and `removeNode`, rather than as a
derived selector. Per RESEARCH Pattern 4 + zustand semantics: selectors
do not auto-recompute on dependent state changes; explicit sync is the
recommended path.

### Validation runs BEFORE `_pushSnapshot`

If `addGeometry({ name: "3bad" })` throws (digit-prefix), no snapshot is
pushed — rejected attempts do not consume an undo slot. This matches
typical undo-stack discipline (only committed mutations get an undo
entry).

### `renameResource` to the same name is a no-op-pass

The uniqueness check excludes the record being renamed via the
`ignoreUuid` parameter. Renaming `g_a` → `g_a` does not throw. This
matches "save without changes" UX.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 — missing critical functionality] Added `loadProjectFromPath` selection reset**

- **Found during:** Task 1 (writing the selection state)
- **Issue:** `loadProjectFromPath` did not reset `selectedResourceId`,
  `selectedResourceKind`, or `selectionKind` after load, which would
  violate D-05 mutual exclusivity if a project was loaded while a
  resource was selected
- **Fix:** Added three lines to the `set({...})` call in
  `loadProjectFromPath` (Phase 62-04 will own resource deserialization
  itself; this is just the in-memory selection reset)
- **Files modified:** `gui/src/store/useStore.ts`
- **Commit:** `150b624` (Task 1)

**2. [Rule 2 — missing critical functionality] Added `newProject` resource/options reset**

- **Found during:** Task 1
- **Issue:** `newProject` previously cleared canvas state but not the new
  Phase 62 slices; an old project's `modelOptions.name` or `resources`
  would leak into a fresh document
- **Fix:** Extended the `set({...})` in `newProject` to reset all Phase
  62 slices to initial values (including re-injecting the sentinel
  PowerShape and the placeholder fluid)
- **Files modified:** `gui/src/store/useStore.ts`
- **Commit:** `150b624` (Task 1)

**3. [Rule 2 — missing critical functionality] Added `removeNode` selectionKind sync**

- **Found during:** Task 1 (selection invariant audit)
- **Issue:** `removeNode` cleared `selectedNodeId` but did not recompute
  `selectionKind`. If a node was selected and then removed,
  `selectionKind` would stay `"component"` even though `selectedNodeId`
  became `null`, violating the discriminator's invariant
- **Fix:** Recompute `selectionKind` via `deriveSelectionKind(...)` in
  the `removeNode` `set({...})` call
- **Files modified:** `gui/src/store/useStore.ts`
- **Commit:** `150b624` (Task 1)

## TypeScript Friction

None encountered. The plan flagged "zustand generic narrowing on the
snapshot extension" as a possible friction; in practice the existing
`create<AppState>()` pattern absorbed the new fields without any new
type-error noise. The 7-error baseline (Phase 61 deferred items) is
unchanged and `useStore.ts` itself remains error-free.

## Verification Evidence

```
$ cd gui && npx tsc --noEmit | grep -cE 'error TS[0-9]+:'
7                                  # baseline preserved
$ grep -cE 'src/store/useStore\.ts' tsc.log
0                                  # no errors in useStore.ts

$ npx vitest run src/store/__tests__/
Test Files  5 passed (5)
Tests       107 passed (107)

$ grep -c SENTINEL_UNSET_POWER_SHAPE gui/src/store/useStore.ts
10                                 # >= 3 (acceptance floor)
$ grep -cE '_pushSnapshot\(\)' gui/src/store/useStore.ts
17                                 # baseline 11 + 6 new = +6 (>= +5)
$ grep -cE 'INV-0[1-5]|INV-08' gui/src/store/__tests__/resources.slice.test.ts
20                                 # >= 5 (acceptance floor)
$ grep -cE 'INV-09|INV-17' gui/src/store/__tests__/selection.test.ts
8                                  # >= 2 (acceptance floor)
$ grep -cE 'abstol|reltol|dtmax' gui/src/store/__tests__/modelOptions.test.ts
17                                 # >= 3 (acceptance floor)
$ grep -cE 'import.*from "(uuid|nanoid)"' gui/src/store/useStore.ts
0                                  # CD-03 — crypto.randomUUID() only
```

## Commits

| Task | Hash      | Message                                                                |
| ---- | --------- | ---------------------------------------------------------------------- |
| 1    | `150b624` | feat(62-02): add Resources/ModelOptions/Tabs/Selection slices to useStore |
| 2    | `df85bd4` | test(62-02): add resources.slice tests — CRUD + uniqueness + sentinel + undo |
| 3    | `5e0cb68` | test(62-02): add ModelOptions/activeLeftTab/selection tests            |

## Requirements Addressed

- D-04 (Model Options state shape)
- D-05 (selection-kind mutual exclusivity)
- D-08 (activeLeftTab default + state)
- D-09 (FK shape — components reference resources by UUID via *_ref)
- D-10 (Resources record shape + per-kind name uniqueness)
- D-11 (UUID strategy via `crypto.randomUUID()`; UUIDs never reused)
- D-12 (rename propagation by construction — record mutation in place)
- D-13 (copy-paste preserves FK by NOT cloning resource records)
- D-26 (sentinel UUID + name baked into initial state; uneditable)
- CD-03 (UUID lib choice: `crypto.randomUUID()`, no `uuid`/`nanoid` dep)
- CD-04 (solver-defaults field set: `{abstol, reltol, dtmax}`)

## Known Stubs

None. This plan ships state primitives only; the surfaces (Resources tab,
popover, picker, Edit… jump) are owned by Wave 2 plans. Fluids ship as a
single non-editable placeholder, but that is the agreed Phase 62 scope per
D-03 + UI-SPEC, NOT a stub — full multi-fluid lands in v0.6+ per the
agreed long-term design (memory `project_fluids_longterm`).

## Self-Check: PASSED

- gui/src/store/useStore.ts — FOUND (1182 lines after extension; was 640)
- gui/src/store/__tests__/resources.slice.test.ts — FOUND
- gui/src/store/__tests__/modelOptions.test.ts — FOUND
- gui/src/store/__tests__/activeLeftTab.test.ts — FOUND
- gui/src/store/__tests__/selection.test.ts — FOUND
- Commit 150b624 — FOUND in `git log`
- Commit df85bd4 — FOUND in `git log`
- Commit 5e0cb68 — FOUND in `git log`
- All 107 store tests pass
- TypeScript at 7-error documented baseline (no new errors)
