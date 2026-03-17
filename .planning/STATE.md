---
gsd_state_version: 1.0
milestone: v0.6
milestone_name: Flow Reversal Systems
status: completed
stopped_at: Completed 21-02-PLAN.md
last_updated: "2026-03-17T18:45:52.714Z"
last_activity: 2026-03-17 — 21-02 elenbaas_nusselt, elenbaas_htc natural convection correlation complete
progress:
  total_phases: 5
  completed_phases: 2
  total_plans: 4
  completed_plans: 4
  percent: 100
---

# STATE: STREAM.jl

*Project memory — updated at the start and end of every session*

---

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-17)

**Core value:** A Julia MTK-based thermal-hydraulics library that matches Python STREAM results, proving the architecture is sound before large-scale porting begins.
**Current focus:** Phase 20 — Sign Safety (v0.6 start)
**Python STREAM reference:** ~/projects/STREAM

---

## Current Position

Phase: 21 of 24 (Fluid Properties and Natural Convection)
Plan: 02 complete (21-02 elenbaas_nusselt, elenbaas_htc, NATCONV-01/02)
Status: Phase 21 complete
Last activity: 2026-03-17 — 21-02 elenbaas_nusselt, elenbaas_htc natural convection correlation complete

Progress: [██████████] 100% (4 of 4 phase 21 plans complete)

---

## Performance Metrics

**v0.5 velocity reference:** 6 plans completed

| Phase | Plans | Avg/Plan |
|-------|-------|----------|
| 17 File Structure Reorganization | 2 | ~24 min |
| 18 Test Split and API Cleanup | 2 | ~9 min |
| 19 Docstrings, CLAUDE.md, Final Polish | 2 | ~6 min |

*Updated after each plan completion*

---
| Phase 20-sign-safety P01 | 2 | 2 tasks | 2 files |
| Phase 20 P02 | 100 | 2 tasks | 4 files |
| Phase 21 P01 | 27 | 2 tasks | 7 files |
| Phase 21 P02 | 10 | 2 tasks | 2 files |

## Accumulated Context

### Key Decisions (carry-forward for v0.6)

- [v0.5]: solve_transient is now keyword-only — SOLV-01 must preserve this convention when adding `callbacks` kwarg
- [v0.4]: ifelse() used for flow reversal and regime switching — SIGN-01..03 may need to audit all ifelse() sign usages
- [v0.4]: Correlation functions are plain Julia closures (not @register_symbolic) — elenbaas_nusselt follows the same pattern
- [v0.4]: Re/Nu/velocity/Pe are @observed (not unknowns) — SIGN-02 must ensure these stay @observed and sign-correct
- [v0.3]: Flapper is a new component file — goes to src/components/ per CLAUDE.md layout
- [v0.6 SIGN]: ifelse(port_in.mdot >= 0, T_up_fwd, T_up_rev) per-cell upwinding — T_inlet_fwd/rev declared before loop, selection inside loop
- [v0.6 SIGN]: port_in.T ~ T[1] is correct MTK outflow equation (T[1] is outflow temp through port_in under reverse flow)
- [v0.6 SIGN]: velocity[i] (unsigned speed) and v[i] (signed) are distinct observables in ChannelAndContacts
- [v0.6 SIGN-02]: abs(port_in.mdot) in FV energy balance — T_up already selects correct direction; advective flux = |mdot|*cp*(T_up-T[i]); signed mdot gives wrong sign for reversed flow
- [v0.6 SIGN-02]: Q_advect for reversed flow uses T_boundary_inlet (from port_in.T pin), NOT T[n] (already heated above T_inlet by wall)
- [v0.6 FLUID]: Re, Pr, Nu, Pe NOT exported as standalone names — conflict with @variables in component functions; use STREAM.Re(...) for utility access
- [v0.6 FLUID]: HTC closures accept (Re, Pr, T_bulk, T_wall); dittus_boelter/constant_Nusselt use args...; regime_dependent forwards 4 args explicitly
- [v0.6 FLUID]: elenbaas_nusselt and elenbaas_htc pre-exported in STREAM.jl; Plan 02 only needs to implement the functions
- [v0.6 NATCONV]: NATCONV-02 Gr/Ra tolerances use rtol=5e-4 — Julia Simantov coefficients match Python exactly but tabulated reference values differ by ~0.034%; standalone Nu test with pre-computed Ra validates formula to rtol=1e-6

### Pending Todos

None.

### Blockers/Concerns

- VAL-01 (Fourier series validation) is a pre-existing flaky numerical test — not caused by v0.6 changes.
- PUMP-01 requires @register_symbolic for a callable — implementation strategy (wrapping f(t) as symbolic) needs prototyping in plan.

---

## Session Continuity

**Last session:** 2026-03-17T18:04:09.802Z
**Stopped at:** Completed 21-02-PLAN.md
**Next action:** `/gsd:plan-phase 20`
**Resume file:** None

---

*Last updated: 2026-03-17 — v0.6 roadmap created; 5 phases (20-24), 8 planned plans, 21 requirements mapped*
