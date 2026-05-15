---
phase: 65
slug: interaction-model-overhaul
status: verified
threats_open: 0
asvs_level: 1
created: 2026-05-15
---

# Phase 65 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.
> All 14 PLAN `<threat_model>` blocks have been audited; mitigations verified in source; accepted risks logged.

---

## Trust Boundaries

Aggregated across all 14 plans in this phase.

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| OS clipboard → `navigator.clipboard.readText` → `JSON.parse` → `isClipboardPayload` | UNTRUSTED clipboard text crosses into the renderer on paste. | Arbitrary string (JSON-shaped if valid) |
| `.scp` file → `projectIO.deserializeProject` → store hydration | Untrusted JSON file content drives store state. | Project layout / nodes / edges / resources |
| User-controlled file path → `getSidecarBasename` → autorecover filesystem write path | Filename component may be traversal-shaped. | Path string |
| `running.lock` file contents → `parseLockfileContent` → `isPidAlive(pid)` | Corrupted/manually-edited lockfile drives a PID-alive IPC query. | PID line + timestamp line |
| Sidecar file contents → `deserializeProject` (in `recoverFromSidecar`) | Same surface as `.scp` open; sidecar lives in `$APPDATA/STREAM-Composer/autorecover/`. | Untrusted JSON |
| Modal cannot be bypassed (UI invariant) | `AutoRecoverRestoreModal` blocks workspace mount; Esc / outside-click MUST NOT close. | n/a — UI invariant |
| Webview → Tauri fs plugin (capability ACL) | `autoRecover.ts` calls cross IPC into the native fs plugin. | Path strings + file contents |
| Webview → Tauri core `invoke('is_pid_alive')` | Local IPC channel exposes PID-aliveness query. | u32 PID |
| Browser DOM events → React handlers (right-click context menu, marquee) | Pure synthetic events; no untrusted JSON. | MouseEvent |

---

## Threat Register

| Threat ID | Category | Component | Disposition | Mitigation | Status |
|-----------|----------|-----------|-------------|------------|--------|
| T-65-01 | Tampering | `nextInstanceName` (useStore.ts) | accept | Pure function over store-owned data; no external input. | closed (accepted) |
| T-65-02 | Tampering | NumericField blur handler | accept | Field values flow through `validateReal()` for non-empty inputs; reset writes a registry constant. | closed (accepted) |
| T-65-03 | Denial of service | `useRightClickContextMenu` window listeners | accept | Listeners bounded by component lifetime via `useEffect` cleanup. | closed (accepted) |
| T-65-03b | Tampering | window `contextmenu` preventDefault override | accept | Only fires after a right-button drag exceeded threshold; user's own gesture is the trigger surface. | closed (accepted) |
| T-65-04 | Tampering | `pasteFromClipboard` | mitigate | `JSON.parse` wrapped in try/catch + `isClipboardPayload` type guard rejects on `__format` / `version` / non-array `nodes` / non-array `edges`; `_pushSnapshot()` runs AFTER the guard, so partial state mutation is impossible. Verified in `gui/src/lib/clipboard.ts:48-57` and `gui/src/store/useStore.ts:1895-1914`. | closed |
| T-65-05 | Denial of service | `pasteFromClipboard` with crafted 100k-node payload | accept | Clipboard is locally controlled by the same user; `crypto.randomUUID()` loop is O(n). | closed (accepted) |
| T-65-06 | Information disclosure | `copySelection` writes payload to OS clipboard | accept | Same data the user could already export via Save — no new disclosure surface. | closed (accepted) |
| T-65-07 | Tampering | Add Component submenu → `addNode` | accept | `componentId` comes from registry iteration (trusted); `flowPosition` already handled by `addNode`. | closed (accepted) |
| T-65-08 | Tampering | `deserializeProject` snap_to_grid parse | mitigate | Explicit boolean default: `(rawLayout.snap_to_grid as boolean) ?? false`. Verified in `gui/src/lib/projectIO.ts:202`. Missing field correctly defaults to `false`; nullish coalescing protects against `null`/`undefined`. | closed |
| T-65-09 | Tampering | `getSidecarBasename` | mitigate | Path sanitization: split on `/` and `\`, strip `.scp` extension, replace non-`[A-Za-z0-9._-]` chars with `_`, collapse runs of `_`, strip leading dots, fallback to `"untitled"` on empty. Verified in `gui/src/lib/autoRecover.ts:36-66`. Output is guaranteed to match `/^[A-Za-z0-9._-]+\.scp\.autosave$/`. | closed |
| T-65-09a | Elevation of privilege | `gui/src-tauri/capabilities/default.json` | accept | New flat grants are scoped to `$APPDATA` only (`fs:scope-appdata-recursive`, `fs:allow-appdata-write-recursive`); pre-existing `fs:scope-home-recursive` is a READ-only scope retained from baseline for opening user `.scp` files (intentional per PLAN 09 lines 26, 75, 223). Structured `fs:scope` entry further narrows declared intent to `$APPDATA/STREAM-Composer/autorecover/**`. No write grant on `$HOME`; no arbitrary path. Verified in `gui/src-tauri/capabilities/default.json:11-25`. | closed (accepted) |
| T-65-09b | Information disclosure | `autoRecover.ts` catch blocks | accept | DEV-mode `console.warn` only logs Tauri ACL diagnostic text to devtools console; Vite strips the `import.meta.env.DEV` branch in production builds. No PII. | closed (accepted) |
| T-65-09c | Tampering | `capabilities/default.json` | mitigate | JSON-schema validation via `$schema` reference (`../gen/schemas/desktop-schema.json`) catches malformed permission identifiers AND malformed structured `fs:scope` objects at Tauri build time. Verified in `gui/src-tauri/capabilities/default.json:2`. | closed |
| T-65-10 | Tampering | `parseLockfileContent` | mitigate | Strict shape: requires ≥2 lines; line 1 must parse to a positive integer (`Number.isInteger && > 0`); line 2 must be a non-empty trimmed string. Any deviation → `null`. `readLockfile` propagates `null` → `detectCrashOnLaunch` returns the safe no-crash default. Verified in `gui/src/lib/autoRecover.ts:272-287`. | closed |
| T-65-10a | Denial of service | SidebarPanel Esc handler | accept | `e.target` is browser-provided EventTarget-or-null; null check on `isContentEditable` handles all malformed cases. | closed (accepted) |
| T-65-11 | Information disclosure | `is_pid_alive` Tauri command | accept | Local IPC only; aliveness data already available via `ps`. | closed (accepted) |
| T-65-11a | Tampering | `dropdown-menu.tsx` shim | accept | Radix DropdownMenu is already a transitive dep of multiple existing shadcn primitives; no new external code added. | closed (accepted) |
| T-65-11b | Denial of service | Nested portal rendering for Add Component submenu | accept | `getAllComponents` returns 16 components / ~3-4 categories — bounded. | closed (accepted) |
| T-65-12 | Denial of service | Sidecar overwrites every 2s under heavy editing | accept | Writes are small (<1MB typical); 2s debounce caps disk traffic. | closed (accepted) |
| T-65-12a | Tampering | `gui/src/index.css` marquee overrides | accept | CSS rules cannot induce logic faults; future ReactFlow class renames silently no-op back to default styling. | closed (accepted) |
| T-65-12b | Tampering | Sidecar-clear race after successful save (W11) | accept | If app crashes between successful `writeTextFile(scp)` and `clearSidecar`, user sees a redundant restore prompt with the same state already saved — no data loss. | closed (accepted) |
| T-65-13 | Tampering | `recoverFromSidecar` → `deserializeProject` | mitigate | `deserializeProject(text)` wrapped in try/catch inside `recoverFromSidecar`; on failure, sidecar AND lockfile are cleared to prevent boot-loop, then function returns silently. Caller in `App.tsx:151-164` adds outer try/catch/finally, ensuring `initAutoRecover` runs even on error and the modal always closes. Verified in `gui/src/store/useStore.ts:2520-2541` and `gui/src/App.tsx:151-165`. | closed |
| T-65-13a | Denial of service | `InteractiveLockButton` stuck-locked state | accept | One-click unlock; no persistence — reload restores unlocked. | closed (accepted) |
| T-65-13b | Tampering | `useStore.interactiveLocked` field placement | mitigate | Vitest case asserts `interactiveLocked` token count in `useStore.ts` is ≥3 and ≤4 — catches accidental insertion into serialize paths (`saveProjectAs` / `deserializeProject`). Verified in `gui/src/store/__tests__/interactiveLocked.test.ts:37-46`. | closed |
| T-65-14 | Elevation of privilege | Modal dismiss bypass | mitigate | `Dialog.Content` on `AutoRecoverRestoreModal.tsx:72-77` registers `onEscapeKeyDown`, `onPointerDownOutside`, AND `onInteractOutside` — each calls `e.preventDefault()`. No `Dialog.Close` element is rendered; the only dismiss paths are the explicit Recover / Discard buttons. Verified in `gui/src/components/AutoRecoverRestoreModal.tsx:63-123`. | closed |
| T-65-14a | Tampering | `useStore` autoRecover subscribe semantics | mitigate | Inline comment at `gui/src/store/useStore.ts:2697-2701` documents the Plan 07 → Plan 14 semantic shift ("2s after last edit" → "2s after first edit in the dirty session"). Subscribe is now selector-gated on `(state) => state.isDirty` and only re-fires on transitions. | closed |
| T-65-14b | Denial of service | `subscribeWithSelector` composition error | mitigate | Three vitest cases in `gui/src/store/__tests__/subscribeWithSelector.test.ts` assert: (1) selector-gated `subscribe((s)=>s.field, listener)` overload fires only on selected-value change; (2) single-arg backward-compat overload still fires on every set; (3) middleware composition preserves existing action behavior. tsc + vitest are part of the commit-time gate. | closed |
| T-65-14c | Information disclosure | App.tsx title-sync gate omits a state | accept | Title now reflects only `{filePath, isDirty}` — same fields `syncTitle` consumes; no previously displayed title state dropped. | closed (accepted) |
| T-65-15 | Information disclosure | Sidecar contents on disk | accept | Same disclosure surface as user-owned `.scp` files; lives in per-user `appDataDir` with OS-level permissions. | closed (accepted) |

*Status: closed = mitigation verified in code (mitigate) OR risk documented (accept).*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party).*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-65-01 | T-65-01 | Pure in-memory store mutation over store-owned data; no untrusted input boundary. | Phase 65 plan owner | 2026-05-15 |
| AR-65-02 | T-65-02 | NumericField values pass through `validateReal()`; reset writes a registry constant. Low-risk UI mutation. | Phase 65 plan owner | 2026-05-15 |
| AR-65-03 | T-65-03 | Window-level listeners bounded by `useEffect` cleanup; cannot leak past component unmount. | Phase 65 plan owner | 2026-05-15 |
| AR-65-04 | T-65-03b | The OS-menu suppression fires after a user's own right-button drag exceeds threshold; cannot be triggered by remote input. | Phase 65 plan owner | 2026-05-15 |
| AR-65-05 | T-65-05 | Clipboard input source is the same user; a malicious 100k-node payload would only hang the user's own renderer. Per CLAUDE.md no-malicious-input-hardening during heavy dev. | Phase 65 plan owner | 2026-05-15 |
| AR-65-06 | T-65-06 | `copySelection` writes only data the user could already export via Save — no new disclosure surface. | Phase 65 plan owner | 2026-05-15 |
| AR-65-07 | T-65-07 | `componentId` comes from trusted registry iteration; `flowPosition` already validated by `addNode`. | Phase 65 plan owner | 2026-05-15 |
| AR-65-08 | T-65-09a | New fs grants confined to `$APPDATA`; pre-existing `fs:scope-home-recursive` is a READ-only scope retained from baseline for opening user `.scp` files. Structured `fs:scope` further narrows declared intent to `$APPDATA/STREAM-Composer/autorecover/**`. | Phase 65 plan owner | 2026-05-15 |
| AR-65-09 | T-65-09b | DEV-mode `console.warn` strips in production via Vite `import.meta.env.DEV`; logs Tauri ACL diagnostic strings only, no PII. | Phase 65 plan owner | 2026-05-15 |
| AR-65-10 | T-65-10a | `e.target` is guaranteed by the browser to be EventTarget-or-null; null path handled. No DoS surface. | Phase 65 plan owner | 2026-05-15 |
| AR-65-11 | T-65-11 | `is_pid_alive` query surface is local IPC only; PID-aliveness already obtainable via `ps`. | Phase 65 plan owner | 2026-05-15 |
| AR-65-12 | T-65-11a | Radix DropdownMenu is already a transitive dep of multiple existing shadcn primitives; no new external code introduced. | Phase 65 plan owner | 2026-05-15 |
| AR-65-13 | T-65-11b | Registry contains ~16 components / ~3-4 categories — bounded portal count. | Phase 65 plan owner | 2026-05-15 |
| AR-65-14 | T-65-12 | 2s debounce caps writes; typical sidecar <1MB. No disk-thrash risk. | Phase 65 plan owner | 2026-05-15 |
| AR-65-15 | T-65-12a | CSS rules cannot induce logic faults; future ReactFlow class renames silently revert to default styling. | Phase 65 plan owner | 2026-05-15 |
| AR-65-16 | T-65-12b | Sidecar-clear-after-write race yields a redundant restore prompt on next launch — no data loss. Alternative (clear before write) loses crash protection during the write itself. | Phase 65 plan owner | 2026-05-15 |
| AR-65-17 | T-65-13a | InteractiveLock stuck-state is one-click recoverable; non-persistent across reload. | Phase 65 plan owner | 2026-05-15 |
| AR-65-18 | T-65-14c | Title-sync gate consumes the same `{filePath, isDirty}` fields `syncTitle` reads. No state previously displayed in the title is dropped. | Phase 65 plan owner | 2026-05-15 |
| AR-65-19 | T-65-15 | Sidecar lives in per-user `appDataDir` with OS-level permissions; identical disclosure surface as user-owned `.scp` files. | Phase 65 plan owner | 2026-05-15 |

*Accepted risks do not resurface in future audit runs.*

---

## Unregistered Flags

None. Every `## Threat Flags` block across the 14 SUMMARYs either reports "None" or maps to existing threat IDs in the register. The 6 gap-closure plans (09–14) introduced new threats (T-65-09a/b/c, T-65-10a, T-65-11a/b, T-65-12a, T-65-13a/b, T-65-14a/b/c) — all are present in the plan-time register above. No surface emerged during implementation without a corresponding threat ID.

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-05-15 | 28 | 28 | 0 | /gsd:secure-phase auditor |

Verification evidence (mitigate threats only — 10 of 28):

| Threat ID | Verification artifact |
|-----------|----------------------|
| T-65-04 | `gui/src/lib/clipboard.ts:48-57` (`isClipboardPayload`); `gui/src/store/useStore.ts:1895-1914` (try/catch JSON.parse, guard, snapshot-after-guard) |
| T-65-08 | `gui/src/lib/projectIO.ts:202` (`(rawLayout.snap_to_grid as boolean) ?? false`) |
| T-65-09 | `gui/src/lib/autoRecover.ts:36-66` (sanitization to `[A-Za-z0-9._-]+`, leading-dot strip, fallback) |
| T-65-09c | `gui/src-tauri/capabilities/default.json:2` (`$schema` reference) |
| T-65-10 | `gui/src/lib/autoRecover.ts:272-287` (strict shape, positive-integer PID check) |
| T-65-13 | `gui/src/store/useStore.ts:2520-2541` (try/catch around `deserializeProject` + clearSidecar/clearLockfile on failure); `gui/src/App.tsx:151-165` (outer try/catch/finally) |
| T-65-13b | `gui/src/store/__tests__/interactiveLocked.test.ts:37-46` (token count ≥3 and ≤4) |
| T-65-14 | `gui/src/components/AutoRecoverRestoreModal.tsx:72-77` (`onEscapeKeyDown`, `onPointerDownOutside`, `onInteractOutside` all preventDefault; no `Dialog.Close`) |
| T-65-14a | `gui/src/store/useStore.ts:2697-2701` (inline comment documenting Plan 07 → Plan 14 semantic shift) |
| T-65-14b | `gui/src/store/__tests__/subscribeWithSelector.test.ts` (3 cases: selector-gated, single-arg backward-compat, composition smoke) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer) — 10 mitigate, 18 accept, 0 transfer
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-05-15
