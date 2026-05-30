---
phase: 53-shared-channel-core-with-enthalpy-form-energy-balance
verified: 2026-05-07T08:00:00Z
status: passed
score: 5/5 must-haves verified
overrides_applied: 0
---

# Phase 53: Shared `_channel_core` with Enthalpy-Form Energy Balance — Verification Report

**Phase Goal:** Extract a single private `_channel_core(...; q_left_expr, q_right_expr)` function that is the only source of truth for energy balance, mass conservation, momentum ODE `(L/A)·D(mdot)`, friction `dp[i]`, port wiring, and observables (Re, Pe, P[i], T_sat, T_ONB, dP). Switch the energy-balance convective term to enthalpy form (face-averaged cp, cp(T_in) at the boundary face) in the same change since both touch the same equation.
**Verified:** 2026-05-07T08:00:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A single `_channel_core` function exists; `_channel_base_eqs` is fully deleted from src/components/channel.jl and grep returns no remaining references | ✓ VERIFIED | `grep -c 'function _channel_core' src/components/channel.jl` = 1 (line 208). `grep -c 'function _channel_base_eqs' src/components/channel.jl` = 0. `grep -rn '_channel_base_eqs' src/ test/` returns zero hits. |
| 2 | No `observed_mode`, `skip_htc`, or `T_wall_cells=nothing` flags exist anywhere in the codebase | ✓ VERIFIED | `grep -rn 'observed_mode\|skip_htc\|T_wall_cells' src/` returns zero hits. |
| 3 | Convective enthalpy-form energy balance is implemented in `_channel_core`: numerator uses face-averaged cp `(cp(T_up) + cp(T[i])) / 2`; boundary face of cell 1 (forward) and cell n (reverse) uses `cp(instream(port_in.T))` / `cp(instream(port_out.T))`; denominator retains local `cp(T[i])` | ✓ VERIFIED | channel.jl:247 `cp_face = (cp_water(T_up) + cp_water(T[i])) / 2`. channel.jl:232-233 `T_inlet_fwd = instream(port_in.T)` / `T_inlet_rev = instream(port_out.T)`. channel.jl:255-258: numerator uses `cp_face`; denominator uses `cp_water(T[i])`. These do not cancel (NRG-03). CAC/CHF retain constant-cp form per the explicit Phase 54 deferral in the ROADMAP and the in-file comment at channel.jl:153-155. |
| 4 | Flow reversal symmetry: same `ifelse(mdot >= 0, ...)` selects upstream T and upstream cp; focused unit test on a single-cell channel asserts forward and reverse runs are mirror images | ✓ VERIFIED | channel.jl:241 `T_up = ifelse(port_in.mdot >= 0, T_up_fwd, T_up_rev)`. cp_water(T_up) propagates the selection deterministically (no second ifelse). G3 testset (test_channel_core.jl:421-484) passes 5/5 assertions at rtol=1e-12 absolute equality for n=1; G3b testset (lines 493-551) passes 7/7 assertions including spatial mirror T_rev[i] == T_fwd[n+1-i] at rtol=1e-12 for n=3. Test run confirmed: G3 5/5 PASS, G3b 7/7 PASS. |
| 5 | Every code path inside `_channel_core` is exercised by at least one test (G4 branch-coverage matrix) | ✓ VERIFIED | G4 testset (test_channel_core.jl:568-604) enumerates 6 rows covering all branches B1-B7: forward boundary (B1), reverse boundary (B2), interior cells (B3), adiabatic (B4), left-only (B5), right-only (B6), two-sided (B7). Each row asserts `sol.retcode == ReturnCode.Success`. Test run confirmed: G4 6/6 PASS. |

**Score:** 5/5 truths verified

---

### Scope Note — CR-01 Review Finding (FALSE POSITIVE)

The code review (53-REVIEW.md) raised CR-01 as a BLOCKER claiming CAC and CHF use enthalpy form and are therefore inconsistent with the phase goal. This finding is a false positive.

Verification confirms:
- `grep -n 'cp_face\|cp_water' src/components/thermal_channel.jl` shows both CAC (line 176) and CHF (line 362) use `abs(port_in.mdot) * cp_water(T[i]) * (T_up - T[i])` in the energy balance numerator — the **constant-cp form**.
- The ROADMAP Phase 53 success criteria make no claim that CAC/CHF switch to enthalpy form; SC #3 refers only to `_channel_core`.
- The ROADMAP Phase 54 goal explicitly reads: "Rewrite the three public variants on top of `_channel_core`" — variant migration is Phase 54's mandate.
- The in-file comment at channel.jl:153-155 explicitly states: "Phase 54 will migrate Channel, ChannelAndContacts, and ChannelHeatFlux onto `_channel_core`; until then those variants carry inlined per-variant equation blocks (constant-cp form)."

The reviewer confused the phase scope. CR-01 does not block Phase 53 acceptance.

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `src/components/channel.jl` | Contains `_channel_core` (not `_channel_base_eqs`) | ✓ VERIFIED | 306 lines. `function _channel_core` at line 208. No `_channel_base_eqs`. `Channel` constructor untouched (lines 26-144). |
| `src/components/thermal_channel.jl` | CAC and CHF with inlined constant-cp bodies; no flag references | ✓ VERIFIED | 406 lines. CAC inlined block at lines 105-136 (h_tc loop + friction + port wiring). CHF inlined block at lines 324-351. Zero hits for `_channel_base_eqs`, `observed_mode`, `skip_htc`, `T_wall_cells`. |
| `test/test_channel_core.jl` | G1, G2, G3, G3b, G4 testsets + `_StubChannelCore` harness | ✓ VERIFIED | 604 lines. 10 `@testset` blocks. `_StubChannelCore` body at lines 102-153 delegates to `STREAM._channel_core`. All 54 tests pass. |
| `test/data/stage2_reference.py` | Python parity reference generator with pair_mean_1d formula | ✓ VERIFIED | 239 lines. Contains pure-Python Simantov cp_water implementation + pair_mean_1d fallback. STAGE2_REFERENCE_T constants committed. |
| `test/runtests.jl` | Includes `test_channel_core.jl` between `test_channel.jl` and `test_sign_safety.jl` | ✓ VERIFIED | Line 7: `include("test_channel_core.jl")`. Position confirmed between line 6 (`test_channel.jl`) and line 8 (`test_sign_safety.jl`). |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `_channel_core` energy balance | `cp_water` (registered symbolic) | `cp_face = (cp_water(T_up) + cp_water(T[i])) / 2` at channel.jl:247 | ✓ WIRED | 4 distinct `cp_water` calls per cell in `_channel_core`: `cp_water(T_up)` (line 247), `cp_water(T[i])` (line 247), `cp_water(T[i])` (line 258 denominator), `cp_water(T[i])` (line 271 Pr_i). Grep count in `_channel_core` body: 4 (vs 2 in old form). |
| `_channel_core` boundary face | `instream(port_in.T)` / `instream(port_out.T)` | channel.jl:232-233 | ✓ WIRED | Both `instream` calls present. T_up_fwd uses `T_inlet_fwd` at cell 1; T_up_rev uses `T_inlet_rev` at cell n. |
| `test_channel_core.jl _StubChannelCore` | `STREAM._channel_core` | `core = STREAM._channel_core(...)` at test_channel_core.jl:139 | ✓ WIRED | Direct delegation call. All 12 required kwargs passed. `q_left_expr`/`q_right_expr` lifted via `Num.(q_left_vals)`. |
| `_channel_core` T_ONB observable | `_bergles_rohsenow_dT_ONB` | Inlined `q_density_i` at channel.jl:288-289 | ✓ WIRED | `q_density_i = (q_left_expr[i] + q_right_expr[i]) / (sum(geometry.heated_parts) * dz)` — Julia local, not observable symbol (avoids Pitfall 7). |
| `_channel_core` NOT exported | `src/STREAM.jl` | `grep -rn '_channel_core' src/STREAM.jl` | ✓ WIRED | Zero hits in `src/STREAM.jl`. Private helper accessible only as `STREAM._channel_core` from test code. |

---

### Data-Flow Trace (Level 4)

`_channel_core` is a helper returning `(; eqs, obs)` vectors — it does not render data directly; data flows through the test stub `_StubChannelCore` into a solver. The stub passes numeric `q_left_vals`/`q_right_vals` which are lifted to `Vector{Num}` (real data, not hardcoded empty). The G1, G2, G3, G3b, G4 gates all exercise this data path and produce non-empty numerical results with `ReturnCode.Success`. Level 4 trace confirms real data flows through the wiring.

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| `_channel_core` is defined and reachable | `julia --project=. -e 'using STREAM; @assert isdefined(STREAM, :_channel_core); println("OK")'` | `_channel_core defined: OK` | ✓ PASS |
| G1 constant-cp limit baseline (rtol=1e-6 vs v1.0) | `julia --project=. -e 'include("test/test_channel_core.jl")'` — G1 block | 16/16 PASS | ✓ PASS |
| G2 Python parity (rtol=1e-9) | Same run — G2 block | 6/6 PASS | ✓ PASS |
| G3 single-cell mirror (rtol=1e-12 absolute equality) | Same run — G3 block | 5/5 PASS | ✓ PASS |
| G3b multi-cell spatial mirror (rtol=1e-12) | Same run — G3b block | 7/7 PASS | ✓ PASS |
| G4 branch-coverage matrix (6 rows × 7 branches) | Same run — G4 block | 6/6 PASS | ✓ PASS |
| Full test_channel_core.jl suite | Same run — all testsets | 54/54 PASS | ✓ PASS |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| CORE-01 | 53-01, 53-02 | Single private `_channel_core(...)` exists as single source of truth | ✓ SATISFIED | channel.jl:208-305. `isdefined(STREAM, :_channel_core)` = true. |
| CORE-02 | 53-04 | `_channel_base_eqs` fully removed from `src/components/channel.jl` | ✓ SATISFIED | `grep -rn '_channel_base_eqs' src/ test/` = zero hits. |
| CORE-03 | 53-04 | No `observed_mode` flag anywhere | ✓ SATISFIED | `grep -rn 'observed_mode' src/` = zero hits. |
| CORE-04 | 53-04 | No `skip_htc` flag anywhere | ✓ SATISFIED | `grep -rn 'skip_htc' src/` = zero hits. |
| CORE-05 | 53-04, 53-03 | No `T_wall_cells=nothing` dead branch; all `_channel_core` code paths exercised | ✓ SATISFIED | `grep -rn 'T_wall_cells' src/` = zero hits. G4 6-row matrix covers all branches B1-B7. |
| NRG-01 | 53-02, 53-03 | Numerator uses face-averaged cp `(cp(T_up) + cp(T[i])) / 2` | ✓ SATISFIED | channel.jl:247. G2 parity (rtol=1e-9 vs Python pair_mean_1d) confirms correct averaging. |
| NRG-02 | 53-02, 53-03 | Boundary face uses `cp(instream(...))` not `cp(T[1])` or `cp(T[n])` | ✓ SATISFIED | channel.jl:232-241: T_up at cell 1 forward = `T_inlet_fwd` = `instream(port_in.T)`. cp_water operates on this via `cp_face`. |
| NRG-03 | 53-02, 53-03 | Denominator retains local `cp(T[i])`; numerator cp_face ≠ denominator cp | ✓ SATISFIED | channel.jl:255-258: numerator uses `cp_face`; denominator uses `cp_water(T[i])`. They differ unless T_up == T[i]. |
| NRG-04 | 53-02, 53-03 | Single `ifelse(mdot >= 0, ...)` selects T_up; cp propagates deterministically | ✓ SATISFIED | channel.jl:241. G3+G3b confirm rtol=1e-12 symmetry (5+7 assertions all PASS). |

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `test/test_channel_core.jl` | 472-479, 541-549 | `try/catch` around `@test` — `@test` does not throw on failure in default Julia Test runner; `catch` branch is dead code | WARNING (WR-03 from review) | Does not affect test correctness today (all strict assertions pass); would produce confusing output if a strict assertion ever fails on a different machine. Non-blocking. |
| `test/test_channel_core.jl` | 368-371 | `if isempty(STAGE2_REFERENCE_T)` guard — `STAGE2_REFERENCE_T` is populated (length=5), so this branch can never trigger | INFO (IN-03 from review) | Dead guard code; harmless. |
| `test/test_channel_core.jl` | 472, 540 | `passed_strict` variable set but never read | INFO (IN-04 from review) | Dead variable; harmless. |
| `src/components/channel.jl` | 153-155 | Block comment says "CAC and CHF carry inlined per-variant equation blocks" — slightly stale since this is the transitional Phase 53 state; accurate but could be clearer | INFO (WR-01 from review, partial) | Informational; does not affect correctness. |

None of these rise to BLOCKER status. The `try/catch` anti-pattern (WR-03) is a test hygiene issue but does not affect the current pass/fail outcome since all strict assertions pass on this machine.

---

### Human Verification Required

None. All must-have truths are verifiable programmatically and were verified by test execution producing `54/54 PASS`.

---

### Gaps Summary

No gaps. All 5 ROADMAP success criteria are verified by codebase evidence and live test execution. The code review blocker (CR-01) is a false positive per the ROADMAP scope note — CAC/CHF variant migration to `_channel_core` is Phase 54's mandate, not Phase 53's.

Pre-existing test failures (NET-03 KINSOL flake, VAL-02 ArgumentError, LOF NC buoyancy) were confirmed at parent commit `8bafcbb` in the SUMMARY records and are not Phase 53 regressions.

---

_Verified: 2026-05-07T08:00:00Z_
_Verifier: Claude (gsd-verifier)_
