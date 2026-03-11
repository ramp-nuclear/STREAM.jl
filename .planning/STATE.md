# STATE: STREAM.jl

*Project memory — updated at the start and end of every session*

---

## Project Reference

**Core value:** A working forced-convection loop in MTK that matches Python STREAM's steady-state and transient results, proving the Julia architecture is sound before any large-scale porting begins.

**Milestone:** v0.1 — single forced-convection loop proof-of-concept

**Python STREAM reference:** ~/projects/STREAM

---

## Current Position

**Current phase:** Phase 1 — Foundation
**Current plan:** None (planning not yet started)
**Status:** Not started

**Progress:**
```
Phase 1: Foundation          [ ] Not started
Phase 2: Components          [ ] Not started
Phase 3: Integration/Valid.  [ ] Not started

Overall: 0/3 phases complete
```

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

## Accumulated Context

### Key Decisions Made

| Decision | Rationale |
|----------|-----------|
| MTK from day one | Avoid Python-style architecture; hit learning curve on 30 equations not 300 |
| Fluid properties via @register_symbolic | Define once globally, callable anywhere, ForwardDiff-compatible |
| Flow reversal: start with ifelse() | Simplest; migrate to tanh-smoothing if Jacobian issues arise |
| Single closed loop as v0.1 | Validates architecture before large-scale porting |

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

**Last session:** 2026-03-12 — Project initialized, requirements defined, roadmap created
**Next action:** Run `/gsd:plan-phase 1` to plan Phase 1: Foundation

---

*Last updated: 2026-03-12*
