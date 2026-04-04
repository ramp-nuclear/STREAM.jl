# Phase 33: Project Scaffold - Context

**Gathered:** 2026-04-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Create the Tauri 2 + React + ReactFlow desktop app skeleton and the component metadata registry JSON. At phase end: `npm run tauri dev` launches a working app with an empty three-panel layout and ReactFlow canvas; the registry defines all 12 STREAM.jl components with their full API. No visual design, no real canvas behavior — that's Phase 34+.

</domain>

<decisions>
## Implementation Decisions

### Repository Location
- **D-01:** GUI lives at `gui/` as a plain directory inside Julia-STREAM (monorepo). Not a git submodule. Not a sibling repo. Single git history, CLAUDE.md stays in scope for the GUI, all phase PRs cover both library and GUI changes.

### Component Registry
- **D-02:** Registry covers all 12 STREAM.jl exported components — NOT just 9. The "9 hydraulic" language in REQUIREMENTS.md and ROADMAP.md is an undercount and should be corrected. The correct list: Channel, ChannelAndContacts, ChannelHeatFlux, Pump, Flapper, Friction, Gravity, Resistor, Inertia, HeatExchanger, ConstantTemperature, HeatDiffusion.
- **D-03:** ConstantTemperature is a canvas node (ThermalPort-only component), not a BC panel entry. It will be wired to ChannelAndContacts/HeatDiffusion ThermalPorts in Phase 40.
- **D-04:** Components with ThermalPort arrays (ChannelAndContacts, ChannelHeatFlux, HeatDiffusion, ConstantTemperature) have their thermal port metadata fully described in the registry. The GUI does not render ThermalPort handles in Phase 33 or Phase 34 — that's Phase 40's job. The registry is complete data regardless of what the canvas currently renders.
- **D-05:** Registry records the STREAM.jl target version (SCAF-05) and validates extensibility: adding a new component requires only a JSON entry, no TypeScript changes (SCAF-04).

### Scaffold Depth
- **D-06:** Phase 33 sets up a Zustand store (`useStore.ts`) with at minimum: `nodes`, `edges`, `selectedNodeId`. Three-panel layout shells are created as empty components (`ToolboxPanel`, `CanvasPanel`, `SidebarPanel`). Phase 34 populates real behavior on top of this structure — Phase 33 does not do both setup and behavior.
- **D-07:** Vitest + React Testing Library are configured in Phase 33. The first test is a registry-loading test (validates JSON parses, all 12 components present, required fields non-null). This establishes the testing pattern for all subsequent GUI phases.

### Claude's Discretion
- TypeScript configuration (strict mode, tsconfig settings)
- Package manager (follow Tauri 2 defaults; `npm` is conventional)
- Tauri 2 init approach (`npm create tauri-app` with `react-ts` template is standard)
- Exact Zustand store shape beyond nodes/edges/selectedNodeId
- Registry JSON field names and schema versioning (follow SCAF-03 requirements)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Architecture & Feasibility
- `.planning/research/gui-feasibility/RESEARCH.md` — Full feasibility study: ecosystem survey, Tauri 2 + ReactFlow architecture rationale, graph-to-code translation algorithm, effort estimates. Section 2 is most relevant for scaffold decisions.

### Requirements
- `.planning/REQUIREMENTS.md` §"v0.8 Requirements (STREAM Composer GUI)" → SCAF-01..05 — Exact acceptance criteria for this phase. **Note:** SCAF-03 says "9 hydraulic components" — this is wrong; the correct count is 12. Treat D-02 above as the authoritative decision.

### STREAM.jl Component API (source of truth for registry content)
- `src/STREAM.jl` lines 26-35 — Export list; these 12 component names go in the registry
- `CLAUDE.md` §"Component authoring conventions" — Positional vs keyword argument rules; registry `constructor_signature` field must match these exactly (e.g., `Pump(dP_pump::Real; name)` is positional, `Channel(; name, L, Dh, ...)` is keyword-only)
- `src/components/` — Component source files for verifying parameter lists, port definitions, and constructor signatures

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- None yet — `gui/` does not exist; Phase 33 creates it from scratch via `npm create tauri-app`

### Established Patterns
- Julia package uses `Project.toml` at repo root — `gui/` with its own `package.json` at `gui/package.json` is a clean parallel structure
- CLAUDE.md export rules (all exports in `src/STREAM.jl`) are the model for registry completeness — the registry is the GUI-side equivalent of the export list

### Integration Points
- `src/STREAM.jl` lines 26-35: source of truth for component names and port/parameter structure — registry must be derived from these
- `CLAUDE.md` component conventions: registry constructor_signature field must encode the positional-vs-keyword distinction that governs generated `@named` syntax in Phase 36
- Phase 40 (Thermal Composition) will consume the thermal port metadata written in Phase 33's registry — getting field names right now avoids breaking changes

</code_context>

<specifics>
## Specific Ideas

- Three-panel layout structure: `ToolboxPanel` (left, collapsible) → `CanvasPanel` (center, ReactFlow) → `SidebarPanel` (right, collapsible). Unstyled shells in Phase 33; styled in Phase 38.
- Zustand store minimum shape: `{ nodes, edges, selectedNodeId, actions: { addNode, removeNode, addEdge, removeEdge, selectNode, updateNodeParams } }`
- Registry first test: import registry, assert `components.length === 12`, assert every entry has required fields (`id`, `label`, `ports`, `parameters`, `stream_version`)

</specifics>

<deferred>
## Deferred Ideas

- **Requirements correction**: REQUIREMENTS.md SCAF-03 and ROADMAP.md Phase 33 description both say "9 STREAM.jl hydraulic components" — this should be updated to "12 STREAM.jl components". Should be a quick fix at the start of planning or execution.
- **ConstantTemperature as BC panel**: Alternative placement was considered and rejected — it's a canvas node.
- **Minimal scaffold (bare canvas)**: Considered and rejected in favor of Zustand + panel shells to avoid Phase 34 doing setup + canvas features simultaneously.

</deferred>

---

*Phase: 33-project-scaffold*
*Context gathered: 2026-04-01*
