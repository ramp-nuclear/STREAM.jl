---
status: testing
phase: 62-resources-panel-architecture
source: [62-12-SUMMARY.md, 62-13-SUMMARY.md, 62-14-SUMMARY.md, 62-15-SUMMARY.md]
started: 2026-05-13T12:00:00Z
updated: 2026-05-13T12:05:00Z
---

## Current Test

number: 2
name: Reference Picker — `+ New…` no longer clipped at default sidebar width (Gap #1)
expected: |
  Drop a Channel (or any component with a `geometry` field) on the
  canvas. Open the right sidebar Properties panel at its default
  width (320px). The geometry picker row shows the Select dropdown
  AND `+ New…` AND `Edit…` buttons all fully inside the panel —
  nothing is clipped or off-screen. At narrower widths the row
  wraps, but the `+ New…` button is never hidden.
awaiting: user response

## Tests

### 1. Cold Start Smoke Test
expected: Kill any running dev server, cold-start `npm run dev`. Composer opens, tab strip + SOURCES header visible, no boot-time console errors.
result: pass

### 2. Reference Picker — `+ New…` no longer clipped at default sidebar width (Gap #1)
expected: Drop a Channel (or any component with a `geometry` field) on the canvas. Open the right sidebar Properties panel at its default width (320px). The geometry picker row shows the **Select dropdown** AND **+ New…** AND **Edit…** buttons all fully inside the panel — nothing is clipped or off-screen. At narrower widths the row wraps, but the `+ New…` button is never hidden.
result: issue
reported: "What the fuck did you do?? This is just horrible design. Why isn't the design aware of the shape and size of the window? this looks really bad and not professional. Now everything in the properties tab is cut on the right side and doesn't dynamically fit the window. Get this fixed. Don't make a mistake here again. If you have to rewrite the logic so its actually dynamic you have to do that. Don't be lazy with editing whatever needed to make it work properly and professionally."
severity: blocker

### 3. Delete AlertDialog fires on a USED resource (Gap #2)
expected: In the Resources tab tree, create a geometry named `mtr_ch` (use `+ New` from a Channel's geometry picker so it ends up referenced). Then in the Resources tab right-click that geometry row → Delete. An AlertDialog appears with description matching `Delete geometry mtr_ch? Used by 1 component(s).` (lowercase `geometry`, the new `Used by` wording, no `It is used by`). The default focused button is Cancel.
result: [pending]

### 4. Delete AlertDialog Cancel + Delete-anyway behavior (Gap #2 cont)
expected: From test 3's dialog click Cancel → the resource remains in the tree and the canvas component still references it. Re-open the dialog (right-click → Delete again), click `Delete anyway` → resource is removed from the tree and the component's geometry field reverts to the sentinel `(leave unset — set in code)`.
result: [pending]

### 5. Save As default filename pulls from Model Options Name (Gap #3)
expected: Open the Project tab → Model Options form. Set the Name field to `phase62-smoke`. File → Save As. The OS save dialog pre-fills the filename as `phase62-smoke.scp` (not `project.scp`). Cancel the dialog. Clear the Name field to empty, try Save As again — dialog pre-fills `project.scp`.
result: [pending]

### 6. Professional copy spot-checks (Gap #4)
expected: Hover the disabled `Edit…` button when no resource is selected in a picker — tooltip reads `Pick a resource first.` (not `Select a resource to edit it.`). The sentinel option in the geometry/power-shape Select dropdown reads `(leave unset — set in code)` (not `fill in code`). If you can trigger a save error (e.g., point Save As at a read-only path), the error dialog reads `Save failed. <…>` (not `Couldn't save project`).
result: [pending]

### 7. Regression spot-checks against the 14 originally-passing steps
expected: Quick sweep — these all worked before the gap-closure plans and should still work: (a) Ctrl+1 / Ctrl+2 / Ctrl+3 switches Project / Resources / Components tabs; (b) `+ New geometry` creation auto-suggests `geometry_1` and auto-selects the new resource on Create; (c) Inline rename via double-click in the Resources tree still works; (d) Esc cascade-clears selection; (e) Round-trip: save a project, open another, reopen the first — canvas + Resources + Model Options + active tab restore correctly.
result: [pending]

### 8. Left panel overflow at narrow widths (surfaced during Test 1)
expected: Resizing the LEFT panel (the Resources / Project tab tree, not the right Properties panel) down to its minimum width keeps every button inside the panel — nothing escapes the panel bounds or overlaps the File / Code Preview buttons in the top bar.
result: issue
reported: "Yes, but if i make the left panel smaller, the buttons go out of the panel and overlap the file and code buttons."
severity: major

## Summary

total: 8
passed: 1
issues: 2
pending: 5
skipped: 0

## Gaps

- truth: "Right Properties panel content fits dynamically within its current width at every panel/window size — no horizontal clipping of fields or controls."
  status: failed
  reason: "User reported: 'everything in the properties tab is cut on the right side and doesn't dynamically fit the window... If you have to rewrite the logic so its actually dynamic you have to do that.' The 62-12 patch was scoped to a single row inside ResourceReferencePicker; the Properties form as a whole still does not respond to panel width. Likely a missing min-w-0 / overflow strategy on the parent ParameterForm container — not just one picker row."
  severity: blocker
  test: 2
  root_cause: ""
  artifacts: []
  missing: []
  debug_session: ""

- truth: "Resizing the LEFT panel down to its minimum width keeps every button inside the panel and never overlaps the top-bar File / Code Preview controls."
  status: failed
  reason: "User reported: Yes, but if i make the left panel smaller, the buttons go out of the panel and overlap the file and code buttons."
  severity: major
  test: 8
  root_cause: ""
  artifacts: []
  missing: []
  debug_session: ""
