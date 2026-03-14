---
phase: 14
slug: laminar-correlations
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-15
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
| 14-01-01 | 01 | 1 | PHY-02, PHY-03, PHY-04 | unit/integration | `julia --project=. -e "include(\"test/runtests.jl\")"` | ❌ Wave 1 | ⬜ pending |
| 14-01-02 | 01 | 1 | PHY-02, PHY-03, PHY-04 | unit/integration | `julia --project=. -e "include(\"test/runtests.jl\")"` | ❌ Wave 1 | ⬜ pending |
| 14-02-01 | 02 | 2 | PHY-02, PHY-03, PHY-04 | unit/integration | `julia --project=. -e "include(\"test/runtests.jl\")"` | ❌ Wave 1 | ⬜ pending |
| 14-02-02 | 02 | 2 | PHY-04 | integration (regression) | `julia --project=. -e "include(\"test/runtests.jl\")"` | ✅ exists (VAL tests) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/runtests.jl` — append PHY-02, PHY-03, PHY-04 testsets (file exists; tests stubbed in Wave 1)
- [ ] `src/correlations.jl` — does not exist; create in Wave 1 (source file, not test infra)

*No new test framework installation needed — existing `runtests.jl` infrastructure is sufficient.*

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
