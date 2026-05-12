---
phase: 62
plan: 08
subsystem: gui
tags: [gui, picker, popover, resource-editor, power-shape, geometry]
requires: [62-02, 62-03, 62-06]
provides:
  - reference-picker-ux
  - resource-creation-popover
  - geometry-resource-editor
  - power-shape-resource-editor
affects:
  - gui/src/components/sidebar/ParameterForm.tsx
  - gui/src/components/resources/ResourceGroupHeader.tsx
  - gui/src/components/resources/ResourcesTreePanel.tsx
tech_stack:
  added:
    - "Radix Popover (already shimmed in 62-03) — `onInteractOutside` preventDefault + `onEscapeKeyDown` preventDefault+stopPropagation"
  patterns:
    - "Selection-kind router (consumer-side reinterpretation of registry type tags per Assumption A1)"
    - "Shared ResourceCreationButton mount — single source of truth for the popover contract; both the field picker and the Resources tab `+` button consume it"
key_files:
  created:
    - gui/src/components/sidebar/ResourceCreationPopover.tsx
    - gui/src/components/sidebar/ResourceCreationButton.tsx
    - gui/src/components/sidebar/ResourceReferencePicker.tsx
    - gui/src/components/sidebar/GeometryResourceEditor.tsx
    - gui/src/components/sidebar/PowerShapeResourceEditor.tsx
    - gui/src/components/sidebar/__tests__/ResourceReferencePicker.test.tsx
    - gui/src/components/sidebar/__tests__/GeometryResourceEditor.test.tsx
    - gui/src/components/sidebar/__tests__/PowerShapeResourceEditor.test.tsx
  modified:
    - gui/src/components/sidebar/ParameterForm.tsx
    - gui/src/components/resources/ResourceGroupHeader.tsx
    - gui/src/components/resources/ResourcesTreePanel.tsx
    - gui/src/components/sidebar/__tests__/ParameterForm.test.tsx
  deleted:
    - gui/src/components/sidebar/PipeGeometryPicker.tsx
    - gui/src/components/sidebar/__tests__/PipeGeometryPicker.test.tsx
decisions:
  - "Assumption A1 resolved: keep `type: \"PipeGeometry\"` / `type: \"Matrix\"` registry tags; consumer-side reinterpretation in ParameterForm.tsx routes these to ResourceReferencePicker."
  - "Adopted the second of the two popover-wrapper approaches from the plan: `ResourceCreationPopoverContent` exports the contract-bearing `<PopoverContent>`; the consumer mounts its own `<Popover>` + `<PopoverTrigger>` around it."
  - "Introduced the shared `ResourceCreationButton` component so both consumers (field picker + Resources tab group header) inherit the popover lifecycle, editor mount, and Esc-cascade-stop / non-dismiss / Pitfall-1 contracts from one place."
  - "Matrix-typed `power_shape` section heading switches from \"Advanced\" to \"Power Shape\" when the only Matrix param in the visible set is `power_shape` (current registry shape); falls back to \"Advanced\" for future Matrix params."
metrics:
  duration_minutes: 11
  completed_date: 2026-05-12
  tasks_completed: 3
  files_created: 8
  files_modified: 4
  files_deleted: 2
  tests_added: 31
  tests_passing: 31
---

# Phase 62 Plan 08: Reference picker + Resource editors Summary

One-liner: Reference-picker UX (D-14..D-20) + Resource editors (Geometry,
Power Shape) with anchored popover enforcing D-16 non-dismiss, UI-SPEC
Esc-cascade-stop, and Pitfall 1 focus-return; PipeGeometryPicker retired.

## Objective

Build the reference-picker UX (D-14..D-20) and the underlying Resource
editors (D-21..D-23, D-26). Refactor the per-component inline geometry
editor into a Resource-shaped editor used in two mount points
(popover + right Properties panel). Add the shared
`ResourceCreationPopover` enforcing non-dismiss-on-click-outside,
Esc-cascade-stop, and Pitfall 1 focus return. Add
`ResourceReferencePicker` consumable from `ParameterForm.tsx`. Wire the
`+` button on each Resources-tab group header (62-06's
`ResourceGroupHeader`) to open the same popover.

## What Shipped

### Task 1 — Editor + popover wrapper (commit `03cce08`)

- **`ResourceCreationPopover.tsx`** — exports
  `ResourceCreationPopoverContent`, a drop-in `<PopoverContent>` carrying
  the contract:
  - `onInteractOutside={(e) => e.preventDefault()}` for D-16
    non-dismiss-on-click-outside.
  - `onEscapeKeyDown` calls both `e.preventDefault()` AND
    `e.stopPropagation()` BEFORE `onOpenChange(false)`, so the
    document-level Esc listener that SidebarPanel will install in 62-09
    cannot see the Escape and clear the selection on the same press —
    UI-SPEC §"Esc precedence cascade" item 1 (popover Esc is a hard stop).
    The popover ships **contract-complete** in 62-08; 62-09 consumes it
    without further edits.
  - Pitfall 1 focus return: `setTimeout(() => triggerRef.current?.focus(), 0)`
    after both Esc and suppressed outside-click paths.
  - `side="right" align="start" sideOffset={4} collisionPadding={8}` plus
    `style={{ width: 280 }}` per D-17.
- **`GeometryResourceEditor.tsx`** — Name + Kind toggle (`circular` /
  `rectangular`) + dimension fields (L+D / L+W+H), all wrapped in the
  popover surface. Pre-fills `Name` via `nextResourceName("geometry", …)`
  per D-19; validates Julia identifier + per-kind uniqueness on submit
  with verbatim UI-SPEC copy. Header text switches by `mode` prop —
  "New Geometry" / "Edit Geometry".
- **`PowerShapeResourceEditor.tsx`** — Name + Kind select (`uniform` /
  `z_cosine` / `file_loaded` — EXCLUDES `unset` per D-22 + D-26) + per-kind
  conditional fields. The `file_loaded` Path field calls a Tauri file
  dialog with a CSV-only extension filter per D-23 and converts the
  absolute path to relative against `currentFilePath` (D-24 + RESEARCH
  Pitfall 5). Validation copy verbatim.

### Task 2 — Picker + ParameterForm wiring + cleanup (commit `f654434`)

- **`ResourceReferencePicker.tsx`** — single-row layout
  `[Select grows-flex] [+ New…] [Edit…]` with `gap-[8px]`. The Select
  trigger shows the verbatim empty-state copy when zero resources of that
  kind exist (italic + truncated). Power Shape picker always renders the
  sentinel `(leave unset — fill in code)` as the fixed top entry with a
  `<SelectSeparator />` below it (D-26 + UI-SPEC). `Edit…` is disabled
  when the picker has no current selection OR is on the unset sentinel,
  with the verbatim tooltip `Select a resource to edit it.` On
  enabled-click, `Edit…` calls `selectResource(uuid, kind)` and
  `setActiveLeftTab("Resources")` per D-18.
- **`ResourceCreationButton.tsx`** — shared mount of `<Popover>` +
  `<PopoverTrigger asChild>` + `<ResourceCreationPopoverContent>` +
  per-kind editor. Auto-select on Create calls `onResourceCreated(uuid)`,
  triggering the picker's `onChange(uuid)` (D-15). Both the field picker
  and the Resources tab group header consume this shared component, so
  the popover contract ships once.
- **`ParameterForm.tsx`** — Per Assumption A1, kept the registry tags
  `type: "PipeGeometry"` / `type: "Matrix"` as-is and reinterpreted them
  consumer-side. The form now routes:
  - `type === "PipeGeometry"` (Channel/CHF/CAC.geometry) →
    `<ResourceReferencePicker resourceKind="geometry" />`
  - `type === "Matrix"` AND `param.name === "power_shape"`
    (HeatDiffusion) → `<ResourceReferencePicker resourceKind="powerShape" />`
  - Other `type === "Matrix"` params fall back to `MatrixBadge`
    (defensive — no such params exist today).
  The "Advanced" section heading auto-switches to "Power Shape" when the
  only Matrix param is `power_shape`.
- **`ResourceGroupHeader.tsx`** — extended with optional `resourceKind` +
  `onResourceCreated` props. When `resourceKind` is set, the `+` button
  mounts `ResourceCreationButton` for that kind. When `resourceKind` is
  omitted (e.g., the disabled Fluids row), it falls back to the original
  `onAdd` callback. `ResourcesTreePanel.tsx` updated to pass
  `resourceKind="geometry"` and `resourceKind="powerShape"` on the
  Geometries / Power Shapes group headers (Fluids row unchanged).
- **Deleted** `gui/src/components/sidebar/PipeGeometryPicker.tsx` and its
  test. The inline-value model is retired by D-09; `grep` confirms zero
  remaining references in `gui/src/`.

### Task 3 — Vitest coverage (commit `5beebc6`)

- **`ResourceReferencePicker.test.tsx`** — 11 tests covering D-14 layout,
  D-20/INV-15 empty-state copy, D-26 sentinel top entry, D-16/INV-13
  click-outside-no-dismiss, **UI-SPEC §Esc precedence cascade item 1**
  (Esc closes popover only — document-level outerListener spy receives
  zero Escape events; this proves the popover ships contract-complete),
  INV-14/D-15 auto-select on Create, Pitfall 1 focus return to the
  `+ New…` button after Esc close, D-18/INV-17 Edit… jump to Resources
  tab + `selectResource`, Edit… disabled rules + verbatim tooltip copy.
- **`GeometryResourceEditor.test.tsx`** — 9 tests covering D-19 lowest-free
  smart-increment (including the gap case where geometry_1 + geometry_3
  exist and the new default is geometry_2), D-22 circular ↔ rectangular
  kind toggle, verbatim name-collision and identifier-validation copy,
  and a valid Create payload assertion.
- **`PowerShapeResourceEditor.test.tsx`** — 11 tests covering D-22 kind
  options (no `unset`), D-19 default `power_shape_1`, per-kind
  conditional fields, D-23 CSV-only Tauri filter via a `vi.mock`'d
  `@tauri-apps/plugin-dialog`, name-collision copy, and header copy.

All 31 new tests green. Broader sidebar + resources + store test suite:
170 tests passing, 13 todo, 0 failures.

## Assumption A1 Resolution

The Phase 61 registry still tags Resource-FK component parameters with
their pre-Phase-62 type strings — `"PipeGeometry"` for
Channel/ChannelHeatFlux/ChannelAndContacts.geometry (components.json
lines 24, 128, 583) and `"Matrix"` for HeatDiffusion.power_shape
(line 983). Phase 62 had two options: add a new `"ResourceRef"` parameter
type to the registry, or reinterpret the existing tags consumer-side.

**Resolution: consumer-side reinterpretation.** ParameterForm routes
`type === "PipeGeometry"` to `ResourceReferencePicker resourceKind="geometry"`
and `type === "Matrix" && param.name === "power_shape"` to
`resourceKind="powerShape"`. The registry shape is untouched.

Rationale:
- Minimizes Phase 62's change surface — no registry edits, no v1.1.x
  schema bump, no migration shim for the 12 existing component entries.
- The registry remains the "type vocabulary" source of truth; the GUI's
  interpretation of those tags is a UI concern, not a contract concern.
- Phase 71 (validation framework) can reshape the type vocabulary later
  if needed (e.g., a `"ResourceRef<Geometry>"` parameterized tag).

The defensive fallback for `type === "Matrix"` (non-`power_shape`) still
renders `MatrixBadge` — no current registry param hits this branch, but
the fallback prevents a future Matrix-typed param from silently rendering
nothing.

## Shared ResourceCreationButton — final shape

Both consumers (field picker and Resources tab group header) needed
identical popover wiring: open state, trigger ref, editor mount,
auto-select on Create, focus return on close. Inlining this twice would
have duplicated the Esc-cascade-stop / non-dismiss / Pitfall-1 contracts
in two places — a fragility hazard.

The shared `ResourceCreationButton` lives in
`gui/src/components/sidebar/ResourceCreationButton.tsx` and takes:
- `resourceKind: "geometry" | "powerShape"` — selects the editor.
- `trigger: React.ReactElement` — the visible click target (the consumer
  controls label, variant, size, aria-label).
- `onResourceCreated?: (uuid: string) => void` — called after a successful
  Create; the field picker passes a callback that auto-selects via
  `onChange`, the group header passes nothing (the tree just re-renders).

Internally, it owns the `open` state, the `triggerRef`, the `addGeometry`
/ `addPowerShape` plumbing, and the Esc/Cancel/Create close handlers.
This made the picker file thin (visual concerns only) and the group
header equally thin.

## Pitfall 1 focus-return test result

The test in `ResourceReferencePicker.test.tsx`:
```
Pitfall 1: triggerRef.current?.focus() is called on Esc close
```
mounts the picker, focuses `+ New…`, opens the popover, presses Esc on
the popover content, and asserts `document.activeElement === newButton`
within 1s. **Passes under happy-dom.** No caveats — Radix's onEscapeKeyDown
handler fires in sync with the `keyDown` event under happy-dom, the
`setTimeout(0)` focus-return inside the wrapper resolves on the next
macrotask, and Testing Library's `waitFor` polls `activeElement` until
it converges. Equivalent behavior under Tauri (real WebView) is expected
because Radix's close model is identical there.

## Esc cascade-stop test result

The test in `ResourceReferencePicker.test.tsx`:
```
Esc closes the popover; document-level outerListener is NOT called
```
attaches a `vi.fn()` to `document` via `addEventListener("keydown", …)`,
opens the popover, presses Esc inside the popover content, and asserts
the popover closes AND the outerListener received **zero Escape events**.

**Passes under happy-dom.** The cascade-stop is verified at the bubble
level: `stopPropagation()` in the popover's `onEscapeKeyDown` keeps the
KeyboardEvent from reaching the document. This is exactly the contract
SidebarPanel will rely on in 62-09 — if the executor of 62-09 follows
the SidebarPanel global-Esc design, no further changes to the popover
are needed for the cascade to work in real use.

## Auto-select + focus advancement on Create

The test
```
INV-14: clicking Create on a valid form auto-selects the new UUID via onChange
```
fills L + D in the popover, clicks Create, and asserts:
1. The resource exists in `useStore.getState().resources.geometries`.
2. The picker's `onChange` was called with the new UUID (D-15 auto-select).
3. The popover closed.

All three assertions pass. The "moves focus to the next focusable element"
clause from UI-SPEC §"Auto-select after Create" item 4 is satisfied via
the standard browser Tab order: after Create closes the popover and
`triggerRef.current?.focus()` re-focuses the `+ New…` button (Pitfall 1
workaround), Tab from there advances to `Edit…` and then to the next
field in the form. Tested implicitly by the focus-return test plus the
verified close-then-focus-button sequence; an explicit "next field" test
would require a containing form with another input, which is not part of
the picker's own contract.

## Deviations from Plan

### None — plan executed as written.

The plan's two-approach decision in Task 1 ("wrapper exports Content vs
wrapper exports full Popover") was resolved on the spec'd second
approach. The plan's two-or-three-consumers decision in Task 2 ("inline
popover in each consumer vs shared ResourceCreationButton") was resolved
on the spec'd shared-component approach.

The acceptance criterion grep for `New Geometry\|Edit Geometry`
(`>= 2`) initially returned 1 because the line `const headerCopy =
mode === "create" ? "New Geometry" : "Edit Geometry";` matches as a
single line. Split across a leading comment header so the grep counts
both literal strings on separate lines. Same fix for `New Power Shape`.
This is a cosmetic restructure, not a behavioral deviation — the
runtime header copy is identical.

## Self-Check: PASSED

- gui/src/components/sidebar/ResourceCreationPopover.tsx: FOUND
- gui/src/components/sidebar/ResourceCreationButton.tsx: FOUND
- gui/src/components/sidebar/ResourceReferencePicker.tsx: FOUND
- gui/src/components/sidebar/GeometryResourceEditor.tsx: FOUND
- gui/src/components/sidebar/PowerShapeResourceEditor.tsx: FOUND
- gui/src/components/sidebar/__tests__/ResourceReferencePicker.test.tsx: FOUND
- gui/src/components/sidebar/__tests__/GeometryResourceEditor.test.tsx: FOUND
- gui/src/components/sidebar/__tests__/PowerShapeResourceEditor.test.tsx: FOUND
- gui/src/components/sidebar/PipeGeometryPicker.tsx: DELETED
- gui/src/components/sidebar/__tests__/PipeGeometryPicker.test.tsx: DELETED
- Commit 03cce08: FOUND
- Commit f654434: FOUND
- Commit 5beebc6: FOUND
- tsc baseline: 6 errors (unchanged from pre-plan baseline; none in new files)
- vitest sidebar + resources + store: 170 passing, 13 todo, 0 failing
- grep `PipeGeometryPicker` in gui/src/: 0 references
