# Phase 35: Parameter Editing - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the Q&A.

**Date:** 2026-04-02
**Phase:** 35-parameter-editing
**Mode:** discuss

## Gray Areas Presented

| Area | Selected? |
|------|-----------|
| PipeGeometry picker | Yes |
| Function-type params | Yes |
| Validation timing | Yes |
| Sidebar deselect behavior | Yes |

## Discussion

### PipeGeometry Picker
- **Q:** How should the PipeGeometry picker work?
- **A:** Segmented control (`Circular | Rectangular`) — conditional fields below
- **Q:** When user switches type, what happens to entered dimension values?
- **A:** Clear them — prevents nonsensical values surviving a type switch

### Function-Type Parameters
- **Q (initial, rejected):** Show as read-only badge / hide / dropdown of known names?
- **User pushback:** "Why wouldn't we obviously provide the user with the available options to select from?"
- **Corrected framing:** The real issue is factory correlations (regime_dependent, elenbaas_htc, maximal_htc) require nested sub-parameters — not a problem with showing a dropdown
- **User follow-up:** "Can we not handle this properly? Show sub-parameters when a factory is selected, hide them when a simple closure is selected. Is this plausible?"
- **Claude analysis:** Technically yes — standard React conditional rendering. Main work is registry schema extension (add `options` field to Function-type params) and code gen contract for nested factory calls. Recursion depth cap needed (factories within factories → cap at 1 level).
- **Decision:** Gray out factory correlations in Phase 35 with "coming soon" tooltip. Phase 35.1 activates them.
- **Phase 35.1 added to ROADMAP.md** with full design notes from this conversation.

### Validation Timing
- **Q:** On-blur, on-change, or hybrid?
- **A:** On-blur

### Sidebar Deselect Behavior
- **Q:** Clear to placeholder or keep last selection?
- **A:** Clear to placeholder

## Corrections Made

None — all areas confirmed as discussed.

## Phase 35.1 Notes (documented during this session)

Everything captured in ROADMAP.md §Phase 35.1. Key points:
- Registry needs `options` field on Function-type parameters
- Each option: `id` (Julia function name), `label`, `kind` ("simple" | "factory"), and for factory: `sub_parameters[]`
- Recursion cap: factory sub-dropdowns only show simple closures
- Code gen: simple closure → bare identifier; factory → `fn(arg=val, ...)` call
- Known factories: `regime_dependent(htc_forced, htc_natural, threshold)`, `elenbaas_htc(b, L, Dh, g)`, `maximal_htc(htc1, htc2)`
- Known simple: `dittus_boelter`, `constant_Nusselt`, `blasius_friction`, `laminar_friction`
