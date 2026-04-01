---
phase: 29
slug: threshold-analysis
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-31
---

# Phase 29 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia Test (stdlib) |
| **Config file** | `test/runtests.jl` |
| **Quick run command** | `julia --project -e 'include("test/test_analysis.jl")'` |
| **Full suite command** | `julia --project test/runtests.jl` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `julia --project -e 'include("test/test_analysis.jl")'`
- **After every plan wave:** Run `julia --project test/runtests.jl`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 29-01-01 | 01 | 1 | THRS-01 | unit | `julia --project -e 'include("test/test_analysis.jl")'` | ❌ W0 | ⬜ pending |
| 29-01-02 | 01 | 1 | THRS-02..07 | unit | `julia --project -e 'include("test/test_analysis.jl")'` | ❌ W0 | ⬜ pending |
| 29-01-03 | 01 | 1 | THRS-08 | unit | `julia --project -e 'include("test/test_analysis.jl")'` | ❌ W0 | ⬜ pending |
| 29-02-01 | 02 | 2 | THRS-09 | unit+integration | `julia --project -e 'include("test/test_analysis.jl")'` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/test_analysis.jl` — stubs for THRS-01..09
- [ ] Add `include("test_analysis.jl")` to `test/runtests.jl`

*Existing test infrastructure (Julia stdlib Test) covers all phase requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Transient matrix broadcasting | THRS-09 | Requires full transient solve setup | Run `build_loop_transient` example and pass result to `threshold_analysis` |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
