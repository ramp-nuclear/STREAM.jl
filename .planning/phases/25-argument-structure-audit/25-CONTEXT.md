# Phase 25: Argument Structure Audit - Context

**Gathered:** 2026-03-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Sweep all exported functions and component constructors; replace keyword-only signatures with positional arguments + multiple dispatch wherever it improves clarity or enables type-based dispatch. Update CLAUDE.md with a new canonical rule. No new features or behavior changes — this is a pure API consistency pass.
</domain>

<decisions>
## Implementation Decisions

### Simple Single-Parameter Components → Positional

- **D-01:** The following 5 components get positional physics parameters:
  - `Resistor(R; name)` — replaces `Resistor(; name, R)`
  - `Gravity(H; name)` — replaces `Gravity(; name, H)`
  - `Inertia(L_over_A; name)` — replaces `Inertia(; name, L_over_A)`
  - `HeatExchanger(T_bc; name)` — replaces `HeatExchanger(; name, T_bc)`
  - `ConstantTemperature(T; name)` — replaces `ConstantTemperature(; name, T)`
- **D-02:** The `name` kwarg stays keyword-only (always provided by `@named` macro — this is not negotiable).
- **D-03:** All call sites in `test/` and `src/examples.jl` are updated. No backward-compat shim. Same migration policy as v0.4 PipeGeometry (MethodError forces migration).

### Correlation Factories — Typed Single-Arg → Positional

- **D-04:** `laminar_friction(aspect_ratio::Real)` becomes positional (single typed required arg, role is unambiguous).
- **D-05:** `constant_Nusselt(; Nu=8.235)` stays keyword-only (has a default value; `Nu=` label is informative at call site).
- **D-06:** `elenbaas_htc(; b, L, Dh, g=9.81)` stays keyword-only (4 args all `Float64`, labeling prevents order confusion).
- **D-07:** `regime_dependent(; ...)` stays keyword-only (complex multi-arg factory with many optionals).

### Already Correct — No Changes

- **D-08:** `Pump(dP_pump::Real; name)` / `Pump(dP_pump::Any; name)` / `Pump(; name, mdot0)` — multiple dispatch pattern is already correct.
- **D-09:** Dimensionless utilities (`Re`, `Re_vel`, `Gr`, `Ra`, `Pe`, `Pr`, `Nu`) — all already positional ✓
- **D-10:** `dittus_boelter(Re, Pr, args...)`, `blasius_friction(Re)`, `rectangular_laminar_correction(aspect_ratio)` — already positional ✓
- **D-11:** `PipeGeometry_rectangular`, `PipeGeometry_circular` — already positional ✓
- **D-12:** Composition helpers (`symmetric_plate`, `plate`, `one_sided_connection`, `compose_systems`) — already use positional args + keyword `name` ✓
- **D-13:** `solve_steady`, `solve_transient`, `steady_state_guess` — stay keyword-only (v0.5 decision; `solve_transient(ssys, op, t; callbacks=nothing)` has positional required + keyword optional, which is correct).
- **D-14:** Complex multi-arg constructors (`Channel`, `ChannelAndContacts`, `ChannelHeatFlux`, `HeatDiffusion`, `Flapper`, `Friction`) — stay keyword-only. Multiple args of same type (Float64) where labeling prevents order bugs.

### CLAUDE.md Rule Update

- **D-15:** Replace "All component constructor arguments are keyword-only" with a two-tier rule:
  - **Positional when:** (a) argument type determines behavior, enabling multiple dispatch (e.g., `Real` vs `Function`); OR (b) constructor/function has ≤1 physics parameter and its role is unambiguous from the function name.
  - **Keyword when:** multiple arguments of the same type (labeling prevents order bugs), OR complex constructors with many parameters where self-documentation outweighs brevity.
  - The `name` kwarg is always keyword-only (provided by `@named` macro).

### Claude's Discretion

- Exact order of keyword vs positional in updated signatures (but `name` stays keyword-always)
- Whether to update docstrings to reflect new signatures
- Internal `_channel_base_eqs`, `_diffusion_eqs` — these are `_`-prefixed helpers; apply positional where natural (SC#2), but these functions are not exported
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Current signatures to change
- `src/components/resistors.jl` — `Resistor`, `Gravity` current keyword-only signatures
- `src/components/misc.jl` — `Inertia`, `HeatExchanger`, `ConstantTemperature` current signatures
- `src/physical_models/correlations.jl` — `laminar_friction` current keyword signature
- `src/STREAM.jl` — export list (no changes expected, but verify)

### Test call sites to update
- `test/test_misc.jl` — `Inertia(L_over_A=...)`, `Resistor(R=...)`, `HeatExchanger(T_bc=...)` calls
- `test/test_resistors.jl` — `Resistor(R=...)`, `Gravity(H=...)` calls
- `test/test_solvers.jl` — any component constructor calls
- `test/test_composition.jl` — any component constructor calls
- `src/examples.jl` — all `build_loop*` functions use these components

### Rule to update
- `CLAUDE.md` §"Component authoring conventions" — the keyword-only rule

No external specs — requirements are fully captured in decisions above.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Pump` multiple dispatch pattern (`src/components/pump.jl:42-56`) — the model for type-dispatch: `Pump(x::Real; name)` / `Pump(x::Any; name)` / `Pump(; name, mdot0)`. Phase 25 changes do NOT touch this.
- `@named` macro convention — `name` kwarg is always injected by `@named`, never passed manually. All updated signatures must keep `name` as keyword.

### Established Patterns
- v0.4 migration precedent: `PipeGeometry_rectangular/circular` replaced sentinel-kwarg constructor with positional factory; old form deleted; MethodError forced migration. Phase 25 follows the same policy (no shim, update call sites).
- Composition helpers already show the correct mixed pattern: `symmetric_plate(cac, fuel; name::Symbol)` — positional data args + keyword `name`.

### Integration Points
- Every `build_loop*` function in `src/examples.jl` constructs components and will need call site updates.
- `test/test_misc.jl`, `test/test_resistors.jl`, `test/test_solvers.jl`, `test/test_composition.jl` — likely contain most call sites.
- Grep `Resistor(\|Gravity(\|Inertia(\|HeatExchanger(\|ConstantTemperature(\|laminar_friction(` across `src/` and `test/` to find all call sites before changing signatures.
</code_context>

<specifics>
## Specific Ideas

- "Same migration policy as v0.4 PipeGeometry" — delete old form, update call sites, MethodError forces users to migrate.
- The `name` kwarg is inviolable: it is ALWAYS provided by the `@named` macro and NEVER changes to positional.
</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.
</deferred>

---

*Phase: 25-argument-structure-audit*
*Context gathered: 2026-03-26*
