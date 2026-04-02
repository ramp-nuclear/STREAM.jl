---
phase: 37-project-persistence
plan: 01
subsystem: ui
tags: [zustand, tauri, typescript, vitest, serialization, file-io]

# Dependency graph
requires:
  - phase: 36-code-generation
    provides: BCEntry type and codeGenerator.ts structure reused by projectIO
  - phase: 34-canvas-node-editor
    provides: Zustand store with zundo temporal middleware that Task 2 extends

provides:
  - "projectIO.ts: pure serializeProject/deserializeProject/addToRecent/reconstructInstanceCounters"
  - "useStore.ts extended with isDirty, currentFilePath, recentFiles state"
  - "saveProject, saveProjectAs, loadProject, loadProjectFromPath, newProject store actions"
  - "loadRecentFiles/saveRecentFiles helpers for recent.json persistence"
  - "initializeRecentFiles() export for App.tsx mount"
  - "Tauri capabilities updated with fs:allow-read-text-file, fs:allow-exists, fs:allow-mkdir"

affects:
  - 37-02 (File menu UI, WelcomeOverlay — consumes all store actions from this plan)
  - 37-03 (close guard + keyboard shortcuts — consumes isDirty and saveProject)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Dynamic Tauri API imports inside async store actions to avoid vitest node-env breakage"
    - "reconstructInstanceCounters pattern for Pitfall 6: counter continuity after project load"
    - "isDirty manual flagging in each content-mutating action (not middleware) — matches zundo partialize precision"

key-files:
  created:
    - gui/src/lib/projectIO.ts
    - gui/src/lib/__tests__/projectIO.test.ts
  modified:
    - gui/src/store/useStore.ts
    - gui/src/store/__tests__/useStore.test.ts
    - gui/src-tauri/capabilities/default.json

key-decisions:
  - "Dynamic imports (`await import('@tauri-apps/...')`) inside store actions instead of top-level imports: keeps vitest node environment working without mocking Tauri — all file I/O actions are tested manually via cargo tauri dev"
  - "reconstructInstanceCounters extracts prefix via /^(.+)_(\\d+)$/ and tracks max per prefix — restores correct counter state after project load (Pitfall 6)"
  - "beforeEach in useStore.test.ts reset to include isDirty: false alongside nodes/edges — prevents state bleed between tests"

patterns-established:
  - "Pattern: Dynamic Tauri API import — import Tauri APIs inside async functions to avoid test-env failures"
  - "Pattern: isDirty manual flagging — add isDirty: true to each content-mutating set() call explicitly"

requirements-completed: [PERS-01, PERS-02, PERS-03, PERS-04]

# Metrics
duration: 3min
completed: 2026-04-02
---

# Phase 37 Plan 01: Project Persistence Data Layer Summary

**Pure serialization layer with Zustand store extended for isDirty tracking, save/load/new file I/O actions, and recent.json persistence via Tauri plugin-fs**

## Performance

- **Duration:** 3 min
- **Started:** 2026-04-02T18:50:43Z
- **Completed:** 2026-04-02T18:54:21Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Created `projectIO.ts` with 4 pure exported functions tested by 29 unit tests: `serializeProject` (version+nodes+edges+bcs JSON), `deserializeProject` (validates structure, throws on bad input), `addToRecent` (dedup+prepend+truncate-5), `reconstructInstanceCounters` (max counter per prefix from node names)
- Extended Zustand store with `isDirty`/`currentFilePath`/`recentFiles` state and 6 file I/O actions; all 9 content-mutating actions now set `isDirty: true`; `selectNode` and `toggleBottomPanel` correctly excluded
- Added 10 isDirty tracking tests; updated `beforeEach` to reset `isDirty: false` to prevent inter-test state bleed

## Task Commits

Each task was committed atomically:

1. **Task 1: Create projectIO.ts with serialization, deserialization, and recent-files logic** - `a55bdb7` (feat)
2. **Task 2: Extend Zustand store with persistence state and file I/O actions, update Tauri permissions** - `462689b` (feat)

**Plan metadata:** (created next)

## Files Created/Modified
- `gui/src/lib/projectIO.ts` — Pure serialization/deserialization, addToRecent, reconstructInstanceCounters (no side-effects)
- `gui/src/lib/__tests__/projectIO.test.ts` — 29 unit tests for all projectIO functions
- `gui/src/store/useStore.ts` — isDirty/currentFilePath/recentFiles state; saveProject/saveProjectAs/loadProject/loadProjectFromPath/newProject actions; loadRecentFiles/saveRecentFiles helpers; initializeRecentFiles export
- `gui/src/store/__tests__/useStore.test.ts` — Added 10 isDirty tracking tests; fixed beforeEach to reset isDirty
- `gui/src-tauri/capabilities/default.json` — Added fs:allow-read-text-file, fs:allow-exists, fs:allow-mkdir

## Decisions Made
- Dynamic Tauri API imports inside async store actions (`await import('@tauri-apps/...')`) avoid vitest node-environment failures while keeping the real Tauri APIs in production. No mocks needed.
- `reconstructInstanceCounters` uses `/^(.+)_(\d+)$/` regex to parse `instanceName` fields and track max counter per lowercase prefix — restores correct naming continuity after project load (Pitfall 6 from RESEARCH.md).
- `beforeEach` in useStore tests now resets `isDirty: false` explicitly to prevent bleed from prior tests that set it to true.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed beforeEach to reset isDirty in test file**
- **Found during:** Task 2 (isDirty tracking tests)
- **Issue:** The "isDirty starts false" test failed because the existing `beforeEach` reset `nodes/edges/selectedNodeId` but not `isDirty`. Prior tests left `isDirty: true` in the store state.
- **Fix:** Added `isDirty: false` to the `useStore.setState(...)` call in `beforeEach`.
- **Files modified:** `gui/src/store/__tests__/useStore.test.ts`
- **Verification:** All 31 useStore tests pass
- **Committed in:** `462689b` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug in test setup)
**Impact on plan:** Necessary for test correctness. No scope creep.

## Issues Encountered
None beyond the `beforeEach` reset issue documented above.

## User Setup Required
None — no external service configuration required. Tauri capabilities updates take effect on next `cargo tauri dev` or `cargo tauri build`.

## Next Phase Readiness
- Plan 02 (File menu UI + WelcomeOverlay) can import all store actions: `saveProject`, `saveProjectAs`, `loadProject`, `loadProjectFromPath`, `newProject`, `setRecentFiles`
- Plan 02 can read `isDirty`, `currentFilePath`, `recentFiles` from store
- `initializeRecentFiles()` exported and ready for App.tsx mount call
- All file I/O actions include proper error dialogs matching UI-SPEC copy

## Self-Check: PASSED

- `gui/src/lib/projectIO.ts` — FOUND
- `gui/src/lib/__tests__/projectIO.test.ts` — FOUND
- `gui/src/store/useStore.ts` — FOUND
- `gui/src-tauri/capabilities/default.json` — FOUND
- `.planning/phases/37-project-persistence/37-01-SUMMARY.md` — FOUND
- Commit `a55bdb7` — FOUND
- Commit `462689b` — FOUND

---
*Phase: 37-project-persistence*
*Completed: 2026-04-02*
