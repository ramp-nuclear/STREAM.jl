---
phase: 71-validation-framework
plan: 10
subsystem: gui
tags: [validation, statusbar, ui, app-mount, initValidation, toaster]
dependency_graph:
  requires: ["71-01", "71-03", "71-09"]
  provides: ["ValidationStatusBar", "pulse-once-animation", "initValidation-mount", "Toaster-mount"]
  affects: ["gui/src/App.tsx", "gui/src/index.css"]
tech_stack:
  added: []
  patterns: ["zustand-primitive-selector", "window-CustomEvent-dispatch", "CSS-keyframe-animation", "useRef-previous-value"]
key_files:
  created:
    - gui/src/components/ValidationStatusBar.tsx
    - gui/src/components/__tests__/ValidationStatusBar.test.tsx
  modified:
    - gui/src/App.tsx
    - gui/src/index.css
decisions:
  - "Strip height fixed at 22px (D-02 range 22-24px; 22px chosen)"
  - "Pulse duration: 600ms ease-out, single shot; cleared after 700ms timeout"
  - "Error chip uses AlertCircle, warning uses AlertTriangle, info uses Info (lucide-react)"
  - "ValidationDialog import + mount LEFT IN PLACE pending Plan 12 export-gate rewire"
  - "initValidation useEffect is independent from autoRecover — separate subscription"
metrics:
  duration: "~7 minutes"
  completed: "2026-05-21"
  tasks_completed: 2
  tasks_total: 2
  files_changed: 4
---

# Phase 71 Plan 10: ValidationStatusBar + App Bootstrap Summary

Always-visible 22px validation statusbar strip mounted under BottomPanel; three count chips (error/warning/info) with click-to-filter and 0→N pulse animation; initValidation() and sonner Toaster bootstrapped in App.tsx.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | ValidationStatusBar.tsx + pulse-once CSS + tests | e6785b0 | ValidationStatusBar.tsx, ValidationStatusBar.test.tsx, index.css |
| 2 | Mount ValidationStatusBar + Toaster + initValidation in App.tsx | 6febdbf | App.tsx |

## What Was Built

### ValidationStatusBar.tsx

A functional component rendering the always-visible 22px statusbar strip (D-02). Structure:

- **Outer div**: `height: 22px`, `bg-chrome`, `border-t`, flex row, `text-[11px]`
- **Three chip buttons** using `Button variant="ghost" size="sm"` with `h-5 px-1.5 gap-1`:
  - Error chip: `AlertCircle` icon + count; dims to `opacity-60` when count=0
  - Warning chip: `AlertTriangle` icon + count; dims when count=0
  - Info chip: `Info` icon + count; dims when count=0
- **Click handler** per chip (D-05 locked): calls `useStore.setState({ bottomPanelOpen: true, activeBottomTab: 'validation' })` + dispatches `window.CustomEvent('stream:validation-filter', { detail: { severity } })`
- **0→N pulse** (D-03): `useRef` tracks previous error count; on `prev===0 && current>0` transition, adds `pulse-once` className via a `useState` boolean that auto-clears after 700ms. Panel does NOT auto-open on count change.

### pulse-once CSS (index.css)

```css
@keyframes pulse-once {
  0%   { opacity: 1; transform: scale(1); }
  50%  { opacity: 0.4; transform: scale(1.1); }
  100% { opacity: 1; transform: scale(1); }
}
.pulse-once { animation: pulse-once 600ms ease-out 1; }
```

### App.tsx Changes

- **`ValidationStatusBar`** imported and mounted as sibling after `<BottomPanel />` inside the root `flex flex-col h-screen` div — the natural flex child absorbs the 22px height
- **`Toaster`** imported from `./components/ui/sonner` and mounted inside `<TooltipProvider>` alongside other modal mounts (single mount, app lifetime)
- **`initValidation`** added to the existing `useStore` import; new independent `useEffect` with `return teardown` wires the validator subscription on mount and cleans it up on unmount
- **`ValidationDialog`** import + mount left in place per Plan 12 handoff (Plan 12 replaces the export gate before deleting it)

## Test Coverage

7 tests in `ValidationStatusBar.test.tsx` (all pass):
1. Three chips render with counts derived from validationResults
2. Chips render with count 0 when validationResults is empty
3. Error chip click → bottomPanelOpen=true + activeBottomTab='validation'
4. Error chip click → dispatches `stream:validation-filter` with `severity='error'`
5. Warning chip click → dispatches `stream:validation-filter` with `severity='warning'`
6. Info chip click → dispatches `stream:validation-filter` with `severity='info'`
7. 0→N error transition adds `pulse-once` class to error chip

## Verification Results

- `npm run test -- --run src/components/__tests__/ValidationStatusBar.test.tsx`: **7/7 pass**
- `npm run test -- --run` (full suite): **998/998 tests pass, 90/90 files**
- `npx tsc --noEmit`: **13 pre-existing errors only** — no new errors introduced

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — the statusbar renders live data from `validationResults` (empty array until rules fire).

## Threat Flags

None — no new network endpoints, auth paths, or trust-boundary changes.

## Self-Check: PASSED

- `gui/src/components/ValidationStatusBar.tsx` exists: FOUND
- `gui/src/components/__tests__/ValidationStatusBar.test.tsx` exists: FOUND
- `gui/src/index.css` has `pulse-once`: FOUND (3 occurrences)
- `gui/src/App.tsx` has `ValidationStatusBar` (×2), `initValidation` (×3), `<Toaster` (×1), `ValidationDialog` (×2): FOUND
- Commit e6785b0 exists: FOUND
- Commit 6febdbf exists: FOUND
