# Phase 41: Layered Canvas - Research

**Researched:** 2026-04-03
**Domain:** React GUI -- canvas layer visibility, ReactFlow node/edge styling, Zustand state, shadcn toggle-group
**Confidence:** HIGH

## Summary

Phase 41 adds a layer toggle system to the STREAM Composer GUI so that hydraulic and thermal canvas content can be viewed independently or together. The implementation touches 6 existing files (Toolbar, ToolboxPanel, CanvasPanel, StreamNode, useStore, projectIO) and requires installing one new shadcn component (toggle-group). All decisions are locked in CONTEXT.md with clear implementation paths.

The core challenge is applying per-node and per-edge opacity/interactivity changes based on an `activeLayer` state variable, while correctly handling dual-layer components (ChannelAndContacts) and their mixed port types. The architecture is straightforward: a new `activeLayer` field in the Zustand store drives conditional styling in ReactFlow node/edge arrays and filtering in the toolbox.

**Primary recommendation:** Add `activeLayer` to the store, derive node/edge styling via enrichment before passing to ReactFlow (not via StreamNode internal changes), filter toolbox using port-based detection, and bump the project schema to v2 with backwards-compatible deserialization.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Off-layer content is dimmed (low opacity, ~20-30%), not hidden. Spatial context preserved.
- **D-02:** Dimmed nodes and edges are non-interactive (pointer-events: none). Cannot be selected, dragged, or connected in wrong layer view.
- **D-03:** Dimming applies to both nodes AND edges of the subordinated layer.
- **D-04:** Toolbox filters to layer-relevant components in single-layer views.
- **D-05:** ChannelAndContacts appears in toolbox for BOTH Hydraulic and Thermal views (dual-layer).
- **D-06:** Dual-layer membership is port-based auto-detection. Component belongs to a layer if it has at least one port of that type.
- **D-07:** ChannelHeatFlux is Hydraulic-only (T_wall is scalar parameter, not ThermalPort).
- **D-08:** In Thermal view, dual-layer components show dimmed FlowPort handles. In Hydraulic view, ThermalPort handles are dimmed.
- **D-09:** Layer toggle in main Toolbar, centered. Three segmented buttons: Hydraulic, Both, Thermal. Default: Both.
- **D-10:** Toggle must be visually prominent -- users must immediately understand it controls visibility.
- **D-11:** Tab key cycles layers when canvas has focus. Must suppress browser default Tab behavior. Guard against text inputs.
- **D-12:** Active layer persisted in .streamgui. Schema bumps to version 2. Backwards-compat default "Both" for v1 files.

### Claude's Discretion
- Exact opacity value for dimmed state (20-30% range)
- Exact visual treatment for toggle prominence (label prefix, active state color, icon choice)
- CSS transition timing for layer switching (instant vs short fade ~100ms)
- Whether Tab interception uses keydown on outer div or custom React hook
- Visual state of toggle when all canvas nodes are single-layer

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.
</user_constraints>

## Project Constraints (from CLAUDE.md)

- All UI primitives use shadcn/ui (DSGN-01)
- No hand-rolled CSS component implementations
- Component tests use `@vitest-environment jsdom` docblock per-file (not global jsdom)
- Store pattern: non-canvas UI state (like `activeLayer`) is NOT part of `CanvasSnapshot`, NOT pushed to undo stack, does NOT set `isDirty`
- All exports declared in module entry points
- TypeScript strict mode

## Standard Stack

### Core (already installed)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| @xyflow/react | ^12.10.2 | ReactFlow canvas | Already in use |
| zustand | ^5.0.12 | State management | Already in use |
| lucide-react | ^1.7.0 | Icons (Layers icon) | Already in use |
| radix-ui | ^1.4.3 | Primitives (via shadcn) | Already in use |

### Phase 41 Addition
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| shadcn toggle-group | N/A (codegen) | Segmented layer toggle | `npx shadcn@latest add toggle-group` |

**Installation:**
```bash
cd gui && npx shadcn@latest add toggle-group
```

## Architecture Patterns

### Files Modified
```
gui/src/
  store/useStore.ts           # Add activeLayer state + setActiveLayer + cycleLayer
  components/Toolbar.tsx       # Add centered layer toggle section
  components/ToolboxPanel.tsx  # Filter components by active layer
  components/CanvasPanel.tsx   # Tab key interception + node/edge style enrichment
  components/StreamNode.tsx    # Handle dimming for dual-layer nodes (D-08)
  lib/projectIO.ts            # StreamProject v2 schema + backwards compat
```

### Pattern 1: Store-Driven Layer State (NOT undoable)
**What:** `activeLayer` follows the same pattern as `toolboxCollapsed` / `sidebarCollapsed` -- UI view state that is not canvas content.
**When to use:** Always for view-layer state.
**Key detail:** `activeLayer` is NOT in `CanvasSnapshot`, does NOT trigger `isDirty`, does NOT push to undo stack. It IS persisted to .streamgui (unlike panel collapse which is session-only).

```typescript
// In AppState interface:
activeLayer: "Hydraulic" | "Both" | "Thermal";
setActiveLayer: (layer: "Hydraulic" | "Both" | "Thermal") => void;
cycleLayer: () => void;

// In store creation:
activeLayer: "Both",
setActiveLayer: (layer) => set({ activeLayer: layer }),
cycleLayer: () => {
  const order = ["Hydraulic", "Both", "Thermal"] as const;
  const { activeLayer } = get();
  const idx = order.indexOf(activeLayer);
  set({ activeLayer: order[(idx + 1) % 3] });
},
```

### Pattern 2: Node/Edge Style Enrichment Before ReactFlow
**What:** Apply dimming by modifying `node.style` and `edge.style` in a derived computation, before nodes/edges reach `<ReactFlow>`.
**When to use:** For node and edge dimming based on active layer.
**Why:** Keeps StreamNode.tsx changes minimal. ReactFlow respects `node.style.opacity` and `node.style.pointerEvents` natively.

**Critical finding:** The current codebase does NOT store `edge.data.edgeType` on edges. The UI-SPEC suggests `edge.data?.edgeType === "thermal"` but this field does not exist. Edge type must be determined by checking connected port types via the registry (same pattern as `addEdge` in useStore and `detectThermalTopologies` in codeGenerator). Alternatively, the simpler approach: check `edge.style?.stroke === "#f59e0b"` since thermal edges already have this style applied at creation time. The style-based check is fragile but matches existing conventions. **Recommendation:** Use style-based detection (`edge.style?.stroke === "#f59e0b"`) for edge dimming since it avoids touching edge creation logic. If this feels too fragile, add `data: { edgeType: "thermal" }` during edge creation in `addEdge`.

### Pattern 3: Port-Based Layer Detection Utility
**What:** A shared utility function that determines which layer(s) a component belongs to, based on its ports.
**When to use:** In toolbox filtering AND node dimming AND handle dimming.

```typescript
// Shared utility (can live in registry/index.ts or a new lib/layers.ts)
export function getComponentLayers(comp: ComponentDefinition): { hasFlow: boolean; hasThermal: boolean } {
  return {
    hasFlow: comp.ports.some(p => p.type === "FlowPort"),
    hasThermal: comp.ports.some(p => p.type === "ThermalPort"),
  };
}
```

### Pattern 4: Handle Dimming in StreamNode (D-08)
**What:** When in single-layer view, dual-layer nodes (ChannelAndContacts) stay fully visible but off-layer handles are dimmed.
**When to use:** StreamNode must read `activeLayer` from the store and conditionally apply opacity/pointer-events to individual Handle elements.
**Key detail:** This is the ONE case where StreamNode needs to know about `activeLayer`. Single-layer nodes are fully dimmed at the node level (via style enrichment), so StreamNode doesn't need to handle those.

### Pattern 5: Tab Key Interception
**What:** Add Tab key handler to CanvasPanel container.
**When to use:** When canvas (or its non-input children) has focus.
**Key detail:** The existing `containerRef` div has `tabIndex={-1}`. The CONTEXT says to use `tabIndex={0}` or similar. The current `tabIndex={-1}` allows programmatic focus (via `containerRef.current?.focus()` in onDrop) but prevents Tab-navigation TO the container. Changing to `tabIndex={0}` would allow Tab to focus the container -- but since Tab is being intercepted FOR cycling, `tabIndex={-1}` is fine. The handler should be on `onKeyDown` of the container div.

**Implementation note:** The existing keyboard handler for undo/redo uses `window.addEventListener("keydown")`. Tab interception should NOT use window-level -- it must only fire when the canvas container has focus. Use the `onKeyDown` prop on the container div.

### Anti-Patterns to Avoid
- **Do NOT add activeLayer to CanvasSnapshot:** It's view state, not content. Undo should not change the visible layer.
- **Do NOT set isDirty when changing layers:** Layer switching is not a document edit.
- **Do NOT modify the component registry JSON:** Layer detection is port-based auto-detection, not a registry field.
- **Do NOT hide dimmed nodes:** D-01 explicitly says dim, not hide. Spatial context must be preserved.
- **Do NOT use window-level Tab interception:** Would break Tab in inputs, selects, and other form elements across the app.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Segmented toggle control | Custom button group | shadcn `ToggleGroup` | Handles single-select semantics, keyboard nav, ARIA |
| Layer icon | Custom SVG | lucide-react `Layers` | Already installed, consistent with existing icons |

## Common Pitfalls

### Pitfall 1: Edge Type Detection Without Data Field
**What goes wrong:** UI-SPEC references `edge.data?.edgeType === "thermal"` but edges have no `edgeType` field.
**Why it happens:** Thermal edge styling was applied via `edge.style` in Phase 40, not via a data field.
**How to avoid:** Either (a) detect thermal edges by checking `edge.style?.stroke === "#f59e0b"` or (b) add `data: { edgeType: "thermal" }` to thermal edges in `addEdge`. Option (b) is cleaner but requires also setting it during project deserialization for existing saved projects.
**Warning signs:** All edges appear dimmed in Thermal view, or no edges are dimmed.

### Pitfall 2: ToggleGroup onValueChange Deselection
**What goes wrong:** shadcn ToggleGroup with `type="single"` fires `onValueChange("")` when clicking the already-selected item (deselects).
**Why it happens:** Radix ToggleGroup single-mode allows deselection by default.
**How to avoid:** Guard `onValueChange`: `if (value) setActiveLayer(value)`. Never allow empty/null active layer.
**Warning signs:** Layer toggle becomes "un-toggled" with no item selected.

### Pitfall 3: Tab Key Bubbling
**What goes wrong:** Tab press both cycles the layer AND moves focus to the next element.
**Why it happens:** Missing `e.preventDefault()` or `e.stopPropagation()`.
**How to avoid:** Call both `e.preventDefault()` and `e.stopPropagation()` in the Tab handler.
**Warning signs:** Focus jumps away from canvas when pressing Tab.

### Pitfall 4: Dimmed Nodes Still Selectable via ReactFlow
**What goes wrong:** Clicking on a dimmed node selects it, even though it has `pointer-events: none`.
**Why it happens:** ReactFlow may handle click events at a layer above individual node styles.
**How to avoid:** Test that `pointer-events: none` on `node.style` actually prevents selection. If not, add an `interactionWidth: 0` or filter click events in `onNodeClick` based on active layer.
**Warning signs:** Dimmed nodes get selected, sidebar opens for a dimmed component.

### Pitfall 5: Persistence Does Not Set isDirty
**What goes wrong:** `activeLayer` is persisted to .streamgui but changing it does NOT set isDirty, so the new layer value may not be saved if the user closes without another edit.
**Why it happens:** CONTEXT says activeLayer is "UI state, not canvas content" -- but it IS persisted.
**How to avoid:** This is an intentional design choice from D-12 + established patterns. The layer state will be saved whenever the user makes any content change that triggers isDirty. If a user only changes the layer and closes, the layer change is lost. This is acceptable -- layer view is a preference, not content.
**Warning signs:** User sets Hydraulic view, saves, reopens -> sees Both view.

**Recommendation for Pitfall 5:** Consider setting `isDirty` when `activeLayer` changes, since it IS persisted. This deviates from the toolboxCollapsed pattern (which is NOT persisted), but aligns with the fact that layer state is part of the saved document. **The planner should make a call on this.**

### Pitfall 6: loadProjectFromPath Must Restore activeLayer
**What goes wrong:** Loading a v2 project file doesn't restore the saved layer -- canvas always shows "Both".
**Why it happens:** `loadProjectFromPath` sets nodes/edges/bcs but doesn't set `activeLayer`.
**How to avoid:** Add `activeLayer: project.activeLayer` to the `set()` call in `loadProjectFromPath`.
**Warning signs:** Saved layer preference not restored on file open.

## Code Examples

### Toolbox Filtering (verified pattern from existing ToolboxPanel)
```typescript
// In ToolboxPanel.tsx
import useStore from "../store/useStore";
import { getComponentLayers } from "../lib/layers";

const activeLayer = useStore((s) => s.activeLayer);

// Filter components before rendering
const visibleHydraulic = hydraulicComponents.filter(comp => {
  if (activeLayer === "Both") return true;
  const { hasFlow, hasThermal } = getComponentLayers(comp);
  if (activeLayer === "Hydraulic") return hasFlow;
  if (activeLayer === "Thermal") return hasThermal;
  return true;
});
```

### Node Style Enrichment (in CanvasPanel or a useMemo)
```typescript
const enrichedNodes = useMemo(() => {
  if (activeLayer === "Both") return nodes;
  return nodes.map(node => {
    const comp = getComponent((node.data as StreamNodeData).componentId);
    if (!comp) return node;
    const { hasFlow, hasThermal } = getComponentLayers(comp);
    const isDualLayer = hasFlow && hasThermal;
    if (isDualLayer) return node; // Never fully dimmed
    const belongsToLayer = activeLayer === "Hydraulic" ? hasFlow : hasThermal;
    if (belongsToLayer) return node;
    return {
      ...node,
      style: { ...node.style, opacity: 0.2, pointerEvents: "none" as const, transition: "opacity 150ms ease" },
    };
  });
}, [nodes, activeLayer]);
```

### StreamProject v2 Type
```typescript
export interface StreamProject {
  version: 1 | 2;
  nodes: Node[];
  edges: Edge[];
  bcs: BCEntry[];
  activeLayer?: "Hydraulic" | "Both" | "Thermal"; // Present in v2
}
```

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | vitest 4.1.2 |
| Config file | gui/vitest.config.ts |
| Quick run command | `cd gui && npx vitest run --reporter=verbose` |
| Full suite command | `cd gui && npx vitest run` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SC-1 | Layer toggle switches between Hydraulic/Both/Thermal views | unit (store) | `cd gui && npx vitest run src/store/__tests__/useStore.test.ts -t "layer"` | Extend existing |
| SC-2 | In Hydraulic view, thermal nodes/edges are dimmed | unit (logic) | `cd gui && npx vitest run src/lib/__tests__/layers.test.ts` | Wave 0 |
| SC-3 | In Thermal view, hydraulic nodes/edges are dimmed | unit (logic) | Same as SC-2 | Wave 0 |
| SC-4 | Dual-layer components (ChannelAndContacts) visible in both views | unit (logic) | Same as SC-2 | Wave 0 |
| SC-5 | Layer persisted in .streamgui | unit (projectIO) | `cd gui && npx vitest run src/lib/__tests__/projectIO.test.ts -t "v2"` | Extend existing |

### Sampling Rate
- **Per task commit:** `cd gui && npx vitest run --reporter=verbose`
- **Per wave merge:** `cd gui && npx vitest run`
- **Phase gate:** Full suite green before /gsd:verify-work

### Wave 0 Gaps
- [ ] `gui/src/lib/__tests__/layers.test.ts` -- layer detection utility tests (isNodeDimmed, isEdgeDimmed, isComponentVisibleInLayer)
- [ ] Extend `gui/src/lib/__tests__/projectIO.test.ts` -- v2 serialization/deserialization, v1 backwards compat
- [ ] Extend `gui/src/store/__tests__/useStore.test.ts` -- activeLayer, setActiveLayer, cycleLayer actions

## Open Questions

1. **Should activeLayer changes set isDirty?**
   - What we know: activeLayer IS persisted (unlike toolboxCollapsed which is NOT). The established pattern says "UI state = no isDirty". But persisted UI state is a grey area.
   - What's unclear: Whether users will be confused when layer preference is lost after a layer-only change + close.
   - Recommendation: Set isDirty when activeLayer changes. It's persisted, so it IS part of the document state.

2. **Edge type detection approach**
   - What we know: No `edgeType` data field exists on edges. Thermal edges identified by amber stroke style.
   - What's unclear: Whether style-based detection is robust enough long-term.
   - Recommendation: Add `data: { edgeType: "thermal" | "flow" }` to edges during creation in `addEdge`. Also handle existing saved projects by inferring edge type from style in `deserializeProject` or during style enrichment.

## Sources

### Primary (HIGH confidence)
- GUI source code: useStore.ts, Toolbar.tsx, ToolboxPanel.tsx, CanvasPanel.tsx, StreamNode.tsx, projectIO.ts (direct inspection)
- Registry types: gui/src/registry/types.ts (Port.type field)
- Phase 41 CONTEXT.md and UI-SPEC.md (locked decisions)

### Secondary (MEDIUM confidence)
- shadcn ToggleGroup: deselection behavior inferred from Radix UI ToggleGroup docs pattern (single mode allows deselect)
- ReactFlow node.style.pointerEvents: inferred from ReactFlow API -- nodes accept style prop

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - all libraries already installed, toggle-group is a standard shadcn add
- Architecture: HIGH - all patterns established by prior phases, clear integration points
- Pitfalls: HIGH - identified from direct code inspection, known Radix/ReactFlow behaviors

**Research date:** 2026-04-03
**Valid until:** 2026-05-03 (stable -- no external dependency changes expected)
