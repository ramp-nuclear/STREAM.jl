---
status: complete
phase: 65-interaction-model-overhaul
source: [65-01-SUMMARY.md, 65-02-SUMMARY.md, 65-03-SUMMARY.md, 65-04-SUMMARY.md, 65-05-SUMMARY.md, 65-06-SUMMARY.md, 65-07-SUMMARY.md, 65-08-SUMMARY.md, 65-09-SUMMARY.md, 65-10-esc-input-focus-guard-SUMMARY.md, 65-11-addcomponent-submenu-radix-SUMMARY.md, 65-12-marquee-css-SUMMARY.md, 65-13-canvas-controls-dedup-SUMMARY.md, 65-14-perf-trivial-gates-SUMMARY.md]
started: 2026-05-15T11:13:01Z
updated: 2026-05-15T13:30:00Z
---

## Current Test
<!-- OVERWRITE each test - shows where we are -->

[testing complete]

## Tests

### 1. Cold Start Smoke Test
expected: Kill any running STREAM Composer dev process. Start the Tauri dev app from scratch (`npm run tauri dev` in `gui/`). The app boots without errors, the canvas workspace loads (no stuck boot splash), and no crash-recovery modal appears on a clean launch.
result: pass

### 2. Lowest-Free Instance Naming on Drop (Plan 01)
expected: Drop a Pump from the toolbox — it gets a name like `pump_1`. Drop two more — `pump_2`, `pump_3`. Delete `pump_2`. Drop another Pump — the new one is named `pump_2` (lowest free slot), NOT `pump_4`.
result: pass

### 3. Reset-to-Empty in Numeric Fields (Plan 02)
expected: Select a component with a numeric param that has a default (e.g., a Pump). Clear the numeric field and click away (blur). The field restores to its default value, no red error. Then try the same on a `required` field with no default (e.g., a Channel `L`) — it shows a required-error after clearing. Optional-no-default fields clear silently.
result: pass

### 4. Left-Marquee Selection — restyled + no bounding box (Plans 03/12)
expected: |
  Left-mouse-drag on empty canvas draws a selection rectangle.
  Post Plan 12:
  - Marquee border is a SOLID line in the primary accent color (not the default dotted rgba(0,89,220,0.8)).
  - Border slightly brighter/more opaque than the fill.
  - After releasing the marquee, NO bounding box wraps the selected nodes (`.react-flow__nodesselection-rect` is hidden).
  - Selection is still visible via the per-node ring highlight on StreamNode.
  - Node dragging and per-node selection are unaffected.
  Also: Plan 14 added a session-only InteractiveLock button (top-right) that should NOT affect marquee — verify only that marquee still works (Test 14 covers the lock button itself).
result: pass
prior_result: issue
prior_severity: cosmetic
prior_report: "1. Dotted border looks ugly. 2. Bounding box after release. 3. Right-drag pan not smooth (perf gap — covered separately under perf gates in Plan 14)."
fix_plans: [65-12 (marquee CSS), 65-14 (perf gates — partial; WSL2/WebKitGTK floor remains)]
re_verified_note: "User confirmed marquee styling and no-bbox both land correctly. Two NEW out-of-scope observations raised — see ## Out-of-scope observations section."

### 5. Right-Drag Pan (Plan 03)
expected: Hold right mouse button and drag on empty canvas. The canvas pans (viewport moves). When you release the right button after dragging more than ~5px, NO context menu appears (the right-drag-pan suppresses the OS context menu).
result: pass
note: "User also reported right-click without moving does nothing — captured under Test 6."

### 6. Right-Click Context Menu Disambiguation (Plan 03)
expected: Right-click on empty canvas without moving the mouse (or moving <5px within 250ms). The canvas context menu appears with Paste / Auto-Layout (future) / Add Component options.
result: pass
note: "Initially reported 'Nothing happens on right click no move' but user retested at Test 13 and confirmed canvas right-click menu now works. Original failure may have been transient (hot-reload state, focus on text input, etc.)."

### 7. Esc Inside Text Input Doesn't Desync Selection (Plans 03/10)
expected: |
  Select a node. Focus a text input in the sidebar (e.g., the InstanceName field). Press Esc while typing.
  Post Plan 10:
  - Properties panel still shows the same selection (does NOT go to 'nothing selected').
  - Canvas ring outline on the node stays visible.
  - Properties panel and canvas stay in lockstep.
  Also re-verify: Esc with NO input focused still clears selection (CanvasPanel handler — existing behavior preserved).
result: pass
prior_result: issue
prior_severity: major
prior_report: "Esc while typing in input made properties panel go to 'nothing selected' but canvas outline persisted — properties panel and canvas selection out of sync."
fix_plans: [65-10 (Esc input-focus guard on SidebarPanel)]
re_verified_note: "User confirmed Esc-with-input-focused no longer desyncs. Two NEW out-of-scope UX observations raised — see ## Out-of-scope observations section."

### 8. Ctrl+C / Ctrl+V Copy & Paste (Plan 04)
expected: Select 2-3 connected nodes. Press Ctrl+C, then Ctrl+V. New copies appear offset from the originals with fresh names (e.g., `pump_2` becomes `pump_3` or next free). Internal edges between the copied nodes are preserved; edges to non-copied nodes are dropped. Pasting again stacks further offset.
result: pass

### 9. Ctrl+X Cut (Plan 04)
expected: Select a node. Press Ctrl+X — the node is removed from the canvas AND the clipboard now holds it. Press Ctrl+V — the node is restored (possibly offset). Ctrl+Z (undo) restores the cut node to its original position.
result: pass

### 10. Ctrl+D Duplicate (Plan 04)
expected: Select a node. Press Ctrl+D. A duplicate appears offset by 20px in both x/y with a new lowest-free name. This does NOT touch the OS clipboard (Ctrl+V afterward still pastes the previous Ctrl+C content, not the duplicate).
result: pass
note: "User reaffirmed GUI lag concern (tracked under Test 4 perf gap — partially closed by Plan 14)."

### 11. Right-Click Node Context Menu (Plan 05)
expected: Right-click on a node. Menu shows: Rename / Duplicate / Show generated Julia code / Delete. Clicking Rename focuses+selects the InstanceName text field in the sidebar. Clicking Duplicate creates an offset copy. Clicking Delete removes the node. Show errors should NOT appear (hidden until Phase 71).
result: pass

### 12. Right-Click Edge Context Menu (Plan 05)
expected: Right-click on an edge. Menu shows only Delete. Clicking Delete removes the edge.
result: pass

### 13. Canvas "Add Component" Submenu — viewport-aware placement (Plans 05/11)
expected: |
  Right-click on empty canvas → hover Add Component → hover a category submenu.
  Post Plan 11:
  - Submenu renders fully on screen.
  - Near the RIGHT edge of the canvas, the submenu flips to the LEFT of the trigger (Floating UI `flip()` middleware).
  - Keyboard navigation (Enter / ArrowRight opens; ArrowLeft / Esc closes) works.
  - Clicking a component (e.g., Pump) adds it at the right-click flow position.
result: pass
prior_result: issue
prior_severity: major
prior_report: "Add Components opens a submenu but each per-category item doesn't show its submenu fully — only a tiny edge is visible. Placement bugged."
fix_plans: [65-11 (Radix DropdownMenu.Sub with Floating UI flip+shift)]
re_verified_note: |
  Required 4 follow-up iterations on Plan 11 after the initial Radix DropdownMenu.Sub swap:
  1. (commit 321e2c1) Add Component was always-open (defaultOpen={true}); switched to hover-driven open + sideOffset tuning. Also re-added Sources to ToolboxPanel (was hidden by 63.1 D-06).
  2. (commit 41f3795) First item appeared "selected" due to Radix autoFocus + focus:bg-accent. Added onOpenAutoFocus prevent + focus-visible: styling. Removed onFocus from Add Component trigger (was re-opening submenu on Popover close).
  3. (commit 19a9ea6) Architectural rewrite — replaced outer Popover with DropdownMenu so Add Component is a real DropdownMenu.Sub with Radix's native safe-polygon hover. Fixed first-right-click-silent bug in useRightClickContextMenu (capture-phase listeners + null-gesture fallback).
  4. (commit a26ca81) Dropped hand-tuned sideOffset/alignOffset on SubContent — Radix defaults (Floating UI flip+shift) are correct.

### 14. Canvas Overlay Buttons — top-right only (Plans 06/13)
expected: |
  Plan 13 changes the canvas chrome:
  - The ReactFlow built-in bottom-left Controls panel is REMOVED (no zoom-in / zoom-out / fit-view / lock buttons in the bottom-left corner).
  - The top-right overlay now contains FIVE buttons: ZoomIn, ZoomOut, FitView, InteractiveLock, SnapToGrid.
  - Zoom buttons zoom in/out, FitView frames all nodes.
  - Interactive Lock toggles a session-only lock: when ON, nodes are not draggable, not connectable, not selectable; viewport pan via wheel/scroll still works.
  - Interactive Lock is session-only — NOT persisted to `.scp` (close project → reopen → lock state resets to OFF).
  - Snap-to-grid behavior from Plan 06 unchanged.
result: pass
prior_result: issue
prior_severity: cosmetic
prior_report: "Canvas has buttons at the bottom-left for size, focus, and lock — duplicates the new top-right overlay. Hide the bottom-left buttons."
fix_plans: [65-13 (delete <Controls/>, add 4 new top-right buttons + interactiveLocked store field)]

### 15. Snap-to-Grid Persistence (Plan 06)
expected: Toggle snap-to-grid ON. Save the project (`.scp` file). Close and reopen the file. The snap state persists (still ON). Opening a legacy `.scp` file without `snap_to_grid` defaults to OFF.
result: pass

### 16. AutoRecover Sidecar Write on Edit (Plans 07/09)
expected: |
  Edit something in a project (e.g., add a node). Within ~2 seconds, an autosave sidecar file appears in `~/.local/share/com.stream.composer/STREAM-Composer/autorecover/` (Linux $APPDATA path).
  Post Plan 09:
  - Tauri v2 fs ACL now grants $APPDATA scope — `mkdir`, `writeTextFile`, `readTextFile`, `readDir`, `remove` all succeed.
  - For an untitled project, file is `untitled-<uuid>.scp.autosave` plus a `running.lock` lockfile in the same directory.
  - When you Save the project normally, the sidecar files are removed.
  - Open devtools → console — no `[autoRecover] ... failed:` warnings should appear under normal use (DEV-mode logging is in place but should be silent on success).
  Verify on disk:
  ```
  ls ~/.local/share/com.stream.composer/STREAM-Composer/autorecover/
  ```
  Expect at least one `*.scp.autosave` file and a `running.lock` file.
result: pass
prior_result: issue
prior_severity: blocker
prior_report: "Filesystem inspection showed no autorecover/ directory at all — capability ACL was blocking every fs op silently. ~/.local/share/com.stream.composer contained only WebKitCache/localstorage."
fix_plans: [65-09 (Tauri v2 fs ACL appdata scope + DEV-mode logging on silent catch blocks)]
re_verified_note: "User confirmed sidecar writer now produces files on disk + running.lock + no devtools warnings + save() clears sidecar. Plan 09 capability ACL fix landed."

### 17. Crash-Recovery Restore Modal (Plans 08/09)
expected: |
  1. Open the app, add nodes (do NOT save).
  2. Verify a sidecar file exists in the autorecover directory (from Test 16).
  3. Force-kill the Tauri shell: `pkill -9 -f target/debug/gui` or `kill -9 <pid>`.
  4. Relaunch `npm run tauri dev` (or the built app).
  5. A blocking modal appears: "Recover unsaved work from `<timestamp>` in `<displayName>`?" with Recover / Discard buttons.
  6. The canvas workspace does NOT appear behind the modal — only the modal is visible.
result: pass
prior_result: issue
prior_severity: blocker
prior_report: "Force-kill → relaunch → no modal, workspace loaded clean. Tauri global undefined in devtools."
fix_plans: [65-09 (root cause of Test 17 was same as Test 16 — fs ACL; sidecar writer was no-op so detectCrashOnLaunch found nothing)]
re_verified_note: "User confirmed crash-recovery modal appears blocking on relaunch after kill -9. Plan 09 ACL fix unblocked the entire AutoRecover chain."

### 18. Restore Modal Blocks Esc/Outside-Click (Plan 08)
expected: With the restore modal open (after simulated crash), pressing Esc does NOT close it. Clicking outside the modal does NOT close it. The only way to dismiss is Recover or Discard.
result: pass
prior_result: blocked
prior_blocked_by: prior-phase
fix_plans: [65-09 (unblocks Test 17 → unblocks this)]
re_verified_note: "Modal correctly ignores Esc + outside-click; only Recover/Discard buttons dismiss."

### 19. Restore Modal — Recover Path (Plan 08)
expected: With the restore modal open, click "Recover". The unsaved work loads into the workspace (nodes/edges restored), isDirty becomes true, and (for an untitled project) the file path stays null so Save will prompt Save-As. The modal closes.
result: pass
prior_result: blocked
prior_blocked_by: prior-phase
fix_plans: [65-09 (unblocks Test 17 → unblocks this)]
re_verified_note: "Recover restored the unsaved nodes/edges, dirty indicator showed, Save prompted Save-As for untitled project."

### 20. Restore Modal — Discard Path (Plan 08)
expected: After another simulated crash, click "Discard" instead. All sidecar files are removed, the workspace loads in its normal clean state, and relaunching again does NOT show the restore modal.
result: pass
prior_result: blocked
prior_blocked_by: prior-phase
fix_plans: [65-09 (unblocks Test 17 → unblocks this)]
re_verified_note: "Discard cleared sidecars, workspace loaded clean, relaunch confirmed no second modal. AutoRecover chain end-to-end verified."

## Summary

total: 20
passed: 20
issues: 0
pending: 0
skipped: 0
blocked: 0

## Out-of-scope observations

Items surfaced during the re-verification UAT that are NOT regressions of the gap-closure plans (Test 4 passed as designed). Triage destination TBD (likely Phase 72 design system / interaction contract).

- **Selection ring on individual selected components could be more obvious / brighter.** Today it's `ring-2 ring-[var(--ring)]` on StreamNode. After Plan 12 removed the bounding box, this ring is now the sole visual cue for selection — user wants it more prominent. Candidate fixes: thicker ring, brighter color token, glow/shadow halo. (cosmetic, design)
- **Multi-selection right-panel behavior is undefined.** When the user selects 2+ nodes (via marquee or shift-click), the Properties panel currently shows the properties of the last-added node. Open design question: what should the panel show for multi-select? Options to consider: (a) nothing — empty state with "N selected"; (b) bulk-edit form for fields common to all selected types; (c) keep "last node added" but make it explicit in the header; (d) a list selector to pick which selection's properties to view. (design, future-phase)
- **Esc-twice should layer: first blur input, then clear selection.** Today's Plan 10 guard makes Esc-in-input a no-op. User wants Esc inside an input to first BLUR the input (release focus to document.body) on the first press, then a second Esc would fall through to the CanvasPanel handler and clear selection as normal. Implementation: in SidebarPanel.tsx Esc handler, when input has focus call `(e.target as HTMLElement).blur()` and stopPropagation — instead of full early-return. (UX, minor)
- **Text fields with default/current values should auto-select on focus.** Today clicking into a populated text field places the cursor inside; user must select-all+delete before typing a new value. Two candidate fixes: (a) render defaults as placeholder text (faded), with empty-field-means-default semantics — requires a load/save contract change to treat empty input as "use default" rather than "explicit empty"; (b) on focus, auto-select the existing value (`e.target.select()`) so any keystroke replaces it — zero contract change, smaller blast radius. Recommendation: **(b)** — same UX win, no risk to the value-semantics layer. (UX, minor, design)

## Re-verification Notes

- This is the **post-gap-closure UAT pass** after Plans 09–14 shipped 2026-05-15.
- 9 tests reset to `[pending]`: the 6 previous issues (Tests 4, 7, 13, 14, 16, 17) plus 3 previously blocked (Tests 18, 19, 20 — unblocked once Test 17's autorecover root cause is fixed).
- Each pending test lists its `fix_plans` so we can trace which plan should have closed which gap.
- On pass, the corresponding entry in the original `## Gaps` (preserved in git history at commit `4af45a9`) is implicitly resolved. If a test still fails, the new failure becomes a fresh Gaps entry and is diagnosed via the normal flow.

## Gaps

<!-- New issues discovered in this re-verification pass append here. The original Gaps block (closed by Plans 09–14) lives in git history at commit 4af45a9. -->
[none yet]
