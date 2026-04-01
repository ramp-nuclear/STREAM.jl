# Phase 29: Threshold Analysis - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the discussion.

**Date:** 2026-03-31
**Phase:** 29-threshold-analysis
**Mode:** discuss
**Areas analyzed:** threshold_analysis() API, T_wall extraction, THRS-01 promotion, File organization

---

## Areas Discussed

### threshold_analysis() API

| Question | Options Presented | Selected |
|----------|------------------|----------|
| How are threshold functions passed in? | Keyword NamedTuple (kwargs), NamedTuple arg, Dict | Keyword NamedTuple (kwargs) |
| What do functions receive? | User clarified — see below | ChannelState bundle |
| Ship pre-built wrappers? | Yes + chfr() helper, Physics only | Yes + chfr() helper |
| Where does threshold_analysis() live? | New src/analysis.jl, Everything in physical_models/ | New src/analysis.jl |

**User clarification:** User asked Claude to look at Python STREAM before finalizing. After reading Python STREAM's `analysis/thresholds.py` and `aggregator/aggregator.py`, Claude adopted the two-layer pattern (physics functions + analysis wrappers with uniform signature) and proposed shipping pre-built wrappers alongside the physics functions.

**Key insight from Python STREAM:** The `ThresholdFunction` protocol defines a uniform wrapper signature. All analysis-layer wrappers accept the same state bundle and absorb unused kwargs. This enables `threshold_analysis` to call all registered functions identically without knowing their signatures.

### T_wall extraction and directionality

| Question | Options Presented | Selected |
|----------|------------------|----------|
| state.T_wall convention | max(left, right), left/right only | max(left, right) — but raised directionality concern |

**User clarification:** Different CHF/CHFR calculations may need per-face fluxes. Asymmetric heating is common (outer vs inner plate face). Negative q_flux occurs when channel cools the wall — CHFR must handle this.

**Resolution:**
- `ChannelState` exposes `q_flux_left`, `q_flux_right`, and `q_flux = max(left, right)`
- `chfr(fn; direction=:max)` with `:left`, `:right`, `:max`, `:total` options
- Guard: `q_flux_i ≤ 0 → Inf` (wall cooled by coolant = no boiling risk = infinite safety margin)
- Negative CHFR is physically meaningless and would be a silent safety analysis bug

### THRS-01 Promotion

| Question | Options Presented | Selected |
|----------|------------------|----------|
| How to promote _bergles_rohsenow_dT_ONB | Public calls private helper, Replace private everywhere | Public calls private helper |

**Rationale:** `_bergles_rohsenow_dT_ONB` is used internally by ChannelAndContacts T_ONB observable. Keeping it private in `correlations.jl` avoids touching the channel component. The new public `Bergles_Rohsenow_T_ONB(pressure, q_wall, T_sat)` returns `T_sat + _bergles_rohsenow_dT_ONB(...)`.

### File Organization

| Question | Options Presented | Selected |
|----------|------------------|----------|
| File layout | src/analysis.jl (new) + physical_models/threshold_analysis.jl, Everything in one file | Two-file split |

**Rationale:** Mirrors Python STREAM's `analysis/` vs `physical_models/` separation. Keeps physics pure and testable independently. `src/analysis.jl` handles MTK solution interaction.

---

## No Corrections Made

All areas reached consensus through discussion — no user corrections to initial proposals.

---

## Python STREAM Reference

Consulted during discussion:
- `/home/itayb/projects/STREAM/stream/physical_models/thresholds.py` — physics function signatures and formulas
- `/home/itayb/projects/STREAM/stream/analysis/thresholds.py` — ThresholdFunction protocol, threshold_analysis factory, twall_limit, directional wrappers
- `/home/itayb/projects/STREAM/stream/aggregator/aggregator.py` — CalcState/aggregator pattern (informed ChannelState design)
- `/home/itayb/projects/STREAM/stream/physical_models/heat_transfer_coefficient/temperatures.py` — Bergles_Rohsenow_T_ONB formula reference
