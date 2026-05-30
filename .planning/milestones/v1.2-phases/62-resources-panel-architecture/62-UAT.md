---
status: complete
phase: 62-resources-panel-architecture
source: [62-12-SUMMARY.md, 62-13-SUMMARY.md, 62-14-SUMMARY.md, 62-15-SUMMARY.md]
started: 2026-05-13T12:00:00Z
updated: 2026-05-13T15:15:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Cold Start Smoke Test
expected: Kill any running dev server, cold-start `npm run dev`. Composer opens, tab strip + SOURCES header visible, no boot-time console errors.
result: pass

### 2. Reference Picker — `+ New…` no longer clipped at default sidebar width (Gap #1)
expected: Drop a Channel (or any component with a `geometry` field) on the canvas. Open the right sidebar Properties panel at its default width (320px). The geometry picker row shows the **Select dropdown** AND **+ New…** AND **Edit…** buttons all fully inside the panel — nothing is clipped or off-screen. At narrower widths the row wraps, but the `+ New…` button is never hidden.
result: pass
notes: |
  Originally failed (commit 6c3fe29 patched only one row inside the picker; user reported the whole Properties panel was clipped). Resolved across a multi-commit panel-chrome rework: 6c3fe29 (ScrollArea `[&>div]:!block` + min-w-0 cascade) and 6a595d7 (full VS Code-aligned chrome + density pass). User confirmed "Looks good" on 2026-05-13 after the icon-tab + tooltip-timing iteration.

### 3. Delete AlertDialog fires on a USED resource (Gap #2)
expected: In the Resources tab tree, create a geometry named `mtr_ch` (use `+ New` from a Channel's geometry picker so it ends up referenced). Then in the Resources tab right-click that geometry row → Delete. An AlertDialog appears with description matching `Delete geometry mtr_ch? Used by 1 component(s).` (lowercase `geometry`, the new `Used by` wording, no `It is used by`). The default focused button is Cancel.
result: pass

### 4. Delete AlertDialog Cancel + Delete-anyway behavior (Gap #2 cont)
expected: From test 3's dialog click Cancel → the resource remains in the tree and the canvas component still references it. Re-open the dialog (right-click → Delete again), click `Delete anyway` → resource is removed from the tree and the component's geometry field reverts to the sentinel `(leave unset — set in code)`.
result: pass

### 5. Save As default filename pulls from Model Options Name (Gap #3)
expected: Open the Project tab → Model Options form. Set the Name field to `phase62-smoke`. File → Save As. The OS save dialog pre-fills the filename as `phase62-smoke.scp` (not `project.scp`). Cancel the dialog. Clear the Name field to empty, try Save As again — dialog pre-fills `project.scp`.
result: pass

### 6. Professional copy spot-checks (Gap #4)
expected: Hover the disabled `Edit…` button when no resource is selected in a picker — tooltip reads `Pick a resource first.` (not `Select a resource to edit it.`). The sentinel option in the geometry/power-shape Select dropdown reads `(leave unset — set in code)` (not `fill in code`). If you can trigger a save error (e.g., point Save As at a read-only path), the error dialog reads `Save failed. <…>` (not `Couldn't save project`).
result: pass
notes: |
  First pass surfaced a related bug — the disabled-Edit logic did not account for dangling resource references, so after deleting a resource the Channel's Edit button stayed enabled and routed to a non-existent selection. Fixed in commit 6a60853 (isEditDisabled now also requires the UUID to resolve to a resource that exists in userResources). Also corrected the test wording: the `(leave unset — set in code)` sentinel only exists for Power Shape pickers (HeatDiffusion's power_shape), not Geometry — re-verified against a HeatDiffusion component.

### 7. Regression spot-checks against the 14 originally-passing steps
expected: Quick sweep — these all worked before the gap-closure plans and should still work: (a) Ctrl+1 / Ctrl+2 / Ctrl+3 switches Project / Resources / Components tabs; (b) `+ New geometry` creation auto-suggests `geometry_1` and auto-selects the new resource on Create; (c) Inline rename via double-click in the Resources tree still works; (d) Esc cascade-clears selection; (e) Round-trip: save a project, open another, reopen the first — canvas + Resources + Model Options + active tab restore correctly.
result: pass
notes: |
  User confirmed "other stuff is fine" — all five regression sub-checks (a-e) still work after the panel-chrome rework + density pass + icon-tab swap. The only adjustment surfaced was a polish ask on the active-tab highlight (originally bg-secondary tint, dropped in commit ed75ff3 to match the hover treatment — icon brighter, no bg).

### 8. Left panel overflow at narrow widths (surfaced during Test 1)
expected: Resizing the LEFT panel (the Resources / Project tab tree, not the right Properties panel) down to its minimum width keeps every button inside the panel — nothing escapes the panel bounds or overlaps the File / Code Preview buttons in the top bar.
result: pass
notes: |
  Originally failed (text-based tab strip overflowed at narrow widths). Resolved by the panel-chrome rework (6a595d7) plus the icon-tab swap (2f451a7) — three 32×32 icons total 112px and always fit within the 120px minimum panel width. The container also got `overflow-hidden` so any future intrinsic-width content gets clipped at the panel boundary instead of bleeding into the Toolbar.

## Summary

total: 8
passed: 8
issues: 0
pending: 0
skipped: 0

## Gaps

[both originally-logged gaps were closed during the panel-chrome rework; see Tests 2 and 8 notes]
