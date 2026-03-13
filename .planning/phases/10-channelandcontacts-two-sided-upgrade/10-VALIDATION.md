---
phase: 10
slug: channelandcontacts-two-sided-upgrade
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-14
---

# Phase 10 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia Test stdlib (built-in) |
| **Config file** | none — existing `test/runtests.jl` |
| **Quick run command** | `julia --project -e 'include("test/runtests.jl")'` |
| **Full suite command** | `julia --project -e 'using Pkg; Pkg.test()'` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `julia --project -e 'include("test/runtests.jl")'`
- **After every plan wave:** Run `julia --project -e 'using Pkg; Pkg.test()'`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 10-01-01 | 01 | 1 | DEBT-01 | unit (compilation) | `julia --project -e 'include("test/runtests.jl")'` | ✅ updates runtests.jl | ⬜ pending |
| 10-01-02 | 01 | 1 | CHAN-01 | unit (structure) | `julia --project -e 'include("test/runtests.jl")'` | ✅ updates runtests.jl | ⬜ pending |
| 10-01-03 | 01 | 1 | CHAN-02 | integration | `julia --project -e 'include("test/runtests.jl")'` | ✅ updates runtests.jl | ⬜ pending |
| 10-02-01 | 02 | 2 | DEBT-02 | integration | `julia --project -e 'include("test/runtests.jl")'` | ✅ updates runtests.jl | ⬜ pending |
| 10-02-02 | 02 | 2 | CHAN-03 | integration | `julia --project -e 'include("test/runtests.jl")'` | ✅ updates runtests.jl | ⬜ pending |
| 10-02-03 | 02 | 2 | DEBT-03 | manual | N/A — cosmetic doc edit | ✅ 09-01-SUMMARY.md exists | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. All new tests are additions/updates to `test/runtests.jl`. No Wave 0 setup needed.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Cosmetic doc fix in `09-01-SUMMARY.md` | DEBT-03 | Text change only; no runtime effect | Read `.planning/phases/09-*/09-01-SUMMARY.md` and confirm the referenced cosmetic issue is resolved |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
