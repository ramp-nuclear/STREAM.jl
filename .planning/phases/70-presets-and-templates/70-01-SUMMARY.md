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
    - shadcn Textarea component
    - shadcn RadioGroup + RadioGroupItem components
  affects:
    - gui/src-tauri/Cargo.toml
    - gui/src-tauri/capabilities/default.json
    - gui/src/components/ui/textarea.tsx
    - gui/src/components/ui/radio-group.tsx
tech_stack:
  added: []
  patterns:
    - Tauri ACL capability scope with $APPCONFIG variable
    - Cargo feature table form for conditional Rust feature flags
key_files:
  created:
    - gui/src/components/ui/textarea.tsx
    - gui/src/components/ui/radio-group.tsx
  modified:
    - gui/src-tauri/Cargo.toml
    - gui/src-tauri/capabilities/default.json
decisions:
  - "Two separate fs:scope objects kept (autorecover vs presets) to document intent separately per plan spec"
  - "watch feature added to Cargo.toml table form without version bump per RESEARCH.md Q1"
  - "Cargo rebuild deferred to Wave 4 (70-06) — hot-reload does not pick up feature flag changes"
  - "Task 3 shadcn install executed inline by the orchestrator after the checkpoint surfaced: this is a deterministic first-party shadcn add and the no-inline-human-verify project rule applies. shadcn pulled zero new package.json / pnpm-lock.yaml entries (Radix deps already satisfied), and the two new component files compile clean."
metrics:
  duration: "~4 minutes"
  completed_date: "2026-05-20"
  tasks_completed: 3
  tasks_total: 3
  files_created: 2
  files_modified: 2
---

# Phase 70 Plan 01: Platform Substrate — Tauri FS Watch + ACL + shadcn Primitives Summary

## One-liner

Tauri `watch` Cargo feature enabled, four ACL permissions/scopes added for `$APPCONFIG/presets/**` watching, and shadcn `textarea` + `radio-group` primitives installed for the Save-as-Preset modal.

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

### Task 3 — shadcn primitives install (commit 1849d39)

Ran `npx shadcn@latest add textarea radio-group` from `gui/`, which dropped two first-party shadcn registry components into `gui/src/components/ui/`:
- `textarea.tsx` (759 B) — `export { Textarea }`
- `radio-group.tsx` (1446 B) — `export { RadioGroup, RadioGroupItem }`

shadcn did not touch `gui/package.json` or `pnpm-lock.yaml` — the required `@radix-ui/react-radio-group` dep was already pulled in by an existing primitive. `npx tsc --noEmit` from `gui/` produced 13 errors, all in pre-existing files unrelated to the new primitives (`StreamNode.tsx`, `BCsTabForm.test.tsx`, `SidebarRouter.test.tsx`, `validation.test.ts`, `saveProjectAs.test.ts`); the baseline count in STATE.md (11) was stale, not a regression introduced here.

## Deviations from Plan

The plan marked Task 3 as `checkpoint:human-verify` with `blocking-human` gate. The orchestrator surfaced the checkpoint to the user, who pushed back: a deterministic first-party shadcn install is exactly the inline-UAT anti-pattern flagged in the project's `feedback_no_inline_human_verify` rule. The orchestrator therefore ran the install in the worktree itself, verified file existence + exports + tsc baseline, and committed the result on behalf of the executor. No code-level deviation — the same files landed with the same contents; only the "who pressed enter" changed.

## Threat Surface Scan

| Flag | File | Description |
|------|------|-------------|
| threat_flag: privilege-scope | gui/src-tauri/capabilities/default.json | New `$APPCONFIG/presets/**` scope grants watch/read/write into app config directory. Mitigated: scope variable `$APPCONFIG` is Tauri-controlled and resolves only to `~/.config/com.stream.composer/` on Linux — cannot escape the per-app directory. T-70-01 and T-70-02 from plan threat register apply. |

## Self-Check: PASSED

- [x] `gui/src-tauri/Cargo.toml` exists and contains `features = ["watch"]`
- [x] `gui/src-tauri/capabilities/default.json` parses as valid JSON and contains all four required entries
- [x] Commit 7ead751 exists (Task 1)
- [x] Commit 334241d exists (Task 2)
- [x] Commit 1849d39 exists (Task 3 — shadcn primitives)
- [x] `gui/src/components/ui/textarea.tsx` exists and exports `Textarea`
- [x] `gui/src/components/ui/radio-group.tsx` exists and exports `RadioGroup`, `RadioGroupItem`
- [x] No new package.json / pnpm-lock.yaml entries (verified via `git diff --stat`)
- [x] No files deleted by commits (additions only)
