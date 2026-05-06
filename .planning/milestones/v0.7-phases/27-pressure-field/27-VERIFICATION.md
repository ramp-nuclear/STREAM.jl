---
phase: 27-pressure-field
verified: 2026-04-01T15:00:00Z
status: passed
score: 7/7 must-haves verified
---

# Phase 27: Pressure Field Verification Report

**Phase Goal:** Add per-cell pressure drop dp[i], absolute pressure P[i], saturation temperature function, and T_sat[i]/T_ONB[i] observables to all channel variants.
**Verified:** 2026-04-01T15:00:00Z
**Status:** passed
**Note:** Retroactive verification — Phase 27 was fully implemented and validated (27-VALIDATION.md confirms all 4 PRES requirements green with 142 total assertions) but 27-VERIFICATION.md was not written at the time. This document closes that gap (identified by v0.7 audit, Phase 31).

## Goal Achievement

### Observable Truths

Plan 01 truths (requirement PRES-03):

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | sat_temperature(1e5) returns ~372.78 K | VERIFIED | 4 spot-check assertions in test_fluids.jl PRES-03 testset |
| 2 | sat_temperature works on symbolic MTK variables (Num type accepted) | VERIFIED | 1 symbolic type assertion in test_fluids.jl PRES-03 testset |
| 3 | _bergles_rohsenow_dT_ONB returns correct values: zero at zero heat flux, positive dT at positive q, finite output | VERIFIED | 3 assertions in test_fluids.jl (zero heat flux, positive dT, finite) |

Plan 02 truths (requirements PRES-01, PRES-02, PRES-04):

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 4 | dP == sum(dp[i]) for all channel variants (Channel, ChannelAndContacts, ChannelHeatFlux) | VERIFIED | 22 assertions in test_channel.jl PRES-01 testset |
| 5 | P[i] forms a monotonically decreasing absolute pressure profile from port_in.P | VERIFIED | 40 assertions in test_channel.jl PRES-02 testset |
| 6 | T_sat[i] accessible and physically reasonable in thermal channels (ChannelAndContacts, ChannelHeatFlux) | VERIFIED | 72 assertions in test_channel.jl PRES-04 testset |
| 7 | T_ONB[i] > T_sat[i] for all cells under nonzero wall heat flux | VERIFIED | included in 72 PRES-04 assertions |

**Score:** 7/7 plan truths verified
**Total assertions:** 142 (8 from Plan 01 + 134 from Plan 02)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `src/fluids.jl` | sat_temperature(P_Pa) with @register_symbolic and abs() DomainError guard | VERIFIED | Function added using Simantov correlation; abs() guard prevents DomainError at bad Newton iterates |
| `src/physical_models/correlations.jl` | _bergles_rohsenow_dT_ONB(P_Pa, q_spl) private helper | VERIFIED | Plain arithmetic (no @register_symbolic); MTK traces it symbolically. NOTE: file later split to src/physical_models/htc/correlations.jl in Phase 30 |
| `src/STREAM.jl` | sat_temperature export | VERIFIED | Added to fluid export line |
| `src/components/channel.jl` | Per-cell dp[i] as solver unknowns; P[i] and dP as @observed; dP = sum(dp[i]) | VERIFIED | dp as MTK unknown array; P[i] computed via cumsum expression; dP observed alias for backward compatibility |
| `src/components/thermal_channel.jl` | dp[i], P[i], T_sat[i], T_ONB[i] in ChannelAndContacts and ChannelHeatFlux | VERIFIED | Observed equations use P_i expression (not P[i] symbol) to avoid observed-to-observed chain; T_sat/T_ONB from sat_temperature and _bergles_rohsenow_dT_ONB |
| `test/test_fluids.jl` | PRES-03 unit tests (8 assertions across 3 testsets) | VERIFIED | sat_temperature spot-checks, symbolic type check, _bergles_rohsenow_dT_ONB correctness |
| `test/test_channel.jl` | PRES-01, PRES-02, PRES-04 integration tests (134 assertions) | VERIFIED | Pressure anchor at 2e5 Pa; PRES-04 uses D_ch=0.01 geometry for convergence |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `src/fluids.jl` | `src/STREAM.jl` | export statement | WIRED | sat_temperature in fluid export line |
| `src/components/thermal_channel.jl` | `src/fluids.jl` | sat_temperature(P_i) call in observed equations | WIRED | T_sat[i] ~ sat_temperature(P_i) |
| `src/components/thermal_channel.jl` | `src/physical_models/correlations.jl` | _bergles_rohsenow_dT_ONB(P_i, q_spl_i) call | WIRED | T_ONB[i] ~ T_sat[i] + _bergles_rohsenow_dT_ONB(...) |
| `src/components/channel.jl` | port wiring | dP ~ port_in.P - port_out.P | WIRED | sum(dp[i]) identity enforced via exact per-cell equations |
| dp[i] unknown | P[i] observed | cumsum expression P_i = port_in.P - sum(dp[1:i]) | WIRED | P_i local variable used to avoid observed-to-observed chain |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| PRES-01 | 27-02 | Per-cell dp[i] replaces lumped dP; dP = sum(dp[i]) exact | SATISFIED | 22 test assertions in PRES-01 testset |
| PRES-02 | 27-02 | Per-cell absolute pressure P[i] as observed in all channel variants | SATISFIED | 40 test assertions in PRES-02 testset |
| PRES-03 | 27-01 | sat_temperature(P) with @register_symbolic in fluids.jl | SATISFIED | 8 test assertions in PRES-03 testset |
| PRES-04 | 27-02 | T_sat[i] and T_ONB[i] observed in ChannelAndContacts and ChannelHeatFlux | SATISFIED | 72 test assertions in PRES-04 testset |

### Key Decisions

- **Removed Dt(mdot) inertia from per-cell dp[i]:** With n per-cell equations each containing Dt(mdot), mtkcompile promoted the derivative as a free state variable in observed_mode (ChannelAndContacts), producing all-NaN solutions. Standalone Inertia component handles momentum — consistent with project architecture (commits 4c56220, 5afbb51).
- **dp[i] kept as solver unknown (not observed):** When dp[i] was observed in ChannelAndContacts, mtkcompile could not resolve the observed-to-observed chain involving dp and P[i]. Keeping dp[i] as an unknown avoids the elimination issue.
- **P[i]/T_sat[i]/T_ONB[i] use P_i local expression (not P[i] symbol):** Using the P[i] observed symbol on the RHS of another observed equation would create an observed-to-observed dependency that mtkcompile cannot resolve. Computing P_i as a local Julia variable (pure arithmetic) and using it in the observed equations avoids this.

### Anti-Patterns Found

None. No TODO/FIXME/placeholder patterns found in Phase 27 files. All functions have substantive implementations.

### Human Verification Required

None — all Phase 27 requirements are programmatically verifiable. Assertion counts from automated test suite confirm coverage.

---

_Verified: 2026-04-01_ / _Source: retroactive from 27-VALIDATION.md evidence_
