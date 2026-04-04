# Phase 37: Project Persistence - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-02
**Phase:** 37-project-persistence
**Areas discussed:** File menu surface, Recent projects UX, Unsaved changes guard

---

## File menu surface

| Option | Description | Selected |
|--------|-------------|----------|
| File dropdown menu | File ▾ button at left of Toolbar with New/Open/Save/Save As items + keyboard shortcuts | ✓ |
| Keyboard-only + minimal buttons | Ctrl+S/Ctrl+O with icon buttons, no dropdown menu | |

**User's choice:** File dropdown menu

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — Save + Save As | Save overwrites current file; Save As always prompts for path | ✓ |
| Save always asks (single dialog) | Ctrl+S always opens file save dialog | |

**User's choice:** Yes — Save + Save As (standard desktop behavior)

---

## Recent projects UX

| Option | Description | Selected |
|--------|-------------|----------|
| Welcome overlay | Centered overlay on empty canvas with app name + recent files list + Open button | ✓ |
| File menu only (no screen) | Recent files as submenu under File ▾ only | |

**User's choice:** Welcome overlay

| Option | Description | Selected |
|--------|-------------|----------|
| App data dir JSON | recent.json in app_data_dir via plugin-fs | ✓ |
| tauri-plugin-store | Official Tauri key-value plugin | |

**User's choice:** App data dir JSON (no new plugin needed)

---

## Unsaved changes guard

| Option | Description | Selected |
|--------|-------------|----------|
| Window title asterisk | Title shows `STREAM Composer*` when dirty | ✓ |
| Toolbar badge/dot | Orange dot or 'Unsaved' badge in toolbar | |

**User's choice:** Window title asterisk

| Option | Description | Selected |
|--------|-------------|----------|
| Tauri onCloseRequested | Intercept native close event, show Save/Discard/Cancel dialog | ✓ |
| beforeunload only | Browser beforeunload event (unreliable in Tauri production) | |

**User's choice:** Tauri onCloseRequested

---

## Claude's Discretion

- recent.json error handling strategy
- Welcome overlay when no recent files exist
- instanceCounters reset on New
- Keyboard shortcut implementation location (App.tsx vs. custom hook)

## Deferred Ideas

None.
