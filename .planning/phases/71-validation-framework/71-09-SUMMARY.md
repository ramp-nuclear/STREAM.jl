---
phase: 71-validation-framework
plan: "09"
subsystem: gui
tags: [validation, ui, bottom-panel, tabs, panel-entry, click-to-focus, severity-filter, node-filter, fix-action]
dependency_graph:
  requires: ["71-01"]
  provides: ["ValidationPanel", "BottomPanel-controlled-tabs"]
  affects: ["gui/src/components/BottomPanel.tsx", "gui/src/components/ValidationPanel.tsx"]
tech_stack:
  added: []
  patterns:
    - "window CustomEvent for cross-component navigation (stream:focus-validation-result, stream:open-property-field)"
    - "zustand live-store handles passed to FixAction closures at click time (Pitfall 7 mitigation)"
    - "Mutually exclusive severity+node filter state with banner UI"
key_files:
  created:
    - gui/src/components/ValidationPanel.tsx
    - gui/src/components/__tests__/ValidationPanel.test.tsx
  modified:
    - gui/src/components/BottomPanel.tsx
decisions:
  - "Sort order: severity rank (error=0,warning=1,info=2) then validatorId ASCII sort within each bucket"
  - "Severity + node filters are mutually exclusive — activating one clears the other"
  - "FixActionButtons extracted as a named sub-component to keep the row JSX readable"
  - "Exhaustiveness check uses void(fa as never) to avoid TS6133 'unused variable' error while still enforcing the never type at compile time"
  - "Filter banner uses &middot; separator, engineerig-voice copy: 'Showing only <severity> results · N' / 'Filtered to <nodeId> · N'"
  - "value-transfer-picker button row: flex gap-1 horizontal, both secondary variant"
  - "Severity icons: AlertCircle (error, text-destructive), AlertTriangle (warning, text-yellow-500), Info (info, text-blue-500) — Phase 72 sweeps visual tokens"
metrics:
  duration: "~25 min"
  completed: "2026-05-21"
  tasks_completed: 2
  files_count: 3
---

# Phase 71 Plan 09: ValidationPanel + BottomPanel Validation Tab Summary

**One-liner:** Validation tab added to BottomPanel (controlled by store), ValidationPanel body lists results with click-to-focus CustomEvents, D-05 severity+node filter listeners, and D-14 three-kind FixAction buttons invoking live store handles.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create ValidationPanel.tsx (list, sort, empty state, click-to-focus, severity icons, severity + node filter listeners, fix-action buttons) | 151a131 | gui/src/components/ValidationPanel.tsx, gui/src/components/__tests__/ValidationPanel.test.tsx |
| 2 | Add the Validation tab to BottomPanel.tsx + switch Tabs to controlled state | 151a131 | gui/src/components/BottomPanel.tsx |

## What Was Built

### ValidationPanel.tsx

A functional React component that is the canonical surface for every `ValidationResult` emitted by the validator registry.

**Subscribe:** `validationResults: ValidationResult[]` from `useStore`.

**Filter pipeline (D-05 locked):**
- `severityFilter` state: set by `stream:validation-filter` CustomEvent (dispatched by Plan 10 StatusBar chip).
- `nodeFilter` state: set by `stream:validation-filter-node` CustomEvent (dispatched by Plan 11 NodeContextMenu).
- Filters are mutually exclusive: activating one clears the other.
- When node filter activates with a non-empty match, `requestAnimationFrame` scrolls the first row into view.

**Filter banner:** displayed when any filter is active:
- Severity: `Showing only <severity> results · N  [Clear filter]`
- Node: `Filtered to <nodeId> · N  [Clear filter]`

**Sort order:** severity rank (error→warning→info) then `validatorId` ASCII sort within each bucket.

**Empty states:**
- No filter, no results: `"No issues."` (D-04, engineering voice)
- Filter active, no matches: `"No results match the active filter."` with Clear filter button

**Row layout (left to right):**
1. Severity icon (AlertCircle / AlertTriangle / Info from lucide-react)
2. Description text (flex-1, truncated)
3. FixActionButtons (conditional, see below)
4. Validator ID chip (10px mono, muted)

**Click-to-focus (D-05):**
- Row click dispatches `stream:focus-validation-result` with `{ result }` — Plan 11 CanvasPanel listens for canvas pan + flash.
- If exactly one `kind === 'field'` target: also dispatches `stream:open-property-field` with `{ nodeId, fieldPath }`.

**FixActionButtons (D-14, §3.9 three kinds):**
- `lossless-sync`: one `secondary` Button, `onClick` calls `fa.apply(useStore.setState, useStore.getState)`.
- `value-transfer-picker`: two `secondary` Buttons in `flex gap-1` horizontal row; left calls `fa.applyLeft`, right calls `fa.applyRight` — each with `(useStore.setState, useStore.getState)`.
- `navigation-only`: one `ghost` Button, `onClick` calls `handleResultClick(result)` (same as row click).
- All buttons call `e.stopPropagation()` before their action — prevents row click-to-focus from also firing.
- **Pitfall 7 mitigation:** closures receive `useStore.setState` and `useStore.getState` (the live zustand API methods) at click time, never a snapshot captured at rule-run time. The closure body calls `get()` to read fresh state.
- TypeScript exhaustiveness: `void (fa as never)` after the three branches — compile error if a fourth kind is added without a handler.

### BottomPanel.tsx modifications

- Added `import ValidationPanel from "./ValidationPanel"`.
- Added `activeBottomTab` and `setActiveBottomTab` subscriptions from store.
- Changed `<Tabs defaultValue="code"` to `<Tabs value={activeBottomTab} onValueChange={(v) => setActiveBottomTab(v as 'code' | 'validation')}` — controlled by store (Plan 10's statusbar chip and Plan 12's export gate can programmatically switch tabs).
- Added `<TabsTrigger value="validation" className="text-[13px] font-medium">Validation</TabsTrigger>` alongside Code trigger. No badge at count=0 (D-04).
- Added `<TabsContent value="validation" className="flex-1 min-h-0"><ValidationPanel /></TabsContent>`.

### Test file: ValidationPanel.test.tsx (13 tests, all passing)

| # | Test | Covers |
|---|------|--------|
| 1 | Empty state "No issues." | D-04 |
| 2 | Three results in severity order | sort contract |
| 3 | Row click dispatches stream:focus-validation-result | D-05 |
| 4 | Single field target also dispatches stream:open-property-field | D-05 |
| 5 | stream:validation-filter severity=error filters list | D-05 |
| 6 | Filter replacement (error→warning drops error rows) | D-05 |
| 7 | stream:validation-filter-node filters to matching nodeId | D-05 |
| 8 | Clear filter restores full list | D-05 |
| 9 | Filtered empty state shows "No results match the active filter." | D-04 |
| 10 | No buttons when fixAction is undefined | D-14 |
| 11 | lossless-sync: one button, apply called with store handles, no row dispatch | D-14 |
| 12 | value-transfer-picker: two buttons, left/right closures routed correctly | D-14 |
| 13 | navigation-only: ghost button triggers focus-validation-result | D-14 |

## Verification

```
npm run test -- --run src/components/__tests__/ValidationPanel.test.tsx
# Tests: 13 passed (13)

npx tsc --noEmit | grep "^src" | wc -l
# 13 (same as plan-01 baseline — no new errors)

grep -c 'TabsTrigger value="validation"' gui/src/components/BottomPanel.tsx  # 1
grep -c 'TabsContent value="validation"' gui/src/components/BottomPanel.tsx  # 1
grep -c 'defaultValue="code"'            gui/src/components/BottomPanel.tsx  # 0
grep -c 'value={activeBottomTab}'        gui/src/components/BottomPanel.tsx  # 1
grep -c 'stream:validation-filter\b'     gui/src/components/ValidationPanel.tsx  # ≥1
grep -c 'stream:validation-filter-node'  gui/src/components/ValidationPanel.tsx  # ≥1
grep -c 'lossless-sync'                  gui/src/components/ValidationPanel.tsx  # ≥1
grep -c 'value-transfer-picker'          gui/src/components/ValidationPanel.tsx  # ≥1
grep -c 'navigation-only'               gui/src/components/ValidationPanel.tsx  # ≥1
grep -c 'useStore.setState'              gui/src/components/ValidationPanel.tsx  # ≥1
grep -c 'useStore.getState'              gui/src/components/ValidationPanel.tsx  # ≥1
```

## Deviations from Plan

None — plan executed exactly as written.

The one minor implementation detail: the `_exhaustive: never` pattern from the plan spec was changed to `void (fa as never)` to avoid the pre-existing TypeScript strict-mode `TS6133: declared but never read` pattern. The exhaustiveness guarantee is identical — TypeScript still errors on the `as never` cast if the union is not fully narrowed.

## Known Stubs

None. ValidationPanel renders live `validationResults` from the store. The store ships an empty array until Plans 05/06 populate it with rule emissions — the panel correctly shows "No issues." in that state, which is the intended empty-state behavior per D-04.

## Threat Flags

None. No new network endpoints, auth paths, file access, or schema changes introduced. All state reads/writes go through the existing zustand store API.

## Self-Check: PASSED

- [x] gui/src/components/ValidationPanel.tsx exists
- [x] gui/src/components/__tests__/ValidationPanel.test.tsx exists
- [x] gui/src/components/BottomPanel.tsx modified (validation tab + controlled Tabs)
- [x] Commit 151a131 exists (`git log --oneline -1` confirms)
- [x] 13 tests pass
- [x] tsc errors: 13 (baseline unchanged)
