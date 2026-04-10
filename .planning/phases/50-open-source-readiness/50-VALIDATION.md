---
phase: 50
slug: open-source-readiness
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-10
audited: 2026-04-10
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
| 50-01-01 | 01 | 1 | D-15/D-16/D-17/D-18/D-19 | — | N/A | manual | `grep -E "^version|^uuid|^authors" Project.toml` | ✅ | ✅ green |
| 50-02-01 | 02 | 1 | D-07 | — | N/A | manual | `test -f LICENSE && head -1 LICENSE` | ✅ | ✅ green |
| 50-03-01 | 03 | 1 | D-13 (VAL-01 fix) | — | N/A | unit | `julia --project=. test/runtests.jl` | ✅ | ✅ green |
| 50-03-02 | 03 | 1 | D-13 (NET-03 fix) | — | N/A | unit | `julia --project=. test/runtests.jl` | ✅ | ✅ green |
| 50-04-01 | 04 | 1 | D-12 | — | N/A | manual | `test -f .github/workflows/ci.yml && cat .github/workflows/ci.yml` | ✅ | ✅ green |
| 50-03-03 | 03 | 1 | D-09 | — | N/A | manual | `test -f examples/simple_loop.jl` | ✅ | ✅ green |
| 50-03-04 | 03 | 1 | D-10 | — | N/A | manual | `test -f examples/mtr_assembly.jl` | ✅ | ✅ green |
| 50-04-02 | 04 | 1 | D-01..D-06 | — | N/A | manual | `test -f README.md && wc -l README.md` | ✅ | ✅ green |
| 50-05-01 | 05 | 1 | OSR-04 | — | N/A | manual | `grep NonlinearSolve test/Project.toml` | ✅ | ✅ green |
| 50-05-02 | 05 | 1 | OSR-06 | — | N/A | manual | `grep "hd.power" examples/mtr_assembly.jl` | ✅ | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] `LICENSE` — MIT license file in repo root
- [x] `.github/workflows/ci.yml` — GitHub Actions CI
- [x] `examples/simple_loop.jl` — minimal forced-convection loop example
- [x] `examples/mtr_assembly.jl` — HeatDiffusion + ChannelAndContacts example (power eq fixed)
- [x] `README.md` — public-facing README
- [x] `test/Project.toml` — direct test invocation support (gap closure 50-05)

*All Wave 0 artifacts confirmed present on disk.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| README renders correctly on GitHub | D-01..D-06 | Markdown rendering requires browser | Push to GitHub and inspect rendered README |
| CI passes on push | D-12 | Requires GitHub Actions runner | Push to main and verify green check |
| Example scripts run end-to-end | D-09, D-10 | Requires Julia runtime with all deps | `julia --project=. examples/simple_loop.jl` and `julia --project=. examples/mtr_assembly.jl` |

---

## Validation Audit 2026-04-10

| Metric | Count |
|--------|-------|
| Gaps found | 2 (Wave 0 artifacts missing + mtr_assembly underdetermined) |
| Resolved | 2 (via gap closure plan 50-05) |
| Escalated | 0 |

---

## Validation Sign-Off

- [x] All tasks have automated verify or Wave 0 dependencies
- [x] Sampling continuity: automated unit tests (D-13) cover task stream
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 120s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** 2026-04-10 — all gap closure plans executed, Wave 0 artifacts verified on disk
