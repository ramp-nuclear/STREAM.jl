---
phase: 06-gravity-validation
verified: 2026-03-13T12:46:31Z
status: passed
score: 3/3 must-haves verified
---

# Phase 6: Gravity Validation Verification Report

**Phase Goal:** Validate that gravity is correctly wired and produces physically correct results in a vertical closed loop simulation
**Verified:** 2026-03-13T12:46:31Z
**Status:** passed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A vertical closed loop (Channel with g_acc=9.80665 + Gravity on return leg of equal height) assembles, mtkcompiles, and solves to ReturnCode.Success | VERIFIED | `build_loop_vertical()` in `src/solvers.jl` lines 153-197; GRAV-01 testsets in `test/runtests.jl` lines 298-312 test both mtkcompile and solve |
| 2 | Gravity cancellation: equal up/down height (g_acc=9.80665, H=L_ch) produces steady-state mass flow within 1% of horizontal reference loop (g_acc=0) | VERIFIED | GRAV-02 testset in `test/runtests.jl` lines 323-342; `isapprox(mdot_vert, mdot_horiz; rtol=0.01)` assertion present and wired to both `build_loop` and `build_loop_vertical` |
| 3 | All 54 existing v0.1 tests continue to pass (no regressions) | VERIFIED | Phase 1/2/3 testsets unchanged; commit 8c48067 message confirms "All 58 tests pass" (54 prior `@test` assertions + 4 new); no modifications to existing test blocks detected |

**Score:** 3/3 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `src/solvers.jl` | `build_loop_vertical()` function assembling Channel + Gravity in a closed loop | VERIFIED | Lines 129-197; 69-line substantive implementation with full docblock, correct component wiring, mtkcompile call, and `@info` logging mirroring `build_loop` |
| `test/runtests.jl` | Phase 6 gravity test cases (GRAV-01 and GRAV-02) | VERIFIED | Lines 291-344; `@testset "STREAM Phase 6 Tests"` block present with 3 inner testsets covering GRAV-01 (2 sub-tests) and GRAV-02 (1 sub-test) |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `Channel.dP equation` | `Gravity.port_in.P - port_out.P` | `connect()` wiring in `build_loop_vertical` | VERIFIED | `src/solvers.jl` line 182: `connect(ch.port_out, grav.port_out)` and line 183: `connect(grav.port_in, pump.port_in)` — reversed wiring for correct descending-return-leg physics |
| `build_loop_vertical` | `solve_steady` | `mtkcompile` output passed to `SteadyStateProblem` | VERIFIED | `test/runtests.jl` lines 308-311: `sol = solve_steady(ssys_v, op)` directly follows `ssys_v = build_loop_vertical(...)` |

**Wiring note:** The key wiring uses the physically correct reversed-port pattern (`ch.port_out -> grav.port_out`; `grav.port_in -> pump.port_in`) discovered and fixed during TDD. The PLAN's suggested naive flow-direction wiring was superseded by the corrected implementation. The PLAN `pattern` field anticipated `connect(ch.port_out, grav.port_in)` (naive), but the actual code uses the reversed convention — this is the physically correct fix, not a deviation.

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| GRAV-01 | 06-01-PLAN.md | Vertical closed loop assembles, compiles, and solves correctly | SATISFIED | `build_loop_vertical()` implemented and exported; GRAV-01 testset in `test/runtests.jl` tests both mtkcompile and solve; REQUIREMENTS.md marks `[x]` |
| GRAV-02 | 06-01-PLAN.md | Gravity cancellation: equal height gives same steady-state flow as horizontal reference within 1% | SATISFIED | GRAV-02 testset in `test/runtests.jl` compares `mdot_vert` to `mdot_horiz` with `rtol=0.01`; REQUIREMENTS.md marks `[x]` |

**Orphaned requirements check:** REQUIREMENTS.md traceability table maps GRAV-01 and GRAV-02 to Phase 6 only. No additional requirement IDs are mapped to Phase 6 that were not claimed in the plan. Zero orphaned requirements.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | — | — | None found |

Scanned `src/solvers.jl` and `test/runtests.jl` for: TODO/FIXME/HACK, empty returns (`return null`, `return {}`, `return []`), placeholder comments. Zero matches.

The one comment near line 4 of `src/solvers.jl` ("Future refactor note") is pre-existing from Phase 3 and is informational, not a blocker.

---

### Human Verification Required

None. All phase behaviors are fully automatable:
- Assembly and solve behavior is tested via `@test` assertions in `test/runtests.jl`
- Cancellation physics is quantitative (1% tolerance), not visual
- No external services, no UI, no real-time behavior involved

---

### Gaps Summary

No gaps. All three must-have truths are verified, both artifacts are substantive and wired, both requirement IDs are satisfied, and no anti-patterns were found.

**Test count reconciliation:** The PLAN anticipated 57 total tests (54 + 3 new `@testset` blocks). The SUMMARY reports 58 (counting 4 new `@test` assertions instead of testset blocks). The actual file contains exactly 54 `@test` assertions at the Phase 3 close, plus 4 new `@test` assertions in the Phase 6 block = 58 total assertions. The discrepancy is cosmetic (testset-count vs assertion-count); no missing tests.

---

## Commit Verification

| Commit | Description | Files Changed | Status |
|--------|-------------|---------------|--------|
| `15274d4` | feat(06-01): add build_loop_vertical | `src/solvers.jl`, `src/STREAM.jl` | EXISTS in git log |
| `8c48067` | feat(06-01): add GRAV-01 and GRAV-02 tests + wiring fix | `src/solvers.jl`, `test/runtests.jl` | EXISTS in git log |

---

_Verified: 2026-03-13T12:46:31Z_
_Verifier: Claude (gsd-verifier)_
