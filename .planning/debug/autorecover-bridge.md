---
status: resolved
resolved: 2026-05-21
resolved_in: "Phase 65 follow-up — capabilities/default.json now grants fs:scope-appdata-recursive, fs:allow-appdata-write-recursive, fs:allow-remove, fs:allow-read-dir, fs:allow-watch, fs:allow-unwatch, fs:scope-appconfig-recursive, plus an explicit fs:scope override for $APPDATA/STREAM-Composer/autorecover/**. AutoRecover writes succeed; sidecars land in ~/.local/share/com.stream.composer/STREAM-Composer/autorecover/."
trigger: "Phase 65 UAT Tests 16 + 17 (AutoRecover) — sidecar files never written; window.__TAURI__.core undefined; crash modal never appears"
created: 2026-05-15T12:00:00Z
updated: 2026-05-21
---

## Current Focus

hypothesis: "AutoRecover fs writes to $APPDATA are blocked by the fs plugin scope ACL. tauri-v2 fs plugin requires explicit appdata write/read scope permissions (fs:scope-appdata-recursive + fs:allow-appdata-write-recursive); only home-recursive READ scope is granted, and even that grants read, not write."
test: "Compare working write path (saveProject -> user-chosen filePath via dialog.save) against failing write path (autoRecover -> appDataDir-derived path). Inspect gui/src-tauri/capabilities/default.json scope grants."
expecting: "Capability config will list fs:scope-home-recursive but no appdata scope and no recursive write scope; user-dialog path bypasses ACL via dialog plugin implicit scope; appDataDir path does not."
next_action: "Return structured root cause to caller — do not patch (diagnose-only mode)."

## Symptoms

expected:
  - "Editing a node produces a .scp.autosave in $APPDATA/STREAM-Composer/autorecover/ within ~2s; saved -> sidecar cleared."
  - "After kill -9 with unsaved edits and relaunch, AutoRecoverRestoreModal blocks the workspace."
actual:
  - "~/.config/com.stream.composer DOES NOT EXIST."
  - "~/.local/share/com.stream.composer contains only WebKitCache/localstorage — no autorecover/ subdir, no *.autosave files, no *.lock files."
  - "window.__TAURI__.core.invoke('get_pid') throws 'Cannot read properties of undefined (reading invoke)'."
  - "After kill -9 + relaunch, no restore modal — workspace loads clean."
errors:
  - "DevTools: TypeError: Cannot read properties of undefined (reading 'invoke') when accessing window.__TAURI__.core"
reproduction:
  - "UAT 65, Tests 16/17 — npm run tauri dev, drop nodes, then ls ~/.config and ~/.local/share for app id; or kill -9 the binary and relaunch."
started: "Phase 65 UAT 2026-05-15 — Plans 07+08 shipped with full vitest coverage but vitest mocks all Tauri IPC; runtime IPC never exercised before UAT."

## Eliminated

- hypothesis: "tauri_plugin_fs not registered in lib.rs"
  evidence: "gui/src-tauri/src/lib.rs:25 — .plugin(tauri_plugin_fs::init()) IS present in Builder."
  timestamp: 2026-05-15T12:10:00Z

- hypothesis: "@tauri-apps/api/core / @tauri-apps/plugin-fs ES module imports fail (Tauri v2 bridge not exposed at all)"
  evidence: "saveProject (useStore.ts:2064) uses the SAME dynamic-import pattern (`import('@tauri-apps/plugin-fs')` + writeTextFile) and SUCCEEDS in Test 15 and Test 16's 'save the project' step. ES module imports of @tauri-apps/* resolve and execute correctly. window.__TAURI__.core being undefined is the unrelated `withGlobalTauri` default — irrelevant to ES imports."
  timestamp: 2026-05-15T12:12:00Z

- hypothesis: "initAutoRecover() never called from App.tsx"
  evidence: "gui/src/App.tsx:125 — clean-launch branch calls `const { teardown } = await initAutoRecover();`. User reaches the workspace (no boot-splash hang), which means setRestoreCandidates([]) fired and initAutoRecover was awaited."
  timestamp: 2026-05-15T12:14:00Z

- hypothesis: "isDirty subscription never fires when adding a node"
  evidence: "useStore.ts:1117 — `set({ nodes: [...get().nodes, newNode], isDirty: true })` on addNode. Zustand subscribe (useStore.ts:2691) fires on every state change. Path is wired."
  timestamp: 2026-05-15T12:16:00Z

- hypothesis: "Tauri 'get_pid' / 'is_pid_alive' commands not in generate_handler!"
  evidence: "lib.rs:26 — `.invoke_handler(tauri::generate_handler![greet, is_pid_alive, get_pid])` — both registered. Permission for these custom commands is granted via `core:default`."
  timestamp: 2026-05-15T12:17:00Z

## Evidence

- timestamp: 2026-05-15T12:08:00Z
  checked: "gui/src-tauri/capabilities/default.json"
  found: |
    Permissions list:
      core:default, opener:default, dialog:default,
      fs:default, fs:allow-write-text-file, fs:allow-read-text-file,
      fs:allow-exists, fs:allow-mkdir, fs:scope-home-recursive,
      core:window:allow-set-title/close/destroy
    NOTABLY ABSENT:
      - fs:scope-appdata-recursive   (READ scope for $APPDATA)
      - fs:allow-appdata-write-recursive  (WRITE scope for $APPDATA)
      - fs:allow-remove             (silent-fail today, but needed for clearSidecar / clearLockfile)
      - fs:allow-read-dir / fs:scope-appdata-recursive (needed for enumerateSidecars)
  implication: "The fs plugin enforces a scoped ACL: every fs command must be authorized by both an operation permission (fs:allow-write-text-file) AND a scope permission for the target path. fs:scope-home-recursive is a READ scope, not write, AND in Tauri's path-base model $APPDATA is a distinct base directory from $HOME even when it physically resolves under home on Linux (~/.local/share/<bundle id>/). Per Tauri v2 fs docs: fs:scope-appdata-recursive + fs:allow-appdata-write-recursive are required to read/write $APPDATA."

- timestamp: 2026-05-15T12:09:00Z
  checked: "gui/src/lib/autoRecover.ts paths"
  found: |
    All autoRecover writes go through getSidecarPath / getLockfilePath, both of which compute
        appDataDir() + 'STREAM-Composer/autorecover/<basename>'
    via @tauri-apps/api/path appDataDir().
    All writes are inside try/catch with silent failure (lines 121-123, 137-139, 150-152, 197-199, 213-216, 228-230, 170-172).
  implication: "Every fs op (mkdir, writeTextFile, readTextFile, readDir, remove) targets $APPDATA. Each is silently caught — the ACL rejection raises a Tauri error string that's discarded. The user observes zero files and zero error indication."

- timestamp: 2026-05-15T12:11:00Z
  checked: "Working write path vs. failing write path"
  found: |
    saveProject (useStore.ts:2087) writes to `currentFilePath` — a path returned from
    `@tauri-apps/plugin-dialog`'s save() picker. Tauri's dialog plugin returns paths inside
    a one-shot grant scope: the fs plugin honors writes to paths the user just selected via
    the dialog, regardless of static scope. This is why Test 15 (save .scp + reload) passes.
    autoRecover never asks the user — it constructs the $APPDATA path itself, so the dialog
    one-shot doesn't apply, and the static fs scope rejects it.
  implication: "Diagnostic discriminator: 'Save .scp works, autoRecover writes don't' is consistent with — and pretty much only explained by — the static fs scope missing the $APPDATA base. This is the load-bearing piece of evidence."

- timestamp: 2026-05-15T12:13:00Z
  checked: "gui/src-tauri/tauri.conf.json"
  found: |
    No app.withGlobalTauri key (defaults false in Tauri v2 -> window.__TAURI__ NOT exposed).
    No app.security.csp restrictions (csp: null).
    No app.security.assetProtocol or capabilities override.
  implication: "withGlobalTauri=false explains why `window.__TAURI__.core` is undefined in devtools — that's the v2 default and is a RED HERRING. ES module imports of @tauri-apps/* still work; they go through the v2 IPC bridge (postMessage / IPC handlers) that's always on. No tauri.conf change is needed for AutoRecover to work — only the capabilities file."

- timestamp: 2026-05-15T12:15:00Z
  checked: "gui/src/store/useStore.ts initAutoRecover() — line 2647-2709"
  found: |
    initAutoRecover does: invoke('get_pid') -> writes lockfile -> subscribes to isDirty -> debounced 2s -> writeSidecar.
    All Tauri calls wrapped in try/catch. invoke('get_pid') failing falls through with pid=0 (line 2660-2662); writeLockfile(0) still fails on ACL silently.
  implication: "Even if 'get_pid' command itself worked (it should — core:default authorizes custom commands), the subsequent writeLockfile and writeSidecar calls into the fs plugin would be the actual failure points. Silent-failure pattern masks the entire chain."

- timestamp: 2026-05-15T12:18:00Z
  checked: "Cargo.toml — tauri-plugin-fs version"
  found: "tauri-plugin-fs = 2.4.5 — current; permission identifiers (fs:scope-appdata-recursive, fs:allow-appdata-write-recursive) are available in this version per plugins-workspace/v2 autogenerated reference."
  implication: "No version bump needed; just permission additions in capabilities."

## Resolution

root_cause: |
  AutoRecover's fs writes to $APPDATA (~/.local/share/com.stream.composer/STREAM-Composer/autorecover/)
  are rejected by the tauri-plugin-fs scope ACL because `gui/src-tauri/capabilities/default.json`
  does not grant the appdata scope (`fs:scope-appdata-recursive`) nor the appdata recursive write
  permission (`fs:allow-appdata-write-recursive`). The only scope granted is
  `fs:scope-home-recursive`, which (per Tauri v2 fs docs) is a READ scope for the home base
  directory — separate from the $APPDATA base, and not a write scope. Every fs call from
  autoRecover.ts (mkdir, writeTextFile, readTextFile, readDir, remove) raises a Tauri ACL
  error that is swallowed by the module's `try { ... } catch { }` silent-failure pattern,
  producing exactly the observed symptom: zero files on disk, no errors surfaced in devtools
  or in the dev terminal.

  saveProject's `writeTextFile(currentFilePath, ...)` works because `currentFilePath` is the
  path returned by `@tauri-apps/plugin-dialog`'s save() picker, which grants a one-shot
  implicit fs scope to the user-selected path — that path is NOT subject to the static
  capability scope. AutoRecover paths are constructed from `appDataDir()` and have no such
  bypass.

  `window.__TAURI__.core` being undefined in devtools is a RED HERRING — it is the Tauri v2
  default behavior because `app.withGlobalTauri` is unset in tauri.conf.json. ES module
  imports of `@tauri-apps/api/core` and `@tauri-apps/plugin-fs` continue to work through the
  v2 IPC bridge regardless. Reaching for `window.__TAURI__` is a v1 idiom; in v2 you import.

fix: ""
verification: ""
files_changed: []
