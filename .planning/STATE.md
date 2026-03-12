---
gsd_state_version: 1.0
milestone: v0.1
milestone_name: milestone
current_phase: Phase 3 — Integration and Validation (complete)
current_plan: Plan 03 — Validation (complete)
status: complete
stopped_at: Completed 03-03-PLAN.md
last_updated: "2026-03-12T13:30:00.000Z"
progress:
  total_phases: 3
  completed_phases: 3
  total_plans: 10
  completed_plans: 10
  percent: 100
---

# STATE: STREAM.jl

*Project memory — updated at the start and end of every session*

---

## Project Reference

**Core value:** A working forced-convection loop in MTK that matches Python STREAM's steady-state and transient results, proving the Julia architecture is sound before any large-scale porting begins.

**Milestone:** v0.1 — single forced-convection loop proof-of-concept

**Python STREAM reference:** ~/projects/STREAM

---

## Current Position

**Current phase:** Phase 3 — Integration and Validation (complete)
**Current plan:** Plan 03 — Validation (complete)
**Status:** Complete

**Progress:**
[██████████] 100%
```
Phase 1: Foundation          [3/3 plans complete — Phase 1 DONE]
Phase 2: Components          [4/4 plans complete — Phase 2 DONE]
Phase 3: Integration/Valid.  [3/3 plans complete — Phase 3 DONE]

Overall: 3/3 phases complete — MILESTONE v0.1 ACHIEVED

---

## Performance Metrics

| Metric | Value |
|--------|-------|
| Phases total | 3 |
| Phases complete | 0 |
| Requirements mapped | 15/15 |
| Plans written | 0 |
| Plans complete | 0 |

---
| Phase 01-foundation P01 | 16min | 2 tasks | 6 files |
| Phase 01-foundation P03 | 1min | 1 tasks | 0 files |
| Phase 01-foundation P02 | 5 | 1 tasks | 1 files |
| Phase 02-components P01 | 2min | 2 tasks | 3 files |
| Phase 02-components P02 | 6 | 2 tasks | 2 files |
| Phase 02-components P03 | 3min | 2 tasks | 2 files |
| Phase 02-components P04 | 3min | 2 tasks | 2 files |
| Phase 03-integration-and-validation P01 | 68min | 2 tasks | 4 files |
| Phase 03-integration-and-validation P02 | 18 | 1 tasks | 4 files |
| Phase 03-integration-and-validation P03 | 15min | 2 tasks | 2 files |

## Accumulated Context

### Key Decisions Made

| Decision | Rationale |
|----------|-----------|
| MTK from day one | Avoid Python-style architecture; hit learning curve on 30 equations not 300 |
| Fluid properties via @register_symbolic | Define once globally, callable anywhere, ForwardDiff-compatible |
| Flow reversal: start with ifelse() | Simplest; migrate to tanh-smoothing if Jacobian issues arise |
| Single closed loop as v0.1 | Validates architecture before large-scale porting |
| MTK v11 @connector uses function syntax | DSL block syntax requires SciCompDSL.jl — use `@connector function Name(; name)` instead |
| VariableConnectType accessed via Symbolics.getmetadata | Constructor API does not exist in MTK v11; use `Symbolics.getmetadata(var, ModelingToolkitBase.VariableConnectType, nothing)` |
| Across variables have nothing for VariableConnectType | Not Equality — check for `nothing` to identify across variables |
| Symbolics compat must include v7 | MTK v11 requires Symbolics v7, not just 5-6 |
| `function Channel end` required to avoid Base.Channel conflict | Julia 1.12 requires explicit forward declaration to create new generic function with same name as Base type |
| Explicit `import STREAM: Channel` in test files | When STREAM exports Channel alongside Base, ambiguity must be resolved with explicit module import |
| Rename kwarg D to Dh inside Channel function | Keyword arg `D` (Float64) shadows Differential(t) operator; explicit alias prevents Float64-callable MethodError |
| mtkcompile(ch; fully_determined=false) for isolated component tests | Unconnected ports leave thermal.T and port_in.P unconstrained; fully_determined=false is the correct MTK approach for Phase 2 isolation testing |
| [] as vars argument to System() for algebraic-only components | Pump and Gravity have no local state variables; empty vector avoids MTK variable tracking overhead |
| A_grav parameter retained in Gravity even though unused in pressure equation | API consistency with future velocity observable; mirrors Friction's A_f pattern |
| Constructor kwargs renamed to match MTK parameter names (dP->dP_pump, A->A_grav) | Eliminates UndefKeywordError in consumer code; public API now identical to internal @parameters names |
| TempBC component breaks circular instream() T dependency | MTK instream() resolves to connected stream T — in closed loop gives T=T_wall trivial equilibrium; TempBC injects fixed T_inlet as proper stream variable |
| ch.thermal.T ~ T_wall only (no Q_flow constraint) | Setting both ThermalPort vars overspecifies; only T needs pinning — HTC equation determines Q_flow |
| ch.port_in.T ~ T_inlet needed alongside TempBC | TempBC alone leaves residual circular T dependency; both constraints together give fully determined 12-equation system |
| KINSOL default globalization (no LineSearch) works with good initial guess | LineSearch finds trivial T=T_wall solution; default Newton with physics-based mdot_guess=0.490 kg/s converges to physical solution |
| warn_initialize_determined=false for closed-loop SteadyStateProblem | MTK init system sees 22 eqs for 1 unknown (mdot) due to connector defaults; suppressing warning uses least-squares init correctly |
| mtkcompile time ~12s for 12-equation closed loop | ANSWERED: Phase 3 benchmark; acceptable for interactive use, no assertion needed |
| T_wall stepped in transient (not Q_wall) | Channel energy balance uses thermal.T via HTC; Q_flow is only an observable — T_wall change is physically equivalent to Q_wall change |
| Rodas5P for transient DAE simulation | IDA needs DAEProblem+du0; CVODE_BDF cannot use mass matrices; Rodas5P (stiff implicit RK) handles mass-matrix ODEProblem from mtkcompile |
| SciMLBase.NoInit for transient initialization | MTK init sees 29 eqs for 1 unknown (overdetermined); NoInit bypasses and trusts physics-based initial guess |
| build_loop uses Pump→TempBC→Channel (no Friction) | Channel's Darcy-Weisbach term handles friction internally; separate Friction component created double-counting vs Python STREAM ChannelAndContacts |
| Python STREAM FlowGraph+ChannelAndContacts for VAL-01 | ChannelAndContacts computes Dittus-Boelter HTC and friction self-consistently; HeatExchanger(outlet=T_inlet) is the TempBC equivalent |
| T_outlet_ref=327.7894 K, mdot_ref=0.609289 kg/s hardcoded | Reference values from single Python STREAM run; hardcoded for reproducibility without requiring Python STREAM in test environment |

### Open Questions

- Flow reversal: will ifelse() cause solver convergence issues? Fallback: tanh-smoothing (still unanswered)

### Blockers

None.

### Notes

- Developer has limited Julia experience and no prior MTK experience — Claude writes code, developer reviews iteratively
- Python STREAM uses Aggregator+DAE+SUNDIALS IDA; Julia-STREAM replaces this with MTK compose()+connect()+mtkcompile()
- Validation inputs must be identical between Python STREAM and Julia runs

---

## Session Continuity

**Last session:** 2026-03-12T13:30:00.000Z
**Stopped at:** Completed 03-03-PLAN.md
**Next action:** Milestone v0.1 complete. All 54 tests pass. Julia-STREAM validates within 1% of Python STREAM reference values.

---

*Last updated: 2026-03-12*
