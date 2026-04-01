---
phase: 30
slug: htc-friction-completions
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-01
---

# Phase 30 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia Test stdlib |
| **Config file** | test/runtests.jl |
| **Quick run command** | `julia --project -e 'include("test/test_correlations.jl")'` |
| **Full suite command** | `julia --project -e 'using Pkg; Pkg.test()'` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `julia --project -e 'include("test/test_correlations.jl")'`
- **After every plan wave:** Run `julia --project -e 'using Pkg; Pkg.test()'`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 30-01-01 | 01 | 1 | HTC-01 | unit | `julia --project -e 'include("test/test_correlations.jl")'` | ✅ (extend) | ⬜ pending |
| 30-01-02 | 01 | 1 | HTC-02 | unit | same | ✅ (extend) | ⬜ pending |
| 30-01-03 | 01 | 1 | HTC-03 | unit | same | ✅ (extend) | ⬜ pending |
| 30-01-04 | 01 | 1 | HTC-04 | unit | same | ✅ (extend) | ⬜ pending |
| 30-01-05 | 01 | 1 | FRIC-01 | unit | same | ✅ (extend) | ⬜ pending |
| 30-01-06 | 01 | 1 | FRIC-02 | unit | same | ✅ (extend) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/test_correlations.jl` — add test cases for HTC-01..04 and FRIC-01..02 (file exists; extend with new @testset blocks)
- [ ] Import additions in test file for new exported names (`Marco_Han_Nusselt`, `fully_developed_laminar_h_spl`, `developing_laminar_h_spl`, `maximal_htc`, `turbulent_friction`, `viscosity_correction`)

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
