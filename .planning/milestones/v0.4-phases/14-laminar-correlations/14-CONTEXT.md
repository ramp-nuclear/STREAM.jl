# Phase 14: Laminar Correlations - Context

**Gathered:** 2026-03-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Make HTC and friction correlations pluggable in all three channel variants (Channel, ChannelAndContacts, ChannelHeatFlux). Add `constant_Nusselt`, `laminar_friction`, and `regime_dependent` correlation factories. Extend `PipeGeometry` with `width` and `depth` fields to support aspect-ratio-dependent correlations. Covers PHY-02, PHY-03, PHY-04.

Developing-length laminar, viscosity corrections, natural convection, and CHF correlations are out of scope for this phase.

</domain>

<decisions>
## Implementation Decisions

### Correlation function signatures

- **HTC correlation**: `(Re, Pr) -> Nu` — returns Nusselt number. Surrounding channel code handles `h_tc = Nu * k_water(T) / Dh`. Geometry-independent; MTK-compatible (Re and Pr are symbolic expressions at solve time).
- **Friction correlation**: `(Re) -> f_darcy` — returns Darcy friction factor. Surrounding channel code handles the full Darcy-Weisbach equation. MTK-compatible.
- **Re and Pr are the only solve-time variables** needed across all Phase 14 correlations. Everything else (geometry corrections, configuration) is captured in closures at construction time — mirrors Python STREAM's `partial` pattern.
- Closures for complex correlations (e.g. `laminar_friction(aspect_ratio=0.57)`) capture construction-time scalars; the inner function receives only symbolic Re/Pr.

### Correlation factories to implement

- `dittus_boelter(Re, Pr) = 0.023 * Re^0.8 * Pr^0.4` — named standalone function (currently hardcoded inline)
- `blasius_friction(Re) = 0.3164 * Re^(-0.25)` — named standalone function (currently hardcoded inline)
- `constant_Nusselt(; Nu=8.235)` — factory returning `(Re, Pr) -> Nu`; default 8.235 = uniform-heat-flux parallel plates (Shah & London)
- `laminar_friction(; aspect_ratio)` — factory returning `(Re) -> 64 / (Re * rectangular_laminar_correction(aspect_ratio))`; circular case (aspect_ratio=1.0) reduces to plain 64/Re
- `rectangular_laminar_correction(aspect_ratio)` — scalar precomputed from KAERI formula; exposed as a standalone utility

### regime_dependent

- `regime_dependent(; htc_laminar, htc_turbulent, friction_laminar, friction_turbulent, Re_transition=2300)` — requires all four correlation args (both htc pair and friction pair)
- Returns a **named tuple** `(htc=fn, friction=fn)` where each fn is a closure with `ifelse` switching baked in:
  ```julia
  htc_fn      = (Re, Pr) -> ifelse(Re < Re_transition, htc_lam(Re, Pr), htc_turb(Re, Pr))
  friction_fn = (Re)     -> ifelse(Re < Re_transition, f_lam(Re), f_turb(Re))
  ```
- `ifelse()` switching is already the established project pattern (carry-forward from prior phases)
- User unpacks explicitly: `rd = regime_dependent(...); ChannelAndContacts(htc_correlation=rd.htc, friction_correlation=rd.friction)`

### ChannelAndContacts / channel variant API

- All three channel variants (Channel, ChannelAndContacts, ChannelHeatFlux) get `htc_correlation` and `friction_correlation` kwargs
- **Defaults**: `htc_correlation=dittus_boelter`, `friction_correlation=blasius_friction` — all existing tests pass unchanged
- **`_channel_base_eqs`** is refactored to accept and call `htc_correlation(Re[i], Pr_i)` and `friction_correlation(Re_mean)` instead of hardcoded expressions; ChannelAndContacts and ChannelHeatFlux inherit this for free by passing kwargs through
- **Channel** (which does not use `_channel_base_eqs`) gets the same kwargs updated inline — same logic, same small swap
- Pr is computed inline as `cp_water(T[i]) * mu_water(T[i]) / k_water(T[i])` and passed to the htc closure as a symbolic expression; no new MTK variable needed

### PipeGeometry extension

- Add `width` and `depth` fields to `PipeGeometry` struct (aligning with Python STREAM's `EffectivePipe`)
- `PipeGeometry_rectangular`: `width = max(edge1, edge2)`, `depth = min(edge1, edge2)`
- `PipeGeometry_circular`: `width = D`, `depth = D` (aspect_ratio = 1.0 → k_R = 1.0 → plain 64/Re, correct)
- `aspect_ratio = depth / width` is derived by the user at construction time when building laminar closures:
  ```julia
  geom = PipeGeometry_rectangular(L, edge1, edge2, heated_edge)
  rd = regime_dependent(
    htc_laminar       = constant_Nusselt(Nu=8.235),
    htc_turbulent     = dittus_boelter,
    friction_laminar  = laminar_friction(aspect_ratio = geom.depth / geom.width),
    friction_turbulent = blasius_friction,
    Re_transition     = 2300
  )
  ```
- `width` and `depth` are NOT auto-injected into correlations by the channel component — user always builds closures explicitly

### Claude's Discretion

- Exact Julia module/file organization for correlation functions (new file vs. added to `components.jl`)
- Whether `dittus_boelter` and `blasius_friction` become the default argument values directly or are referenced by name
- Test structure for PHY-04: which Re values to exercise for both laminar and turbulent branches

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets

- `_channel_base_eqs` (`src/components.jl:304`): shared helper called by ChannelAndContacts and ChannelHeatFlux; currently has Dittus-Boelter and Blasius hardcoded; primary refactor target
- `PipeGeometry` struct (`src/components.jl`): add `width` and `depth` fields; factory constructors `PipeGeometry_rectangular` and `PipeGeometry_circular` already exist from Phase 13

### Established Patterns

- `ifelse()` for smooth switching (no hard branches in MTK equations) — already used for flow reversal; same pattern for regime switching
- Sentinel-kwargs dispatch (`Pump(dP_pump=nothing, mdot0=nothing)`) — same pattern as correlation factories returning closures
- `@register_symbolic` for fluid property functions (`rho_water`, `mu_water`, etc.) — correlation functions should be plain Julia math (not `@register_symbolic`) so MTK can trace them symbolically

### Integration Points

- `_channel_base_eqs` call sites in ChannelAndContacts (`src/components.jl:388`) and ChannelHeatFlux (`src/components.jl:459`) — add `htc_correlation` and `friction_correlation` kwargs to these calls
- Channel's inline correlation equations (around `src/components.jl:144-152`) — replace hardcoded expressions with `htc_corr(Re[i], Pr_i)` and `friction_corr(Re_mean)`
- All existing VAL-01/02/03 and PHY tests use default constructor — no changes needed if defaults are preserved

</code_context>

<specifics>
## Specific Ideas

- Python STREAM's `EffectivePipe.rectangular()` sets `width=max(edge1,edge2)`, `depth=min(edge1,edge2)` — match this exactly
- Python STREAM's `rectangular_laminar_correction(aspect_ratio)` uses the KAERI formula; port the same formula
- `constant_Nusselt` default Nu=8.235 matches Python STREAM's `FIXED_FLUXES` constant (uniform heat flux, parallel plates, Shah & London)
- Correlation factories should read naturally as Julia keyword constructors: `laminar_friction(aspect_ratio=geom.depth/geom.width)`, `constant_Nusselt(Nu=8.235)`, `regime_dependent(Re_transition=2300, ...)`

</specifics>

<deferred>
## Deferred Ideas

- Developing-length laminar HTC (`developing_laminar_h_spl` equivalent) — needs `develop_length` from cell position; complex; no Phase 14 validation target
- Viscosity correction for friction (`viscosity_correction(heat_wet_ratio, mu_ratio)`) — needs `T_wall` at solve time; not uniformly available in `_channel_base_eqs`; defer to future phase
- Natural convection (`Elenbaas_h_spl`) — out of scope for v0.4
- `maximal_h_spl` equivalent (take max of multiple correlations) — no current validation target
- `turbulent_friction` (Colebrook-White approximation, more accurate than Blasius) — Blasius is sufficient for Phase 14 scope

</deferred>

---

*Phase: 14-laminar-correlations*
*Context gathered: 2026-03-15*
