---
phase: 14
slug: laminar-correlations
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-15
audited: 2026-03-15
---

# Phase 14 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia Test stdlib |
| **Config file** | none — `test/runtests.jl` is the entry point |
| **Quick run command** | `julia --project=. -e "include(\"test/runtests.jl\")"` |
| **Full suite command** | `julia --project=. -e "include(\"test/runtests.jl\")"` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `julia --project=. -e "include(\"test/runtests.jl\")"`
- **After every plan wave:** Run `julia --project=. -e "include(\"test/runtests.jl\")"`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** ~30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 14-01-01 | 01 | 1 | PHY-02, PHY-03, PHY-04 | unit | `julia --project=. -e "include(\"test/runtests.jl\")"` | ✅ `PHY-02/03/04: Correlation Library` (17 tests) | ✅ green |
| 14-01-02 | 01 | 1 | PHY-02, PHY-03, PHY-04 | unit | `julia --project=. -e "include(\"test/runtests.jl\")"` | ✅ `PHY-01: PipeGeometry_rectangular/circular` (width/depth fields) | ✅ green |
| 14-02-01 | 02 | 2 | PHY-02, PHY-03, PHY-04 | integration | `julia --project=. -e "include(\"test/runtests.jl\")"` | ✅ `PHY-02/03/04: Integration Tests` (11 tests, both regime branches) | ✅ green |
| 14-02-02 | 02 | 2 | PHY-04 | integration (regression) | `julia --project=. -e "include(\"test/runtests.jl\")"` | ✅ `PHY-04: regime_dependent integration — turbulent branch` | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] `test/runtests.jl` — PHY-02/03/04 testsets appended (17 unit + 11 integration tests)
- [x] `src/correlations.jl` — created with 6 public correlation functions/factories

*No new test framework installation needed — existing `runtests.jl` infrastructure is sufficient.*

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [x] All tasks have automated verify (28 tests total: 17 unit + 11 integration)
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 60s (~30s full suite)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** PASSED — 2026-03-15

## Validation Audit 2026-03-15
| Metric | Count |
|--------|-------|
| Gaps found | 0 |
| Resolved | 0 |
| Escalated | 0 |
