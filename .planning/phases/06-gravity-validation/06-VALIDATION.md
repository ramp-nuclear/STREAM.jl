---
phase: 6
slug: gravity-validation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-13
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia Test stdlib (`@testset`, `@test`) |
| **Config file** | test/runtests.jl |
| **Quick run command** | `julia --project -e "include(\"test/runtests.jl\")"` |
| **Full suite command** | `julia --project -e "include(\"test/runtests.jl\")"` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `julia --project -e "include(\"test/runtests.jl\")"`
- **After every plan wave:** Run `julia --project -e "include(\"test/runtests.jl\")"`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** ~30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 06-01-01 | 01 | 1 | GRAV-01, GRAV-02 | unit | `julia --project -e "include(\"test/runtests.jl\")"` | ✅ | ⬜ pending |
| 06-01-02 | 01 | 1 | GRAV-01, GRAV-02 | unit | `julia --project -e "include(\"test/runtests.jl\")"` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements.*

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
