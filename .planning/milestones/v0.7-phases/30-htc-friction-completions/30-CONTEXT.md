# Phase 30: HTC & Friction Completions - Context

**Gathered:** 2026-04-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Complete the HTC and friction correlation library with the 6 remaining functions needed for full physical accuracy: Marco_Han_Nusselt (HTC-01), fully_developed_laminar_h_spl factory (HTC-02), developing_laminar_h_spl factory (HTC-03), maximal_htc combinator (HTC-04), turbulent_friction Colebrook-White (FRIC-01), and viscosity_correction (FRIC-02).

Companion to Phase 29 (threshold analysis). Does NOT modify existing components or correlations — adds new functions only.

</domain>

<decisions>
## Implementation Decisions

### HTC-02 and HTC-03 Nusselt polynomial
- **D-01:** `fully_developed_laminar_h_spl` (HTC-02) uses `_two_sided_heating_nusselt(aspect_ratio)` — the Kakac Table 44 case 3 polynomial for 2-sided rectangular duct heating. This is the physically correct choice for MTR fuel channels (heated on two opposite walls), and matches Python STREAM behavior. It is NOT Marco-Han (which is 4-sided uniform heat flux).
- **D-02:** `_two_sided_heating_nusselt` is a **private helper** (underscore-prefixed, not exported). Used internally by both HTC-02 and HTC-03. Formula: `8.235 * (1 - 1.4122*ar + 2.3473*ar^2 - 2.8983*ar^3 + 2.0629*ar^4 - 0.6077*ar^5)`
- **D-03:** `developing_laminar_h_spl` (HTC-03) applies `_two_sided_heating_nusselt(aspect_ratio, nudev)` as a finite-size correction to the Shah & London piecewise Nu coefficient. The x_star formula from Python STREAM includes the aspect-ratio-dependent correction factor: `x_star = develop_length / Dh / Re / Pr / (6 - 5 * exp(-0.75 * aspect_ratio / 0.3257))`.
- **D-04:** Requirements incorrectly state HTC-02 uses "Marco-Han." The correct function is two-sided heating (user decision). `Marco_Han_Nusselt` (HTC-01) is still implemented exactly as specified — 4-sided uniform heat flux polynomial.

### File placement (split correlations.jl)
- **D-05:** Split `src/physical_models/correlations.jl` into two files during this phase:
  - `src/physical_models/htc/correlations.jl` — all HTC functions (existing: `dittus_boelter`, `constant_Nusselt`, `rectangular_laminar_correction`, `laminar_friction`, `regime_dependent`, `elenbaas_nusselt`, `elenbaas_htc`, `_bergles_rohsenow_dT_ONB`; new: `Marco_Han_Nusselt`, `fully_developed_laminar_h_spl`, `developing_laminar_h_spl`, `maximal_htc`, `_two_sided_heating_nusselt`)
  - `src/physical_models/friction/correlations.jl` — all friction functions (existing: `blasius_friction`, `laminar_friction`; new: `turbulent_friction`, `viscosity_correction`)
- **D-06:** Update `src/STREAM.jl` includes accordingly: replace single `include("physical_models/correlations.jl")` with two targeted includes. All exports remain in `src/STREAM.jl` only.
- **D-07:** The existing `laminar_friction(aspect_ratio::Real)` factory belongs in friction/ (it returns a friction closure). `rectangular_laminar_correction` is a friction geometry helper — also goes to friction/.

### turbulent_friction edge case
- **D-08:** `turbulent_friction(Re, epsilon=0)` guards `Re <= 0 → 0.0` before the Colebrook-White formula. Matches Python STREAM's `nan_to_num` behavior. Prevents NaN propagation. Guard condition: `Re <= 0 ? 0.0 : formula`.

### Claude's Discretion
- Exact piecewise formula for `_nusselt_coefficient_developing` — match Python STREAM exactly: `x ≤ 2e-4: 1.49*x^(-1/3)`, `x ≤ 1e-3: 1.49*x^(-1/3) - 0.4`, else `8.235 + 8.68*exp(-164x)*(1e3*x)^-0.506`
- `maximal_htc(correlations...)` variadic signature: returns `(Re, Pr, T_bulk, T_wall) -> max(c1(...), c2(...), ...)` using broadcasting
- Test file: `test/test_correlations.jl` — add new test cases to the existing file (not a new file)
- How to handle `_nusselt_coefficient_developing` — keep private (underscore), not exported

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` §HTC-01..04, §FRIC-01..02 — exact function signatures, input/output, success criteria
- Note: Requirements say HTC-02 uses "Marco-Han" — **this is incorrect per D-01**. Use `_two_sided_heating_nusselt` instead.

### Python STREAM reference implementations
- `/home/itay/projects/STREAM/stream/physical_models/heat_transfer_coefficient/laminar.py` — `Marco_Han_Nusselt`, `two_sided_heating_nusselt`, `_nusselt_coefficient_developing`, `fully_developed_laminar_h_spl`, `developing_laminar_h_spl` exact formulas
- `/home/itay/projects/STREAM/stream/physical_models/pressure_drop/friction.py` — `turbulent_friction` (Colebrook-White), `viscosity_correction` exact formulas
- `/home/itay/projects/STREAM/stream/physical_models/heat_transfer_coefficient/single_phase.py` — `maximal_h_spl` pattern (use `reduce(max, ...)` → Julia: broadcast `max.()`)

### Existing code to migrate/extend
- `src/physical_models/correlations.jl` — source of all existing functions; this file is REPLACED by the split in D-05
- `src/STREAM.jl` — update includes and keep all exports here

### Prior phase context
- `.planning/phases/29-threshold-analysis/29-CONTEXT.md` — references `_bergles_rohsenow_dT_ONB` from correlations.jl; after split, this goes to htc/correlations.jl; no behavior change

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `rectangular_laminar_correction(aspect_ratio)` in current `correlations.jl` — already exists; belongs in friction/ after split
- `_bergles_rohsenow_dT_ONB(P_Pa, q_spl)` — private helper already in correlations.jl; migrates to htc/ after split
- Pattern for factories: `constant_Nusselt`, `laminar_friction`, `elenbaas_htc` — all use the same "capture params at construction, return closure" pattern; HTC-02/03 and maximal_htc follow this

### Established Patterns
- Correlation closures use 4-arg interface: `(Re, Pr, T_bulk, T_wall) -> Nu` for HTC; `(Re) -> f` for friction
- Private helpers prefixed with `_`, not exported (per CLAUDE.md)
- No `@register_symbolic` in correlations — plain arithmetic only
- All exports declared in `src/STREAM.jl` only

### Integration Points
- `src/STREAM.jl`: replace `include("physical_models/correlations.jl")` with `include("physical_models/htc/correlations.jl")` and `include("physical_models/friction/correlations.jl")`; add new exports: `Marco_Han_Nusselt`, `fully_developed_laminar_h_spl`, `developing_laminar_h_spl`, `maximal_htc`, `turbulent_friction`, `viscosity_correction`
- `test/test_correlations.jl` — extend existing file with HTC-01..04 and FRIC-01..02 test cases

</code_context>

<specifics>
## Specific Ideas

- Python STREAM uses `nan_to_num` for `turbulent_friction` — Julia equivalent is `Re <= 0 ? 0.0 : formula` guard (D-08).
- `_nusselt_coefficient_developing` private helper used only by HTC-03 factory. No need to expose.
- `two_sided_heating_nusselt` is private `_two_sided_heating_nusselt` — not the same as `Marco_Han_Nusselt`. Both start at 8.235 at ar=0 but diverge significantly (e.g., at ar=0.2: Marco-Han gives ~5.99, two-sided gives ~6.56).

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 30-htc-friction-completions*
*Context gathered: 2026-04-01*
