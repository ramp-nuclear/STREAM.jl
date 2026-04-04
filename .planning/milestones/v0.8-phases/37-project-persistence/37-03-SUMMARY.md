---
phase: 37-project-persistence
plan: 03
subsystem: verification
tags: [tauri, save, load, unsaved-changes, recent-files, human-verification]

# Dependency graph
requires:
  - phase: 37-01
    provides: isDirty, currentFilePath, recentFiles state; saveProject/saveProjectAs/loadProject/loadProjectFromPath/newProject actions
  - phase: 37-02
    provides: FileMenu, WelcomeOverlay, keyboard shortcuts, unsaved-changes guard, window title dirty indicator

provides:
  - "Human-verified project persistence: all 6 save/load/guard/recent-files scenarios pass in real Tauri runtime"
  - "Bug fixes committed: permission name correction, React UnsavedChangesDialog, destroy() guard, kbLock mutex, Vite watcher ignore, document.title workaround for WSLg"

affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Toolbar filename/dirty indicator as WSLg-compatible alternative to OS window title (setTitle silently no-ops on WSL2)"
    - "kbLock mutex ref blocks keyboard shortcuts while native GTK dialogs are open to prevent Ctrl+N 'new folder' leak into WebView"
    - "destroy() not close() in onCloseRequested handler — close() re-fires CloseRequested causing re-entrant guard execution"
    - "Zustand subscribe + document.title for title sync as fallback (setTitle confirmed unreliable on WSLg)"

key-files:
  created: []
  modified:
    - gui/src-tauri/capabilities/default.json
    - gui/src/components/FileMenu.tsx
    - gui/src/App.tsx
    - gui/vite.config.ts

key-decisions:
  - "OS window title (setTitle) does not update on WSL2/WSLg — GTK title bar stays static despite document.title change and no Tauri error; toolbar indicator used as primary dirty/filename display"
  - "React UnsavedChangesDialog replaces native Tauri dialog: @tauri-apps/plugin-dialog message() returns void (not button label), making it impossible to branch on Save/Don't Save/Cancel"
  - "destroy() in close guard instead of close(): close() re-fires CloseRequested, causing re-entrant guard execution (double-dialog bug)"
  - "kbLock ref pattern: set true before any dialog await, reset in finally block; blocks keyboard shortcut handler while GTK dialog is open"
  - "**/*.streamgui added to Vite server.watch.ignored: saving a project inside gui/ triggered Vite full page reload, clearing unsaved state mid-session"

patterns-established:
  - "Pattern: destroy() over close() for close guards — prevents CloseRequested re-entrant loop"
  - "Pattern: async mutex ref (kbLock) for GTK dialog sequencing — prevents native dialog keystrokes from leaking into WebView handlers"
  - "Pattern: toolbar as platform-agnostic title display — required on Linux/WSLg where setTitle is unreliable"

requirements-completed: [PERS-01, PERS-02, PERS-03, PERS-04]

# Metrics
duration: human-verification
completed: 2026-04-02
---

# Phase 37 Plan 03: Human Verification Summary

**All 6 project-persistence scenarios confirmed working in real Tauri runtime; 7 bug fixes committed during verification including WSLg title workaround, React close-guard dialog, and kbLock mutex**

## Performance

- **Duration:** human verification session
- **Completed:** 2026-04-02
- **Tasks:** 1
- **Files modified:** 4 (bug fixes only)

## Accomplishments

All 6 verification scenarios passed:

1. **File Menu exists** — File dropdown visible in toolbar with New/Open/Save/Save As items and shortcut labels
2. **Save flow (PERS-01)** — Ctrl+S opens native save dialog on first save; subsequent Ctrl+S saves silently; toolbar shows filename and asterisk for dirty state
3. **Load flow (PERS-02)** — Ctrl+O opens native file picker; selected .streamgui restores canvas nodes and parameters
4. **Unsaved changes guard (PERS-03)** — Window close triggers React dialog with Save/Don't Save/Cancel; Cancel keeps window open; Don't Save closes; Save triggers save dialog then closes
5. **Recent Projects (PERS-04)** — Welcome overlay on empty canvas lists recently saved files; clicking entry loads the project
6. **Save As (Ctrl+Shift+S)** — Opens native save dialog regardless of existing path; toolbar title updates to new filename

## Bug Fixes During Verification

1. `window:allow-set-title` → `core:window:allow-set-title` — Tauri v2 permission namespace correction in `default.json`
2. Native `message()` dialog → `UnsavedChangesDialog` React component — native dialog returns void, cannot branch on button
3. `close()` → `destroy()` in close guard — `close()` re-fires `CloseRequested`, causing double-dialog re-entrant bug
4. Strict Mode async race on `onCloseRequested` — added unlisten cleanup in useEffect return to prevent duplicate listener
5. `document.title` + Zustand `subscribe` for title sync — `setTitle` silently no-ops on WSLg; toolbar indicator added as primary display
6. `kbLock` mutex ref — blocks keyboard shortcuts while GTK native dialogs are open; prevents Ctrl+N "new folder" key leak from GTK into WebView
7. `handleKeyDown` wrapped in `try/catch/finally` — prevents unhandled promise rejections from surfacing to users; kbLock always released

## Deviations from Plan

- Window title update via `setTitle` confirmed non-functional on WSL2/WSLg; toolbar filename/dirty indicator used as the primary (and sufficient) display surface — requirement PERS-01 satisfied via toolbar

## Next Phase Readiness

- All PERS-01..04 requirements implemented and human-verified
- Phase 37 complete — ready for verifier and phase close

---
*Phase: 37-project-persistence*
*Completed: 2026-04-02*
