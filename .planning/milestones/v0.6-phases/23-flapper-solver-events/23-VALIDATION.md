---
phase: 23
slug: flapper-solver-events
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-20
audited: 2026-03-27
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
| 23-01-01 | 01 | 1 | FLAP-01 | compile | `julia --project -e 'include("test/test_flapper.jl")'` | ✅ | ✅ green |
| 23-01-02 | 01 | 1 | FLAP-02 | unit | `julia --project -e 'include("test/test_flapper.jl")'` | ✅ | ✅ green |
| 23-01-03 | 01 | 1 | FLAP-03 | manual | see Manual-Only | ✅ | ✅ manual |
| 23-01-04 | 01 | 1 | FLAP-04 | unit | `julia --project -e 'include("test/test_flapper.jl")'` | ✅ | ✅ green |
| 23-01-05 | 01 | 1 | SOLV-01 | unit | `julia --project -e 'include("test/test_flapper.jl")'` | ✅ | ✅ green |
| 23-02-01 | 02 | 2 | FLAP-05 | integration | `julia --project -e 'include("test/test_flapper.jl")'` | ✅ | ✅ green |
| 23-02-02 | 02 | 2 | FLAP-06 | integration | `julia --project -e 'include("test/test_flapper.jl")'` | ✅ | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

**Coverage notes:**
- FLAP-01 (component construction + mtkcompile): covered implicitly by FLAP-05 and FLAP-06 testsets, both of which build and compile a Flapper-containing system
- FLAP-02 (Hermite cubic ramp R_closed → R_open): covered by FLAP-06 `xi == 1.0` assertion at t_end
- FLAP-04 (ref_mdot user-wired, no equation inside component): covered by both FLAP-05 and FLAP-06 which wire `flapper.ref_mdot ~` externally
- SOLV-01 (solve_transient user callbacks): covered by dedicated `@testset "SOLV-01"` in test_flapper.jl (2 assertions: retcode + fired[])

---

## Wave 0 Requirements

- [x] `test/test_flapper.jl` — full test suite (153 lines; 10 passing tests)
- [x] Entry in `test/runtests.jl` — `include("test_flapper.jl")` line

*Existing infrastructure (`test/test_solvers.jl`) also references SOLV-01 for solve_steady — distinct from the solve_transient callbacks requirement here.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| T_open recorded without solver restart | FLAP-03 | Requires inspecting that no reinit! or discontinuity in solution trajectory | Check that `sol.t` is monotonically increasing through the event; no repeated timestamps |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** 2026-03-27

---

## Validation Audit 2026-03-27

| Metric | Count |
|--------|-------|
| Gaps found | 0 |
| Resolved | 0 |
| Escalated | 0 |
| Tests verified green | 10 |

All 10 tests in `test/test_flapper.jl` pass (FLAP-05: 3, FLAP-06: 5, SOLV-01: 2). VALIDATION.md updated from `draft/pending` to `complete/green` — no new test files needed.
