---
phase: 11
slug: heatdiffusion-component
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-14
---

# Phase 11 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia Test stdlib (`using Test`, `@testset`, `@test`) |
| **Config file** | none — tests run via `Pkg.test()` |
| **Quick run command** | `julia --project test/runtests.jl` |
| **Full suite command** | `julia --project test/runtests.jl` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `julia --project test/runtests.jl`
- **After every plan wave:** Run `julia --project test/runtests.jl`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 11-01-01 | 01 | 0 | HDIFF-01..05 | unit stubs | `julia --project test/runtests.jl` | ❌ W0 | ⬜ pending |
| 11-02-01 | 02 | 1 | HDIFF-01 | unit | `julia --project test/runtests.jl` | ❌ W0 | ⬜ pending |
| 11-02-02 | 02 | 1 | HDIFF-04 | unit | `julia --project test/runtests.jl` | ❌ W0 | ⬜ pending |
| 11-03-01 | 03 | 1 | HDIFF-02 | unit | `julia --project test/runtests.jl` | ❌ W0 | ⬜ pending |
| 11-03-02 | 03 | 1 | HDIFF-03 | unit | `julia --project test/runtests.jl` | ❌ W0 | ⬜ pending |
| 11-04-01 | 04 | 2 | HDIFF-05 | unit | `julia --project test/runtests.jl` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/runtests.jl` — add `@testset "STREAM Phase 11 Tests"` block (5 testsets covering HDIFF-01 through HDIFF-05 as stubs)
- [ ] `src/components.jl` — add `_diffusion_eqs` helper and `HeatDiffusion` function skeleton
- [ ] `src/STREAM.jl` — add `HeatDiffusion` to exports

*All existing test infrastructure is in place — no new test files, no new packages. Wave 0 only adds stubs to existing files.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| T profile is physically correct (heat flows from hot interior to cold boundary) | HDIFF-02 | Visual inspection of steady-state values | Check that T[boundary] < T[interior] at steady state with pinned BCs |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
