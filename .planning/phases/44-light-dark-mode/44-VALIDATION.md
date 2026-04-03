---
phase: 44
slug: light-dark-mode
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-04
---

# Phase 44 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | vitest |
| **Config file** | gui/vite.config.ts |
| **Quick run command** | `cd gui && npm run test -- --run` |
| **Full suite command** | `cd gui && npm run test -- --run` |
| **Estimated runtime** | ~10 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd gui && npm run test -- --run`
- **After every plan wave:** Run `cd gui && npm run test -- --run`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 44-01-01 | 01 | 1 | SC-2 | unit | `cd gui && npm run test -- --run` | ✅ | ⬜ pending |
| 44-01-02 | 01 | 1 | SC-1 | manual | see Manual Verifications | N/A | ⬜ pending |
| 44-01-03 | 01 | 2 | SC-3 | manual | see Manual Verifications | N/A | ⬜ pending |
| 44-02-01 | 02 | 1 | SC-4 | manual | see Manual Verifications | N/A | ⬜ pending |
| 44-02-02 | 02 | 2 | SC-5 | manual | see Manual Verifications | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Settings button opens panel | SC-1 | DOM interaction / visual | Open app, click gear icon, verify dropdown opens |
| All shadcn/ui components correct in both themes | SC-3 | Visual inspection | Toggle light/dark, inspect all panels and dialogs |
| ReactFlow canvas adapts to theme | SC-4 | Visual inspection | Toggle light/dark, verify canvas background and node colors |
| Amber edges & red error rings legible in both themes | SC-5 | Visual inspection | Toggle light/dark with thermal edges and error rings visible |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
