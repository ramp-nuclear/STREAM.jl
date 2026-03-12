---
phase: 3
slug: integration-and-validation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-12
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia Test stdlib (built-in) |
| **Config file** | `Project.toml` `[extras]` + `[targets]` (already configured) |
| **Quick run command** | `julia --project -e "using Pkg; Pkg.test()"` |
| **Full suite command** | `julia --project -e "using Pkg; Pkg.test()"` |
| **Estimated runtime** | ~30 seconds (includes JIT compile) |

---

## Sampling Rate

- **After every task commit:** Run `julia --project -e "using Pkg; Pkg.test()"`
- **After every plan wave:** Run `julia --project -e "using Pkg; Pkg.test()"`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** ~30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 3-01-01 | 01 | 0 | SYS-01 | unit/smoke | `julia --project -e "using Pkg; Pkg.test()"` | ❌ W0 | ⬜ pending |
| 3-01-02 | 01 | 0 | SYS-02 | unit | `julia --project -e "using Pkg; Pkg.test()"` | ❌ W0 | ⬜ pending |
| 3-01-03 | 01 | 1 | SOLV-01 | unit | `julia --project -e "using Pkg; Pkg.test()"` | ❌ W0 | ⬜ pending |
| 3-01-04 | 01 | 1 | SOLV-02 | unit | `julia --project -e "using Pkg; Pkg.test()"` | ❌ W0 | ⬜ pending |
| 3-02-01 | 02 | 2 | VAL-01 | comparison | `julia --project -e "using Pkg; Pkg.test()"` | ❌ W0 | ⬜ pending |
| 3-02-02 | 02 | 2 | VAL-02 | qualitative | `julia --project -e "using Pkg; Pkg.test()"` | ❌ W0 | ⬜ pending |
| 3-02-03 | 02 | 2 | VAL-03 | integration | `julia --project -e "using Pkg; Pkg.test()"` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/runtests.jl` — append `@testset "STREAM Phase 3 Tests"` block (file exists, needs new content)
- [ ] `test/generate_reference.py` — create Python reference script; run once manually to get hardcoded reference values
- [ ] `src/solvers.jl` — create with `solve_steady`, `solve_transient`, `steady_state_guess`
- [ ] `src/STREAM.jl` — add `include("solvers.jl")` and export new functions

*These must exist before task commits in Wave 1+.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Run `generate_reference.py` to produce reference values | VAL-01 | Requires Python STREAM installed; one-time setup | `cd test && python generate_reference.py` then inspect output |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
