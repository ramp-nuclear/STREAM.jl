---
phase: 40
slug: thermal-composition
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-03
---

# Phase 40 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | vitest 4.1.2 |
| **Config file** | gui/vitest.config.ts |
| **Quick run command** | `cd gui && npx vitest run --reporter=verbose` |
| **Full suite command** | `cd gui && npx vitest run --reporter=verbose` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd gui && npx vitest run --reporter=verbose`
- **After every plan wave:** Run `cd gui && npx vitest run --reporter=verbose`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 40-xx-01 | TBD | 1 | THERM-01 | unit | `cd gui && npx vitest run src/components/__tests__/StreamNode.test.tsx` | ✅ extends existing | ⬜ pending |
| 40-xx-02 | TBD | 1 | THERM-01 | unit | `cd gui && npx vitest run src/components/__tests__/StreamNode.test.tsx` | ✅ extends existing | ⬜ pending |
| 40-xx-03 | TBD | 2 | THERM-02 | unit | `cd gui && npx vitest run src/lib/codeGenerator.test.ts` | ❌ W0 | ⬜ pending |
| 40-xx-04 | TBD | 2 | THERM-03 | unit | `cd gui && npx vitest run src/lib/codeGenerator.test.ts` | ✅ extends existing | ⬜ pending |
| 40-xx-05 | TBD | 2 | THERM-03 | unit | `cd gui && npx vitest run src/lib/codeGenerator.test.ts` | ✅ extends existing | ⬜ pending |
| 40-xx-06 | TBD | 2 | THERM-03 | unit | `cd gui && npx vitest run src/lib/codeGenerator.test.ts` | ✅ extends existing | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `gui/src/components/__tests__/StreamNode.test.tsx` — add tests for ThermalPort handle count on ChannelAndContacts (n=4 → 4 thermal_left + 4 thermal_right), HeatDiffusion (thermal_left, thermal_right handles), ConstantTemperature (thermal handle)
- [ ] `gui/src/lib/codeGenerator.test.ts` — add thermal topology detection tests: symmetric_plate, plate, one_sided_connection, unknown fallback
- [ ] New test for isValidConnection port-type enforcement — blocks FlowPort↔ThermalPort, allows ThermalPort↔ThermalPort (may go in CanvasPanel test file or standalone)

*Note: Existing test files exist and are extended — no new framework install needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Amber edge color on ThermalPort connection | THERM-02 | Visual styling not easily DOM-testable in happy-dom | Connect a HeatDiffusion thermal port to a ChannelAndContacts thermal port; edge should render in amber (#f59e0b) in the canvas |
| Drag connection snaps only to matching port type | THERM-02 | ReactFlow drag interaction not covered by unit tests | Drag from a ThermalPort handle; verify only other ThermalPort handles highlight as valid drop targets |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
