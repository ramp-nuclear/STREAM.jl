---
phase: 42
slug: edge-path-visual-overhaul
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-03
---

# Phase 42 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | vitest (existing GUI test suite) |
| **Config file** | `gui/vite.config.ts` or `gui/vitest.config.ts` |
| **Quick run command** | `cd gui && npm test -- --run` |
| **Full suite command** | `cd gui && npm test -- --run` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd gui && npm test -- --run`
- **After every plan wave:** Run `cd gui && npm test -- --run`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 42-01-01 | 01 | 1 | arrowheads | unit/visual | `cd gui && npm test -- --run` | ✅ | ⬜ pending |
| 42-01-02 | 01 | 1 | parallel routing | unit | `cd gui && npm test -- --run` | ✅ | ⬜ pending |
| 42-01-03 | 01 | 1 | edge enrichment on load | unit | `cd gui && npm test -- --run` | ✅ | ⬜ pending |
| 42-02-01 | 02 | 1 | handle polarity colors | visual/manual | manual visual check | ❌ W0 | ⬜ pending |
| 42-02-02 | 02 | 1 | cursor fix | manual | manual interaction | ❌ W0 | ⬜ pending |
| 42-03-01 | 03 | 2 | rename counter reconstruct | unit | `cd gui && npm test -- --run` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Test stubs for arrowhead/routing store logic (if not already covered by existing tests)

*Existing infrastructure covers most phase requirements — vitest suite already set up.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Arrowheads visible on canvas | SC-1 | ReactFlow rendering is DOM/visual | Load GUI, add Pump→Channel edge, verify arrowhead at target end |
| Two distinct parallel routes | SC-2 | Visual routing appearance | Create Pump→Channel→Pump loop, verify non-overlapping edges |
| Cursor state on drag handles | SC-4 | Browser cursor CSS behavior | Hover over edge drag handles, verify cursor doesn't disappear |
| Handle polarity colors | D-06 | Visual color rendering | Add component with FlowPort handles, verify blue-300/blue-700 |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
