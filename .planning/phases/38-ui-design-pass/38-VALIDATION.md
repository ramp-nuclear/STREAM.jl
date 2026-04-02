---
phase: 38
slug: ui-design-pass
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-04-03
---

# Phase 38 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Vitest ^4.1.2 |
| **Config file** | gui/vitest.config.ts |
| **Quick run command** | `cd gui && npx vitest run --passWithNoTests` |
| **Full suite command** | `cd gui && npx vitest run --passWithNoTests` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd gui && npx vitest run --passWithNoTests`
- **After every plan wave:** Run `cd gui && npx vitest run --passWithNoTests`
- **Before `/gsd:verify-work`:** Full suite must be green + human visual verification
- **Max feedback latency:** ~5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 38-01-01 | 01 | 1 | DSGN-03, DSGN-04 | unit | `cd gui && npx vitest run src/registry/__tests__/icons.test.ts src/components/__tests__/StreamNode.test.tsx` | ❌ W0 | ⬜ pending |
| 38-02-01 | 02 | 2 | DSGN-01, DSGN-02 | unit | `cd gui && npx vitest run --passWithNoTests` | ✅ | ⬜ pending |
| 38-02-02 | 02 | 2 | DSGN-01, DSGN-02 | unit | `cd gui && npx vitest run --passWithNoTests` | ✅ | ⬜ pending |
| 38-03-01 | 03 | 3 | DSGN-05 | manual | N/A (human-verify checkpoint) | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `gui/src/registry/__tests__/icons.test.ts` — covers DSGN-03: all 12 components have an icon mapping (created in Plan 38-01 Task 1)
- [ ] Update `gui/src/components/__tests__/StreamNode.test.tsx` — covers DSGN-04: node renders icon and category border class (updated in Plan 38-01 Task 1)
- [ ] Extend `gui/src/store/__tests__/useStore.test.ts` — add tests for `setToolboxCollapsed`/`setSidebarCollapsed` (updated in Plan 38-02 Task 1)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| All UI elements use shadcn primitives | DSGN-01 | Visual/structural audit required | Open app, inspect rendered elements for shadcn class patterns; check no raw `<button>` or `<input>` |
| Three-panel layout collapse/resize | DSGN-02 | Interaction requires human browser testing | Click chevron buttons, drag resize handles, verify smooth behavior |
| UI-SPEC precedes coding; UI-REVIEW after | DSGN-05 | Process verification | Confirm 38-UI-SPEC.md exists (done); run `/gsd:ui-review 38` after implementation |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 10s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-04-03
