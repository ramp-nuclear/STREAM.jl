# Phase 57: HTC film-temperature evaluation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-08
**Phase:** 57-htc-film-temperature-evaluation
**Areas discussed:** Eval site, Scope of T_film usage, Friction Re and NC Gr/Re², Success bar

---

## Eval site (where film-T property evaluation lives)

| Option | Description | Selected |
|--------|-------------|----------|
| In the Channel core | Channel computes Re_i, Pr_i, k_film at T_film and passes them in. HTC correlation signature `(Re, Pr, T_bulk, T_wall) -> Nu` stays exactly as-is; only the meaning of Re/Pr shifts from bulk to film. Smallest blast radius, no signature break, all existing correlations (DB, Marco-Han, Elenbaas) work unchanged. | ✓ |
| Inside each HTC closure | Change signature to `(mdot, Dh, A, T_cool, T_wall) -> Nu` (or pass `(T_film, T_cool, T_wall, ...)`). Each correlation owns its property eval point — matches Python more literally. Touches every HTC factory + every call site + tests; bigger refactor. | |
| Hybrid via property-bundle | Channel builds a `WaterProps@T_film` bundle (rho, cp, mu, k) and passes that plus T_cool/T_wall to the closure. Mirrors Python's `coolant_funcs.to_properties(T_film, pressure)` shape. New abstraction; nothing else in STREAM.jl uses it yet. | |

**User's choice:** In the Channel core
**Notes:** Default selection accepted. Smallest blast radius and preserves the established "property eval at call site" convention already used for friction Re.

---

## Scope of T_film usage (which terms switch)

| Option | Description | Selected |
|--------|-------------|----------|
| Re, Pr, AND leading k_water | All three terms in `h = Nu(Re,Pr) · k / Dh` evaluate at T_film. Full match to Python's `coolant_funcs.to_properties(T_film, pressure)` — every property the HTC formula touches uses film-T. This is what should collapse the 19% drift. | ✓ |
| Re and Pr only; leave k at bulk | Only the dimensionless groups inside Nu use film-T; the dimensional `k_water(T[i])` outside Nu stays at bulk. Partial match. Likely leaves residual GRAY drift. | |
| Re only | Most conservative — only viscosity in Re uses film-T. Probably won't collapse the drift. | |

**User's choice:** Re, Pr, AND leading k_water
**Notes:** Full match to Python is the intent of the phase; partial fixes would miss the point.

---

## Friction Re and NC Gr/Re²

| Option | Description | Selected |
|--------|-------------|----------|
| Leave friction Re and NC Gr at bulk T | Only the HTC pipeline uses T_film. Friction's Re and `regime_dependent`'s NC detection (β, ν, Gr) keep evaluating at bulk T. Matches Python: friction is a bulk-flow quantity; NC Gr is naturally a bulk vs wall ΔT phenomenon. | ✓ |
| Switch friction Re to T_film also | Friction also uses film-T mu. Diverges from Python (Python's friction correlations are bulk). Would introduce a new drift source on dP. | |
| Investigate per-call-site, defer to research/planning | Confirm by reading Python's friction call site and Gr eval before locking. Adds a research step. | |

**User's choice:** Leave at bulk T (option 1) — but "do this cleanly. Make it look as clean as possible."
**Notes:** Cleanliness directive captured as D-03 in CONTEXT.md: a single principled HTC=film / friction+NC=bulk split anchored by ONE explanatory comment in `_channel_core`, not ad-hoc per-call-site annotations sprinkled through the file.

---

## Success bar

| Option | Description | Selected |
|--------|-------------|----------|
| Re-run parity harness; h_tc rows must drop from FAIL to CLEAN or GRAY | Concrete: `test/data/parity_report.csv` h_tc_left/right rows in simple_loop must move out of FAIL (rtol < 0.02). q_density rows likely follow. Other Phase 56 GRAY rows may shift slightly — that's expected and fine. No new FAIL rows introduced. | ✓ |
| Stricter — h_tc rows must reach CLEAN (≤1e-6) | Aspirational solver-floor target. Probably unreachable given residual cp(T) face-averaging differences. Setting this as the bar likely leaves Phase 57 not-shippable. | |
| h_tc rows green + downstream T_out/T[i] no worse than Phase 56 | Same as option 1 but also asserts that T_out and per-cell T[i] rtol does not regress compared to the Phase 56 baseline CSV. Catches the case where film-T fixes h_tc but accidentally worsens the energy balance. | |

**User's choice:** Re-run parity harness; h_tc rows must drop from FAIL to CLEAN or GRAY
**Notes:** "No new FAIL rows" clause in D-05 covers regression risk implicitly without needing the stricter T_out/T[i] no-regression assertion.

---

## Claude's Discretion

- Exact placement and wording of the explanatory comment in `_channel_core` (D-03 cleanliness directive).
- Exact docstring wording for the eval-point convention note in HTC correlation factories (D-04).
- Whether `T_film_i` is a single named local or an inlined expression; both work, named local is cleaner for the comment to anchor to.
- Wave decomposition (likely a single plan given phase size; planner picks).
- Whether existing `test_correlations.jl` unit tests need updates (likely none; planner verifies).

## Deferred Ideas

- `WaterProps@T_film` property-bundle abstraction — defer to AbstractFluid / multi-fluid work (v0.6+).
- HTC closure signature change to `(mdot, Dh, A, T_cool, T_wall) -> Nu` — Python-shaped but bigger refactor; defer.
- Friction Re film-T evaluation — diverges from Python; not on roadmap.
- NC Gr/Re² film-T evaluation — diverges from Python; not on roadmap.
- Stricter CLEAN-tier h_tc bar — blocked by upstream cp(T) face-averaging; revisit on a future exact-DAE parity push.
- MILESTONES.md v1.1 narrative refresh after Phase 57 CSV regen — owned by Phase 56 D-09 / milestone-close cleanup.
