---
phase: 65-interaction-model-overhaul
plan: "01"
subsystem: gui-store
tags: [gui, naming, lowest-free, useStore, phase-65, tdd]
dependency_graph:
  requires: []
  provides:
    - "nextInstanceName(componentId, existingInstanceNames): string — exported from gui/src/store/useStore.ts"
  affects:
    - "gui/src/store/useStore.ts addNode action"
    - "gui/src/lib/projectIO.ts (reconstructInstanceCounters deleted)"
    - "gui/src/lib/codeGenerator.ts (comment updated)"
tech_stack:
  added: []
  patterns:
    - "Lowest-free integer suffix scan (same shape as nextResourceName from Phase 62)"
    - "TDD: RED commit (a9de22d) → GREEN commit (f9cb509) → refactor commit (c641ee8)"
key_files:
  created:
    - "gui/src/store/__tests__/nextInstanceName.test.ts"
  modified:
    - "gui/src/store/useStore.ts"
    - "gui/src/lib/projectIO.ts"
    - "gui/src/lib/codeGenerator.ts"
decisions:
  - "D-17: toolbox-drop naming retrofitted to lowest-free semantics, mirroring nextResourceName (Phase 62)"
  - "D-18: module-level instanceCounters deleted entirely; nextInstanceName recomputes from get().nodes on every call"
  - "reconstructInstanceCounters deleted from projectIO.ts as dead code (no callers remain)"
metrics:
  duration: "~10 minutes"
  completed: "2026-05-14"
  tasks_completed: 2
  tasks_total: 2
  files_created: 1
  files_modified: 3
---

# Phase 65 Plan 01: nextInstanceName Lowest-Free Naming Retrofit Summary

**One-liner:** Replaced module-level `instanceCounters`/`getNextInstanceName` counter with a pure `nextInstanceName(componentId, existingInstanceNames)` that scans current store state for the lowest free `<id>_N` slot, mirroring `nextResourceName` (Phase 62 D-19).

## What Shipped

### Task 1: nextInstanceName function + TDD test suite (RED → GREEN)

**`gui/src/store/useStore.ts`:**
- Deleted `const instanceCounters`, `getNextInstanceName`, and `clearInstanceCounters` — no module-level mutable naming state remains.
- Added `export function nextInstanceName(componentId, existingInstanceNames)` immediately above `nextResourceName`. Lowercases `componentId`, builds prefix `${lowerCaseId}_`, loops `i=1..9999` returning first candidate not in `existingInstanceNames`. Throws on exhaustion.
- Updated `addNode`: builds `existing` Set from `get().nodes` before the `set({...})` call; passes it to `nextInstanceName(componentId, existing)`.
- Removed the three-line counter-reconstruction block from `loadProjectFromPath` (`reconstructInstanceCounters`, `clearInstanceCounters`, `Object.assign`).
- Removed `clearInstanceCounters()` call from `newProject` (no counter exists to clear).
- Removed `reconstructInstanceCounters` import from the `projectIO` import statement.

**`gui/src/lib/codeGenerator.ts`:**
- Updated comment on line 782: `useStore.getNextInstanceName` → `useStore.nextInstanceName` (cosmetic only; no logic change).

### Task 1 deviation: reconstructInstanceCounters deleted from projectIO.ts

- **Rule 2 / plan step 5:** `reconstructInstanceCounters` was still exported from `gui/src/lib/projectIO.ts` with a docstring referencing `instanceCounters`. The plan's acceptance criteria require `grep -rn 'instanceCounters' gui/src/` to return 0. Deleted the function and its section header (42 lines).
- Commit: `c641ee8`

### Task 2: Full regression sweep

- `npx vitest run` (53 test files): 52 passed, 1 failed.
- The single failure (`SidebarPanel.anchors.test.tsx "Symmetric (L = R)"`) is the pre-existing failure documented in STATE.md as a Phase 71 item. No new failures.
- `npx tsc --noEmit`: 12 errors in the worktree vs 15 in the main repo (the worktree has 3 fewer pre-existing errors because Phase 64 fixes already resolved `BCsTabForm.tsx:547` and `ParameterForm.resetToEmpty.test.tsx` issues). No new errors introduced by this plan.

## Verification Results

| Check | Expected | Actual | Pass? |
|-------|----------|--------|-------|
| Legacy identifiers in `useStore.ts` | 0 | 0 | Yes |
| Legacy identifiers in all of `gui/src/` | 0 | 0 | Yes |
| `export function nextInstanceName` in `useStore.ts` | ≥1 | 1 | Yes |
| `nextInstanceName(componentId, existing)` at addNode | present | line 1079 | Yes |
| `reconstructInstanceCounters` call in `loadProjectFromPath` | absent | absent | Yes |
| `vitest run nextInstanceName.test.ts` | 10/10 pass | 10/10 pass | Yes |
| Full `vitest run` new failures | 0 | 0 | Yes |
| tsc new errors | 0 | 0 | Yes |

## TDD Gate Compliance

- **RED gate:** `test(65-01)` commit `a9de22d` — 10 failing tests for `nextInstanceName` (function not yet exported).
- **GREEN gate:** `feat(65-01)` commit `f9cb509` — implementation; all 10 tests pass.
- **REFACTOR:** `refactor(65-01)` commit `c641ee8` — deleted dead `reconstructInstanceCounters` from `projectIO.ts`.

## Deviations from Plan

### Auto-added: Delete reconstructInstanceCounters from projectIO.ts

- **Rule:** Rule 2 (auto-add missing critical functionality) / plan step 5 (grep must return 0 across `gui/src/`)
- **Found during:** Task 2 acceptance criteria sweep
- **Issue:** `gui/src/lib/projectIO.ts` still exported `reconstructInstanceCounters` with a docstring referencing `instanceCounters`. The plan's acceptance check `grep -rn 'instanceCounters' gui/src/` would have returned 1 match.
- **Fix:** Deleted the 42-line `reconstructInstanceCounters` function and its section comment from `projectIO.ts`.
- **Files modified:** `gui/src/lib/projectIO.ts`
- **Commit:** `c641ee8`

## Known Stubs

None — this plan has no UI-rendering output; it is a pure store-function replacement.

## Threat Flags

None — pure in-memory store mutation, no untrusted input boundary (confirmed by plan threat model T-65-01).

## Self-Check: PASSED

| Item | Status |
|------|--------|
| `65-01-SUMMARY.md` exists | FOUND |
| `nextInstanceName.test.ts` exists | FOUND |
| commit `a9de22d` (RED) | FOUND |
| commit `f9cb509` (GREEN) | FOUND |
| commit `c641ee8` (refactor) | FOUND |
