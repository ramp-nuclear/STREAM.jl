---
phase: 58
slug: mtk-system-determinacy-repair
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-08
---

# Phase 58 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Source: `58-RESEARCH.md` §7 "Validation Architecture".

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `Test` (Julia stdlib) — in use across all 14 existing `test/test_*.jl` files |
| **Config file** | `test/runtests.jl` (orchestrator-only, one `include()` per test file per CLAUDE.md "Test placement rule") |
| **Quick run command** | `bin/jl test/test_determinacy.jl` |
| **Full suite command** | `bin/jl test/runtests.jl` |
| **Estimated runtime** | new file ~5–15s warm; full suite ~3–5 min warm |

---

## Sampling Rate

- **After every task commit:** `bin/jl test/test_determinacy.jl` — cheapest gate against fix-then-regress (~30s warm).
- **After every plan wave:** `bin/jl test/test_determinacy.jl && bin/jl test/test_validation.jl` — exercises structural test plus the seven scenarios that motivated the phase (3–5 min).
- **Before `/gsd-verify-work`:** `bin/jl test/runtests.jl` — full suite green.
- **Max feedback latency:** 30 seconds for incremental, 5 minutes for wave gate.

---

## Per-Task Verification Map

| Scenario | Behavior | Test Type | Automated Command | File Exists | Status |
|----------|----------|-----------|-------------------|-------------|--------|
| DETERMINACY-CANON | Every canonical builder in `src/examples.jl` (`build_loop`, `build_loop_vertical`, `build_loop_transient`, `build_cube`, `build_loop_lof_bypass`) is `fully_determined=true` after `mtkcompile` | unit (structural) | `bin/jl test/test_determinacy.jl` | ❌ W0 | ⬜ pending |
| DETERMINACY-PHASE58 | Every Phase-58 scenario topology (MTR sym/asym/one-sided, VAL-01 HD Fourier setup, VAL-02 two-plate steady, PK validation, VAL-02 transient) is `fully_determined=true` | unit (structural) | `bin/jl test/test_determinacy.jl` | ❌ W0 | ⬜ pending |
| MTR-SYM | MTR symmetric reaches `solve_steady` Success | integration | `bin/jl test/test_validation.jl` (testset "Python parity: MTR symmetric") | ✅ | ⬜ pending |
| MTR-ASYM | MTR asymmetric reaches `solve_steady` Success | integration | `bin/jl test/test_validation.jl` (testset "Python parity: MTR asymmetric") | ✅ | ⬜ pending |
| MTR-ONESIDED | MTR one-sided reaches `solve_steady` Success | integration | `bin/jl test/test_validation.jl` (testset "Python parity: MTR one-sided") | ✅ | ⬜ pending |
| VAL-01-FOURIER | HD transient reaches `solve(ODEProblem)` Success and Fourier reference holds | integration | `bin/jl test/test_validation.jl` (testset "VAL-01: HeatDiffusion transient — Fourier series validation") | ✅ | ⬜ pending |
| VAL-02-TWOPLATE | Two-plate one-channel reaches `solve_steady` Success and energy balance holds | integration | `bin/jl test/test_validation.jl` (testset "VAL-02: Two-plate one-channel topology — both faces active") | ✅ | ⬜ pending |
| VAL-02-TRANSIENT | T_outlet rises after T_wall step in `build_loop_transient` callable mode | integration | `bin/jl test/test_validation.jl` (testset "VAL-02: Transient T_outlet rises after T_wall step") | ✅ | ⬜ pending |
| PK-VAL | PK testset reaches `solve_*` (steady or transient fallback) | integration | `bin/jl test/test_validation.jl` (testset "PointKinetics validation") | ✅ | ⬜ pending |
| AUDIT-FFD | All 22 `fully_determined=false` / `check_length=false` sites classified per D-04; bug-hiding flips to `true`; legitimate-structural sites get inline comment naming the structural reason | unit | `bin/jl test/runtests.jl` | ✅ existing files | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/test_determinacy.jl` — new file with two testsets:
  1. **Canonical builders** — every builder in `src/examples.jl`
  2. **Phase-58 scenario topologies** — MTR sym/asym/one-sided, VAL-01 HD Fourier setup, VAL-02 two-plate steady, PK validation, VAL-02 transient
- [ ] `test/runtests.jl` — add `include("test_determinacy.jl")` line
- [x] Test framework — Julia `Test` stdlib already in use; no install needed.

---

## Determinacy Contract (formal)

For every system `sys` produced by a builder or a Phase-58 scenario topology:

```julia
# Cheap surface check (microseconds):
ssys = mtkcompile(sys; fully_determined=false)
@assert length(equations(ssys)) == length(unknowns(ssys))

# Strong structural check (runs StateSelection + alias-elimination, ms):
ssys = mtkcompile(sys; fully_determined=true)   # raises ExtraVariablesSystemException
                                                 # or ExtraEquationsSystemException on imbalance
```

Both checks must pass. The regression target is "the determinacy contract holds across MTK upgrades." The most likely future regression class is "a transitive MTK upgrade reintroduces Δ ≠ 0 in one of these scenarios"; the test catches it in <1 s warm and names the failing builder.

---

## Manual-Only Verifications

| Behavior | Why Manual | Test Instructions |
|----------|------------|-------------------|
| MTK CHANGELOG read for the version bump that introduced the `power(t)` non-auto-balance behavior | Documentation-grade evidence; not a runtime invariant | Plan 58-01 records the read in `58-01-SUMMARY.md` per D-02. |

*Otherwise: all phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies declared
- [ ] Sampling continuity: no 3 consecutive tasks without an automated verify
- [ ] Wave 0 covers all MISSING references (`test_determinacy.jl` + `runtests.jl` wiring)
- [ ] No watch-mode flags (the daemon is the watch loop; tests are one-shot)
- [ ] Feedback latency < 30 s for incremental, < 5 min for wave gate
- [ ] `nyquist_compliant: true` set in frontmatter once Wave 0 is complete

**Approval:** pending
