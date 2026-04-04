---
phase: 36
slug: code-generation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-02
---

# Phase 36 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | vitest (existing) |
| **Config file** | `gui/vite.config.ts` |
| **Quick run command** | `cd gui && npm run test -- --run src/lib/codeGenerator` |
| **Full suite command** | `cd gui && npm run test -- --run` |
| **Estimated runtime** | ~10 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd gui && npm run test -- --run src/lib/codeGenerator`
- **After every plan wave:** Run `cd gui && npm run test -- --run`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 36-01-01 | 01 | 1 | CODE-01 | unit | `cd gui && npm run test -- --run src/lib/codeGenerator` | ❌ W0 | ⬜ pending |
| 36-01-02 | 01 | 1 | CODE-03 | unit | `cd gui && npm run test -- --run src/lib/codeGenerator` | ❌ W0 | ⬜ pending |
| 36-01-03 | 01 | 1 | CODE-05 | unit | `cd gui && npm run test -- --run src/lib/codeGenerator` | ❌ W0 | ⬜ pending |
| 36-01-04 | 01 | 1 | CODE-06 | unit | `cd gui && npm run test -- --run src/lib/codeGenerator` | ❌ W0 | ⬜ pending |
| 36-01-05 | 01 | 1 | CODE-07 | unit | `cd gui && npm run test -- --run src/lib/codeGenerator` | ❌ W0 | ⬜ pending |
| 36-02-01 | 02 | 2 | CODE-04 | unit | `cd gui && npm run test -- --run src/store` | ✅ | ⬜ pending |
| 36-03-01 | 03 | 2 | CODE-01 | manual | visual inspection | N/A | ⬜ pending |
| 36-03-02 | 03 | 2 | CODE-04 | manual | visual inspection | N/A | ⬜ pending |
| 36-04-01 | 04 | 3 | CODE-02 | manual | click Export button | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `gui/src/lib/codeGenerator.test.ts` — stubs for CODE-01, CODE-03, CODE-05, CODE-06, CODE-07
- [ ] Test cases: Pump positional, Channel keyword, HeatExchanger, connect() edges, BC emission, identifier validation

*Existing test infrastructure (vitest) covers remaining requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Bottom panel opens/closes on Code button click | CODE-01 | UI interaction | Open app, click Code button, verify panel animates open/closed |
| Export opens native file dialog | CODE-02 | Tauri native dialog | Click Export, verify OS file save dialog appears with `.jl` filter |
| Saved file opens in editor with valid Julia | CODE-02 | File content + OS | Save file, open in text editor, verify content matches preview |
| BC dropdown populates from canvas nodes | CODE-04 | UI interaction | Add nodes to canvas, open BCs tab, verify component dropdown lists them |
| Deleting node removes its BCs | CODE-04 | Store cleanup | Add node + BC, delete node, verify BC row disappears |
| Generated code updates live on canvas change | CODE-01 | Visual inspection | Add/remove component, verify code panel updates without refresh |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
