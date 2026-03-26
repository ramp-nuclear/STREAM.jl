---
gsd_state_version: 1.0
milestone: v0.6
milestone_name: Flow Reversal Systems
status: unknown
stopped_at: Phase 26 context gathered
last_updated: "2026-03-26T21:17:12.827Z"
progress:
  total_phases: 8
  completed_phases: 7
  total_plans: 12
  completed_plans: 12
---

# STATE: STREAM.jl

*Project memory — updated at the start and end of every session*

---

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-17)

**Core value:** A Julia MTK-based thermal-hydraulics library that matches Python STREAM results, proving the architecture is sound before large-scale porting begins.
**Current focus:** Phase 25 — argument-structure-audit
**Python STREAM reference:** ~/projects/STREAM

---

## Current Position

Phase: 25
Plan: Not started

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
| Phase 22-time-varying-pump P02 | 32 | 2 tasks | 6 files |
| Phase 23-flapper-solver-events P01 | 9 | 2 tasks | 4 files |
| Phase 23 P02 | 21 | 1 tasks | 1 files |
| Phase 24-loss-of-flow P01 | 90 | 2 tasks | 4 files |
| Phase 24.1 P01 | 12 | 2 tasks | 4 files |
| Phase 24.1 P02 | 55 | 2 tasks | 4 files |
| Phase 25 P01 | 15 | 2 tasks | 17 files |

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
- [v0.6 PUMP]: @named Pump(dP_pump) positional syntax — @named macro injects name=:pump; old Pump(dP_pump=x) keyword syntax removed; all test call sites now updated (Plan 02)
- [v0.6 PUMP-02]: Analytical PUMP-03 formula corrected: particular solution for tau*x'+x=dP0/R*(1-t/T_ramp) is x_p=(dP0/R)*(1+tau/T_ramp-t/T_ramp); plan spec had sign error
- [v0.6 PUMP-02]: Two-system pattern for callable T_wall ICs: scalar build_loop_transient for solve_steady, callable build_loop_transient for solve_transient (SteadyStateProblem cannot handle time-dependent callables)
- [v0.6 PUMP-02]: Pair{Any,Any} op vector required when mixing Float64 state ICs with callable parameter values; use last(parameters(ssys)) to get raw callable sym
- [v0.6 PUMP-02]: Two thermal anchors needed in hydraulics-only closed loop (no HeatExchanger): single pump.port_in.T anchor leaves ine.port_out.T underdetermined
- [v0.6 FLAP-01]: T_open initial value is 1e30 (not Inf) -- Inf causes Rodas5P instability; 1e30 sentinel keeps ramp at 0 before event fires
- [v0.6 FLAP-03]: affect_neg=[T_open ~ t] fires on downward crossing (ref_mdot drops below threshold); affect=nothing ignores upward crossing
- [v0.6 FLAP-04]: ref_mdot has no equation inside Flapper -- user must wire flapper.ref_mdot ~ component.port_in.mdot during composition
- [v0.6 FLAP-06]: Callable Pump(f(t)) cannot be used in same ODEProblem as Flapper (SymbolicContinuousCallback): MTK compile_equational_affect builds sub-ImplicitDiscreteProblem that cannot resolve callable parameter at build time; use Pump(0)+Inertia IC decay pattern for open-transition tests
- [v0.6 FLAP-05]: Use threshold << expected steady-state mdot for closed-state tests (e.g. threshold=1e-6 vs mdot~1e-3); default threshold=0.01 > mdot through R_closed=1e8 Flapper, making test fragile
- [v0.6 LOF]: Series topology for LOF: parallel bypass Gravity creates irresolvable pressure contradiction when H_bypass=H_ch; series avoids it; all energy balance assertions pass at 0.09% error
- [v0.6 LOF]: LOF IC strategy: reference loop without Flapper/Inertia for KINSOL SS; D(T_open)=0 causes zero Jacobian if Flapper present in SteadyStateProblem
- [v0.6 LOF]: LOF energy balance: max(T_cells)-T_inlet selects correct outlet in both forward flow (T[n]=top) and reversed flow (T[1]=bottom) without direction detection
- [v0.6 LOF-02]: VAL-02 gravity-driven NC: series topology with HX temperature reset creates rho*g*L (~9700 Pa) NC driver, NOT buoyancy delta_rho*g*H (~40 Pa); use gravity-friction stability check (CV < 5%), not buoyancy analytical estimate
- [v0.6 LOF-02]: Channel Dt term reverted: (L/A)*Dt(port_in.mdot) in _channel_base_eqs over-determines parallel 3-way junction systems (28 eq/27 unknowns); standalone Inertia component provides hydraulic inductance for series topology
- [v0.6 LOF-02]: MTK parallel Channel limitation: any Channel with bidirectional instream() at a 3-way junction adds one extra Kirchhoff equation -> over-determined; use series topology or pure Resistor/Gravity for parallel paths

### Pending Todos

None.

### Blockers/Concerns

- VAL-01 (Fourier series validation) is a pre-existing flaky numerical test — not caused by v0.6 changes.

---

## Session Continuity

**Last session:** 2026-03-26T21:17:12.819Z
**Stopped at:** Phase 26 context gathered
**Next action:** `/gsd:plan-phase 20`
**Resume file:** .planning/phases/26-nc-regime-htc-lof-cleanup/26-CONTEXT.md

---

*Last updated: 2026-03-22 — Completed quick task 260322-l7z: Create LOF transient example script with comprehensive plots and analysis*

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260322-l7z | Create LOF transient example script with comprehensive plots and analysis | 2026-03-22 | 52f4e44 | [260322-l7z-create-lof-transient-example-script-with](./quick/260322-l7z-create-lof-transient-example-script-with/) |
