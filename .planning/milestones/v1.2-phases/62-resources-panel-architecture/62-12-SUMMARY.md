---
phase: 62
plan: 12
subsystem: gui
tags: [gui, picker, layout, overflow, gap-closure]
gap_closure: true
gap_source: 62-VERIFICATION.md
gap_step: 5
root_plan: 62-08
requires: [62-08]
provides:
  - "ResourceReferencePicker row layout that survives the 320px sidebar default and the 200px min without clipping `+ New…` or `Edit…`"
affects:
  - "every parameter form rendering a Resource-FK picker (Channel.geometry_ref, *.power_shape_ref)"
tech_stack:
  added: []
  patterns:
    - "flex-wrap + basis-full sm:basis-0 + shrink-0 — narrow-row two-row wrap discipline"
key_files:
  created: []
  modified:
    - gui/src/components/sidebar/ResourceReferencePicker.tsx
    - gui/src/components/sidebar/__tests__/ResourceReferencePicker.test.tsx
decisions:
  - "Two-row wrap-when-narrow via flex-wrap + basis-full sm:basis-0; rejected icon-collapse (would invalidate verbatim copy assertions for `+ New…` / `Edit…`) and rejected bumping sidebar default width (preempts deferred Phase 72 panel-resize-bounds work)."
  - "happy-dom does not implement real CSS flex layout, so the new vitest cases assert className discipline (`flex-wrap`, `shrink-0`, `min-w-0` + `flex-1`/`basis`) + `offsetParent` presence rather than runtime-measured non-clipping. Visual verification stays a human-verify Step 5 re-run."
metrics:
  duration_min: 7
  completed_date: "2026-05-13"
  tests_added: 3
  tests_total: 14
---

# Phase 62 Plan 12: ResourceReferencePicker narrow-row wrap fix Summary

Close VERIFICATION.md Critical Gap #1 — at the App.tsx sidebar default of
320px (≈280-300px inner) and at the 200px min, the picker row
`[Select flex-1][+ New…][Edit…]` overflowed and clipped the rightmost
button, removing the user's in-form `+ New…` entry point for creating a
Geometry or Power Shape resource.

## What changed

`gui/src/components/sidebar/ResourceReferencePicker.tsx` (line-level diff):

1. Outer container `className`:
   - Before: `"flex items-center gap-[8px]"`
   - After:  `"flex flex-wrap items-center gap-[8px]"`
2. Select wrapper `<div>` `className`:
   - Before: `"flex-1 min-w-0"`
   - After:  `"flex-1 min-w-0 basis-full sm:basis-0"`
   At narrow widths the Select claims the full row (`basis-full` wins
   because the sidebar inner width is always below Tailwind's `sm`
   breakpoint of 640px in v1). At hypothetical wider widths the row
   collapses back to a single line via `sm:basis-0`. Future-proof only.
3. `+ New…` button trigger: added `className="shrink-0"`.
4. Disabled-Edit `<span>` wrapper: `"inline-flex"` → `"inline-flex shrink-0"`.
   The wrapper is the flex item (the disabled inner `<Button>` cannot
   receive focus and is not a direct flex child of the picker row).
5. Enabled-Edit `<Button>`: added `className="shrink-0"`.

No copy, variant, size, gap, or behavior changes — only layout discipline.

## Tests

`gui/src/components/sidebar/__tests__/ResourceReferencePicker.test.tsx`:
appended three vitest cases under a new describe block
`"62-12 layout: row contents survive a 280px container width"`:

- **Test A** — mounts the picker inside `<div style={{ width: 280 }}>`
  with one seeded geometry, asserts that `getByRole("combobox")`,
  `+ New…` button, and `Edit…` button each have a non-null
  `offsetParent`, and asserts the outer flex container has class
  matching `/flex-wrap/`.
- **Test B** — renders both branches (enabled with a value, then a
  re-render with `value={null}` for the disabled tooltip-wrapped
  branch) and asserts `+ New…`, enabled `Edit…`, and the
  `[data-slot='tooltip-trigger']` `<span>` each have className matching
  `/(shrink-0|flex-shrink-0)/`.
- **Test C** — asserts the Select trigger's nearest `<div>` parent has
  className matching both `/min-w-0/` and `/(flex-1|basis)/`.

happy-dom does not implement true CSS flex layout, so we cannot strictly
verify "no horizontal clipping" via runtime `getBoundingClientRect`
measurement — the className discipline plus `offsetParent` presence is
the testable contract. Visual verification is the Step 5 human-verify
re-run.

## Verification

| Gate | Command | Result |
| ---- | ------- | ------ |
| Vitest scoped to picker | `cd gui && npx vitest run src/components/sidebar/__tests__/ResourceReferencePicker.test.tsx` | **14/14 passed** (11 baseline + 3 new) |
| Source class discipline — flex-wrap | `grep -v '^//' gui/src/components/sidebar/ResourceReferencePicker.tsx \| grep -c "flex-wrap"` | 2 (≥1) |
| Source class discipline — shrink-0 | `grep -v '^//' gui/src/components/sidebar/ResourceReferencePicker.tsx \| grep -c "shrink-0"` | 5 (≥3) |
| Source class discipline — basis-full | `grep -v '^//' gui/src/components/sidebar/ResourceReferencePicker.tsx \| grep -c "basis-full"` | 2 (≥1) |
| Test class assertions — flex-wrap | `grep -c "flex-wrap" .../ResourceReferencePicker.test.tsx` | 4 (≥1) |
| Test class assertions — shrink-0 | `grep -cE "shrink-0\|flex-shrink-0" .../ResourceReferencePicker.test.tsx` | 6 (≥1) |
| Type check | `cd gui && npx tsc --noEmit 2>&1 \| grep -c "error TS"` | 8 (unchanged from baseline; 0 new) |

## Baseline drift note

The PLAN's `<acceptance_criteria>` claims a tsc baseline of 6 errors.
Measured baseline at HEAD before any change in this plan was 8 errors —
all in unrelated files (`StreamNode.tsx`, `ToolboxPanel.test.tsx`,
`SidebarRouter.test.tsx`, `validation.test.ts`). None in
`ResourceReferencePicker.*`. The plan's intent is "same or fewer than
baseline" — that invariant holds (8 → 8). No new TS errors introduced.
Treat the "6" in the plan as a stale estimate, not a regression.

## Deviations from Plan

None. The action steps in `<action>` were applied verbatim — `flex-wrap`
on the outer, `basis-full sm:basis-0` added to the Select wrapper,
`shrink-0` on `+ New…` and both Edit branches (the disabled `<span>`
wrapper and the enabled `<Button>`).

One Test A nuance worth noting: the plan suggested `useStore.setState`
to seed a single geometry. I used `useStore.getState().addGeometry(...)`
(the store's own action) instead, matching the existing
`D-18 / INV-17` test's seeding pattern. This keeps validation/dirty-flag
side-effects consistent with the production store contract and avoids
hand-rolling a `Geometry` object literal that would drift if the store
schema changes. Effect on the test contract: none — the Select gets a
real selectable entry either way.

## Chosen layout strategy

Two-row wrap-when-narrow via `flex flex-wrap` + Select wrapper
`basis-full sm:basis-0` + `shrink-0` on both side buttons.

Rejected `<chosen_strategy>` alternatives:

- **Icon-collapse (VERIFICATION.md Option b)** — would replace the
  verbatim `+ New…` / `Edit…` text labels with icons, invalidating
  existing test assertions on those strings and forcing UI-SPEC copy
  changes that belong to a separate plan (62-15 copy-pass scope).
- **Bump sidebar default width (VERIFICATION.md Option c)** — would
  preempt the deferred Phase 72 panel-resize-overflow-bounds work
  (`.planning/todos/pending/panel-resize-overflow-bounds.md`).

## Authentication gates

None encountered.

## Self-Check: PASSED

- `gui/src/components/sidebar/ResourceReferencePicker.tsx` — FOUND, contains `flex-wrap` × 2, `shrink-0` × 5, `basis-full` × 2 (code lines)
- `gui/src/components/sidebar/__tests__/ResourceReferencePicker.test.tsx` — FOUND, three new describe-level cases under "62-12 layout" present
- Commit `affdd1e` — FOUND in `git log --all` on `worktree-agent-aa888c444dd6fb237` branch
- Vitest scoped run — 14 passed, 0 failed
- No file deletions on commit
- No new tsc errors over baseline (8 → 8)
