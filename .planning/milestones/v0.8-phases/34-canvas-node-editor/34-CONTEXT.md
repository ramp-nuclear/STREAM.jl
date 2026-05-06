# Phase 34: Canvas & Node Editor - Context

**Gathered:** 2026-04-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Users can visually build hydraulic system topologies by placing components from the toolbox onto the canvas and wiring them together via FlowPort edges. Phase 34 delivers: custom node rendering, drag-from-toolbox, FlowPort edge drawing with strict source/target enforcement, delete, undo/redo. ThermalPort handles are Phase 40's job. UI design/styling is Phase 38's job.

</domain>

<decisions>
## Implementation Decisions

### Node Visual Design
- **D-01:** Minimal card — neutral/white background, component type as small subtitle label, instance name as bold title. No icons, no category colors (Phase 38 will redesign). Functional, not styled.
- **D-02:** FlowPort handles placed left/right per `port.side` field from the registry. Each component's handle positions come from `components.json` — no hardcoding.
- **D-03:** ThermalPort handles are NOT rendered in Phase 34. They are deferred to Phase 40 (carries forward from Phase 33 D-04). The registry already has full thermal port metadata for when Phase 40 needs it.
- **D-04:** Node shows component type and user-assigned instance name. Default name is `comp_type_N` (e.g., `pump_1`, `channel_2`), per CANV-02.

### Toolbox Interaction
- **D-05:** HTML5 drag-and-drop is the interaction model. Toolbox items use `onDragStart` to set `dataTransfer` payload (component id). Canvas `onDrop` reads it and calls `addNode`. This is ReactFlow's documented standard pattern — not react-dnd, not click-to-place.

### Edge & Port Validation
- **D-06:** Strict FlowPort directionality: only FlowPort-out handles can be edge sources; only FlowPort-in handles can be edge targets. Implemented via ReactFlow's `isValidConnection` prop and handle `type` (`source` vs `target`). Prevents connecting two outputs or two inputs at draw time.
- **D-07:** Higher-level topology rules (unconnected ports, missing pressure BC, missing driving element) are deferred to Phase 39. Phase 34 only enforces source/target directionality.

### Undo/Redo
- **D-08:** Use `zundo` library (Zustand temporal middleware). Wraps the existing store and adds `undo()` / `redo()` actions. Must cover at least 10 sequential operations (CANV-07). If zundo causes issues (incompatibilities, unexpected behavior), fall back to a custom `past[]`/`future[]` snapshot stack in the Zustand store — same contract, no refactor of consumers.

### Claude's Discretion
- Default instance name counter strategy (per-type counter vs. global counter)
- Exact node card dimensions and CSS
- Handle colors for FlowPort in/out handles
- Keyboard shortcut for delete (Delete/Backspace) — ReactFlow has built-in support

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 33 foundation
- `.planning/phases/33-project-scaffold/33-CONTEXT.md` — Established decisions: three-panel layout structure, Zustand store minimum shape, registry schema, ThermalPort handle deferral (D-04)

### Registry (source of truth for handle placement)
- `gui/src/registry/components.json` — 12 components with `ports[].side` (left/right/top/bottom) and `ports[].type` (FlowPort/ThermalPort). Handle positions and types come from here.
- `gui/src/registry/types.ts` — TypeScript interfaces: `Port`, `Parameter`, `ComponentDefinition`, `ComponentRegistry`

### Existing canvas infrastructure
- `gui/src/store/useStore.ts` — Zustand store: `nodes`, `edges`, `selectedNodeId`, `onNodesChange`, `onEdgesChange`, `selectNode`. Phase 34 adds: `addNode`, `removeNode`, `addEdge`, `removeEdge` + zundo temporal wrapper.
- `gui/src/components/CanvasPanel.tsx` — ReactFlow setup with Controls/MiniMap/Background already wired. Phase 34 extends this with `nodeTypes`, `onDrop`, `onDragOver`, `deleteKeyCode`.

### Requirements
- `.planning/REQUIREMENTS.md` §"Canvas & Node Editor" → CANV-01..07 — Exact acceptance criteria

### Architecture reference
- `.planning/research/gui-feasibility/RESEARCH.md` — ReactFlow + Zustand patterns, drag-drop implementation notes, custom node component approach

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `gui/src/store/useStore.ts`: Zustand store with `applyNodeChanges`/`applyEdgeChanges` wiring — Phase 34 extends this store, does not replace it
- `gui/src/components/CanvasPanel.tsx`: ReactFlow already configured with Controls/MiniMap/Background; Phase 34 adds `nodeTypes` map and drop handler
- `gui/src/registry/index.ts` + `components.json`: Registry loader pattern established; toolbox reads from here to enumerate items
- `gui/src/components/ToolboxPanel.tsx`: Stub with placeholder text — Phase 34 populates with registry-driven component list

### Established Patterns
- ReactFlow + Zustand: `onNodesChange` calls `applyNodeChanges`, `onEdgesChange` calls `applyEdgeChanges` — established in Phase 33; Phase 34 must not break this
- Registry-driven UI: component metadata in JSON drives rendering (no hardcoded component lists) — same principle applies to toolbox items and node handle placement
- Three-panel layout: ToolboxPanel (left w-60) / CanvasPanel (flex-1) / SidebarPanel (right w-80) — Phase 34 populates left panel, does not change layout

### Integration Points
- Custom node component (`StreamNode.tsx`) registered in `nodeTypes` map passed to `<ReactFlow>` — each canvas node renders via this component
- `registry.components` drives toolbox list (12 items) AND provides `ports[]` for handle placement inside `StreamNode`
- `selectedNodeId` in the Zustand store connects canvas selection events (CANV-04) to SidebarPanel (Phase 35 reads this)
- `addNode` action (to be added to store) is called by canvas `onDrop` with component id + screen position converted to canvas coordinates via `screenToFlowPosition`

</code_context>

<specifics>
## Specific Ideas

- Node card: type name as `text-xs text-muted-foreground`, instance name as `font-semibold text-sm` — functional, unstyled for Phase 38
- Handle positioning: iterate `component.ports.filter(p => p.type === "FlowPort")`, map `side` → ReactFlow `Position` enum (left/right/top/bottom), use `source` type for port_out, `target` type for port_in
- zundo note: if the library has issues, fall back to manual `past[]`/`future[]` snapshot arrays — user was explicit about this as the escape hatch

</specifics>

<deferred>
## Deferred Ideas

- ThermalPort handle rendering — Phase 40
- Component icons/colors — Phase 38 (UI design pass)
- Edge labels showing `connect(a.port_out, b.port_in)` — could be added in Phase 36 (code gen) or Phase 38
- Multi-select with lasso tool — ReactFlow supports this out of the box; may come for free, but no explicit requirement

</deferred>

---

*Phase: 34-canvas-node-editor*
*Context gathered: 2026-04-02*
