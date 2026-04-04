# Phase 41: Layered Canvas - Context

**Gathered:** 2026-04-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Hydraulic and thermal canvas content live on separate toggleable layers so the canvas stays readable when both types of components are present. A toolbar toggle (plus Tab keybind) switches between Hydraulic, Both, and Thermal views. In layer-specific views, off-layer content is dimmed and non-interactive. Layer selection is persisted in the .streamgui project file.

Phase 41 covers:
- Layer toggle control in the toolbar (visual + keybind)
- Dimming behavior for off-layer nodes and edges
- Toolbox filtering to match active layer
- Multi-layer component detection (ChannelAndContacts)
- Persistence of active layer in .streamgui

</domain>

<decisions>
## Implementation Decisions

### Dim vs Hide
- **D-01:** Off-layer content is **dimmed** (low opacity, ~20–30%), not hidden. Spatial context is preserved — you can see where thermal components are while working on hydraulics.
- **D-02:** Dimmed nodes and edges are **non-interactive** (`pointer-events: none`). Cannot be selected, dragged, or connected while in the wrong layer view.
- **D-03:** Dimming applies to both nodes AND edges of the subordinated layer. Thermal edges (amber dashed) are dimmed in Hydraulic view; FlowPort edges are dimmed in Thermal view.

### Toolbox Filtering
- **D-04:** Toolbox filters to layer-relevant components in single-layer views. In Hydraulic view: show Hydraulic-layer components only. In Thermal view: show Thermal-layer components only. In Both view: show all 12 components.
- **D-05:** ChannelAndContacts appears in the toolbox for BOTH Hydraulic and Thermal views (it is dual-layer: has FlowPorts and ThermalPorts). It is always draggable regardless of active layer.

### Multi-layer Component Detection
- **D-06:** Dual-layer membership is **port-based auto-detection** — no registry changes. A component belongs to a layer if it has at least one port of that type in its `ports[]` array. Logic: `hasFlowPort = ports.some(p => p.type === "FlowPort")`, `hasThermalPort = ports.some(p => p.type === "ThermalPort")`.
- **D-07:** ChannelHeatFlux is Hydraulic-only. Its `T_wall` is a scalar parameter (not a ThermalPort), so it has no ThermalPort entries in `ports[]` — single-layer.
- **D-08:** In Thermal view, dual-layer components (ChannelAndContacts) are fully visible, but their FlowPort handles are **dimmed and non-interactive**. Only ThermalPort handles are active for drawing edges.

### Layer Toggle UI
- **D-09:** Layer toggle lives in the **main Toolbar**, centered between the file/code section (left) and export section (right). Three segmented buttons: `[Hydraulic]` `[Both]` `[Thermal]`. Default state: `Both`.
- **D-10:** The toggle must be **visually prominent** — users must immediately understand it controls what is visible on the canvas. Claude picks exact styling, but the control must not look like a generic button group. Consider: a label "Layer:" prefix, distinct background when active, or an icon that signals visibility/layers.
- **D-11:** **Tab key cycles layers** when canvas focus is active: Hydraulic → Both → Thermal → Hydraulic. This MUST intercept and suppress the browser's default Tab focus-cycle behavior. Implementation: keydown handler on the `CanvasPanel` container div (with `tabIndex={0}` or similar), active only when focus is NOT inside a text input, `<select>`, or other form element. Do not globally suppress Tab — only when the canvas container itself has focus.

### Persistence
- **D-12:** Active layer is persisted in `.streamgui`. `StreamProject` schema bumps to **version 2**, adding `activeLayer: "Hydraulic" | "Both" | "Thermal"`. The `deserializeProject` function defaults to `"Both"` when loading a version 1 file (backwards-compatible). Serialize always writes version 2.

### Claude's Discretion
- Exact opacity value for dimmed state (20–30% range — pick what looks clear but still spatially informative)
- Exact visual treatment for toggle prominence (label prefix, active state color, icon choice)
- CSS transition timing for layer switching (instant vs short fade ~100ms)
- Whether Tab interception uses a `keydown` on the outer div or a custom React hook
- Visual state of the toggle when all canvas nodes are single-layer (e.g., only hydraulic components present — Thermal view would be all-dimmed)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` §"v0.8 Requirements" — No LAYR-* requirements exist yet; this phase defines them. Success criteria from ROADMAP.md Phase 41 are the source of truth.

### Roadmap
- `.planning/ROADMAP.md` §"Phase 41: Layered Canvas" — Goal, success criteria (5 items), note about interaction model decisions

### Registry (layer classification source)
- `gui/src/registry/components.json` — `category` field ("Hydraulic" / "Thermal") and `ports[].type` ("FlowPort" / "ThermalPort") per component. Port-based layer detection reads `ports[]` directly.
- `gui/src/registry/types.ts` — `Port` interface with `type` field; `ComponentDefinition` interface

### Existing GUI code (read before editing)
- `gui/src/components/Toolbar.tsx` — Current toolbar layout (left: FileMenu/Code, right: Export); layer toggle buttons go in a new centered section
- `gui/src/components/ToolboxPanel.tsx` — Current toolbox renders all components; filtering by active layer reads `useStore` layer state + port-based detection
- `gui/src/components/CanvasPanel.tsx` — ReactFlow setup; Tab interception keydown handler goes here; layer state flows into node/edge style overrides
- `gui/src/components/StreamNode.tsx` — Node renderer; dimmed state applied via `data.dimmed` prop or CSS class; handle dimming for FlowPort handles in Thermal view
- `gui/src/store/useStore.ts` — Add `activeLayer: "Hydraulic" | "Both" | "Thermal"` state + `setActiveLayer` action; NOT undoable (UI state, not canvas content)
- `gui/src/lib/projectIO.ts` — `StreamProject` interface: add `activeLayer` field, bump version 1→2, add backwards-compat default in `deserializeProject`

### Prior phase context
- `.planning/phases/40-thermal-composition/40-CONTEXT.md` — D-03: ThermalPort handles are amber (#f59e0b); D-05/D-06: FlowPort/ThermalPort type distinction in handles; D-01: ChannelAndContacts has one handle per side (thermal_left/thermal_right)
- `.planning/phases/38-ui-design-pass/38-CONTEXT.md` — D-03/D-04: category color scheme (Hydraulic = blue, Thermal = amber); D-06/D-07: toolbox collapse tracked in Zustand, not persisted
- `.planning/phases/34-canvas-node-editor/34-CONTEXT.md` — D-06: `isValidConnection` pattern for handle type enforcement; established edge/handle type conventions

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `useStore.ts` `AppState` interface: adding `activeLayer` follows the same pattern as `bottomPanelOpen` (UI state boolean, not canvas content, not pushed to undo stack, not `isDirty`)
- `ToolboxPanel.tsx`: currently maps all registry components to `ToolboxItem`; filtering by active layer = add a `filter()` before the map using port-based detection utility
- `StreamNode.tsx`: node appearance is driven by `data` props; dimming can be applied via a `dimmed` boolean in node data (set by the store/canvas before passing to ReactFlow) or via a CSS class override
- `CanvasPanel.tsx`: already has a `containerRef` for focus management (used for drag-drop focus restore); Tab interception can attach to the same container

### Established Patterns
- Zustand UI state: non-canvas state (panel collapse, validation results) lives in the store but is NOT part of `CanvasSnapshot` (undo stack). `activeLayer` follows this pattern.
- ReactFlow node styling: nodes receive `className` or inline `style` via the `nodes[]` array in the store; dimming can be applied by enriching `node.style` based on `activeLayer` in a selector/derived value
- Registry-driven rendering: all component-specific logic reads from `getComponent()` / `components.json`. Layer detection is no exception — use `comp.ports.some(p => p.type === "ThermalPort")`.

### Integration Points
- `Toolbar.tsx`: new centered `<div>` section with three `<Button>` or a shadcn `ToggleGroup` component for the layer switcher
- `ToolboxPanel.tsx` + `useStore.ts` `activeLayer`: filter `Object.values(registry)` by whether the component is relevant to the active layer
- `CanvasPanel.tsx` keydown handler: `e.key === "Tab"` → prevent default, call `cycleLayer()` store action — but only if `e.target` is not an input/textarea/select
- `projectIO.ts` `StreamProject` v2: `{ version: 2, nodes, edges, bcs, activeLayer }`. Deserializer: `if (parsed.version === 1) return { ...parsed, activeLayer: "Both" }`

</code_context>

<specifics>
## Specific Ideas

- "It has to be CLEAR that that is the button that determines stuff because I don't want it to feel clunky or users not know why they can't see all their stuff." — The toggle must be obviously a layer-visibility control, not a generic segmented button. Prominent label, strong active state, maybe an eye/layers icon. Users should never be confused about why content appears dimmed.
- "Tab key to cycle between the options" + "make sure you disable whatever Tab does right now" — Tab interception is a first-class requirement, not a nice-to-have. Must suppress default browser Tab focus-cycling when the canvas is the active context.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 41-layered-canvas*
*Context gathered: 2026-04-03*
