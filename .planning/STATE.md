---
gsd_state_version: 1.0
milestone: v0.6
milestone_name: Flow Reversal Systems
status: completed
stopped_at: Completed 22-01-PLAN.md
last_updated: "2026-03-17T23:58:43.623Z"
last_activity: 2026-03-17 — 21-02 elenbaas_nusselt, elenbaas_htc natural convection correlation complete
progress:
  total_phases: 6
  completed_phases: 2
  total_plans: 6
  completed_plans: 5
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

Phase: 22 of 24 (Time-Varying Pump)
Plan: 01 complete (22-01 callable Pump dispatch, solve_transient redesign, PUMP-01/02)
Status: Phase 22 in progress (Plan 01 of 2 complete)
Last activity: 2026-03-18 — 22-01 three-method Pump dispatch + positional solve_transient API

Progress: [████████░░] 83% (5 of 6 v0.6 plans complete)

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
| Phase 22-time-varying-pump P01 | 7 | 2 tasks | 3 files |

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
- [v0.6 PUMP-01]: Pump callable dispatch uses @parameters (dP_pump_fn::FType)(..) — NOT @register_symbolic; caller passes ssys.pump.dP_pump_fn => f in op to ODEProblem
- [v0.6 PUMP]: solve_transient positional: ssys, op, t (time array); tspan=(t[1],t[end]); callbacks=nothing pre-wired for Phase 23 Flapper
- [v0.6 PUMP]: build_loop_transient returns ssys only; T_wall_fn callable wires ch.thermal.T ~ ps[1](t) via @parameters (T_wall_callable::FType)(..)
- [v0.6 PUMP]: @named Pump(dP_pump) positional syntax — @named macro injects name=:pump; old Pump(dP_pump=x) keyword syntax removed; all test call sites need updating in Plan 02

### Pending Todos

None.

### Blockers/Concerns

- VAL-01 (Fourier series validation) is a pre-existing flaky numerical test — not caused by v0.6 changes.
- All test files using Pump(dP_pump=X) keyword syntax will fail until Plan 02 updates them (test_channel.jl, test_composition.jl, test_correlations.jl, test_validation.jl, test_solvers.jl).

---

## Session Continuity

**Last session:** 2026-03-17T23:58:43.621Z
**Stopped at:** Completed 22-01-PLAN.md
**Next action:** `/gsd:plan-phase 20`
**Resume file:** None

---

*Last updated: 2026-03-17 — v0.6 roadmap created; 5 phases (20-24), 8 planned plans, 21 requirements mapped*
