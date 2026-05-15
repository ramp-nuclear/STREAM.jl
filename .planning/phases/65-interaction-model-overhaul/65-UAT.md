---
status: diagnosed
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
  root_cause: "gui/src-tauri/capabilities/default.json grants only fs:scope-home-recursive (a READ scope for $HOME). It does NOT grant fs:scope-appdata-recursive or fs:allow-appdata-write-recursive. AutoRecover writes to $APPDATA (Linux: ~/.local/share/com.stream.composer/STREAM-Composer/autorecover/) — every tauri-plugin-fs call (mkdir, writeTextFile, readTextFile, readDir, remove) is rejected by the v2 ACL. The 7 silent `try { ... } catch { }` blocks in autoRecover.ts swallow the rejections. saveProject works because the dialog `save()` picker grants an implicit one-shot scope to the chosen file."
  artifacts:
    - path: "gui/src-tauri/capabilities/default.json"
      issue: "Missing: fs:scope-appdata-recursive, fs:allow-appdata-write-recursive, fs:allow-remove, fs:allow-read-dir. Existing fs:scope-home-recursive is the wrong base (and read-only)."
    - path: "gui/src/lib/autoRecover.ts"
      issue: "7 silent try/catch blocks at lines 121, 137, 150, 170, 197, 213, 228 hide ACL rejections in devtools."
  missing:
    - "Add fs:scope-appdata-recursive + fs:allow-appdata-write-recursive + fs:allow-remove + fs:allow-read-dir to gui/src-tauri/capabilities/default.json"
    - "Add a structured fs:scope entry binding $APPDATA/STREAM-Composer/autorecover/* (defense-in-depth)"
    - "Replace the 7 silent catch blocks with `catch (err) { if (import.meta.env.DEV) console.warn('[autoRecover] <op> failed:', err); }`"
    - "Fix smoke-test guidance — replace window.__TAURI__.core.invoke(...) with `(await import('@tauri-apps/api/core')).invoke(...)`; window.__TAURI__ is correctly not exposed (v2 default) and ES module imports bypass it."
  debug_session: .planning/debug/autorecover-bridge.md

- truth: "After force-killing the Tauri shell with unsaved edits and relaunching, the AutoRecoverRestoreModal appears blocking the workspace"
  status: failed
  reason: "User simulated crash (added nodes, kill -9 target/debug/gui, relaunched) — no modal appeared, workspace loaded clean. Additionally `window.__TAURI__.core` is undefined in devtools."
  severity: blocker
  test: 17
  root_cause: "Same root cause as Test 16 gap — capabilities/default.json missing appdata scope. With no sidecar files written, detectCrashOnLaunch's `enumerateSidecars` returns empty and App.tsx renders the clean workspace path. Tauri JS bridge, plugin registration, and is_pid_alive command are all correctly wired — fixing the capability ACL unblocks everything downstream."
  artifacts:
    - path: "gui/src/App.tsx"
      issue: "Render gate behaves correctly given no sidecars; no change needed — will work once capabilities are fixed."
    - path: "gui/src-tauri/src/lib.rs"
      issue: "tauri_plugin_fs::init() and is_pid_alive/get_pid handlers correctly registered — no change needed."
  missing:
    - "No code changes specific to Test 17 — fix is the same capabilities/default.json change as Test 16."
    - "After fix: re-run UAT 16 → expect ~/.local/share/com.stream.composer/STREAM-Composer/autorecover/untitled-<uuid>.scp.autosave; then UAT 17 → kill -9 target/debug/gui → relaunch → modal appears."
  debug_session: .planning/debug/autorecover-bridge.md

- truth: "Canvas chrome shows only one set of overlay controls — ReactFlow's built-in bottom-left Controls (zoom/fit/lock) are hidden, leaving only the new top-right canvas overlay buttons"
  status: failed
  reason: "User reported: The canvas comes with buttons at the bottom-left (size, focus, and a lock) — there are now two places for these buttons. User wants the bottom-left buttons hidden."
  severity: cosmetic
  test: 14
  root_cause: "<Controls /> rendered unconditionally at gui/src/components/CanvasPanel.tsx:328 (imported on line 4). The top-right overlay div at lines 333-335 contains only <SnapToGridButton /> — no zoom/fit/lock counterparts exist. Removing Controls outright would lose those four functions; recommended path is to add top-right counterparts first using @xyflow/react v12's useReactFlow() helpers (zoomIn, zoomOut, fitView) plus a lock toggle backed by a new useStore boolean."
  artifacts:
    - path: "gui/src/components/CanvasPanel.tsx:328"
      issue: "<Controls /> rendered unconditionally — needs to be removed."
    - path: "gui/src/components/CanvasPanel.tsx:4"
      issue: "Unused `Controls` import after removal."
    - path: "gui/src/components/CanvasPanel.tsx:333-335"
      issue: "Top-right overlay div needs new ZoomInButton / ZoomOutButton / FitViewButton / InteractiveLockButton siblings to SnapToGridButton."
  missing:
    - "Add 3-4 small icon buttons (Lucide ZoomIn/ZoomOut/Maximize/Lock) in the top-right overlay, mirroring SnapToGridButton.tsx structure"
    - "Wire to useReactFlow().zoomIn(), zoomOut(), fitView() for the first three"
    - "Add `interactiveLocked: boolean` + setInteractiveLocked action to useStore.ts; bind to ReactFlow nodesDraggable / nodesConnectable / elementsSelectable / panOnDrag props"
    - "Delete <Controls /> at CanvasPanel.tsx:328 and the unused import on line 4"
  debug_session: .planning/debug/reactflow-controls-dedup.md

- truth: "Per-category submenus inside the Canvas → Add Component menu render fully on screen (not clipped or positioned offscreen)"
  status: failed
  reason: "User reported: Add components opens a submenu, but each item there doesn't show the submenu. Its placement is bugged — only a tiny edge of it is visible."
  severity: major
  test: 13
  root_cause: "PopoverMenuSubContent in gui/src/components/ui/context-menu.tsx:243-265 (added by Plan 05 W10 workaround) is a hand-rolled absolutely-positioned <div> with hardcoded `absolute left-full top-0 z-50`. No viewport-collision detection / Floating UI / flip middleware. When the parent Add Component menu lives in the right portion of the viewport, the `left-full` projection pushes the level-2 submenu past the right edge, clipping it. The top-level Popover works because it uses Radix PopoverContent with Floating-UI auto-flip; the W10 workaround removed that for nested levels and never restored it."
  artifacts:
    - path: "gui/src/components/ui/context-menu.tsx:243-265"
      issue: "PopoverMenuSubContent uses hardcoded `absolute left-full top-0` with no collision response — broken primitive."
    - path: "gui/src/components/ui/context-menu.tsx:188-241"
      issue: "PopoverMenuSub / PopoverMenuSubTrigger surround the broken primitive — need to participate in the fix."
    - path: "gui/src/components/canvasMenus/AddComponentSubmenu.tsx:45-61"
      issue: "Consumer — should not need changes if primitive is fixed cleanly."
    - path: "gui/src/components/canvasMenus/CanvasContextMenu.tsx:38-43"
      issue: "Same submenu primitive used for level-1 Add Component nesting — benefits from same fix."
  missing:
    - "PREFERRED: swap to Radix DropdownMenu.Sub / DropdownMenu.SubTrigger / DropdownMenu.SubContent — they ship viewport-collision via Floating UI, plus keyboard navigation and focus management. Mount with a dummy hidden DropdownMenu.Trigger inside PopoverContent."
    - "ALTERNATIVE: patch PopoverMenuSub primitives with @floating-ui/react — useFloating with `flip()` + `shift()` middleware, FloatingPortal for content, refs.setReference on trigger."
    - "Delete old hand-rolled PopoverMenuSub* primitives once unused"
    - "Verify by right-clicking near right edge of canvas — submenu must flip to left and remain fully visible"
  debug_session: .planning/debug/addcomponent-submenu-placement.md

- truth: "Esc inside a focused text input does NOT change selection (properties panel and canvas stay aligned with the previously selected node)"
  status: failed
  reason: "User reported: While typing in a text input, Esc makes the properties window go back to 'nothing selected' but the canvas still shows the outline around what was selected — properties panel and canvas selection are out of sync."
  severity: major
  test: 7
  root_cause: "Esc handling is split across two listeners on two state sources. (A) zustand selectedNodeId/selectionKind drives SidebarPanel. (B) ReactFlow nodes[].selected drives the canvas per-node `ring-2 ring-[var(--ring)]` outline. SidebarPanel.tsx:80-95 has a DOCUMENT keydown listener with NO input-focus guard — calls clearSelection() on Esc, clearing (A) only. CanvasPanel.tsx:266-280 correctly skips when input has focus, leaving (B) untouched. clearSelection() at useStore.ts:1762-1768 doesn't touch nodes[].selected, and D-22's ReactFlow→zustand sync is one-way. Net: properties panel deselects, canvas outline persists."
  artifacts:
    - path: "gui/src/components/sidebar/SidebarPanel.tsx:80-95"
      issue: "Document keydown listener clears zustand selection on Esc with NO input-focus guard — proximate source of the desync."
    - path: "gui/src/store/useStore.ts:1762-1768"
      issue: "clearSelection() only mutates zustand selection slice; never touches nodes[].selected."
    - path: "gui/src/components/CanvasPanel.tsx:266-280"
      issue: "Correct handler with input-focus guard; clears BOTH state sources. Reference implementation."
    - path: "gui/src/components/StreamNode.tsx:361"
      issue: "Canvas per-node ring outline reads ReactFlow's `selected` prop, not zustand."
  missing:
    - "PREFERRED: add the same input-focus guard from CanvasPanel.tsx:266-275 to SidebarPanel.tsx:80-95 (HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement | isContentEditable early-return)"
    - "Restores the documented invariant: Esc inside text input does not change selection at all"
    - "OPTIONAL HARDENING (follow-up): update useStore.clearSelection() to also clear nodes[].selected via setNodes, so any future programmatic caller doesn't drift the two sources"
  debug_session: .planning/debug/esc-selection-desync.md

- truth: "Marquee selection rectangle border is styled to fit the GUI (not the default ReactFlow dotted line)"
  status: failed
  reason: "User reported: The border of the selection area is dotted and looks ugly. Wants a custom design — fill is fine, but the border should be a full line a little brighter than the fill."
  severity: cosmetic
  test: 4
  root_cause: "Default @xyflow/react@12.10.2 stylesheet imported at gui/src/components/CanvasPanel.tsx:17 ships --xy-selection-border-default: 1px dotted rgba(0,89,220,0.8). Project has zero CSS overrides for .react-flow__selection. Phase 65 Plan 03 enabled selectionOnDrag + SelectionMode.Partial without adding accompanying CSS — defaults surfaced."
  artifacts:
    - path: "gui/src/index.css"
      issue: "Missing custom override for .react-flow__selection (target file for the fix)."
    - path: "gui/src/components/CanvasPanel.tsx:17"
      issue: "Default stylesheet import — context only, not edited."
  missing:
    - "Append to gui/src/index.css after the existing .react-flow__handle block:"
    - "  .react-flow__selection { background: color-mix(in oklch, var(--primary) 12%, transparent); border: 1px solid color-mix(in oklch, var(--primary) 55%, transparent); border-radius: 2px; }"
    - "Uses existing --primary design token so it auto-adapts to light/dark via .dark class"
  debug_session: .planning/debug/marquee-visual-style.md

- truth: "After releasing marquee selection, no bounding box wraps the selected nodes — selection state is conveyed only by the per-node highlight"
  status: failed
  reason: "User reported: Once you release selection, a bounding box of what is selected appears. I don't like it. Prefers (a) no box at all, just keep the stuff that is selected marked."
  severity: cosmetic
  test: 4
  root_cause: "@xyflow/react v12 internal <NodesSelection> renders .react-flow__nodesselection-rect whenever 2+ nodes are selected; no v12 prop disables it. Project has no override."
  artifacts:
    - path: "gui/src/index.css"
      issue: "Missing display:none override for .react-flow__nodesselection-rect."
  missing:
    - "Append to gui/src/index.css:"
    - "  .react-flow__nodesselection-rect { display: none; }"
    - "Parent .react-flow__nodesselection has pointer-events:none — hiding the child rect does not affect dragging or selection state."
  debug_session: .planning/debug/marquee-visual-style.md

- truth: "Right-click drag (pan) and node drag feel smooth — not visibly FPS-capped or chopped"
  status: failed
  reason: "User reported: Dragging with right click is not smooth (not something new). It may be FPS locked or something like that, because it feels chopped to drag around and drag stuff around."
  severity: minor
  test: 4
  root_cause: "Two superimposed effects. (a) Environmental floor: right-click pan is pure CSS-transform with NO React state touch, yet it still chops — implicating WebKitGTK/WSLg compositing path on Linux 6.6 WSL2. No fix inside the app for this layer. (b) App-layer amplifier on top of (a) for NODE drag: zustand created without subscribeWithSelector middleware at useStore.ts:781 → every set() wakes every subscribe callback. App.tsx:288 title-sync subscribe calls getCurrentWindow().setTitle() on every store change including per-pixel drag sets — a Tauri IPC per pixel. useStore.ts:2691 autoRecover subscribe runs clearTimeout/setTimeout per pixel. StreamNode.tsx:174-194 per-port selectors run O(N+E) autoflip scans per node per set."
  artifacts:
    - path: "gui/src/App.tsx:272-292"
      issue: "Unconditional title-sync subscribe calls Tauri IPC setTitle on every store change — single biggest in-app contributor."
    - path: "gui/src/store/useStore.ts:781"
      issue: "create() missing subscribeWithSelector middleware — every subscribe fires on every set."
    - path: "gui/src/store/useStore.ts:1014-1048"
      issue: "onNodesChange writes isDirty:true on every drag pixel — flips per-pixel debounce timers everywhere."
    - path: "gui/src/store/useStore.ts:2691"
      issue: "AutoRecover subscribe — per-pixel clearTimeout/setTimeout churn."
    - path: "gui/src/components/StreamNode.tsx:174-206, 261-281"
      issue: "Per-port autoflip selectors run O(N×P×(N+E)) scans per set()."
  missing:
    - "TRIVIAL: gate App.tsx:288 title-sync — only call setTitle when {currentFilePath, isDirty} actually changes (closure-tracked or via subscribeWithSelector)"
    - "TRIVIAL: gate autoRecover subscribe — schedule on isDirty rising edge only"
    - "TRIVIAL: install subscribeWithSelector middleware on the zustand store (useStore.ts:781)"
    - "MEDIUM: memoize autoflip per-port selectors so the O(N+E) scan runs once per node-set change, not per port per set"
    - "MEDIUM: consider flipping isDirty at onNodeDragStop instead of per pixel"
    - "ENVIRONMENTAL (recommend retest, not code): test on native Linux or built Windows .exe (WebView2 — materially faster than WebKitGTK, not subject to WSLg)"
  debug_session: .planning/debug/gui-drag-perf.md
