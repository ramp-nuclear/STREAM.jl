---
phase: 23
slug: flapper-solver-events
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-20
---

# Phase 23 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia Test (stdlib) + TestEnv |
| **Config file** | test/runtests.jl |
| **Quick run command** | `julia --project -e 'include("test/test_flapper.jl")'` |
| **Full suite command** | `julia --project test/runtests.jl` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `julia --project -e 'include("test/test_flapper.jl")'`
- **After every plan wave:** Run `julia --project test/runtests.jl`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 23-01-01 | 01 | 1 | FLAP-01 | compile | `julia --project -e 'using STREAM; Flapper(name=:f)'` | ❌ W0 | ⬜ pending |
| 23-01-02 | 01 | 1 | FLAP-02 | unit | `julia --project -e 'include("test/test_flapper.jl")'` | ❌ W0 | ⬜ pending |
| 23-01-03 | 01 | 1 | FLAP-03 | unit | `julia --project -e 'include("test/test_flapper.jl")'` | ❌ W0 | ⬜ pending |
| 23-01-04 | 01 | 1 | FLAP-04 | unit | `julia --project -e 'include("test/test_flapper.jl")'` | ❌ W0 | ⬜ pending |
| 23-01-05 | 01 | 1 | SOLV-01 | unit | `julia --project -e 'include("test/test_solvers.jl")'` | ✅ | ⬜ pending |
| 23-02-01 | 02 | 2 | FLAP-05 | integration | `julia --project -e 'include("test/test_flapper.jl")'` | ❌ W0 | ⬜ pending |
| 23-02-02 | 02 | 2 | FLAP-06 | integration | `julia --project -e 'include("test/test_flapper.jl")'` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/test_flapper.jl` — stub file with @testset structure for FLAP-01..06
- [ ] Entry in `test/runtests.jl` — `include("test_flapper.jl")` line

*Existing infrastructure (`test/test_solvers.jl`) covers SOLV-01.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| T_open recorded without solver restart | FLAP-03 | Requires inspecting that no reinit! or discontinuity in solution trajectory | Check that `sol.t` is monotonically increasing through the event; no repeated timestamps |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
