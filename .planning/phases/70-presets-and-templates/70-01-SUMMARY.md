---
phase: 70-presets-and-templates
plan: "01"
subsystem: gui
tags: [tauri, cargo, acl, shadcn, presets, substrate]
dependency_graph:
  requires: []
  provides:
    - tauri-plugin-fs watch feature enabled in Cargo.toml
    - fs:allow-watch + fs:allow-unwatch + fs:scope-appconfig-recursive ACL permissions
    - $APPCONFIG/presets/** fs:scope entry in capabilities/default.json
    - shadcn Textarea component (pending human install — Task 3 checkpoint)
    - shadcn RadioGroup + RadioGroupItem components (pending human install — Task 3 checkpoint)
  affects:
    - gui/src-tauri/Cargo.toml
    - gui/src-tauri/capabilities/default.json
    - gui/src/components/ui/textarea.tsx (pending)
    - gui/src/components/ui/radio-group.tsx (pending)
tech_stack:
  added: []
  patterns:
    - Tauri ACL capability scope with $APPCONFIG variable
    - Cargo feature table form for conditional Rust feature flags
key_files:
  created: []
  modified:
    - gui/src-tauri/Cargo.toml
    - gui/src-tauri/capabilities/default.json
decisions:
  - "Two separate fs:scope objects kept (autorecover vs presets) to document intent separately per plan spec"
  - "watch feature added to Cargo.toml table form without version bump per RESEARCH.md Q1"
  - "Cargo rebuild deferred to Wave 4 (70-06) — hot-reload does not pick up feature flag changes"
metrics:
  duration: "~2 minutes"
  completed_date: "2026-05-20"
  tasks_completed: 2
  tasks_total: 3
  files_created: 0
  files_modified: 2
---

# Phase 70 Plan 01: Platform Substrate — Tauri FS Watch + ACL + shadcn Primitives Summary

## One-liner

Tauri `watch` Cargo feature enabled and four ACL permissions/scopes added for `$APPCONFIG/presets/**` watching; shadcn `textarea` and `radio-group` install delegated to human checkpoint.

## What Was Built

### Task 1 — Cargo.toml watch feature (commit 7ead751)

Changed `tauri-plugin-fs = "2.4.5"` to the table form with `features = ["watch"]`. This enables the Rust-side IPC command that the JS `watch()` import from `@tauri-apps/plugin-fs` calls at runtime. Without this feature flag, importing `watch` succeeds (JS types are bundled regardless) but the actual IPC call fails at runtime.

### Task 2 — capabilities/default.json ACL additions (commit 334241d)

Added to the `permissions` array immediately after the existing `fs:allow-read-dir` entry:
- `"fs:allow-watch"` — allows the `watch` IPC command
- `"fs:allow-unwatch"` — allows the `unwatch` IPC command (cleanup)
- `"fs:scope-appconfig-recursive"` — grants recursive access to `$APPCONFIG` directory
- New `fs:scope` object with `allow: [{ "path": "$APPCONFIG/presets/**" }]` — restricts path-scope to preset directory only

The existing `$APPDATA/STREAM-Composer/autorecover/**` scope object is preserved unchanged as a separate sibling (different subsystems, separate scope objects document intent clearly).

JSON validity confirmed via `node -e "JSON.parse(...)"`.

### Task 3 — shadcn primitives install (CHECKPOINT: awaiting human)

This task is a `type="checkpoint:human-verify" gate="blocking-human"` — requires the human to run:
```
cd gui && npx shadcn@latest add textarea radio-group
```
and verify that `gui/src/components/ui/textarea.tsx` and `gui/src/components/ui/radio-group.tsx` exist with their expected exports before resuming.

## Deviations from Plan

None — Tasks 1 and 2 executed exactly as written. Task 3 is a blocking human checkpoint, not a deviation.

## Threat Surface Scan

| Flag | File | Description |
|------|------|-------------|
| threat_flag: privilege-scope | gui/src-tauri/capabilities/default.json | New `$APPCONFIG/presets/**` scope grants watch/read/write into app config directory. Mitigated: scope variable `$APPCONFIG` is Tauri-controlled and resolves only to `~/.config/com.stream.composer/` on Linux — cannot escape the per-app directory. T-70-01 and T-70-02 from plan threat register apply. |

## Self-Check: PASSED

- [x] `gui/src-tauri/Cargo.toml` exists and contains `features = ["watch"]`
- [x] `gui/src-tauri/capabilities/default.json` parses as valid JSON and contains all four required entries
- [x] Commit 7ead751 exists (Task 1)
- [x] Commit 334241d exists (Task 2)
- [x] No files deleted by commits (additions only)
