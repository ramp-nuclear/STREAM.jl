# Project Research Summary

**Project:** STREAM Composer GUI (v0.8)
**Domain:** Desktop node-based visual editor for STREAM.jl thermal-hydraulic system composition with Julia code generation
**Researched:** 2026-04-01
**Confidence:** HIGH

## Executive Summary

STREAM Composer is a desktop GUI that lets engineers visually compose STREAM.jl thermal-hydraulic systems by dragging components onto a canvas, connecting ports, configuring parameters, and exporting runnable Julia code. The research consensus is clear: build this with Tauri 2 + React + @xyflow/react (ReactFlow 12), backed by a Zustand store and a JSON component metadata registry. This stack is mature, actively maintained, and has been proven in similar domain-specific node editors (ComfyUI pattern). The critical architectural insight is that the app is a pure code generator -- it never needs a Julia runtime, which eliminates TTFX issues and makes distribution trivial. This is the key differentiator versus all competing tools (JuliaHub Dyad, OMEdit, ModelingToolkitDesigner.jl), all of which require a live simulation backend.

The recommended approach is registry-driven: a single `components.json` file encodes every STREAM.jl component's ports, parameters, and constructor signatures. The GUI renders nodes generically from this registry, and the code generator reads it to emit correct Julia syntax. This means adding a new STREAM.jl component to the GUI requires only a JSON entry -- no TypeScript changes. The feature set for v0.8 is well-scoped: canvas editing, parameter sidebar, code generation, and project persistence form the MVP core; thermal port arrays and smart composition code-gen are v0.8 Phase 2 additions; Julia backend integration and round-trip parsing are explicitly deferred.

The main risks are (1) ReactFlow stale closures and re-render cascades if Zustand is not adopted from day one, (2) incorrect constructor signatures in generated code if the registry does not encode positional-vs-keyword argument style explicitly for each component, and (3) Tauri 2 capability permission denials in production builds if file/dialog permissions are not configured during scaffold. All three are preventable at Phase 33 (scaffold) if the patterns are established before any feature work begins.

## Key Findings

### Recommended Stack

The stack is fully pinned and ready to use. Tauri 2 (2.10.x) provides the native desktop shell with a sub-10 MB bundle and cross-platform file dialogs. React 19.2.x with @xyflow/react 12.10.x forms the canvas layer; ReactFlow 12 is a complete rewrite with React 19 and zustand 5 support. Vite 8 (Rolldown-based) provides fast builds and HMR. Tailwind CSS 4.x and shadcn/ui (CLI v4) supply UI components without heavy library dependencies. There are no version conflicts when using the recommended pinned versions.

**Core technologies:**
- Tauri 2.10.x: Native desktop shell (file I/O, dialogs, packaging) -- proven small-bundle, cross-platform, minimal Rust required
- @xyflow/react 12.10.x: Node-based canvas editor -- 800K weekly downloads, built-in pan/zoom/minimap, typed handle support for FlowPort/ThermalPort
- React 19.2.x: UI framework -- required by ReactFlow 12; React 19 is stable since Dec 2024
- zustand 5.0.x: Global state management -- required for React 19; ReactFlow uses it internally; enables undo/redo via Zundo
- Vite 8.0.x: Build tool -- official Tauri template; Rolldown gives 10-30x faster builds
- Tailwind CSS 4.2.x + shadcn/ui CLI v4: UI components -- zero-config setup; pre-built accessible components; owned code (not a runtime dependency)
- TypeScript 5.8.x: Type safety -- non-negotiable for complex graph state and code generation

**Critical version warnings:**
- Use `@xyflow/react`, NOT the deprecated `reactflow` package (stuck at v11, 2+ years stale)
- Use zustand 5.x, NOT 4.x (no React 19 support; peer dependency conflict)
- Use Tailwind 4.x, NOT 3.x (shadcn/ui CLI v4 targets Tailwind 4; zero-config vs PostCSS required)
- Use Tauri 2.x, NOT 1.x (EOL trajectory; plugin ecosystem is Tauri 2-only now)

### Expected Features

The feature set is precisely scoped by the REQUIREMENTS.md v0.8 section. Research confirms this scope is correct for an MVP that validates the GUI concept.

**Must have (table stakes -- v0.8 Phase 33-37):**
- Drag-drop component creation from toolbox onto canvas
- Pan, zoom, minimap on canvas (ReactFlow built-in)
- Connect ports by dragging handle to handle
- Delete nodes and edges
- Click-to-select opens parameter sidebar with editable fields
- PipeGeometry picker (circular vs rectangular with shape-specific fields)
- Pump mode toggle (fixed-dP vs fixed-mdot dispatch)
- Instance renaming with Julia identifier validation
- Live code preview panel (debounced)
- Export to `.jl` with correct `@named` + `connect()` + `compose()` + `mtkcompile()`
- Boundary condition panel for pressure anchor + thermal pins
- Save/load `.streamgui` JSON project files (Ctrl+S / Ctrl+O)
- Unsaved changes guard

**Should have (differentiators -- v0.8 Phase 38-40):**
- Typed port validation (FlowPort vs ThermalPort -- reject cross-type connections at draw time)
- Undo/redo (Zustand + Zundo middleware; selective recording)
- Topology validation alerts (unconnected ports, missing pump/pressure anchor)
- shadcn/ui design pass for polish
- ThermalPort array handles on ChannelAndContacts (dynamic count based on `n`)
- HeatDiffusion node wiring
- Smart thermal code-gen (detects symmetric_plate / plate / one_sided_connection patterns)
- Recent projects list

**Defer (v0.9+):**
- Embedded Julia runtime / live model validation -- Julia TTFX makes this impractical; conflates composer with IDE
- Round-trip `.jl` parsing -- compiler-level difficulty, not worth the investment
- Correlation closure editing in GUI -- combinatorial form space; too complex for v0.8
- Multi-way junction nodes (T-junctions for Cube problem) -- defer until linear loops validated
- Simulation execution from GUI -- conflates composer with IDE
- Auto-layout (ElkJS) -- manual positioning sufficient; users often undo auto-layout
- Dark mode -- ship light theme first; shadcn/ui supports it in a future pass
- Native installers -- dev mode sufficient for the validation phase

**Key anti-features to avoid building:**
- In-node parameter editing (too cluttered for components with 5-15 params; use sidebar)
- Drag-from-filesystem to open project (use Ctrl+O menu pattern instead)

### Architecture Approach

The architecture follows a three-panel desktop layout (Toolbox | Canvas | Sidebar) with a clear separation between UI concerns and business logic. The component registry JSON is the coupling contract between STREAM.jl and the GUI -- a single source of truth that drives node rendering, form generation, and code templates. All mutable state lives in a Zustand store (not React component state), which avoids stale closures and enables undo/redo. Code generation is a pure function (`GraphState -> string`) with no side effects, making it fully unit-testable. The Tauri Rust backend is intentionally minimal (~100 lines) handling only file I/O and native dialogs.

**Major components:**
1. Component Registry (`registry/components.json`) -- STREAM.jl API contract: ports, params, constructor signatures; drives all other components; no TypeScript changes needed to add new components
2. Zustand Store (`store/`) -- single mutable state for nodes, edges, params, selection, undo history; includes Zundo temporal middleware (limit: 50 steps)
3. ReactFlow Canvas (`components/canvas/`) -- visual graph with single generic StreamNode rendered from registry; typed FlowPort and ThermalPort array handles
4. Parameter Sidebar (`components/sidebar/`) -- dynamic form generated from registry schema; includes PipeGeometryPicker and PumpModePicker
5. Code Generator (`codegen/generator.ts`) -- pure function pipeline: imports -> component declarations -> connections -> BCs -> compose -> mtkcompile
6. Validation Engine (`validation/topology.ts`) -- pure function on graph state: unconnected ports, missing driver, missing pressure anchor
7. Tauri Shell (`src-tauri/`) -- Rust: native file dialogs, read/write .streamgui and .jl files, capabilities ACL (~100 LOC)
8. Persistence Layer (`hooks/useProjectFile.ts`) -- save/load .streamgui JSON with viewport state; Tauri plugin-store for recent files

**Key architectural decisions:**
- Registry-driven rendering: one `StreamNode.tsx` renders all STREAM.jl component types; no per-component TSX files
- `gui/` directory at repo root (sibling to `src/`, not nested inside Julia codebase)
- `codegen/` and `validation/` are pure TypeScript modules, separate from UI components; testable without rendering
- ThermalPort handles use indexed IDs (`thermal_left_0`, `thermal_left_1`) to enable smart thermal code-gen pattern detection

### Critical Pitfalls

1. **ReactFlow stale closures in callbacks** -- Custom node callbacks capture stale `nodes` array snapshots, causing parameter edits to silently revert. Use Zustand selectors (`useStore(s => s.nodes.find(n => n.id === id)?.data)`) for all reads inside event handlers. Establish this pattern at Phase 34 before any sidebar logic is written.

2. **ReactFlow re-render cascades** -- Every custom node re-renders when the `nodes` array changes unless wrapped in `React.memo`. Define `nodeTypes`/`edgeTypes` outside the component (or `useMemo`) on day one. Symptom: sidebar input fields lose focus while typing; canvas janky with 15+ nodes.

3. **Wrong constructor signatures in generated code** -- STREAM.jl uses positional args for single-physics components (`Pump(30000.0)`) and keyword args for multi-param components (`Channel(; n=10, geometry=...)`). The registry JSON must encode `argStyle: "positional" | "keyword"` per parameter. Add per-component unit tests for generated output at Phase 36.

4. **Tauri 2 capability permission denials in production builds** -- Dev mode is more permissive than the installed app. All required permissions (`dialog:allow-open`, `dialog:allow-save`, `fs:allow-read-text-file`, `fs:allow-write-text-file`) must be in `src-tauri/capabilities/default.json` at Phase 33. Every Tauri IPC call must have a `.catch()` error handler. Test production builds on both platforms before completing Phase 37.

5. **Thermal port array handle orphaning** -- When `n` decreases on a ChannelAndContacts node, existing edges to removed handles become invalid React errors. Phase 40 must include an edge cleanup pass on `n` changes with a confirmation dialog if edges would be severed.

## Implications for Roadmap

Based on research, suggested phase structure (continues from current v0.7 milestone, starting at Phase 33):

### Phase 33: Scaffold + Component Registry
**Rationale:** All downstream work depends on the scaffold and registry. The registry is the contract between STREAM.jl and the GUI -- it must encode correct constructor signatures before any UI is built. Tauri capabilities set here prevent production build failures in Phase 37.
**Delivers:** Running Tauri 2 + React + ReactFlow dev environment on both Windows and Linux; complete `components.json` for all 9 STREAM.jl hydraulic components with argStyle encoding; Tauri capability permissions configured; `gui/` project structure established.
**Addresses:** SCAF-01, SCAF-03, SCAF-04
**Avoids:** Pitfall 3 (registry encodes argStyle from day one); Pitfall 5 (capabilities configured at scaffold, not after)

### Phase 34: Canvas Node Editor + State Architecture
**Rationale:** Canvas is the core product feature. Must establish Zustand store pattern before any custom node logic -- retrofitting stale-closure fixes is a medium-cost refactor if deferred.
**Delivers:** Drag-drop from toolbox; FlowPort connections with typed handle validation (`isValidConnection`); node/edge deletion; free repositioning; minimap/controls; Zustand store with Zundo undo/redo; React.memo on all custom nodes; nodeTypes/edgeTypes defined outside render.
**Addresses:** CANV-01..07
**Avoids:** Pitfall 1 (Zustand selectors from day one); Pitfall 2 (React.memo and stable nodeTypes from day one)

### Phase 35: Parameter Editing Sidebar
**Rationale:** Canvas must exist before there is anything to edit. Dynamic form generation from registry schema keeps the sidebar extensible without code changes when STREAM.jl adds components.
**Delivers:** Click-to-select opens sidebar; dynamic parameter fields from registry schema; PipeGeometry picker; Pump mode toggle; instance renaming with Julia identifier validation; per-field validation.
**Addresses:** PARA-01..06
**Avoids:** Pitfall 2 (sidebar uses precise Zustand selectors, not full nodes array); shadcn/ui Select inside custom node requires `stopPropagation`

### Phase 36: Code Generation + Export
**Rationale:** Code generation is the product's output contract. Must be correct before persistence (persistence saves the state the generator reads). Pure-function architecture enables exhaustive testing.
**Delivers:** Pure-function code generator producing complete runnable Julia scripts; live code preview (debounced 300ms); export to `.jl` via Tauri save dialog; boundary condition panel; Julia identifier injection validation (CODE-07); unit tests per component verifying generated output.
**Addresses:** CODE-01..07
**Avoids:** Pitfall 3 (unit tests verify constructor signatures per component); Pitfall 4 (deterministic ordering, always emit mtkcompile, emit `using STREAM` + `using ModelingToolkit: t`)

### Phase 37: Project Persistence
**Rationale:** Users need to save work before the product is usable for real systems. Must come after code generation since `.streamgui` JSON serializes the same state the generator reads.
**Delivers:** Save/load `.streamgui` JSON (Ctrl+S / Ctrl+O) with canvas viewport state; unsaved changes guard; recent projects list (Tauri plugin-store); `.streamgui` format versioning (`version` + `streamjl_version` fields).
**Addresses:** PERS-01..04
**Avoids:** Pitfall 5 (verify production build save/load on both Windows and Linux); cross-platform path handling (use Tauri path APIs, not hardcoded separators)

### Phase 38: Design Polish + Undo/Redo Solidification
**Rationale:** After core editor works end-to-end, stabilize UX before adding complex thermal features. Polish is cheaper before thermal complexity is added.
**Delivers:** shadcn/ui component pass across all panels; Zundo undo/redo refinement (pause during drag, resume on drop); handle hit-area sizing for high-DPI; selected node highlight; non-blocking topology alert banners foundation.
**Addresses:** DSGN-01..04; CANV-07 solidification
**Avoids:** Undo history noise from drag micro-movements; UX pitfalls (handle too small, no selection indication)

### Phase 39: Topology Validation
**Rationale:** Validation catches the most common user errors before they waste time running Julia. Must come after BC panel exists (Phase 36) since validation checks for pressure anchor presence.
**Delivers:** Non-blocking alert banners: unconnected mandatory ports; no pump/gravity driver; no pressure anchor BC; disconnected subgraph; export button highlighted when warnings exist; port-level visual warning badges.
**Addresses:** VALD-01..03
**Avoids:** Pitfall 4 (validation catches missing BCs before code generation is attempted)

### Phase 40: Thermal Composition
**Rationale:** Most complex feature -- depends on all foundation layers. Dynamic handle counts are a non-standard ReactFlow usage that requires careful design. Best isolated when confidence in foundation is high.
**Delivers:** ThermalPort array handles on ChannelAndContacts (dynamic count from `n`; indexed handle IDs `thermal_left_0`, etc.); HeatDiffusion node wiring; smart thermal code-gen pattern recognition (symmetric_plate / plate / one_sided_connection); edge cleanup on `n` reduction with confirmation dialog.
**Addresses:** THERM-01..03
**Avoids:** Pitfall 6 (edge cleanup on n-change is required behavior, not optional)

### Phase Ordering Rationale

- Registry before canvas: the registry JSON is the contract -- building custom nodes without it leads to hardcoded per-component components that violate SCAF-04 (extensibility via JSON only).
- Zustand before custom nodes: stale closure bugs are a state management architecture problem. Retrofitting Zustand after building with useState is a medium-cost refactor.
- Code generation before persistence: `.streamgui` serializes graph state; knowing what the generator needs from that state informs the save format. Avoids a save-format redesign.
- Validation after BC panel (Phase 36): topology validation checks for pressure anchor BCs -- the BC panel must exist first.
- Thermal last: depends on every foundation layer. High complexity with dynamic handle counts. Best isolated to the final phase when confidence in the foundation is high.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 40 (Thermal Composition):** ThermalPort array handles with dynamic counts are a non-standard ReactFlow usage. The edge cleanup logic and smart code-gen pattern recognition (symmetric_plate detection algorithm) need detailed design before implementation. Consider a targeted research step during Phase 40 planning focused on dynamic handle patterns.
- **Phase 33 (Linux AppImage -- SCAF-02):** Known Tauri bug (tauri-apps/tauri#12463) with missing `libwebkit2gtkinjectedbundle.so` in AppImage. Monitor for fix status before committing to AppImage distribution in Phase 33.

Phases with standard patterns (skip research-phase):
- **Phase 34 (Canvas):** ReactFlow official docs have exhaustive examples for custom nodes, handle typing, and Zustand integration.
- **Phase 35 (Parameter Sidebar):** Dynamic form generation from JSON schema is a standard React pattern; shadcn/ui provides all needed form primitives.
- **Phase 36 (Code Generation):** Pure function with known input/output contract. STREAM.jl constructor signatures documented in CLAUDE.md.
- **Phase 37 (Persistence):** Tauri plugin-dialog + plugin-fs are well-documented with examples.
- **Phase 38 (Design Polish):** shadcn/ui components are copy-paste with documented customization; Zundo has documented drag-pause pattern.
- **Phase 39 (Validation):** Graph topology analysis is standard algorithm work (connectivity, node classification).

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All version numbers verified against npm/GitHub registries. React 19 + ReactFlow 12 + zustand 5 compatibility confirmed. Tauri 2 stable since Oct 2024. No version conflicts. |
| Features | HIGH | Requirements already defined in REQUIREMENTS.md v0.8; research validates scope and identifies correct deferrals. Feature dependencies mapped explicitly with clear rationale. |
| Architecture | HIGH | Registry-driven pattern is established in ReactFlow community. Zustand + Zundo is ReactFlow's official recommendation. Pure-function code generator is standard. Three-panel layout is well-proven. |
| Pitfalls | MEDIUM-HIGH | ReactFlow stale closure and re-render pitfalls verified via official docs and community posts. Tauri capability pitfalls from tracked GitHub issues. Code generation pitfalls from STREAM.jl source analysis. Platform-specific pitfalls from bug reports. |

**Overall confidence:** HIGH

### Gaps to Address

- **WebKitGTK rendering on Linux:** Rendering differences between WebKitGTK versions (Ubuntu 22.04 vs 24.04) are documented but the specific impact on ReactFlow canvas rendering is not quantified. Mitigation: test on both distros early in Phase 33; avoid CSS features requiring WebKit 2.38+.
- **AppImage bundling for Linux:** Tauri bug #12463 (missing injected bundle .so) is cosmetic for most uses but unresolved as of 2026-04-01. Monitor during Phase 33 SCAF-02; may require workaround or deferral of AppImage distribution.
- **`.streamgui` format evolution:** The JSON format needs a migration strategy for when STREAM.jl components change (e.g., parameter renamed across Julia versions). Phase 37 should define a version field and basic migration path, but the full migration strategy is not yet designed.
- **Pump dual-dispatch registry schema:** The registry must encode both `Pump(dP::Real)` (positional) and `Pump(; mdot0)` (keyword) modes as a single mode-switching entry. The exact JSON schema for this dual-dispatch entry needs to be specified during Phase 33 registry design.

## Sources

### Primary (HIGH confidence)
- [Tauri 2 Official Docs](https://v2.tauri.app/) -- version 2.10.x, plugin docs, capabilities ACL
- [@xyflow/react npm](https://www.npmjs.com/package/@xyflow/react) -- v12.10.2; React Flow 12 migration guide
- [React Flow Official Docs](https://reactflow.dev/) -- custom nodes, state management, performance, connection validation, undo/redo
- [React npm](https://www.npmjs.com/package/react) -- v19.2.4
- [Vite 8 Announcement](https://vite.dev/blog/announcing-vite8) -- Rolldown integration, March 2026
- [shadcn/ui Changelog](https://ui.shadcn.com/docs/changelog) -- CLI v4 March 2026; unified radix-ui Feb 2026
- [zustand npm](https://www.npmjs.com/package/zustand) -- v5.0.12; React 19 support
- [Tailwind CSS npm](https://www.npmjs.com/package/tailwindcss) -- v4.2.2; zero-config Vite plugin
- STREAM.jl CLAUDE.md -- constructor conventions (positional vs keyword); component API
- STREAM.jl `.planning/REQUIREMENTS.md` v0.8 section -- feature scope definition

### Secondary (MEDIUM confidence)
- [ReactFlow: State Management Guide](https://reactflow.dev/learn/advanced-use/state-management) -- Zustand integration patterns, stale closure warnings
- [ReactFlow: Performance Guide](https://reactflow.dev/learn/advanced-use/performance) -- React.memo requirements, selector patterns
- [Zundo GitHub](https://github.com/charkour/zundo) -- Zustand undo/redo middleware; selective recording pattern
- [tauri-apps/tauri#8074](https://github.com/tauri-apps/tauri/issues/8074) -- Windows defaultPath forward slash bug
- [tauri-apps/tauri#12463](https://github.com/tauri-apps/tauri/issues/12463) -- Linux AppImage missing injected bundle .so
- [shadcn-ui/ui#1511](https://github.com/shadcn-ui/ui/issues/1511) -- Popover z-index in ReactFlow nodes
- STREAM.jl `.planning/research/gui-feasibility/RESEARCH.md` -- prior feasibility study

### Tertiary (LOW confidence)
- [kitlib/tauri-app-template](https://github.com/kitlib/tauri-app-template) -- community Tauri v2 + React 19 + shadcn/ui template (validates stack compatibility)
- [Synergy Codes -- ReactFlow State Management](https://www.synergycodes.com/blog/state-management-in-react-flow) -- community patterns for large graphs

---
*Research completed: 2026-04-01*
*Ready for roadmap: yes*
