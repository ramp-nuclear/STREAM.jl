# Phase 30: HTC & Friction Completions - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the Q&A.

**Date:** 2026-04-01
**Phase:** 30-htc-friction-completions
**Mode:** discuss
**Areas discussed:** HTC-02/03 Nusselt basis, File placement, turbulent_friction edge case

## Gray Areas Presented

| Area | Description |
|------|-------------|
| HTC-02/03 Nusselt basis | Requirements say HTC-02 uses Marco-Han (4-sided). Python STREAM uses two_sided_heating_nusselt (2-sided, Kakac case 3). Which is correct? |
| File placement | correlations.jl at 274 lines. Adding 6 functions crosses ~300-line CLAUDE.md split threshold. Split now or defer? |
| turbulent_friction edge case | Python STREAM returns 0.0 for very low Re (nan_to_num). Explicit Julia guard or document valid range? |

## Q&A Log

### HTC-02/03 Nusselt basis

**Q:** For fully_developed_laminar_h_spl (HTC-02): which Nusselt polynomial?
- Options: two_sided_heating_nusselt (Recommended) | Marco_Han_Nusselt (as per requirements)
- **Selected:** two_sided_heating_nusselt

**Q:** two_sided_heating_nusselt — export or private helper?
- Options: Private helper only (Recommended) | Export it
- **Selected:** Private helper only

### File placement

**Q:** Split correlations.jl now or defer?
- Options: Split now (Recommended) | Stay in correlations.jl
- **Selected:** Split now

### turbulent_friction edge case

**Q:** Low-Re behavior for turbulent_friction?
- Options: Match Python STREAM: return 0.0 (Recommended) | Let formula run, document range
- **Selected:** Match Python STREAM: return 0.0

## Corrections Applied

- Requirements state HTC-02 uses "Marco-Han" — **user corrected to `two_sided_heating_nusselt`** (physically correct for 2-sided MTR channel heating; Marco-Han is 4-sided).

## No corrections on

- File split decision — confirmed recommended approach
- turbulent_friction guard — confirmed recommended approach
