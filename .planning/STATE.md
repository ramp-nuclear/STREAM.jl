---
gsd_state_version: 1.0
milestone: v0.2
milestone_name: Component & Network Expansion
current_phase: Not started
current_plan: —
status: Defining requirements
stopped_at: —
last_updated: "2026-03-13"
progress:
  total_phases: 0
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# STATE: STREAM.jl

*Project memory — updated at the start and end of every session*

---

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-13)

**Core value:** A Julia MTK-based thermal-hydraulics library that matches Python STREAM results, proving the architecture is sound before large-scale porting begins.
**Current focus:** Planning next milestone (v0.2)
**Python STREAM reference:** ~/projects/STREAM

---

## Current Position

Phase: Not started (defining requirements)
Plan: —
Status: Defining requirements
Last activity: 2026-03-13 — Milestone v0.2 started

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
| Phase 04-tech-debt-cleanup P01 | 4min | 3 tasks | 7 files |
| Phase 05-nyquist-validation P01 | 2min | 3 tasks | 3 files |

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
| Gravity BUG-01 fixed: @parameters H = H (single param, no A_grav) | MTK symbolic H shadows Julia Float64 kwarg in equation scope — param is now modifiable via setp post-compilation |
| Channel/Friction param renames (L_ch→L, A_ch→A, L_f→L, A_f→A) | Equation bodies use Julia locals (safe); MTK symbolic paths now match Python STREAM convention |
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

**Last session:** 2026-03-12T22:25:17.319Z
**Stopped at:** Completed 05-nyquist-validation-01-PLAN.md
**Next action:** v0.1 milestone archived. Run `/gsd:new-milestone` to plan v0.2.

---

*Last updated: 2026-03-13 — v0.1 milestone archived*
