---
phase: 36-code-generation
plan: 02
subsystem: ui
tags: [tauri, react, zustand, shadcn, code-generation, file-export]

requires:
  - phase: 36-01
    provides: generateCode pure function and BCEntry type
provides:
  - Toolbar with Code toggle and Export button
  - Collapsible bottom panel with Code/BCs tabs
  - Live code preview via generateCode
  - BC add form with structured component/port/value selects
  - File export via Tauri native save dialog
affects: [37-topology-validation, 38-ui-design-pass, 40-thermal-bc]

tech-stack:
  added: [tauri-plugin-dialog, tauri-plugin-fs, shadcn-tabs]
  patterns: [bottom-panel-collapsible-layout, toolbar-above-canvas, bc-store-cleanup-on-delete]

key-files:
  created:
    - gui/src/components/Toolbar.tsx
    - gui/src/components/BottomPanel.tsx
    - gui/src/components/CodePreview.tsx
    - gui/src/components/BCPanel.tsx
    - gui/src/components/BCRow.tsx
  modified:
    - gui/src/App.tsx
    - gui/src/store/useStore.ts
    - gui/src-tauri/src/lib.rs
    - gui/src-tauri/Cargo.toml
    - gui/src-tauri/capabilities/default.json

key-decisions:
  - "BC cleanup wired into removeNode action for automatic cascade delete"

patterns-established:
  - "Bottom panel pattern: collapsible fixed-height panel below 3-column row, toggled via toolbar button"
  - "Store-driven code generation: useMemo with generateCode recomputes on nodes/edges/bcs changes"

requirements-completed: [CODE-01, CODE-02, CODE-04, CODE-06]

duration: 4min
completed: 2026-04-02
---

# Phase 36 Plan 02: Code Generation UI Summary

**Toolbar with Code toggle/Export, collapsible bottom panel with live Julia code preview and BC editing, Tauri file save dialog**

## Performance

- **Duration:** 4 min
- **Started:** 2026-04-02T14:28:42Z
- **Completed:** 2026-04-02T14:32:49Z
- **Tasks:** 2
- **Files modified:** 11

## Accomplishments
- Toolbar with Code toggle button and Export button above the canvas
- Collapsible bottom panel (240px) with Code/BCs tabs using shadcn Tabs
- Live code preview via useMemo calling generateCode on store changes
- BC panel with structured add form (component/port/value selects) and BC list with delete
- Export button writes .jl file via Tauri native save dialog (tauri-plugin-dialog + tauri-plugin-fs)
- BC cascade delete: removing a canvas node automatically removes its associated BCs

## Task Commits

Each task was committed atomically:

1. **Task 1: Install dependencies, extend store with BC state, configure Tauri plugins** - `1d1c6d5` (feat)
2. **Task 2: Create all UI components and update App.tsx layout** - `4d00d53` (feat)

## Files Created/Modified
- `gui/src/components/Toolbar.tsx` - Code toggle + Export buttons with Tauri save dialog
- `gui/src/components/BottomPanel.tsx` - Collapsible panel with Code/BCs tabs
- `gui/src/components/CodePreview.tsx` - Read-only monospace code display via useMemo + generateCode
- `gui/src/components/BCPanel.tsx` - BC add form + BC list with delete
- `gui/src/components/BCRow.tsx` - Single BC row with expression and delete button
- `gui/src/App.tsx` - Restructured to flex-col layout with Toolbar and BottomPanel
- `gui/src/store/useStore.ts` - Added bcs, bottomPanelOpen, addBC, removeBC, toggleBottomPanel; BC cleanup in removeNode
- `gui/src-tauri/src/lib.rs` - Registered dialog and fs plugins
- `gui/src-tauri/Cargo.toml` - Added tauri-plugin-dialog, tauri-plugin-fs dependencies
- `gui/src-tauri/capabilities/default.json` - Added dialog:default, fs:default permissions
- `gui/src/components/ui/tabs.tsx` - shadcn Tabs component (auto-generated)

## Decisions Made
- BC cleanup wired directly into removeNode action rather than a separate effect, keeping cascade delete atomic with the node deletion in a single store update.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Known Stubs
None - all components are fully wired to the store and code generator.

## Next Phase Readiness
- Code generation UI is complete and ready for visual verification
- Phase 37 (topology validation) can build on the code preview to show warnings
- Phase 38 (UI design pass) may add syntax highlighting to code preview
- Phase 40 (thermal BC) can extend the BC panel with thermal port options

## Self-Check: PASSED

All 8 key files verified present. Both task commits (1d1c6d5, 4d00d53) found in git history.

---
*Phase: 36-code-generation*
*Completed: 2026-04-02*
