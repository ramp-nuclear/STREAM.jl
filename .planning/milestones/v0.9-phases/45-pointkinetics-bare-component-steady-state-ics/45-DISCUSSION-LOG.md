# Phase 45: PointKinetics Bare Component & Steady-State ICs - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the Q&A.

**Date:** 2026-04-04
**Phase:** 45-pointkinetics-bare-component-steady-state-ics
**Mode:** discuss
**Areas analyzed:** Delayed group parameters, Default nuclear data, Diagnostic observables

## Assumptions Presented

Prior to discussion, the following were pre-determined from codebase/prior context (not discussed):
- New file `src/components/point_kinetics.jl`
- Keyword-only constructor (CLAUDE.md rule)
- No Unicode variable names (feedback memory)
- Export from `STREAM.jl` only
- Test file `test/test_point_kinetics.jl`

## Q&A Log

### Delayed Group Parameter Representation
- **Question:** How to encode the 6 beta_k and lambda_k arrays as MTK parameters?
- **Options presented:**
  - Constructor takes Julia arrays, generates 6 scalar MTK params internally *(Recommended)*
  - MTK array parameters: `@parameters beta[1:6], lambda[1:6]`
  - Caller passes 12 individual keyword args (beta_1..beta_6, lambda_1..lambda_6)
- **Selected:** Constructor takes Julia arrays, generates 6 scalar MTK params internally

### Default Nuclear Data
- **Question:** Embed U-235 defaults or require explicit kwargs?
- **Options presented:**
  - Embed U-235 defaults (Lambda, beta_k, lambda_k from Python STREAM) *(Recommended)*
  - No defaults — always required
- **Selected:** Embed U-235 defaults

### Diagnostic Observables
- **Question:** Which quantities should be @observed?
- **Options presented:** beta_total, dPdt, None (bare only)
- **Selected:** beta_total + dPdt
- **User note:** "Everything that can be seen in Python STREAM should be provided here too if possible" → added `reactivity` as third observable to match Python STREAM `save()` output

## Corrections Made

None — all recommended options confirmed.
