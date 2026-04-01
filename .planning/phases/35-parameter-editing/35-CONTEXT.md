# Phase 35: Parameter Editing - Context

**Gathered:** 2026-04-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Populate the `SidebarPanel` stub so clicking any canvas node opens an editable form showing that component's parameters, with type-aware fields, mode switching (Pump), PipeGeometry picker, validation, and component rename. No visual design pass — Phase 38 handles that. Factory correlation editing (regime_dependent, elenbaas_htc, maximal_htc) is deferred to Phase 35.1.

</domain>

<decisions>
## Implementation Decisions

### PipeGeometry Picker
- **D-01:** Segmented control: `[ Circular | Rectangular ]`. Conditional fields render below based on selection. Circular shows L + D; Rectangular shows L + W + H.
- **D-02:** Switching geometry type clears all dimension fields to empty. No value migration between types. Prevents nonsensical values surviving a mode switch.

### Function-Type Parameters (htc_correlation, friction_correlation)
- **D-03:** Show a dropdown of all available correlation names for each Function-type parameter. Simple closures are fully interactive: `dittus_boelter`, `constant_Nusselt` (HTC); `blasius_friction`, `laminar_friction` (friction).
- **D-04:** Factory correlations (`regime_dependent`, `elenbaas_htc`, `maximal_htc`) appear in the dropdown but are **grayed out and non-selectable** in Phase 35, with a tooltip: "Factory correlation editing coming in a future update." Phase 35.1 activates them with nested sub-parameter forms.
- **D-05:** The dropdown option list must come from the registry — add an `options` field to Function-type parameter entries in `components.json`. Do not hardcode correlation names in the UI component.

### Validation
- **D-06:** Validation fires **on-blur** (when the user leaves a field). No validation noise while typing. Error message appears inline below the field.
- **D-07:** Validation rules per field type: `Int` — must be a positive integer; `Real` — must be a finite number (NaN/Infinity rejected); `PipeGeometry` sub-fields — all required dimensions must be positive; component name (PARA-05) — must match Julia identifier pattern `[a-zA-Z_][a-zA-Z0-9_]*`.

### Sidebar Selection Behavior
- **D-08:** Clicking the canvas background (deselect) clears the sidebar to the placeholder state: "Select a component to view its properties." The `selectedNodeId` in the store returns to `null`. No stale data shown.
- **D-09:** Clicking a node sets `selectedNodeId` and the sidebar renders that node's form. Switching from one node to another updates the form immediately.

### Store Integration
- **D-10:** Add `updateNodeParams(nodeId: string, params: Partial<StreamNodeData>)` action to the Zustand store. This action updates the node's `data` field (instanceName and/or parameters). Undo/redo via zundo covers param edits — no special handling needed.

### Claude's Discretion
- Exact shadcn/ui components to install and use (Input, Label, Button for segmented control, Badge for read-only, Select for dropdowns)
- Sidebar section layout (name field at top, then parameters grouped by type)
- Exact error message wording for each validation rule
- Whether to show units (m, kg/s, Pa) as suffix labels on numeric inputs

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing sidebar + store
- `gui/src/components/SidebarPanel.tsx` — Current stub: shows placeholder text only. Phase 35 replaces this with the full parameter form.
- `gui/src/store/useStore.ts` — Zustand store with `selectedNodeId`, `nodes` (each with `data: StreamNodeData`). Phase 35 adds `updateNodeParams` action.
- `gui/src/store/useStore.ts` — `StreamNodeData` interface: `{ componentId, instanceName, parameters: Record<string, unknown> }`. Phase 35 populates `parameters` on every edit.

### Registry (source of truth for form generation)
- `gui/src/registry/components.json` — Parameter definitions per component: `name`, `type` (Int/Real/PipeGeometry/Function), `required`, `default`, `unit`, `description`. Phase 35 must also add an `options` field to Function-type parameters listing available correlations.
- `gui/src/registry/types.ts` — TypeScript interfaces; may need extension for Function-type `options` field.

### Phase 34 canvas selection wiring
- `.planning/phases/34-canvas-node-editor/34-CONTEXT.md` — D-09: `selectedNodeId` in store connects canvas selection to sidebar. ReactFlow `onNodeClick` calls `selectNode(nodeId)`; `onPaneClick` calls `selectNode(null)`.

### Requirements
- `.planning/REQUIREMENTS.md` §"Parameter Editing" → PARA-01..06 — Exact acceptance criteria

### Phase 35.1 (factory correlations — deferred)
- `.planning/ROADMAP.md` §"Phase 35.1: Correlation Picker" — Full design decisions for factory correlation sub-parameter forms, registry schema extension, code gen contract. Read this before implementing Phase 35.1.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `gui/src/store/useStore.ts`: `temporal(...)` zundo wrapper already in place — `updateNodeParams` action added here will be covered by undo/redo automatically
- `gui/src/registry/index.ts` + `components.json`: `getComponent(id)` returns full parameter list with types — drives form field rendering without any hardcoding
- `gui/src/components/StreamNode.tsx`: reads `nodeData.instanceName` from store — rename changes here must propagate to canvas node label immediately via store update
- `gui/src/index.css`: shadcn/ui CSS variables already configured (New York/Zinc style from Phase 33). No `ui/` component files installed yet — Phase 35 installs them via `npx shadcn add`.

### Established Patterns
- Registry-driven UI: component metadata in JSON drives rendering — same principle applies to sidebar form field generation (loop over `component.parameters`, render field per type)
- Zustand store: `set({ nodes: nodes.map(n => n.id === id ? { ...n, data: { ...n.data, ...patch } } : n) })` is the update pattern for node data

### Integration Points
- `selectedNodeId` → `nodes.find(n => n.id === selectedNodeId)` gives the selected node; `getComponent(node.data.componentId)` gives its parameter schema
- `updateNodeParams` action writes back into `nodes[].data.parameters` — Phase 36 code gen reads from the same location to emit Julia constructor arguments
- `instanceName` in `StreamNodeData` is the `@named` variable name in generated code (Phase 36) — rename validation must enforce valid Julia identifier format

</code_context>

<specifics>
## Specific Ideas

- Segmented control for PipeGeometry: two `<Button variant="outline">` side by side, active one has `variant="default"`. Below it, fields switch conditionally based on state.
- Correlation dropdown: `<Select>` from shadcn/ui. Factory options rendered with `disabled` attribute + shadcn tooltip showing "Factory correlation editing coming in a future update."
- Component name field at the very top of the sidebar, above the parameter list, with Julia identifier validation on blur.
- Units as suffix text inside the input container (e.g., `m`, `Pa`, `kg/s`) — not a separate label.

</specifics>

<deferred>
## Deferred Ideas

- **Factory correlation sub-parameter forms** — Phase 35.1. Full design in ROADMAP.md §Phase 35.1. Factory correlations (regime_dependent, elenbaas_htc, maximal_htc) grayed out in Phase 35 dropdown, fully interactive in Phase 35.1.
- **marco_han_nusselt in correlation list** — check if this is exported from STREAM.jl before adding to picker; may belong in Phase 35.1 only.
- **Correlation closure editing** — explicitly deferred to v0.9+ in PROJECT.md; Phase 35.1 handles the factory UI but not arbitrary closure composition.

</deferred>

---

*Phase: 35-parameter-editing*
*Context gathered: 2026-04-02*
