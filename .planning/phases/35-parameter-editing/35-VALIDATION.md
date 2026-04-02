---
phase: 35
slug: parameter-editing
status: draft
nyquist_compliant: true
wave_0_complete: true
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
| 35-01-01 | 01 | 1 | PARA-01,06 | unit | `cd gui && npx vitest run` | Yes (useStore.test.ts, validation.test.ts) | pending |
| 35-01-02 | 01 | 1 | PARA-02,05 | unit | `cd gui && npx vitest run` | Yes (useStore.test.ts, validation.test.ts) | pending |
| 35-02-01 | 02 | 2 | PARA-01..06 | unit | `cd gui && npx vitest run` | Yes (W0 Task 3 creates stubs) | pending |
| 35-02-02 | 02 | 2 | PARA-03,04 | unit | `cd gui && npx vitest run` | Yes (W0 Task 3 creates stubs) | pending |
| 35-02-03 | 02 | 2 | PARA-01..06 | unit | `cd gui && npx vitest run` | Yes (Wave 0 test stubs) | pending |
| 35-03-01 | 03 | 3 | PARA-01..06 | human | Manual verification | N/A | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

Wave 0 test stubs are created by Plan 02, Task 3. All files below are created with at least one real render test plus it.todo() stubs for future coverage:

- [x] `gui/src/components/sidebar/__tests__/SidebarPanel.test.tsx` — stubs for PARA-01 (selection, empty state)
- [x] `gui/src/components/sidebar/__tests__/ParameterForm.test.tsx` — real render test for field dispatch + stubs for PARA-02 (blur-gating)
- [x] `gui/src/components/sidebar/__tests__/ModeToggle.test.tsx` — real render test for mode buttons + stubs for PARA-03 (mode switching)
- [x] `gui/src/components/sidebar/__tests__/PipeGeometryPicker.test.tsx` — real render test for geometry buttons + stubs for PARA-04 (field clearing)
- [x] `gui/src/components/sidebar/__tests__/InstanceNameField.test.tsx` — real render test for input + stubs for PARA-05 (identifier validation)

Additionally, Plan 01 Task 2 creates full-coverage tests for non-UI logic:
- [x] `gui/src/lib/__tests__/validation.test.ts` — comprehensive validateInt/Real/PositiveReal/JuliaIdentifier tests
- [x] `gui/src/store/__tests__/useStore.test.ts` — updateNodeParams and addNode default population tests

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| shadcn component visual rendering | PARA-01 | Requires browser render | Open app, click Channel node, verify sidebar appears with styled inputs |
| Mode-specific field switch (Pump) | PARA-05 | Requires interactive toggle | Click Pump node, toggle constructor mode, verify fields change |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 15s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved (revision pass)
