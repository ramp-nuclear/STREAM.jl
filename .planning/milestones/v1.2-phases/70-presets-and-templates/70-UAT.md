---
status: complete
phase: 70-presets-and-templates
source: [70-01-SUMMARY.md, 70-02-SUMMARY.md, 70-03-SUMMARY.md, 70-04-SUMMARY.md, 70-05-SUMMARY.md, 70-06-SUMMARY.md]
started: 2026-05-21T00:30:00Z
updated: 2026-05-21T03:00:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Cold Tauri rebuild
expected: `cd gui && npm run tauri dev` boots without errors; Tauri window opens. First build is slower because of the new `watch` Cargo feature flag — wait it out.
result: pass

### 2. Ctrl+4 keybind
expected: Pressing Ctrl+4 switches the left panel to the Presets tab (BookMarked icon highlighted). Ctrl+1 / Ctrl+2 / Ctrl+3 still cycle through Components / Resources / Project tabs.
result: pass

### 3. Library section initial state
expected: With a fresh empty `~/.config/com.stream.composer/presets/` directory, Library shows "No library presets yet." + "Save a selection to add your first template." Skeleton rows may flash briefly.
result: pass
note: User flagged the empty-state copy as too verbose / not engineering-voice. Tracked as a phase-wide copy gap (see Gaps section).

### 4. Project section initial state
expected: With no project open, Project shows "Open a project to use the Project store." Opening any `.scp` fixture refreshes the section to either an empty state or any existing presets.
result: pass

### 5. Save selection — happy path (right-click)
expected: Select 2+ components, right-click → "Save selection as preset…" appears → click opens modal (note any amber dashed outline on auto-extended nodes behind it). Type name `test_save_1`, optional description `"test preset 1"`, keep Store at Library, click Save Preset. Modal closes; within ~200ms Library shows `test_save_1`.
result: pass

### 6. Save selection — File menu
expected: With 2+ selected, File menu's "Save selection as preset…" is enabled. With 0 or 1 selected, disabled. Open it → same modal flow. Save as `test_save_2` to Project; `.scpr` appears in `<project-dir>/presets/`.
result: pass

### 7. Validation (empty / bad chars / collision)
expected: Empty name → button disabled, no inline error until first keystroke. Type `bad name` → "Use only letters, digits, underscores, or hyphens." Type `test_save_1` while Library selected → "A preset with this name already exists in the library." Cancel.
result: pass

### 8. Drag-from-tab
expected: Drag `test_save_1` row from Library onto the canvas → bundle lands centered at cursor → all placed nodes auto-selected (D-18) → instance names increment-renamed (no collision with existing) → any embedded resources appear in Resources tab with smart-incremented names.
result: pass
note: Initial pass — drag image was blank (didn't follow cursor) due to `select-none` + `overflow-hidden` on the draggable `<li>` (Chromium snapshot quirk). Fixed in 4a125a0 by gating both classes on `renaming` only. While re-testing, the user also approved a left-panel tab reshuffle: Components / Presets / Resources / Project (Ctrl+1..4 remapped). Landed in 018373c.

### 9. File → Load preset…
expected: Pan canvas to a non-default viewport (zoom in, scroll to corner). File → Load preset… → pick the `.scpr` via OS dialog → bundle lands at viewport center (not origin, not cursor) → auto-selected.
result: pass
note: User asked where the default Library directory lives — answered `~/.config/com.stream.composer/presets/`. The OS Open dialog opens at its own default cwd, not scoped to either preset directory; "Reveal in Finder/Explorer" (test 12) is the quicker route. Could be improved later by passing `defaultPath: appConfigDir/presets` to the dialog plugin in `loadPresetFromPath` — not blocking.

### 10. Rename
expected: Right-click preset → Rename → inline Input. Collision name → error border + tooltip. Valid new name → Enter or blur updates both filename on disk and JSON `name` field (verify with `cat`). Escape restores original.
result: pass
note: Two real bugs surfaced and were fixed before this test passed. (a) Right-click on a preset row did nothing — global `contextmenu` listener in useRightClickContextMenu was running in capture phase and setting `event.defaultPrevented = true` on the synthetic event before React dispatched it; Radix's `composeEventHandlers` then skipped its open-menu handler for ANY Radix `<ContextMenuTrigger>` in the app, not just PresetRow. Fixed in c88ed1e by moving the contextmenu listener to bubble phase (mousedown/mouseup stay in capture). (b) Clicking Rename selected the existing name for one frame then unselected — Radix's `onCloseAutoFocus` default returns focus to the trigger after inside-interaction. Fixed in bc57aaf by passing `onCloseAutoFocus={(e) => e.preventDefault()}` on `<ContextMenuContent>`.

### 11. Delete
expected: Right-click → Delete → AlertDialog ("Delete preset?" + "Delete {name}? This removes the file from {store} and cannot be undone." + Keep / Delete buttons). Click Delete Preset → file disappears from disk and from section (~200ms via watcher).
result: pass

### 12. Reveal in Finder/Explorer
expected: Right-click → Reveal → OS file manager opens scoped to the preset's parent directory (Linux: file manager to `presets/`; macOS: Finder; Windows: Explorer).
result: pass
note: Verified on WSL2 with the new three-tier reveal strategy. (a) `plugin-opener.revealItemInDir` fails on WSL2 because Linux impl uses dbus + freedesktop FileManager1, neither registered. (b) Initial fallback to `openPath(parentDir)` also failed because `wslu`/`wslview` not installed → `xdg-open` has no GUI handler. (c) Final fix in 6672166: custom Rust command `reveal_in_wsl_explorer` detects WSL via `/proc/version`, translates path with `wslpath -w`, and invokes `explorer.exe /select,<winpath>`. Returns Err on non-WSL so JS falls through to native revealItemInDir on macOS / Windows / Linux desktop. Required Tauri rebuild (Rust binary changed).

### 13. External-write watcher
expected: External `echo '{"format_version":"1.0","kind":"preset","name":"external_test","description":"","resources":{"geometries":[],"power_shapes":[],"fluids":[]},"components":[],"connections":[],"layout":{}}' > ~/.config/com.stream.composer/presets/external_test.scpr` → Library shows the new entry within ~200ms. `rm` the file → entry disappears within ~200ms.
result: pass

### 14. Project switch rebinding (D-06)
expected: With one project open showing Project presets, File → Open a different `.scp` → Project section refreshes to the new project's presets (or empty state). Library unaffected.
result: pass
note: Initial test was misleading — user opened a second `.scp` in the SAME directory as the first and saw the prior preset still listed. This is expected per D-04: the Project store is per-directory (`<project-dir>/presets/`), not per-file. Two `.scp` files in the same folder share the same preset store. After verifying the rebind across DIFFERENT directories, behavior matches the design. Worth surfacing in user-facing copy at some point ("Project presets are scoped to the project's folder") — added to the engineering-voice-copy gap.

### 15. Auto-extend preview (D-12)
expected: Build small graph (Channel + WallTemperature wired by BC edge). Select only the Channel (1 component) → "Save selection as preset…" hidden (selection < 2). Select Channel + Pump (2 components, where one Channel has a WT BC edge). Right-click → Save → WallTemperature renders amber dashed outline (auto-extended) though not explicitly selected. Modal body shows "1 additional component(s) included via BC connections." Discard → amber outline clears immediately.
result: pass

### 16. No-back-compat error toast
expected: External `echo '{"format_version":"0.9","kind":"preset"}' > ~/.config/com.stream.composer/presets/broken.scpr` → broken file does NOT appear in Library (slice catches parse error and skips). DevTools console shows the logged failure (expected per no-back-compat policy).
result: pass

## Summary

total: 16
passed: 16
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

- truth: "Empty-state and help-text copy across Phase 70 surfaces reads as engineering-voice (terse, no consumer-style hand-holding)"
  status: failed
  reason: "User reported on test 3: 'you have to write the texts in a more professional way. It looks bad with so much text.'"
  severity: cosmetic
  test: 3
  scope: phase-wide
  surfaces:
    - "PresetsPanel Library empty state ('No library presets yet.' + 'Save a selection to add your first template.')"
    - "PresetsPanel Project empty state ('Open a project to use the Project store.')"
    - "SavePresetModal name-validation error ('Use only letters, digits, underscores, or hyphens.')"
    - "SavePresetModal collision error ('A preset with this name already exists in the library.')"
    - "Delete AlertDialog body ('Delete {name}? This removes the file from {store} and cannot be undone.')"
    - "SavePresetModal auto-extend preview line ('1 additional component(s) included via BC connections.')"
    - "SavePresetModal Project-disabled helper ('Open a project first.')"
  root_cause: ""
  artifacts: []
  missing: []
  debug_session: ""
