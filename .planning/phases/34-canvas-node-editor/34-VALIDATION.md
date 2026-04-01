---
phase: 34
slug: canvas-node-editor
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-02
---

# Phase 34 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | vitest + @testing-library/react |
| **Config file** | gui/vite.config.ts |
| **Quick run command** | `cd gui && npx vitest run --reporter=dot` |
| **Full suite command** | `cd gui && npx vitest run` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd gui && npx vitest run --reporter=dot`
- **After every plan wave:** Run `cd gui && npx vitest run`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 20 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 34-01-01 | 01 | 1 | CANV-01 | unit | `cd gui && npx vitest run --reporter=dot` | ❌ W0 | ⬜ pending |
| 34-01-02 | 01 | 1 | CANV-02 | unit | `cd gui && npx vitest run --reporter=dot` | ❌ W0 | ⬜ pending |
| 34-02-01 | 02 | 1 | CANV-03 | unit | `cd gui && npx vitest run --reporter=dot` | ❌ W0 | ⬜ pending |
| 34-02-02 | 02 | 1 | CANV-04 | unit | `cd gui && npx vitest run --reporter=dot` | ❌ W0 | ⬜ pending |
| 34-03-01 | 03 | 2 | CANV-05 | unit | `cd gui && npx vitest run --reporter=dot` | ❌ W0 | ⬜ pending |
| 34-03-02 | 03 | 2 | CANV-06 | unit | `cd gui && npx vitest run --reporter=dot` | ❌ W0 | ⬜ pending |
| 34-04-01 | 04 | 2 | CANV-07 | unit | `cd gui && npx vitest run --reporter=dot` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `gui/src/__tests__/canvas/StreamNode.test.tsx` — stubs for CANV-01, CANV-02
- [ ] `gui/src/__tests__/canvas/ToolboxPanel.test.tsx` — stubs for CANV-01
- [ ] `gui/src/__tests__/canvas/store.test.ts` — stubs for CANV-03, CANV-04, CANV-05, CANV-06, CANV-07
- [ ] `gui/src/__tests__/canvas/EdgeConnection.test.tsx` — stubs for CANV-02, CANV-03

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Drag-and-drop node placement | CANV-01 | jsdom cannot simulate real drag events | Launch Tauri app, drag Pump from toolbox to canvas, verify node appears |
| Edge drawing via handle click-drag | CANV-02 | ReactFlow edge creation requires pointer events | Launch Tauri app, drag from port_out handle to port_in handle, verify edge appears |
| Canvas pan/zoom feel | CANV-05 | UX quality not automatable | Launch Tauri app, scroll to zoom, drag background to pan |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 20s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
