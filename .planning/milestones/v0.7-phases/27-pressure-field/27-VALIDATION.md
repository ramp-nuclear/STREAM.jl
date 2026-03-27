---
phase: 27
slug: pressure-field
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-28
---

# Phase 27 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia Test (stdlib) |
| **Config file** | test/runtests.jl |
| **Quick run command** | `julia --project -e 'include("test/test_channel.jl")'` |
| **Full suite command** | `julia --project test/runtests.jl` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `julia --project -e 'include("test/test_channel.jl")'`
- **After every plan wave:** Run `julia --project test/runtests.jl`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 27-01-01 | 01 | 1 | PRES-01 | unit | `julia --project -e 'include("test/test_channel.jl")'` | ✅ | ⬜ pending |
| 27-01-02 | 01 | 1 | PRES-02 | unit | `julia --project -e 'include("test/test_channel.jl")'` | ✅ | ⬜ pending |
| 27-02-01 | 02 | 1 | PRES-03 | unit | `julia --project -e 'include("test/test_fluids.jl")'` | ✅ | ⬜ pending |
| 27-02-02 | 02 | 2 | PRES-04 | unit | `julia --project -e 'include("test/test_channel.jl")'` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| P[i] meaningful only with pressure anchor | PRES-02 | Design constraint — any anchor value is valid; tests must set one | Run test_channel.jl PRES tests; confirm sol[ch.P[1],:] is non-NaN |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
