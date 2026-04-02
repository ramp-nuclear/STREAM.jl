---
phase: 37-project-persistence
plan: 02
subsystem: ui
tags: [react, tauri, typescript, shadcn, zustand, dropdown-menu, keyboard-shortcuts]

# Dependency graph
requires:
  - phase: 37-01
    provides: isDirty, currentFilePath, recentFiles state; saveProject/saveProjectAs/loadProject/loadProjectFromPath/newProject actions; initializeRecentFiles export

provides:
  - "FileMenu.tsx: DropdownMenu with File trigger and New/Open/Save/Save As items and keyboard shortcut labels"
  - "WelcomeOverlay.tsx: centered card on empty canvas with recent files list and Open Project button"
  - "promptUnsavedChanges: reusable 3-button dialog function exported from FileMenu"
  - "Toolbar.tsx updated: FileMenu rendered at left before Code button"
  - "CanvasPanel.tsx updated: WelcomeOverlay rendered as sibling to ReactFlow on relative-positioned container"
  - "App.tsx updated: global keyboard shortcuts (Ctrl+S/O/N/Shift+S), window title sync, close guard, recent files init"

affects:
  - 37-03 (UI review — all file surfaces from this plan are subject to audit)

# Tech tracking
tech-stack:
  added:
    - "@radix-ui/react-dropdown-menu (via shadcn dropdown-menu)"
    - "gui/src/components/ui/dropdown-menu.tsx"
  patterns:
    - "promptUnsavedChanges exported from FileMenu and reused in App.tsx for DRY unsaved-changes guard"
    - "Ctrl+Shift+S check before Ctrl+S in keydown handler to prevent shiftKey consuming both handlers"
    - "isDirty read via useStore.getState() inside async keydown handler to avoid stale closure"

key-files:
  created:
    - gui/src/components/FileMenu.tsx
    - gui/src/components/WelcomeOverlay.tsx
    - gui/src/components/ui/dropdown-menu.tsx
  modified:
    - gui/src/components/Toolbar.tsx
    - gui/src/components/CanvasPanel.tsx
    - gui/src/App.tsx

key-decisions:
  - "Ctrl+Shift+S checked before Ctrl+S in the keydown handler: JavaScript keydown fires for both; if shiftKey is not checked first, Ctrl+Shift+S triggers Ctrl+S and then Ctrl+Shift+S — leading to double-save"
  - "isDirty shadowed as 'dirty' inside async closures: avoids naming conflict with outer useStore((s) => s.isDirty) reactive subscription; getState() gives current value without stale closure"
  - "promptUnsavedChanges exported from FileMenu.tsx: same dialog needed in FileMenu handlers and App.tsx close guard; single export point avoids duplication"

patterns-established:
  - "Pattern: Ctrl+Shift before Ctrl in keydown — always check more-specific modifier combinations (shiftKey) before less-specific ones when handling keyboard shortcuts"
  - "Pattern: useStore.getState() in async handlers — avoids stale closure on isDirty/other state read inside async event handlers; reactive useStore((s) => s.x) for rendering only"

requirements-completed: [PERS-01, PERS-02, PERS-03, PERS-04]

# Metrics
duration: 5min
completed: 2026-04-02
---

# Phase 37 Plan 02: UI Surfaces for Project Persistence Summary

**FileMenu dropdown with 4 items and unsaved-changes guard, WelcomeOverlay with recent files, global keyboard shortcuts (Ctrl+S/O/N/Shift+S), window title dirty indicator, and close guard — all wired into Toolbar, CanvasPanel, and App.tsx**

## Performance

- **Duration:** 5 min
- **Started:** 2026-04-02T18:57:09Z
- **Completed:** 2026-04-02T19:00:00Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- Created `FileMenu.tsx` with shadcn DropdownMenu containing New/Open/Save/Save As items, each with right-aligned keyboard shortcut labels; isDirty guard in handleNew/handleOpen with 3-button native dialog
- Created `WelcomeOverlay.tsx` as absolute-positioned centered card that renders only when canvas is empty; shows up to 5 recent files (filename only, clickable to load) or "no projects" hint copy
- Updated `App.tsx` with 4 useEffect hooks: global keyboard shortcuts, window title sync (dirty asterisk + filename), window close guard, and recent files initialization on mount

## Task Commits

Each task was committed atomically:

1. **Task 1: Install shadcn dropdown-menu, create FileMenu and WelcomeOverlay components** - `9d95745` (feat)
2. **Task 2: Add keyboard shortcuts, window title sync, and close guard in App.tsx** - `a05a133` (feat)

**Plan metadata:** (created next)

## Files Created/Modified
- `gui/src/components/FileMenu.tsx` — DropdownMenu with File trigger, 4 menu items with shortcut labels, promptUnsavedChanges export
- `gui/src/components/WelcomeOverlay.tsx` — Centered overlay card, conditional on empty canvas, recent files list, Open Project button
- `gui/src/components/ui/dropdown-menu.tsx` — shadcn dropdown-menu component (installed via npx shadcn add)
- `gui/src/components/Toolbar.tsx` — Added FileMenu import and render at left side before Code button
- `gui/src/components/CanvasPanel.tsx` — Added WelcomeOverlay import and render; outer div className gains `relative`
- `gui/src/App.tsx` — Added 4 useEffect hooks: keyboard shortcuts, title sync, close guard, initializeRecentFiles

## Decisions Made
- Ctrl+Shift+S is checked before Ctrl+S in the keydown handler to prevent shiftKey from consuming both handlers
- isDirty state inside async keydown and close handlers is read via `useStore.getState()` (not stale reactive subscription)
- `promptUnsavedChanges` exported from FileMenu.tsx and imported by App.tsx — single source of truth for the 3-button dialog

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None — no external service configuration required. UI components render immediately with next `cargo tauri dev`.

## Next Phase Readiness
- All PERS-01..04 requirements complete
- FileMenu, WelcomeOverlay, keyboard shortcuts, title sync, and close guard fully functional
- Phase 37-03 (UI review / code-gen integration) can proceed

## Self-Check: PASSED

- `gui/src/components/FileMenu.tsx` — FOUND
- `gui/src/components/WelcomeOverlay.tsx` — FOUND
- `gui/src/components/ui/dropdown-menu.tsx` — FOUND
- `gui/src/components/Toolbar.tsx` — FOUND (contains FileMenu)
- `gui/src/components/CanvasPanel.tsx` — FOUND (contains WelcomeOverlay)
- `gui/src/App.tsx` — FOUND (contains onCloseRequested, getCurrentWindow, setTitle, isDirty, promptUnsavedChanges, ctrlKey, initializeRecentFiles, STREAM Composer)
- Commit `9d95745` — FOUND
- Commit `a05a133` — FOUND

---
*Phase: 37-project-persistence*
*Completed: 2026-04-02*
