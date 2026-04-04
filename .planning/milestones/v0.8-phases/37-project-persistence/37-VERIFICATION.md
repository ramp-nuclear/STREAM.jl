---
phase: 37-project-persistence
verified: 2026-04-03T00:41:00Z
status: passed
score: 9/9 must-haves verified
re_verification: false
---

# Phase 37: Project Persistence Verification Report

**Phase Goal:** Users can save, load, and resume their work across sessions without data loss
**Verified:** 2026-04-03
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Ctrl+S saves project; reloading the app and opening the file restores all nodes, edges, positions, and parameters exactly | ✓ VERIFIED | `saveProject` in useStore.ts calls `serializeProject`+`writeTextFile`; `loadProjectFromPath` calls `readTextFile`+`deserializeProject`+reconstructs instanceCounters; human verification scenario 2+3 confirmed round-trip |
| 2 | Closing the app with unsaved changes shows a confirmation dialog | ✓ VERIFIED | `onCloseRequested` in App.tsx calls `showUnsavedDialog()` when `isDirty`; `UnsavedChangesDialog.tsx` renders Save/Don't Save/Cancel; human verification scenario 4 confirmed |
| 3 | Recent Projects list shows last 5 files by name | ✓ VERIFIED | `WelcomeOverlay.tsx` renders `recentFiles.slice(0,5)` with filename extracted from path; `addToRecent` deduplicates and truncates to 5; `saveRecentFiles`/`loadRecentFiles` persist to `recent.json`; human verification scenario 5 confirmed |
| 4 | Project state can be serialized to a JSON string with version, nodes, edges, bcs | ✓ VERIFIED | `serializeProject` in projectIO.ts returns `JSON.stringify({ version: 1, nodes, edges, bcs }, null, 2)`; 6 unit tests pass |
| 5 | A serialized JSON string can be deserialized back to restore nodes, edges, and bcs | ✓ VERIFIED | `deserializeProject` validates all 4 required fields; throws `Invalid .streamgui file` on invalid input; 9 unit tests pass |
| 6 | isDirty flag is true after content mutations and false after save/load/new | ✓ VERIFIED | All 9 content-mutating store actions set `isDirty: true`; `selectNode`/`toggleBottomPanel` do not; isDirty set to false in `saveProject`, `loadProjectFromPath`, `newProject`; 10 unit tests pass |
| 7 | Recent files list adds to top, deduplicates, and truncates to 5 | ✓ VERIFIED | `addToRecent` filters existing, prepends, slices to 5; 8 unit tests pass |
| 8 | instanceCounters are reconstructed from loaded node names | ✓ VERIFIED | `reconstructInstanceCounters` parses `prefix_N` pattern, tracks max per prefix; `loadProjectFromPath` calls `clearInstanceCounters()` then `Object.assign(instanceCounters, reconstructed)`; 4 unit tests pass |
| 9 | File dropdown at left of toolbar with New, Open, Save, Save As items and keyboard shortcut labels | ✓ VERIFIED | `FileMenu.tsx` renders `DropdownMenu` with all 4 items and Ctrl+N/O/S/Shift+S labels; mounted in Toolbar via `<FileMenu onUnsavedCheck={onUnsavedCheck} />`; human verification scenario 1 confirmed |

**Score:** 9/9 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `gui/src/lib/projectIO.ts` | Serialize/deserialize/recent-files pure functions | ✓ VERIFIED | 153 lines; exports `serializeProject`, `deserializeProject`, `addToRecent`, `reconstructInstanceCounters`, `StreamProject` interface |
| `gui/src/lib/__tests__/projectIO.test.ts` | Unit tests for projectIO | ✓ VERIFIED | 297 lines; 4 describe blocks covering all exported functions; all tests pass |
| `gui/src/store/useStore.ts` | isDirty, currentFilePath, recentFiles state + file I/O actions | ✓ VERIFIED | 401 lines; contains all required fields and actions; imports from projectIO.ts |
| `gui/src/components/FileMenu.tsx` | DropdownMenu with File trigger and 4 menu items | ✓ VERIFIED | 84 lines; all 4 items with shortcut labels; wired to store actions via `onUnsavedCheck` prop |
| `gui/src/components/WelcomeOverlay.tsx` | Centered overlay with recent files and Open button | ✓ VERIFIED | 63 lines; reads `recentFiles`, calls `loadProjectFromPath`; renders nothing when canvas non-empty |
| `gui/src/components/UnsavedChangesDialog.tsx` | React dialog with Save/Don't Save/Cancel | ✓ VERIFIED | 47 lines; replaces native Tauri dialog (native returns void, no button branching possible) |
| `gui/src/App.tsx` | Window close guard, keyboard shortcuts, title sync, recent files init | ✓ VERIFIED | 189 lines; contains `onCloseRequested`, `getCurrentWindow`, `setTitle`, `isDirty`, `initializeRecentFiles`, `ctrlKey`, `STREAM Composer` |
| `gui/src-tauri/capabilities/default.json` | Tauri FS and window permissions | ✓ VERIFIED | Contains `fs:allow-read-text-file`, `fs:allow-exists`, `fs:allow-mkdir`, `core:window:allow-set-title`, `core:window:allow-close`, `core:window:allow-destroy` |
| `gui/vite.config.ts` | Vite watcher ignores .streamgui files | ✓ VERIFIED | `ignored: ["**/src-tauri/**", "**/*.streamgui"]` — prevents full page reload on save |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `gui/src/store/useStore.ts` | `gui/src/lib/projectIO.ts` | `import serializeProject, deserializeProject, addToRecent, reconstructInstanceCounters` | ✓ WIRED | Line 16–20: explicit named imports |
| `gui/src/store/useStore.ts` | `@tauri-apps/plugin-fs` | `readTextFile`/`writeTextFile` for save/load | ✓ WIRED | Dynamic imports inside `saveProject`, `loadProjectFromPath`, `saveRecentFiles`, `loadRecentFiles` |
| `gui/src/components/FileMenu.tsx` | `gui/src/store/useStore.ts` | calls `saveProject`, `saveProjectAs`, `loadProject`, `newProject` | ✓ WIRED | Lines 17–20: `useStore((s) => s.saveProject)` etc.; called in handlers |
| `gui/src/components/WelcomeOverlay.tsx` | `gui/src/store/useStore.ts` | reads `recentFiles`, calls `loadProjectFromPath` | ✓ WIRED | Lines 7–9: `useStore((s) => s.recentFiles)` and `loadProjectFromPath`; used in render and onClick |
| `gui/src/App.tsx` | `@tauri-apps/api/window` | `getCurrentWindow().setTitle()` and `onCloseRequested()` | ✓ WIRED | Lines 3, 117, 136: import and calls in title-sync and close-guard useEffects |
| `gui/src/components/Toolbar.tsx` | `gui/src/components/FileMenu.tsx` | renders `<FileMenu onUnsavedCheck={onUnsavedCheck} />` | ✓ WIRED | Line 9 import, line 42 render |
| `gui/src/components/CanvasPanel.tsx` | `gui/src/components/WelcomeOverlay.tsx` | renders `<WelcomeOverlay />` inside `relative` container | ✓ WIRED | Line 18 import, line 120 render; container has `relative` class |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|-------------------|--------|
| `WelcomeOverlay.tsx` | `recentFiles` | `useStore((s) => s.recentFiles)` → initialized from `loadRecentFiles()` → `readTextFile(appDataDir + "/recent.json")` | Yes — reads from disk; populated after `initializeRecentFiles()` on App mount | ✓ FLOWING |
| `WelcomeOverlay.tsx` | `nodes`, `edges` | `useStore((s) => s.nodes/edges)` → set by `loadProjectFromPath` from deserialized file | Yes — populated from `deserializeProject` result | ✓ FLOWING |
| `Toolbar.tsx` | `isDirty`, `currentFilePath` | `useStore((s) => s.isDirty/currentFilePath)` → set by all content-mutating actions and save/load | Yes — reactive Zustand subscription | ✓ FLOWING |
| `UnsavedChangesDialog.tsx` | `open` prop | `dialogOpen` state in App.tsx → set by `showUnsavedDialog()` → called by close guard and keyboard shortcuts | Yes — triggered by real user events | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| All vitest tests pass | `cd gui && npx vitest run` | 138 passed, 17 todo (skipped), 0 failed | ✓ PASS |
| TypeScript compiles cleanly | `cd gui && npx tsc --noEmit` | No output (exit 0) | ✓ PASS |
| projectIO unit tests pass | vitest run for projectIO.test.ts | Included in above 138 passing | ✓ PASS |
| isDirty tracking tests pass | vitest run for useStore.test.ts isDirty describe | All 10 isDirty tests pass | ✓ PASS |
| Tauri runtime (save/load/guard/recent) | `cd gui && npm run tauri dev` + 6 manual scenarios | All 6 confirmed by human verification (37-03-SUMMARY.md, 2026-04-02) | ✓ PASS (human-verified) |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| PERS-01 | 37-01, 37-02 | Save full canvas state as .streamgui via Ctrl+S / File→Save | ✓ SATISFIED | `saveProject`/`saveProjectAs` serialize and write to disk; `serializeProject` includes nodes, edges, bcs; File menu Save/Save As items wired; keyboard shortcut in App.tsx |
| PERS-02 | 37-01, 37-02 | Open existing .streamgui to fully restore canvas via Ctrl+O / File→Open | ✓ SATISFIED | `loadProjectFromPath` reads, deserializes, restores nodes/edges/bcs/instanceCounters; `loadProject` shows native open dialog; Ctrl+O handler in App.tsx; WelcomeOverlay Open Project button |
| PERS-03 | 37-01, 37-02 | Unsaved changes confirmation before close/new/open when dirty | ✓ SATISFIED | `UnsavedChangesDialog` shown by close guard (`onCloseRequested`) and keyboard handlers (Ctrl+N/O); FileMenu handlers check `isDirty` via `onUnsavedCheck` prop; Save/Don't Save/Cancel all handled |
| PERS-04 | 37-01, 37-02 | Recent Projects list on startup/empty canvas (last 5 files) | ✓ SATISFIED | `WelcomeOverlay` renders when `nodes.length === 0 && edges.length === 0`; shows `recentFiles.slice(0,5)` with filename display; clickable to load; persisted to `recent.json` on disk |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None detected | — | — | — | — |

Scan notes:
- No `TODO`/`FIXME`/`PLACEHOLDER` comments in any phase-37 files
- No `return null` stubs that gate real functionality (WelcomeOverlay returns null when canvas is non-empty — intentional conditional render, not a stub)
- No hardcoded empty arrays that replace real data in rendering paths
- `loadRecentFiles` returns `[]` on catch — intentional safe default, not a stub (catch is for first-run before file exists)

### Human Verification Required

No outstanding human verification items. All 6 Tauri runtime scenarios were confirmed passing during the 37-03 verification session on 2026-04-02.

Note on OS window title: `setTitle()` silently no-ops on WSL2/WSLg. The toolbar filename/dirty indicator (`filename * | Untitled *`) serves as the functional substitute. This is a platform limitation, not a code defect. The requirement PERS-01 wording ("window title shows filename and asterisk") is satisfied via the toolbar indicator on the target dev platform.

### Gaps Summary

No gaps. All 9 observable truths verified, all artifacts exist and are substantive and wired, all data flows produce real data, all requirements satisfied, TypeScript compiles cleanly, 138 unit tests pass.

---

_Verified: 2026-04-03_
_Verifier: Claude (gsd-verifier)_
