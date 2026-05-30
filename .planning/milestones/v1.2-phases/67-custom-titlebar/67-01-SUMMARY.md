---
phase: 67-custom-titlebar
plan: 01
subsystem: gui/tauri
tags:
  - tauri
  - frameless-window
  - capabilities
  - plugin-os
  - infrastructure
requirements:
  - D-04
  - D-14
  - D-15
  - D-23
  - D-25
dependency_graph:
  requires: []
  provides:
    - "@tauri-apps/plugin-os JS binding installed and reachable"
    - "tauri-plugin-os Rust plugin registered in builder chain"
    - "5 window/os capability permissions granted (minimize, toggle-maximize, start-dragging, is-maximized, os:default)"
    - "decorations: false on main window (OS chrome removed)"
    - "gui/public/32x32.png reachable from Vite at /32x32.png"
  affects:
    - "Plan 02 (WindowControls.tsx) — can now safely call getCurrentWindow().minimize/toggleMaximize/close and platform()"
    - "Plan 03 (CustomTitlebar.tsx) — drag region IPC + <img src=\"/32x32.png\"> will resolve"
tech_stack:
  added:
    - "@tauri-apps/plugin-os@2.x (npm)"
    - "tauri-plugin-os = \"2\" (Cargo, resolved to v2.3.2)"
  patterns:
    - "4-layer Tauri plugin registration (npm + Cargo + lib.rs builder + capabilities permissions)"
key_files:
  created:
    - gui/public/32x32.png
  modified:
    - gui/package.json
    - gui/package-lock.json
    - gui/src-tauri/Cargo.toml
    - gui/src-tauri/Cargo.lock
    - gui/src-tauri/src/lib.rs
    - gui/src-tauri/capabilities/default.json
    - gui/src-tauri/tauri.conf.json
decisions:
  - "Used unpinned tauri-plugin-os = \"2\" matching the rest of the Tauri plugin cluster; cargo resolved to v2.3.2 cleanly"
  - "Cargo.lock regeneration deferred from Task 1 to Task 3 (committed alongside the cargo check gate output)"
metrics:
  duration_sec: 167
  duration_human: "2m 47s"
  completed_date: "2026-05-16"
  tasks_total: 3
  tasks_done: 3
  files_created: 1
  files_modified: 7
---

# Phase 67 Plan 01: Tauri 4-layer foundation Summary

Landed the four-layer Tauri foundation for the custom titlebar: installed `@tauri-apps/plugin-os` and `tauri-plugin-os v2.3.2` at every layer (npm + Cargo + Rust builder + capabilities/default.json), set `decorations: false` on the main window, and copied `32x32.png` into `gui/public/` so Vite can serve it. `cargo check` green.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Install `@tauri-apps/plugin-os` (npm) and `tauri-plugin-os` (Cargo) | `72c4ef3` | `gui/package.json`, `gui/package-lock.json`, `gui/src-tauri/Cargo.toml` |
| 2 | Register `tauri_plugin_os::init()` in `lib.rs` + add 5 capability permissions + set `decorations: false` | `91beb15` | `gui/src-tauri/src/lib.rs`, `gui/src-tauri/capabilities/default.json`, `gui/src-tauri/tauri.conf.json` |
| 3 | Copy `32x32.png` to `gui/public/` + `cargo check` compile gate | `4a8e921` | `gui/public/32x32.png` (new), `gui/src-tauri/Cargo.lock` |

## Precise Locations

### `gui/src-tauri/src/lib.rs`

`.plugin(tauri_plugin_os::init())` inserted at line 26, immediately after `.plugin(tauri_plugin_fs::init())` and before `.invoke_handler(...)`. Builder chain is now:

```rust
tauri::Builder::default()
    .plugin(tauri_plugin_opener::init())
    .plugin(tauri_plugin_dialog::init())
    .plugin(tauri_plugin_fs::init())
    .plugin(tauri_plugin_os::init())   // NEW (Phase 67 D-23)
    .invoke_handler(tauri::generate_handler![greet, is_pid_alive, get_pid])
    .run(tauri::generate_context!())
    .expect("error while running tauri application");
```

### `gui/src-tauri/capabilities/default.json`

Five new permission strings appended to the `permissions` array (lines 29–33), directly after the existing `core:window:allow-destroy` entry. Final cluster of `core:window:*` + `os:*` permissions:

```json
"core:window:allow-set-title",
"core:window:allow-close",
"core:window:allow-destroy",
"core:window:allow-minimize",
"core:window:allow-toggle-maximize",
"core:window:allow-start-dragging",
"core:window:allow-is-maximized",
"os:default"
```

### `gui/src-tauri/tauri.conf.json`

`"decorations": false` added at line 20, as the final key of `app.windows[0]` (after `minHeight`):

```json
"app": {
  "windows": [
    {
      "title": "STREAM Composer",
      "width": 1280,
      "height": 800,
      "minWidth": 800,
      "minHeight": 600,
      "decorations": false
    }
  ],
  ...
}
```

### `gui/src-tauri/Cargo.toml`

`tauri-plugin-os = "2"` appended at line 27, directly after `tauri-plugin-fs = "2.4.5"`. Cargo resolved this to v2.3.2 in `Cargo.lock`.

### `gui/public/32x32.png`

974-byte literal byte-for-byte copy of `gui/src-tauri/icons/32x32.png` (verified with `cmp`). Reachable from Vite as `/32x32.png` at runtime.

## Verification

| Check | Status |
|-------|--------|
| `cd gui && cargo check --manifest-path src-tauri/Cargo.toml` | PASS (`Finished dev profile [unoptimized + debuginfo] target(s) in 37.93s`) |
| `python3 -c 'import json; json.load(open("gui/src-tauri/tauri.conf.json"))'` | PASS |
| `python3 -c 'import json; json.load(open("gui/src-tauri/capabilities/default.json"))'` | PASS |
| `cmp gui/src-tauri/icons/32x32.png gui/public/32x32.png` | PASS (identical) |
| All five new capability strings present | PASS (all five `grep -q` checks passed) |
| `decorations: false` set on `app.windows[0]` | PASS |

`tauri-plugin-os v2.3.2` resolved cleanly; no compile warnings or errors introduced by the four-layer change. The full Tauri plugin cluster (opener, dialog, fs, os) compiles together.

## Deviations from Plan

None — plan executed exactly as written.

The plan envisioned `Cargo.lock` regenerating "as a side effect" of Task 1, but in practice the lockfile only updates when Cargo actually resolves the dependency graph — which happens during Task 3's `cargo check` gate. This is consistent with the plan's note that "Cargo.lock will be regenerated by Task 3's compile gate," so it is in-spec rather than a deviation. `Cargo.lock` was committed alongside Task 3.

## Authentication Gates

None.

## Known Stubs

None — this plan is pure infrastructure plumbing. No UI components rendered; no placeholder data.

## Plan 03 UAT Awareness

For the eventual manual UAT (Plan 03 checkpoint):

- The OS chrome will be **gone** the moment `npm run tauri dev` runs from this commit forward. No custom titlebar exists yet (Plans 02 and 03 build it). This means the window has no minimize/maximize/close buttons visible until Plan 03 ships. **Don't panic** when the dev window opens with no chrome — it's expected.
- WSLg edge-resize is the known dominant risk (Pitfall 3 in 67-RESEARCH.md). UAT must specifically probe edge-resize. Plan 67-03 Task 4 captures this as a documented UAT item per D-18 (defer; no pre-emptive code fix).
- `tauri-plugin-os v2.3.2` is the active resolved version — slightly newer than the `2.0.x` line referenced in some research notes; behavior is API-compatible.

## Self-Check: PASSED

- gui/package.json: FOUND (`grep '@tauri-apps/plugin-os'` matches)
- gui/src-tauri/Cargo.toml: FOUND (`grep 'tauri-plugin-os = "2"'` matches)
- gui/src-tauri/src/lib.rs: FOUND (`grep 'tauri_plugin_os::init()'` matches)
- gui/src-tauri/capabilities/default.json: FOUND (all 5 new permission strings present)
- gui/src-tauri/tauri.conf.json: FOUND (`grep '"decorations": false'` matches; JSON parses)
- gui/public/32x32.png: FOUND (byte-identical to source)
- Commit 72c4ef3: FOUND in git log
- Commit 91beb15: FOUND in git log
- Commit 4a8e921: FOUND in git log
