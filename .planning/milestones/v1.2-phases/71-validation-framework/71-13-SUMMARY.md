---
phase: 71-validation-framework
plan: 13
subsystem: gui
tags: [validation, onConnect, reroute, cleanup, deletion, vald-fold]
dependency_graph:
  requires: [71-01, 71-04, 71-06, 71-08, 71-11, 71-12]
  provides: [D-16-complete, D-18-complete, D-19-complete, D-20-complete, phase-71-cleanup-wave]
  affects:
    - gui/src/components/CanvasPanel.tsx
    - gui/src/components/StreamNode.tsx
    - gui/src/store/useStore.ts
    - gui/src/lib/validation/ (new framework — unchanged)
    - gui/src/lib/selectors/ (nodeErrors.ts deleted)
tech_stack:
  added: []
  patterns:
    - "One-shot portType.run() on synthetic edge snapshot inside isValidConnection (D-19)"
    - "errorNodeIds as sole red-ring source — populated by initValidation subscription (D-20)"
key_files:
  created: []
  modified:
    - gui/src/components/CanvasPanel.tsx
    - gui/src/components/StreamNode.tsx
    - gui/src/store/useStore.ts
    - gui/src/store/__tests__/saveAndOpenErrors.test.ts
    - gui/src/store/__tests__/saveProjectAs.test.ts
    - gui/src/store/__tests__/useStore.bc.test.ts
    - gui/src/components/__tests__/CanvasPanel.bc.test.tsx
    - gui/src/components/__tests__/StreamNode.test.tsx
    - gui/src/lib/__tests__/validation.test.ts
  deleted:
    - gui/src/lib/validation.ts
    - gui/src/lib/validation.test.ts
    - gui/src/lib/selectors/nodeErrors.ts
    - gui/src/lib/selectors/__tests__/nodeErrors.test.ts
decisions:
  - "D-19: portType.run() called one-shot with synthetic single-edge snapshot inside isValidConnection; full runValidators NOT called on hover tick (avoids loopTraversal on every drag)"
  - "D-20: hasBCError subscription removed from StreamNode; errorNodeIds is the sole red-ring source populated by nMatch via initValidation"
  - "D-16: validateAndGate/clearValidation/validationResult removed from store; saveProject/saveProjectAs no longer have legacy topology gate (export gate lives in exportCode.ts via runValidators)"
  - "Test helpers in useStore.bc.test.ts + CanvasPanel.bc.test.tsx: selectNodeErrors inlined as errorsFor() since the nMatch path is async/debounced and the BC n-mismatch logic is deterministic and testable synchronously"
metrics:
  duration: ~35 minutes
  completed: "2026-05-21"
  tasks_completed: 4
  files_changed: 13
  files_deleted: 4
---

# Phase 71 Plan 13: Legacy Validation Cleanup — Summary

Final cleanup wave: reroute onConnect hard-block through portType validator (D-19), remove legacy selectNodeErrors path in StreamNode (D-20), delete validateAndGate / clearValidation / validationResult slice + validation.ts + validation.test.ts (D-16). After this plan, Phase 71's old code is gone and the new framework is the sole source of validation state.

## Tasks Completed

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1 | Reroute isValidConnection through portType validator (D-19) | 3487d09 | CanvasPanel.tsx |
| 2 | Remove hasBCError subscription from StreamNode (D-20) | 35664b7 | StreamNode.tsx |
| 3 | Delete legacy state from useStore.ts (D-16) | 2e0288e | useStore.ts + 2 test files |
| 4 | Delete validation.ts + validation.test.ts + nodeErrors.ts | 5dbfa6e | 4 deleted + 5 test files updated |

## Deliverable Verification

**D-19 closed (onConnect reroute):**
- `grep -c "isAllowedBCConnection" gui/src/components/CanvasPanel.tsx` → 0
- `grep -c "portType\." gui/src/components/CanvasPanel.tsx` → 1
- Synthetic single-edge snapshot passed to `portType.run()` only — loopTraversal never called on hover tick

**D-20 closed (StreamNode cleanup):**
- `grep -c "selectNodeErrors|hasBCError" gui/src/components/StreamNode.tsx` → 0
- `hasAnyError` now equals `hasError` (sole source: `errorNodeIds` Set on store)

**D-16 closed (store cleanup):**
- `grep -c "validationResult\b" gui/src/store/useStore.ts` → 0
- `grep -c "validateAndGate|clearValidation" gui/src/store/useStore.ts` → 0
- `grep -c "validateTopology|TopologyResult" gui/src/store/useStore.ts` → 0
- `grep -rn "validateAndGate|clearValidation" gui/src/` (non-test) → nothing

**Files deleted:**
- `gui/src/lib/validation.ts` — deleted via `git rm`
- `gui/src/lib/validation.test.ts` — deleted via `git rm`
- `gui/src/lib/selectors/nodeErrors.ts` — deleted via `git rm`
- `gui/src/lib/selectors/__tests__/nodeErrors.test.ts` — deleted (tested the deleted selector)

**File preserved:**
- `gui/src/lib/selectors/topologyHints.ts` — confirmed present (axis-collision hint, out of scope)

**Rule count:** `ls gui/src/lib/validation/rules/*.ts | wc -l` → 11

## Test Results

- Final: 97 test files, 1033 tests passed, 10 todo — no failures
- TypeScript errors: 10 (down from 13 baseline — 3 fewer; all remaining are pre-existing)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing] Updated test files that imported deleted modules**

- **Found during:** Task 4
- **Issue:** `src/lib/__tests__/validation.test.ts` imported field validators from `../validation` (deleted). `useStore.bc.test.ts` and `CanvasPanel.bc.test.tsx` imported `selectNodeErrors` from the deleted `selectors/nodeErrors.ts`.
- **Fix:** Updated `validation.test.ts` import to `../validation/fields`. Inlined the n-mismatch check as `errorsFor()` in both BC test files (same logic as deleted selector; nMatch path is debounced/async so synchronous inline is needed for test assertions).
- **Files modified:** `src/lib/__tests__/validation.test.ts`, `src/store/__tests__/useStore.bc.test.ts`, `src/components/__tests__/CanvasPanel.bc.test.tsx`
- **Commit:** 5dbfa6e

**2. [Rule 1 - Bug] StreamNode.test.tsx BC red-ring test expected hasBCError behavior**

- **Found during:** Task 4
- **Issue:** Test set up `bcMode` state expecting `hasBCError` subscription to fire; after D-20 removal, the red ring requires `errorNodeIds` to contain the node id.
- **Fix:** Replaced test setup to seed `errorNodeIds: new Set(["wt_red"])` directly, matching D-20 contract.
- **Files modified:** `src/components/__tests__/StreamNode.test.tsx`
- **Commit:** 5dbfa6e

**3. [Rule 1 - Bug] saveProject/saveProjectAs still called validateAndGate**

- **Found during:** Task 3
- **Issue:** After removing the `validateAndGate` action body, `saveProject` and `saveProjectAs` still called it, creating a missing method error. The plan said "Confirm that no `validateAndGate` call remains in src/ after Plan 12" — those calls were not removed in Plan 12.
- **Fix:** Removed the `validateAndGate()` gate calls from both save actions (export gate now lives in `exportCode.ts` via `runValidators`).
- **Files modified:** `src/store/useStore.ts`
- **Commit:** 2e0288e

## Known Stubs

None.

## Threat Flags

None — plan is pure deletion/reroute; no new network endpoints, auth paths, or trust boundaries introduced.

## Self-Check

- [x] `gui/src/lib/validation.ts` deleted
- [x] `gui/src/lib/validation.test.ts` deleted
- [x] `gui/src/lib/selectors/nodeErrors.ts` deleted
- [x] `gui/src/lib/selectors/__tests__/nodeErrors.test.ts` deleted
- [x] `gui/src/lib/selectors/topologyHints.ts` preserved
- [x] Commits 3487d09, 35664b7, 2e0288e, 5dbfa6e exist
- [x] 97/97 test files pass
- [x] TypeScript errors: 10 (≤ 13 baseline — 3 fewer)

## Self-Check: PASSED
