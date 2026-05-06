# Feature Research

**Domain:** Desktop GUI for visual composition of STREAM.jl thermal-hydraulic systems (node-based editor)
**Researched:** 2026-04-01
**Confidence:** HIGH (well-established domain with mature tooling; requirements already defined in REQUIREMENTS.md)

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist in any node-based visual editor for simulation systems. Missing these means the product feels broken.

#### Canvas & Node Editing

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Drag-drop component creation from toolbox | Every node editor has this (ComfyUI, Simulink, OMEdit, Blender Geometry Nodes). Without it, the tool has no purpose. | MEDIUM | ReactFlow provides drag-and-drop primitives. Custom drag-from-toolbox requires `onDragStart` on toolbox items + `onDrop` on canvas with coordinate translation. |
| Pan, zoom, scroll on canvas | Users expect infinite canvas behavior from any diagramming tool. | LOW | ReactFlow built-in: `<ReactFlow panOnDrag zoomOnScroll>`. Minimap and Controls components included. |
| Minimap for orientation | Standard in ReactFlow-based editors; users expect a thumbnail overview for large graphs. | LOW | `<MiniMap />` component from `@xyflow/react`. One import, one line. |
| Connect ports by dragging from handle to handle | The fundamental interaction pattern for node-based editors. Without it there is no graph. | MEDIUM | ReactFlow `<Handle>` components with `type="source"` / `type="target"`. Custom handle IDs for multi-port nodes. |
| Delete nodes and edges (select + Del/Backspace) | Basic editing. Users will rage-quit without this. | LOW | ReactFlow built-in: `deleteKeyCode="Delete"` prop. Multi-select with Shift+click or box selection. |
| Move nodes without losing connections | Fundamental expectation. Edges must follow their connected nodes. | LOW | ReactFlow built-in behavior. Edges automatically re-route on node position change. |
| Node displays component type and instance name | Users need to identify what each node is. Unnamed rectangles are useless. | LOW | Custom node component renders `data.label` (type) + `data.instanceName`. |

#### Parameter Editing

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Click-to-select opens property panel | Simulink, ComfyUI, OMEdit all use click-to-inspect. The pattern is universal. | LOW | `onNodeClick` handler sets selected node ID in state; sidebar reads from node data. |
| Editable scalar parameter fields | Users must configure component physics (dP, L, D, etc.). | MEDIUM | Dynamic form generation from component metadata registry. shadcn/ui `<Input>` with type validation. |
| Rename component instance | Engineers name things (`pump_primary`, `ch_hot`). The `@named` macro requires a valid Julia identifier. | LOW | Text input with regex validation: `/^[a-zA-Z_][a-zA-Z0-9_]*$/`. Reject Julia reserved words. |
| Per-field validation (type, range, required) | Entering "abc" for a pressure value should show an error, not silently generate broken code. | MEDIUM | Validate on blur: numeric check, non-empty check, optional physical range check (e.g., temperature > 0 K). |

#### Code Generation

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Export to `.jl` file | The stated output contract. Without this, the GUI produces nothing usable. | LOW | `toObject()` on ReactFlow instance -> transform to Julia AST -> render to string -> Tauri `save_dialog` + `write_file`. |
| Correct `@named` + `connect()` + `compose()` output | Generated code must actually run in Julia. Wrong constructor signatures or missing `mtkcompile` = useless output. | HIGH | Must match CLAUDE.md conventions: positional vs keyword args vary by component. Registry JSON drives the code template per component type. |
| Live code preview | Users want to see what they are building. "What will this generate?" is the first question. | MEDIUM | Debounced re-generation on any graph or parameter change. Read-only Monaco editor or `<pre>` block in a collapsible panel. |

#### Project Persistence

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Save project (Ctrl+S) | Any desktop app. Losing work on close is unacceptable. | LOW | ReactFlow `toObject()` + component parameter data -> JSON -> Tauri `save_dialog`. Custom `.streamgui` extension. |
| Open project (Ctrl+O) | Complement to save. | LOW | Tauri `open_dialog` with filter -> parse JSON -> set nodes/edges/viewport. |
| Unsaved changes guard | Losing work on accidental close is a top user complaint for any editor. | LOW | Track dirty flag (set on any graph mutation, clear on save). `beforeunload` event + Tauri window close hook. |

### Differentiators (Competitive Advantage)

Features that set STREAM Composer apart from generic diagramming tools and make it genuinely useful for STREAM.jl users.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Typed port validation (FlowPort vs ThermalPort) | Prevents connecting incompatible port types. No generic node editor does this without customization. ComfyUI does it for its domain; STREAM Composer does it for thermal-hydraulics. | MEDIUM | `isValidConnection` callback on `<ReactFlow>` checks source handle type matches target handle type. Store port type in handle ID convention (e.g., `flow-out`, `thermal-left-3`). |
| PipeGeometry picker (circular vs rectangular) | Channel components need geometry configuration. A picker with dynamic fields (L,D vs L,W,H) is more ergonomic than raw number entry. | MEDIUM | Conditional form: radio/select for shape, then shape-specific dimension fields. Maps to `PipeGeometry_circular(L,D)` or `PipeGeometry_rectangular(L,W,H)` in generated code. |
| Pump mode toggle (fixed-dP vs fixed-mdot) | Pump has two constructor dispatch paths. A toggle makes this discoverable instead of requiring users to know the API. | LOW | Radio group or toggle switch. Changes which parameter field is shown (dP_pump vs mdot0). Maps to `Pump(30000.0)` vs `Pump(; mdot0=0.5)`. |
| Boundary condition panel | Pressure anchors and thermal pins are not obvious from the graph. A dedicated BC panel that lists required BCs and lets users set values prevents the #1 "why doesn't my model solve" error. | MEDIUM | Separate panel or sidebar tab. Auto-detects: (1) which component ports need pressure anchor, (2) which thermal pins exist. Generates `pump.inlet.P ~ 1.0e5` etc. |
| Topology validation alerts (unconnected ports, missing pump/pressure anchor) | Catches the three most common user errors before they waste time running Julia. OMEdit has similar checks; no generic node editor does. | MEDIUM | Graph analysis on each mutation: (1) scan for nodes with unconnected mandatory ports, (2) check for at least one Pump or Gravity, (3) check for at least one pressure anchor BC. Non-blocking banner alerts. |
| ThermalPort array handles (stacked port visualization) | ChannelAndContacts has `thermal_left[1:n]` and `thermal_right[1:n]`. Visualizing these as stacked handles on the node edge (count = parameter `n`) is a unique feature for thermal-hydraulic modeling. | HIGH | Dynamic handle count based on `n` parameter. Requires custom node rendering that reacts to parameter changes. Handle IDs encode index: `thermal-left-1`, `thermal-left-2`, etc. |
| Smart thermal composition code-gen | Detects symmetric/asymmetric/one-sided wiring patterns and emits `symmetric_plate()`, `plate()`, or `one_sided_connection()` instead of raw `connect()` loops. This is domain-specific intelligence no generic tool provides. | HIGH | Pattern recognition on the thermal subgraph: if both sides of HeatDiffusion connect to same CAC -> `symmetric_plate`; different CACs -> `plate`; one side only -> `one_sided_connection`. |
| Undo/redo (Ctrl+Z / Ctrl+Shift+Z) | Expected in desktop apps, but many node editors ship without it. Having it is a differentiator vs quick-and-dirty tools. | MEDIUM | Zustand + Zundo middleware. Selective recording: batch drag operations into single undo steps. Record add/delete node, add/delete edge, parameter changes. |
| Recent projects list on startup | Small touch that makes the app feel professional. | LOW | Store last 5 file paths in Tauri app data (localStorage or `app_data_dir`). Display on empty canvas screen. |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems for this specific use case.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Embedded Julia runtime (live validation) | "Validate my model in real-time" | Julia TTFX is 10-30s for STREAM.jl. Embedding libjulia adds massive complexity (C FFI, process management, error marshalling). Makes GUI depend on Julia installation. Couples two fast-moving codebases. | Generate `.jl` files only. Add optional Oxygen.jl HTTP backend in v0.9+ after proving the GUI concept. |
| Round-trip `.jl` parsing (import Julia code into graph) | "Load my existing scripts" | Parsing arbitrary Julia code back into a constrained graph IR is a compiler problem. Julia's AST is complex. Hand-edited code may not map cleanly to graph nodes. Maintenance burden is enormous. | One-way code generation. If users want to edit, they edit the `.jl` file. GUI is for composition, not general Julia editing. |
| Correlation closure editing in GUI | "Let me configure `regime_dependent(htc_laminar=..., htc_turbulent=...)`" | Closures are nested function calls with keyword arguments. Representing this in a form UI requires recursive parameter forms or a code editor widget. The combinatorial space of correlation configurations is large. | Defer to v0.9+. For v0.8, use sensible defaults (Dittus-Boelter for turbulent, constant Nu for laminar). Show a "correlation" field as read-only text with a note "edit in generated .jl file". |
| Multi-way junction nodes (3+ port connections) | "I need T-junctions and manifolds" | STREAM.jl uses variadic `connect(a, b, c)` for junctions, which has no visual 1:1 mapping. Junction nodes add visual complexity and a new node type that doesn't correspond to any STREAM.jl component. | Defer to v0.9+. For v0.8, limit to 1:1 connections (linear loops). The Cube problem (12 Resistors, 8 junctions) is an advanced use case. |
| Simulation execution from GUI | "Click Run and see results" | Requires Julia backend, process management, result visualization (plotting). Each of these is a major feature. Conflates "composer" with "IDE". | STREAM Composer is a code generator. User runs the `.jl` file in their own Julia REPL/VS Code. Separation of concerns. |
| Auto-layout (automatic node positioning) | "Arrange my nodes nicely" | ElkJS integration is non-trivial. Auto-layout often produces worse results than manual placement for domain-specific diagrams (loops, parallel branches). Users undo auto-layout more often than they keep it. | Manual positioning with snap-to-grid. Consider adding auto-layout as an optional "tidy up" button in v0.9+ if users request it. |
| In-node parameter editing (inline forms) | "Edit parameters directly on the node like ComfyUI" | Makes nodes large and cluttered. STREAM.jl components have 5-15 parameters each. Inline editing works for ComfyUI (2-3 fields per node) but not for engineering components with many typed parameters. | Sidebar panel for parameter editing. Node shows only type + name + key parameter summary (e.g., "Pump: 30 kPa"). |
| Drag-and-drop from file system | "Drop a .streamgui file onto the canvas" | Requires Tauri file drop event handling. Edge case: what if canvas has unsaved changes? What if file is malformed? Adds complexity for a rare interaction. | File > Open menu item + Ctrl+O shortcut. Standard and predictable. |
| Dark mode / theme switching | "Every app should have dark mode" | Adds CSS complexity across every component. shadcn/ui supports it, but testing doubles. First version should nail one theme. | Ship with light theme only. Add dark mode in a future polish pass if users request it. |

## Feature Dependencies

```
[Component Registry JSON] (SCAF-03)
    |
    +--requires--> [Canvas Node Editor] (CANV-01..07)
    |                  |
    |                  +--requires--> [Parameter Editing Sidebar] (PARA-01..06)
    |                  |                  |
    |                  |                  +--enhances--> [Code Generation] (CODE-01..07)
    |                  |
    |                  +--requires--> [Code Generation] (CODE-01..07)
    |
    +--requires--> [Code Generation] (CODE-01..07)

[Canvas Node Editor] (CANV-01..07)
    +--requires--> [Project Persistence] (PERS-01..04)
    |                  (save/load needs nodes+edges+params to exist)
    |
    +--enhances--> [Topology Validation] (VALD-01..03)
                       (validation analyzes existing graph)

[Parameter Editing Sidebar] (PARA-01..06)
    +--enhances--> [PipeGeometry picker] (PARA-04)
    +--enhances--> [Pump mode toggle] (PARA-03)

[Topology Validation] (VALD-01..03)
    +--requires--> [Boundary Condition Panel] (CODE-06)
                       (BC panel generates the anchors that validation checks for)

[ThermalPort Array Handles] (THERM-01)
    +--requires--> [Canvas Node Editor] (basic node rendering must work first)
    +--requires--> [Parameter Editing] (n parameter drives handle count)
    +--enhances--> [Smart Thermal Code-Gen] (THERM-03)

[Smart Thermal Code-Gen] (THERM-03)
    +--requires--> [ThermalPort Array Handles] (THERM-01)
    +--requires--> [Code Generation] (CODE-01..07)
    +--requires--> [HeatDiffusion Wiring] (THERM-02)
```

### Dependency Notes

- **Registry requires nothing:** The JSON metadata is the foundation. It can be written before any UI exists and validated independently.
- **Canvas requires Registry:** Custom nodes render based on registry metadata (port definitions, type labels).
- **Parameter Editing requires Canvas:** There is nothing to edit without nodes on canvas. The sidebar reads from selected node data.
- **Code Generation requires Registry + Canvas:** It transforms graph topology (from canvas) using component metadata (from registry) into Julia code.
- **Persistence requires Canvas + Parameters:** Save/load serializes the full graph state including parameter values.
- **Validation requires Canvas + BCs:** Topology analysis runs on the live graph. Pressure anchor detection needs the BC panel to exist.
- **Thermal features require all basics:** ThermalPort arrays, HeatDiffusion wiring, and smart code-gen are the most complex features and depend on every foundation layer working correctly.
- **Undo/redo is independent of domain features:** It operates on the Zustand store level and can be added at any phase after the store exists.

## MVP Definition

### Launch With (v0.8 Phase 33-37)

Minimum viable product -- what is needed to validate that the GUI concept works and produces runnable STREAM.jl code.

- [ ] Tauri 2 + React + ReactFlow scaffold with hot-reload dev mode (SCAF-01)
- [ ] Component metadata registry for all 9 STREAM.jl hydraulic components (SCAF-03)
- [ ] Drag-drop nodes from toolbox onto canvas (CANV-02)
- [ ] FlowPort edge connections with type-safe handles (CANV-03)
- [ ] Node deletion, edge deletion, free repositioning (CANV-04, CANV-05)
- [ ] Parameter editing sidebar with scalar fields (PARA-01, PARA-02)
- [ ] PipeGeometry picker for channel components (PARA-04)
- [ ] Pump mode toggle (PARA-03)
- [ ] Instance renaming with Julia identifier validation (PARA-05)
- [ ] Live code preview panel (CODE-01)
- [ ] Export to `.jl` with correct `@named` + `connect()` + `compose()` + `mtkcompile()` (CODE-02..05)
- [ ] Boundary condition panel for pressure anchor + thermal pins (CODE-06)
- [ ] Save/load `.streamgui` JSON project files (PERS-01, PERS-02)
- [ ] Unsaved changes guard (PERS-03)

### Add After Validation (v0.8 Phase 38-40)

Features to add once the core editor works end-to-end.

- [ ] Undo/redo with Zustand + Zundo (CANV-07) -- add when basic editing is solid
- [ ] shadcn/ui design pass across all panels (DSGN-01..04) -- add when layout is stable
- [ ] Topology validation alerts (VALD-01..03) -- add when BC panel exists
- [ ] ThermalPort array handles on ChannelAndContacts (THERM-01) -- add when basic FlowPort canvas is proven
- [ ] HeatDiffusion node wiring (THERM-02) -- add after thermal handles work
- [ ] Smart thermal code-gen with composition helpers (THERM-03) -- add last, depends on all thermal features
- [ ] Recent projects list (PERS-04) -- polish feature, add whenever convenient

### Future Consideration (v0.9+)

Features to defer until v0.8 is shipped and user feedback is collected.

- [ ] Correlation closure editing -- complex nested forms; defer until users hit the limitation
- [ ] Multi-way junction nodes -- needed for advanced topologies (Cube problem); defer until linear loops are validated
- [ ] Live Julia validation backend (Oxygen.jl) -- requires Julia installation + startup time management
- [ ] Auto-layout (ElkJS) -- optional polish; manual positioning is sufficient
- [ ] Simulation execution from GUI -- conflates composer with IDE
- [ ] Round-trip `.jl` parsing -- compiler-level difficulty; not worth the investment
- [ ] Dark mode -- cosmetic; ship light theme first
- [ ] Native installers for Windows/Linux (SCAF-02) -- defer to end of v0.8 or v0.9; dev mode is sufficient for validation

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority | Phase |
|---------|------------|---------------------|----------|-------|
| Component metadata registry | HIGH | LOW | P1 | 33 |
| Canvas with drag-drop + connections | HIGH | MEDIUM | P1 | 34 |
| Parameter editing sidebar | HIGH | MEDIUM | P1 | 35 |
| Code generation + export | HIGH | HIGH | P1 | 36 |
| Project save/load | HIGH | LOW | P1 | 37 |
| Boundary condition panel | HIGH | MEDIUM | P1 | 36 |
| PipeGeometry picker | MEDIUM | MEDIUM | P1 | 35 |
| Pump mode toggle | MEDIUM | LOW | P1 | 35 |
| Undo/redo | MEDIUM | MEDIUM | P2 | 34 or 38 |
| Topology validation | MEDIUM | MEDIUM | P2 | 39 |
| shadcn/ui design pass | MEDIUM | MEDIUM | P2 | 38 |
| ThermalPort array handles | MEDIUM | HIGH | P2 | 40 |
| HeatDiffusion wiring | MEDIUM | HIGH | P2 | 40 |
| Smart thermal code-gen | MEDIUM | HIGH | P2 | 40 |
| Recent projects list | LOW | LOW | P2 | 37 |
| Correlation editing | MEDIUM | HIGH | P3 | v0.9+ |
| Multi-way junctions | LOW | MEDIUM | P3 | v0.9+ |
| Live Julia backend | MEDIUM | HIGH | P3 | v0.9+ |
| Auto-layout | LOW | MEDIUM | P3 | v0.9+ |
| Round-trip parsing | LOW | HIGH | P3 | Never |

**Priority key:**
- P1: Must have for v0.8 launch
- P2: Should have in v0.8, add after core works
- P3: Defer to v0.9+ or later

## Competitor Feature Analysis

| Feature | ModelingToolkitDesigner.jl | JuliaHub Dyad | OMEdit (Modelica) | ComfyUI | Our Approach |
|---------|---------------------------|---------------|-------------------|---------|--------------|
| Node-based canvas | GLMakie keyboard nav | Full drag-drop | Qt drag-drop | Canvas drag-drop | ReactFlow drag-drop |
| Typed port validation | N/A (manual connect) | Yes | Yes (Modelica types) | Yes (per-socket type) | `isValidConnection` on FlowPort/ThermalPort types |
| Parameter editing | Julia REPL | In-IDE sidebar | Properties dialog | In-node widgets | Right sidebar with dynamic forms |
| Code generation | Partial (.toml + .jl) | Built-in (1:1 mapping) | Modelica text output | JSON workflow export | Full Julia code with `@named` + `connect()` + `compose()` |
| Save/load project | `.toml` file | Cloud workspace | `.mo` files | JSON workflow | `.streamgui` JSON |
| Boundary conditions | Manual in Julia | GUI panel | Modelica annotations | N/A | Dedicated BC panel |
| Thermal port arrays | N/A | Component library | Modelica arrays | N/A | Stacked handles with dynamic count |
| Requires runtime | Yes (Julia + GLMakie) | Yes (cloud) | Yes (OMC) | Yes (Python) | No (file-only output) |
| Cost | Free/OSS | Commercial | Free/OSS | Free/OSS | Free/OSS |

**Key competitive insight:** STREAM Composer's differentiator is that it requires no runtime dependency. It generates inspectable, versionable `.jl` files. Every other tool in this space requires the simulation backend to be running. This makes distribution trivial and decouples the GUI from Julia's TTFX problem.

## Sources

- [ReactFlow Custom Nodes](https://reactflow.dev/learn/customization/custom-nodes) -- custom node rendering, handle configuration
- [ReactFlow Connection Validation](https://reactflow.dev/examples/interaction/validation) -- `isValidConnection` for typed port checking
- [ReactFlow Handle Component](https://reactflow.dev/api-reference/components/handle) -- port definitions, connection limits
- [ReactFlow Save and Restore](https://reactflow.dev/examples/interaction/save-and-restore) -- `toObject()` / `fromObject()` persistence pattern
- [ReactFlow Undo and Redo](https://reactflow.dev/examples/interaction/undo-redo) -- Zustand + Zundo middleware pattern
- [ReactFlow State Management](https://reactflow.dev/learn/advanced-use/state-management) -- Zustand integration patterns
- [ComfyUI Interface Overview](https://docs.comfy.org/interface/overview) -- sidebar panel UX patterns for node editors
- [ComfyUI sidebar feature request #8635](https://github.com/comfyanonymous/ComfyUI/issues/8635) -- evidence that in-node editing is insufficient for complex parameters
- [Flume](https://flume.dev/) -- JSON graph to business logic extraction pattern
- [Rete.js](https://retejs.org/) -- alternative node editor with code generation capabilities
- [xyflow/awesome-node-based-uis](https://github.com/xyflow/awesome-node-based-uis) -- curated list of node-based UI references
- STREAM.jl feasibility research: `.planning/research/gui-feasibility/RESEARCH.md` (HIGH confidence)
- STREAM.jl requirements: `.planning/REQUIREMENTS.md` v0.8 section (HIGH confidence)

---
*Feature research for: STREAM Composer GUI (v0.8)*
*Researched: 2026-04-01*
