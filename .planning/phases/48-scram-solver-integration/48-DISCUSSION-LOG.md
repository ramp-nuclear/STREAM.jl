# Phase 48: SCRAM Solver Integration — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the analysis.

**Date:** 2026-04-07
**Phase:** 48-scram-solver-integration
**Mode:** discuss (update)
**Areas analyzed:** dPdt callback access, P index lookup strategy

## Prior Context Loaded

- Phase 45 CONTEXT.md — PointKinetics bare component decisions
- Phase 47 CONTEXT.md — Temperature feedback decisions (D-01..D-10)
- `src/components/point_kinetics.jl` — ReactivityController struct, change_state, abort_states confirmed
- `src/solvers.jl:99` — `solve_transient` callbacks kwarg confirmed present
- `src/components/flapper.jl` — SymbolicContinuousCallback pattern (different from DiscreteCallback)
- `Project.toml` — MTK v11, OrdinaryDiffEq 6.109+

## Codebase Findings

| Finding | Impact |
|---------|--------|
| `solve_transient` has `callbacks` kwarg (solvers.jl:99) | SCRAM-03 is already satisfied — no changes needed |
| `DiscreteCallback` not yet used anywhere in codebase | Phase 48 is first use; needs verification at first test |
| `dPdt` is `@observed` — NOT in ODE state vector | Cannot use `variable_index` for `dPdt` (original CONTEXT bug) |
| `abort_states`, `change_state` confirmed in struct | Phase 46 work complete, no changes needed |

## Gray Areas Presented

### Area 1: dPdt in callback (D-03 — bug in original CONTEXT)

| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Original CONTEXT showed `variable_index(ssys, dPdt_sym)` | **Wrong** | `dPdt` is `@observed` in point_kinetics.jl:105; observed vars are not in ODE state vector |

### Area 2: P index lookup strategy (D-05)

| Option | Trade-off |
|--------|-----------|
| `variable_index(ssys, P)` → `u[p_idx]` | Classic DiffEq pattern; faster per-step; variable_index not yet used in codebase |
| `integrator[p_sym]` symbolic indexing | Clean, namespace-agnostic, DiffEq native for MTK; no u index needed |

## Corrections Made

### Area 1: dPdt Fix
- **Original assumption:** `dp_idx = variable_index(ssys, ssys.pk.dPdt)` — use integer index for observed dPdt
- **Correction:** `p_idx = variable_index(ssys, ssys.pk.P)` + `integrator.du[p_idx]` — use ODE derivative of P, which equals dPdt by the PK ODE formulation
- **Reason:** `dPdt` is `@observed` and not in the ODE state vector. `variable_index` only works for ODE state variables. The ODE derivative `du[p_idx]` IS `dPdt` by definition (Dt(P) ~ ...).

### Area 2: P Index Lookup
- **Original assumption:** pre-compute `p_idx = variable_index(ssys, p_sym)`, then `u[p_idx]`
- **User correction:** use `integrator[p_sym]` for P value (symbolic indexing)
- **Combined pattern:** `integrator[p_sym]` for P value + `variable_index(ssys, p_sym)` pre-computed for `du` access (dPdt)
- **Reason:** Symbolic indexing is cleaner and namespace-agnostic. `variable_index` is still needed for `integrator.du` access since `du` is raw array indexing.

### User note on dPdt
> "Yeah we pass it through and right now only have a SCRAM_at_power, but in the future we may have SCRAM_at_dPdt or SCRAM_at_'something' that plays with power and dPdt"
→ dPdt is preserved in the `change_state` call for future extensibility.

## All Other Decisions

Confirmed unchanged from original CONTEXT.md:
- D-01: SCRAM_at_power signature (state machine factory returning new state, not Bool) ✓
- D-04: File placement in point_kinetics.jl ✓
- D-06: solve_transient callbacks kwarg (confirmed in code) ✓
- D-07: abort_states in ReactivityController (confirmed in code) ✓
- D-08: SCRAM input_reactivity patterns ✓
