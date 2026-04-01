---
phase: 35
slug: parameter-editing
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-02
---

# Phase 35 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | vitest (existing in gui/) |
| **Config file** | `gui/vite.config.ts` |
| **Quick run command** | `cd gui && npx vitest run --reporter=verbose` |
| **Full suite command** | `cd gui && npx vitest run` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd gui && npx vitest run --reporter=verbose`
- **After every plan wave:** Run `cd gui && npx vitest run`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 35-01-01 | 01 | 1 | PARA-01 | unit | `cd gui && npx vitest run` | ❌ W0 | ⬜ pending |
| 35-01-02 | 01 | 1 | PARA-02 | unit | `cd gui && npx vitest run` | ❌ W0 | ⬜ pending |
| 35-02-01 | 02 | 1 | PARA-03 | unit | `cd gui && npx vitest run` | ❌ W0 | ⬜ pending |
| 35-02-02 | 02 | 1 | PARA-04 | unit | `cd gui && npx vitest run` | ❌ W0 | ⬜ pending |
| 35-03-01 | 03 | 2 | PARA-05 | unit | `cd gui && npx vitest run` | ❌ W0 | ⬜ pending |
| 35-03-02 | 03 | 2 | PARA-06 | unit | `cd gui && npx vitest run` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `gui/src/components/__tests__/ParameterSidebar.test.tsx` — stubs for PARA-01, PARA-02, PARA-03, PARA-04
- [ ] `gui/src/components/__tests__/PumpSidebar.test.tsx` — stubs for PARA-05 (mode toggle)
- [ ] `gui/src/store/__tests__/registry.test.ts` — stubs for PARA-06 (validation)

*If vitest not yet installed in gui/, run `cd gui && npm install -D vitest @testing-library/react @testing-library/user-event`*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| shadcn component visual rendering | PARA-01 | Requires browser render | Open app, click Channel node, verify sidebar appears with styled inputs |
| Mode-specific field switch (Pump) | PARA-05 | Requires interactive toggle | Click Pump node, toggle constructor mode, verify fields change |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
