# Phase 36: Code Generation - Context

**Gathered:** 2026-04-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Users can view a live-updating read-only Julia code preview generated from their canvas topology, configure boundary conditions (pressure anchors), and export the result to a `.jl` file via native file dialog. No live Julia execution. ThermalPort wiring and ConstantTemperature code gen are Phase 40.

</domain>

<decisions>
## Implementation Decisions

### Preview Panel Layout
- **D-01:** Bottom panel below the full-width canvas (spanning Toolbox + Canvas + Sidebar columns). Collapsible. This matches the IDE convention and keeps the 320px sidebar untouched.
- **D-02:** A "Code" button in a top toolbar / canvas header bar toggles the bottom panel open/closed. Export button also lives in this toolbar area.

### BC Panel Layout
- **D-03:** The bottom panel has two tabs: **[Code] [BCs]**. The BCs tab shows the boundary conditions list + Add button. Same panel, same toggle — no extra screen real estate or separate widget needed.
- **D-04:** BC entry uses a structured form: `[component dropdown ▾] . [port.field dropdown ▾] ~ [value input]` + `[Add]`. The component dropdown is populated from canvas nodes (instanceNames). The port.field dropdown is limited to **FlowPort.P only** (`port_in.P` and `port_out.P`). Thermal BCs come from ConstantTemperature canvas nodes (Phase 40), not from this panel.
- **D-05:** BC entries are stored in the Zustand store as an array of `{ nodeId: string, portField: "port_in.P" | "port_out.P", value: number }`. Each entry renders as a row with the expression string and a delete `[x]` button.

### Generated Code Structure
- **D-06:** Full runnable stub format:
  ```julia
  using ModelingToolkit, STREAM
  using ModelingToolkit: t_nounits as t

  # Components
  @named pump_1 = Pump(30000.0)
  @named ch_1   = Channel(; L=0.5, Dh=0.01, n=5)

  # Connections
  eqs = [
      connect(pump_1.port_out, ch_1.port_in),
      pump_1.port_in.P ~ 1.0e5,
  ]

  # System
  @named sys = ODESystem(eqs, t; systems=[pump_1, ch_1])
  ssys = mtkcompile(sys)

  # Solve (uncomment to run)
  # sol = solve(SteadyStateProblem(ssys, []), DynamicSS(Rodas5P()))
  ```
- **D-07:** Uses `ODESystem(eqs, t; systems=[...])` idiom — not `compose(System(...), ...)`. This matches STREAM.jl's own examples (`build_loop`, etc.) and is more familiar to Julia users.
- **D-08:** `@named` declarations use the correct positional vs keyword argument convention from CLAUDE.md. E.g., `Pump(30000.0)` (positional), `Channel(; L=..., Dh=..., n=...)` (keyword-only). The registry `positional` field per parameter drives this — no hardcoding in the code generator.
- **D-09:** Function-type parameters (htc_correlation, friction_correlation): if the stored value is a `string` → emit as bare Julia identifier (e.g., `dittus_boelter`); if `value.kind === "factory"` → emit as factory call with keyword args (e.g., `elenbaas_htc(b=0.003, L=0.6, Dh=0.0025)`). The ROADMAP code-gen contract is the authoritative spec.
- **D-10:** Component ordering in `@named` declarations and `systems=[...]` follows insertion order (the order nodes were added to the canvas). No topological sorting needed.

### Export
- **D-11:** Export button triggers Tauri's native file save dialog (`tauri-plugin-dialog` save dialog API), defaulting to `system.jl`. The dialog filters to `.jl` files.

### Claude's Discretion
- Syntax highlighting library for the code preview (e.g., highlight.js, shiki, or a simple `<pre>` with monospace font)
- Exact toolbar component layout and styling
- Whether the bottom panel has a resize handle or fixed height
- Shadcn/ui components for the BC structured form (Select, Input, Button)
- Error display for CODE-07 identifier validation (inline vs toast)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` §"Code Generation" → CODE-01..CODE-07 — Exact acceptance criteria for this phase

### Roadmap notes (code gen contract)
- `.planning/ROADMAP.md` §"Phase 36: Code Generation" — Success criteria and depends-on
- `.planning/ROADMAP.md` §"Notes for implementors" (around line 185–205) — Code gen contract for Function-type params: simple closures vs factory calls, known factory signatures, simple closure list

### Store + data structures (Phase 35.1 output)
- `gui/src/store/useStore.ts` — `StreamNodeData.parameters: Record<string, unknown>`. Code gen reads `parameters` for each node. Factory values have `kind: "factory"`.
- `gui/src/registry/types.ts` — `FactoryCorrelationValue` interface: `{ kind: "factory"; value: string; subParams: Record<string, unknown> }`. Code gen detects `typeof v === "string"` (simple) vs `v.kind === "factory"` (factory).

### Registry (source of truth for constructor signatures)
- `gui/src/registry/components.json` — `parameter.positional` field drives whether a param is emitted positionally or as `name=value` keyword arg. `constructorModes` drives which parameter list is active per mode.
- `gui/src/registry/types.ts` — `Parameter`, `ConstructorMode`, `ComponentDefinition` interfaces

### Canvas edge data (port names for connect() calls)
- `gui/src/components/StreamNode.tsx` — Handle `id` = port name (e.g., `port_in`, `port_out`). ReactFlow `Edge.sourceHandle` and `Edge.targetHandle` carry these names.
- `gui/src/store/useStore.ts` — `edges` array: each edge has `source` (node id), `sourceHandle` (port name), `target` (node id), `targetHandle` (port name)

### STREAM.jl constructor API (source of truth for generated syntax)
- `CLAUDE.md` §"Component authoring conventions" — Positional vs keyword argument rules
- `src/STREAM.jl` lines 26-35 — Exported component names
- `src/components/` — Component source files for verifying constructor signatures match registry

### Prior phase context
- `.planning/phases/35.1-correlation-picker/35.1-CONTEXT.md` — D-06/D-07: store value shapes for factory vs simple correlations; D-08: `FactoryCorrelationValue` TypeScript interface
- `.planning/phases/33-project-scaffold/33-CONTEXT.md` — D-03: ConstantTemperature is a canvas node (not BC panel entry); D-02: 12 components total

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `gui/src/store/useStore.ts`: `nodes` and `edges` arrays are the sole input to code generation. `node.data.instanceName` → `@named` variable name. `node.data.componentId` → component lookup. `node.data.parameters` → constructor args. `edge.sourceHandle` / `edge.targetHandle` → port names for `connect()`.
- `gui/src/registry/index.ts` + `components.json`: `getComponent(id)` returns full parameter + constructor mode definitions. Code gen loops over active mode's `parameters` list to emit constructor args.
- `gui/src/lib/validation.ts`: Julia identifier regex already implemented for CODE-07 (`instanceName` validation in Phase 35). Code gen can reuse it to check node names before emitting.

### Established Patterns
- Registry-driven rendering (Phase 35/35.1): all rendering logic reads registry JSON, never hardcodes component behavior. Code gen follows the same pattern — the generator is a pure function `(nodes, edges, bcs, registry) → string`.
- Zustand store update pattern: `updateNodeParams(nodeId, patch)`. New BC store state needs a parallel action: `addBC`, `removeBC`, `bcs: BCEntry[]`.
- shadcn/ui + Tailwind installed (New York/Zinc style). Bottom panel and toolbar use the same design tokens.
- Bottom panel does not exist yet — Phase 36 creates it from scratch. The three-panel layout is in `App.tsx` as a flex row; adding a bottom panel means wrapping the row in a flex column.

### Integration Points
- `App.tsx`: Current layout is `<div class="flex h-screen">Toolbox | Canvas | Sidebar</div>`. Code gen bottom panel wraps this in a `flex flex-col`: top row = existing 3 panels, bottom row = collapsible panel.
- `CanvasPanel.tsx` or a new `Toolbar.tsx`: "Code" button and "Export" button need a home. A thin toolbar bar above or inside the canvas area is the natural location.
- Tauri export: `gui/src-tauri/` already exists. Export requires adding `tauri-plugin-dialog` to Cargo.toml and `"dialog"` to tauri `allowlist` / permissions. The save dialog API is `save()` from `@tauri-apps/plugin-dialog`.

</code_context>

<specifics>
## Specific Ideas

- Generated code template uses `using ModelingToolkit, STREAM` + `using ModelingToolkit: t_nounits as t` as the header. The `t` alias is required since all MTK equations reference `t` as the independent variable.
- The commented solve stub is `# sol = solve(SteadyStateProblem(ssys, []), DynamicSS(Rodas5P()))` — gives users a starting point without forcing a specific solve call.
- BC structured form layout: `[component dropdown ▾] . [port.field dropdown ▾] ~ [value input]` followed by `[Add]` button on the same row.
- The bottom panel toggle button is labeled "Code" and lives in a toolbar area above the canvas (same row as an "Export" button).

</specifics>

<deferred>
## Deferred Ideas

- **Thermal BC via BC panel** — ConstantTemperature canvas node handles thermal pins (Phase 40). The BC panel is FlowPort.P-only in Phase 36.
- **Syntax highlighting** — Claude's discretion; a plain `<pre>` with monospace is acceptable if highlight.js/shiki adds complexity.
- **Live validation feedback** — Whether to show a warning toast when the canvas has unconnected ports that would make the generated code non-compilable. Phase 37 (topology validation) handles this.

</deferred>

---

*Phase: 36-code-generation*
*Context gathered: 2026-04-02*
