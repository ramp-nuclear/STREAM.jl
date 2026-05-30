# Phase 62: Resources panel architecture - Context

**Gathered:** 2026-05-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Restructure the GUI shell so that the user has a first-class home for two
non-canvas concept families: **Model Options** (a singleton project-settings
object) and **Resources** (user-created, named, reusable, UUID-keyed
definitions of `PipeGeometry` and `PowerShape`). Components on the canvas
stop carrying inline geometry / power-shape values and instead reference
Resources by stable UUID foreign key.

Phase 62 ships the data layer, the new shell wiring, the reference picker
UX, the `.scp` save format, the `rebin_extensive` source helper that makes
file-loaded Power Shapes "just work" across mismatched discretizations, and
the empty Sources toolbox category placeholder.

**In scope:**

- **Shell restructure — Pattern F (tabbed left panel).** Existing left
  panel keeps its width and home but gains a small top tab strip:
  `[Components] [Resources] [Project]`. Components is the default tab and
  reuses today's `ToolboxPanel` body unchanged (Hydraulic / Thermal /
  Sources / future Reactor Physics drag sources, layer-filtered). Resources
  tab is a small tree (Geometries / Power Shapes / Fluids placeholder),
  each group header carrying a `+` button, with inline rename (F2 /
  double-click), per-row context menu (Rename / Duplicate / Delete / Show
  usages), and a top search box. Project tab body **is** the Model Options
  form (Name / Description / Default fluid / Default g / Solver defaults) —
  no inner selection step since the singleton is the only thing the tab
  edits.
- **Right Properties panel becomes a selection-kind router.** Three
  exclusive selection scopes — canvas node, resource row, project tab —
  feed the same right panel. Selecting a Resource clears canvas selection
  and vice versa. Esc clears. Right panel header text changes by kind
  (`Properties`, `Geometry: mtr-channel`, `Project Options`).
- **Keyboard.** `Ctrl+1 / Ctrl+2 / Ctrl+3` switch the left tabs (VS Code
  idiom). Do **not** use `Ctrl+Tab` (browser collision).
- **Tab persistence.** Active left tab persists per project (saved in the
  `.scp` layout block, restored on load).
- **Foreign-key model in state.** Components carry `geometry_ref: <uuid>`,
  `power_shape_ref: <uuid>`, etc. — never inline geometry/power-shape
  values. Resources live in their own store slice keyed by UUID. Rename
  propagates everywhere (no broken refs). Copy-paste of a component
  preserves the reference (does NOT duplicate the Resource).
- **Reference picker UX.** For Resource-typed fields in component
  properties: dropdown showing resource names of the right type +
  `+ New…` button + `Edit…` button. The `+ New…` opens an **anchored
  popover** at the field; click-outside does **nothing** (dismiss only on
  Esc / Cancel / Create); Create adds the Resource to the store, the
  dropdown auto-selects it, popover closes, focus returns to the next
  Channel field. Auto-suggested name follows the §3.5 smart-name-increment
  rule scoped per Resource kind (`geometry_<lowest-free-integer>`,
  `power_shape_<lowest-free-integer>`).
- **`Edit…` jump.** Switches the left tab to **Resources**, selects the
  row, right panel switches to its editor. Return-to-component is one
  click on the canvas node.
- **Empty-state nudge.** Brand-new project with zero geometries: the
  `geometry` dropdown placeholder reads `No geometries yet — click + New…
  or open the Resources tab.` Single line, present on every Resource-typed
  field that has no resources of its kind yet. The discoverability moment.
- **Power Shape Resource semantics — recipe model.** A Power Shape
  Resource stores `{kind, params}` (NOT a materialized matrix). Codegen
  emits a STREAM.jl library call that takes the consumer's `(nz, nx)` at
  script runtime. Four kinds (per §3.2): `uniform`, `z_cosine` (amplitude
  / peaking factor; x-axis uniform per Python STREAM `uniform_x_power_shape`),
  `file_loaded` (CSV path), `unset`. Identical Resource is reusable across
  multiple HeatDiffusions with different `(nz, nx)`.
- **`file_loaded` Power Shape specifics.** File format: **CSV only** for
  v1 (text, 2D matrix, np.savetxt-compatible). Storage: **path reference
  relative to the .scp file** (NOT embedded). On file-not-found at load:
  user-visible error with `Locate file…` action.
- **`unset` Power Shape specifics.** Picker shows `(leave unset — fill
  in code)` as a fixed top entry above the user's named Power Shapes.
  Selecting it is a real choice. Codegen emits:
  ```julia
  power_shape_<name> = ones(nz, nx)  # TODO: fill in your power shape
  ```
  User sees the explicit hand-off when they run the script.
- **`rebin_extensive` source helper (NEW, in `src/`).** Add a public
  helper to a new `src/utilities.jl` that conservatively rebins an
  extensive 2D quantity from any source shape to any target shape, with
  `sum(out) ≈ sum(in)` to floating-point precision. Algorithm: separable
  area-weighted reassignment (rebin along z, then along x). Eliminates the
  file-size-doesn't-match problem entirely — codegen for `file_loaded`
  Power Shapes emits:
  ```julia
  power_shape_mtr = rebin_extensive(
      readdlm(joinpath(@__DIR__, "shapes/mtr.csv"), ','),
      (nz, nx),
  )
  ```
  Rebin runs at script runtime (not at GUI codegen time), so the user can
  edit the CSV and re-run without re-opening Composer. Visible in the
  generated code, not hidden in the GUI — caller-trust posture per
  `feedback_power_shape_trust_caller.md`. Tested in
  `test/test_utilities.jl`: sum-conservation across upsampling /
  downsampling / non-integer-ratio / identity cases.
- **`.scp` file format finalized (`format_version: "2.0"`).** Storage
  shape per §3.2:
  ```json
  {
    "format_version": "2.0",
    "model_options": { "name": "...", "fluid": "water", "g_default": 9.80665, ... },
    "resources": {
      "geometries":   [ { "uuid": "...", "name": "mtr-channel", "kind": "rectangular", ... } ],
      "power_shapes": [ { "uuid": "...", "name": "cosine-axial", "kind": "z_cosine", "params": { ... } } ]
    },
    "components": [ { "uuid": "...", "type": "ChannelAndContacts", "geometry_ref": "<uuid>", ... } ],
    "connections": [ ... ],
    "layout": { "active_left_tab": "Components", ... canvas positions, view state ... }
  }
  ```
- **Hard cutover from `.streamgui`.** Rename all internal references
  (`projectIO.ts`, `useStore.ts`, error strings, tests, Tauri file-dialog
  extension filter). **Delete** the 5 stale `gui/export_examples/*.streamgui`
  files (they predate the v1.1 channel-family redesign and won't load
  anyway under the new registry). Phase 62 ships fresh `.scp` example
  files. No migration code anywhere. Matches §3.2 "starts fresh" decision.
- **Sources toolbox category — empty placeholder.** Phase 62 ships the
  Sources category **header** in the Components tab (so the toolbox shows
  Hydraulic / Thermal / Sources / future Reactor Physics in the navigator
  shape). Sources is visibly empty until Phase 63 lands
  `WallTemperature` / `HeatFluxSource` as draggable entries with the BCs
  wiring. No inert affordances in 62.

**Out of scope:**

- **BCs tab in the property panel + value-source drag entries.** Phase 63
  owns the Properties tab vs BCs tab split, the five BC modes per field,
  the `WallTemperature` / `HeatFluxSource` toolbox entries, the dashed BC
  edge style, and the bidirectional sync between BCs tab dropdown and
  canvas connection.
- **Connection routing autoflip (per-port; asymmetric same-side; thermal
  pair axis-flip; anti-parallel offset).** Phase 64.
- **Validation framework rules** (resource-of-wrong-kind in a picker,
  z_N/length match, dangling FlowPorts, etc.). Phase 71.
- **Code preview rework with `CodeSection[]` and source-UUID tracking.**
  Phase 66. Phase 62 only changes WHAT codegen emits (Resources at the
  top, FK references in component constructors); the section-block UI
  rework is Phase 66.
- **Custom titlebar + full-width unified top toolbar.** Phase 67.
- **Interaction model overhaul** (marquee selection, right-pan, edge
  deletion, copy/paste/cut/duplicate, snap-to-grid, AutoRecover).
  Phase 65. Phase 62 does NOT change canvas interaction behaviors.
- **Layers system overhaul** (four-layer taxonomy, floating chip,
  hide-vs-dim setting). Phase 68. Phase 62 leaves the existing three-mode
  layer state unchanged.
- **Reactivity Controller Resource group in the navigator.** Already
  declared as a Resource kind in the Phase 61 registry (D-13), but
  Phase 62 does NOT add the `Resources / Reactivity Controllers` tree
  group. Deferred to the phase that ships Point Kinetics GUI integration
  (currently parked in §6 of the design doc).
- **Multi-fluid expansion.** `Resources / Fluids` is a placeholder
  showing a single non-editable `light_water` entry. Real multi-fluid is
  v0.6+ Julia work (`project_fluids_longterm.md`).
- **User-defined constants** (e.g., `Q_total = 100kW` referenced from
  many components). Explicitly out per §3.2.
- **Power Shape file formats beyond CSV.** No `.npy`, no JSON 2D arrays,
  no HDF5. CSV-only for v1.
- **Embed-in-`.scp` mode for file-loaded power shapes.** Path-reference
  only for v1. If users later want a portable self-contained `.scp` for
  emailing, an "Embed" mode can be added per Resource without breaking
  the v2.0 schema.

</domain>

<decisions>
## Implementation Decisions

### Shell layout — Pattern F (tabbed left panel)
- **D-01:** Left panel keeps its current width and home in `App.tsx` but
  gains a small text-only tab strip at the top: `[Components] [Resources]
  [Project]`. Tab strip is part of the left panel (not a separate
  activity bar à la VS Code). Components is the default tab on cold start
  / new project; active tab persists per project in the `.scp` layout
  block.
- **D-02:** Components tab body reuses today's `ToolboxPanel.tsx`
  unchanged (Hydraulic / Thermal / Sources / Reactor Physics drag sources,
  layer-filtered via existing `isComponentVisibleInLayer`). Drag flow is
  unchanged from v0.8 — the highest-frequency left-panel action does NOT
  move when the user creates a new Geometry.
- **D-03:** Resources tab body is a small tree with three group headers
  (Geometries / Power Shapes / Fluids). Each group header carries a
  trailing `+` button. Each row has inline rename (F2 / double-click),
  per-row context menu (Rename / Duplicate / Delete / Show usages), and a
  top search box. Tree is flat-per-group (no nesting under a group
  header). Fluids group is placeholder-only for v1 (single non-editable
  `light_water` row).
- **D-04:** Project tab body **is** the Model Options form (no inner
  selection step). Fields: Name (string), Description (multi-line
  string), Default fluid (read-only "water" placeholder for v1), Default
  g (Real, default 9.80665 m/s²), Solver defaults (TBD by planner —
  whatever subset of solve_steady / solve_transient kwargs makes sense to
  expose).
- **D-05:** Right Properties panel becomes a router by selection kind:
  canvas node → existing Component editor; resource row → Resource editor
  (per-kind form); project tab active → Model Options editor (same form
  the tab body would show, but the tab body IS the form, so this is a
  no-op — the panel either shows the Component/Resource editor or stays
  on "No selection" while the user is editing Project). Three selection
  scopes are exclusive: selecting in one clears the other. Esc clears.
- **D-06:** Right panel header text varies by selection kind:
  `Properties` (component), `Geometry: <name>` / `Power Shape: <name>`
  (resource), `Project Options` (singleton). Implementation: a single
  header component reads the selection-kind discriminator.
- **D-07:** Keyboard: `Ctrl+1` Components, `Ctrl+2` Resources, `Ctrl+3`
  Project. Do NOT use `Ctrl+Tab` (browser collision). Existing keyboard
  bindings in `App.tsx` are not disturbed.
- **D-08:** Tab strip persistence — active tab written to the `.scp`
  `layout.active_left_tab` field. Restored on load. Defaults to
  `"Components"` if missing.

### Foreign-key model + resource store
- **D-09:** Components reference Resources by stable UUID in fields
  named `<resource_kind>_ref` (e.g., `geometry_ref`, `power_shape_ref`).
  No alternate "inline" representation exists for these fields — eager-
  only resource creation per §3.2.
- **D-10:** Resource store is a new zustand slice (or extension of
  `useStore.ts`) shaped as `{ geometries: Record<uuid, Geometry>,
  powerShapes: Record<uuid, PowerShape>, fluids: Record<uuid, Fluid> }`.
  Keyed by UUID. Name is a per-resource property; uniqueness is enforced
  per kind (`geometry_<n>` and `power_shape_<n>` can coexist; two
  geometries cannot share a name).
- **D-11:** UUID generation strategy — planner picks (uuid v4 is the
  obvious default; nanoid acceptable). UUIDs are minted client-side at
  Resource creation and never reused.
- **D-12:** Rename propagation is automatic by construction — components
  display the resource name by looking it up via `geometry_ref` UUID at
  render time. Renaming a Geometry mutates the Geometry record; every
  Channel referencing it re-renders with the new label. No "broken refs"
  state exists.
- **D-13:** Copy-paste of a component preserves the FK (does NOT
  duplicate the Resource). Per §3.2 + Phase 65 (interaction model). The
  smart-name-increment rule applies to the component's instance name only.

### Reference picker UX
- **D-14:** Reference picker on a Resource-typed field renders as:
  dropdown (showing names of resources of the right kind) +
  `+ New…` button + `Edit…` button. `Edit…` is disabled when the dropdown
  is on the empty/unset state.
- **D-15:** `+ New…` opens an **anchored popover** at the field. Popover
  contains: name field (auto-suggested per D-19), kind selector (where
  applicable — Geometry has rectangular/circular; Power Shape has the
  four kinds), and the kind-specific numeric fields. Submit (`Create` /
  Enter) creates the Resource, dropdown auto-selects it, popover closes,
  focus moves to the next Channel field. Cancel (`Cancel` / Esc) closes
  without creating.
- **D-16:** Popover does **NOT** dismiss on click-outside. Only Esc,
  Cancel, or successful Create dismisses. This eliminates the "half-typed
  form, accidental canvas click loses work" hazard.
- **D-17:** Popover anchors to the right of the dropdown field if there
  is room in the right Properties panel; otherwise overlaps the canvas to
  the left. Width is a fixed value the layout guarantees (planner picks —
  ~280px is the natural fit).
- **D-18:** `Edit…` switches the left tab to **Resources**, selects the
  row, right Properties panel switches to its editor. Round-trip back to
  the component: user clicks the canvas node (one click). No explicit
  "Back" breadcrumb in the panel — selection model is the navigation.
- **D-19:** Auto-suggested Resource name follows the §3.5
  smart-name-increment rule scoped per kind: `geometry_<lowest-free-integer>`,
  `power_shape_<lowest-free-integer>`. Lowest-free, not next-after-highest.
  Names are valid Julia identifiers (ASCII, no spaces / parens / hyphens —
  the rule from §3.5 + project memory `feedback_ascii_variable_names.md`).
  User can edit the name in the popover before Create; uniqueness is
  validated on submit.
- **D-20:** Empty-state copy on a Resource-typed dropdown when zero
  resources of that kind exist: `No geometries yet — click + New… or
  open the Resources tab.` (or `No power shapes yet — …`). Single line,
  italicized placeholder. Brand-new-user discoverability moment.

### Power Shape Resource semantics — recipe model
- **D-21:** Power Shape Resources store `{ kind, params }`, NOT a
  materialized `[nz, nx]` matrix. Codegen emits a STREAM.jl library call
  that takes the consumer's `(nz, nx)` at script runtime. One Resource is
  reusable across multiple HeatDiffusions with different `(nz, nx)`.
- **D-22:** Four kinds: `uniform`, `z_cosine`, `file_loaded`, `unset`.
  Param shapes (planner finalizes the exact field names + units):
  - `uniform` — no params. Codegen: `power_shape = ones(nz, nx)` (or a
    `STREAM.uniform_power_shape(nz, nx)` helper — planner decides).
  - `z_cosine` — `amplitude` / `peaking_factor` (Real, default 1.0).
    Uniform along x; cosine along z. Mirrors Python STREAM
    `uniform_x_power_shape` shape. Codegen: a new
    `STREAM.cosine_power_shape(nz, nx; amplitude)` helper in
    `src/utilities.jl`.
  - `file_loaded` — `path` (relative to `.scp` file location). Codegen
    uses `rebin_extensive` (D-25).
  - `unset` — no params. Codegen: `power_shape = ones(nz, nx)  # TODO:
    fill in your power shape` (explicit TODO comment for the hand-off).
- **D-23:** `file_loaded` file format: **CSV only** for v1 (plain text
  2D matrix, comma-separated, np.savetxt-compatible). Not `.npy`, not
  JSON 2D arrays. Auditable + portable, matches engineering-tool ethos.
- **D-24:** `file_loaded` storage in `.scp`: **path reference relative to
  the .scp file**, NOT embedded inline. Smaller project file; user can
  edit the CSV in any text editor / Excel without re-opening Composer.
  On file-not-found at load: user-visible error with `Locate file…`
  action (planner decides exact UX).
- **D-25:** `rebin_extensive` helper in `src/utilities.jl` (NEW file).
  Conservative area-weighted regridding from any source shape to any
  target shape; preserves `sum(out) ≈ sum(in)` to floating-point
  precision. Separable algorithm (rebin along z, then along x).
  Public, exported from `STREAM.jl`. Tested in `test/test_utilities.jl`
  for sum-conservation across upsampling / downsampling / non-integer
  ratios / identity cases. Codegen for `file_loaded` Power Shapes emits:
  ```julia
  power_shape_mtr = rebin_extensive(
      readdlm(joinpath(@__DIR__, "shapes/mtr.csv"), ','),
      (nz, nx),
  )
  ```
  Rebin runs at script runtime, not at GUI codegen time. Visible in
  generated code, not hidden in GUI — caller-trust posture per
  `feedback_power_shape_trust_caller.md`. No GUI "file size mismatch"
  error; no validation framework rule needed for this case.
- **D-26:** `unset` Power Shape picker UX: dropdown always has a fixed
  top entry `(leave unset — fill in code)` above the user's named Power
  Shapes. Selecting it is a real, persistent choice (the field is
  `power_shape_ref = <uuid-of-the-unset-singleton>`, or a sentinel —
  planner decides). Codegen emits the `ones(nz, nx)` placeholder plus a
  `# TODO` comment so the user sees the explicit hand-off when they run
  the script.

### `.scp` file format + cutover
- **D-27:** File extension finalized at `.scp` per §3.2 + §3.14.
  `format_version: "2.0"`. Schema per §3.2 storage block (see Phase
  Boundary above for the literal JSON shape).
- **D-28:** **Hard cutover** from `.streamgui`. No read-side migration
  shim. All internal references renamed (`gui/src/lib/projectIO.ts`,
  `gui/src/store/useStore.ts`, error strings, Tauri file-dialog
  extension filter, tests). The 5 stale `gui/export_examples/*.streamgui`
  files are **deleted** (they predate the v1.1 channel-family redesign
  and won't load under the new registry anyway). Phase 62 ships fresh
  `.scp` example files representative of the v1.1 + Resources model.
- **D-29:** `layout` block in `.scp` carries the canvas positions, view
  state, AND the active-left-tab discriminator (D-08). Layout-only edits
  do not dirty the simulation-relevant diff (per §4 cross-cutting
  invariant).

### Sources toolbox category — empty placeholder
- **D-30:** Phase 62 ships the **Sources category header** in the
  Components tab. Visible structure: `Hydraulic / Thermal / Sources` (+
  future `Reactor Physics` when PK lands; not Phase 62). Sources is
  visibly empty until Phase 63 lands the `WallTemperature` /
  `HeatFluxSource` draggable entries with the BCs wiring. No inert
  affordances in 62 — better to show "Sources" empty than to ship
  draggable nodes that can't connect properly.

### Claude's Discretion
- **CD-01:** Tree widget choice for the Resources tab (a hand-rolled
  `<ul>`-based component vs a library like `react-arborist`) is left to
  the planner. The tree is shallow (3 groups, flat per group) so a
  hand-rolled implementation is likely simpler and matches the
  engineering-tool restraint of §3.8 (no animated chrome).
- **CD-02:** Popover rendering primitive (Radix `Popover`, a custom
  fixed-position div, etc.) is left to the planner. The
  shadcn/Radix `Popover` is already a likely match given the existing
  `gui/src/components/ui/` shadcn surface. The non-dismiss-on-click-
  outside behavior is the only non-default knob.
- **CD-03:** UUID generation library (uuid v4 vs nanoid) is left to the
  planner. uuid v4 is the obvious default.
- **CD-04:** Solver-defaults field set in Model Options (which subset
  of `solve_steady` / `solve_transient` kwargs to expose) is left to the
  planner with a sanity check against the user — `abstol`, `reltol`,
  `dtmax` are the natural minimum. If unclear, planner should ask.
- **CD-05:** Whether to refactor `gui/src/components/SidebarPanel.tsx`
  into a per-selection-kind switcher with sub-components (e.g.,
  `<ComponentEditor>`, `<ResourceEditor>`, `<ProjectEditor>`) vs grow
  the existing file with conditional rendering is left to the planner.
  The selection-kind router pattern is what matters; the file layout is
  implementation taste.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Design contract for v1.2 GUI redesign
- `.planning/notes/gui-redesign-design-decisions.md` §3.2 (lines ~204–311)
  — Resources Panel + foreign-key model + navigator tree + reference
  picker UX + storage shape + power-shape variants + eager-only resource
  creation + rename propagation + copy-paste preserves refs + v0.8 file
  migration dropped. **The single most important reference for this phase.**
- `.planning/notes/gui-redesign-design-decisions.md` §3.5 (lines ~503–531)
  — Smart-name-increment rule for component names; Phase 62 applies the
  same rule to Resource names scoped per kind (D-19).
- `.planning/notes/gui-redesign-design-decisions.md` §3.8 — Design system
  commitments (engineering-tool not consumer-SaaS feel; visual restraint;
  density expectations). Grounds the Pattern F vs Activity-Bar vs modal-only
  decision (D-01) and the popover's non-dismiss-on-click-outside
  behavior (D-16).
- `.planning/notes/gui-redesign-design-decisions.md` §3.14 (lines ~1151–1232)
  — `.scp` / `.scpr` file format and identity model. Phase 62 implements
  `.scp` only; `.scpr` is Phase 70.
- `.planning/notes/gui-redesign-design-decisions.md` §4 (cross-cutting
  invariants) — "No anonymous Geometry"; "Layout (canvas positions)
  persisted separately from semantic data"; "All Julia identifiers
  ASCII-only and valid"; per-§3.5 reset-to-empty rule.

### Phase 61 handoff (mandatory reads)
- `.planning/phases/61-registry-audit-rewrite-for-v1-1/61-CONTEXT.md` —
  Registry already declares the FK-shape for `geometry_ref` /
  `power_shape_ref`, the `BCPort` GUI-only port type tag, the
  `array_size` / `default_axis` / `pair_with` fields, and
  `ReactivityController` as a Resource. Phase 62 consumes the registry
  but does NOT modify it (registry rewrites are Phase 61's territory).
- `gui/src/registry/components.json` (post-Phase-61) — v1.1.0 / schema
  2.0. Source of truth for what Resource-typed fields exist on each
  component (`Channel.geometry_ref`, `ChannelAndContacts.geometry_ref`,
  `HeatDiffusion.power_shape_ref`, etc.) and for the Sources category
  registry tags.

### Source code references
- `src/components/heat_diffusion.jl` (lines 1–170) — `HeatDiffusion`
  constructor signature; `power_shape` is `[nz, nx]` dimensionless;
  `q_vol = power * power_shape[i,j] / (ρ·c·y·dz·dx)`; the
  caller-trust-no-normalization invariant.
- `src/composition/helpers.jl` — Existing helper file; `rebin_extensive`
  could live there OR in a new `src/utilities.jl`. Phase 62 D-25 places
  it in a new `src/utilities.jl` for clean topical separation (helpers.jl
  is composition-shaped helpers; utilities.jl is general data-shape
  helpers).
- `src/STREAM.jl` — Public exports. Phase 62 adds `rebin_extensive` to
  the export list. Convention: all public names exported from STREAM.jl
  per CLAUDE.md "Exports" rule.
- `/home/itay/projects/STREAM/stream/composition/mtr_geometry.py`
  (lines 297–335) — Python STREAM `uniform_x_power_shape` reference
  shape (axial cosine, x-uniform). Informs the `z_cosine` codegen helper.

### GUI shell + existing code (the target of the changes)
- `gui/src/App.tsx` — Current shell layout. Phase 62 modifies the left
  panel region to add the tab strip and route the panel body by active
  tab.
- `gui/src/components/ToolboxPanel.tsx` — Current Components tab body.
  Phase 62 wraps it (or leaves it unchanged inside the tab) and adds the
  Sources category header (D-30).
- `gui/src/components/sidebar/SidebarPanel.tsx` — Current right
  Properties panel. Phase 62 extends it into a selection-kind router
  (D-05 / D-06 / CD-05).
- `gui/src/store/useStore.ts` — Current zustand store. Phase 62 adds the
  Resources slice (D-10), the active-left-tab state, the Model Options
  state, and migrates the `.streamgui` → `.scp` references (D-28).
- `gui/src/lib/projectIO.ts` — Current serialize/deserialize. Phase 62
  rewrites for the v2.0 schema (D-27) and hard cutover from `.streamgui`
  (D-28).
- `gui/src/lib/codeGenerator.ts` — Current codegen. Phase 62 changes
  WHAT codegen emits (Resources at top of file, `_ref` lookups in
  component constructors, `rebin_extensive` calls for `file_loaded`
  power shapes). The section-block UI rework is Phase 66 — Phase 62
  keeps the existing flat-string emit shape and just updates the
  content.
- `gui/src/registry/index.ts` — Registry loader. Phase 62 reads the
  registry to drive picker filtering (which Resource kind matches which
  field) and the Sources category header rendering.

### Project policy
- `CLAUDE.md` — Branching policy (working branch `gui-redesign`, no
  GSD-created branches); file structure standard (new `src/utilities.jl`
  follows the "new component file → new test file" rule with
  `test/test_utilities.jl`); MTK patterns; daemon dev loop conventions.
- `.planning/PROJECT.md` — v1.2 milestone framing.
- `.planning/STATE.md` — Working branch confirmation (`gui-redesign`);
  Phase 61 complete; Phase 62 next.

### Project memory (carried-forward decisions)
- Memory `feedback_power_shape_trust_caller.md` — `power_shape` must
  NOT be validated/asserted; trust the caller. Grounds D-25 (rebin is
  visible in generated code, not hidden GUI magic) and the absence of a
  "shape mismatch" validation rule.
- Memory `feedback_ascii_variable_names.md` — No Unicode variable names
  in Julia code. Grounds D-19 (auto-suggested Resource names are ASCII).
- Memory `project_fluids_longterm.md` — `AbstractFluid` + multiple
  dispatch is the long-term shape; do not add new `rho_heavy_water`
  globals. Grounds the Fluids placeholder-only treatment.
- Memory `project_future_multi_material.md` — Future multi-material
  HeatDiffusion uses `materials[nz,nx]` matrix + full-grid
  `power_shape[nz,nx]`. Phase 62's recipe model + rebin_extensive
  forward-compatibly supports this.
- Memory `feedback_no_execute_without_confirmation.md` — Planner / executor
  should not spawn implementations mid-discussion without explicit user
  instruction.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`gui/src/components/ui/` (shadcn surface)** — `Popover`, `Dialog`,
  `ScrollArea`, `Badge`, `Separator`, etc. The anchored popover (D-15)
  is a Radix `Popover` with the click-outside-dismiss disabled. The
  Resources tree (D-03) is rendered inside `ScrollArea`.
- **`gui/src/components/ToolboxPanel.tsx`** — Body of the Components tab
  carries forward unchanged. The only change is adding the Sources
  category header (D-30) above where future Phase-63 entries will land.
- **`gui/src/components/sidebar/`** — Existing per-field editors
  (`InstanceNameField`, `NumericField`, `PipeGeometryPicker`,
  `ParameterForm`, `ModeToggle`). The new Resource editors reuse these
  primitives wherever the field shapes match. The existing
  `PipeGeometryPicker` is the obvious starting point for the Geometry
  Resource editor — but it's currently per-component-inline; Phase 62
  refactors it into a Resource-shaped editor + a separate reference-picker
  component.
- **`gui/src/store/useStore.ts`** — Zustand store + zundo undo/redo
  pattern + the `_pushSnapshot` discipline. Resource creation /
  deletion / rename must push snapshots so undo works on Resource
  changes too.
- **`gui/src/lib/projectIO.ts`** — Existing serialize / deserialize
  shape (currently v2 `.streamgui`). Phase 62 bumps to `format_version:
  "2.0"` `.scp` and replaces the validation logic.

### Established Patterns
- **Registry-driven property panel** — Today the property panel reads
  `parameters[]` from the registry to render the Properties form. Phase
  62 extends this: Resource-typed fields (`geometry_ref`,
  `power_shape_ref`) render as the new reference picker instead of an
  inline editor. Distinction comes from the registry's
  `type_union` / `type: "Resource"` shape (post-Phase-61).
- **`@named` + `@variable` Julia codegen convention** — Existing
  codegen emits `@named pump_1 = Pump(...)`. Phase 62 adds Resource
  declarations BEFORE the `@named` block:
  ```julia
  # Resources
  geom_mtr = PipeGeometry_rectangular(0.6, 0.07, 0.0025, 0.066)
  power_shape_mtr = rebin_extensive(readdlm(joinpath(@__DIR__, "shapes/mtr.csv"), ','), (nz, nx))
  # Components
  @named hd_1 = HeatDiffusion(; nz=10, nx=5, power_shape=power_shape_mtr, ...)
  @named cac_1 = ChannelAndContacts(; geometry=geom_mtr, ...)
  ```
- **Layer-filtered toolbox** (`isComponentVisibleInLayer`) — Stays in
  place. Future Phase 68 layers overhaul does not block Phase 62.
- **shadcn-based widget surface** — Phase 62 uses `Popover`,
  `ContextMenu` (for per-row Resource context menu), `ScrollArea`,
  `Tabs`. All present in `gui/src/components/ui/` already.

### Integration Points
- **`gui/src/App.tsx` left-panel region** — Modify to wrap
  `ToolboxPanel` in a Tabs container with three triggers. Bind
  `Ctrl+1/2/3` accelerators here (or in a new global keyboard hook).
- **`gui/src/store/useStore.ts`** — Add slices: `resources`,
  `modelOptions`, `activeLeftTab`. Add actions: `addResource`,
  `removeResource`, `renameResource`, `updateResource`,
  `setActiveLeftTab`, `setModelOptions`. Snapshot integration for undo
  / redo.
- **`gui/src/lib/codeGenerator.ts`** — Rework to emit Resource
  declarations first, then components. Component constructors look up
  the named Resource via `_ref` UUID and emit the resource's variable
  name (not the inline value). For `file_loaded` Power Shapes, emit the
  `rebin_extensive(readdlm(...), (nz, nx))` call inline.
- **`gui/src/components/sidebar/SidebarPanel.tsx`** — Branch on
  selection kind. Component branch is today's behavior. Resource branch
  renders a Resource-kind-specific editor. Project branch renders Model
  Options form (or is unused if the Project tab body IS the form per D-04).
- **`gui/src/registry/components.json`** — Read-only consumer. Phase 62
  reads the `external_inputs` / FK-shape declarations laid down in
  Phase 61.
- **Tauri file dialog filters** (`useStore.ts:516`, `547`) — Update from
  `.streamgui` to `.scp`. `defaultPath: "project.scp"`. Extension filter:
  `{ name: "STREAM Composer Projects", extensions: ["scp"] }`.

</code_context>

<specifics>
## Specific Ideas

- **Unity is the strongest UI analogue.** Pattern F mirrors Unity's
  Project (reusable assets) + Hierarchy (scene instances) + Inspector
  (right-side, swaps by selection). The researcher's table walks through
  Unity, Simulink Model Explorer, Fusion 360, Figma, VS Code, Blender
  Outliner, diagrams.net, and node editors and identifies Unity as the
  closest peer in conceptual shape and engineering-tool feel. The
  Inspector pattern (right panel swaps by selection-kind) directly
  informs D-05.
- **The "tune `mtr-channel.L` once, see it everywhere" workflow.** Users
  will edit a Resource frequently after initial creation. This drives the
  fast-access requirement that ruled out modal-only and top-bar-dropdown
  patterns — Resources need to be one click away, not behind a menu.
- **The brand-new-user discoverability test.** A first-time user drops a
  Channel onto a fresh canvas; the `geometry` dropdown is empty. The
  empty-state copy (D-20) is the moment they learn they need to create a
  Geometry. Single line, no modal interruption.
- **The "engineering tool, not consumer SaaS playground" §3.8 commitment.**
  Modals were rejected for `+ New…` (D-15) because they ceremonialize a
  small action with a darkened backdrop. Popover with non-dismiss-on-
  click-outside (D-16) is the lighter equivalent that still prevents the
  accidental-click-loses-work hazard.
- **Conservative rebin algorithm (sketch from discussion).** Separable
  1D pass, area-weighted reassignment, `sum(out) ≈ sum(in)` to
  floating-point precision. ~30 lines of Julia. Standard
  conservative-regridding pattern from atmospheric science / image
  resampling.
- **Codegen shape examples (from discussion).**
  ```julia
  # uniform
  power_shape_uniform = ones(nz, nx)
  # z_cosine
  power_shape_cos = cosine_power_shape(nz, nx; amplitude=1.0)
  # file_loaded
  power_shape_mtr = rebin_extensive(readdlm(joinpath(@__DIR__, "shapes/mtr.csv"), ','), (nz, nx))
  # unset
  power_shape_pending = ones(nz, nx)  # TODO: fill in your power shape
  ```

</specifics>

<deferred>
## Deferred Ideas

- **Embed-in-`.scp` mode for file-loaded Power Shapes.** Path-reference
  only for v1. If users later want a portable self-contained `.scp` for
  emailing, an "Embed" toggle per Resource can be added without breaking
  the v2.0 schema. Re-evaluate after first real-user feedback.
- **Additional Power Shape file formats** (`.npy`, JSON 2D, HDF5).
  CSV-only for v1. NumPy `.npy` is the most likely next addition given
  the Python STREAM ecosystem overlap; deferred until a real workflow
  needs it.
- **`Resources / Reactivity Controllers` tree group.** Already declared
  as a Resource kind in the Phase 61 registry (D-13). The Resources tab
  in Phase 62 does NOT expose it. Deferred to the phase that ships
  Point Kinetics GUI integration (parked in §6 of the design doc).
- **"Show usages" context-menu item.** Listed in D-03 as a Resources-tab
  context-menu action. The implementation depends on a usages-index over
  the components store. The action is in scope for Phase 62 but the
  visualization (e.g., highlighting the consuming components on the
  canvas, vs popping a small modal listing them) is a planner-detail
  decision; if it grows beyond a simple list, fold to a follow-up phase.
- **`.scpr` presets file format + Save-selection-as-preset + Presets
  toolbox category.** Per §3.14 / Phase 70. Phase 62 implements `.scp`
  only.
- **Resource "Embed" / "Re-link to source file" toggles for file-loaded
  power shapes.** Considered during Area 3 discussion (hybrid storage
  option). Out of scope for v1; revisit if real users complain about
  path brittleness.
- **Auto-interpolation / bilinear smoothing alternatives to
  `rebin_extensive`.** Considered and rejected. Bilinear doesn't
  conserve sum (loses or gains power on resample), which is wrong for
  extensive quantities. Conservative regridding is the correct choice
  and the only one in scope.
- **Multi-fluid expansion in the Fluids Resource group.** Placeholder
  only for v1. Real multi-fluid is v0.6+ Julia work.
- **Right-panel "Back to <component>" breadcrumb after `Edit…` jump.**
  Considered during Area 2 discussion. Rejected because the canvas node
  is still selectable (one click returns); a breadcrumb would duplicate
  navigation that the selection model already provides. If users
  complain that the return is non-obvious, revisit.
- **`Ctrl+Tab` as left-tab switcher.** Rejected (browser collision).
  `Ctrl+1/2/3` chosen instead.
- **Project tab body as a *form* vs a *form-in-Properties-panel*.**
  Considered making the Project tab a thin entry point that selects the
  Project and lets the right Properties panel render the form (parallel
  to Resource selection). Rejected in favor of D-04 (tab body IS the
  form, no inner selection step) because there is only one Project per
  model — no list to select from. If a future "multi-project" or
  "project templates" idea lands, revisit.

</deferred>

---

*Phase: 62-resources-panel-architecture*
*Context gathered: 2026-05-13*
