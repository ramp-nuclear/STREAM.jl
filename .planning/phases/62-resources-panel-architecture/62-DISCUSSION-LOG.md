# Phase 62: Resources panel architecture - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-13
**Phase:** 62-resources-panel-architecture
**Areas discussed:** Navigator placement + selection model; '+ New Resource' inline UX; Power Shape variants UX; .scp cutover + Sources category scope

---

## Navigator placement + selection model

Initial framing presented four placement options (replace toolbox / split stacked / right-side navigator / defer). User questioned the premise itself — *what is the point of this navigator, what would it have, where can it live without crowding*. Claude broke the question into three honest sub-answers (the need = Model Options + Resources have no canvas presence; the content = §3.2 tree; the placement options = left-fold / toolbar-dropdown / modal-only). User asked Claude to research how comparable tools handle "many kinds of information" and form an opinionated recommendation.

A general-purpose research agent surveyed Unity, Simulink Model Explorer, Fusion 360, Figma, VS Code, Blender Outliner, diagrams.net, n8n, ComfyUI. Identified Unity as the closest peer (Project = Resources, Hierarchy = canvas instances, Inspector = right panel that swaps by selection-kind). Considered patterns A–F (Activity Bar, unified tree, stacked accordion, modal-only, top-bar dropdown, tabbed left panel).

| Pattern | Description | Selected |
|--------|-------------|----------|
| A. VS Code Activity Bar | Narrow icon strip switches the left panel between distinct views. | |
| B. Figma-style unified tree | One left panel with Model Options + Resources + Components branches; drag-source from the Components branch. | |
| C. Stacked left panel | Resources tree on top (collapsible), Toolbox on bottom. | |
| D. Modal-only | Toolbox unchanged; ModelOptions/Resources via menubar dialogs. | |
| E. Top-bar dropdown | Small menus in toolbar; modal/popover editors. | |
| F. Tabbed left panel | `[Components] [Resources] [Project]` tabs in the existing left panel. Components default. | ✓ |

**User's choice:** Pattern F, locked. Plus the right-Properties-panel-as-selection-kind-router shape, `Ctrl+1/2/3` keyboard, active-tab persistence per project, and the brand-new-user discoverability empty-state copy.

**Notes:** User explicitly approved trusting the recommendation. Separately confirmed that the full-width top titlebar (with min/max/close + File/Edit/View/Help menubar) is Phase 67's territory, not Phase 62's — current `gui/src/components/Toolbar.tsx` sits above the canvas only and stays that way through Phase 62.

---

## '+ New Resource' inline UX

Four creation flows presented with ASCII preview mockups: anchored popover at the field, right-panel takeover with breadcrumb, switch-to-Resources-tab with auto-create, modal dialog.

| Option | Description | Selected |
|--------|-------------|----------|
| Anchored popover at the field | Small floating popover; name + kind + numeric fields; submit creates and selects; user never leaves Channel context. | ✓ |
| Right-panel takeover + breadcrumb | Right panel temporarily switches to New Geometry editor with "← Back to <component>" affordance. | |
| Switch to Resources tab + auto-create empty | Left tab switches to Resources; fresh empty Resource created and selected; user returns by clicking canvas node. | |
| Modal dialog | Centered modal blocks canvas; submit creates and selects. | |

**User's choice:** User was between Anchored popover and Modal dialog; asked Claude to pick the better fit.

**Claude's pick:** Anchored popover, with one tweak — click-outside does **not** dismiss; only Esc / Cancel / Create dismisses. Rationale: popover preserves engineering-tool feel per §3.8 (modals are SaaS-flavored); preserves Channel context (user sees the form they're filling for); fits the small Geometry / Power Shape form sizes. The click-outside hazard (accidental canvas click loses half-typed work) is solved by the non-dismiss behavior — the popover behaves like a small docked panel. If a future Resource kind grows past ~10 fields, that kind can graduate to right-panel-takeover without changing the v1 pattern.

**Notes:** Auto-suggested name follows §3.5 smart-name-increment scoped per Resource kind (`geometry_<lowest-free-integer>`).

---

## Power Shape variants UX

Three sub-questions, each ratified one at a time.

### Sub-question 1: Resource semantics — recipe vs data

| Option | Description | Selected |
|--------|-------------|----------|
| Recipe (kind + params; matrix built at codegen) | Resource stores `{kind, params}`. Codegen emits a STREAM.jl library call that takes consumer's `(nz, nx)`. One Resource reusable across any consumer. | ✓ |
| Hybrid: recipe for analytic, data for file-loaded | Uniform / z-cosine / unset = recipe. File-loaded = data Resource (locked to one matrix size). | |
| Data (always store the [nz, nx] matrix) | Resource always stores the materialized matrix. Consumer's nz/nx must match. | |

**User's choice:** Recipe.

### Sub-question 2: File format for file-loaded variant

| Option | Description | Selected |
|--------|-------------|----------|
| CSV only | Plain text 2D matrix, np.savetxt-compatible, auditable, editable in Excel. | ✓ |
| CSV + NumPy `.npy` | Both formats accepted; .npy preserves float64 exactly. | |
| JSON 2D array | Nested array of numbers in the .scp JSON tree. | |

**User's choice:** CSV only.

### Sub-question 3: Storage in `.scp`

| Option | Description | Selected |
|--------|-------------|----------|
| Path reference (relative to .scp) | Resource stores relative path; file lives alongside .scp; user can edit CSV externally. | ✓ |
| Embed inline in .scp | Matrix data inlined into the .scp JSON. Self-contained but bigger. | |
| Hybrid: import inline, re-link button | Default embed, with a button to convert to path reference per Resource. | |

**User's choice:** Path reference (relative).

### Sub-question 4: Size mismatch handling

| Option | Description | Selected |
|--------|-------------|----------|
| Hard error — validation framework flags it | Phase 71 validation rule: file matrix shape must match consumer (nz, nx). Red ring + actionable error. | |
| Auto-interpolate to target size | Bilinear interpolation; tolerant but hides modeling intent. | |
| **rebin_extensive helper in src/** *(user-proposed)* | Add a public Julia helper that conservatively rebins extensive 2D data from any source shape to any target shape; codegen emits a `rebin_extensive(readdlm(...), (nz, nx))` call. No GUI error, no validation rule, no auto-magic in the GUI — the rebin is visible in generated code. | ✓ |

**User's choice:** User pushed back on both original options, proposed the `rebin_extensive` helper instead. Claude verified the user's "extensive" framing was correct (sum of cells, not average; matches power-per-cell semantics in W/cell or as dimensionless share). Wrote a ~30-line algorithm sketch (separable area-weighted reassignment, `sum(out) ≈ sum(in)` to floating-point precision). User locked the choice. Helper lives in NEW `src/utilities.jl` + `test/test_utilities.jl`; exported from `STREAM.jl` per CLAUDE.md convention. Codegen emits the call inline; rebin runs at script runtime.

### Sub-question 5: "Leave unset" UX

| Option | Description | Selected |
|--------|-------------|----------|
| Picker shows '(leave unset — fill in code)' as fixed top entry; codegen emits ones() + TODO | Dropdown always has the unset entry above named Power Shapes. Codegen: `power_shape = ones(nz, nx) # TODO: fill in your power shape`. | ✓ |
| Picker shows '(none)'; codegen omits the kwarg entirely | Empty dropdown state IS the unset state. | |
| Treat 'unset' as a kind; codegen emits a noop function call | `unset_power_shape(nz, nx)` library function that returns ones() and warns at runtime. | |

**User's choice:** Fixed top entry + TODO placeholder. User sees explicit hand-off when they run the script.

---

## .scp cutover + Sources category scope

Two coupled but independent sub-questions, asked in one batch.

### Sub-question 1: .streamgui → .scp transition

| Option | Description | Selected |
|--------|-------------|----------|
| Hard cutover; delete the 5 stale example files | Rename all references; delete `gui/export_examples/*.streamgui` (predates v1.1 redesign, won't load anyway); ship fresh .scp examples. No migration code. | ✓ |
| Hard cutover; keep stale files as historical artifacts | Same renames but leave files on disk. Won't load. | |
| Read-side migration shim | On opening a .streamgui file, attempt in-memory upgrade and save back as .scp. Few hundred lines for near-zero benefit (no real files in the wild). | |

**User's choice:** Hard cutover; delete stale files.

### Sub-question 2: Sources toolbox category scope

| Option | Description | Selected |
|--------|-------------|----------|
| Phase 62 adds empty Sources section; Phase 63 adds entries | Phase 62 ships category header only (Hydraulic / Thermal / Sources visible structure). Phase 63 lands WallTemperature/HeatFluxSource entries with BCs wiring. | ✓ |
| Phase 62 adds Sources + entries as draggable but inert | Both category + entries; drop works; BCs tab + dashed edge wiring is Phase 63. Visible but half-broken. | |
| Phase 62 defers Sources entirely to Phase 63 | Toolbox in 62 stays Hydraulic + Thermal only. | |

**User's choice:** Empty section in Phase 62; entries + wiring all in Phase 63.

---

## Claude's Discretion

Areas where user explicitly delegated to Claude or where the implementation detail is below the discussion threshold:

- **Tree widget choice for the Resources tab** (hand-rolled `<ul>` vs library like `react-arborist`). Tree is shallow; hand-rolled likely simpler.
- **Popover rendering primitive** (Radix `Popover` vs custom fixed-position). Radix is the obvious match given existing shadcn surface.
- **UUID generation library** (uuid v4 vs nanoid). uuid v4 is the obvious default.
- **Solver-defaults field set in Model Options** (which subset of `solve_steady` / `solve_transient` kwargs to expose). Planner should ask if unclear.
- **SidebarPanel refactor shape** (per-selection-kind sub-components vs grow existing file with conditional rendering). Implementation taste.
- **`'+ New' UX choice between Anchored popover and Modal dialog`** — user explicitly said "whatever you think fits more in this place." Claude picked Anchored popover with non-dismiss-on-click-outside behavior.

---

## Deferred Ideas

- **Embed-in-`.scp` mode for file-loaded Power Shapes.** v1 = path reference only. Re-evaluate after first real-user feedback.
- **Additional Power Shape file formats** (`.npy`, JSON 2D, HDF5). CSV-only for v1.
- **`Resources / Reactivity Controllers` tree group.** Phase 61 registry already declares it as a Resource kind; Phase 62 does NOT expose it. Deferred to the phase that ships Point Kinetics GUI integration.
- **"Show usages" context-menu visualization** (canvas-highlight vs modal list of consuming components). Action is in scope; visualization is planner-detail.
- **`.scpr` presets file format + Save-selection-as-preset + Presets toolbox category.** Phase 70.
- **Resource "Embed" / "Re-link to source file" toggles** for file-loaded power shapes. Considered as a hybrid storage option, rejected for v1.
- **Auto-interpolation / bilinear smoothing** as an alternative to `rebin_extensive`. Considered and rejected (doesn't conserve sum, wrong for extensive quantities).
- **Multi-fluid expansion** in the Fluids Resource group. Placeholder only for v1. v0.6+ Julia work.
- **Right-panel "Back to <component>" breadcrumb** after Edit… jump. Considered, rejected — canvas node click returns the user.
- **`Ctrl+Tab` as left-tab switcher.** Rejected (browser collision).
- **Project tab body as a separate form-in-Properties-panel** (parallel to Resource selection). Rejected because the singleton makes inner selection redundant.
- **Full-width unified top toolbar.** Confirmed Phase 67 territory, not Phase 62.
