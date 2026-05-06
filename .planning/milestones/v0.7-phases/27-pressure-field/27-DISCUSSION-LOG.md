# Phase 27: Pressure Field - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the discussion.

**Date:** 2026-03-28
**Phase:** 27-pressure-field
**Mode:** discuss
**Areas discussed:** Inertia in dp[i], dp[i] variable type, T_ONB formula placement

## Gray Areas Identified

| Area | Confidence | Resolution |
|------|-----------|------------|
| Inertia in dp[i] | Likely | Split equally per cell: (dz/A)·Dt(mdot) |
| dp[i] variable type | Likely | MTK unknowns; dP becomes @observed alias |
| T_ONB formula placement | Likely | Private _bergles_rohsenow_dT_ONB helper in correlations.jl |
| sat_temperature formula | Confident | Simantov from Python STREAM, returns K |
| P[i] cumsum sign | Confident | inlet.P - cumsum(dp[1:i]) |

## Decisions Made

### Inertia in dp[i]
- **Decision:** Split equally — `dp[i] += (dz/A)*Dt(inlet.mdot)`
- **Why:** Sum over n cells gives exactly (L/A)*Dt(mdot); satisfies "dP = sum(dp[i]) exactly" success criterion; physically correct for incompressible uniform acceleration

### dp[i] variable type
- **User insight:** No need for separate dP unknown — port wiring can use sum(dp[i]) directly
- **Decision:** dp[i] are MTK unknowns; port wiring: `outlet.P - inlet.P ~ -sum(dp[i])`; dP is @observed alias for backward compat
- **Why:** dp[i] must be unknowns because they appear in the solver equation; dP no longer needed as unknown once port wiring uses inline sum

### T_ONB formula placement
- **Decision:** Private `_bergles_rohsenow_dT_ONB(P_Pa, q_spl)` helper in correlations.jl
- **Why:** Phase 29 exports it as Bergles_Rohsenow_T_ONB — no rewrite needed; avoids planned tech debt from inline duplication

### P[i] absolute vs relative
- **User clarification:** Pressure anchor can be any absolute pressure value, not just 1e5 Pa
- **Decision:** P[i] is absolute — `P_i = inlet.P - sum(dp[j] for j in 1:i)`; anchor must be set by user; any value valid

### MTK observed chaining safety
- **Decision:** P_i, T_sat[i], T_ONB[i] all computed via same local Julia expression `P_i = inlet.P - sum(dp[j]...)` in the loop body — no observed-to-observed chain; both reference dp[j] unknowns directly

## Corrections Applied

None — all gray areas resolved through discussion without reversing initial assumptions.
