# Phase 44: Light/Dark Mode - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the discussion.

**Date:** 2026-04-04
**Phase:** 44-light-dark-mode
**Mode:** discuss
**Areas analyzed:** Settings UI placement, Theme persistence, ReactFlow dark mode

## Gray Areas Presented

All three areas were selected by the user for discussion.

| Area | Options Presented | Selected |
|------|------------------|---------|
| Settings UI placement | Toolbar gear icon / FileMenu dropdown / Sun-Moon toggle button | Toolbar gear icon |
| Theme persistence | localStorage / Zustand persist / Tauri plugin-store | localStorage |
| ReactFlow dark mode | colorMode prop / CSS overrides only | colorMode prop |

## Decisions Made

### Settings UI
- **Selected:** Toolbar gear icon (right section) opening a DropdownMenu with Light/Dark/System radio options
- **Reasoning:** Consistent with where app-level settings typically live; doesn't pollute the file-centric FileMenu

### Theme Persistence
- **Selected:** localStorage under key `"stream-composer-theme"`
- **Reasoning:** Zero dependencies, works in Tauri WebView, no new plugins or middleware needed

### ReactFlow Dark Mode
- **Selected:** Pass `colorMode` prop to `<ReactFlow>` + explicit `color` prop to `<Background>`
- **Reasoning:** More robust than CSS class targeting; official ReactFlow dark mode API

## Pre-resolved (no user input needed)

- `.dark` class toggle on `document.documentElement` — already set up in `index.css`
- "System" mode uses `window.matchMedia('(prefers-color-scheme: dark)')` with change listener
- No CSS work needed — all OKLCH tokens already defined in both themes
