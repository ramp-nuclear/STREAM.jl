---
phase: 65-interaction-model-overhaul
plan: 08
subsystem: ui
tags: [autorecover, restore-modal, app-shell, crash-detection, phase-65]

# Dependency graph
requires:
  - phase: 65-07
    provides: autoRecover.ts substrate + initAutoRecover lifecycle + untitledProjectUuid
provides:
  - "gui/src/components/AutoRecoverRestoreModal.tsx: blocking modal, D-03 Esc+outside-click invariant"
  - "gui/src/store/useStore.ts: recoverFromSidecar + discardAllSidecars actions"
  - "gui/src/App.tsx: mount crash-detection, render gate, teardown on unmount"
affects: []

# Tech tracking
tech-stack:
  added:
    - "@radix-ui/react-dialog (already in node_modules; first use in STREAM Composer)"
  patterns:
    - "render gate pattern: useState<T | null>(null) for async init with boot splash + modal branch"
    - "try/finally in modal resolution handlers — initAutoRecover always runs even on hydration error"
    - "TDD RED/GREEN: test file committed before implementation"

key-files:
  created:
    - "gui/src/components/AutoRecoverRestoreModal.tsx — Radix Dialog, onEscapeKeyDown+onPointerDownOutside preventDefault, Recover/Discard buttons"
    - "gui/src/components/__tests__/AutoRecoverRestoreModal.test.tsx — 8 vitest cases"
    - "gui/src/store/__tests__/autoRecover.actions.test.ts — 5 vitest cases"
  modified:
    - "gui/src/store/useStore.ts — recoverFromSidecar + discardAllSidecars actions added"
    - "gui/src/App.tsx — AutoRecover mount effect, render gate, teardown ref"

key-decisions:
  - "Display raw ISO timestamp with T→space replacement instead of toLocaleString() — locale formatting varies by test environment; ISO keeps date fragment stable for tests and is readable enough for users"
  - "DEFER initAutoRecover on crash path: do not start writer+lockfile until user resolves modal (prevents clobbering stale lockfile while crash-detection inspects it)"
  - "try/finally in handleRecover/handleDiscard: user has committed to a choice by clicking; must not strand them with modal still open AND no autoRecover writer running even if hydration throws"

# Metrics
duration: 25min
completed: 2026-05-14
---

# Phase 65 Plan 08: AutoRecover Restore Modal Summary

**Blocking crash-restore modal (D-03/D-04): AutoRecoverRestoreModal + recoverFromSidecar + discardAllSidecars + App.tsx mount integration with render gate**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-05-14T18:21:00Z
- **Completed:** 2026-05-14T18:26:00Z
- **Tasks:** 2 automated + 1 manual smoke (checkpoint:human-verify)
- **Files modified:** 5

## Accomplishments

- Created `gui/src/components/AutoRecoverRestoreModal.tsx` — Radix `@radix-ui/react-dialog` based blocking modal:
  - `onEscapeKeyDown={(e) => e.preventDefault()}` + `onPointerDownOutside={(e) => e.preventDefault()}` (D-03)
  - Shows "Recover unsaved work from `<timestamp>` in `<displayName>`?" with Recover / Discard buttons
  - `candidates.length === 0` → returns null (defensive guard)
  - `candidates.length > 1` → `console.warn` + picks first (D-03 single-candidate UX for v1.2)
- Added `recoverFromSidecar(basename)` to `useStore.ts`:
  - Reads sidecar, deserializes via `projectIO.deserializeProject`, hydrates store (same shape as `loadProjectFromPath`)
  - Sets `isDirty: true` + `currentFilePath: null` (D-04 Save-As gate for recovered untitled projects)
  - Silent-failure cleanup: on null or malformed sidecar → `clearSidecar + clearLockfile` to prevent boot-loop
- Added `discardAllSidecars()` to `useStore.ts`:
  - `enumerateSidecars()` → `clearSidecar` each → `clearLockfile`
- Wired `App.tsx` with render gate pattern:
  - `null` state = crash check in progress → minimal boot splash `<div>`
  - `length > 0` = crash detected → `<AutoRecoverRestoreModal>` (canvas does NOT mount)
  - `[]` = clean launch → normal workspace
  - Mount effect: `invoke('get_pid')` → `detectCrashOnLaunch(pid)` → branch on `result.crashed`
  - `teardownRef` stores initAutoRecover's teardown function → called on unmount
  - `handleRecover` / `handleDiscard`: `try/finally` guarantees `initAutoRecover` always runs + modal always closes

## Task Commits

1. **Task 1 RED** - `3c57e22` — failing tests for AutoRecoverRestoreModal + store actions
2. **Task 1 GREEN** - `ce1b8a2` — AutoRecoverRestoreModal component + store actions
3. **Task 2** - `2758e25` — App.tsx mount/unmount integration

## Files Created/Modified

- `gui/src/components/AutoRecoverRestoreModal.tsx` — New blocking restore modal (Radix Dialog)
- `gui/src/components/__tests__/AutoRecoverRestoreModal.test.tsx` — 8 vitest cases (render, text, buttons, zero-candidates)
- `gui/src/store/__tests__/autoRecover.actions.test.ts` — 5 vitest cases (recoverFromSidecar valid/null/malformed, discardAllSidecars)
- `gui/src/store/useStore.ts` — `recoverFromSidecar` + `discardAllSidecars` actions + interface declarations
- `gui/src/App.tsx` — AutoRecover mount effect, render gate, teardown ref, modal resolution handlers

## Decisions Made

1. **ISO timestamp display**: Use `candidate.modifiedAt.replace("T", " ")` rather than `toLocaleString()`. `toLocaleString()` formats vary by locale/environment (test failure on "2026-05-14" substring check), and the ISO format is unambiguous and legible enough for a crash-recovery dialog.

2. **Deferred initAutoRecover on crash path**: When crash is detected, do NOT call `initAutoRecover()` until after the user resolves the modal. Starting the writer immediately would write a new lockfile, potentially confusing the crash-detection inspection window.

3. **try/finally in modal handlers**: A malformed sidecar file can cause `recoverFromSidecar` to throw (parsed via `deserializeProject` which throws on bad format_version). The user has already clicked "Recover" — the app must not stay frozen on the modal screen. `finally` ensures `initAutoRecover()` runs and `setRestoreCandidates([])` fires.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] vi.fn<[T], R> type annotation syntax — vitest 4.x**
- **Found during:** Task 1 GREEN verification (tsc --noEmit)
- **Issue:** `vi.fn<[string], Promise<string | null>>()` uses the older vitest 3.x two-argument generic; vitest 4.x uses `vi.fn<(arg: T) => R>()`
- **Fix:** Changed `vi.fn<[string], Promise<...>>()` to `vi.fn<(basename: string) => Promise<...>>()`; updated mock dispatch lambdas to use typed params
- **Files modified:** `gui/src/store/__tests__/autoRecover.actions.test.ts`
- **Commit:** ce1b8a2

**2. [Rule 1 - Bug] Unused `beforeEach` import in modal test**
- **Found during:** Task 1 GREEN (tsc --noEmit TS6133 unused variable)
- **Fix:** Removed `beforeEach` from the import statement; tests use only `afterEach`
- **Files modified:** `gui/src/components/__tests__/AutoRecoverRestoreModal.test.tsx`
- **Commit:** ce1b8a2

---

**Total deviations:** 2 auto-fixed (Rule 1 — minor test-file issues)
**Impact on plan:** None — no scope change, no behavior change.

## Known Stubs

None — the modal is fully wired. The manual smoke (Task 3 checkpoint) verifies end-to-end behavior including the Tauri IPC path (`get_pid`, `is_pid_alive`) which cannot be exercised in vitest.

## Threat Flags

T-65-13 mitigated: `recoverFromSidecar` wraps `deserializeProject` in try/catch; corrupted sidecar is removed on failure to prevent boot-loop.
T-65-14 mitigated: `onEscapeKeyDown` + `onPointerDownOutside` both call `e.preventDefault()` on Radix `DialogContent`; no close button rendered. Manual smoke step 9 enforces.

## Checkpoint: Manual Smoke Required

Task 3 is a `checkpoint:human-verify` — the orchestrator must run the end-to-end smoke test described in the plan (13 verification steps: sidecar write, lock lifecycle, simulated kill -9, modal appearance, Esc blocking, Recover/Discard behavior).

---
*Phase: 65-interaction-model-overhaul*
*Completed: 2026-05-14*
