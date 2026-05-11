# Correlation `geom`-first API — Post-Phase-59 Surface

**Status:** Canonical handoff artifact for Phase 61 (GUI registry rewrite).
**Source decision:** Phase 59 CONTEXT.md `<decisions>` D-05.
**Companion document:** `.planning/notes/gui-redesign-design-decisions.md` §3.1
("Correlation Refactor — `geom`-first Convention").
**Scope:** This doc captures the post-Phase-59 correlation API surface only.
It does **not** replace docstrings — in-source docstrings remain the
canonical source of truth for argument semantics, eval-point conventions,
and per-correlation references. Phase 61 reads this doc instead of
re-deriving the API surface from `src/`.

Phase 59 landed in four plans on the `gui-redesign` working branch:
- 59-01 — `laminar_friction(geom)` clean break + `HTCCorrelation` alias
- 59-02 — `elenbaas_htc(geom; g)` / `fully_developed_laminar_h_spl(geom)` /
  `developing_laminar_h_spl(geom; develop_length)` / `regime_dependent(geom; ...)`
  clean break
- 59-03 — Repo-wide call-site sweep + Python-parity gate
- 59-04 — This doc

---

## Type alias: `HTCCorrelation`

```julia
const HTCCorrelation = Function
```

Declared and exported from `src/STREAM.jl`. The alias is a
**documentation-only annotation** for closure-arg positions (see
`regime_dependent`'s `htc_laminar::HTCCorrelation`, `htc_turbulent::HTCCorrelation`,
and `htc_natural::Union{HTCCorrelation,Nothing}` kwargs). It is **not**
runtime-enforcing — Julia treats `HTCCorrelation` and `Function` as the
same type for dispatch. The alias signals intent at call sites without
imposing a stricter check. See `gui-redesign-design-decisions.md` §3.1
for the locked design rationale.

The alias has no GUI-visible effect — Phase 61's registry should ignore
it when rendering parameter forms.

---

## Refactored factories — final API surface

The five factories below are the **only** correlation factories changed
in Phase 59. Each takes `geom::PipeGeometry` as its first positional
argument and derives geometry-dependent constants internally. Any
remaining kwargs are pure tuning parameters per §3.1.

| Factory | File | Final signature | `geom` fields read | Remaining kwargs | Notes |
|---------|------|-----------------|--------------------|------------------|-------|
| `laminar_friction` | `src/physical_models/friction/correlations.jl` | `laminar_friction(geom::PipeGeometry) -> (Re) -> f_darcy` | `depth`, `width` (derives `aspect_ratio = depth/width`) | — | For circular geometry (`depth == width`), `K_R ≈ 1.1246` gives `f ≈ 56.9/Re`. Callers wanting strict-circular `64/Re` should use a raw lambda `(Re) -> 64.0/Re` instead of this factory (documented in the factory's docstring). |
| `elenbaas_htc` | `src/physical_models/htc/correlations.jl` | `elenbaas_htc(geom::PipeGeometry; g=9.81) -> (Re, Pr, T_bulk, T_wall) -> Nu` | `depth` (as plate gap `b`), `L`, `Dh` (as Grashof characteristic length) | `g` (default `9.81` m/s²) | Trust-the-user posture per D-03. Docstring states this correlation is for **parallel-vertical-plates natural convection** and expects a rectangular `PipeGeometry` where `depth` is the plate gap. No runtime geometry-kind check. |
| `fully_developed_laminar_h_spl` | `src/physical_models/htc/correlations.jl` | `fully_developed_laminar_h_spl(geom::PipeGeometry) -> (Re, Pr, T_bulk, T_wall) -> Nu` | `depth`, `width` (derives `aspect_ratio`) | — | `geom.Dh` is **intentionally not consumed** — `Nu` depends on `aspect_ratio` only. This matches the pre-Phase-59 behavior where `Dh` was an ignored interface-consistency kwarg. |
| `developing_laminar_h_spl` | `src/physical_models/htc/correlations.jl` | `developing_laminar_h_spl(geom::PipeGeometry; develop_length) -> (Re, Pr, T_bulk, T_wall) -> Nu` | `depth`, `width`, `Dh` | `develop_length` (**MANDATORY**, no default per D-04) | `develop_length` is the distance from channel entrance at which `Nu` is evaluated. The caller must explicitly choose the evaluation point; no silent substitution with `geom.L`. Phase 61's GUI registry should encode `develop_length` as a required field with no default value. |
| `regime_dependent` | `src/physical_models/htc/correlations.jl` | `regime_dependent(geom::PipeGeometry; htc_laminar::HTCCorrelation, htc_turbulent::HTCCorrelation, friction_laminar::Function, friction_turbulent::Function, htc_natural::Union{HTCCorrelation,Nothing}=nothing, g=nothing, Re_transition=2300) -> (htc=fn, friction=fn)` | `Dh` (only used on the NC-enabled path for the Grashof formula) | `htc_laminar`, `htc_turbulent`, `friction_laminar`, `friction_turbulent` (all four required); `htc_natural` (optional, default `nothing`); `g` (paired with `htc_natural` — `ArgumentError` if `htc_natural` provided without `g`); `Re_transition` (default `2300`) | Group validation collapsed from `(htc_natural, Dh, g)` (Phase 26) to `(htc_natural, g)` (Phase 59) since `Dh` is no longer a user-facing kwarg. The pre-Phase-59 stray-kwarg `@warn` ("NC regime will not be detected") was removed — `Dh` is now read from `geom.Dh` internally, and a lone `g` without `htc_natural` is a permitted no-op. The `ArgumentError` text is: `"regime_dependent: htc_natural provided but g is missing — both (htc_natural, g) must be supplied together."` |

### Canonical construction example

The shape Phase 61's GUI registry should generate for a channel with
forced + natural convection regime switching:

```julia
geom = PipeGeometry_rectangular(L, e1, e2, he)
fric  = laminar_friction(geom)
htc_fd  = fully_developed_laminar_h_spl(geom)
htc_dev = developing_laminar_h_spl(geom; develop_length = 0.5)
htc_nc  = elenbaas_htc(geom; g = 9.81)
rd = regime_dependent(geom;
    htc_laminar        = htc_fd,
    htc_turbulent      = dittus_boelter,
    friction_laminar   = fric,
    friction_turbulent = blasius_friction,
    htc_natural        = htc_nc,
    g                  = 9.81,
)
ChannelAndContacts(
    htc_correlation      = rd.htc,
    friction_correlation = rd.friction,
    ...,
)
```

Note that `geom` is the *single* geometry source threaded through every
factory; the GUI registry should reflect this by replacing each factory's
geometry-bearing fields with a single "geom reference" pointing at the
parent channel's `PipeGeometry` resource.

---

## Not touched (explicit non-modifications)

Phase 59 deliberately left the following correlation functions unchanged.
Each entry cites the locked rationale from `gui-redesign-design-decisions.md`
§3.1 or Phase 59 CONTEXT.md `<decisions>`.

- **`dittus_boelter`** (`src/physical_models/htc/correlations.jl`):
  stateless direct function, no geom needed. §3.1 "Stateless direct
  functions stay direct functions."
- **`blasius_friction`** (`src/physical_models/friction/correlations.jl`):
  same — stateless turbulent friction correlation.
- **`turbulent_friction`** (`src/physical_models/friction/correlations.jl`):
  same — stateless Colebrook-White approximation. `epsilon` stays a kwarg
  per §3.1 "Pure tuning kwargs stay kwargs."
- **`constant_Nusselt(; Nu=8.235)`** (`src/physical_models/htc/correlations.jl`):
  no geom-dependent state. `Nu` is a pure tuning kwarg per §3.1.
- **`maximal_htc(correlations...)`** (`src/physical_models/htc/correlations.jl`):
  combinator over already-built HTC closures; has no geom of its own.
- **`elenbaas_nusselt(Ra, b, L)`** (`src/physical_models/htc/correlations.jl`):
  standalone formula, not a factory. Used internally by `elenbaas_htc`.
- **`Marco_Han_Nusselt(aspect_ratio)`** (`src/physical_models/htc/correlations.jl`):
  standalone formula. Not a factory.
- **`viscosity_correction(heat_wet_ratio, mu_ratio)`** (`src/physical_models/friction/correlations.jl`):
  standalone formula. Not a factory.
- **`rectangular_laminar_correction(aspect_ratio)`** (`src/physical_models/friction/correlations.jl`):
  private helper consumed inside `laminar_friction`. Public API surface
  unchanged.
- **`regime_dependent_q_scb`** (`src/physical_models/subcooled_boiling.jl`):
  same factory pattern as `regime_dependent`, but reads no `geom` fields
  today (its arguments are `pressure`, `h_fg`, `sigma`, `Re_transition` —
  none of which are geometry quantities). Per Phase 59 CONTEXT.md D-02,
  touching it would be churn; deferred until a future correction inside
  `q_scb` actually needs `Dh`.
- **Private helpers** — `_two_sided_heating_nusselt`,
  `_nusselt_coefficient_developing`, `_bergles_rohsenow_dT_ONB`. Not
  factories, not user-facing, not exported.

---

## GUI registry implications (Phase 61 guidance)

For each refactored factory, Phase 61's GUI registry should:

- **Collapse the parameter tree.** The pre-Phase-59 user-facing fields
  `Dh`, `L`, `b`, `aspect_ratio` are replaced by a single "geom reference"
  pointing at the parent channel's `PipeGeometry` resource. No factory
  accepts these as independent user-facing kwargs anymore.
- **Render only the remaining kwargs as editable fields per factory:**
  - `elenbaas_htc`: `g` (default `9.81`)
  - `developing_laminar_h_spl`: `develop_length` (**mandatory, no default** —
    the GUI should mark this field as required and refuse to submit
    without a user-supplied value)
  - `regime_dependent`: `htc_laminar`, `htc_turbulent`, `friction_laminar`,
    `friction_turbulent` (all required, foreign keys to other correlation
    resources); `htc_natural` (optional, foreign key); `g` (required iff
    `htc_natural` is set); `Re_transition` (default `2300`)
  - `constant_Nusselt`: `Nu` (default `8.235`) — unchanged from
    pre-Phase-59 since `constant_Nusselt` was already in §3.1's
    "pure-tuning-kwarg-only" bucket.
  - `turbulent_friction`: `epsilon` (default `0`) — same, unchanged.
- **Ignore the `HTCCorrelation` alias.** It has no GUI-visible effect; it
  is source-only documentation.
- **Per §3.10 / §3.11**, `htc_correlation` / `friction_correlation` are
  Properties-tab fields on `ChannelAndContacts` (constructor kwargs).
  They accept factory-call expressions whose first argument is the
  channel's own `geom`. The GUI registry should validate that the geom
  threaded into each factory matches the parent channel's geom
  (or warn / require an explicit override if not).

---

## Validation / parity status

Python parity gate (`test/test_validation.jl`) confirmed no semantic
drift from this refactor — see
`.planning/phases/59-correlation-geom-first-refactor/59-03-SUMMARY.md`.
Pre- and post-refactor verdicts are identical: 424 CLEAN / 78 GRAY /
34 FAIL across the MTR L/R harness baseline. No correlation produced
a different Nu or `f` between the kwarg-only and geom-first surfaces;
the refactor is a pure API reshape with zero numerical impact.

---

*Phase 59 handoff artifact. Last updated 2026-05-11.*
