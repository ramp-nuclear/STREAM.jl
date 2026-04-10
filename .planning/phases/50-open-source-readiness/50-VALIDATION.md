---
phase: 50
slug: open-source-readiness
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-10
---

# Phase 50 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia stdlib Test |
| **Config file** | test/runtests.jl |
| **Quick run command** | `julia --project=. test/runtests.jl` |
| **Full suite command** | `julia --project=. test/runtests.jl` |
| **Estimated runtime** | ~60 seconds (without sysimage) |

---

## Sampling Rate

- **After every task commit:** Run `julia --project=. test/runtests.jl`
- **After every plan wave:** Run full suite
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 50-01-01 | 01 | 1 | D-15/D-16/D-17/D-18/D-19 | — | N/A | manual | `grep -E "^version|^uuid|^authors" Project.toml` | ✅ | ⬜ pending |
| 50-02-01 | 02 | 1 | D-07 | — | N/A | manual | `test -f LICENSE && head -1 LICENSE` | ❌ W0 | ⬜ pending |
| 50-03-01 | 03 | 1 | D-13 (VAL-01 fix) | — | N/A | unit | `julia --project=. test/runtests.jl` | ✅ | ⬜ pending |
| 50-03-02 | 03 | 1 | D-13 (NET-03 fix) | — | N/A | unit | `julia --project=. test/runtests.jl` | ✅ | ⬜ pending |
| 50-04-01 | 04 | 2 | D-12 | — | N/A | manual | `test -f .github/workflows/ci.yml && cat .github/workflows/ci.yml` | ❌ W0 | ⬜ pending |
| 50-03-01 | 03 | 1 | D-09 | — | N/A | manual | `test -f examples/simple_loop.jl && julia --project=. examples/simple_loop.jl` | ❌ W0 | ⬜ pending |
| 50-03-02 | 03 | 1 | D-10 | — | N/A | manual | `test -f examples/mtr_assembly.jl && julia --project=. examples/mtr_assembly.jl` | ❌ W0 | ⬜ pending |
| 50-04-01 | 04 | 1 | D-01..D-06 | — | N/A | manual | `test -f README.md && wc -l README.md` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `LICENSE` — MIT license file in repo root
- [ ] `.github/workflows/ci.yml` — GitHub Actions CI
- [ ] `examples/simple_loop.jl` — minimal forced-convection loop example
- [ ] `examples/mtr_assembly.jl` — HeatDiffusion + ChannelAndContacts example
- [ ] `README.md` — public-facing README

*Existing infrastructure (test suite, Project.toml, src/) covers the remaining requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| README renders correctly on GitHub | D-01..D-06 | Markdown rendering requires browser | Push to GitHub and inspect rendered README |
| CI passes on push | D-12 | Requires GitHub Actions runner | Push to main and verify green check |
| Example scripts run end-to-end | D-09, D-10 | Requires Julia runtime with all deps | `julia --project=. examples/simple_loop.jl` and `julia --project=. examples/mtr_assembly.jl` |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
