---
phase: 71-validation-framework
plan: 12
subsystem: ui
tags: [validation, export-gate, toast, sonner, zustand, react, tauri]

# Dependency graph
requires:
  - phase: 71-validation-framework
    provides: runValidators, buildValidationSnapshot, ValidationResult types, ValidationPanel, sonner Toaster (Plans 01/03/09/10/11)
provides:
  - "D-17 export gate: synchronous runValidators call in exportCode.ts, toast.error on error, auto-open Validation tab"
  - "Export button disabled when validationResults has severity=error entries; tooltip with count"
  - "ValidationDialog.tsx deleted; App.tsx mount removed"
affects:
  - phase 71-13 (store slice cleanup — validateAndGate/validateTopology/clearValidation deletion)
  - phase 72 (design pass — tooltip styling, toast styling)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "D-17 gate: synchronous runValidators before save dialog; toast.error + store setState on error"
    - "Derived primitive subscription: useStore(s => s.validationResults.filter(...).length) for re-render efficiency"
    - "span wrapper around disabled Button for Tooltip hover capture"

key-files:
  created: []
  modified:
    - gui/src/lib/exportCode.ts
    - gui/src/components/BottomPanel.tsx
    - gui/src/App.tsx
    - gui/src/lib/__tests__/exportCode.test.ts

key-decisions:
  - "Tooltip wraps Export button via span shim: disabled buttons don't fire mouse events, span captures hover without breaking button semantics"
  - "exportCode.test.ts rewritten to mock runValidators + toast.error + useStore.setState directly — cleanly controls new contract without full store setup"
  - "AboutDialog.tsx comment mentioning ValidationDialog by name (as API shape analogy) left untouched — not an import or mount, not a code dependency"

patterns-established:
  - "Export gate pattern: build snapshot → run validators → gate on errorCount → toast + panel → abort"
  - "Derived errorCount subscription: filter validationResults in selector, subscribe to primitive length"

requirements-completed: [D-15, D-17]

# Metrics
duration: 25min
completed: 2026-05-21
---

# Phase 71 Plan 12: Export Gate Rewire + ValidationDialog Deletion Summary

**D-17 fully implemented: synchronous runValidators export gate with sonner toast, auto-focus Validation tab, disabled Export button with tooltip, and ValidationDialog modal deleted**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-05-21T15:28:00Z
- **Completed:** 2026-05-21T15:35:00Z
- **Tasks:** 3
- **Files modified:** 4 (+ 1 deleted)

## Accomplishments

- `exportCode.ts` rewired to call `runValidators(buildValidationSnapshot(s))` synchronously; on errorCount > 0 fires `toast.error("Export blocked: N validation error(s). See Validation panel.")`, sets `bottomPanelOpen: true` + `activeBottomTab: 'validation'`, aborts export
- Export button in BottomPanel disabled when `!hasNodes || errorCount > 0`; tooltip text: `"Resolve N validation error(s) first"` / `"Add components first"` / default label
- `ValidationDialog.tsx` deleted via `git rm`; import and mount removed from `App.tsx`
- `exportCode.test.ts` rewritten (7 tests, all pass) to cover new D-17 contract: validation error gate, toast.error call, setState with bottomPanelOpen + activeBottomTab, user cancel, happy path, write error propagation

## Task Commits

1. **Task 1: Rewrite exportCode.ts** — `11e5999` (feat)
2. **Task 2: Disable Export button + tooltip** — `8e75150` (feat)
3. **Task 3: Delete ValidationDialog; remove App.tsx mount; update tests** — `762fb5e` (feat)

## Files Created/Modified

- `gui/src/lib/exportCode.ts` — D-17 gate: runValidators + toast.error + setState on error; propagate results on success
- `gui/src/components/BottomPanel.tsx` — errorCount derived selector; Export disabled when errorCount > 0; Tooltip with dynamic content
- `gui/src/App.tsx` — removed ValidationDialog import (line 16) and mount (line 601)
- `gui/src/lib/__tests__/exportCode.test.ts` — rewritten for new contract; mocks runValidators + toast.error + useStore.setState
- `gui/src/components/ValidationDialog.tsx` — **DELETED** (git rm)

## Decisions Made

- Tooltip wraps Export button via `<span>` shim: disabled buttons don't fire mouse events in browsers, the span captures hover and forwards to Tooltip; tabIndex on span is 0 when disabled, -1 when enabled so keyboard users can still discover the tooltip
- `exportCode.test.ts` mocks `../validation/runner` and `../../components/ui/sonner` directly rather than providing a full store state; this keeps tests fast and precisely targets the new contract without depending on all 8 validators
- `AboutDialog.tsx` comment at line 21 references "ValidationDialog" as a JSDoc analogy for API shape — this is documentation only, not an import; left untouched

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] exportCode.test.ts failing after store mock no longer provided validateAndGate**
- **Found during:** Task 3 verification (post-deletion test run)
- **Issue:** Original test mocked `useStore.getState()` returning only `{ validateAndGate }`. New `exportCode.ts` calls `buildValidationSnapshot(s)` which reads `s.edges`, `s.anchors`, `s.bcMode`, `s.resources` — these were undefined, causing "snapshot.edges is not iterable" errors in 4 tests
- **Fix:** Rewrote `exportCode.test.ts` to mock `../validation/runner` (runValidators returns `[]` by default, `[errorResult]` per-test), mock `../../components/ui/sonner` (toast.error), and mock `useStore.setState` as `vi.fn()`. Expanded test coverage to also assert toast.error call and setState with bottomPanelOpen/activeBottomTab
- **Files modified:** `gui/src/lib/__tests__/exportCode.test.ts`
- **Verification:** 7/7 tests pass; full suite 99 files / 1048 tests pass
- **Committed in:** `762fb5e` (Task 3 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - Bug)
**Impact on plan:** Required for test suite to pass after contract change. Added 3 new assertions beyond the original 4 tests, improving coverage of the D-17 gate behavior.

## Verification Results

- `grep -c "validateAndGate" gui/src/lib/exportCode.ts` → **0** (no external callers)
- `grep -c "runValidators" gui/src/lib/exportCode.ts` → **1**
- `grep -c "buildValidationSnapshot" gui/src/lib/exportCode.ts` → **1**
- `grep -c "toast.error" gui/src/lib/exportCode.ts` → **1**
- `grep -c "errorCount" gui/src/components/BottomPanel.tsx` → **5** (selector + predicate + tooltip × 3)
- `grep -c "Resolve" gui/src/components/BottomPanel.tsx` → **1**
- `test ! -f gui/src/components/ValidationDialog.tsx` → **deleted OK**
- `grep -rn "ValidationDialog" gui/src/` → only comment in AboutDialog.tsx (not an import/mount)
- `npx tsc --noEmit` → **13 errors** (matches baseline; no regression)
- `npm run test` → **99 files, 1048 tests pass, 10 todo**

## Tooltip Strings Used

- Error state: `"Resolve ${errorCount} validation ${errorCount === 1 ? "error" : "errors"} first"`
- No nodes: `"Add components first"`
- Default: `"Export generated Julia code to file"`

## Known Stubs

None.

## Threat Flags

None — no new network endpoints, auth paths, or trust-boundary surfaces introduced.

## Issues Encountered

- `vi.mock` hoisting: the original rewrite attempt used a module-level `const setStateMock = vi.fn()` referenced inside a `vi.mock()` factory — vitest hoists `vi.mock` to top of file, causing "Cannot access before initialization". Fixed by using `vi.fn()` inline in the factory and accessing via `vi.mocked(useStore.setState)` after import.

## Next Phase Readiness

- Plan 13 can now safely delete `validateAndGate`, `validateTopology`, `clearValidation`, and the `validationResult: TopologyResult | null` slice — no caller in `src/` (outside `useStore.ts` itself and test mocks) references these
- The only test files still referencing `validateAndGate` are store mocks in `saveAndOpenErrors.test.ts` and `saveProjectAs.test.ts` — these provide the property as part of a broader store mock shape; Plan 13 will clean these up when the action is deleted

---
*Phase: 71-validation-framework*
*Completed: 2026-05-21*
