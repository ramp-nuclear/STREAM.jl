---
phase: 65-interaction-model-overhaul
plan: 07
subsystem: ui
tags: [autorecover, sidecar, lockfile, tauri-fs, sysinfo, debounce, zustand, phase-65]

# Dependency graph
requires:
  - phase: 65-06
    provides: snapToGrid layout block changes in useStore.ts and .scp format
provides:
  - "gui/src/lib/autoRecover.ts: 14 exports — pure path helpers, sidecar I/O, lockfile API, crash detection, debounced writer factory"
  - "Tauri commands: is_pid_alive (sysinfo 0.30) + get_pid registered in lib.rs"
  - "useStore.ts: untitledProjectUuid field, initAutoRecover() exported function, sidecar cleared on saveProject/saveProjectAs/newProject"
affects: [65-08]

# Tech tracking
tech-stack:
  added:
    - "sysinfo 0.30 (Rust, default-features=false) — cross-platform PID-alive check"
  patterns:
    - "dynamic-import Tauri API pattern for testability (same as loadRecentFiles in useStore.ts)"
    - "debounced writer factory with schedule/cancel/flush API"
    - "untitledProjectUuid: stable per-session UUID for untitled project sidecar filename"

key-files:
  created:
    - "gui/src/lib/autoRecover.ts — AutoRecover substrate: path sanitization, sidecar/lockfile I/O, crash detection, debounce"
    - "gui/src/lib/__tests__/autoRecover.test.ts — 22 vitest cases covering pure helpers + debounce timing + crash detection"
  modified:
    - "gui/src/store/useStore.ts — untitledProjectUuid, initAutoRecover, clearSidecar on save/newProject"
    - "gui/src-tauri/src/lib.rs — is_pid_alive + get_pid Tauri commands"
    - "gui/src-tauri/Cargo.toml — sysinfo = {version=0.30, default-features=false}"

key-decisions:
  - "sysinfo 0.30 with default-features=false chosen for PID-alive check (B5 pin per plan); refresh_processes() takes no args in 0.30 (fixed at implementation time)"
  - "Sidecar cleared AFTER successful save (not before) — if crash between write + clear, user sees redundant restore prompt but no data loss; documented as known minor wart (T-65-12b)"
  - "initAutoRecover() subscribes to entire state (not just isDirty transitions) — each state change calls schedule() or cancel(); debounce internal logic handles redundant schedule calls via timer reset"
  - "Untitled project UUID stored in zustand state (not module-level) so it resets cleanly on newProject and survives HMR"

patterns-established:
  - "AutoRecover I/O: always dynamic-import Tauri APIs; wrap all calls in try/catch with silent failure"
  - "Debounced writer: schedule() clears+resets timer; cancel() clears+nulls; flush() clears+awaits immediately"
  - "Lockfile format: two-line text — pid on line 1, ISO timestamp on line 2; parseLockfileContent validates strictly"

requirements-completed: []

# Metrics
duration: 35min
completed: 2026-05-14
---

# Phase 65 Plan 07: AutoRecover I/O Substrate Summary

**Debounced sidecar writer substrate: 14-export autoRecover.ts module + sysinfo-backed is_pid_alive Tauri command + untitledProjectUuid store field + initAutoRecover() lifecycle hook**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-05-14T18:04:00Z
- **Completed:** 2026-05-14T18:12:00Z
- **Tasks:** 2 (TDD: RED + GREEN + Task 2)
- **Files modified:** 5

## Accomplishments

- Created `gui/src/lib/autoRecover.ts` with 14 exports: path resolution, sidecar read/write/clear/enumerate, lockfile write/read/clear/parse, crash detection, debounced writer factory
- Path-traversal mitigation: `getSidecarBasename` sanitizes to `[A-Za-z0-9._-]+` — `../../etc/passwd` input yields `passwd.scp.autosave` (T-65-09)
- Lockfile parser validates PID as positive integer; any malformed input returns null (T-65-10)
- Rust: `is_pid_alive(pid)` using sysinfo 0.30 + `get_pid()` both registered in `invoke_handler!`
- Store: `untitledProjectUuid` field + `initAutoRecover()` exported lifecycle function + sidecar cleared on all save/newProject success paths
- 22 vitest cases pass; cargo check exits 0; no new TypeScript errors

## Task Commits

1. **Task 1 RED: failing tests** - `7cfed5a` (test)
2. **Task 1 GREEN: autoRecover.ts + Tauri commands** - `8d53cbe` (feat)
3. **Task 2: store integration** - `036366a` (feat)

## Files Created/Modified

- `gui/src/lib/autoRecover.ts` — Pure substrate: 14 exports for sidecar path resolution, I/O, lockfile API, crash detection, debounced writer factory
- `gui/src/lib/__tests__/autoRecover.test.ts` — 22 vitest cases: getSidecarBasename (6), parseLockfileContent (7), detectCrashOnLaunch (3), createDebouncedSidecarWriter (5) + fake timers
- `gui/src/store/useStore.ts` — untitledProjectUuid field + initial value + newProject regeneration; saveProject/saveProjectAs clearSidecar on success; initAutoRecover() export
- `gui/src-tauri/src/lib.rs` — is_pid_alive + get_pid commands added to generate_handler!
- `gui/src-tauri/Cargo.toml` — sysinfo = {version="0.30", default-features=false}

## Decisions Made

1. **sysinfo 0.30 API fix**: The plan's code snippet used `refresh_processes(ProcessesToUpdate::All, false)` which is the sysinfo 0.33+ API. sysinfo 0.30 uses `refresh_processes()` with no arguments. Fixed at implementation time — pinned version honored, API adjusted.

2. **Sidecar-clear race (T-65-12b)**: Sidecar is cleared AFTER successful writeTextFile, not before. If the app crashes between the two operations, the user sees a restore modal on next launch but the recovered state is identical to what was just saved — no data loss, just a redundant prompt. The alternative (clear before write) loses crash protection during the write window, which is worse.

3. **Subscribe pattern**: `useStore.subscribe((state) => { if (state.isDirty) writer.schedule(); else writer.cancel(); })` fires on every state change. Each schedule() call resets the 2s timer — correct debounce resets on rapid edits without needing to track previous state.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] sysinfo 0.30 refresh_processes() takes no arguments**
- **Found during:** Task 1 (Rust implementation)
- **Issue:** Plan snippet used `sys.refresh_processes(sysinfo::ProcessesToUpdate::All, false)` which is the sysinfo 0.33+ API. sysinfo 0.30 exposes `refresh_processes()` with no arguments.
- **Fix:** Changed to `sys.refresh_processes()` — matches the pinned 0.30 version exactly.
- **Files modified:** gui/src-tauri/src/lib.rs
- **Verification:** `cargo check` exits 0 after fix
- **Committed in:** 8d53cbe (Task 1 GREEN commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - version API mismatch)
**Impact on plan:** Minimal — same sysinfo version, different method signature. No scope change.

## Issues Encountered

- vitest `node_modules` not present in worktree — resolved by running `npm install --ignore-scripts` in `gui/` within the worktree before first test run. Pre-existing behavior for worktree-isolated agents.

## Tauri Smoke Test Note

The plan's Task 1 acceptance criteria includes a manual one-line smoke test:
```javascript
await window.__TAURI__.core.invoke('is_pid_alive', { pid: 1 });
```
This verifies the Tauri command is registered and callable from JS. This plan is a parallel worktree executor and does not have access to a running Tauri dev process. Plan 08 (restore modal) will perform end-to-end smoke testing that exercises the full IPC path including `is_pid_alive` and `get_pid`. The vitest suite mocks all Tauri IPC and verifies the TS-side logic thoroughly.

## Known Stubs

None — the module is pure substrate (no UI, no hardcoded data). Plan 08 wires `initAutoRecover()` into `App.tsx` mount/unmount and adds the restore modal UI.

## Threat Flags

No new security surface beyond what was in the plan's threat model:
- T-65-09 mitigated: `getSidecarBasename` enforces `[A-Za-z0-9._-]+` charset
- T-65-10 mitigated: `parseLockfileContent` validates pid as positive integer; timestamp as non-empty string
- T-65-11 accepted: `is_pid_alive` IPC surface is local-only
- T-65-12b documented: sidecar-clear race after save is benign (no data loss)

## Next Phase Readiness

Plan 08 (restore modal) can now:
1. Import `initAutoRecover` from `useStore.ts` and call it from `App.tsx` `useEffect`
2. Import `detectCrashOnLaunch` + `readSidecar` + `clearSidecar` from `autoRecover.ts` for the restore flow
3. Render the blocking modal before workspace loads using `CrashDetectionResult.crashed` + `CrashDetectionResult.sidecars`

---
*Phase: 65-interaction-model-overhaul*
*Completed: 2026-05-14*
