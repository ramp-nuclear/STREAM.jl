---
phase: 71-validation-framework
plan: 11
subsystem: ui
tags: [validation, field-highlight, data-field-path, canvas-focus, context-menu, custom-events, react-hooks]

# Dependency graph
requires:
  - phase: 71-01
    provides: ValidationResult + Target types (node/field/edge/port) + validationResults store slice
  - phase: 71-09
    provides: ValidationPanel dispatching stream:focus-validation-result + stream:open-property-field; listening for stream:validation-filter-node
  - phase: 71-10
    provides: ValidationStatusBar dispatching stream:validation-filter; bottomPanelOpen + activeBottomTab store fields

provides:
  - data-field-path attribute on every renderable field in ParameterForm + BCsTabForm (D-12, D-13)
  - useValidationFieldHighlight hook painting .validation-field-error / .validation-field-warning on matching sidebar fields
  - SidebarPanel stream:open-property-field listener for selectNode + scroll/focus
  - CanvasPanel stream:focus-validation-result listener for setCenter pan + stream:node-flash flash ring
  - NodeContextMenu "Show errors for this component" item dispatching stream:validation-filter-node
  - CSS classes: .validation-field-error, .validation-field-warning, .validation-flash

affects:
  - 71-12 (UAT verification of D-05 end-to-end navigation contract)
  - 72-design-system (Phase 72 will sweep the validation CSS visual tokens)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - data-field-path HTML attribute as cross-cutting DOM bridge (D-12 pattern — same idiom as data-source-id in Phase 66)
    - CustomEvent chain for bidirectional panel↔canvas navigation (stream:* namespace)
    - CSS.escape for safe attribute-selector injection when fieldPath contains dots/brackets
    - useEffect DOM side-effect hook (no new store slice) for transient node flash via stream:node-flash

key-files:
  created:
    - gui/src/hooks/useValidationFieldHighlight.ts
    - gui/src/hooks/__tests__/useValidationFieldHighlight.test.ts
  modified:
    - gui/src/components/sidebar/ParameterForm.tsx
    - gui/src/components/sidebar/BCsTabForm.tsx
    - gui/src/components/sidebar/SidebarPanel.tsx
    - gui/src/components/CanvasPanel.tsx
    - gui/src/components/canvasMenus/NodeContextMenu.tsx
    - gui/src/index.css

key-decisions:
  - "Canvas node flash mechanism: CustomEvent 'stream:node-flash' (not new store slice) — CanvasPanel dispatches and listens in the same useEffect; simpler and avoids adding a flashedNodeIds Set to global store state"
  - "data-field-path wrapper in ParameterForm: refactored renderField to assign to inner variable then wrap in single <div data-field-path={param.name}> — preserves all existing key={param.name} props on inner elements; wrapper has no className (Pitfall 3 layout-transparent)"
  - "BCsTabForm: added data-field-path={externalInput.name} directly to existing FieldRow root div — no extra wrapper needed (whole-array fieldPath per D-13)"

patterns-established:
  - "Pattern: data-field-path attribute injection at renderField site — one wrapper per field, no className, CSS.escape in querySelector"
  - "Pattern: stream:* CustomEvent naming for all validation cross-component events"

requirements-completed: [D-05, D-12, D-13]

# Metrics
duration: 8min
completed: 2026-05-21
---

# Phase 71 Plan 11: Bidirectional Validation Bridges Summary

**data-field-path injection on all sidebar fields + useValidationFieldHighlight hook + CanvasPanel pan/flash on row click + NodeContextMenu "Show errors" dispatch completing the D-05 navigation contract**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-05-21T15:00:00Z
- **Completed:** 2026-05-21T15:08:00Z
- **Tasks:** 3
- **Files modified:** 7 (3 modified, 2 created)

## Accomplishments

- Every renderable field in ParameterForm and BCsTabForm carries `data-field-path` for DOM-based field targeting (D-12, D-13)
- `useValidationFieldHighlight` hook (6 tests) applies `.validation-field-error`/`.validation-field-warning` classes to matching sidebar elements when `validationResults` change
- Full D-05 navigation contract wired: panel row click → canvas pan + node flash + (single field target) sidebar scroll/focus; right-click node → show-errors item → panel filter + scroll

## Task Commits

1. **Task 1: data-field-path + CSS** - `471c5ab` (feat)
2. **Task 2: useValidationFieldHighlight hook + SidebarPanel** - `347a6c4` (feat)
3. **Task 3: CanvasPanel focus + NodeContextMenu errors entry** - `be0ed9e` (feat)

## Files Created/Modified

- `gui/src/hooks/useValidationFieldHighlight.ts` — Hook: subscribes to validationResults, clears + re-applies highlight classes to data-field-path elements via CSS.escape-guarded querySelector
- `gui/src/hooks/__tests__/useValidationFieldHighlight.test.ts` — 6 tests: error paint, warning paint, clear-on-change, null nodeId, dot-notation CSS.escape, wrong-nodeId filtering
- `gui/src/components/sidebar/ParameterForm.tsx` — renderField refactored to assign `inner` then wrap in `<div data-field-path={param.name}>` (layout-transparent, no className)
- `gui/src/components/sidebar/BCsTabForm.tsx` — FieldRow root div gains `data-field-path={externalInput.name}` (D-13 whole-array fieldPath)
- `gui/src/components/sidebar/SidebarPanel.tsx` — containerRef added; useValidationFieldHighlight called; stream:open-property-field listener added (selectNode + scroll/focus)
- `gui/src/components/CanvasPanel.tsx` — stream:focus-validation-result listener added (bbox setCenter + stream:node-flash dispatch); stream:node-flash listener added (DOM querySelector + .validation-flash class toggle)
- `gui/src/components/canvasMenus/NodeContextMenu.tsx` — hasErrors selector; "Show errors for this component" menu item (useStore.setState + stream:validation-filter-node dispatch)
- `gui/src/index.css` — .validation-field-error, .validation-field-warning, .validation-flash utility classes

## Integration Points (CustomEvent contract)

| Event | Dispatcher | Listener | Purpose |
|-------|-----------|----------|---------|
| `stream:focus-validation-result` | ValidationPanel (Plan 09) | CanvasPanel (Plan 11) | Pan canvas + flash node on row click |
| `stream:open-property-field` | ValidationPanel (Plan 09) | SidebarPanel (Plan 11) | Select node + scroll/focus property field |
| `stream:validation-filter` | ValidationStatusBar (Plan 10) | ValidationPanel (Plan 09) | Filter list by severity |
| `stream:validation-filter-node` | NodeContextMenu (Plan 11) | ValidationPanel (Plan 09) | Filter list to node + scroll first match |
| `stream:node-flash` | CanvasPanel (Plan 11) | CanvasPanel (Plan 11) | Toggle .validation-flash class on ReactFlow node DOM elements |

No orphan dispatchers — every event has both a dispatcher and a listener wired.

## Decisions Made

- **Canvas flash mechanism:** Chose the simpler CustomEvent `stream:node-flash` approach (CanvasPanel dispatches and listens in the same useEffect, queries DOM via `[data-id="..."]` ReactFlow attribute) over adding a `flashedNodeIds: Set<string>` store slice. The flash is transient (700ms), purely presentational, and does not need to survive component remounts — no store state needed.

- **data-field-path wrapper shape in ParameterForm:** Refactored `renderField` from inline `return` in each branch to assign to `inner: React.ReactNode` then return a single `<div data-field-path={param.name}>{inner}</div>`. This is the single injection point (D-12 "do NOT per-field"), and the wrapper carries no className so layout is unaffected (Pitfall 3).

- **BCsTabForm attribute placement:** Added directly to the existing FieldRow root `<div className="flex flex-col gap-[8px]">` rather than adding another wrapper. The data-field-path and className coexist without conflict — no layout change.

## Deviations from Plan

None — plan executed exactly as written. The `stream:node-flash` approach was explicitly described as the "simpler alternative" in the Task 3 action block, which was selected.

## Issues Encountered

- CSS.escape not available in jsdom test environment — added a polyfill block at the top of the test file before any code that calls it. Production browser environments always have CSS.escape.
- The test file tested the DOM logic directly (re-implementing the hook's useEffect body as a helper function) rather than rendering a React component, since the hook is a pure DOM side-effect and React renderer overhead was unnecessary for the test goals.

## Sidebar Layout Impact

No layout changes. All data-field-path additions are either:
- A wrapper div with no className (ParameterForm — Pitfall 3 compliant)
- An attribute added to an existing div that already has its className (BCsTabForm — no new element)

The `<Input>` auto-select-on-focus wrapper (memory `feedback_input_select_on_focus`) is preserved — the data-field-path wrapper sits outside existing input wrappers and changes no input mounting.

## Known Stubs

None — all integration points are fully wired. The CSS visual tokens (colors, outline widths) are intentionally placeholder per Phase 72 design-system sweep commitment.

## Threat Flags

None — this plan adds no new network endpoints, auth paths, file access patterns, or schema changes.

## Next Phase Readiness

Plan 12 (UAT) can now verify the full D-05 navigation contract end-to-end:
- Click ValidationPanel row → canvas pans + node flashes + (single field) sidebar scrolls/focuses
- Click statusbar chip → panel opens + severity filter
- Right-click node with errors → "Show errors for this component" → panel filter + scroll to first match

---
*Phase: 71-validation-framework*
*Completed: 2026-05-21*
