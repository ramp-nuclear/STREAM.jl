---
phase: 38-ui-design-pass
plan: 02
subsystem: ui
tags: [react, zustand, shadcn, resizable-panels, collapse]

requires:
  - phase: 38-01
    provides: shadcn primitives, icon registry, category colors
provides:
  - Collapsible toolbox and sidebar panels with chevron toggle
  - Drag-to-resize panels via useResizable hook
  - PanelCollapseButton reusable component with shadcn Button+Tooltip
  - Store state for toolboxCollapsed/sidebarCollapsed
affects: [38-03]

tech-stack:
  added: []
  patterns: [useResizable custom hook for panel resize, PanelCollapseButton with shadcn primitives]

key-files:
  created:
    - gui/src/hooks/useResizable.ts
    - gui/src/components/PanelCollapseButton.tsx
  modified:
    - gui/src/store/useStore.ts
    - gui/src/components/ToolboxPanel.tsx
    - gui/src/components/sidebar/SidebarPanel.tsx
    - gui/src/App.tsx

key-decisions:
  - "useResizable attaches mousemove/mouseup to document to avoid mouse-escape leak"
  - "Collapse state excluded from zundo partialize to prevent undo toggling panel visibility"
  - "PanelCollapseButton uses icon-xs size (24px) for compact collapse strip"

patterns-established:
  - "useResizable hook: direction-aware drag resize with document-level event listeners"
  - "Panel collapse pattern: conditional render of panel content, always-visible chevron strip"

requirements-completed: [DSGN-01, DSGN-02, DSGN-05]

duration: 3min
completed: 2026-04-03
---

# Phase 38 Plan 02: Panel Collapse/Resize and shadcn Audit Summary

**Collapsible + resizable three-panel layout with useResizable hook, PanelCollapseButton component, and store-driven collapse state**

## Performance

- **Duration:** 3 min
- **Started:** 2026-04-02T22:56:26Z
- **Completed:** 2026-04-02T22:59:18Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- Toolbox and sidebar panels collapse to a chevron strip and re-expand via PanelCollapseButton
- Both panels drag-resizable between min/max widths using useResizable hook
- Canvas fills freed space when panels are collapsed
- All UI interactive elements use shadcn primitives (no raw button/input)
- Collapse state excluded from undo/redo (zundo partialize unchanged)

## Task Commits

Each task was committed atomically:

1. **Task 1: Store additions + useResizable hook + PanelCollapseButton** - `3f8566a` (feat)
2. **Task 2: Wire panel collapse/resize into ToolboxPanel, SidebarPanel, and App.tsx** - `43aadd1` (feat)

## Files Created/Modified
- `gui/src/hooks/useResizable.ts` - Custom hook for panel drag-to-resize with document-level listeners
- `gui/src/components/PanelCollapseButton.tsx` - Reusable chevron collapse/expand button with shadcn Button+Tooltip
- `gui/src/store/useStore.ts` - Added toolboxCollapsed/sidebarCollapsed state and setters
- `gui/src/components/ToolboxPanel.tsx` - Accepts width prop, removed hardcoded w-60
- `gui/src/components/sidebar/SidebarPanel.tsx` - Accepts width prop, removed hardcoded w-80 from all return paths
- `gui/src/App.tsx` - Three-panel layout with collapse buttons, drag handles, TooltipProvider wrapper

## Decisions Made
- useResizable hook captures startWidth in ref to avoid stale closure during drag
- PanelCollapseButton uses icon-xs size for compact strip appearance
- TooltipProvider placed inside ReactFlowProvider but wrapping entire app content
- Collapse state reset to false in newProject action

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Panel collapse/resize complete, ready for Plan 03 (visual polish pass)
- All 150 tests pass, TypeScript type check clean

---
*Phase: 38-ui-design-pass*
*Completed: 2026-04-03*
