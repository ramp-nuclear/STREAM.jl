# Phase 61: Registry audit + rewrite for v1.1 - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-12
**Phase:** 61-registry-audit-rewrite-for-v1-1
**Areas discussed:** scope field + external-input shape, Correlation factory tree, Polymorphic value params, PointKinetics + ReactivityController, Port-type + array ports (follow-up)

---

## Area 1 — `scope` field + external-input shape

### Q1: Where should T_wall_*[1:n] / q_*[1:n] external-input variables live?

| Option | Description | Selected |
|--------|-------------|----------|
| Top-level `external_inputs[]` | Separate top-level array per component; `parameters[]` stays pure constructor-kwarg | ✓ |
| Unified `parameters[]` + `scope` | Single array, each entry tagged `scope: 'constructor_kwarg' | 'external_input'` | |
| Hybrid: scope on params + bc_modes | Unified array but external-input entries get bc_modes sub-block | |

**User's choice:** Top-level `external_inputs[]`.
**Notes:** Locks the MTK kwarg-vs-@variable distinction at the JSON-shape level. CAC has no `external_inputs[]` block since its wall conditions arrive exclusively via ThermalPort connections (§3.10 invariant).

### Q2a: Still add a redundant `scope` field on parameters[] entries?

| Option | Description | Selected |
|--------|-------------|----------|
| Skip — structure encodes it | Structural separation already accomplishes the split; no `scope` field | ✓ |
| Add scope for explicitness | Every row tagged with single legal value; self-documenting but redundant | |

**User's choice:** Skip.

### Q2b: Bump `schema_version` 1.0 → 2.0?

| Option | Description | Selected |
|--------|-------------|----------|
| Bump to 2.0 (clean break) | Honest signal that schema reshape introduces breaking new fields | ✓ |
| Stay at 1.0 | Optional new fields don't break a permissive reader; no external consumers | |
| Bump to 1.1 (additive) | Middle ground; but Phase 61 also renames htc_correlation away from Channel which is breaking | |

**User's choice:** Bump to 2.0.

---

## Area 2 — Correlation factory tree under geom-first

### Q1: How should the registry represent correlation factory trees?

| Option | Description | Selected |
|--------|-------------|----------|
| Keep nesting, drop geom leaves | Existing recursive `options[].sub_parameters[]` shape; just shorter leaves; mark geometry-bearing factories `geom_source: parent` | ✓ |
| Top-level `correlation_factories` catalog | Extract factory definitions out of inline; component param declares `accepts: HTCCorrelation` | |
| Hybrid: catalog + inline allowlist | Catalog + per-component `allowed_factories[]` allowlist | |

**User's choice:** Keep nesting, drop geom leaves.

### Q2: How should `regime_dependent`'s htc/friction-bundle output be handled?

| Option | Description | Selected |
|--------|-------------|----------|
| Bundle option on htc_correlation only | Auto-fill friction_correlation when regime_dependent chosen on htc | |
| Top-level regime_bundle param | Sibling param that supplies both fields when set | |
| Repeat on both fields, dedupe at codegen | List regime_dependent independently on both; codegen detects duplicate selection | (user variant) |

**User's choice:** Free-text — "They don't have to be connected to each other. A user could want to use regime_dependent on htc, and a different one on friction. or vise versa. What we do need to detect is if they both are regime_dependent, there is no need to call the factory twice."
**Notes:** Locked as D-09. Registry lists `regime_dependent` independently in both `htc_correlation.options` and `friction_correlation.options`. The de-duplication is a codegen-side optimization (Phase 66 territory): if both fields reference semantically-identical `regime_dependent(...)` calls, emit one `rd = regime_dependent(...)` plus `htc_correlation=rd.htc, friction_correlation=rd.friction`; otherwise two separate factory calls. Each `regime_dependent` registry option carries `produces: ["htc","friction"]` so codegen knows which NamedTuple field to take.

---

## Area 3 — Polymorphic value parameters (Real | Vector | Function)

### Q1: How should Properties-tab polymorphic value params be typed?

| Option | Description | Selected |
|--------|-------------|----------|
| type_union with input_modes | Single param with `type_union: ['Real','Vector','Function']` and `input_modes: ['scalar','vector','callable']` | ✓ |
| Separate mode-tagged entries | Three rows per polymorphic kwarg (h_left_scalar, h_left_vector, h_left_callable) | |
| Single type:Real, hide vector/callable | v1 only exposes scalar mode; defer mode-switcher UI | |

**User's choice:** type_union with input_modes.
**Notes:** Applies to Channel `h_left`/`h_right`, WallTemperature `T_wall`, HeatFluxSource `q`. BCs-tab external inputs use a separate `bc_modes: ["Value","Profile","Function","Mark","Source"]` mode list per §3.11 (D-11) — the two mode sets are deliberately distinct because BCs-tab includes "Mark" and "Source" which only make sense on Channel/CHF external inputs.

---

## Area 4 — PointKinetics + ReactivityController

### Q1: How should PointKinetics' two constructors be represented?

| Option | Description | Selected |
|--------|-------------|----------|
| Single entry, polymorphic rho | One PointKinetics entry, rho field has `type_union: ['Real','Function','ReactivityController']` with mode picker | ✓ |
| Two entries: PointKinetics + PointKinetics_callable | Two registry IDs, toolbox shows both | |
| Single entry, callable always | Only callable constructor exposed; scalar = constant callable | |

**User's choice:** Single entry, polymorphic rho.
**Notes:** `temp_worth` / `ref_temp` show only in callable/controller modes. Encoded as "Mark in code" for v1 since the Dict keys are MTK Systems and can't be selected in JSON.

### Q2: How should ReactivityController be exposed?

| Option | Description | Selected |
|--------|-------------|----------|
| Resource (kwarg-only target) | Created in navigator, never dragged onto canvas; PK's rho field accepts a Resource ref | ✓ |
| Canvas-draggable component (no ports) | Toolbox-draggable block with logical 'controller' output; new port-type concept | |
| Defer entirely from Phase 61 | Punt ReactivityController until full PK GUI integration phase | |

**User's choice:** Resource (kwarg-only target).
**Notes:** Lives in navigator under `Resources → Reactivity Controllers` (sibling to Geometries, Power Shapes). No canvas presence, no ports, no MTK System. Callable kwargs (input_reactivity, state_machine, abort_states) use "Mark in code" mode in v1. initial_state is a Symbol (free-text + `:` prefix at codegen); initial_time is `Real` default `0.0`.

---

## Area 5 — Port-type + array ports (follow-up clarification)

User asked for clarification before answering; questions reformulated, then re-asked after explanation.

### Q1: Add a new port type for value-source outputs?

| Option | Description | Selected |
|--------|-------------|----------|
| New `BCPort` type | GUI-only port-type tag for `WallTemperature.T_wall_out` / `HeatFluxSource.q_out`; drives dashed-edge style and hard-block validation | ✓ |
| Reuse `ThermalPort` with subtype | Discriminator field on existing port type; conflates MTK heat-flow with BC binding | |
| No port — binding-only | No registry port; edge connects body-to-body via `external_inputs[].source_component` only | |

**User's choice:** New `BCPort` type.
**Notes:** Explicitly confirmed GUI-only — no `src/` change, no MTK connector type. The underlying binding remains a plain `@variable` equality (`ch.T_wall_left[i] ~ wt.T_wall_out[i]`). `BCPort` is a string tag in `components.json` that tells the GUI how to render the dot, which edge style to use, and which validation hard-blocks apply.

### Q2: How should array-shaped logical ports be encoded?

| Option | Description | Selected |
|--------|-------------|----------|
| `array_size: 'n'` + autoflip axis | New `array_size` and `default_axis` fields; registry is single source of truth for autoflip default | ✓ (Claude's recommendation, user agreed) |
| `array_size` + explicit side | Only add `array_size`; keep `side` as-is; autoflip logic lives in TypeScript files | |

**User's choice:** Claude's recommendation accepted ("Do what you recommend if you think its best").
**Notes:** CAC `thermal_left`/`thermal_right`: `array_size: "n"`, `default_axis: "vertical"`. HD `thermal_left`/`thermal_right`: `array_size: "n"`, `default_axis: "horizontal"`. Value-source `T_wall_out`/`q_out`: `array_size: "n"`, `default_axis: "horizontal"`, static `side: "right"`. `pair_with` field on thermal ports locks opposing pairs to opposite faces (§3.4 invariant).

---

## Claude's Discretion

- **Empty-sub_parameters factories** (CD-01): For factories with zero remaining user-facing kwargs after Phase 59 (`laminar_friction`, `fully_developed_laminar_h_spl`), omit `sub_parameters` entirely rather than emitting `sub_parameters: []`. JSON cleanliness; tooling reads "factory with no remaining kwargs" identically.
- **Icon SVGs deferred** (CD-02): WallTemperature / HeatFluxSource / PointKinetics / ReactivityController icon visuals are §3.8 / Phase 68 (design system) territory. Phase 61 declares the registry data only.
- **Channel `friction_correlation.options`** (CD-03): Channel has no `htc_correlation` field, so `regime_dependent` is NOT a legal option for Channel's `friction_correlation` (it produces both htc and friction in a bundle with no htc consumer on Channel). Registry encodes this by simply not listing `regime_dependent` in Channel's `friction_correlation.options`.

## Deferred Ideas

- Phase 71 — Connection-rule validation framework (consumes the new port-type taxonomy + `external_inputs[].source_component` allowlist + `pair_with` invariant).
- Phase 66 — `codeGenerator.ts` rewrite + `regime_dependent` dedupe rule + `fuel_assembly` topology detector (Phase 60 handoff).
- Phase 62 — Resources Panel navigator UI (Phase 61 declares `ReactivityController` as a Resource kind; navigator tree node is Phase 62).
- Phase 63 — BCs tab UI (consumes `external_inputs[]` + `bc_modes` enum; builds mode picker + bidirectional sync between dropdown and canvas dashed edge).
- Phase 64 — Dashed BC-edge rendering + autoflip routing (consumes `BCPort` + `default_axis` + `pair_with` data).
- Future GUI phase — Structured editor for PointKinetics `temp_worth` / `ref_temp` dicts (v1.2 punts to "mark in code").
- v0.6+ library work — User-defined correlation Resources (mentioned as a possible Area-2 option B evolution; out of v1.2 scope).
