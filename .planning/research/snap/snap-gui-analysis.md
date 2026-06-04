# SNAP GUI Analysis — STREAM.jl GUI Design Reference

**Sources analyzed:**
- `SNAP_docs.pdf` — RELAP5 Plug-in User Manual, SNAP v6.5.1 (108 pages, Applied Programming Technology Inc., 2021)
- `SNAP_main_report.pdf` — CAFEAN Preprocessor API Main Report, NUREG/CR-6974 Vol. 1 (76 pages, US NRC, 2009)

**Raw extractions:** `snap-docs-extraction.md`, `snap-report-extraction.md`

**What SNAP is:** A Java-based graphical preprocessor for nuclear thermal-hydraulics analysis codes (primarily RELAP5). Users build reactor loop models by placing components on a 2D canvas, connecting them via ports, editing parameters in property panels, then exporting to an ASCII input deck that a separate solver executable reads. SNAP and STREAM.jl operate in the same physical domain — coolant loops, pumps, pipes, heat structures — which makes it the highest-quality reference we have.

---

## Visual Character of SNAP (from screenshots)

Before diving into features, the visual style informs what we should and shouldn't copy:

- **Component icons in 2D view**: Schematic symbols — a pipe is a labeled rectangle divided into cells, a pump is a distinct glyph. Not photorealistic, not abstract boxes. Domain-recognizable shapes.
- **Component icons in 3D view**: Volumetric 3D objects — stacked gray cylinders (pipes), red boxes (pumps), green cylinders (large vessels), dark red coils (heat exchangers), blue dots (junction points), magenta arrows (connections). Impressive visually but extremely domain-specific.
- **Property View**: Two-column table — property name left, inline editor right, small icon buttons far right (help/lock). Compact, dense, Swing-era.
- **Pipe Geometry dialog**: Modal dialog with a small 2D schematic of the pipe at the top (graphical representation, cells highlighted when selected in table), tabbed table below (Cells / Orientation / Rot. Matrix / Junctions). Radio buttons control which quantity is calculated from others. This is the most important editor pattern — graphical preview synchronized bidirectionally with the data table.
- **Navigator**: Left-side tree panel with category icons. Right-click context menus for all operations.
- **3D Viewer**: Separate window with camera control buttons on the left panel, main viewport center, status bar at bottom.
- **Dialogs**: Heavy use of modal dialogs with OK/Cancel — a Swing-era constraint. STREAM.jl can do better with non-modal side panels.

**Overall aesthetic verdict**: Functional but dated. STREAM.jl can take the *workflows* and *data organization* from SNAP while using a modern UI toolkit and layout.

---

## Part 1 — Architecture Decisions to Adopt

These are the structural decisions from CAFEAN (the architectural report) that should be baked in from day one. Getting these wrong early is expensive to fix.

### 1. Foreign-key relational model (most important)

Every component gets a stable UUID (`ident`) assigned at creation. Components reference each other only via UUIDs, never via direct Julia handles. The "model" is a flat dictionary `UUID → ComponentData`.

**Why this matters for STREAM.jl:** When a user renames a Channel, all connections to it still work. When you undo a deletion, the restored component has the same UUID. When you copy-paste between models, new UUIDs are assigned. When `mtkcompile` fails, we can map the error back to a UUID and highlight the component on canvas. Without this, all of these are painful.

**Julia implementation note:** Use `Base.UUID` or `Int64` keys. A `Dict{UUID, ComponentSpec}` as the model's backing store. MTK system names are derived from the human-readable label, not the UUID.

### 2. Connections are first-class objects

A connection between two ports is itself a model object with its own UUID, stored in a separate connection list alongside components. It carries: source component UUID, source port name, target component UUID, target port name.

**Why:** Connections need undo/redo, persistence, validation (FlowPort↔FlowPort type checking), visual rendering. Treating them as adjacency lists owned by components makes all of this harder. SNAP's `HydroConnection` / `HeatConnection` typed connections map exactly to STREAM.jl's `FlowPort` / `ThermalPort`.

### 3. Component categories drive Navigator + toolbox + creation

Define a category tree (e.g., `Hydraulic → {Pump, Channel, Resistor, Friction, Gravity, Inertia}`, `Thermal → {HeatExchanger, ChannelHeatFlux, HeatDiffusion}`, `Fluids`, `Geometry`, `Options`). This single structure drives: the Navigator tree, the toolbox button layout, component creation dispatch, and iteration for validation and serialization.

### 4. Multi-view reactive architecture

All views (2D canvas, Property Panel, Julia Code View, Solve Monitor, Plot View) subscribe to component change events and refresh independently. A change in the Property Panel immediately reflects on the canvas and in the code view — no manual sync, no refresh buttons.

**Pattern:** Component fires `component_changed(uuid)` → all subscribed views call their own `refresh(uuid)` method.

### 5. Layout and semantic data are separable in the save file

The save format has two sections: (a) semantic data — component types, parameter values, connections, model options; (b) layout data — canvas positions, view states, zoom levels, annotation positions. Saving a layout-only change (moved a component on canvas) does not touch the simulation-relevant section. This matters for git diffs — parameter changes vs layout changes are readable separately.

### 6. Single application-wide undo stack with compound edits

One undo stack. Compound edits for multi-step operations (e.g., "delete component and its 3 connections" = one undo entry). Every mutable operation on the model goes through this stack.

### 7. Two-tier validation

- Per-component: `is_valid(component) → Vector{ValidationError}` — checks invariants the component owns (required fields filled, values in range, port counts correct).
- Model-level: pluggable `ValidationTest` objects — checks cross-component constraints (loop mass balance, connected FlowPort types match, no dangling ports, geometry consistency). Runs silently before solve; runs verbosely on user request ("Check Model" button).

### 8. Save format: JSON/TOML, not binary

SNAP uses PIB binary (opaque, not diffable, requires custom parser). STREAM.jl should use JSON or TOML. A `.stream` file is human-readable, git-diffable, and directly loadable into Julia. Structure:

```
{
  "format_version": "1.0",
  "model": {
    "options": { ... },
    "components": [ { "uuid": "...", "type": "Channel", "label": "ch1", "params": { ... } }, ... ],
    "connections": [ { "uuid": "...", "from": {"uuid": "...", "port": "port_out"}, "to": {...} }, ... ]
  },
  "layout": {
    "canvas": { ... positions, zoom ... },
    "views": [ ... ],
    "annotations": [ ... ]
  },
  "stored_solutions": [ ... ],
  "named_ic_sets": [ ... ]
}
```

### 9. Component spec table (Julia analog of BeanInfo)

Each STREAM.jl component type registers a spec:

```julia
ComponentSpec(
  type = :Channel,
  category = [:Hydraulic],
  fields = [
    FieldSpec(:L,   Float64, unit=u"m",   required=true,  group="Geometry"),
    FieldSpec(:Dh,  Float64, unit=u"m",   required=true,  group="Geometry"),
    FieldSpec(:N,   Int,     unit=nothing, required=true,  group="Discretization"),
    FieldSpec(:mdot_init, Float64, unit=u"kg/s", required=false, group="Initial Conditions"),
    ...
  ],
  ports = [
    PortSpec(:port_in,  :FlowPort),
    PortSpec(:port_out, :FlowPort),
  ],
  icon = :channel_icon,
  docstring = "..."
)
```

This is the single source of truth for: property panel auto-generation, canvas icon port positions, serialization/deserialization, validation, Julia code generation. Adding a new component type requires only registering one spec — no separate editor code, no separate serializer code.

---

## Part 2 — Features to Build (Apply / Adapt)

Organized by priority. Each entry notes what SNAP does, what STREAM.jl should do, and the delta.

### Canvas & Navigation

| Feature | SNAP | STREAM.jl |
|---|---|---|
| Navigator tree | Left-side tree of all components by category | Same. Categories: Hydraulic, Thermal, Geometry, Fluids, Model Options |
| 2D canvas | Main editing area; pan/zoom; components placed as icons | Same. Tools: Select, Pan, Zoom, Connect, Insert |
| Right-click context menus | New, Show ASCII, Add to View, Reference Docs, Copy/Cut/Paste, Renodalize | New, Show Julia Code, Reference Docs (docstring), Copy/Cut/Paste, Re-discretize |
| Component icons | Domain-recognizable schematic symbols | Same principle — pipe=segmented rectangle, pump=circle with arrow, channel=segmented, heat exchanger=zigzag |
| Multiple 2D views per model | Supported | Same — useful for primary loop vs secondary loop side-by-side |
| Auto-layout | Not provided; user places manually | Provide a BFS-based "Auto Layout" using connection topology. Critical for new users. SNAP doesn't have this — we should. |
| Color coding | Red=modified in restart, yellow=selected, red-foreground=invalid | Red=error, yellow=selected, orange=warning, grey=disabled/unconnected |
| Selection sync | Canvas ↔ property panel ↔ table editors bidirectional | Same |

### Property Panel

| Feature | SNAP | STREAM.jl |
|---|---|---|
| Inline property editing | Two-column table, edits live, pushes undo | Same, but non-modal side panel not modal dialog |
| Field groups (collapsible) | Attribute groups; collapsed groups defer editor creation | Same — "Geometry", "Initial Conditions", "Solver Options", "Advanced" |
| Optional/Required/Disabled per field | PropertyController interface | Derived from ComponentSpec FieldSpec flags |
| `< Different Values >` on multi-select | Union of properties shown; non-shared fields show this placeholder | Same — select 3 channels, edit L for all at once |
| Tooltip documentation | Column header tooltips are the primary docs | Show first line of field docstring as tooltip; "?" button opens full docstring |
| Enum dropdowns | NamedIntEditor | Same — e.g., Friction mode: Laminar / Turbulent / Churchill |
| Unit display | SI / British toggle, stored in SI | SI / Imperial toggle per field; displayed unit annotation; backed by Unitful.jl |
| Foreign-key picker | ComponentSelectionEditor ("S" button, modal dialog listing components) | Dropdown or modal picker for e.g. geometry reference, fluid reference |

### Component Editors

| Feature | SNAP | STREAM.jl |
|---|---|---|
| Completion dialog at creation | Pipe asks cell count + total length at creation time | Channel asks: L, Dh, N_cells, orientation. PipeGeometry asks: shape (rectangular/circular), dimensions. |
| Tabbed sub-editor dialogs | Pipe Geometry: Cells / Orientation / Rot.Matrix / Junctions tabs; graphical preview at top | Channel Geometry: Cells (length, area, Dh per cell) / Orientation (angle per cell, elevation) / Junctions (loss coefficients). Graphical pipe preview at top synced with table. |
| Per-cell table editing | Cell Number / Volume / Length / Area with Calculate radio buttons | Cell Number / Length / Dh / Area with Calculate radio (auto-derive one from others) |
| Range-fill utilities | "Zipper" for Multi-Junction, range creation for Signal Variables, Heat Connections range dialog | "Fill range" for connecting ThermalPort arrays (e.g., channel cells 1-N all connected to plate contacts), batch probe creation |
| `< Different Values >` in axial cell editor | Heat Structure axial cells multi-select | Channel cell editor multi-select (edit multiple cells at once) |
| Renodalization dialog | Split / Split Uniform / Merge with internal undo, previews, Announce Changes | Re-discretize dialog: same controls, previews current vs proposed cell distribution, internal undo, applies only on OK |
| Pipe Split | Split a pipe at an internal junction into two components | Channel Split: creates two Channels connected by a new FlowPort junction — useful for inserting a tee |
| Graphical preview synced with table | Pipe geometry shows diagram; selecting a row highlights the cell in diagram | Same — selected cell in table highlights in the schematic |

### Data Import/Export

| Feature | SNAP | STREAM.jl |
|---|---|---|
| Open / Save native format | `.MED` binary | `.stream` JSON — open, save, forward-compatible |
| Live Julia Code view | "Show ASCII" shows RELAP5 deck | "Show Julia Code" shows auto-generated MTK construction code for selected component or whole model. Live-updating as user edits parameters. |
| Full model code export | Export ASCII deck | Export runnable Julia script: imports, component constructions, `compose_systems`, `mtkcompile`, solver call. Verbatim re-runnable. |
| Import from code | ASCII deck import | Import a Julia source file that constructs STREAM.jl components; parse parameter values back into the GUI model. Round-trip resource-map style (sidecar JSON preserves canvas layout). |
| Resource round-trip | ASCII + sidecar `.MED` preserves views/numerics/notes | Julia code + sidecar `.stream` layout file. Text-editor changes to the code survive import with layout intact. |

### Solve & Results

| Feature | SNAP | STREAM.jl |
|---|---|---|
| Submit model | External "Calculation Server" over network | In-process solve — no network. Solve button triggers Julia solver directly. |
| Solve mode picker | No choice; RELAP5 is time-domain only | Pick: `solve_steady`, `steady_state_guess`, `solve_transient` |
| Solver options | Not user-configurable in GUI | Tolerances, dtmax, maxiters, solver algorithm (IDA, Rodas5, FBDF) with tooltips on suitability |
| Solve progress | No monitor | Progress bar for transients (time/t_end), convergence indicator for steady (residual norm), abort button |
| Result loading | Separate post-processor application | MTKSolution is a first-class model artifact attached to the model — not a separate app |
| Retrieve Initial Conditions from previous run | Right-click → Retrieve Initial Conditions; pick restart time; category+component level selection | Same: "Load ICs from solve result" dialog; pick steady or any transient time point; selectively apply per component |
| Named IC sets (Store/Load/Remove) | Manage Initial Conditions — named snapshots persisted with model | Same: named IC sets stored in `.stream` file; survives without the original solve |
| Solution comparison | No built-in; manual | Side-by-side plot of stored solutions; baseline diff |

### Plotting & Visualization

| Feature | SNAP | STREAM.jl |
|---|---|---|
| Tabular editor Plot button | Right-click → Plot; pick independent + dependent variables | Same in table editors |
| Post-solve variable browser | Separate post-processor; must declare signal variables upfront | Auto-discover all MTK unknowns + observed variables post-solve — no declaration needed. Tree browser: per-component variables. |
| Time-series plots | APTPlot (external plug-in) | Integrated Julia plot (Makie or similar); time-series for transients |
| Spatial plots | Not standard | Plot variable along channel cells (axial profile) |
| 3D visualization | Impressive 3D viewer; separate plug-in | GREY for v0 — 2D canvas is sufficient. BFS auto-layout in 2D is higher value. |

### Diagnostics & Validation

| Feature | SNAP | STREAM.jl |
|---|---|---|
| Check Model button | Runs loop test + component validation; emits to Message Window | Same; additionally runs MTK structural check pre-mtkcompile |
| Message Window | Central non-modal feedback console | Same; three severity levels (info/warning/error) with component-uuid links that highlight on canvas |
| Red foreground for invalid table values | General Tables marks out-of-order/duplicate in red | Same in all table editors (e.g., non-monotone time column) |
| Reference Docs per component | Opens RELAP input manual PDF section | Opens rendered Julia docstring for the component type (in-panel, not browser) |
| mtkcompile diagnostics | No analog | New: MTK Compile Panel — shows structural singularities, index reduction steps, equation count. Links error to responsible component on canvas. |

### Capture & Notes

| Feature | SNAP | STREAM.jl |
|---|---|---|
| Description + Comments per component | `*d:` / `*c:` tagged; survive ASCII round-trip | Free-text description + comments per component in ComponentSpec; survive Julia code round-trip |
| Model Notebooks | ODF/DOCX with sub-system sections, component images, ASCII listings | Pluto.jl notebook export: per-component section with MTK equations, Julia code, parameter table, solution plot. Quarto/Markdown for static reports. |
| Sub-system organization | Sub-systems with Nest flag + 2D view image | `compose_systems` groups as named sub-systems; each gets a canvas view usable as notebook section header |
| User-defined numerics (constants/variables) | Model-wide named constants; right-click "User Values" to reference in any real field | Named parameter constants (e.g., `Q_total = 100kW`); reference from any field via a picker; stored in model; exported as Julia `@parameters` |
| Attribute Level Ownership | Per-attribute owner/reviewer/timestamps; Review window | GREY — skip for v0. Useful for institutional regulated users later. |

---

## Part 3 — Features to Skip

These are SNAP features that don't apply to STREAM.jl's context.

| Feature | Why skip |
|---|---|
| RELAP5 ASCII deck import | RELAP5-specific format; STREAM.jl has no equivalent input language |
| 22-component hydraulic catalog (Branch, Pressurizer, JETMIXER, ECCMIX, CANDU, etc.) | RELAP5-specific physics; not in STREAM.jl domain |
| Multi-Dimensional hydraulic volumes (MULTID) | STREAM.jl is 1D axial; HeatDiffusion is 2D solid plate only |
| Reactor Kinetics (Nodal) | Out of STREAM.jl scope |
| Radiation Enclosure + View Factors | Not modeled in STREAM.jl |
| Trip numbering formats (401-799 vs expanded) | RELAP card-numbering artifact |
| Restart Case "Virtual Model" with red-coloring | The concept (IC sets + parametric cases) APPLIES but the specific restart-deck mechanism is RELAP5-specific |
| Attribute Level Ownership | Regulatory QA workflow; not a v0 concern |
| PIB binary format | Use JSON |
| 3D Model Viewer | GREY/SKIP for v0; 2D canvas with BFS auto-layout is higher value |
| Java plug-in architecture (`MEPlugin`, `MEPluginData`) | Language-specific infrastructure; Julia has a simpler equivalent via component registration |
| Mathcad output format | Not a Julia ecosystem tool |
| Test Suite Analyzer (METRICS_SPEC / METRICS export) | RELAP5-specific benchmark infrastructure |
| `ConnectionData.equals`-based line routing | Fragile pattern; use explicit named-port references instead |

---

## Part 4 — STREAM.jl-Specific Features SNAP Has No Analog For

These are features SNAP cannot have (RELAP5 is causal/procedural; no symbolic layer) that STREAM.jl should build as first-class GUI features.

### 4.1 Live Julia Code View (highest priority)
Two synchronized panels:
- **Component code**: auto-generated `@named ch1 = Channel(L=3.0, Dh=0.01, ...)` for selected component.
- **Model code**: full runnable Julia script — imports, all component constructions, `compose_systems`, `mtkcompile`, solver call. Verbatim re-runnable. Updates live as user edits parameters.

This is the single biggest differentiator from SNAP. STREAM.jl's user base is code-native; they will use this constantly. It also serves as a "what is the GUI actually doing" transparency layer.

### 4.2 MTK Equation View
For selected component or whole model, show:
- Pre-compile: full DAE equations as rendered LaTeX or Julia
- Post-compile: index-reduced ODE + observed equations + variable classification

Expert users and students debugging their models need to see the math.

### 4.3 Port Type Visualization
- Color-code `FlowPort` vs `ThermalPort` connections on canvas (e.g., blue for flow, orange for thermal)
- Show port variable list (mdot, p for FlowPort; Q, T for ThermalPort) on hover
- Detect type mismatch at connection time — block the connection with an error message instead of silently creating an invalid model
- Show acausal nature explicitly: no "from"/"to" arrow; use bidirectional line

### 4.4 MTK Compile Diagnostics Panel
`mtkcompile` errors (structural singularity, DAE index too high, missing equations) need a dedicated panel that:
- Shows which equation is problematic
- Links to the component UUID responsible
- Highlights that component on canvas
- Shows the structural analysis steps taken (index reduction, tearing, etc.)

SNAP surfaces RELAP errors as plain text in the Message Window. STREAM.jl can do structurally-informed diagnostics.

### 4.5 Solve Monitor (in-process)
Because STREAM.jl solves in-process (not external executable):
- Live progress bar for transients (current t / t_end)
- Convergence indicator for steady (residual norm log plot, updating as iterations run)
- Abort button that cancels the solve cleanly
- Partial results visible during transient solve (live updating plots)

### 4.6 Auto-Discovered Variable Browser
Post-solve, every MTK unknown and observed variable is automatically available for plotting — no "Signal Variable" declaration step needed. Browser shows:
- Per-component tree of variables
- Filterable by name
- Select multiple → multi-line plot

### 4.7 Composition Macro Operations
STREAM.jl's `plate`, `symmetric_plate`, `one_sided_connection`, `compose_systems` are first-class workflow tools. The GUI should expose these as one-click "macro" operations:
- "Symmetric plate from N channels with M contacts" → dialog asking N/M → creates the full assembly
- "Compose into sub-system" → selects a set of components and wraps them in a `compose_systems` call
Closest SNAP analog is the Multi-Junction zipper utility — generalize it.

### 4.8 Correlation Picker per Component
`physical_models/correlations.jl` exposes multiple HTC and friction correlation closures. The GUI should expose a "Correlation" dropdown per Channel/ChannelHeatFlux component showing available correlations with:
- Preview plot of Nu(Re) or f(Re) for the chosen correlation
- Tooltip describing the correlation's validity range

### 4.9 Constructor Introspection-Driven Property Panels
Because STREAM.jl components are Julia structs with documented constructors, the GUI can auto-generate property panels by introspecting constructor signatures (`methods`, `Base.kwarg_decl`, docstrings). This means: add a new component to `src/components/`, register its spec, and the GUI automatically gets its property panel — no hand-written editor code. SNAP hard-codes all its editors.

### 4.10 Parametric Sweep as First-Class Object
A "Sweep" object: pick parameters + ranges, run N solve calls, browse results in a matrix view, plot parameter vs output. SNAP's restart cases approximate this only for restart-time variations. STREAM.jl should make it explicit.

### 4.11 Named Solutions (Steady + Transient)
Named stored solutions (`Dict{String, MTKSolution}`) persisted in the `.stream` file:
- Attach a steady solution → use as IC for transient (warm start)
- Attach multiple transient solutions → side-by-side plot as baseline comparisons
- SNAP has named IC sets only; STREAM.jl has richer solution objects worth persisting.

### 4.12 Symbolic Parameter Marking
MTK supports `@parameters` (symbolic, kept tunable post-compile). The GUI should let a user mark any numeric field as "symbolic" (stays in the `ODEProblem` parameter vector and can be changed without recompiling) vs "numeric" (baked at compile time). Displayed differently in the property panel.

### 4.13 mtkcompile Cache Status
`mtkcompile` is slow on first call. GUI should show compile cache status per model ("stale / current") and a "Pre-compile" button that warms the cache in background. After source changes (Revise.jl picks them up), the cache is automatically invalidated.

---

## Part 5 — Grey Areas

These require a design decision before the milestone starts. Neither obvious "apply" nor obvious "skip."

| Feature | The ambiguity | Recommendation |
|---|---|---|
| 3D Visualization | Cover page shows impressive 3D; very domain-specific component shapes | Skip for v0. BFS auto-layout in 2D gives 80% of the navigation value. Revisit when multi-loop spatial models are common. |
| Drill-Down (embedded views) | Powerful for large models; adds architectural complexity | Design for it (view-as-component pattern from CAFEAN §2.3), but don't expose until `compose_systems` sub-systems exist. |
| Interactive Variables (live inputs during solve) | Powerful for operator-style simulations; requires a runtime channel into a running ODE | Skip v0. Julia async + DiffEq callbacks make this achievable later, but it's non-trivial to implement safely. |
| Attribute Level Ownership | High value for institutional/regulated users; zero value for solo researchers | Skip v0. Design the data model to allow per-field metadata (the slot exists) but don't build the UI. |
| Cases / Restart Deck | SNAP's Cases concept = parametric variants. In STREAM.jl this maps to stored solutions + sweep. | Build Named Solutions (§4.11) in v0. Build full Sweep UI later. |
| Model Notebooks → Pluto export | Very Julia-native; Pluto notebook structure maps well | Implement later (after core editing is solid). Mark as v1.x feature. |
| REPL embedding | Extremely useful for STREAM.jl's code-native user base | Include a Julia REPL pane with `model` pre-bound. Depends on the GUI framework choice. |

---

## Part 6 — Proposed v0 GUI Feature Set

Based on everything above, the minimum coherent v0 that is actually useful to a STREAM.jl user and that SNAP validates as the right scope:

**Shell:**
- 2D canvas with pan/zoom/select
- Navigator tree (categories: Hydraulic, Thermal, Geometry, Fluids, Options)
- Property Panel (auto-generated from ComponentSpec, grouped, with units)
- Message Window
- Undo/redo (single stack, compound edits)

**Model building:**
- Insert components from toolbox (all current STREAM.jl components)
- Connect FlowPort↔FlowPort and ThermalPort↔ThermalPort (type-checked)
- Port type color coding (blue=flow, orange=thermal)
- BFS auto-layout
- Component icons (domain-schematic, not 3D)
- Completion dialog at creation (key dimensions)
- Channel geometry tabbed editor (Cells / Orientation) with graphical preview

**Code integration:**
- Live Julia Code View (per-component + whole model)
- "Export to Julia script" (full runnable script)
- Open / Save `.stream` JSON

**Solve:**
- Solve mode picker (steady / transient)
- Basic solver options (tolerances, maxiters)
- In-process solve with progress bar + abort
- Named IC sets (Store/Load from solve result)

**Results:**
- Auto-discovered variable browser post-solve
- Time-series plots (transient)
- Axial spatial plots (per channel)

**Validation:**
- Check Model button with per-component + model-level tests
- Red foreground for invalid table values
- Port type mismatch prevention at connection time
- mtkcompile diagnostic messages with component links

**Deferred to later versions:**
- Parametric sweep UI
- Equation view (MTK math display)
- Pluto notebook export
- 3D visualization
- Correlation picker with preview curves
- Drill-down into compose_systems sub-systems
- Attribute ownership
- Interactive Variables

---

## Part 7 — Key Architectural Anti-Patterns to Avoid

Drawn from "What SNAP Gets Wrong" (snap-report-extraction.md §10) applied to STREAM.jl:

1. **Don't let the deck/code be the source of truth.** SNAP's ASCII deck is canonical; the GUI is a deck editor. STREAM.jl should flip this: the component graph is canonical; the Julia code is a derived view. This means the GUI owns the model, not the code file.

2. **Don't split save logic across many files.** One declarative serialization layer that walks the ComponentSpec table. Every component type is automatically serializable by registering its spec.

3. **Don't use binary save formats.** JSON only.

4. **Don't make threading a component-authoring concern.** Keep solve off the UI thread, but don't require component authors to know about threading. A simple `run_solve(model, options)` callback is enough.

5. **Don't use a god-object MainFrame.** Separate services: model registry, undo service, message bus, event bus, command registry. Each independently testable.

6. **Don't bury actions in a "Special" menu overflow.** If there are too many actions, the answer is a command palette (fuzzy search, keyboard-driven), not a hidden submenu.

7. **Don't omit keyboard-first navigation.** Command palette (Ctrl-Shift-P), quick-jump-to-component by name, keyboard shortcuts for common operations.

8. **Don't have a project-less model management.** Define a project directory structure from day one: one folder per project with a manifest, model files, stored solutions, sweep results, notes. Enables git collaboration, diff, and merge.

---

## Notes on What the Screenshots Revealed (visual supplement)

The cover page of SNAP_docs.pdf shows the 3D viewer as the hero image — volumetric component icons representing a reactor primary loop. This is SNAP's most visually distinctive feature. In practice it's used far less than the 2D canvas.

Page 23 (Figure 3.11 — Pipe Cell Geometry) is the single most instructive screenshot for STREAM.jl's Channel editor design:
- Modal dialog titled "Geometry - PIPE 108 (lsgtubes)"
- Graphical pipe schematic at top (2D cross-section showing cells as stacked rectangles, selected cells highlighted)
- Below: tabbed table — **Cells** / **Orientation** / **Rot. Matrix** / **Junctions**
- Cells tab columns: Cell Number | Volume (ft³) | Length (ft) | Area (ft²)
- Radio buttons at bottom: Calculate: ⊙ Volume ○ Length ○ Area ○ By Cell | □ Z...
- "Close" button — not OK/Cancel (live edits)

This should be the direct template for STREAM.jl's Channel Geometry editor, with `Dh` added as a column and `Volume` dropped (STREAM.jl uses cross-sectional area + length, not volume directly).

Page 80 (Figure 7.2 — 3D Model Viewer) shows the camera control panel layout: vertical strip of labelled buttons on the left edge of the viewer window. The main viewport shows 3D component icons. This is informative for if/when a 3D view is added, but not v0 scope.

The Property View (Figures 3.2 and 3.10) shows the two-column table layout: property name left (with bold for required), editable value right, small icon buttons far right (help "?", ownership lock). This is the right pattern — compact, scannable, consistent.

---

## Ambiguities Not Resolved by the Documents

These were flagged in the raw extractions and remain unresolved — they need design decisions or further research before planning starts:

1. **Canvas coordinate system** — The CAFEAN report describes `ZoomablePanel` / `BeanBox` but not the coordinate-space convention. For STREAM.jl: use logical coordinates (component centers in "model units"), zoom is a display scale factor, all positions stored in logical coordinates.

2. **Exact pipe "general properties" field list** — Manual references Figure 3.10 but doesn't enumerate top-level fields. Screenshot confirms: Component Name, Component Number, Description, Geometry (button), Friction Data (button), Initial Conditions (button). This is the template for STREAM.jl's Channel top-level property panel.

3. **Whether 3D viewer is in-process or separate window** — Screenshot (Figure 7.2) shows it as a separate window with its own title bar. For STREAM.jl: don't separate; if added, embed in the multi-view panel.

4. **Full correlation/closure catalog per component type** — Not enumerated in the manual. For STREAM.jl: enumerate from `src/physical_models/correlations.jl` directly at implementation time.

5. **Wire protocol to Calculation Server** — Not described. Irrelevant for STREAM.jl (in-process solve).

---

*Generated from full text extraction of both PDFs (36,600 words) + targeted visual reads of pages 1–12, 74–84, 13–25 of SNAP_docs.pdf. Raw extraction files preserved in this directory.*
