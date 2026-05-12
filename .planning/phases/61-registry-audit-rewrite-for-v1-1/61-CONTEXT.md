# Phase 61: Registry audit + rewrite for v1.1 - Context

**Gathered:** 2026-05-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Rewrite `gui/src/registry/components.json` to match v1.1 `src/` exactly. The
registry is the single source of truth that drives toolbox rendering, property
panel field generation, port handle placement, and (downstream) connection
validation. Today it is pinned at `stream_version: 0.7.0` and predates the
v1.1 channel-family redesign, the Phase 59 geom-first correlation refactor,
and the v1.1 value-source components.

**In scope:**
- Bump `stream_version: 0.7.0 → 1.1.0` and `schema_version: 1.0 → 2.0` (clean
  break — no `.streamgui` files exist in the wild per §3.2, the registry has
  no external consumers).
- Add 4 missing components: `WallTemperature`, `HeatFluxSource`,
  `PointKinetics`, `ReactivityController` (`ReactivityController` is a
  Resource, not a draggable component — see D-12).
- Rewrite `Channel` and `ChannelHeatFlux` entries:
  - Drop the `thermal` port entry (Channel/CHF have no thermal ports under v1.1).
  - Drop `htc_correlation` from Channel (only CAC keeps it; §3.10).
  - Add `h_left` and `h_right` Properties-tab kwargs to Channel
    (`Real | Vector | Function` polymorphic).
  - Declare `T_wall_left[1:n]` / `T_wall_right[1:n]` (Channel) and
    `q_left[1:n]` / `q_right[1:n]` (CHF) as external-input variables via a
    new top-level `external_inputs[]` block per entry.
- Rewrite `ChannelAndContacts`:
  - Keep `htc_correlation` and `friction_correlation` as Properties-tab kwargs.
  - Collapse all factory `sub_parameters` trees per Phase 59 geom-first:
    drop `Dh`/`L`/`b`/`aspect_ratio` from every factory; mark
    geometry-bearing factories with `geom_source: "parent"`.
  - Encode thermal port pair as `thermal_left` / `thermal_right` with
    `array_size: "n"` and `default_axis: "vertical"` (top/bottom default per
    §3.4 autoflip rule).
- Introduce a new `BCPort` port-type tag for value-source outputs
  (`WallTemperature.T_wall_out[1:n]`, `HeatFluxSource.q_out[1:n]`). GUI-only
  concept (no `src/` change); enables the dashed-edge style and per-§3.11
  hard-blocks at connection time.
- Add `array_size` and `default_axis` fields to array-shaped logical ports;
  keep the static `side` field for non-autoflip components (Pump, Resistor,
  etc.).
- Cross-reference HeatDiffusion's thermal port pair (today `side: "left"`/`side: "right"`)
  with the new `array_size`/`default_axis` shape — HD default axis is
  `horizontal`.

**Out of scope:**
- The actual TypeScript GUI rewrites that consume the new schema (property
  panel tabs, BCs-tab mode picker UI, dashed-edge rendering, autoflip
  routing). Those land in Phases 62/63/64/68 per the roadmap.
- Connection-rule validation framework (Phase 71).
- `gui/src/lib/codeGenerator.ts` topology detection for `fuel_assembly`
  (Phase 60 handoff note → Phase 61 implements the detector in
  `codeGenerator.ts`). The detector lives in `codeGenerator.ts`, but the
  registry side of Phase 61 (this CONTEXT.md) declares no registry changes
  for it — `fuel_assembly` is not a registry component (Phase 60 D-01).
- New port-type taxonomy in `src/` (BCPort is GUI-only — see D-13).
- v1.2 Resources panel architecture (Phase 62 — registry only needs to
  support the FK-shape for `geometry_ref` / future `power_shape_ref` /
  `reactivity_controller_ref`; the navigator-tree UI is Phase 62).
- Code preview rework (Phase 66 owns the regime_dependent dedupe codegen
  rule; this phase only sets up the registry shape to enable it).

</domain>

<decisions>
## Implementation Decisions

### Version bumps + schema reshape (Area 1)
- **D-01:** Bump `stream_version: 0.7.0 → 1.1.0`. The library version this
  registry mirrors. Required by phase goal wording.
- **D-02:** Bump `schema_version: 1.0 → 2.0` (clean break). Phase 61
  introduces structural changes that a v1.0 consumer cannot parse safely
  (new top-level `external_inputs[]`, new `BCPort` port type, new
  `array_size`/`default_axis`/`type_union`/`input_modes`/`geom_source`/`bc_modes`
  fields). No `.streamgui` files in the wild (§3.2); only consumer is the
  GUI code in this repo, which Phase 61 rewrites in lockstep.

### External-input variable declaration (Area 1)
- **D-03:** Channel/CHF external-input variables live in a NEW top-level
  array per component: `external_inputs[]`. NOT mixed into `parameters[]`.
  `parameters[]` stays a pure constructor-kwarg list. Components with no
  external inputs (CAC, Pump, value-sources themselves, etc.) simply omit
  the `external_inputs[]` block.
  - Rationale: matches the MTK kwarg-vs-`@variable` distinction; gives the
    BCs tab a clean array to render; structural separation accomplishes the
    Properties-tab vs BCs-tab split (D-04 follows from this).
- **D-04:** No `scope` field on `parameters[]` entries. The phase-scope
  wording ("Add `scope` field per parameter") was a means to the
  Properties-tab vs BCs-tab end; D-03's structural separation accomplishes
  the same outcome more cleanly. Property panel reads `parameters[]` for
  Properties tab and `external_inputs[]` for BCs tab — `scope` would be
  redundant labeling.
- **D-05:** Each `external_inputs[]` entry has fields:
  `name`, `shape` (e.g., `"[1:n]"`), `unit`, `description`, `bc_modes`,
  `source_component`, `source_port`. `bc_modes` is the per-field-mode list
  the BCs-tab picker exposes (D-08).

### Correlation factory tree (Area 2)
- **D-06:** Keep the existing recursive `options[].sub_parameters[]` shape
  in correlation factory entries. Phase 59's geom-first refactor shortens
  the leaves; it does not flatten the recursion. `regime_dependent` still
  nests `htc_laminar` / `htc_turbulent` / `htc_natural` / `friction_laminar`
  / `friction_turbulent` sub-pickers.
- **D-07:** Add a per-factory `geom_source` field on every factory option:
  - `"geom_source": "parent"` → factory derives geometry from the parent
    channel's `geometry` Resource. Applies to `laminar_friction`,
    `elenbaas_htc`, `fully_developed_laminar_h_spl`,
    `developing_laminar_h_spl`, `regime_dependent`.
  - Stateless options (`dittus_boelter`, `constant_Nusselt`,
    `blasius_friction`, `turbulent_friction`, `maximal_htc`) carry
    `"kind": "stateless"` and no `geom_source` (no geometry to thread).
- **D-08:** Per Phase 59 handoff §3.1, the *only* remaining per-factory
  user-facing kwargs are:
  - `dittus_boelter`: none (stateless).
  - `constant_Nusselt`: `Nu` (default `8.235`).
  - `blasius_friction`: none (stateless).
  - `turbulent_friction`: `epsilon` (default `0.0`).
  - `laminar_friction`: none (`geom_source: "parent"`; no remaining kwargs).
  - `fully_developed_laminar_h_spl`: none (`geom_source: "parent"`; no
    remaining kwargs).
  - `elenbaas_htc`: `g` (default `9.81`).
  - `developing_laminar_h_spl`: `develop_length` (`required: true`,
    `no_default: true` — Phase 59 D-04 forbids silent substitution with
    `geom.L`).
  - `regime_dependent`: `htc_laminar` (req), `htc_turbulent` (req),
    `friction_laminar` (req), `friction_turbulent` (req),
    `htc_natural` (optional, FK to another factory), `g` (`required_if:
    "htc_natural"`), `Re_transition` (default `2300`).
- **D-09:** `regime_dependent` produces a NamedTuple `(htc=fn, friction=fn)`,
  but the registry lists it independently in both `htc_correlation.options`
  and `friction_correlation.options` on CAC. The two fields are NOT coupled
  in the registry — the user can pick `regime_dependent` for one and not
  the other. Each `regime_dependent` option carries
  `produces: ["htc", "friction"]`. The codegen-side dedupe rule (out of
  scope here, owned by Phase 66) detects when both fields reference
  semantically-identical `regime_dependent(...)` calls and emits a single
  `rd = regime_dependent(...)` followed by `htc_correlation=rd.htc,
  friction_correlation=rd.friction`; otherwise emits two separate factory
  calls. Registry stays simple; codegen owns the optimization.

### Polymorphic value parameters (Area 3)
- **D-10:** Constructor kwargs that accept `Real | AbstractVector{<:Real} | Function`
  use the `type_union` + `input_modes` pattern:
  - `type_union: ["Real", "Vector", "Function"]`
  - `input_modes: ["scalar", "vector", "callable"]`
  - Applies to: Channel `h_left`, Channel `h_right`, WallTemperature
    `T_wall`, HeatFluxSource `q`.
  - Property panel mode picker switches the inline editor: scalar → number
    field; vector → array editor / file import; callable → expression field
    (Julia function literal).
- **D-11:** External-input variables (BCs tab) use a DIFFERENT mode list
  from constructor kwargs:
  - `bc_modes: ["Value", "Profile", "Function", "Mark", "Source"]` per §3.11.
  - "Mark" emits a `# TODO:` comment in generated Julia; "Source" creates a
    bidirectional sync to a `WallTemperature` / `HeatFluxSource` block on
    the canvas (the dashed-edge BC connection).
  - The two mode lists are deliberately distinct because BCs-tab modes
    include things ("Mark", "Source") that don't make sense for constructor
    kwargs on the value-source itself.

### PointKinetics + ReactivityController (Area 4)
- **D-12:** Single `PointKinetics` registry entry. The `rho` field is
  polymorphic with `type_union: ["Real", "Function", "ReactivityController"]`
  and `input_modes: ["scalar", "callable", "controller"]`. The GUI mode
  picker chooses which constructor to call:
  - `scalar` → first constructor (`PointKinetics(; rho=<value>, Lambda, beta_k, lambda_k)`).
  - `callable` → second constructor with an inline callable
    (`PointKinetics(rho_c_fn; rho_val=0.0, Lambda, beta_k, lambda_k, temp_worth=nothing, ref_temp=nothing)`).
  - `controller` → second constructor with a `ReactivityController`
    Resource reference as `rho_c_fn`.
  - `temp_worth` and `ref_temp` fields appear in the Properties panel only
    when mode is `callable` or `controller`. Both are dict-shaped (per-component
    feedback weights / reference temperatures) — encode as a "mark in code"
    field for v1.2 (`type_union: ["Mark"]`), since the Dict keys are MTK
    Systems and can't be selected in JSON. Future phase can expose a
    structured editor.
- **D-13:** `ReactivityController` is a **Resource**, not a draggable
  canvas component:
  - Lives in the navigator under `Resources → Reactivity Controllers` (a
    new sibling to `Geometries` and `Power Shapes`). Navigator-tree update
    is Phase 62's concern; Phase 61 just declares it as a Resource kind in
    the registry.
  - No canvas presence, no ports, no MTK System (per source — it's a plain
    Julia struct).
  - Constructor kwargs (`input_reactivity`, `state_machine`, `abort_states`,
    `initial_state`, `initial_time`) are exposed in the property panel
    when the Resource is selected.
  - `input_reactivity` and `state_machine` are callable — use "Mark in code"
    mode in v1 (user fills the closure in the generated `.jl`); `abort_states`
    is a `Set` — also "Mark in code" for v1.
  - `initial_state` is a Symbol (Julia atom) — render as a free-text input
    that the codegen wraps with `:` prefix.
  - `initial_time` is `Real` — standard scalar field, default `0.0`.

### Port-type taxonomy + array ports (port-shape discussion)
- **D-14:** Add a new GUI-only port type `BCPort`. **Registry-side tag
  only**: no `src/` change, no MTK connector type. The underlying binding
  remains a plain `@variable` equality (`ch.T_wall_left[i] ~ wt.T_wall_out[i]`).
  `BCPort` exists so the registry can describe:
  - The output handle on `WallTemperature` / `HeatFluxSource` block icons.
  - The dashed-edge rendering style (§3.11).
  - The validation hard-blocks (`BCPort(T_wall) → CHF.q_*` rejected at
    connect time — the source-port type and the consumer field semantics
    are mismatched).
- **D-15:** Channel / CHF have NO BCPort entry on their side. The dashed
  edge connects from the value-source's `BCPort` directly onto the
  Channel/CHF block body (§3.11: "no permanent BC-inlet handle on the
  canvas"). The bindable target is declared via `external_inputs[].source_component`
  and `external_inputs[].source_port`.
- **D-16:** Array-shaped logical ports gain two new fields:
  - `array_size: "n"` — string-valued; references the `n` parameter on the
    same component (validation: `array_size`'s referent must exist in
    `parameters[]`).
  - `default_axis: "horizontal" | "vertical"` — drives §3.4 autoflip
    default. CAC `thermal_left` / `thermal_right`: `default_axis: "vertical"`.
    HD `thermal_left` / `thermal_right`: `default_axis: "horizontal"`.
    Value-source `T_wall_out` / `q_out`: `default_axis: "horizontal"` with
    static `side: "right"` (single output handle).
- **D-17:** Pair-related thermal ports declare a `pair_with` field
  pointing to the opposing port's name (e.g., CAC's `thermal_left` has
  `pair_with: "thermal_right"`). This lets the GUI's autoflip code lock
  the pair to opposite faces of the icon (§3.4 invariant: thermal ports
  always come as opposing pairs).

### Channel-family port deltas (concrete)
- **D-18:** `Channel` ports list becomes:
  ```
  [{name: port_in,  type: FlowPort, side: left},
   {name: port_out, type: FlowPort, side: right}]
  ```
  (drop the old `thermal` port).
- **D-19:** `ChannelHeatFlux` ports list is identical to `Channel`'s
  (FlowPort in/out only).
- **D-20:** `ChannelAndContacts` ports list becomes:
  ```
  [{name: port_in,        type: FlowPort,    side: left},
   {name: port_out,       type: FlowPort,    side: right},
   {name: thermal_left,   type: ThermalPort, array_size: "n",
                          default_axis: vertical, pair_with: thermal_right},
   {name: thermal_right,  type: ThermalPort, array_size: "n",
                          default_axis: vertical, pair_with: thermal_left}]
  ```
- **D-21:** `HeatDiffusion` ports list gets the `array_size` / `default_axis` /
  `pair_with` treatment:
  ```
  [{name: thermal_left,   type: ThermalPort, array_size: "n",
                          default_axis: horizontal, pair_with: thermal_right},
   {name: thermal_right,  type: ThermalPort, array_size: "n",
                          default_axis: horizontal, pair_with: thermal_left}]
  ```
  (HD has no FlowPorts; its other internal cell structure stays internal.)

### Claude's Discretion
- **CD-01:** For factories with zero remaining user-facing kwargs after
  Phase 59 (e.g., `laminar_friction`, `fully_developed_laminar_h_spl`),
  the registry uses `"kind": "factory"`, `"geom_source": "parent"`, and
  omits `sub_parameters` entirely (or includes `sub_parameters: []`).
  Tooling reads "factory with no remaining kwargs" as "emit
  `name(geom)`" at codegen time. Decided to omit the empty array for
  JSON cleanliness.
- **CD-02:** `WallTemperature` and `HeatFluxSource` icons are mentioned in
  §3.11 but visual specifics ("hollow square or open-chevron in a neutral
  color, or the new accent color for the Sources/BCs layer") are §3.8 /
  Phase 8 (design system phase). Phase 61's registry just declares
  `category: "Sources"` and `port_type: "BCPort"`; the icon SVG itself is
  Phase 8 / 68 territory.
- **CD-03:** For Channel's `friction_correlation` field, the available
  options are the union of stateless friction functions and geom-bearing
  friction factories (`blasius_friction`, `turbulent_friction`,
  `laminar_friction`). Since Channel has no `htc_correlation` (D-18),
  `regime_dependent` is NOT a legal option on Channel's
  `friction_correlation` — `regime_dependent` produces both htc and
  friction in a bundle, and there's no htc consumer on Channel. The
  registry encodes this by simply not listing `regime_dependent` in
  Channel's `friction_correlation.options`.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Design contract for v1.2 GUI redesign
- `.planning/notes/gui-redesign-design-decisions.md` §3.1 — Correlation
  geom-first convention (factory parameter shapes after Phase 59).
- `.planning/notes/gui-redesign-design-decisions.md` §3.2 — Resources Panel
  + foreign-key model + navigator tree (informs ReactivityController as a
  Resource).
- `.planning/notes/gui-redesign-design-decisions.md` §3.4 — Thermal port
  autoflip behavior (`default_axis` field source).
- `.planning/notes/gui-redesign-design-decisions.md` §3.10 — Three explicit
  channel variants + Properties-tab vs BCs-tab separation rule.
- `.planning/notes/gui-redesign-design-decisions.md` §3.11 — BCs tab + value-source components +
  dashed-edge BC connection + connection-time hard-blocks.

### Phase 59 / 60 handoff artifacts (mandatory reads)
- `.planning/notes/correlation-geom-first-api.md` — Post-Phase-59
  correlation API surface; concrete kwargs remaining per factory; trust-the-user
  posture; example construction. Phase 61's `htc_correlation` /
  `friction_correlation` shape derives directly from this.
- `.planning/notes/fuel-assembly-api.md` — Post-Phase-60 helper signature +
  GUI topology-detection rule. Phase 61's `codeGenerator.ts` work consumes
  this; registry itself does NOT declare `fuel_assembly` as a component.

### Source-of-truth references for component shapes
- `src/components/channels.jl` — Channel, ChannelHeatFlux, ChannelAndContacts
  constructor signatures and external-input `@variables`. Lines 199–311
  (Channel), 357–~460 (CHF), 467–~620 (CAC).
- `src/components/sources.jl` — WallTemperature and HeatFluxSource (lines
  1–110). `T_wall_out[1:n]` and `q_out[1:n]` output shapes confirmed.
- `src/components/point_kinetics.jl` — `PointKinetics(; rho, ...)` (line 78)
  and `PointKinetics(rho_c_fn::Any; rho_val, ..., temp_worth, ref_temp)`
  (line 214). `ReactivityController` struct + constructor (lines ~370–422)
  + `worth` / `change_state` methods.
- `src/STREAM.jl` — Public exports (lines 32–102). Authoritative list of
  what should appear in the registry as components.
- `src/physical_models/htc/correlations.jl` — Source of factory functions
  + remaining kwargs.
- `src/physical_models/friction/correlations.jl` — Same for friction.

### Existing registry (the target of the rewrite)
- `gui/src/registry/components.json` — 910 lines, `stream_version: 0.7.0`,
  12 components. This is what Phase 61 rewrites end-to-end.
- `gui/src/registry/types.ts` — TypeScript types for the registry shape;
  must be updated in lockstep with the JSON schema bump (D-02).
- `gui/src/registry/index.ts` — Loader / accessor surface; check for
  consumer code that assumes old shape.
- `gui/src/registry/__tests__/` — Existing tests; update or rewrite to
  match new schema.

### Project policy
- `CLAUDE.md` — Branching policy (working branch `gui-redesign`, no
  GSD-created branches); MTK patterns; daemon dev loop conventions.
- `.planning/PROJECT.md` — v1.2 milestone framing.
- `.planning/STATE.md` — Working branch confirmation
  (`gui-redesign`), open PR context (#15 → main, not a blocker for this
  phase since v1.1 is already in `gui-redesign`).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `gui/src/registry/components.json` (current, 910 lines): keep the
  overall envelope (`stream_version`, `schema_version`, `components[]`);
  replace the body. Most components (Pump, Friction, Gravity, Resistor,
  Inertia, HeatExchanger, ConstantTemperature, Flapper) have unchanged
  surfaces under v1.1 — their entries need only a `parameters[]`
  re-audit against current source (no functional rewrite).
- `gui/src/registry/types.ts`: existing TypeScript discriminated unions
  give a starting point for the new schema; new fields (`external_inputs`,
  `type_union`, `input_modes`, `bc_modes`, `geom_source`, `array_size`,
  `default_axis`, `pair_with`, `produces`) plug into the same pattern.
- `gui/src/registry/__tests__/`: existing test infrastructure (Vitest) —
  Phase 61 should add validation tests for the new schema shape (e.g.,
  every `array_size: "n"` references an existing `n` parameter; every
  `pair_with` resolves to a sibling port; every `external_inputs[].source_component`
  resolves to a registered component).

### Established Patterns
- **Recursive `options[].sub_parameters[]`** — the existing factory
  representation pattern; carries forward (D-06).
- **`required` + `positional` boolean pair** on every parameter — unchanged.
- **Port `name` / `type` / `side` triple** — extended with `array_size` /
  `default_axis` / `pair_with` for v1.1 array ports (D-16, D-17).
- **String-valued enums** (e.g., `category: "Hydraulic"`) — adopt for new
  enums (`bc_modes`, `input_modes`, `kind`, `geom_source`).

### Integration Points
- `gui/src/components/PropertyPanel.tsx` (or equivalent) consumes
  `parameters[]` and (new) `external_inputs[]` — Phase 63 builds the
  two-tab UI. Phase 61 only ships the data shape.
- `gui/src/lib/codeGenerator.ts` consumes the registry to emit Julia.
  Phase 61 ships the registry; Phase 66 reworks the codegen to use
  `external_inputs[].source_port` / `regime_dependent.produces` / etc.
  Phase 61's responsibility is keeping codegen *building* against the new
  schema, even if it doesn't yet use the new fields meaningfully.
- `gui/src/components/HydraulicEdge.tsx` / `ThermalEdge.tsx` — Phase 64
  adds a `BCEdge.tsx` for the dashed BC edge. Phase 61 declares the new
  port type; the edge component is Phase 64.
- Connection validation hooks consume the new port-type taxonomy +
  `external_inputs[].source_component` allowlist — Phase 71 owns the
  validation framework; Phase 61 declares the data the framework will
  read.

</code_context>

<specifics>
## Specific Ideas

- **Top-level `external_inputs[]` example shape** (locked via D-03 / D-05):
  ```json
  {
    "id": "Channel",
    "parameters": [
      {"name": "n", "type": "Int", "required": true, "positional": false},
      {"name": "geometry", "type": "PipeGeometry", "required": true, ...},
      {"name": "g", "type": "Real", "default": 0.0, ...},
      {"name": "h_left",  "type_union": ["Real","Vector","Function"],
                          "input_modes": ["scalar","vector","callable"],
                          "default": 0.0, "unit": "W/(m^2 K)", ...},
      {"name": "h_right", "type_union": ["Real","Vector","Function"],
                          "input_modes": ["scalar","vector","callable"],
                          "default": 0.0, "unit": "W/(m^2 K)", ...},
      {"name": "friction_correlation", "type": "Function",
                          "default": "blasius_friction", "options": [...]}
    ],
    "external_inputs": [
      {"name": "T_wall_left", "shape": "[1:n]", "unit": "K",
       "description": "Per-cell left-wall temperature BC",
       "bc_modes": ["Value","Profile","Function","Mark","Source"],
       "source_component": "WallTemperature",
       "source_port": "T_wall_out"},
      {"name": "T_wall_right", "shape": "[1:n]", "unit": "K",
       "description": "Per-cell right-wall temperature BC",
       "bc_modes": ["Value","Profile","Function","Mark","Source"],
       "source_component": "WallTemperature",
       "source_port": "T_wall_out"}
    ],
    "ports": [
      {"name": "port_in",  "type": "FlowPort", "side": "left"},
      {"name": "port_out", "type": "FlowPort", "side": "right"}
    ]
  }
  ```

- **Factory tree example shape** (locked via D-06 / D-07 / D-08):
  ```json
  {
    "name": "htc_correlation",
    "type": "Function",
    "default": "dittus_boelter",
    "options": [
      {"value": "dittus_boelter", "kind": "stateless"},
      {"value": "constant_Nusselt", "kind": "stateless",
       "sub_parameters": [{"name": "Nu", "type": "Real", "default": 8.235}]},
      {"value": "elenbaas_htc", "kind": "factory", "geom_source": "parent",
       "sub_parameters": [{"name": "g", "type": "Real", "default": 9.81, "unit": "m/s^2"}]},
      {"value": "developing_laminar_h_spl", "kind": "factory", "geom_source": "parent",
       "sub_parameters": [{"name": "develop_length", "type": "Real",
                           "required": true, "no_default": true, "unit": "m"}]},
      {"value": "fully_developed_laminar_h_spl", "kind": "factory", "geom_source": "parent"},
      {"value": "regime_dependent", "kind": "factory", "geom_source": "parent",
       "produces": ["htc", "friction"],
       "sub_parameters": [
         {"name": "htc_laminar",        "type": "Function", "required": true, "options": [...]},
         {"name": "htc_turbulent",      "type": "Function", "required": true, "options": [...]},
         {"name": "friction_laminar",   "type": "Function", "required": true, "options": [...]},
         {"name": "friction_turbulent", "type": "Function", "required": true, "options": [...]},
         {"name": "htc_natural",        "type": "Function", "required": false, "options": [...]},
         {"name": "g",                  "type": "Real", "required_if": "htc_natural"},
         {"name": "Re_transition",      "type": "Real", "default": 2300}
       ]}
    ]
  }
  ```

- **ChannelAndContacts thermal port shape** (locked via D-16 / D-17 / D-20):
  ```json
  "ports": [
    {"name": "port_in",       "type": "FlowPort",    "side": "left"},
    {"name": "port_out",      "type": "FlowPort",    "side": "right"},
    {"name": "thermal_left",  "type": "ThermalPort", "array_size": "n",
                              "default_axis": "vertical", "pair_with": "thermal_right"},
    {"name": "thermal_right", "type": "ThermalPort", "array_size": "n",
                              "default_axis": "vertical", "pair_with": "thermal_left"}
  ]
  ```

- **WallTemperature shape sketch** (locked via D-10 / D-14 / D-16):
  ```json
  {
    "id": "WallTemperature",
    "label": "Wall Temperature",
    "category": "Sources",
    "parameters": [
      {"name": "n", "type": "Int", "required": true},
      {"name": "T_wall",
       "type_union": ["Real","Vector","Function"],
       "input_modes": ["scalar","vector","callable"],
       "unit": "K", "required": true}
    ],
    "ports": [
      {"name": "T_wall_out", "type": "BCPort",
       "array_size": "n", "side": "right", "default_axis": "horizontal"}
    ]
  }
  ```

- **PointKinetics + ReactivityController shape sketch** (locked via D-12 / D-13):
  ```json
  {
    "id": "PointKinetics",
    "label": "Point Kinetics",
    "category": "Reactor Physics",
    "parameters": [
      {"name": "rho",
       "type_union": ["Real","Function","ReactivityController"],
       "input_modes": ["scalar","callable","controller"],
       "default": 0.0, "required": false},
      {"name": "Lambda", "type": "Real", "default": "U235_LAMBDA"},
      {"name": "beta_k", "type": "Vector", "default": "U235_BETA_K"},
      {"name": "lambda_k", "type": "Vector", "default": "U235_LAMBDA_K"},
      {"name": "temp_worth", "type_union": ["Mark"],
       "visible_when": "rho.input_mode in ['callable','controller']"},
      {"name": "ref_temp",   "type_union": ["Mark"],
       "visible_when": "rho.input_mode in ['callable','controller']"}
    ],
    "ports": []
  }

  {
    "id": "ReactivityController",
    "label": "Reactivity Controller",
    "category": "Resources",
    "resource_kind": "reactivity_controller",
    "parameters": [
      {"name": "input_reactivity", "type_union": ["Mark"]},
      {"name": "state_machine",    "type_union": ["Mark"]},
      {"name": "abort_states",     "type_union": ["Mark"]},
      {"name": "initial_state",    "type": "Symbol", "default": ":NORMAL"},
      {"name": "initial_time",     "type": "Real",   "default": 0.0}
    ]
  }
  ```

</specifics>

<deferred>
## Deferred Ideas

- **Connection-rule validation table** (Phase 71). Phase 61 declares the
  data (`source_component` allowlist, `BCPort` type tag, `pair_with`
  invariant) that the Phase 71 validation framework will read. The
  framework itself is out of scope here.
- **`gui/src/lib/codeGenerator.ts` rewrite** (Phase 66 owns the codegen
  rework; Phase 60 handoff specifies the `fuel_assembly` detection rule,
  which Phase 61's `codeGenerator.ts` portion implements). The
  `regime_dependent` dedupe rule (D-09) lives in codegen, not the
  registry — defer to Phase 66.
- **Resources Panel navigator UI** (Phase 62 owns it). Phase 61 declares
  `ReactivityController` as a Resource kind; the navigator tree node for
  `Resources → Reactivity Controllers` is Phase 62's work.
- **BCs tab UI** (Phase 63 owns it). Phase 61 declares the
  `external_inputs[]` data and `bc_modes` enum; Phase 63 builds the mode
  picker, the bidirectional sync between dropdown and canvas edge, etc.
- **Dashed BC-edge rendering + autoflip routing** (Phase 64 owns them).
  Phase 61 declares `BCPort` and `default_axis` / `pair_with` data;
  Phase 64 implements the visual.
- **Structured editor for PointKinetics `temp_worth` / `ref_temp` dicts.**
  v1.2 punts to "mark in code" — user fills the dict in the generated
  `.jl`. A future GUI phase can expose a per-component-row table.
- **Icon SVGs for new components** (WallTemperature, HeatFluxSource,
  PointKinetics, ReactivityController). Phase 8/68 design-system territory;
  Phase 61 just declares the components exist in the registry.
- **User-defined correlation Resources** (mentioned as a possible future
  evolution of the factory tree per Area-2 option B; not in v1.2 scope).

</deferred>

---

*Phase: 61-Registry audit + rewrite for v1.1*
*Context gathered: 2026-05-12*
