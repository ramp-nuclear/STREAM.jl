---
phase: 48
slug: scram-solver-integration
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-08
---

# Phase 48 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia Test / ReTestItems.jl |
| **Config file** | test/runtests.jl |
| **Quick run command** | `julia --project=. -e 'include("test/test_point_kinetics.jl")'` |
| **Full suite command** | `julia --project=. test/runtests.jl` |
| **Estimated runtime** | ~30-60 seconds (with sysimage: ~10s) |

---

## Sampling Rate

- **After every task commit:** Run quick command (point kinetics tests only)
- **After every plan wave:** Run full suite
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 48-01-01 | 01 | 1 | SCRAM-01 | — | N/A | unit | `julia --project=. -e 'include("test/test_point_kinetics.jl")'` | ✅ exists | ✅ green |
| 48-01-02 | 01 | 1 | SCRAM-02 | — | N/A | integration | `julia --project=. -e 'include("test/test_point_kinetics.jl")'` | ✅ exists | ✅ green |
| 48-01-03 | 01 | 2 | FLAP-REF | — | N/A | unit | `julia --project=. -e 'include("test/test_flapper.jl")'` | ✅ exists | ✅ green |
| 48-01-04 | 01 | 2 | FLAP-CB | — | N/A | integration | `julia --project=. -e 'include("test/test_flapper.jl")'` | ✅ exists | ✅ green |
| 48-01-05 | 01 | 2 | LOF-REF | — | N/A | integration | `julia --project=. -e 'include("test/test_loss_of_flow.jl")'` | ✅ exists | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements.

---

## Manual-Only Verifications

All phase behaviors have automated verification.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 60s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** Nyquist audit complete (2026-04-10)
