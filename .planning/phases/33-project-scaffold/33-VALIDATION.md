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
| **Config file** | `composer/vite.config.ts` (Wave 0 creates it) |
| **Quick run command** | `cd composer && npm run test:unit -- --run` |
| **Full suite command** | `cd composer && npm run test:unit -- --run && npm run lint` |
| **Estimated runtime** | ~10 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd composer && npm run test:unit -- --run`
- **After every plan wave:** Run `cd composer && npm run test:unit -- --run && npm run lint`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 33-01-01 | 01 | 0 | SCAF-01 | unit | `cd composer && npm run test:unit -- --run` | ❌ W0 | ⬜ pending |
| 33-01-02 | 01 | 1 | SCAF-02 | manual | `npm run tauri dev` (visual check) | ✅ | ⬜ pending |
| 33-02-01 | 02 | 1 | SCAF-03 | unit | `cd composer && npm run test:unit -- --run` | ❌ W0 | ⬜ pending |
| 33-02-02 | 02 | 1 | SCAF-04 | unit | `cd composer && npm run test:unit -- --run` | ❌ W0 | ⬜ pending |
| 33-03-01 | 03 | 2 | SCAF-05 | manual | `npm run tauri build` (check output dir) | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `composer/src/test/registry.test.ts` — stubs for SCAF-03/SCAF-04
- [ ] `composer/vitest.config.ts` — vitest configuration
- [ ] `npm install -D vitest @vitest/ui` — if not bundled with Vite scaffold

*If none: "Existing infrastructure covers all phase requirements."*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `npm run tauri dev` launches app within 10s | SCAF-02 | Requires Rust + WebKitGTK; can't run headlessly in CI | Run `npm run tauri dev` from `composer/`, observe browser/webview opens |
| ReactFlow canvas renders without console errors | SCAF-02 | Visual rendering; requires browser | Open DevTools, check Console tab for errors after app loads |
| App bundles to distributable installer | SCAF-05 | Platform-specific binary output | Run `npm run tauri build`, verify `src-tauri/target/release/bundle/` contains installer |
| WSL2/WSLg Tauri window renders | SCAF-02 | Environment-specific | If WebKitGTK fails, fallback to `npm run dev` (browser-only) |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
