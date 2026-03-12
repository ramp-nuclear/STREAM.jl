---
phase: 3
slug: integration-and-validation
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-12
audited: 2026-03-13
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
| 3-01-01 | 01 | 0 | SYS-01 | unit/smoke | `julia --project -e "using Pkg; Pkg.test()"` | ✅ | ✅ green |
| 3-01-02 | 01 | 0 | SYS-02 | unit | `julia --project -e "using Pkg; Pkg.test()"` | ✅ | ✅ green |
| 3-01-03 | 01 | 1 | SOLV-01 | unit | `julia --project -e "using Pkg; Pkg.test()"` | ✅ | ✅ green |
| 3-01-04 | 01 | 1 | SOLV-02 | unit | `julia --project -e "using Pkg; Pkg.test()"` | ✅ | ✅ green |
| 3-02-01 | 02 | 2 | VAL-01 | comparison | `julia --project -e "using Pkg; Pkg.test()"` | ✅ | ✅ green |
| 3-02-02 | 02 | 2 | VAL-02 | qualitative | `julia --project -e "using Pkg; Pkg.test()"` | ✅ | ✅ green |
| 3-02-03 | 02 | 2 | VAL-03 | integration | `julia --project -e "using Pkg; Pkg.test()"` | ✅ | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] `test/runtests.jl` — `@testset "STREAM Phase 3 Tests"` block appended (file exists, new content added by Plan 03-01)
- [x] `test/generate_reference.py` — Python reference script created (Plan 03-03); run once to get hardcoded reference values
- [x] `src/solvers.jl` — created with `solve_steady`, `solve_transient`, `steady_state_guess`, `build_loop`, `build_loop_transient`
- [x] `src/STREAM.jl` — added `include("solvers.jl")` and export new functions

---

## Requirement Coverage

| Requirement | Test Location | Test Name | Status |
|-------------|---------------|-----------|--------|
| SYS-01 | test/runtests.jl | `SYS-01: build_loop compiles closed loop` | ✅ COVERED |
| SYS-02 | test/runtests.jl | `SYS-02: steady_state_guess monotonically increasing` | ✅ COVERED |
| SOLV-01 | test/runtests.jl | `SOLV-01: solve_steady returns physical solution` | ✅ COVERED |
| SOLV-02 | test/runtests.jl | `SOLV-02: build_loop_transient compiles`, `solve_transient returns time-series` | ✅ COVERED |
| VAL-01 | test/runtests.jl | `VAL-01: Steady-state matches Python STREAM within 1%` | ✅ COVERED |
| VAL-02 | test/runtests.jl | `VAL-02: Transient T_outlet rises after T_wall step` | ✅ COVERED |
| VAL-03 | test/runtests.jl | `VAL-03: Test suite runs automatically` | ✅ COVERED |

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Run `generate_reference.py` to produce reference values | VAL-01 | Requires Python STREAM installed; one-time setup | `cd test && python generate_reference.py` then inspect output |

**Manual review status:** Completed during Plan 03-03 execution — T_outlet_ref=327.7894 K, mdot_ref=0.609289 kg/s obtained and hardcoded in `test/runtests.jl`. The VAL-01 test now runs fully automatically without Python STREAM.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** Complete — all 7 requirements COVERED by automated tests in `test/runtests.jl`. 20 Phase 3 tests pass (54 total: 25 Phase 1 + 9 Phase 2 + 20 Phase 3). v0.1 milestone Nyquist-complete.

---

## Validation Audit 2026-03-13

| Metric | Count |
|--------|-------|
| Gaps found | 0 |
| Resolved | 0 |
| Escalated to manual-only | 0 |
| Requirements COVERED | 7/7 |
| Requirements PARTIAL | 0/7 |
| Requirements MISSING | 0/7 |

All Phase 3 requirements (SYS-01, SYS-02, SOLV-01, SOLV-02, VAL-01, VAL-02, VAL-03) have automated test coverage in `test/runtests.jl`. The 20 Phase 3 tests pass in the current 54-test suite. The manual `generate_reference.py` step was completed during Plan 03-03 execution and is not a gap — reference values are hardcoded in the automated test.
