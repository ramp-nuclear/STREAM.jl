---
phase: 22
slug: time-varying-pump
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-18
---

# Phase 22 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia Test stdlib (no version — stdlib) |
| **Config file** | none — run via `include("test_pump.jl")` in runtests.jl |
| **Quick run command** | `julia --project=. -e 'include("test/test_pump.jl")'` |
| **Full suite command** | `julia --project=. -e 'using Pkg; Pkg.test()'` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `julia --project=. -e 'include("test/test_pump.jl")'` and `julia --project=. -e 'include("test/test_solvers.jl")'`
- **After every plan wave:** Run `julia --project=. -e 'using Pkg; Pkg.test()'`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** ~60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 22-01-01 | 01 | 1 | PUMP-01 | integration | `julia --project=. -e 'include("test/test_pump.jl")'` | ✅ extend existing | ⬜ pending |
| 22-01-02 | 01 | 1 | PUMP-02 | regression | `julia --project=. -e 'include("test/test_pump.jl")'` | ✅ existing PHY-05 | ⬜ pending |
| 22-01-03 | 01 | 1 | PUMP-03 | integration+analytical | `julia --project=. -e 'include("test/test_pump.jl")'` | ✅ extend existing | ⬜ pending |
| 22-01-04 | 01 | 1 | SOLV-redesign | unit+integration | `julia --project=. -e 'include("test/test_solvers.jl")'` | ✅ rewrite SOLV-02 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. New tests extend `test/test_pump.jl` and rewrite portions of `test/test_solvers.jl` and `test/test_validation.jl`.

*If none: "Existing infrastructure covers all phase requirements."*

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
