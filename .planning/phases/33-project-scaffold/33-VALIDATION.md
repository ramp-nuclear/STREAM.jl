---
phase: 33
slug: project-scaffold
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-01
---

# Phase 33 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | vitest (unit) + manual Tauri smoke test |
| **Config file** | `gui/vitest.config.ts` (created in Plan 01, Task 1) |
| **Quick run command** | `cd gui && npx vitest run` |
| **Full suite command** | `cd gui && npx vitest run && npx tsc --noEmit` |
| **Estimated runtime** | ~10 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd gui && npx vitest run`
- **After every plan wave:** Run `cd gui && npx vitest run && npx tsc --noEmit`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 33-01-01 | 01 | 1 | SCAF-01 | unit | `cd gui && node -e "require('./package.json')"` | ✅ | ⬜ pending |
| 33-01-02 | 01 | 1 | SCAF-01 | unit | `cd gui && npx tsc --noEmit` | ✅ | ⬜ pending |
| 33-02-01 | 02 | 2 | SCAF-03 | unit | `cd gui && npx tsc --noEmit` | ✅ | ⬜ pending |
| 33-02-02 | 02 | 2 | SCAF-04, SCAF-05 | unit | `cd gui && npx vitest run` | ❌ W0 | ⬜ pending |
| 33-03-01 | 03 | 2 | SCAF-01 | manual | `npm run tauri dev` (visual check) | ✅ | ⬜ pending |
| 33-04-01 | 04 | 3 | SCAF-02 | manual | `cd gui && npm run tauri build` (check bundle output) | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `gui/src/registry/__tests__/registry.test.ts` — stubs for SCAF-03/SCAF-04 (created in Plan 02, Task 2)
- [ ] `gui/vitest.config.ts` — vitest configuration (created in Plan 01, Task 1)
- [ ] `npm install -D vitest @testing-library/react` — installed in Plan 01, Task 1

*If none: "Existing infrastructure covers all phase requirements."*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `npm run tauri dev` launches app within 10s | SCAF-01 | Requires Rust + WebKitGTK; can't run headlessly in CI | Run `npm run tauri dev` from `gui/`, observe browser/webview opens |
| ReactFlow canvas renders without console errors | SCAF-01 | Visual rendering; requires browser | Open DevTools, check Console tab for errors after app loads |
| App bundles to distributable installer | SCAF-02 | Platform-specific binary output | Run `cd gui && npm run tauri build`, verify `gui/src-tauri/target/release/bundle/` contains installer |
| WSL2/WSLg Tauri window renders | SCAF-01 | Environment-specific | If WebKitGTK fails, fallback to `npm run dev` (browser-only) |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
