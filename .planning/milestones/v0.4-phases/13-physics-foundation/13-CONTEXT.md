# Phase 13: Physics Foundation - Context

**Gathered:** 2026-03-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Make PipeGeometry self-computing (Dh derived from geometry, not caller-provided) and add fixed-flow Pump mode. Covers PHY-01 and PHY-05. Laminar/turbulent correlations (PHY-02/03/04) are Phase 14.

</domain>

<decisions>
## Implementation Decisions

### PipeGeometry struct — full alignment with Python EffectivePipe

- Store `heated_perimeter`, `wet_perimeter`, `area`, `heated_parts`, and `Dh` (computed once: `4*area/wet_perimeter`) as struct fields
- `L` stays as a field
- `Dh` is NOT caller-provided — it is always derived from `wet_perimeter` and `area`
- The old struct had `Dh` as a raw caller-provided value; this is the fix

### PipeGeometry factory constructors

- Add `PipeGeometry.rectangular(L, edge1, edge2, heated_edge; one_sided=nothing)`:
  - `area = edge1 * edge2`
  - `wet_perimeter = 2*(edge1 + edge2)`
  - `Dh = 4*area / wet_perimeter`
  - `heated_parts`: `one_sided=nothing` → `(heated_edge, heated_edge)`, `one_sided=:left` → `(heated_edge, 0.0)`, `one_sided=:right` → `(0.0, heated_edge)`
  - `heated_perimeter`: `2*heated_edge` if two-sided, `heated_edge` if one-sided
- Add `PipeGeometry.circular(L, D)`:
  - Same as current circular path: `area=π*D²/4`, `wet_perimeter=π*D`, `heated_perimeter=π*D`, `Dh=D`
- Note: Julia can't have classmethods on a struct. Factory constructors will be standalone functions named `PipeGeometry_rectangular` / `PipeGeometry_circular` OR use a submodule trick. Planner decides the exact Julia idiom — the semantics above are fixed.
- Old sentinel-kwargs constructor (`PipeGeometry(; L, D=nothing, Dh=nothing, A=nothing, y=nothing)`) is **deleted**

### Call site migration

- All ~20 existing test/source uses of `PipeGeometry(; L, D=...)` → `PipeGeometry.circular(L, D)` (or equivalent)
- All uses of `PipeGeometry(; L, Dh, A, y)` → `PipeGeometry.rectangular(L, edge1, edge2, heated_edge)` with correct physical dims
- No backward-compatibility shims — clean break since Dh changes anyway

### MTR reference constant update

- After Dh changes (from hardcoded `0.01` to the correct ~2.2 mm for MTR geometry), existing VAL-01/02/03-style constants will shift
- Strategy: regenerate reference constants from Python STREAM with correct MTR geometry (matching `edge1`, `edge2`, `heated_edge`) and hardcode updated values in Julia tests
- Same approach used in v0.3: run Python STREAM, capture T_out and mdot, hardcode in Julia with rtol=1%

### Pump dual-mode

- `Pump(; name, dP_pump=nothing, mdot0=nothing)` — single function, sentinel dispatch
- Fixed-pressure mode (`dP_pump !== nothing`): existing behavior unchanged
- Fixed-flow mode (`mdot0 !== nothing`): adds `port_in.mdot ~ mdot0` as the only constraint; does NOT add a pressure anchor — caller is responsible
- Error if both or neither provided
- Test assertion: after solving, `sol[pump.port_in.mdot] ≈ mdot0` (rtol=1e-4); loop must include a separate pressure anchor

### Claude's Discretion

- Exact Julia idiom for factory constructors (submodule, standalone functions, or inner constructors)
- Whether to store `heated_diameter` as a field (Python does; may not be needed in v0.4 since all channel code uses `hydraulic_diameter` for Re/Nu/dP)
- `width` and `depth` fields from Python EffectivePipe — omit unless needed (CHF correlations are out of scope)

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets

- `PipeGeometry` struct (`src/components.jl:31`): current inner struct; to be replaced — keep same name
- `_channel_base_eqs` helper (`src/components.jl:253`): uses `Dh` local variable; will continue to work after `geometry.Dh` is computed correctly
- All three channel variants (Channel, ChannelAndContacts, ChannelHeatFlux) extract `Dh = geometry.Dh` at construction time — no change needed there

### Established Patterns

- Sentinel-kwargs dispatch: `PipeGeometry(; D=nothing, y=nothing, ...)` — same pattern being applied to Pump
- `build_initializeprob=false` for coupled HeatDiffusion+CAC — carry forward unchanged
- `@register_symbolic` fluid props callable from any MTK equation — unchanged

### Integration Points

- `PipeGeometry` is used in Channel, ChannelAndContacts, ChannelHeatFlux constructors — all read `.Dh`, `.A`, `.L`, `.heated_parts`; `.wet_perimeter` is new
- `Pump` is used in every integration test; adding `mdot0` mode is additive, does not change existing `dP_pump` tests

</code_context>

<specifics>
## Specific Ideas

- Design goal: `PipeGeometry` should look like Python's `EffectivePipe` — generic, stores raw perimeters, derives effective diameters. Not geometry-specific in the struct itself; geometry-specificity lives in the factory constructors.
- The `one_sided` kwarg on `.rectangular()` mirrors Python exactly so future `one_sided_connection` in Phase 15 can build on it naturally.

</specifics>

<deferred>
## Deferred Ideas

- `heated_diameter` as a separate field (4A/heated_perimeter) — Python stores it; may be needed if laminar CHF correlations land in a future phase; defer until there's a use case
- `width` and `depth` fields (Sudo-Kaminaga CHF, Elenbaas correlation) — out of scope for v0.4
- `one_sided` geometry used in `one_sided_connection` assembly — Phase 15 wires up the MTK connections; Phase 13 just makes the geometry expressible

</deferred>

---

*Phase: 13-physics-foundation*
*Context gathered: 2026-03-14*
