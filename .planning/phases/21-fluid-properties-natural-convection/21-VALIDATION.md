---
phase: 21
slug: fluid-properties-natural-convection
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-17
---

# Phase 21 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia Test stdlib + ReTestItems.jl |
| **Config file** | `test/runtests.jl` |
| **Quick run command** | `julia --project -e 'include("test/test_fluids.jl")'` |
| **Full suite command** | `julia --project test/runtests.jl` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `julia --project -e 'include("test/test_fluids.jl")' && julia --project -e 'include("test/test_correlations.jl")'`
- **After every plan wave:** Run `julia --project test/runtests.jl`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** ~30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 21-01-01 | 01 | 1 | FLUID-01 | unit | `julia --project -e 'include("test/test_fluids.jl")'` | ✅ exists | ⬜ pending |
| 21-01-02 | 01 | 1 | FLUID-02, FLUID-03 | unit | `julia --project -e 'include("test/test_fluids.jl")'` | ✅ exists | ⬜ pending |
| 21-01-03 | 01 | 1 | FLUID-01, FLUID-02, FLUID-03 | unit | `julia --project test/runtests.jl` | ✅ exists | ⬜ pending |
| 21-02-01 | 02 | 2 | NATCONV-01 | unit | `julia --project -e 'include("test/test_correlations.jl")'` | ✅ exists | ⬜ pending |
| 21-02-02 | 02 | 2 | NATCONV-02 | unit | `julia --project -e 'include("test/test_correlations.jl")'` | ✅ exists | ⬜ pending |
| 21-02-03 | 02 | 2 | NATCONV-01 | integration | `julia --project test/runtests.jl` | ✅ exists | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. Test files `test/test_fluids.jl` and `test/test_correlations.jl` already exist and only need new `@testset` blocks added for the new functions.

---

## Manual-Only Verifications

All phase behaviors have automated verification.

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
