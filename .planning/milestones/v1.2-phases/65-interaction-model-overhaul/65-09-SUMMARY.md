---
phase: 65-interaction-model-overhaul
plan: 09
subsystem: autorecover-bridge
tags: [autorecover, tauri-capabilities, blocker, gap-closure, phase-65]
gap_closure: true
requires:
  - Plan 65-07 (AutoRecover I/O substrate — produces autoRecover.ts)
  - Plan 65-08 (AutoRecoverRestoreModal — wired to detectCrashOnLaunch)
provides:
  - Tauri v2 fs ACL grants for $APPDATA (functional fix)
  - Defense-in-depth structured fs:scope narrowed to autorecover/**
  - DEV-mode logging on every previously-silent autoRecover catch block
  - In-source v2 IPC invocation rationale (autoRecover.ts header)
affects:
  - gui/src-tauri/capabilities/default.json
  - gui/src/lib/autoRecover.ts
  - gui/src/App.tsx
tech-stack:
  added: []
  patterns:
    - "Tauri v2 ACL union-of-grants: flat permission strings + structured {identifier, allow:[{path}]} objects coexist in the same permissions array"
    - "import.meta.env.DEV gate for DEV-only console.warn (Vite strips branch in production)"
key-files:
  created: []
  modified:
    - gui/src-tauri/capabilities/default.json
    - gui/src/lib/autoRecover.ts
    - gui/src/App.tsx
decisions:
  - "Add BOTH broad appdata grants (functional) AND structured fs:scope narrowing (defense-in-depth) — Tauri v2 ACL is union-of-grants, so the narrower entry documents intent without revoking the broader grants."
  - "Log under import.meta.env.DEV only — production builds strip the branch; user-facing behavior unchanged; failures still silent to callers."
  - "Add v2 IPC rationale as a JSDoc-style block adjacent to the surprising code (autoRecover.ts isPidAlive) rather than only in a UAT prose doc — future debuggers reading the IPC site see the rationale immediately."
metrics:
  duration: ~7 min
  completed: 2026-05-15
---

# Phase 65 Plan 09: AutoRecover capability fix Summary

Tauri v2 capability ACL grants `$APPDATA` fs scope + write/remove/read-dir permissions (plus a defense-in-depth structured `fs:scope` entry narrowed to `STREAM-Composer/autorecover/**`); the seven previously-silent catch blocks in `autoRecover.ts` plus `isPidAlive` now log under DEV mode, and a JSDoc header documents why ES-module `@tauri-apps/api/core` invocation is the v2-correct path (not `window.__TAURI__`).

## What Was Built

### Task 1 — Capability JSON (`fix(65-09): grant appdata fs ACL for AutoRecover + defense-in-depth scope`, commit `e56e447`)

Edited `gui/src-tauri/capabilities/default.json`. Four flat permissions added between `fs:scope-home-recursive` and the `core:window:*` block:

- `fs:scope-appdata-recursive`       — read scope for `$APPDATA`
- `fs:allow-appdata-write-recursive` — write scope for `$APPDATA` (covers `mkdir` + `writeTextFile`)
- `fs:allow-remove`                  — `clearSidecar` / `clearLockfile`
- `fs:allow-read-dir`                — `enumerateSidecars`

Plus one structured entry (Tauri v2 supports object form alongside flat strings):

```json
{
  "identifier": "fs:scope",
  "allow": [
    { "path": "$APPDATA/STREAM-Composer/autorecover/**" }
  ]
}
```

All pre-existing permissions retained: `core:default`, `opener:default`, `dialog:default`, `fs:default`, `fs:allow-write-text-file`, `fs:allow-read-text-file`, `fs:allow-exists`, `fs:allow-mkdir`, `fs:scope-home-recursive`, three `core:window:*`. JSON parses (`python3 -m json.tool`).

### Task 2 — DEV logging + v2 IPC rationale (`feat(65-09): DEV-mode logging + v2 IPC rationale comment on autoRecover`, commit `5f1e272`)

Edited `gui/src/lib/autoRecover.ts`:

- Eight `} catch {` blocks replaced with `} catch (err) { if (import.meta.env.DEV) { console.warn("[autoRecover] <op> failed:", err); } }`:
  - `writeSidecar`, `readSidecar`, `clearSidecar`, `enumerateSidecars`, `writeLockfile`, `readLockfile`, `clearLockfile`, `isPidAlive`
  - Each warn message names the operation so multiple failures are distinguishable in the devtools console.
  - For blocks with a fallthrough return value (`readSidecar` → `null`, `enumerateSidecars` → `[]`, `readLockfile` → `null`, `isPidAlive` → `false`), the return value is preserved after the warn — user-facing behavior unchanged.
- A 17-line JSDoc-style header comment block was added inside `isPidAlive` (first `await import('@tauri-apps/api/core')` site) documenting:
  - Use `(await import('@tauri-apps/api/core')).invoke(...)`, NOT `window.__TAURI__.core.invoke(...)`.
  - `window.__TAURI__` is intentionally undefined because `app.withGlobalTauri` is unset (v2 default).
  - ES-module imports go through the IPC bridge regardless of `withGlobalTauri`.
  - Cross-references `.planning/debug/autorecover-bridge.md` for the full diagnosis.

Edited `gui/src/App.tsx`:

- One-line comment added above the `get_pid` invoke pointing back to the autoRecover.ts header for the long-form rationale.

### Task 3 — Manual UAT (`checkpoint:human-verify`, gate="blocking")

This is a manual UAT step that cannot be performed inside the worktree executor (no Tauri dev shell, no display, no `node_modules`). It is **carried over** as a pending verification gate for post-merge execution by the user — see "Outstanding / Manual UAT Required" below.

## Verification

Automated checks passing inside the worktree:

```
python3 -m json.tool gui/src-tauri/capabilities/default.json > /dev/null    # JSON valid
grep -c "fs:scope-appdata-recursive"        gui/src-tauri/capabilities/default.json   # 1
grep -c "fs:allow-appdata-write-recursive"  gui/src-tauri/capabilities/default.json   # 1
grep -c "fs:allow-remove"                   gui/src-tauri/capabilities/default.json   # 1
grep -c "fs:allow-read-dir"                 gui/src-tauri/capabilities/default.json   # 1
# Structured fs:scope with autorecover/** path: present (python3 json check passed)
grep -c "catch (err)"            gui/src/lib/autoRecover.ts                           # 8
grep -c "import.meta.env.DEV"    gui/src/lib/autoRecover.ts                           # 8
grep -c "\[autoRecover\]"        gui/src/lib/autoRecover.ts                           # 8
grep -c "} catch {"              gui/src/lib/autoRecover.ts                           # 0
grep -q "Tauri v2 IPC invocation note" gui/src/lib/autoRecover.ts                     # match
grep -q "withGlobalTauri"              gui/src/lib/autoRecover.ts                     # match
grep -q "window.__TAURI__"             gui/src/lib/autoRecover.ts                     # match
npx tsc --noEmit  (target files: autoRecover.ts, App.tsx)                             # 0 errors
```

Vitest could not run inside this worktree because `node_modules/vitest` is not installed in worktree spawns (`npm install` is not part of the worktree provisioning). This is a known worktree-executor limitation — vitest will be exercised by the orchestrator or by manual UAT after merge.

## Deviations from Plan

None — plan executed exactly as written.

## Threat Surface

No new trust boundaries introduced. STRIDE register from PLAN.md (T-65-09a/b/c) holds:

- T-65-09a (Elevation of Privilege, accepted): new grants are scoped to `$APPDATA` (per-app data dir Tauri reserves for the bundle), not `$HOME`, not arbitrary path; structured `fs:scope` further narrows in-band declared intent to `autorecover/**`.
- T-65-09b (Information Disclosure, accepted): `console.warn` only logs Tauri ACL diagnostic strings to devtools console under DEV mode; Vite strips the branch in production builds.
- T-65-09c (Tampering, mitigated): JSON schema validation via `$schema` reference (`../gen/schemas/desktop-schema.json`) catches malformed identifiers at build time.

## Outstanding / Manual UAT Required (Task 3 — checkpoint:human-verify)

This worktree executor cannot run the Tauri dev shell — Task 3 must be performed by the user **after the worktree is merged**. The runbook from PLAN.md:

1. `cd gui && npm run tauri dev` — wait for workspace to load.
2. **UAT Test 16**: drop any node (e.g. Pump) on the canvas; wait ~3s; verify with
   `ls -la ~/.local/share/com.stream.composer/STREAM-Composer/autorecover/` that a
   `*.scp.autosave` file AND a `running.lock` file exist with current timestamps; sanity-`cat` the autosave.
3. Open devtools — confirm zero `[autoRecover] ... failed:` console.warn messages.
4. **UAT Test 17**: `pgrep -fa "target/debug/gui" | head -3` → `kill -9 <pid>` → relaunch
   `npm run tauri dev`. Expected: `AutoRecoverRestoreModal` blocks workspace with "Recover unsaved work from <ts> in <name>?" + [Recover] / [Discard] buttons.
5. Click [Recover] → unsaved node appears on canvas, title shows `*` dirty marker.
6. Re-run with [Discard] → autorecover directory empties; subsequent relaunch shows no modal.
7. DEV logging smoke: rename `autorecover/` away → edit something → devtools should show `[autoRecover] writeSidecar failed:` or `[autoRecover] mkdir failed:`; restore.

Resume signal: "approved" if all 7 steps pass; otherwise paste devtools + `ls` output + failing step.

If step 2 still shows no sidecar files, the `.planning/debug/autorecover-bridge.md` diagnosis missed something and Plan 09 must be revised.

## Key Decisions

- **Both broad + structured scope grants** — Tauri v2 ACL is union-of-grants, so the structured `fs:scope` narrowing is documentation-in-band, not a substitute for the flat permissions. The functional fix is the four flat permissions; the structured entry closes the explicit UAT defense-in-depth gap item.
- **DEV-only logging** — Vite strips `import.meta.env.DEV` branches in production, so DEV logging adds zero production-runtime cost while making future ACL gaps visible in dev devtools. Catch blocks remain silent to callers (best-effort autorecover semantics from Plan 07 unchanged).
- **In-source v2 IPC rationale** — the JSDoc-style block lives next to the surprising code (in `isPidAlive`), not only in a UAT prose file that may be archived. Future debuggers reading the IPC call site see the rationale immediately and don't re-derive the `window.__TAURI__` red herring.

## Commits

| Task | Commit  | Type   | Files                                                              |
| ---- | ------- | ------ | ------------------------------------------------------------------ |
| 1    | e56e447 | fix    | gui/src-tauri/capabilities/default.json                            |
| 2    | 5f1e272 | feat   | gui/src/lib/autoRecover.ts, gui/src/App.tsx                        |

## Self-Check: PASSED

- `gui/src-tauri/capabilities/default.json` exists and contains all four new flat permissions and the structured `fs:scope` entry (verified).
- `gui/src/lib/autoRecover.ts` contains 8 `catch (err)` blocks, 8 `import.meta.env.DEV` gates, 8 `[autoRecover]` tagged warnings, zero bare `} catch {` blocks, and the "Tauri v2 IPC invocation note" header (verified).
- `gui/src/App.tsx` contains the short comment above the `get_pid` invoke (verified).
- Commits `e56e447` and `5f1e272` exist on the worktree branch (verified via `git log --oneline -5`).
