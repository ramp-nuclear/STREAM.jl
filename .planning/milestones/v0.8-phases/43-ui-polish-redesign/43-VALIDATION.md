---
phase: 43
slug: ui-polish-redesign
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-04
---

# Phase 43 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | vitest (jsdom per-file) |
| **Config file** | `gui/vitest.config.ts` |
| **Quick run command** | `cd gui && npx vitest run --passWithNoTests` |
| **Full suite command** | `cd gui && npx vitest run --passWithNoTests` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd gui && npx vitest run --passWithNoTests`
- **After every plan wave:** Run `cd gui && npx vitest run --passWithNoTests`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Criterion | Test Type | Automated Command | Status |
|---------|------|------|-----------|-----------|-------------------|--------|
| SC-1 | 01 | 1 | Button consistency | Code audit | `grep -rn 'size=' gui/src/components/Toolbar.tsx gui/src/components/sidebar/ParameterForm.tsx` | ⬜ pending |
| SC-2 | 01 | 1 | Thermal handle 12x12 | Unit test | `cd gui && npx vitest run --passWithNoTests` | ⬜ pending |
| SC-3 | 02 | 1 | Sidebar param tooltips | Component test | `cd gui && npx vitest run src/components/sidebar/__tests__/` | ⬜ pending |
| SC-4 | 03 | 1 | Panel dividers draggable | Store unit test | `cd gui && npx vitest run src/store/__tests__/` | ⬜ pending |
| SC-5 | all | — | Professional appearance | Manual visual | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `gui/src/store/__tests__/useStore.test.ts` — add tests for `bottomPanelHeight`, `setBottomPanelHeight` store fields
- [ ] Optionally extend `gui/src/components/sidebar/__tests__/ParameterForm.test.tsx` — verify tooltip renders for Bool fields with description

---

## Manual-Only Verifications

| Behavior | Criterion | Why Manual | Test Instructions |
|----------|-----------|------------|-------------------|
| Professional appearance | SC-5 | Visual polish cannot be fully automated | Open app, inspect all surfaces: buttons, handles, sidebar, panels |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
