---
phase: 39
slug: topology-validation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-03
---

# Phase 39 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | vitest (via gui/package.json) |
| **Config file** | `gui/vitest.config.ts` |
| **Quick run command** | `cd gui && npx vitest run --passWithNoTests` |
| **Full suite command** | `cd gui && npx vitest run` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd gui && npx vitest run --passWithNoTests`
- **After every plan wave:** Run `cd gui && npx vitest run`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| TBD | validation logic | 1 | VALD-01 | unit | `cd gui && npx vitest run src/lib/validation.test.ts -t "unconnected"` | ❌ W0 | ⬜ pending |
| TBD | validation logic | 1 | VALD-02 | unit | `cd gui && npx vitest run src/lib/validation.test.ts -t "pressure"` | ❌ W0 | ⬜ pending |
| TBD | validation logic | 1 | VALD-03 | unit | `cd gui && npx vitest run src/lib/validation.test.ts -t "driving"` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `gui/src/lib/validation.test.ts` — stubs for VALD-01, VALD-02, VALD-03 (pure function tests, no DOM needed)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Red ring appears on unconnected node in canvas | VALD-01 | Visual CSS verification | Open canvas, add a Channel without connecting port_in, verify red ring visible |
| AlertDialog appears on export with validation errors | VALD-02, VALD-03 | React dialog rendering | Attempt export with incomplete topology, verify dialog shows grouped error list |
| Alerts disappear when condition resolved | VALD-01–03 | Reactive clearing | Fix unconnected port, verify ring disappears; fix system errors, verify dialog no longer shows on export |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
