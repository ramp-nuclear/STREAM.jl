---
status: partial
phase: 65-interaction-model-overhaul
source: [65-01-SUMMARY.md, 65-02-SUMMARY.md, 65-03-SUMMARY.md, 65-04-SUMMARY.md, 65-05-SUMMARY.md, 65-06-SUMMARY.md, 65-07-SUMMARY.md, 65-08-SUMMARY.md]
started: 2026-05-15T11:13:01Z
updated: 2026-05-15T11:50:00Z
---

## Current Test

[testing paused — 3 items outstanding (Tests 18/19/20 blocked on Test 16/17 AutoRecover blocker)]

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

### 4. Left-Marquee Selection (Plan 03)
expected: With no node under the cursor, hold left mouse button and drag a rectangle across multiple nodes. Nodes inside the marquee become selected (highlighted). Releasing the drag commits the selection.
result: issue
reported: "This works, but a few notes: 1. The border of the selection area is dotted and looks ugly. Maybe we can redesign a custom one to fit the GUI better? the fill is fine, but maybe the border should be a full line a little brighter than the fill? 2. Once you release selection, a bounding box of what is selected appears. I don't like it. I think one of two options: (a) no box at all, just keep the stuff that is selected marked and that is enough. (b) some other solution you come up with, but I don't think anything will come up. 3. IDK exactly what it is, but dragging with right click is not smooth (not something new but I will mention it now). It may be FPS locked or something like that, because it feels chopped to drag around and drag stuff around. Maybe the performance of the entire GUI is capped in some way?"
severity: cosmetic

### 5. Right-Drag Pan (Plan 03)
expected: Hold right mouse button and drag on empty canvas. The canvas pans (viewport moves). When you release the right button after dragging more than ~5px, NO context menu appears (the right-drag-pan suppresses the OS context menu).
result: pass
note: "User also reported right-click without moving does nothing — captured under Test 6."

### 6. Right-Click Context Menu Disambiguation (Plan 03)
expected: Right-click on empty canvas without moving the mouse (or moving <5px within 250ms). The canvas context menu appears with Paste / Auto-Layout (future) / Add Component options.
result: pass
note: "Initially reported 'Nothing happens on right click no move' but user retested at Test 13 and confirmed canvas right-click menu now works. Original failure may have been transient (hot-reload state, focus on text input, etc.)."

### 7. Esc Clears Selection (Plan 03)
expected: Select one or more nodes (or edges). Press Esc. All selection clears. Esc should NOT clear selection while typing in a text input.
result: issue
reported: "Not so clear on what exactly is supposed to happen. Esc clears selection. If i am typing in a text input, it makes the properties window back to be like nothing is selected, but there is an outline around what was selected in the canvas still. Take from that what you will."
severity: major

### 8. Ctrl+C / Ctrl+V Copy & Paste (Plan 04)
expected: Select 2-3 connected nodes. Press Ctrl+C, then Ctrl+V. New copies appear offset from the originals with fresh names (e.g., `pump_2` becomes `pump_3` or next free). Internal edges between the copied nodes are preserved; edges to non-copied nodes are dropped. Pasting again stacks further offset.
result: pass

### 9. Ctrl+X Cut (Plan 04)
expected: Select a node. Press Ctrl+X — the node is removed from the canvas AND the clipboard now holds it. Press Ctrl+V — the node is restored (possibly offset). Ctrl+Z (undo) restores the cut node to its original position.
result: pass

### 10. Ctrl+D Duplicate (Plan 04)
expected: Select a node. Press Ctrl+D. A duplicate appears offset by 20px in both x/y with a new lowest-free name. This does NOT touch the OS clipboard (Ctrl+V afterward still pastes the previous Ctrl+C content, not the duplicate).
result: pass
note: "User reaffirmed GUI lag concern (tracked under Test 4 perf gap)."

### 11. Right-Click Node Context Menu (Plan 05)
expected: Right-click on a node. Menu shows: Rename / Duplicate / Show generated Julia code / Delete. Clicking Rename focuses+selects the InstanceName text field in the sidebar. Clicking Duplicate creates an offset copy. Clicking Delete removes the node. Show errors should NOT appear (hidden until Phase 71).
result: pass

### 12. Right-Click Edge Context Menu (Plan 05)
expected: Right-click on an edge. Menu shows only Delete. Clicking Delete removes the edge.
result: pass

### 13. Canvas "Add Component" Submenu (Plan 05)
expected: Right-click on empty canvas → hover "Add Component". Submenu shows registry components grouped by category (alphabetical). Clicking a component (e.g., Pump) adds it at the right-click flow position.
result: issue
reported: "Right clikcing the canvas works now. The Add components opens a submenu, but each item there doesn't show the submenu. its placement i think is bugged. it shows a tiny edge of it but it doesn't show everything."
severity: major
note: "User reports the canvas right-click menu now opens — Test 6 may need re-test. The nested category submenus inside Add Component are positioned offscreen / clipped — only a tiny edge is visible."

### 14. Snap-to-Grid Toggle (Plan 06)
expected: A Grid icon button is visible in the top-right canvas overlay. Default is OFF on a new project. Click to toggle ON — dragging a node now snaps positions to 16px multiples. Toggle OFF — free positioning resumes.
result: issue
reported: "It works, but there now is an issue. The canvas itself comes with buttons at the buttom left side. for size, focus, and a lock that idk what it does. there is now two places for these buttons. can you hide the bottom left buttons maybe?"
severity: cosmetic
note: "Functional behavior of snap-to-grid passes. Issue is layout polish: ReactFlow's built-in Controls (bottom-left: zoom in/out, fit-view, interactive-lock) feel redundant alongside the new top-right canvas overlay buttons. User wants to hide the bottom-left controls."

### 15. Snap-to-Grid Persistence (Plan 06)
expected: Toggle snap-to-grid ON. Save the project (`.scp` file). Close and reopen the file. The snap state persists (still ON). Opening a legacy `.scp` file without `snap_to_grid` defaults to OFF.
result: pass

### 16. AutoRecover Sidecar Write on Edit (Plan 07)
expected: Edit something in a project (e.g., add a node). Within ~2 seconds, a sidecar autosave file appears next to the project (or in the untitled-project sidecar location). When the project is saved normally, the sidecar is cleared.
result: issue
reported: "Initially marked pass without filesystem verification. Subsequent inspection: ~/.config/com.stream.composer does not exist; ~/.local/share/com.stream.composer contains only WebKitCache/localstorage (no autorecover/ subdir, no *.autosave files, no *.lock files anywhere). No saved-project sidecar next to test.scp either. Writer is producing no files at runtime."
severity: blocker
note: "Combined with window.__TAURI__.core undefined in devtools, the most likely root cause is the Tauri v2 JS bridge isn't reaching the webview, so every Tauri-IPC call (writeTextFile, invoke('get_pid'), etc.) in autoRecover.ts silently fails. Check tauri.conf.json withGlobalTauri / app.security and the dynamic-import path in autoRecover.ts."

### 17. Crash-Recovery Restore Modal (Plan 08)
expected: With unsaved edits in the app, force-kill the process (e.g., `kill -9 <pid>` or close the OS process without saving). Relaunch the app. A blocking modal appears: "Recover unsaved work from `<timestamp>` in `<displayName>`?" with Recover / Discard buttons. The canvas workspace does NOT appear behind the modal.
result: issue
reported: "Sequence: add nodes (unsaved), wait, kill -9 the Tauri binary (target/debug/gui), relaunch via npm run tauri dev — no modal came up, workspace loaded clean. Also: window.__TAURI__.core.invoke('get_pid') in devtools throws 'Cannot read properties of undefined (reading invoke)' — Tauri global not exposed."
severity: blocker
note: |
  Multiple suspects (any combination):
  (a) Sidecar may not actually be writing — Test 16 was reported pass but the user
      did not verify file existence on disk; the test merely asked them to confirm
      the expected behavior abstractly.
  (b) `is_pid_alive` may be returning true incorrectly for the killed PID.
  (c) `window.__TAURI__.core.invoke` undefined suggests Tauri's JS API may not be
      reaching the webview — could indicate Tauri v2 API exposure config issue,
      which would break the autoRecover Tauri-IPC path entirely.
  (d) detectCrashOnLaunch() logic may be flawed.
  Recommend filesystem verification (ls of sidecar dir) + console log of
  detectCrashOnLaunch result on next launch.

### 18. Restore Modal Blocks Esc/Outside-Click (Plan 08)
expected: With the restore modal open (after simulated crash), pressing Esc does NOT close it. Clicking outside the modal does NOT close it. The only way to dismiss is Recover or Discard.
result: blocked
blocked_by: prior-phase
reason: "Blocked by Test 17 — modal never appears because Tests 16/17 show autorecover sidecar writer is non-functional at runtime."

### 19. Restore Modal — Recover Path (Plan 08)
expected: With the restore modal open, click "Recover". The unsaved work loads into the workspace (nodes/edges restored), isDirty becomes true, and (for an untitled project) the file path stays null so Save will prompt Save-As. The modal closes.
result: blocked
blocked_by: prior-phase
reason: "Blocked by Test 17 — modal never appears because Tests 16/17 show autorecover sidecar writer is non-functional at runtime."

### 20. Restore Modal — Discard Path (Plan 08)
expected: After another simulated crash, click "Discard" instead. All sidecar files are removed, the workspace loads in its normal clean state, and relaunching again does NOT show the restore modal.
result: blocked
blocked_by: prior-phase
reason: "Blocked by Test 17 — modal never appears because Tests 16/17 show autorecover sidecar writer is non-functional at runtime."

## Summary

total: 20
passed: 11
issues: 6
pending: 0
skipped: 0
blocked: 3

## Gaps

- truth: "AutoRecover sidecar files are written to disk within ~2s of unsaved edits — at least one `.autosave` (and matching `.lock`) appears in the OS app-config sidecar directory"
  status: failed
  reason: "Filesystem inspection: ~/.config/com.stream.composer does not exist; ~/.local/share/com.stream.composer contains only webview cache/storage — no autorecover/ subdir, no *.autosave, no *.lock files anywhere on disk. Writer produces nothing at runtime."
  severity: blocker
  test: 16
  artifacts:
    - path: "gui/src/lib/autoRecover.ts"
      issue: "Sidecar/lockfile writers never produce files on disk — likely silent Tauri-IPC failure"
    - path: "gui/src-tauri/tauri.conf.json"
      issue: "Suspected: withGlobalTauri or fs/path plugin permissions missing — Tauri v2 JS bridge not reaching webview"
    - path: "gui/src/store/useStore.ts"
      issue: "initAutoRecover subscribe may be wired but the writer's dynamic-import resolution fails silently"
  missing:
    - "Verification that @tauri-apps/plugin-fs / @tauri-apps/api/path are listed in tauri.conf.json capabilities/permissions"
    - "Try/catch logging inside autoRecover.ts writer functions — current silent failure hides the root cause"

- truth: "After force-killing the Tauri shell with unsaved edits and relaunching, the AutoRecoverRestoreModal appears blocking the workspace"
  status: failed
  reason: "User simulated crash (added nodes, kill -9 target/debug/gui, relaunched) — no modal appeared, workspace loaded clean. Additionally `window.__TAURI__.core` is undefined in devtools (Tauri global not exposed)."
  severity: blocker
  test: 17
  artifacts:
    - path: "gui/src/App.tsx"
      issue: "Render gate / mount effect calls detectCrashOnLaunch but downstream Tauri IPC may be failing"
    - path: "gui/src-tauri/src/lib.rs"
      issue: "get_pid / is_pid_alive commands not reachable from JS (window.__TAURI__.core undefined)"
  missing:
    - "Likely the Tauri v2 JS bridge (window.__TAURI__) is gated; verify tauri.conf.json app.withGlobalTauri or migrate calls to use @tauri-apps/api/core import directly with proper capability config"

- truth: "Canvas chrome shows only one set of overlay controls — ReactFlow's built-in bottom-left Controls (zoom/fit/lock) are hidden, leaving only the new top-right canvas overlay buttons"
  status: failed
  reason: "User reported: The canvas comes with buttons at the bottom-left (size, focus, and a lock) — there are now two places for these buttons. User wants the bottom-left buttons hidden."
  severity: cosmetic
  test: 14
  artifacts: []
  missing: []
  note: "Likely <Controls /> from @xyflow/react in CanvasPanel.tsx — either remove it or render Controls without the built-in buttons we duplicate."

- truth: "Per-category submenus inside the Canvas → Add Component menu render fully on screen (not clipped or positioned offscreen)"
  status: failed
  reason: "User reported: Add components opens a submenu, but each item there doesn't show the submenu. Its placement is bugged — only a tiny edge of it is visible."
  severity: major
  test: 13
  artifacts: []
  missing: []
  note: "Likely a Radix Popover / shadcn PopoverMenuSubContent positioning/portal/collisionBoundary issue — see gui/src/components/canvasMenus/AddComponentSubmenu.tsx and gui/src/components/ui/context-menu.tsx PopoverMenuSub* primitives added in Plan 05 (D-11 + W10 workaround)."

- truth: "Esc inside a focused text input does NOT change selection (properties panel and canvas stay aligned with the previously selected node)"
  status: failed
  reason: "User reported: While typing in a text input, Esc makes the properties window go back to 'nothing selected' but the canvas still shows the outline around what was selected — properties panel and canvas selection are out of sync."
  severity: major
  test: 7
  artifacts: []
  missing: []

- truth: "Marquee selection rectangle border is styled to fit the GUI (not the default ReactFlow dotted line)"
  status: failed
  reason: "User reported: The border of the selection area is dotted and looks ugly. Wants a custom design — fill is fine, but the border should be a full line a little brighter than the fill."
  severity: cosmetic
  test: 4
  artifacts: []
  missing: []

- truth: "After releasing marquee selection, no bounding box wraps the selected nodes — selection state is conveyed only by the per-node highlight"
  status: failed
  reason: "User reported: Once you release selection, a bounding box of what is selected appears. I don't like it. Prefers (a) no box at all, just keep the stuff that is selected marked."
  severity: cosmetic
  test: 4
  artifacts: []
  missing: []

- truth: "Right-click drag (pan) and node drag feel smooth — not visibly FPS-capped or chopped"
  status: failed
  reason: "User reported: Dragging with right click is not smooth (not something new). It may be FPS locked or something like that, because it feels chopped to drag around and drag stuff around. Maybe the performance of the entire GUI is capped in some way?"
  severity: minor
  test: 4
  artifacts: []
  missing: []
