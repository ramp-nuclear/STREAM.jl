---
phase: 4
slug: tech-debt-cleanup
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-12
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia Test stdlib + Test.jl |
| **Config file** | `test/runtests.jl` |
| **Quick run command** | `julia --project -e "using Pkg; Pkg.test()"` |
| **Full suite command** | `julia --project -e "using Pkg; Pkg.test()"` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `julia --project -e "using Pkg; Pkg.test()"`
- **After every plan wave:** Run `julia --project -e "using Pkg; Pkg.test()"`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 4-01-01 | 01 | 1 | BUG-01 | unit | `julia --project -e "using Pkg; Pkg.test()"` | ✅ | ⬜ pending |
| 4-01-02 | 01 | 1 | CH/FR renames | unit | `julia --project -e "using Pkg; Pkg.test()"` | ✅ | ⬜ pending |
| 4-01-03 | 01 | 1 | BUG-02 | regression | `julia --project -e "using Pkg; Pkg.test()"` | ✅ | ⬜ pending |
| 4-01-04 | 01 | 1 | stale files | regression | `julia --project -e "using Pkg; Pkg.test()"` | ✅ | ⬜ pending |
| 4-01-05 | 01 | 1 | SUMMARY frontmatter | manual | inspect `.planning/phases/03-integration-and-validation/03-03-SUMMARY.md` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. The only test change is updating COMP-04 in `test/runtests.jl` to call `Gravity(H=3.0)` instead of `Gravity(H=3.0, A_grav=7.85e-5)` — this is done as part of the BUG-01 task, not a Wave 0 stub.

*Existing infrastructure covers all phase requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `03-03-SUMMARY.md` has `requirements-completed: [VAL-01, VAL-02, VAL-03]` | Phase 4 SC-5 | YAML frontmatter field — no automated check | Open `.planning/phases/03-integration-and-validation/03-03-SUMMARY.md` and verify frontmatter contains the field |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
