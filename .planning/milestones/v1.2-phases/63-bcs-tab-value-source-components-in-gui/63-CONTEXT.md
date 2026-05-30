# Phase 63: BCs tab + value-source components in GUI - Context

**Gathered:** 2026-05-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Land the GUI side of the v1.1 channel-family external-input model. Phase 61
already shipped the registry shape (`external_inputs[]`, `bc_modes`,
`source_component`, `BCPort` port type) and Phase 62 reserved the empty
Sources toolbox category. Phase 63 ships the user-visible mechanism:

**In scope:**

- **Properties tab vs BCs tab split** in the right Properties panel for
  components that declare `external_inputs[]` in the registry (today:
  `Channel`, `ChannelHeatFlux`). Tab strip rendered **below** the
  instance-name + component-badge header; `[Properties] [BCs]`. Active tab
  resets to `Properties` on every selection change (predictable; Properties
  is the higher-frequency tab). Components without `external_inputs[]` show
  Properties only — no tab strip, no BCs tab (§3.10 hard rule).
- **CAC has NO BCs tab** (§3.10) — its wall conditions arrive exclusively
  via the ThermalPort connections to a Plate. Already a hard rule; Phase 63
  honors it by checking `external_inputs.length === 0`.
- **Per-field BC mode picker — 5-pill segmented control** matching the
  existing `ModeToggle.tsx` idiom (used today for Pump constructor-mode
  selection). Row of buttons: `[Value] [Profile] [Function] [Mark] [Source]`.
  Editor renders below the row based on the active pill.
- **Field-pair layout — symmetric-by-default with asymmetric toggle.**
  Channel has `T_wall_left[1:n]` and `T_wall_right[1:n]`; CHF has
  `q_left[1:n]` and `q_right[1:n]`. BCs tab starts with a top-level
  `Symmetric (L = R)` toggle ON: one mode picker + one editor, code-gen
  emits to both. Toggle OFF expands to two stacked field blocks (per-side
  mode pickers + editors). Mirrors the canvas BC edge `:both` default with
  `:left` / `:right` overrides (§3.11).
- **Required-unset default state for BC fields on a brand-new Channel.**
  No mode is selected; the 5-pill segmented control has no active pill;
  inline `BC required — select a mode` hint in muted-destructive text.
  Code-gen for an unset BC emits a TODO marker + NO binding equation.
  Phase 71 will own the gates-code-gen-export validation rule; Phase 63
  ships the visual unset state and the no-equation-emission behavior.
  Matches Phase 62's `unset` sentinel pattern for Power Shape and the
  engineering-tool 'don't silently default to a wrong value' ethos.
- **Five BC modes (per §3.11):**
  - **Value** — single scalar `Real` input. Code-gen:
    `[ch.T_wall_left[i] ~ <value> for i in 1:n]...`
  - **Profile** — preset profile picker (v1: **axial cosine only**) or
    import-from-file (CSV). Cosine params: `amplitude` and `peaking_factor`.
    Imports use the new `rebin_intensive` helper (D-13). Code-gen for
    cosine: a STREAM helper call (e.g., `cosine_T_wall_profile(n; amplitude,
    peaking_factor)`); planner finalizes exact signature + name.
  - **Function** — stub-and-edit-in-code pattern. BCs-tab editor is minimal:
    a signature picker `[fn(t)] [fn(t, i)]` (time-only vs time + cell index)
    + auto-generated function name (e.g., `T_wall_left_fn`). Code-gen emits
    a `# TODO: define ...` stub function + the binding equation
    `[ch.T_wall_left[i] ~ T_wall_left_fn(t, i) for i in 1:n]...`. User
    edits the function body in the generated `.jl`. GUI does NOT host an
    inline code editor — engineering-tool restraint; visible in code, not
    hidden in GUI.
  - **Mark in code** — no editor; code-gen emits a `# TODO: set
    ch.T_wall_left[i] here` comment at the appropriate place + no binding
    equation. User edits manually.
  - **Source (Driven by source block)** — dropdown of available
    `WallTemperature` blocks on the canvas (for `T_wall_*`) or
    `HeatFluxSource` blocks (for `q_*`). Selection creates the dashed BCPort
    canvas edge. If NO source blocks of the right kind exist, the dropdown
    shows an inline `+ New WallTemperature` (or `+ New HeatFluxSource`)
    button — clicking it spawns the source block on canvas (auto-positioned
    left of the consumer, smart-name `wall_temperature_<lowest-free-integer>`),
    auto-selects it in the picker, creates the dashed edge.
- **`WallTemperature` and `HeatFluxSource` toolbox entries — first-class
  draggables in the `Sources` category.** Registry entries already exist
  (Phase 61). Phase 63 enables them in the toolbox (Phase 62 left them as
  an empty category placeholder per D-30).
- **Source block visual idiom:**
  - **Block shape:** standard `StreamNode` rectangle (same chrome as
    Pump / Channel / etc.) — consistent layout discipline; no special card
    chrome.
  - **BCPort handle:** small hollow square (no fill, 1.5px stroke,
    `var(--muted-foreground)` color) on the right side of the block.
    Distinct from filled-circle FlowPort and chain-link-circle ThermalPort.
    Matches §3.11 'proposed: hollow square in a neutral color.'
  - **Label content:** two-line. Top = instance name (e.g., `wt_inlet`).
    Bottom = mode-aware compact value:
      - `Real (scalar)`:   `T_wall = 320 K`
      - `Vector`:          `T_wall = vector (n=10)`
      - `Function`:        `T_wall = fn(t)`
      - `Required-unset`:  `T_wall = (unset)` in muted-destructive.
    Truthful about complex values without false precision.
- **Dashed BCPort edge style** — distinct from solid FlowPort/ThermalPort
  edges:
    - `stroke = var(--muted-foreground)`
    - `strokeWidth = 1.5`
    - `strokeDasharray = '6 3'`
  - Theme-aware (works under both light and dark mode per Phase 998.1).
  - Phase 72 design-system audit can override without code surgery.
- **Inline click-to-cycle target-side chip on each BC edge.** Default
  `:both`. Chip renders mid-edge showing `L+R` / `L` / `R`. Click cycles
  `L+R → L → R → L+R`. Always visible — side is part of the edge's
  identity, not a hidden property. Self-documenting; no right-click needed
  to discover. Matches §3.11 'small inline label on the edge.'
- **Whole-component drop zone for BCPort drag.** Channels deliberately
  have NO visible BC handle (§3.11: 'Channels remain visually clean').
  Drop target is the Channel node's whole body, activated only while a
  drag originates from a `BCPort` output. On mouse-enter: faint dashed
  outline on the body + `Connect BC` chip. Release: dashed edge created
  with `:both` default. Implementation = ReactFlow custom-node drop
  target overlay; well within ReactFlow extensibility.
- **Type-checking at connection time — hard-block (§3.11):**
  - `WallTemperature.T_wall_out → Channel.T_wall_*` — ALLOWED.
  - `HeatFluxSource.q_out → ChannelHeatFlux.q_*` — ALLOWED.
  - `WallTemperature.T_wall_out → ChannelHeatFlux` — HARD-BLOCKED (different
    physical quantity). Edge shakes + red toast.
  - `HeatFluxSource.q_out → Channel` — HARD-BLOCKED.
  - `*.x_out → ChannelAndContacts.*` — HARD-BLOCKED (CAC has no BCs tab;
    wall conditions come via ThermalPort only).
- **Soft warning for n-mismatch at connect time.** `WallTemperature.n = 10`
  connecting to `Channel.n = 12`: connection IS created. Red-ring marker
  on both nodes (§3.9 'red-ring markers on offending nodes'). The BCs tab
  field and the source block show red-text hint: `n mismatch:
  WallTemperature.n = 10, Channel.n = 12`. Code-gen still emits the
  equations — they will error at compile time, with the error visible in
  the generated `.jl`. NO inline lossless-sync action button in Phase 63
  (that's Phase 71's validation framework with action buttons). Matches
  §3.11 'same UI shape as the z_N rule.'
- **Bidirectional sync between BCs tab and canvas BC edge (§3.11).**
  Setting a BCs-tab field's mode to `Source: wt_1` creates the canvas
  dashed edge automatically (using whole-body drop target programmatically).
  Deleting the canvas edge reverts the BCs tab field to its prior mode
  (or back to required-unset if none). Two views of the same fact, never
  out of sync. Implementation: a single source-of-truth in the store
  (`bcMode: { field, mode, params }` per node × external_input), with both
  the BCs tab editor and the edge renderer subscribed to it.
- **`rebin_intensive` helper in `src/utilities.jl` (NEW).** Symmetric
  companion to Phase 62's `rebin_extensive`:
  - **Sum-conserving (extensive)** — `rebin_extensive` (Phase 62) for
    `power_shape`.
  - **Area-weighted-mean-conserving (intensive)** — `rebin_intensive`
    (Phase 63) for `T_wall`, `q` heat-flux, and any other intensive
    quantity.
  - Same separable area-weighted-overlap algorithm; intensive version
    normalizes by target cell size. `∫ T dA` ≈ preserved.
  - Signatures: `rebin_intensive(vec::AbstractVector, n_target::Int)` and
    `rebin_intensive(mat::AbstractMatrix, target_shape::Tuple{Int,Int})`.
    2D version added for symmetry with `rebin_extensive` and forward
    compatibility (cost: ~5 extra lines + a few extra test cases).
  - Code-gen for Profile-mode imports emits:
    `T_wall_left_<name> = rebin_intensive(readdlm(joinpath(@__DIR__, "shapes/inlet.csv"), ','), n)`
  - Public, exported from `STREAM.jl`. Tested in `test/test_utilities.jl`
    for area-weighted-mean conservation across upsampling / downsampling /
    non-integer-ratio / identity cases.
  - Caller-trust posture per `feedback_power_shape_trust_caller.md` — call
    is visible in generated code, not hidden in GUI.
- **`Sources` toolbox category fully wired.** Phase 62 reserved an empty
  Sources category in the Components tab; Phase 63 lands the two registry
  entries (`WallTemperature`, `HeatFluxSource`) as draggable toolbox items
  with the smart-name-increment naming (`wall_temperature_<n>`,
  `heat_flux_source_<n>`).

**Out of scope:**

- **Validation framework + lossless-sync action buttons.** Phase 71 owns
  the formal validator registry, the action-button shape (Sync n,
  value-transfer-picker, lossless-sync), and the gates-code-gen-export
  rules. Phase 63 ships the visual unset state (red-flagged inline hint)
  and the n-mismatch red-ring + red-text hint, but NOT the inline
  remediation action buttons. Code-gen for unset BCs still emits the
  TODO marker (no equation); compile-time errors are the failure mode in
  v1.2 until Phase 71 closes the loop.
- **Phase 71 z_N / length matching across channel ↔ HD coupling.** Same
  Phase-71 boundary. Phase 63 mirrors `n`-mismatch UX shape only.
- **Fate of the existing `BottomPanel` BCs tab (pressure anchors).**
  Phase 63 leaves it UNCHANGED. The two BC mechanisms coexist with a
  clean semantic boundary:
    - Per-component BCs tab (right panel) — `external_input` variables
      (T_wall, q). The Phase 63 work.
    - BottomPanel BCs tab — pressure-anchor equations on derived port
      state (e.g., `pump_1.port_in.P ~ 1.0e5`).
  These are mathematically different objects (declared unknowns vs
  derived-state anchor equations). Future consolidation (e.g., pressure
  anchors as FlowPort-property metadata) belongs in Phase 65 or a
  follow-up, not Phase 63.
- **Multiple presets beyond axial cosine.** Profile mode ships axial
  cosine only in v1. Imports cover the rest. Linear / hot-spot /
  chopped-cosine deferred until a real workflow asks.
- **Inline Julia code editor in the GUI for Function mode.** Out of scope
  by design (stub-and-edit-in-code chosen instead).
- **Function Resource kind in the Resources tab.** Out of scope. The
  Phase-62 Resource pattern is for things that have a name and parameters
  (Geometry, Power Shape). Function bodies live in the generated `.jl`
  via the stub-and-edit-in-code pattern.
- **Bidirectional `select-on-canvas → highlight-in-BCs-tab` interaction.**
  The sync goes BCs-tab → canvas (changing mode creates/deletes edge) and
  canvas → BCs-tab (deleting edge reverts mode). Highlighting the
  corresponding BCs-tab pill when the user just-clicked a BC edge on the
  canvas is a nice-to-have but not core; planner judges if it's worth
  including or deferring to Phase 65 / Phase 72.
- **Connection routing autoflip + asymmetric same-side placement + thermal
  pair axis-flip + anti-parallel offset.** Phase 64.
- **Interaction model overhaul** (marquee selection, right-pan, edge
  deletion via Del/Backspace, copy/paste/cut/duplicate with smart-name,
  snap-to-grid, AutoRecover). Phase 65.
- **Code preview rework with `CodeSection[]` + source-UUID tracking.**
  Phase 66. Phase 63 keeps the flat-string emit shape and just updates
  the content emitted for BC modes.
- **Layers system overhaul** (four-layer taxonomy, floating chip,
  hide-vs-dim setting, off-layer locked). Phase 68. Phase 63 leaves the
  existing layer state unchanged.
- **Design system + Sources-layer accent palette.** Phase 72 finalizes
  the accent colors for the Sources / Reactor Physics layers. Phase 63
  uses `muted-foreground` for the BCPort hollow-square handle and the
  dashed edge as a neutral placeholder.
- **Chain-link connected/unconnected ThermalPort icons.** Per user-list
  item, deferred to Phase 72 design-system pass.

</domain>

<decisions>
## Implementation Decisions

### BCs tab visual structure
- **D-01:** Tab strip `[Properties] [BCs]` renders BELOW the instance-name +
  component-badge header in the right Properties panel. Header identifies
  WHICH component you're editing once; tabs switch what aspect you edit.
- **D-02:** Tab visibility is driven by the registry: components with
  `external_inputs.length === 0` show Properties only (no tab strip, no
  BCs tab). Today: only `Channel` and `ChannelHeatFlux` have an
  `external_inputs` declaration — all other components, including `CAC`,
  remain single-tab. Honors §3.10 hard rule.
- **D-03:** Active tab resets to `Properties` on EVERY selection change.
  Predictable: panel always opens in the same state. Properties is the
  higher-frequency tab (constructor kwargs are everyday edits; BCs are
  one-time setup per component). No per-component or global tab memory.
- **D-04:** Per-field BC mode picker = 5-pill segmented control matching
  the existing `ModeToggle.tsx` idiom. Order:
  `[Value] [Profile] [Function] [Mark] [Source]`. Editor renders below
  the row based on the active pill. Brand-new Channel: no pill is active
  (required-unset state, D-09).
- **D-05:** Field-pair layout = symmetric-by-default with asymmetric
  toggle. Top of the BCs tab: `Symmetric (L = R)` toggle, default ON.
    - ON: one mode picker + one editor; code-gen emits to BOTH sides.
    - OFF: expands to two stacked field blocks
      (`T_wall_left[1:n]` header + picker + editor, separator,
      `T_wall_right[1:n]` header + picker + editor).
  Mirrors the canvas BC edge `:both` default with `:left` / `:right`
  overrides.

### BC mode mechanics
- **D-06:** Profile mode v1 ships exactly ONE preset: axial cosine.
  Params: `amplitude` (Real) and `peaking_factor` (Real). Code-gen emits
  a STREAM helper call; planner picks the exact helper name + signature
  (likely lives in `src/utilities.jl` near `rebin_intensive` and
  `cosine_power_shape` if not already there). Imports (file mode within
  Profile) cover anything else.
- **D-07:** Profile-mode 'import from file' uses **`rebin_intensive`**
  (NEW helper, D-13). Imported CSV does NOT need to match the consumer's
  `n` — the helper area-weighted-mean rebins onto the consumer's `n` at
  script runtime. Mirrors Phase 62's `rebin_extensive` story for
  `file_loaded` Power Shapes but with the intensive-quantity conservation
  law. Caller-trust posture: call is visible in generated code, not
  hidden in GUI.
- **D-08:** Function mode = stub-and-edit-in-code pattern.
  - BCs-tab editor: signature picker `[fn(t)] [fn(t, i)]` (time-only vs
    time + cell index) + auto-generated function name field (default:
    `<component_name>_<field_name>_fn`, e.g., `ch1_T_wall_left_fn`).
  - Code-gen emits a stub `T_wall_left_fn(t, i) = ...  # TODO: define
    your time-varying boundary condition` plus the binding equation
    `[ch1.T_wall_left[i] ~ T_wall_left_fn(t, i) for i in 1:n]...`.
  - User edits the function body in the generated `.jl`. GUI does NOT
    host an inline code editor (engineering-tool restraint).
- **D-09:** Default state on a brand-new Channel = **required-unset**.
  Neither `T_wall_left` nor `T_wall_right` has an active mode pill. The
  segmented control renders all 5 pills as outline-variant (none active),
  plus an inline hint in muted-destructive text:
  `BC required — select a mode`. Code-gen for an unset BC emits a
  `# TODO: set <field> on <component> here` comment + NO binding equation.
  Phase 71 owns the gates-code-gen-export rule for unset BCs; Phase 63
  ships only the visual unset state + no-equation emission. Matches
  Phase 62's `unset` Power Shape sentinel pattern.

### Canvas BC connection mechanics
- **D-10:** Drop target for `BCPort → Channel` drag = whole-component
  drop zone on the Channel/CHF node. While a drag originates from a
  `BCPort` output (and ONLY then), the consumer node's body becomes a
  hit-testable drop target. On mouse-enter: faint dashed outline on the
  body + small `Connect BC` chip. Release: dashed BCPort edge created
  with `target_side = :both` default. Implementation = ReactFlow
  custom-node drop overlay; activated only by BCPort drags (filtered by
  source-port type to avoid colliding with FlowPort / ThermalPort
  drops).
- **D-11:** Target-side picker on each BC edge = inline click-to-cycle
  chip. Renders mid-edge with label `L+R` (default) / `L` / `R`. Click
  cycles `L+R → L → R → L+R`. Always visible — side is part of the
  edge's identity, not a hidden property. NO right-click menu in Phase
  63 (right-click is owned by Phase 65 interaction-model overhaul).
- **D-12:** Dashed BCPort edge style:
  - `stroke = var(--muted-foreground)`
  - `strokeWidth = 1.5`
  - `strokeDasharray = '6 3'`
  Theme-aware (light + dark). Phase 72 can override centrally without
  code surgery.

### `rebin_intensive` helper (NEW in src/)
- **D-13:** New public helper `rebin_intensive` in
  `src/utilities.jl` (the file already created in Phase 62 for
  `rebin_extensive`). Both 1D and 2D signatures:
  - `rebin_intensive(vec::AbstractVector, n_target::Int) -> Vector`
  - `rebin_intensive(mat::AbstractMatrix, target_shape::Tuple{Int,Int}) -> Matrix`
  Same separable area-weighted-overlap algorithm as `rebin_extensive`;
  intensive version normalizes by target cell size. `∫ T dA` ≈ preserved
  to floating-point precision. 1D-only would suffice for Phase 63 BCs,
  but 2D is added now for symmetry with `rebin_extensive` (forward
  compatibility with future intensive-field imports for HeatDiffusion
  initial conditions, multi-material work per
  `project_future_multi_material.md`).
- **D-14:** Public export from `STREAM.jl` (`export rebin_intensive`)
  per CLAUDE.md exports rule.
- **D-15:** Tests in `test/test_utilities.jl` (added in Phase 62 for
  `rebin_extensive`): mean-conservation across upsampling / downsampling /
  non-integer-ratio / identity cases. Cross-check with `rebin_extensive`
  symmetric property: `rebin_intensive(x, n) == rebin_extensive(x .* dx_src, n) ./ dx_tgt`
  (or equivalent formulation; planner decides exact assertion).
- **D-16:** Caller-trust posture — Profile-mode import code-gen emits the
  call inline; rebin runs at script runtime, not at GUI codegen time:
  ```julia
  T_wall_left_inlet = rebin_intensive(
      readdlm(joinpath(@__DIR__, "shapes/inlet_T.csv"), ','),
      n,
  )
  ```
  No GUI 'file size mismatch' error; no validation rule needed; user can
  edit the CSV and re-run without re-opening the Composer.

### Source block visual + behavior
- **D-17:** `WallTemperature` / `HeatFluxSource` block on the canvas =
  standard `StreamNode` rectangle (same chrome as Pump / Channel / etc.).
  No special card variant in Phase 63. Phase 72 design-system audit can
  introduce Sources-layer accent treatment without restructuring the
  node renderer.
- **D-18:** `BCPort` handle visual = small hollow square (no fill, 1.5px
  stroke, `var(--muted-foreground)` color) on the right side of the
  block. Distinct from filled-circle FlowPort and chain-link-circle
  ThermalPort. Single output handle representing the array
  `T_wall_out[1:n]` / `q_out[1:n]` (one logical port; n is metadata on
  the edge endpoint, not n handles).
- **D-19:** Source block on-canvas label = two-line:
  - **Top:** instance name (e.g., `wt_inlet`).
  - **Bottom:** mode-aware compact value:
    - `Real (scalar)`:   `T_wall = 320 K`
    - `Vector`:          `T_wall = vector (n=10)`
    - `Function`:        `T_wall = fn(t)`
    - `Required-unset`:  `T_wall = (unset)` in muted-destructive.
  Truthful about complex values without false precision. Hover tooltip
  (if any) deferred to Phase 72 design-system pass.
- **D-20:** When the user picks `Source` mode for a BC field but NO
  source block of the right kind exists on the canvas, the Source-mode
  dropdown shows an inline `+ New WallTemperature` (or `+ New
  HeatFluxSource`) button. Click → spawns a new source-block node on the
  canvas:
    - auto-positioned to the left of the consumer Channel (planner
      picks exact offset; ~120px left + same y-center is the natural
      starting point);
    - smart-name `wall_temperature_<lowest-free-integer>` /
      `heat_flux_source_<lowest-free-integer>` (matches §3.5 smart-name
      rule scoped per component type);
    - `n` defaults to the consumer Channel's `n`;
    - mode = required-unset (D-09 analog for source-block value).
  Then auto-selects the new block in the picker and creates the dashed
  BCPort edge. Mirrors Phase 62's `+ New…` Resource-creation
  inline-button pattern.

### Connection-time validation
- **D-21:** Type mismatch (e.g., `WallTemperature → CHF`,
  `HeatFluxSource → Channel`, `* → CAC`) = HARD-BLOCK at connect time
  with shake + red toast. Matches the existing `FlowPort ↔ ThermalPort`
  hard-block discipline.
- **D-22:** `n` mismatch (e.g., `WallTemperature.n = 10` →
  `Channel.n = 12`) = SOFT WARNING. Connection IS created. Red-ring
  marker on both nodes (§3.9). The BCs tab field and the source block
  show red-text hint: `n mismatch: WallTemperature.n = 10,
  Channel.n = 12`. Code-gen still emits the equations — they will error
  at MTK compile time, with the error visible in the generated `.jl`.
  NO inline lossless-sync action button (`[Sync n: WT → 12]`) in Phase
  63 — that's Phase 71's validation framework. Phase 63 mirrors the
  visual shape (§3.11 'same UI shape as the z_N rule').

### Bidirectional sync
- **D-23:** Single source-of-truth in the zustand store per
  `(component_id, external_input_name)`:
  `bcMode: { mode, params } | { mode: 'source', sourceNodeId: <uuid> } | undefined`.
  Both the BCs-tab editor and the canvas edge renderer subscribe to it.
    - Setting `mode = 'source'` with a source node in the BCs tab → store
      mutation → edge appears on canvas.
    - Deleting the edge on the canvas → store mutation reverting
      `bcMode` to its prior non-source value (or `undefined` if it was
      created fresh from the BCs-tab `+ New` action and never had a
      prior mode).
  Two views of the same fact, never out of sync. No bidirectional event
  plumbing — just a shared store entry.

### Sources toolbox category
- **D-24:** Phase 62 reserved the `Sources` category header in
  `ToolboxPanel.tsx` with no entries. Phase 63 enables the two registry
  entries (`WallTemperature`, `HeatFluxSource`) under that header as
  draggable items. Dragging onto the canvas creates a new node with
  smart-name-increment per D-20 naming rule, `n = 1` default,
  `T_wall` / `q` in required-unset state (D-09 analog).

### Claude's Discretion
- **CD-01:** Exact code-gen text for the unset / Mark TODO comment.
  Planner picks (`# TODO: set ch.T_wall_left[i] here` is a reasonable
  default).
- **CD-02:** Exact name of the cosine helper used for Profile mode (e.g.,
  `cosine_T_wall_profile`, `axial_cosine`, etc.). Planner picks; should
  live in `src/utilities.jl` alongside `rebin_intensive` and Phase 62's
  `cosine_power_shape`. Consider whether to reuse `cosine_power_shape`
  for the shape function (mathematically the same shape, just different
  physical interpretation).
- **CD-03:** Whole-component drop-target activation specifics in
  ReactFlow — pure CSS overlay vs an invisible child handle vs a custom
  node prop. Planner picks.
- **CD-04:** Smart-name-increment number ordering when source blocks are
  created via the inline `+ New` button vs dragged from the toolbox —
  both should share the same per-kind counter (the registered
  smart-name-increment behavior from §3.5).
- **CD-05:** Whether the symmetric-toggle state is per-component
  instance (saved in the `.scp` per-node data block) or session-only.
  Per-component-persistent is the natural default; planner confirms.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Design contract for v1.2 GUI redesign
- `.planning/notes/gui-redesign-design-decisions.md` §3.10 (lines 841–905)
  — Channel Variants direction A; Properties tab vs BCs tab separation
  rule; CAC has no BCs tab. **Primary reference for the property-panel
  split (D-01 / D-02).**
- `.planning/notes/gui-redesign-design-decisions.md` §3.11 (lines 907–994)
  — Boundary Conditions tab and value-source components; the five BC
  modes; Path A (BCs tab) and Path B (drag value-source onto channel);
  dashed edge style; bidirectional sync between BCs tab and canvas edge;
  type-checking + n-match validation. **The most important reference for
  this phase.**
- `.planning/notes/gui-redesign-design-decisions.md` §3.8 — design system
  commitments (engineering tool, not consumer SaaS; visual restraint;
  density expectations; accent palette for Sources / Reactor Physics
  layers). Grounds the hollow-square BCPort choice (D-18) and the
  muted-foreground dashed edge (D-12).
- `.planning/notes/gui-redesign-design-decisions.md` §3.9 — red-ring
  markers on offending nodes for soft warnings. Grounds n-mismatch
  visual treatment (D-22).
- `.planning/notes/gui-redesign-design-decisions.md` §3.5 — smart-name
  increment rule (lowest-free-integer). Grounds D-20 / D-24 naming.

### Phase 61 handoff (mandatory reads)
- `.planning/phases/61-registry-audit-rewrite-for-v1-1/61-CONTEXT.md` —
  Registry declares the `external_inputs[]` per-field schema, `BCPort`
  GUI-only port type tag, the five `bc_modes` enum, the
  `source_component` / `source_port` cross-references, and the
  `array_size` / `default_axis` / `pair_with` fields. Phase 63 consumes
  the registry but does NOT modify it.
- `gui/src/registry/components.json` (post-Phase-61) — v1.1.0 / schema
  2.0. Source of truth for `external_inputs[]` per channel variant +
  the `WallTemperature` / `HeatFluxSource` Sources-category entries.
  Lines 79–98 (`Channel.external_inputs`), 568–642 (`ChannelHeatFlux`),
  1015–1048 (`WallTemperature`), 1049–1082 (`HeatFluxSource`).

### Phase 62 handoff (mandatory reads — selection-kind router, Resource
### pattern, anchored popover discipline, `rebin_extensive` precedent)
- `.planning/phases/62-resources-panel-architecture/62-CONTEXT.md` —
  Phase-62 architectural baseline. Phase 63 inherits the selection-kind
  router (D-05 / D-06 there), the anchored-popover-no-click-outside
  discipline (D-15 / D-16 there), the `+ New…` inline-button pattern
  (used by Phase 63 in D-20), the `rebin_extensive` codegen idiom
  (mirrored by `rebin_intensive` in Phase 63 D-13 / D-16), and the
  required-unset sentinel pattern (mirrored in Phase 63 D-09).
- `src/utilities.jl` — Created in Phase 62 for `rebin_extensive`.
  Phase 63 adds `rebin_intensive` (D-13) alongside.
- `test/test_utilities.jl` — Created in Phase 62 for `rebin_extensive`
  tests. Phase 63 extends with mean-conservation tests for
  `rebin_intensive` (D-15).
- `STREAM.jl` exports — `rebin_extensive` already exported (Phase 62).
  Phase 63 appends `rebin_intensive`.

### Source code references (Julia side)
- `src/components/sources.jl` — `WallTemperature` and `HeatFluxSource`
  Julia component definitions (v1.1, PR #15). Their constructor
  signatures and exposed external-input variable shapes drive the
  registry entries and the source-block label content (D-19).
- `src/components/channels.jl` — Channel and ChannelHeatFlux variant
  definitions (v1.1). Declares the `T_wall_left[1:n]` /
  `T_wall_right[1:n]` and `q_left[1:n]` / `q_right[1:n]` external-input
  variables that the BCs tab binds.
- `STREAM.jl` — Public exports. Phase 63 appends `rebin_intensive`.

### GUI shell + existing code (the target of the changes)
- `gui/src/components/sidebar/SidebarPanel.tsx` — Right Properties
  panel selection-kind router (post-Phase-62). Phase 63 extends the
  component branch with a tab strip + BCs-tab body when the selected
  component's registry entry has `external_inputs.length > 0`.
- `gui/src/components/sidebar/ParameterForm.tsx` — Properties-tab body.
  Phase 63 leaves Properties-tab content unchanged; adds a sibling
  `BCsTabForm` component for the BCs-tab body (or a renamed shared
  scaffold + per-tab body renderer; planner picks).
- `gui/src/components/sidebar/ModeToggle.tsx` — Existing segmented
  control pattern (Pump fixed-dP / fixed-mdot). Phase 63's per-field 5-pill
  picker (D-04) follows the same idiom (and may share a primitive).
- `gui/src/components/sidebar/InstanceNameField.tsx`,
  `NumericField.tsx`, `FunctionSelect.tsx`,
  `ResourceReferencePicker.tsx`, `ResourceCreationPopover.tsx` —
  Reusable field primitives. The Value-mode editor reuses `NumericField`.
  The Function-mode signature picker is a new shadcn-segmented variant.
  The Source-mode dropdown reuses the existing Select primitive + the
  Phase 62 inline `+ New…` button pattern from
  `ResourceCreationButton.tsx`.
- `gui/src/components/StreamNode.tsx` — Custom-node renderer. Phase 63
  modifies it to (a) render the BCPort hollow-square handle when the
  node's registry entry has a `BCPort` port (today: only
  `WallTemperature` and `HeatFluxSource`), and (b) accept BCPort drops
  on the whole-body drop zone when the node has `external_inputs[]`
  (today: `Channel`, `ChannelHeatFlux`). Filter activation by the
  in-flight drag's source-port type to avoid collisions with FlowPort /
  ThermalPort drops.
- `gui/src/components/HydraulicEdge.tsx` — Existing custom-edge
  pattern. Phase 63 adds a sibling `BCEdge.tsx` for the dashed BCPort
  edge (D-12) with the inline click-to-cycle target-side chip (D-11)
  rendered on top of the path.
- `gui/src/store/useStore.ts` — Zustand store + zundo undo/redo. Phase
  63 adds:
    - the `bcMode` slice per `(component_id, external_input_name)`
      (D-23),
    - actions: `setBCMode`, `clearBCMode`, `setBCEdgeTargetSide`,
    - registry-driven validation hooks for connect-time type-check
      (D-21) and n-mismatch warning (D-22),
    - snapshot integration for undo / redo on BC mode changes.
- `gui/src/lib/codeGenerator.ts` — Existing flat-string code-gen.
  Phase 63 updates the per-channel emit logic to read each
  external-input's `bcMode` from the store and emit the appropriate
  Julia code shape (Value / Profile / Function / Mark / Source). Phase
  66 will rework this into structured `CodeSection[]` output — Phase
  63 keeps the flat-string emit shape and just adds the new content
  shapes.
- `gui/src/components/ToolboxPanel.tsx` — Components-tab body. Phase 62
  reserved the `Sources` category header; Phase 63 enables the two
  registry entries (`WallTemperature`, `HeatFluxSource`) under that
  header as draggable toolbox items.
- `gui/src/components/BCPanel.tsx`, `BottomPanel.tsx`, `BCRow.tsx` —
  Existing pressure-anchor BC panel (Phase 36). Phase 63 LEAVES
  UNCHANGED. Two BC mechanisms coexist with clean semantic boundary
  (D-25 below).
- **D-25:** `BottomPanel.tsx` BCs tab (pressure-anchor equations) is
  kept unchanged in Phase 63. Pressure anchors are mathematically
  different from external_input BCs (anchor equations on derived port
  state vs forcing functions on declared unknowns). Future
  consolidation deferred to Phase 65 / a follow-up.

### Project policy
- `CLAUDE.md` — Branching policy (working branch `gui-redesign`, no
  GSD-created branches); file structure standard (new
  `src/utilities.jl` content lives there per Phase 62 precedent; new
  test additions go in `test/test_utilities.jl`); MTK patterns; daemon
  dev loop (`bin/jl` for tests).
- `.planning/PROJECT.md` — v1.2 milestone framing.
- `.planning/STATE.md` — Working branch confirmation (`gui-redesign`);
  Phase 62 complete; Phase 63 next.

### Project memory (carried-forward decisions)
- Memory `feedback_power_shape_trust_caller.md` — `power_shape` must
  NOT be validated/asserted; trust the caller. Grounds D-16 (rebin
  visible in generated code) and the absence of a 'file size mismatch'
  validation rule.
- Memory `feedback_ascii_variable_names.md` — No Unicode variable
  names. Grounds source-block instance-name suggestions (D-20:
  `wall_temperature_<n>`) and Function-mode auto-generated function
  names (D-08).
- Memory `feedback_keyword_only_rule.md` — Keyword-only NOT mandatory;
  use positional + multiple dispatch when types differ. `rebin_intensive`
  uses positional `(vec, n)` / `(mat, shape)` — multiple dispatch on the
  array argument type. Consistent with `rebin_extensive` shape.
- Memory `feedback_no_execute_without_confirmation.md` — Planner /
  executor should not spawn implementations mid-discussion without
  explicit user instruction.
- Memory `feedback_smoke_test_scope_match.md` — Plan smoke-test /
  human-verify checkpoints must promise only what files_modified can
  deliver. Phase 63 plans will partition: helper-only sub-plans (no UI
  visibility) → testable via `bin/jl test/test_utilities.jl`; UI
  sub-plans → testable via `gui && npm run tauri dev`.
- Memory `feedback_channel_hd_connection_rule.md` — Only CAC connects
  to HeatDiffusion. Grounds the §3.11 hard-block:
  `WallTemperature.T_wall_out → CAC.<anything>` is forbidden (CAC has
  no BCs tab; wall conditions via ThermalPort only).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`gui/src/components/sidebar/ModeToggle.tsx`** — Existing segmented
  control (Pump fixed-dP / fixed-mdot). The per-field 5-pill BC mode
  picker (D-04) follows the same idiom and may share a primitive (e.g.,
  extract `SegmentedButtonGroup` with `{values, activeValue,
  onChange}`).
- **`gui/src/components/sidebar/NumericField.tsx`** — Reused verbatim
  for Value-mode editor (single scalar `Real`).
- **`gui/src/components/sidebar/ResourceCreationButton.tsx`** + the
  Phase-62 anchored-popover discipline — Mirrored for the
  `+ New WallTemperature` inline button in the Source-mode dropdown
  (D-20).
- **`gui/src/components/StreamNode.tsx`** — Existing custom-node
  renderer; extended to render the BCPort hollow-square handle (D-18)
  and to accept BCPort drops on the whole-body drop zone (D-10).
- **`gui/src/components/HydraulicEdge.tsx`** — Existing custom-edge
  pattern; sibling `BCEdge.tsx` follows the same `getSmoothStepPath` +
  `BaseEdge` shape (D-12) and overlays the inline click-to-cycle chip
  (D-11).
- **`gui/src/store/useStore.ts`** — Zustand + zundo undo/redo + the
  `_pushSnapshot` discipline; BC mode mutations (D-23) push snapshots
  for undo coverage.
- **`gui/src/lib/codeGenerator.ts`** — Flat-string emit shape; extended
  to emit per-mode code shapes per D-06 through D-09. Phase 66 will
  rework into `CodeSection[]`.
- **`src/utilities.jl`** + **`test/test_utilities.jl`** — Created in
  Phase 62 for `rebin_extensive`. Phase 63 appends `rebin_intensive`
  alongside.

### Established Patterns
- **Registry-driven property panel** — Today the property panel reads
  `parameters[]` from the registry. Phase 63 extends to also read
  `external_inputs[]`: presence drives BCs-tab visibility (D-02);
  per-field metadata (`name`, `shape`, `unit`, `bc_modes`,
  `source_component`, `source_port`) drives the BCs-tab body shape.
- **Selection-kind router in `SidebarPanel.tsx`** (Phase 62) — Phase 63
  modifies only the component branch (adds tab strip + BCs-tab body
  conditionally). Resource and project branches unchanged.
- **Zustand store + zundo snapshot discipline** — BC mode changes push
  snapshots; source-block creation / deletion pushes snapshots;
  edge-side chip cycling pushes snapshots.
- **shadcn primitive surface** — `Tabs`, `Button` (segmented control),
  `Select`, `Popover`, `Tooltip` all present in `gui/src/components/ui/`.
  No new dependencies in Phase 63.
- **`@named` + `@variable` Julia codegen convention** — Existing
  codegen emits `@named ch_1 = Channel(...)`. Phase 63 appends per-BC
  emit shapes after the `@named` block:
  ```julia
  # Phase 62 idiom (carries forward):
  geom_mtr = PipeGeometry_rectangular(...)
  power_shape_mtr = ones(nz, nx)
  # Phase 62 components:
  @named ch_1 = Channel(; n=10, geometry=geom_mtr, g=9.80665, h_left=15000.0, h_right=15000.0)
  # Phase 63 BC bindings (one block per channel with BCs):
  T_wall_left_inlet = rebin_intensive(readdlm(joinpath(@__DIR__, "shapes/inlet_T.csv"), ','), 10)
  bcs = [
      [ch_1.T_wall_left[i] ~ T_wall_left_inlet[i] for i in 1:10]...,
      [ch_1.T_wall_right[i] ~ 320.0 for i in 1:10]...,
  ]
  ```

### Integration Points
- **`gui/src/components/sidebar/SidebarPanel.tsx`** — Add tab strip +
  tab-body switcher when `selectedComponent.external_inputs.length > 0`.
- **`gui/src/components/StreamNode.tsx`** — Render BCPort hollow-square
  handle (port shape decision per `port.type === 'BCPort'`). Accept
  BCPort drops on whole-body drop zone for nodes whose registry entry
  has `external_inputs.length > 0`. Filter drop activation by the
  in-flight drag's source-port type (read from drag state).
- **`gui/src/components/HydraulicEdge.tsx`** + new
  `gui/src/components/BCEdge.tsx` — Edge-type discriminator picks the
  renderer; BCEdge owns the dashed style + inline target-side chip.
- **`gui/src/store/useStore.ts`** — New slice + actions per D-23.
- **`gui/src/lib/codeGenerator.ts`** — Extended per-channel emit logic
  reads `bcMode` per external_input + emits the right Julia shape.
- **`gui/src/registry/components.json`** — READ-ONLY consumer in Phase
  63. Already declares everything Phase 63 needs (Phase 61 work).
- **`src/utilities.jl`** + **`test/test_utilities.jl`** — Extended with
  `rebin_intensive` + tests.
- **`src/STREAM.jl`** — Append `rebin_intensive` to the public exports.

</code_context>

<specifics>
## Specific Ideas

- **`rebin_intensive` as the symmetric companion to `rebin_extensive`.**
  The conservation-law distinction is the engineering nuance: extensive
  quantities (power, mass) sum-conserve under reshape; intensive
  quantities (T, q heat-flux density, p) area-weighted-mean-conserve
  under reshape. Two helpers, one per conservation law, both in
  `src/utilities.jl`. Caller picks based on the physical quantity. The
  user explicitly asked whether this was a good idea — yes, doable in
  ~20-30 lines, mirrors existing helper, fits the architecture cleanly.
- **`Tune mtr-channel.T_wall once, see it everywhere` workflow.**
  Mirrors Phase 62's Resource-edit-propagation idea but for source
  blocks. If a user binds 5 Channels to the same `WallTemperature`
  block and changes its `T_wall` value, all 5 Channels are updated by
  construction (they reference the same store entity). No Resource
  needed for source blocks — the node itself plays that role.
- **Symmetric-by-default toggle pattern (D-05) is a UX accelerator.**
  Both real-world cases (axially-symmetric heated walls, identical
  inlet/outlet adiabatic walls) and most test setups have L = R. The
  default ON state means a single mode-pick covers the common case;
  asymmetric is a one-click expand.
- **Stub-and-edit-in-code for Function mode is the engineering-tool
  ethos crystallized.** The GUI knows function bodies are best edited
  in code, not in a textarea. So the GUI emits the stub + binding, and
  hands off cleanly to the user's text editor. Same posture as
  `rebin_extensive` (visible in code, not hidden in GUI). User-list
  item: 'mark in the code where to change it to a custom one later.'
- **The `+ New WallTemperature` inline button in the Source-mode
  picker (D-20) is the missing parallel to Phase 62's `+ New Geometry`
  for Resources.** Same UX pattern, scaled to canvas blocks. Keeps the
  user in flow inside the BCs tab when wiring up a fresh model.
- **Source block label format (D-19)** — `T_wall = vector (n=10)` /
  `T_wall = fn(t)` / `T_wall = (unset)` mirrors how a Linux man page
  presents enums: terse, type-aware, truthful. No false precision
  (truncated vectors).
- **Edge-side click-to-cycle chip (D-11)** mirrors how diagrams.net
  exposes edge-arrow style: a tiny mid-edge widget that you click to
  cycle through states. Self-documenting; no muscle-memory burden.

</specifics>

<deferred>
## Deferred Ideas

- **Additional Profile presets** (linear ramp, hot-spot, chopped
  cosine, polynomial). Axial cosine only in v1; imports cover anything
  else. Revisit if real users repeatedly hand-roll the same shapes.
- **Lossless-sync action button on n-mismatch** (`[Sync n: WT → 12]`).
  Phase 71 validation framework + action buttons. Phase 63 ships only
  the red-ring + red-text visual.
- **Gates-code-gen-export rule for unset BCs.** Phase 71 owns the
  validation framework. Phase 63 emits TODO markers + no-equation for
  unset; user sees the failure at compile time in v1.2 until Phase 71
  closes the loop.
- **Right-click context menu on BC edges** ([Side: Left/Right/Both,
  Delete]). Phase 65 owns the interaction-model overhaul (right-click
  semantics). Phase 63 ships only the inline click-to-cycle chip.
- **Bidirectional `select-on-canvas → highlight-in-BCs-tab` polish.**
  Mode-state-on-mode-pill highlight when the user just-clicked the
  corresponding BC edge on canvas. Planner judges whether to include
  or defer to Phase 65 / 72.
- **Pressure anchors as FlowPort-property metadata.** Currently
  `BottomPanel.tsx` BCs tab. Future move to per-port handle
  property. Phase 65 (interaction model) or a dedicated follow-up.
- **Function Resource kind** (4th Resources group). Stub-and-edit-in-
  code is the v1 answer. If real users repeatedly write the same
  functions for many BCs, revisit as a true Resource.
- **Inline Julia code editor in the GUI for Function mode.** Explicitly
  rejected (D-08) — engineering-tool restraint.
- **Source-block accent palette + chain-link connected/unconnected
  port icons.** Phase 72 design-system pass.
- **2D `rebin_intensive` use cases beyond the trivial `(n, m) → (n', m')`
  test.** No real workflow in v1.2 needs it — added for API symmetry
  with `rebin_extensive` per D-13. If unused 2 milestones from now,
  evaluate whether to keep.
- **Hover tooltip on source block** showing full T_wall vector / function
  body. Phase 72 design-system pass (tooltip system across the GUI).
- **Bidirectional sync for non-Source BC modes** (e.g., changing Value =
  320 in code → BCs tab updates). One-way only in v1; the BCs tab is
  the canonical authoring surface, code-gen is read-only output. If
  users round-trip-edit, revisit.

</deferred>

---

*Phase: 63-bcs-tab-value-source-components-in-gui*
*Context gathered: 2026-05-13*
