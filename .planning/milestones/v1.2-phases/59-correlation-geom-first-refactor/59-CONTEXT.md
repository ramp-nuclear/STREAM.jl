# Phase 59: Correlation `geom`-first refactor - Context

**Gathered:** 2026-05-11
**Status:** Ready for planning

<domain>
## Phase Boundary

Refactor every correlation factory in `src/physical_models/htc/correlations.jl`
and `src/physical_models/friction/correlations.jl` that consumes geometry to
take `geom::PipeGeometry` as its first positional argument. Derive
`Dh`/`L`/`depth`/`width`/`aspect_ratio` internally from `geom`; eliminate them
as user-facing kwargs. Introduce `const HTCCorrelation = Function` type alias.
Update all in-repo call sites (`src/examples.jl`, `test/test_correlations.jl`).
Re-run Python parity harness (`test/data/python_parity_reference.jl`) to verify
no semantic drift. Emit a Phase 61 handoff doc capturing the new API surface.

**Hard invariant:** No correlation factory accepts `Dh` / `L` / `depth` /
`width` / `aspect_ratio` as a separate user-facing argument. Only `geom`.

**In scope (factories that read geom fields today):**
- `laminar_friction(aspect_ratio)` → `laminar_friction(geom)`
- `elenbaas_htc(; b, L, Dh, g)` → `elenbaas_htc(geom; g)`
- `fully_developed_laminar_h_spl(; Dh, aspect_ratio)` → `fully_developed_laminar_h_spl(geom)`
- `developing_laminar_h_spl(; Dh, develop_length, aspect_ratio)` → `developing_laminar_h_spl(geom; develop_length)`
- `regime_dependent(; ..., Dh, g)` → `regime_dependent(geom; ..., g)`

**Out of scope:**
- `dittus_boelter`, `blasius_friction`, `turbulent_friction` — stateless,
  stay as direct functions.
- `constant_Nusselt(; Nu)`, `maximal_htc(correlations...)` — no geom-dependent
  state, stay as-is.
- `regime_dependent_q_scb` in `src/physical_models/subcooled_boiling.jl` —
  same factory pattern but does not read geom fields today. Already satisfies
  the invariant. Touching it would be churn (D-02).
- Channel / CHF / CAC internals (`src/components/channels.jl`) — they consume
  the closure interface, which does not change.
- GUI registry rewrite — Phase 61.

</domain>

<decisions>
## Implementation Decisions

### Convention (locked upstream by design-decisions §3.1)
- **D-00 (carried forward, not re-discussed):** Every factory that needs
  any value from `PipeGeometry` takes `geom::PipeGeometry` as first
  positional argument and derives what it needs internally. Pure tuning
  kwargs (`Re_transition`, `Nu`, `develop_length`, `epsilon`, `htc_natural`,
  `g`) stay as kwargs. Stateless functions stay direct. `const HTCCorrelation
  = Function` alias is introduced for closure-arg clarity (documentation
  value; not enforcement).

### Rollout strategy
- **D-01:** Clean break, no deprecation shim. Old kwargs (`Dh`, `b`, `L`,
  `aspect_ratio` on factories) are removed in the same commit that introduces
  the new signatures. All in-repo call sites
  (`src/examples.jl` ~lines 438/441/443 + 581; `test/test_correlations.jl`)
  are updated atomically. v1.2 is the natural API-break boundary; STREAM.jl
  is pre-1.0 in the Julia ecosystem sense; no external consumers to protect.
  Documented as a v1.2 breaking change.

### Scope guard for `subcooled_boiling.jl`
- **D-02:** `regime_dependent_q_scb` is left untouched. It already satisfies
  the §3.1 invariant (takes only `pressure`, `h_fg`, `sigma`, `Re_transition`
  — none of which are geom fields). Phase 59 only refactors factories that
  *actually consume* geom values. If a future correction inside `q_scb`
  needs `Dh`, that's a separate phase concern.

### `elenbaas_htc` on non-rectangular geometry
- **D-03:** Docstring-only guidance, no runtime check. The new
  `elenbaas_htc(geom; g)` docstring states explicitly that the correlation
  is for parallel-vertical-plates natural convection and expects a
  rectangular `PipeGeometry` where `geom.depth` is the plate gap. No
  `@assert` / `@warn`. Trust-the-user posture, consistent with the rest of
  the library. A `depth == width` heuristic would also reject legitimate
  square-cross-section rectangular channels, so the check is not worth its
  false-positive cost.

### `develop_length` handling
- **D-04:** `develop_length` stays a *mandatory* kwarg on
  `developing_laminar_h_spl(geom; develop_length)`. No default. No silent
  substitution with `geom.L`. Forces the caller to make a conscious choice
  about the developing-flow evaluation point. The Phase 61 GUI registry
  encodes `develop_length` as a required field. Matches today's call-site
  behavior, so no test churn beyond the signature change.

### Phase 61 handoff
- **D-05:** Phase 59 emits a short reference doc
  `.planning/notes/correlation-geom-first-api.md`. Contents: a table per
  factory listing (a) final signature, (b) which `geom` fields are read
  internally, (c) which kwargs remain and their defaults. Phase 61
  (registry audit + rewrite) reads this directly instead of re-deriving from
  source. The doc is a v1.2 design artifact and survives in
  `.planning/notes/` alongside `gui-redesign-design-decisions.md`. It does
  *not* replace docstrings — those remain the in-source source of truth.

### Test layout
- **D-06:** `test/test_correlations.jl` stays as a single file. The src
  side has been split into `src/physical_models/htc/` and
  `src/physical_models/friction/` subfolders without splitting the test
  file, so the existing precedent for this corner of the codebase already
  permits one test file per subject area. Splitting now is gratuitous
  churn for Phase 59's scope.

### Claude's Discretion
- Internal helper preservation: `rectangular_laminar_correction`,
  `_two_sided_heating_nusselt`, `_nusselt_coefficient_developing`,
  `_bergles_rohsenow_dT_ONB` keep their current signatures. They are
  private helpers, not factories.
- Error messages and `ArgumentError` text for `regime_dependent`'s
  natural-convection group validation can be tightened during the refactor
  if the change makes the constraint clearer; not required.
- Docstring formatting and example-code blocks: planner / executor may
  choose to consolidate redundant "Eval-point convention" boilerplate, but
  this is cosmetic and not load-bearing.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Design contract for this phase
- `.planning/notes/gui-redesign-design-decisions.md` §3.1 — "Correlation
  Refactor — `geom`-first Convention". The locked design; defines the
  convention, the invariant, and the explicit scope/non-scope per factory.
  Also defines `const HTCCorrelation = Function` alias.

### Source files to edit
- `src/physical_models/htc/correlations.jl` — factories: `regime_dependent`,
  `elenbaas_htc`, `fully_developed_laminar_h_spl`,
  `developing_laminar_h_spl`. Stateless helpers stay as-is.
- `src/physical_models/friction/correlations.jl` — factory:
  `laminar_friction`. `blasius_friction`, `turbulent_friction`,
  `viscosity_correction`, `rectangular_laminar_correction` stay as-is.
- `src/STREAM.jl` — export list (no change to exported names; only adds
  `HTCCorrelation`).
- `src/examples.jl` — call sites at lines 438 (regime_dependent block),
  441 (laminar_friction), 443 (elenbaas_htc), 581 (laminar_friction).
- `test/test_correlations.jl` — every factory test + every integration
  test that constructs a factory.

### Verification gates
- `test/test_correlations.jl` — unit + integration tests, all must pass on
  new signatures.
- `test/test_validation.jl` + `test/data/python_parity_reference.jl` —
  quantitative parity gate. MUST be re-run after refactor to catch silent
  semantic drift. Per §3.1 test-plan bullet.
- `test/test_channels.jl`, `test/test_integration.jl` — indirect call sites
  through `examples.jl` builders (`build_loop`, `build_loop_vertical`,
  `build_loop_transient`).

### Geometry contract
- `src/geometry.jl` — `PipeGeometry` struct and `PipeGeometry_rectangular`
  / `PipeGeometry_circular` factories. Fields read by correlations:
  `geom.L`, `geom.Dh`, `geom.depth`, `geom.width` → derived
  `aspect_ratio = depth/width`. No `kind` field exists; geometry is
  flat-struct.

### Workflow conventions
- `CLAUDE.md` — branching policy (this phase commits to `gui-redesign`,
  no new branches), MTK patterns (`ifelse`, `@register_symbolic`,
  `vars=[]`, `mtkcompile`), component authoring conventions (positional
  args when type determines behavior; factory functions use positional
  args; `name` kwarg-only), exports declared in `STREAM.jl` only.
- `.planning/ROADMAP.md` lines 31, 48–54 — phase entry and goal statement.

### Handoff (emitted by this phase)
- `.planning/notes/correlation-geom-first-api.md` — produced as a Phase 59
  deliverable per D-05. Phase 61 consumes it.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`PipeGeometry`** (`src/geometry.jl`): already carries `L`, `Dh`, `depth`,
  `width`. After refactor, `aspect_ratio = geom.depth / geom.width` is
  derived inside each factory. No new field needed.
- **Factory closure pattern**: every refactored factory still returns a
  closure with the same `(Re, Pr, T_bulk, T_wall) -> Nu` or `(Re) -> f`
  signature consumed by `_channel_core` in `src/components/channels.jl`.
  The closure interface is invariant.
- **`Float64(...)` immediate coercion** for scalars captured in closures
  (see `regime_dependent`'s `Re_tr = Float64(Re_transition)` and
  `Dh_val = Float64(Dh)`): avoids type-promotion issues when `Re` is a
  `Symbolics.Num`. Pattern carries forward.

### Established Patterns
- **`ifelse()` (not `if/else`)** for regime switching inside closures.
  MTK-traced; established project pattern. `regime_dependent` and
  `_nusselt_coefficient_developing` both rely on this.
- **`@warn` / `ArgumentError` group-validation** at factory construction
  (see `regime_dependent`'s `(htc_natural, Dh, g)` group). After refactor,
  the `Dh` member of that group goes away (now in `geom`); the validation
  collapses to `(htc_natural, g)` mutual-presence.
- **Stateless `args...` swallowing** on HTC closures (`(Re, Pr, args...)
  -> Nu`): preserved so the 4-arg HTC interface `(Re, Pr, T_bulk, T_wall)
  -> Nu` continues to work for closures that don't need `T_bulk`/`T_wall`.

### Integration Points
- `src/components/channels.jl` line ~456 — `_channel_core` consumes
  `htc_correlation` and `friction_correlation` closures via the kwarg
  pipeline. Untouched.
- `src/examples.jl` `build_loop` family — call sites here demonstrate the
  *intended* construction shape: `geom = PipeGeometry_rectangular(...);
  htc = elenbaas_htc(geom; g=g_acc)`. These become the canonical examples
  for the new API.
- `test/test_correlations.jl` integration tests already build a
  `PipeGeometry_rectangular` and pass derived values; converting them to
  pass the geom struct is a mechanical swap.

</code_context>

<specifics>
## Specific Ideas

- Example construction shape after refactor (canonical form for docstrings):
  ```julia
  geom = PipeGeometry_rectangular(L, e1, e2, he)
  fric = laminar_friction(geom)
  htc_fd = fully_developed_laminar_h_spl(geom)
  htc_dev = developing_laminar_h_spl(geom; develop_length=0.5)
  htc_nc = elenbaas_htc(geom; g=9.81)
  rd = regime_dependent(geom;
      htc_laminar=htc_fd, htc_turbulent=dittus_boelter,
      friction_laminar=fric, friction_turbulent=blasius_friction,
      htc_natural=htc_nc, g=9.81)
  ```
- Phase 61 handoff doc structure (suggested):
  ```
  | Factory | Final signature | geom fields read | Remaining kwargs |
  |---------|------------------|-------------------|-------------------|
  | laminar_friction | (geom) | depth, width | — |
  | elenbaas_htc | (geom; g) | depth, L, Dh | g (default 9.81) |
  | ...
  ```

</specifics>

<deferred>
## Deferred Ideas

- **`regime_dependent_q_scb` geom-first treatment** — explicitly deferred per
  D-02. Revisit only if a future correction needs `Dh` from geometry.
- **Test file split (`test_htc_correlations.jl` / `test_friction_correlations.jl`)**
  — explicitly deferred per D-06. Reconsider if `test/test_correlations.jl`
  grows past ~800 lines or if HTC and friction tests start needing
  divergent helper setup.
- **Deprecation shims** — explicitly deferred per D-01. Clean break instead.
  Not coming back.
- **Runtime geometry-kind enforcement (rectangular vs circular)** —
  explicitly deferred per D-03. Would require a `kind`/discriminator field
  on `PipeGeometry`, which is itself a separate refactor question.

</deferred>

---

*Phase: 59-correlation-geom-first-refactor*
*Context gathered: 2026-05-11*
