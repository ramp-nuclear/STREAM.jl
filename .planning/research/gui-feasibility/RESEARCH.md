# GUI Companion for STREAM.jl - Feasibility Research

**Researched:** 2026-03-31
**Domain:** Desktop GUI / Visual block-diagram editor / Julia backend integration
**Confidence:** MEDIUM (some areas HIGH, some LOW)
**Type:** Feasibility study (not implementation planning)

---

## Executive Summary

Building a visual drag-and-drop GUI for composing STREAM.jl thermal-hydraulic systems is **feasible and moderately complex**. The core technical challenge -- translating a visual graph into valid Julia/MTK code -- is actually the *easiest* part, because STREAM.jl's component API is remarkably uniform: every component has `inlet`/`outlet` FlowPorts, some have ThermalPort arrays, and composition is a flat list of `connect()` calls plus boundary conditions. The harder parts are (1) getting a polished node-based editor working cross-platform and (2) handling the parameter editing UX for components with complex kwargs (correlation closures, PipeGeometry, etc.).

The recommended path is a **Tauri 2 + React + ReactFlow** desktop app that generates `.jl` files as output. Julia runs as a separate process (not embedded). The GUI is a code generator, not a live simulation environment. This approach minimizes coupling, avoids the Julia startup time problem entirely, and produces artifacts (`.jl` files) that users can inspect, version-control, and modify by hand.

An MVP covering the 8 core STREAM.jl components with FlowPort-only connections could be built in **3-5 person-weeks**. Full-featured (ThermalPort arrays, HeatDiffusion composition helpers, validation) would be **8-12 person-weeks**.

**Primary recommendation:** Tauri 2 + React + ReactFlow desktop app that exports `.jl` files. No live Julia backend needed for MVP.

---

## 1. Ecosystem Survey -- What Already Exists

### 1.1 ModelingToolkitDesigner.jl (Julia-native)

**What:** A GLMakie-based visual editor for MTK system connections. Latest release v1.4.0 (Jan 2025). 67 commits total.

**Strengths:**
- Native Julia, directly manipulates MTK objects
- Icons for ModelingToolkitStandardLibrary pre-loaded
- Saves visualization as `.toml`, connection code as `.jl`

**Limitations:**
- Built on GLMakie (OpenGL) -- requires Julia runtime, heavy dependency
- Small project, single maintainer (bradcarman)
- Missing features: auto connection equation generation not yet implemented
- UI is basic (keyboard navigation, not drag-and-drop in the modern web sense)
- No STREAM.jl component icons or awareness
- Requires users to have Julia installed and running

**Verdict:** Interesting proof of concept, but not suitable as a standalone GUI for non-programmers. It assumes the user already has Julia + MTK running. However, its `.toml` + `.jl` output format is a good reference for what code generation should produce.

**Confidence:** HIGH (verified via GitHub repo)

### 1.2 JuliaHub Dyad

**What:** Commercial "AI-native simulation platform" by JuliaHub. Drag-and-drop visual modeling with 1:1 mapping between graphical models and Julia code. Dyad v2.0.0 announced Dec 2025.

**Strengths:**
- Full-featured visual modeling IDE
- Pre-validated component libraries
- One-to-one graphical-to-code mapping
- Synopsys partnership (serious commercial backing)

**Limitations:**
- Commercial product (source-available license, free for education/non-commercial only)
- Cloud-hosted platform (not a local desktop tool)
- No STREAM.jl integration (uses its own standard libraries)
- Pricing opaque (contact sales)

**Verdict:** Dyad is the "if money were no object" solution, but it's a platform lock-in, not an open tool. It validates the concept (visual MTK modeling works commercially) but isn't usable for STREAM.jl directly.

**Confidence:** HIGH (verified via JuliaHub official pages)

### 1.3 OpenModelica OMEdit (Reference Architecture)

**What:** Open-source Modelica graphical editor. C++ / Qt. Communicates with OpenModelica Compiler via CORBA.

**Architecture lessons:**
- Frontend (Qt GUI) is completely separate from backend (OMC compiler)
- Communication over IPC (CORBA), not embedding
- Model stored as Modelica text + graphical annotations
- This separation of concerns is the proven architecture for simulation GUIs

**Verdict:** Good architectural reference. The frontend-backend separation pattern is well-proven in the simulation world.

**Confidence:** HIGH (well-documented open-source project)

### 1.4 Nothing STREAM.jl-Specific Exists

No visual editor, Jupyter widget, or Pluto extension exists for STREAM.jl specifically. The Python STREAM project has `FlowGraph` (a programmatic graph-based composition using NetworkX `DiGraph`/`MultiDiGraph`), but it is purely code -- no GUI. The FlowGraph concept maps well to what a GUI would produce, though.

---

## 2. Architecture Options

### 2.1 Frontend Framework Comparison

| Framework | Bundle Size | Startup | Cross-platform | Web Tech | Claude Code Buildable |
|-----------|-------------|---------|----------------|----------|----------------------|
| **Tauri 2 + React** | ~5-10 MB | <0.5s | Win/Linux/Mac | Yes (system WebView) | YES -- proven by Claudia, opcode |
| Electron + React | ~100+ MB | 1-2s | Win/Linux/Mac | Yes (bundled Chromium) | YES -- proven by CodePilot |
| Qt (C++/Python) | ~30 MB | Fast | Win/Linux/Mac | No | HARDER -- requires Qt expertise |
| Pure web app | 0 (browser) | Instant | Any browser | Yes | YES |

**Recommendation: Tauri 2 + React.**

Rationale:
- Multiple Claude Code-built Tauri 2 apps already exist (Claudia, opcode) -- this is proven territory for AI-assisted coding
- Small bundles, fast startup, cross-platform
- React ecosystem gives access to ReactFlow (the best node editor library)
- Tauri 2 stable since late 2024, strong momentum (17.7K Discord, 35% YoY adoption growth)
- No need for Rust backend complexity -- the Rust side just serves the webview and handles file I/O

**Alternative considered:** Pure web app (no desktop wrapper) would be even simpler. User runs `julia -e 'using HTTP; serve()'` and opens a browser. This is the lightest path if cross-platform desktop packaging isn't required. Could be an MVP-before-MVP.

### 2.2 Node Editor Library

| Library | Weekly Downloads | Stars | Multi-framework | Typed Ports | Best For |
|---------|-----------------|-------|-----------------|-------------|----------|
| **ReactFlow** | 800K+ | 26K+ | React only | Yes (custom handles) | Our use case |
| Rete.js | 26K | 12K | React/Vue/Angular/Svelte | Yes | Multi-framework |
| Drawflow | 11K | 6K | Vue-focused | Limited | Simple flows |
| Litegraph.js | 935 | 8K | Vanilla JS (Canvas) | Yes | ComfyUI-style |

**Recommendation: ReactFlow.**

Rationale:
- Dominant market position (800K weekly downloads)
- TypeScript-first, excellent custom node support
- Built-in: zoom, pan, minimap, controls, node types, edge types
- Custom handles (ports) with validation -- exactly what STREAM.jl needs
- ElkJS integration for auto-layout
- Extensive examples including engineering-style multi-port nodes
- MIT licensed (open source, Pro tier for commercial extras)

### 2.3 Julia Backend Integration Options

| Approach | Complexity | Startup Time | Coupling | Best For |
|----------|-----------|--------------|----------|----------|
| **File generation (no backend)** | LOW | N/A | None | MVP |
| Julia HTTP server (Oxygen.jl) | MEDIUM | 10-30s first load | Loose | Live validation |
| Julia CLI subprocess | LOW-MEDIUM | 10-30s per call | Loose | On-demand execution |
| Embedded libjulia | HIGH | Complex | Tight | Real-time sim (not needed) |

**Recommendation: File generation only (MVP). HTTP server as optional Phase 2.**

Rationale for file-only MVP:
- Julia's first-load latency (TTFX) is 10-30 seconds for STREAM.jl -- unacceptable for interactive GUI
- The user's stated acceptance: "output being a Julia code file (.jl) that they then run"
- File generation has zero runtime dependencies -- GUI works without Julia installed
- Generated `.jl` files are inspectable, version-controllable, editable
- Eliminates entire class of bugs (IPC, process management, error marshalling)

If live validation is later desired, Oxygen.jl (lightweight Flask-like Julia HTTP framework) would be the simplest backend. The GUI would POST the graph JSON, Julia validates it and returns errors. But this is a Phase 2 concern.

---

## 3. Graph-to-Code Translation

### 3.1 How Hard Is It?

**Answer: Surprisingly easy for STREAM.jl specifically.**

STREAM.jl's component API has exceptional uniformity:

1. **Every component** has `inlet` and `outlet` (FlowPort)
2. **Thermal components** additionally have `thermal_left[1:n]` and `thermal_right[1:n]` (ThermalPort arrays)
3. **Composition** is always: create named components, then `connect()` ports, then `compose()` + `mtkcompile()`
4. The `build_loop` example is 15 lines of actual logic

### 3.2 Translation Algorithm

Given a graph with nodes and edges:

```
Input:  { nodes: [{id, type, params}], edges: [{source, target, sourcePort, targetPort}] }
Output: Valid Julia code
```

**Step 1: Component instantiation**
```julia
# For each node in graph:
@named pump = Pump(30000.0)
@named ch = Channel(n=10, geometry=PipeGeometry_circular(0.6, 0.01))
@named bc = HeatExchanger(313.15)
```

**Step 2: Connection equations**
```julia
# For each edge in graph:
connections = [
    connect(pump.outlet, bc.inlet),
    connect(bc.outlet, ch.inlet),
    connect(ch.outlet, pump.inlet),
]
```

**Step 3: Boundary conditions** (user-specified in properties panel)
```julia
push!(connections, pump.inlet.P ~ 1.0e5)
push!(connections, ch.thermal.T ~ 373.15)
```

**Step 4: System composition**
```julia
@named sys = compose(System(connections, t; name=:sys), pump, bc, ch)
ssys = mtkcompile(sys)
```

### 3.3 Component Metadata Schema

Each STREAM.jl component needs a JSON descriptor for the GUI:

```json
{
  "id": "Pump",
  "label": "Pump",
  "category": "Hydraulic",
  "ports": {
    "inlet":  { "type": "FlowPort", "side": "left" },
    "outlet": { "type": "FlowPort", "side": "right" }
  },
  "parameters": [
    { "name": "dP_pump", "type": "Real", "unit": "Pa", "default": 30000,
      "description": "Pressure rise" }
  ],
  "constructorModes": [
    { "mode": "scalar_dP", "signature": "Pump(dP_pump; name)" },
    { "mode": "fixed_flow", "signature": "Pump(; name, mdot0)" }
  ]
}
```

### 3.4 Edge Cases and Hard Parts

| Challenge | Difficulty | Notes |
|-----------|-----------|-------|
| **Simple FlowPort connections** | EASY | Direct 1:1 mapping: edge -> `connect(a.outlet, b.inlet)` |
| **Multi-way junctions** | MEDIUM | Cube example: `connect(pump.outlet, r01.inlet, r02.inlet, r04.inlet)`. GUI needs junction nodes. |
| **ThermalPort arrays** | MEDIUM | `port(cac, :thermal_left, i)` for i in 1:n. GUI needs to show port arrays, or use composition helpers. |
| **Composition helpers** | MEDIUM | `symmetric_plate(cac, fuel)` wraps multiple connects. GUI could emit helper calls instead of raw connects. |
| **Correlation closures** | HARD | `htc_correlation=dittus_boelter` or `regime_dependent(...)`. Need dropdown + nested parameter forms. |
| **Callable parameters** | HARD | `Pump(t -> 30000*(1-t/10))`. Would need a code editor widget or predefined profiles. |
| **Boundary conditions** | MEDIUM | `pump.inlet.P ~ 1.0e5`. Need a "boundary conditions" panel. Not obvious from graph topology alone. |
| **PipeGeometry** | EASY-MEDIUM | `PipeGeometry_circular(L, D)` or `PipeGeometry_rectangular(...)`. Dropdown + fields. |

### 3.5 Scope Reduction for MVP

**MVP scope (FlowPort-only, no thermal):**
- Components: Pump, Resistor, Gravity, Friction, Inertia, HeatExchanger, Channel, ChannelHeatFlux
- Ports: FlowPort only (inlet, outlet)
- Parameters: Scalar values only (no closures, no callables)
- Connections: Direct 1:1 (no multi-way junctions)
- Output: `.jl` file with `build_*`-style code
- Boundary conditions: Pressure anchor + thermal pin (template-based)

**Full scope additions:**
- ChannelAndContacts with ThermalPort arrays
- HeatDiffusion with plate composition helpers
- Correlation selection dropdowns
- Multi-way junctions
- Callable parameter support (code editor widget)
- Live Julia validation backend
- Save/load project files

---

## 4. Effort Estimate

### 4.1 MVP (FlowPort-only graph editor + code export)

| Task | Effort | Notes |
|------|--------|-------|
| Tauri 2 + React project scaffolding | 1 day | `npm create tauri-app`, configure |
| ReactFlow canvas with custom node components | 3-4 days | Custom nodes with typed handles, drag from toolbox |
| Component metadata schema + registry | 1-2 days | JSON descriptors for 8 components |
| Parameter editing sidebar | 2-3 days | Dynamic form from component schema |
| Graph-to-Julia code generator | 2-3 days | Template-based, handles connect() + compose() |
| Boundary condition editor | 1-2 days | Pressure anchor, thermal pins |
| File save/load (project persistence) | 1 day | JSON graph state |
| Export to `.jl` file | 0.5 days | File dialog + write |
| Basic testing + polish | 2-3 days | Cross-platform smoke test |
| **Total MVP** | **~3-4 weeks** | One developer, full-time |

### 4.2 Full-Featured

| Additional Task | Effort | Notes |
|----------------|--------|-------|
| ThermalPort array visualization | 1 week | Port arrays on node edges, indexed connections |
| Composition helper integration | 1 week | `symmetric_plate`, `plate`, `one_sided_connection` as meta-nodes |
| Correlation dropdown + config | 3-4 days | Nested parameter forms for `regime_dependent(...)` |
| Multi-way junction nodes | 2-3 days | Special node type for 3+ port connections |
| Julia HTTP backend (validation) | 1 week | Oxygen.jl server, syntax check, component existence validation |
| Undo/redo | 2-3 days | State management with history |
| Auto-layout (ElkJS) | 2-3 days | Automatic node positioning |
| **Total Full-Featured** | **~8-12 weeks** | One developer, full-time |

### 4.3 Complexity Assessment: MEDIUM

This is not a trivial project, but it is well-bounded:
- The domain is constrained (finite component set, known port types)
- The output format is simple (Julia text files)
- No real-time rendering, 3D, or animation required
- No complex state synchronization (file export, not live sim)
- The hardest UI challenge is the parameter editing forms, not the graph canvas

---

## 5. Claude Code Suitability -- Honest Assessment

### 5.1 What Claude Code is Good At Here

| Aspect | Suitability | Why |
|--------|-------------|-----|
| Tauri 2 scaffolding | HIGH | Proven: multiple Claude-built Tauri apps exist (Claudia, opcode, CodePilot) |
| React components | HIGH | Claude excels at React component authoring |
| ReactFlow integration | HIGH | Well-documented API, many examples to reference |
| TypeScript types/interfaces | HIGH | Type definitions for component metadata |
| Code generation logic | HIGH | String template generation is straightforward |
| Julia code output | HIGH | Claude knows Julia + MTK patterns from this project |

### 5.2 What Claude Code Will Struggle With

| Aspect | Risk | Mitigation |
|--------|------|------------|
| **CSS layout/styling** | MEDIUM | ReactFlow handles canvas; sidebar forms are standard. Use Tailwind + shadcn/ui. |
| **Tauri Rust backend** | LOW-MEDIUM | MVP needs minimal Rust (file I/O only). For HTTP backend, Julia handles it. |
| **Drag-and-drop UX polish** | MEDIUM | ReactFlow provides primitives; custom drag-from-toolbox needs iteration. |
| **Cross-platform testing** | HIGH | Claude cannot run GUI tests. User must manually verify on Windows + Linux. |
| **Complex state management** | MEDIUM | ReactFlow has built-in state. Zustand or Redux for global state. |
| **Edge case debugging** | MEDIUM | Visual bugs require human eyes. Layout glitches need manual iteration. |

### 5.3 Overall Verdict

**Claude Code can build 70-80% of this project effectively.** The remaining 20-30% (visual polish, cross-platform edge cases, UX feel) requires human iteration. This is typical for GUI projects -- the functionality comes fast, but making it "feel right" takes manual testing cycles.

**Specific GSD suitability:**
- Phase planning works well for the backend (code generation, component registry, data model)
- Phase planning works less well for the frontend (visual iteration is not plan-execute, it's plan-execute-look-adjust)
- Recommendation: Use GSD for the data layer + code generation, then switch to interactive human-driven development for the UI layer

### 5.4 What Would NOT Work with Claude Code

- Live-embedded Julia (libjulia): Too much systems programming, C FFI debugging
- Qt/C++ desktop app: Claude's Qt knowledge is shallow compared to React
- Complex real-time simulation visualization: Requires domain-specific rendering knowledge
- Electron IPC patterns: More boilerplate-heavy than Tauri, more things to go wrong

---

## 6. Alternative Approaches (Simpler Paths)

### 6.1 Pluto.jl Notebook Widget (Simplest)

**What:** A custom HTML/JS widget inside a Pluto.jl notebook that renders a ReactFlow canvas. The widget sends graph JSON to Julia via Pluto's `@bind` mechanism.

**Pros:**
- No desktop app needed -- runs in browser
- Julia is already running (Pluto manages the process)
- Reactive: change graph -> Julia re-runs
- Zero packaging/distribution burden

**Cons:**
- User must have Julia + Pluto installed
- Widget development within Pluto is poorly documented
- Limited by Pluto's cell execution model
- Not a "standalone app" feel

**Effort:** 2-3 weeks for a basic version.

**Verdict:** Good for internal/research use. Bad for distributing to non-Julia-users.

### 6.2 VS Code Extension

**What:** A VS Code webview panel with ReactFlow that generates `.jl` files in the workspace.

**Pros:**
- Users likely already have VS Code
- Webview = full React capability
- Can integrate with Julia VS Code extension for syntax highlighting
- No separate app distribution

**Cons:**
- VS Code extension API has quirks
- Webview lifecycle management is tricky
- Locks users into VS Code

**Effort:** 4-6 weeks (VS Code extension boilerplate adds overhead).

### 6.3 Pure Web App (localhost)

**What:** A React app served by a minimal Julia HTTP server (Oxygen.jl). User runs `julia serve_gui.jl`, opens `localhost:8080`.

**Pros:**
- No desktop framework needed
- Full React + ReactFlow capability
- Julia backend available for validation
- Single-command startup

**Cons:**
- Julia startup time (10-30s first launch)
- Not a "real" desktop app
- User must have Julia installed
- Port conflicts, firewall issues on some corporate networks

**Effort:** 3-4 weeks.

### 6.4 Comparison Matrix

| Approach | Effort | Standalone | No Julia Required | UX Quality | Distribution |
|----------|--------|-----------|-------------------|-----------|-------------|
| **Tauri 2 + React** | 3-5 wk | YES | YES | HIGH | Installer |
| Pluto widget | 2-3 wk | NO | NO | MEDIUM | Julia package |
| VS Code extension | 4-6 wk | NO | NO | MEDIUM | Marketplace |
| Pure web (localhost) | 3-4 wk | NO | NO | HIGH | Julia package |
| Pure web (no backend) | 2-3 wk | YES (static) | YES | HIGH | Host anywhere |

**Note on "Pure web (no backend)":** A static single-page app hosted on GitHub Pages or similar. No Julia server. Just generates `.jl` files that the user downloads. This is actually the absolute simplest path and could be the MVP-before-MVP.

---

## 7. Recommended Path

### Phase 0: Static Web App (1-2 weeks)
- React + ReactFlow, hosted as a static site (GitHub Pages or local `index.html`)
- 5 basic components: Pump, Channel, HeatExchanger, Resistor, Gravity
- FlowPort connections only
- Export graph as `.jl` file (download button)
- No Julia backend, no desktop packaging
- **Purpose:** Validate the concept, iterate on UX, get user feedback

### Phase 1: Tauri Desktop App (2-3 weeks additional)
- Wrap Phase 0 web app in Tauri 2
- Add file system integration (Save/Open project, Export `.jl` to chosen path)
- Add remaining components (ChannelHeatFlux, Friction, Inertia, Flapper)
- Parameter editing sidebar with validation
- Boundary condition editor

### Phase 2: Thermal Composition (2-3 weeks additional)
- ChannelAndContacts with ThermalPort arrays
- HeatDiffusion nodes
- Composition helper nodes (symmetric_plate, plate, one_sided_connection)
- Correlation selection dropdowns

### Phase 3: Julia Backend (optional, 1-2 weeks)
- Oxygen.jl HTTP server for live validation
- "Check" button: validates generated code compiles
- Error highlighting on invalid connections
- Optional: run simulation and show results inline

### Total: 6-10 weeks for Phase 0-2 (no Julia backend), 8-12 weeks with Phase 3.

---

## 8. Risks and Open Questions

### 8.1 Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| ReactFlow custom nodes harder than expected | LOW | MEDIUM | ReactFlow has extensive examples; custom handles are well-documented |
| Tauri 2 WebView inconsistency Win vs Linux | MEDIUM | MEDIUM | Test early on both platforms; WebView2 (Win) vs WebKitGTK (Linux) have different rendering |
| Parameter forms become complex (closures, callables) | HIGH | MEDIUM | MVP excludes closures; use code editor widget (Monaco) for advanced params later |
| Multi-way junctions hard to represent visually | MEDIUM | LOW | Use explicit junction nodes (like OMEdit); defer to Phase 2 |
| Generated code doesn't match user expectations | MEDIUM | HIGH | Generate `build_*`-style functions that match existing examples; include comments |
| TTFX makes Julia backend unusable for interactive validation | HIGH | LOW | File-only MVP avoids this entirely; PackageCompiler sysimage for Phase 3 |

### 8.2 Open Questions

1. **Component versioning:** When STREAM.jl adds new components or changes signatures, how does the GUI stay in sync? Need a component metadata registry that can be updated independently of the GUI.

2. **Correlation closure representation:** How should `regime_dependent(htc_laminar=constant_Nusselt(Nu=8.235), ...)` be represented in the GUI? A nested form? A JSON config? A raw code editor? This is the single hardest UX problem.

3. **Multi-way connections:** STREAM.jl uses `connect(a, b, c)` for 3-way junctions. Standard graph editors model edges as pairs. Need junction nodes or hyperedges. This adds visual complexity.

4. **Project file format:** Should the GUI save its own project format (JSON graph) separately from the exported `.jl` file? Or should it round-trip from `.jl` (parse Julia code back into a graph)? Round-tripping is dramatically harder and probably not worth it.

5. **Target user:** "Non-coders" implies the GUI must handle ALL composition logic. "Engineers who don't want to write boilerplate" implies the GUI generates a starting point that users modify. These have very different UX requirements.

---

## Project Constraints (from CLAUDE.md)

The following CLAUDE.md directives are relevant to any GUI that generates STREAM.jl code:

- All public exports declared in `STREAM.jl` only (generated code must `using STREAM`)
- Component naming: `@named` macro always used (generated code must follow this)
- Positional vs keyword arguments vary by component (GUI must know the correct constructor signature)
- Factory functions use positional args: `PipeGeometry_rectangular(L, W, H)`, `PipeGeometry_circular(L, D)`
- `mtkcompile(sys)` required before solve (generated code must include this)
- Internal helpers prefixed with `_` are not public API (GUI should not generate calls to `_channel_base_eqs`, `_infer_n`, etc.)

---

## Sources

### Primary (HIGH confidence)
- STREAM.jl source code: `src/STREAM.jl`, `src/components/*.jl`, `src/composition/helpers.jl`, `src/examples.jl`
- Python STREAM: `stream/composition/cycle.py` (FlowGraph reference implementation)
- [ModelingToolkitDesigner.jl GitHub](https://github.com/bradcarman/ModelingToolkitDesigner.jl)
- [ReactFlow documentation](https://reactflow.dev)
- [Tauri 2 documentation](https://v2.tauri.app)

### Secondary (MEDIUM confidence)
- [JuliaHub Dyad product page](https://juliahub.com/products/dyad)
- [OMEdit Architecture](https://deepwiki.com/OpenModelica/OpenModelica/3.1-omedit-architecture)
- [Tauri vs Electron comparison](https://www.gethopp.app/blog/tauri-vs-electron)
- [Julia embedding documentation](https://docs.julialang.org/en/v1/manual/embedding/)
- [Oxygen.jl](https://oxygenframework.github.io/Oxygen.jl/stable/api/)

### Tertiary (LOW confidence)
- Effort estimates are based on similar projects and general software engineering experience, not empirical data from building this specific tool. Actual effort will vary based on developer experience with React, Tauri, and the STREAM.jl codebase.

---

## Metadata

**Confidence breakdown:**
- Ecosystem survey: HIGH - direct inspection of repos and official docs
- Architecture options: HIGH - well-established frameworks with extensive documentation
- Graph-to-code translation: HIGH - based on direct analysis of STREAM.jl source code
- Effort estimates: MEDIUM - extrapolated from similar projects, not empirical
- Claude Code suitability: MEDIUM - based on observed patterns in AI-built GUI apps, not direct experiment
- Alternative approaches: MEDIUM - some approaches (Pluto widget) are less well-documented

**Research date:** 2026-03-31
**Valid until:** 2026-06-30 (3 months -- React/Tauri ecosystem moves fast but core patterns are stable)
