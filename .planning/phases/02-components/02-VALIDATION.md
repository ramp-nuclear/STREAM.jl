---
phase: 2
slug: components
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-12
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia `Test` stdlib |
| **Config file** | none — `test/runtests.jl` is the entry point |
| **Quick run command** | `julia --project=. -e 'using Pkg; Pkg.test()'` |
| **Full suite command** | `julia --project=. -e 'using Pkg; Pkg.test()'` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `julia --project=. -e 'using Pkg; Pkg.test()'`
- **After every plan wave:** Run `julia --project=. -e 'using Pkg; Pkg.test()'`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 2-W0-01 | W0 | 0 | COMP-01..04 | unit stubs | `julia --project=. -e 'using Pkg; Pkg.test()'` | ❌ W0 | ⬜ pending |
| 2-01-01 | 01 | 1 | COMP-01 | unit | `julia --project=. -e 'using Pkg; Pkg.test()'` | ❌ W0 | ⬜ pending |
| 2-01-02 | 01 | 1 | COMP-01 | unit | `julia --project=. -e 'using Pkg; Pkg.test()'` | ❌ W0 | ⬜ pending |
| 2-01-03 | 01 | 1 | COMP-01 | unit | `julia --project=. -e 'using Pkg; Pkg.test()'` | ❌ W0 | ⬜ pending |
| 2-02-01 | 02 | 1 | COMP-02 | unit | `julia --project=. -e 'using Pkg; Pkg.test()'` | ❌ W0 | ⬜ pending |
| 2-03-01 | 03 | 1 | COMP-03 | unit | `julia --project=. -e 'using Pkg; Pkg.test()'` | ❌ W0 | ⬜ pending |
| 2-04-01 | 04 | 1 | COMP-04 | unit | `julia --project=. -e 'using Pkg; Pkg.test()'` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/runtests.jl` — add `@testset "Phase 2: Components"` block with COMP-01 through COMP-04 testset stubs

*Existing `test/runtests.jl` infrastructure covers Phase 1; Phase 2 test cases need to be added.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Channel `observed(compiled_sys)` contains Re, Nu, h_tc, v, T_out, dP | COMP-01 | Requires symbolic inspection post-mtkcompile | Run `mtkcompile(Channel(n=5,...))`, call `observed(sys)`, check names |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
