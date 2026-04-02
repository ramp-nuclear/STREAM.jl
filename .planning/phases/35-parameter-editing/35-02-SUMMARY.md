---
phase: 35-parameter-editing
plan: 02
subsystem: ui
tags: [react, sidebar, form, validation, shadcn, parameter-editing]

# Dependency graph
requires:
  - phase: 35-parameter-editing/01
    provides: Store (useStore with updateNodeParams, selectNode), registry (types, getComponent), validation (validateInt, validateReal, validatePositiveReal, validateJuliaIdentifier), shadcn UI components
provides:
  - SidebarPanel reading selectedNodeId from store and rendering parameter form or empty state
  - ParameterForm dispatching to type-specific field components based on registry schema
  - NumericField with on-blur validation for Int/Real types with unit suffix
  - InstanceNameField with Julia identifier validation
  - PipeGeometryPicker with circular/rectangular segmented control and conditional dimension fields
  - FunctionSelect dropdown with factory items grayed out and tooltipped
  - ModeToggle segmented control for Pump fixed-dP/fixed-mdot modes
  - MatrixBadge read-only display
  - Wave 0 test stubs for all sidebar components
affects: [35-parameter-editing/03]

# Tech tracking
tech-stack:
  added: []
  patterns: [key-prop remount for node switching, on-blur validation gating, segmented control via Button pairs]

key-files:
  created:
    - gui/src/components/sidebar/SidebarPanel.tsx
    - gui/src/components/sidebar/ParameterForm.tsx
    - gui/src/components/sidebar/InstanceNameField.tsx
    - gui/src/components/sidebar/NumericField.tsx
    - gui/src/components/sidebar/PipeGeometryPicker.tsx
    - gui/src/components/sidebar/FunctionSelect.tsx
    - gui/src/components/sidebar/ModeToggle.tsx
    - gui/src/components/sidebar/MatrixBadge.tsx
    - gui/src/components/sidebar/__tests__/ParameterForm.test.tsx
    - gui/src/components/sidebar/__tests__/SidebarPanel.test.tsx
    - gui/src/components/sidebar/__tests__/ModeToggle.test.tsx
    - gui/src/components/sidebar/__tests__/PipeGeometryPicker.test.tsx
    - gui/src/components/sidebar/__tests__/InstanceNameField.test.tsx
  modified:
    - gui/src/components/SidebarPanel.tsx

key-decisions:
  - "key={selectedNodeId} on form container forces React remount on node switch, resetting all local field state"
  - "Segmented controls use paired Buttons with rounded-l-none/rounded-r-none rather than a custom component"
  - "FunctionSelect wraps disabled factory items in Tooltip for hover explanation"
  - "PipeGeometryPicker clears all dimension fields on geometry type switch per D-02 spec"

patterns-established:
  - "On-blur validation gating: local state while typing, validate on blur, only write to store if valid"
  - "Segmented control: Button pairs with variant=default/outline for active/inactive"
  - "Re-export pattern: gui/src/components/SidebarPanel.tsx re-exports from sidebar/ subdirectory"

requirements-completed: [PARA-01, PARA-02, PARA-03, PARA-04, PARA-05, PARA-06]

# Metrics
duration: 5min
completed: 2026-04-02
---

# Phase 35 Plan 02: Parameter Editing Sidebar Summary

**Full sidebar component tree with registry-driven form dispatching, on-blur validation, mode toggle, PipeGeometry picker, and Wave 0 test stubs for all components**

## What Was Built

### Sidebar Component Tree

1. **SidebarPanel** - Main sidebar container reading `selectedNodeId` from Zustand store. Shows empty state ("No selection") when deselected, renders full parameter form when a node is selected. Uses `key={selectedNodeId}` to force remount on node switch, preventing stale form state.

2. **ParameterForm** - Registry-driven form dispatcher. Groups parameters into sections (Parameters, Geometry, Correlations, Advanced) with separators. Filters visible parameters by the active constructor mode.

3. **NumericField** - Controlled input for Real and Int types. Local state while typing, validates on blur using `validateInt`/`validateReal`. Shows unit suffix (e.g., "m/s^2") right-aligned inside input. Invalid values show destructive border + error message and are NOT written to store.

4. **InstanceNameField** - Instance name input with `validateJuliaIdentifier` on blur. Syncs local state from prop via useEffect for node switching.

5. **PipeGeometryPicker** - Segmented control (Circular/Rectangular) with conditional dimension fields. Circular shows L, D; Rectangular shows L, W, H. Switching type clears all dimension fields. Each dimension validates with `validatePositiveReal` on blur.

6. **FunctionSelect** - Dropdown from registry `options`. Simple items selectable normally. Factory items disabled with tooltip "Factory correlation editing coming in a future update".

7. **ModeToggle** - Segmented control for Pump modes ("Fixed dP" / "Fixed mdot"). Labeled with "Mode" heading.

8. **MatrixBadge** - Read-only badge showing "Matrix (edit in code)" for Matrix-type parameters.

### Test Coverage

- 4 real render tests across ParameterForm, ModeToggle, PipeGeometryPicker, InstanceNameField
- 19 todo stubs documenting future coverage for blur validation, mode switching, geometry clearing, store integration
- All 65 real tests pass (84 total with todos)

## Verification

- TypeScript: `tsc --noEmit` exits 0
- Tests: `vitest run` - 65 passed, 19 todo, 0 failed

## Deviations from Plan

None - plan executed exactly as written.

## Task Completion

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create sidebar component tree | 288dec2 | SidebarPanel.tsx, ParameterForm.tsx, InstanceNameField.tsx, NumericField.tsx, SidebarPanel.tsx (re-export) |
| 2 | Create PipeGeometryPicker, FunctionSelect, ModeToggle, MatrixBadge | 65854a8 | PipeGeometryPicker.tsx, FunctionSelect.tsx, ModeToggle.tsx, MatrixBadge.tsx |
| 3 | Create Wave 0 test stubs | 464bd3b | 5 test files in sidebar/__tests__/ |

## Known Stubs

None - all components are fully implemented with real functionality. Test files contain `it.todo()` stubs by design (Wave 0 pattern), not implementation stubs.

## Self-Check: PASSED

All 14 created files verified on disk. All 3 commit hashes verified in git log.
