---
phase: 41
slug: layered-canvas
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-03
---

# Phase 41 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | vitest (existing, gui/package.json) |
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
| 41-01-01 | 01 | 1 | LAYR-01 | unit | `cd gui && npm run test -- --run` | ❌ W0 | ⬜ pending |
| 41-01-02 | 01 | 1 | LAYR-02 | unit | `cd gui && npm run test -- --run` | ❌ W0 | ⬜ pending |
| 41-02-01 | 02 | 2 | LAYR-03 | unit | `cd gui && npm run test -- --run` | ❌ W0 | ⬜ pending |
| 41-02-02 | 02 | 2 | LAYR-04 | manual | — | — | ⬜ pending |
| 41-03-01 | 03 | 3 | LAYR-05 | unit | `cd gui && npm run test -- --run` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `gui/src/__tests__/layerStore.test.ts` — stubs for activeLayer state + setActiveLayer + cycleLayer
- [ ] `gui/src/__tests__/layerDetection.test.ts` — stubs for port-based layer detection utility
- [ ] `gui/src/__tests__/projectIO.test.ts` — stubs for v2 schema serialization/deserialization with activeLayer

*Existing test infrastructure (vitest) covers all phase requirements — only stub files need creation.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Toggle visual prominence | D-10 | Requires visual inspection of toolbar layout | Open GUI, verify "Layer:" label + icon visible, active state clearly distinct |
| Dimming appearance | D-01/D-03 | CSS opacity requires visual check | Open GUI with both hydraulic + thermal components, switch layers, confirm off-layer nodes/edges visually dimmed |
| Tab key interception | D-11 | Keyboard behavior requires manual test | Open GUI, click canvas, press Tab, verify layer cycles without browser focus ring jumping |
| Handle dimming in layer view | D-08 | Requires visual handle inspection | Add ChannelAndContacts, switch to Thermal view, verify FlowPort handles dimmed, ThermalPort handles active |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
