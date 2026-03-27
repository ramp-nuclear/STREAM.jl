# Phase 25: Argument Structure Audit - Discussion Log (Discuss Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the analysis.

**Date:** 2026-03-26
**Phase:** 25-argument-structure-audit
**Mode:** discuss
**Areas analyzed:** Simple single-arg components, Correlation factories, CLAUDE.md rule

## Gray Areas Presented

### Simple Single-Arg Components
| Gray Area | Options Offered | User Choice |
|-----------|----------------|-------------|
| 5 components with 1 physics param | Yes → positional / No → keep keyword | **Yes — go positional** |

Rationale: `@named r = Resistor(1e4)` is short and consistent with PipeGeometry factory pattern. The `@named` macro names the component; the single physics arg doesn't need a label.

### Correlation Factories
| Gray Area | Options Offered | User Choice |
|-----------|----------------|-------------|
| laminar_friction, constant_Nusselt, elenbaas_htc | Typed-single-arg only / All required / Leave as-is | **Typed single-arg → positional** |

Outcome: `laminar_friction(aspect_ratio::Real)` becomes positional. `constant_Nusselt(; Nu=8.235)` and `elenbaas_htc(; b, L, Dh, g=9.81)` stay keyword-only.

### CLAUDE.md Rule
| Gray Area | Options Offered | User Choice |
|-----------|----------------|-------------|
| New rule phrasing | Two-tier rule / Type-dispatch only | **Two-tier rule** |

New rule: positional when (a) type determines behavior or (b) ≤1 physics param with clear role; keyword when multiple same-type args or complex constructor.

## Corrections Made

No corrections — all three recommended options confirmed.

## Prior Decisions Applied (Not Re-asked)

- v0.5: `solve_transient` keyword-only — solvers not in scope for change
- v0.4: `Pump` multiple dispatch pattern — already correct, not touched
- v0.4: `PipeGeometry_rectangular/circular` positional — already correct
- v0.4 migration policy: delete old form, update call sites (no backward-compat shim)
- Composition helpers — already correct mixed pattern
