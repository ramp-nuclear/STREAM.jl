---
phase: 24
slug: loss-of-flow
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-20
audited: 2026-03-27
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
| 24-01-01 | 01 | 1 | VAL-01, VAL-02 | integration | `julia --project -e 'include("test/test_loss_of_flow.jl")'` | ✓ | green |

*Status: pending · green · red · flaky*

**Note (2026-03-27):** VAL-01 was updated to use time-averaged energy balance for NC regime. Original 5-checkpoint instantaneous test failed at transition checkpoints (9-11% error) because oscillating NC has thermal storage (∂T/∂t ≠ 0). Time-averaged over t=100–300s gives 0.0% error. Forced-flow t=0 instantaneous check retained at 2% rtol.

---

## Wave 0 Requirements

- [x] `test/test_loss_of_flow.jl` — LOF scenario test (build_loop_lof_bypass + energy balance assertions)
- [x] `src/examples.jl` — `build_loop_lof_bypass()` builder function (series topology replaced by bypass in phase 24.1)

*Wave 0 creates both the builder and test file in one plan.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Solver continuity across flow reversal | VAL-01 | Requires visual inspection of mdot(t) trajectory | Plot `sol[ssys.ine.port_in.mdot, :]` and verify sign changes smoothly without NaN/Inf |
| Flapper opens at expected time | VAL-01 | Event timing depends on IC tuning | Check `sol` callback log or plot mdot_bypass vs t |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 120s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** 2026-03-27

## Validation Audit 2026-03-27
| Metric | Count |
|--------|-------|
| Gaps found | 2 |
| Resolved | 2 |
| Escalated | 0 |

**Gap details:**
- VAL-01 PARTIAL: instantaneous energy balance failed at NC oscillation checkpoints (9-11% error). Fixed by switching to time-averaged check over t=100–300s.
- VAL-02 PARTIAL: never ran due to VAL-01 exception. Now runs and passes (2/2 tests green).
