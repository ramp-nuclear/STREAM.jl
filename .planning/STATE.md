---
gsd_state_version: 1.0
milestone: v0.1
milestone_name: milestone
current_phase: Phase 2 — Components (complete)
current_plan: Plan 03 — Pump/Friction/Gravity Implementation (complete)
status: planning
stopped_at: Completed 02-04-PLAN.md
last_updated: "2026-03-12T02:06:04.671Z"
progress:
  total_phases: 3
  completed_phases: 2
  total_plans: 7
  completed_plans: 7
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

**Current phase:** Phase 2 — Components (complete)
**Current plan:** Plan 04 — API Kwarg Rename (Pump/Gravity) (complete)
**Status:** Ready to plan

**Progress:**
[██████████] 100%
```
Phase 1: Foundation          [3/3 plans complete — Phase 1 DONE]
Phase 2: Components          [3/3 plans complete — Phase 2 DONE]
Phase 3: Integration/Valid.  [ ] Not started

Overall: 2/3 phases complete

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

### Open Questions

- MTK compile time on ~30-equation system — benchmark in Phase 3
- Flow reversal: will ifelse() cause solver convergence issues? Fallback: tanh-smoothing

### Blockers

None.

### Notes

- Developer has limited Julia experience and no prior MTK experience — Claude writes code, developer reviews iteratively
- Python STREAM uses Aggregator+DAE+SUNDIALS IDA; Julia-STREAM replaces this with MTK compose()+connect()+mtkcompile()
- Validation inputs must be identical between Python STREAM and Julia runs

---

## Session Continuity

**Last session:** 2026-03-12T02:06:04.669Z
**Stopped at:** Completed 02-04-PLAN.md
**Next action:** Begin Phase 3 (Integration/Validation) — all four components ready: Channel, Pump, Friction, Gravity. Assemble closed forced-convection loop using compose() + connect() + mtkcompile().

---

*Last updated: 2026-03-12*
