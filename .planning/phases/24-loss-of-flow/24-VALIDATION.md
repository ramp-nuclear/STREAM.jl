---
phase: 24
slug: loss-of-flow
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-20
---

# Phase 24 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia Test stdlib (`@test`, `@testset`) |
| **Config file** | `test/runtests.jl` |
| **Quick run command** | `julia --project -e 'include("test/test_loss_of_flow.jl")'` |
| **Full suite command** | `julia --project test/runtests.jl` |
| **Estimated runtime** | ~120 seconds (transient simulation) |

---

## Sampling Rate

- **After every task commit:** Run `julia --project -e 'include("test/test_loss_of_flow.jl")'`
- **After every plan wave:** Run `julia --project test/runtests.jl`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 24-01-01 | 01 | 1 | VAL-01, VAL-02 | integration | `julia --project -e 'include("test/test_loss_of_flow.jl")'` | W0 | pending |

*Status: pending · green · red · flaky*

---

## Wave 0 Requirements

- [ ] `test/test_loss_of_flow.jl` — LOF scenario test (build_loop_lof + energy balance assertions)
- [ ] `src/examples.jl` — `build_loop_lof()` builder function

*Wave 0 creates both the builder and test file in one plan.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Solver continuity across flow reversal | VAL-01 | Requires visual inspection of mdot(t) trajectory | Plot `sol[ssys.ine.port_in.mdot, :]` and verify sign changes smoothly without NaN/Inf |
| Flapper opens at expected time | VAL-01 | Event timing depends on IC tuning | Check `sol` callback log or plot mdot_bypass vs t |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
