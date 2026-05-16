# Phase 68: Layers System Overhaul - Research

**Researched:** 2026-05-16
**Domain:** ReactFlow v12 layer management, shadcn/ui components, Zustand store refactor, .scp schema migration
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Four layer accent palette: Hydraulic=blue-500 (#3b82f6), Thermal=amber-500 (#f59e0b), Sources=violet-500 (#8b5cf6), Reactor Physics=rose-500 (#f43f5e). Phase 68 uses them only on the Layers chip indicator squares and popover labels.
- **D-02:** Dual-layer node (e.g. ChannelAndContacts) is visible if ANY of its layers is active; hides/dims only when ALL its layers are off.
- **D-03:** Dual-layer node with one layer off: off-layer port handles dim to opacity 0.2 and lock non-interactive; active-layer handles remain interactive.
- **D-04:** Edges follow their own layer, not their endpoint nodes. A thermal edge dims when Thermal is off regardless of whether its endpoints are visible.
- **D-05:** `cycleLayer()` store action removed. `LayerView = "Hydraulic" | "Both" | "Thermal"` type deleted.
- **D-06:** Tab key shortcut in CanvasPanel.tsx removed. No replacement.
- **D-07:** View menu "Layer" radio submenu removed (Phase 67 D-11 corrected). View menu retains only "Toggle Code Preview" and Theme submenu.
- **D-08:** `SecondaryToolbar.tsx` deleted entirely. Two-strip layout collapses to single titlebar.
- **D-09:** Export button moves to File menu as "Export to Julia…" (between Save As and any future entries).
- **D-10:** Code Preview toggle moves to bottom panel's own header bar. Closed state: persistent 20px stub strip showing "Code" + ChevronUp. Open state: collapse button (ChevronDown) in tab header row.

### Claude's Discretion
- State shape: `activeLayers: Record<LayerKey, boolean>` (default all true) + `hideOffLayer: boolean` (default false). Actions: `toggleLayer(key)`, `setLayerVisible(key, visible)`, `setAllLayersVisible(visible)`.
- Layer membership: `category` field from `ComponentDefinition` (not port-type sniffing).
- Off-layer locking: per-node ReactFlow props `{ selectable: false, draggable: false }` in enrichment pass. Hide mode: `{ hidden: true }`.
- LayersChip placement: appended to existing `absolute top-2 right-2 z-10 flex flex-col gap-1` overlay stack in CanvasPanel.tsx.
- Popover: shadcn Popover `side="left"` `align="start"`, width `w-52`.
- Auto-enable on connect: hook into `onConnect`, call `setLayerVisible(key, true)` for any newly-connected off-layer; never block.
- `.scp` migration: `active_layer` string → `active_layers` object + `hide_off_layer`. Read-side shim: `"Both"` → all true, `"Hydraulic"` → hydraulic true + others false, `"Thermal"` → thermal true + others false.

### Deferred Ideas (OUT OF SCOPE)
- Extended accent palette to node borders and port handles (Phase 72).
- Settings dialog shell (Phase 72).
- Reactor Physics layer components (PointKinetics/ReactivityController GUI integration).
- Per-component rotation as autoflip fallback (Section 6 parked).
</user_constraints>

---

## Summary

Phase 68 replaces the three-mode layer toggle (`Hydraulic / Both / Thermal`) with a four-layer independent-checkbox system, adds a floating `LayersChip` overlay button with popover, migrates Export to the File menu, redesigns the bottom panel with a header bar and persistent closed stub, and deletes `SecondaryToolbar.tsx` entirely.

The core technical work is a coordinated refactor across five subsystems: (1) `layers.ts` full rewrite, (2) `useStore.ts` state-shape replacement, (3) `CanvasPanel.tsx` enrichment-pass and `onConnect` updates, (4) `projectIO.ts` schema migration, and (5) new `LayersChip.tsx` component. Several existing consumer files must be updated to remove references to the deleted `LayerView` / `cycleLayer` API.

ReactFlow v12 (`@xyflow/react: ^12.10.2`) is confirmed to honor per-node `selectable`, `draggable`, and `hidden` props — these interact correctly with the global `nodesDraggable={!interactiveLocked}` prop, as ReactFlow computes `isDraggable = node.draggable ?? nodesDraggable`. Setting `node.draggable: false` explicitly overrides the global prop for that node. The `hidden: true` prop causes ReactFlow to render `null` for the node and exclude it from interaction and layout calculations while preserving it in store state.

**Primary recommendation:** Proceed exactly as specified in CONTEXT.md decisions. The codebase is well-structured for this refactor — the existing enrichment-pass pattern in CanvasPanel.tsx and the store selector discipline make the changes low-risk and well-isolated.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Layer state (which layers are active) | Store (Zustand) | `.scp` persistence | Layer state is view preference, not model content |
| Layer membership of a component | Registry (`components.json` `category`) | `layers.ts` utility | Category is the single source of truth per CONTEXT.md Claude's Discretion |
| Off-layer visual enrichment (dim/hide/lock) | CanvasPanel.tsx enrichment pass | StreamNode.tsx port handles | Follows established Phase 65 pattern |
| Layer chip UI | LayersChip.tsx (new) | CanvasPanel.tsx (host) | Floating overlay, same cluster as Phase 65 buttons |
| Export-to-Julia | FileMenu.tsx | exportCode.ts (unchanged) | SecondaryToolbar removal requires relocation |
| Bottom panel open/close | BottomPanel.tsx header + stub | ViewMenu "Toggle Code Preview" | D-10 contract |
| `.scp` serialization of layer state | projectIO.ts | useStore.ts (caller) | Existing pattern for layout block fields |

---

## Standard Stack

### Core (no new installs, existing dependencies)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| @xyflow/react | ^12.10.2 | Canvas, node/edge rendering, `hidden`/`selectable`/`draggable` per-node props | Already in use; confirmed v12 API [VERIFIED: inspected node_modules] |
| zustand | existing | Store state for `activeLayers`, `hideOffLayer` | Established store pattern |
| shadcn Popover | already installed | Layers chip expand panel | Used in Phase 62 ResourceReferencePicker |
| shadcn Toggle | already installed (`toggle.tsx`) | Dim/Hide toggle pair in popover | Already used in SecondaryToolbar's ToggleGroup |
| lucide-react | existing | ChevronDown, ChevronUp, layers icon | Existing icon library |

### New Install Required

| Library | Version | Purpose | Install Command |
|---------|---------|---------|----------------|
| shadcn Checkbox | latest | Four layer checkboxes in popover | `npx shadcn add checkbox` (from `gui/` dir) |

**Confirmed NOT installed:** `gui/src/components/ui/checkbox.tsx` does not exist. [VERIFIED: `ls` check]

**Installation:**
```bash
cd gui && npx shadcn add checkbox
```

**Version verification:** Not applicable for shadcn installs — shadcn generates source files from its registry, not npm packages. The `components.json` preset (new-york, zinc, CSS variables) governs the generated file style. [VERIFIED: `gui/components.json`]

---

## Package Legitimacy Audit

No third-party npm packages are introduced in this phase. `npx shadcn add checkbox` generates a local source file from the official shadcn registry — it is not a runtime dependency and is not distributed via npm. No slopcheck required. [VERIFIED: shadcn official registry pattern, UI-SPEC `## Registry Safety`]

**Packages removed due to slopcheck:** none
**Packages flagged as suspicious:** none

---

## Architecture Patterns

### System Architecture Diagram

```
User toggles layer checkbox
         │
         ▼
useStore.toggleLayer(key) ─────────────────────────────────────────►  activeLayers: Record<LayerKey, bool>
                                                                        hideOffLayer: bool
                                                                             │
                              ┌──────────────────────────────────────────────┘
                              ▼
         CanvasPanel.tsx enrichedNodes useMemo (runs on nodes + activeLayers change)
              │
              ├─ isNodeVisible(node, activeLayers) → fully off?
              │      ├─ dim mode: { style: { opacity: 0.2 }, selectable: false, draggable: false }
              │      └─ hide mode: { hidden: true }
              │
              └─ dual-layer node, one layer off → node visible, off-layer port handles dim (in StreamNode.tsx)
                        (StreamNode reads activeLayers directly for handle-level dim)

         CanvasPanel.tsx enrichedEdges useMemo (runs on edges + activeLayers change)
              └─ isEdgeDimmed(edge, activeLayers) → { style: { opacity: 0.15 } } or { hidden: true }

         CanvasPanel.tsx onConnect handler
              └─ after connection → check source/target node layers → setLayerVisible(key, true) for any off

         LayersChip.tsx (new, in top-right overlay stack)
              └─ Popover → 4x Checkbox rows + Dim/Hide Toggle pair
                    └─ reads/writes activeLayers + hideOffLayer via store selectors

         projectIO.ts serialize/deserialize
              └─ layout.active_layers + layout.hide_off_layer
                    └─ read-side compat shim: legacy active_layer string → Record<LayerKey, bool>
```

### Recommended File Structure (changed files only)

```
gui/src/
  lib/
    layers.ts                    # Full rewrite: LayerKey, ActiveLayers, isNodeVisible, isEdgeDimmed, getComponentLayers
    __tests__/layers.test.ts     # Full rewrite matching new API
    projectIO.ts                 # Add active_layers + hide_off_layer to layout block; add compat shim
  store/
    useStore.ts                  # Replace activeLayer/cycleLayer/setActiveLayer with activeLayers/hideOffLayer + new actions
  components/
    LayersChip.tsx               # NEW — floating chip + popover
    CanvasPanel.tsx              # 4 changes: enrichment pass rewrite, onConnect layer-auto-enable, Tab removal, LayersChip add
    StreamNode.tsx               # Update dual-layer handle dimming for new activeLayers shape
    ToolboxPanel.tsx             # Update to use new isNodeVisible API (category-based)
    SecondaryToolbar.tsx         # DELETED
    BottomPanel.tsx              # Add header with collapse button; replace early-return with stub strip
    FileMenu.tsx                 # Add "Export to Julia…" item
    ViewMenu.tsx                 # Add "Toggle Code Preview" + Ctrl+` hint; remove Layer submenu (already clean)
    App.tsx                      # Remove SecondaryToolbar import + render; add Ctrl+` keyboard handler
    CustomTitlebar.tsx           # (may need no change — SecondaryToolbar renders in App.tsx not here)
```

### Pattern 1: Per-Node Enrichment in CanvasPanel.tsx

The existing enrichment pass (lines ~97-131) is the correct extension point. It runs as a `useMemo` over `nodes` + `activeLayer`. The rewrite subscribes to `activeLayers` + `hideOffLayer` instead and sets additional props:

```typescript
// Source: existing CanvasPanel.tsx enrichment pass pattern
const enrichedNodes = useMemo(() => {
  return nodes.map(node => {
    const nodeData = node.data as unknown as StreamNodeData;
    const comp = getComponent(nodeData.componentId);
    if (!comp) return node;
    const visible = isNodeVisible(comp, activeLayers); // category-based
    if (visible) return node;
    if (hideOffLayer) {
      return { ...node, hidden: true };
    }
    return {
      ...node,
      style: { ...node.style, opacity: 0.2, pointerEvents: "none" as const, transition: "opacity 150ms ease" },
      selectable: false,
      draggable: false,
    };
  });
}, [nodes, activeLayers, hideOffLayer]);
```

[ASSUMED] — exact prop names for selectable/draggable confirmed as standard ReactFlow node props.

**ReactFlow v12 confirmed behavior:** [VERIFIED: inspected node_modules/@xyflow/react/dist/esm/index.js]
- `hidden: true` → ReactFlow renders `null`, excludes from fitView/interaction, preserves in store
- `selectable: false` → overrides global `elementsSelectable` prop for that node
- `draggable: false` → overrides global `nodesDraggable` prop for that node
- All three coexist correctly with the Phase 65 `nodesDraggable={!interactiveLocked}` global prop

### Pattern 2: Layer Membership via `category` Field

```typescript
// Source: gui/src/registry/types.ts line ~213 [VERIFIED: read file]
type LayerKey = "Hydraulic" | "Thermal" | "Sources" | "ReactorPhysics";

// Category → LayerKey mapping:
const CATEGORY_TO_LAYER: Record<string, LayerKey> = {
  "Hydraulic": "Hydraulic",
  "Thermal": "Thermal",
  "Sources": "Sources",
  "Reactor Physics": "ReactorPhysics",
  // "Resources" (ReactivityController) — NOT a canvas component, category excluded
};

export function getComponentLayers(comp: ComponentDefinition): LayerKey[] {
  const key = CATEGORY_TO_LAYER[comp.category];
  return key ? [key] : [];
}

export function isNodeVisible(comp: ComponentDefinition, activeLayers: Record<LayerKey, boolean>): boolean {
  const layers = getComponentLayers(comp);
  if (layers.length === 0) return true; // no layer = always visible (Resources)
  return layers.some(key => activeLayers[key]);
}
```

Note: `ChannelAndContacts` has `category: "Hydraulic"` in the registry — it is NOT a dual-category entry. [VERIFIED: components.json] The dual-layer behavior for CAC's thermal ports is handled separately in StreamNode.tsx via port-type detection (`hasFlow && hasThermal`). D-02 dual-layer rule applies to components that belong to multiple layers, but in practice with category-based membership, only CAC has both FlowPort and ThermalPort — its node is visible when Hydraulic is on (category="Hydraulic"), and its thermal handles dim separately per D-03.

**Implication for D-02/D-03:** Since category-based membership gives CAC only `"Hydraulic"`, `isNodeVisible` returns `true` when Hydraulic is on. D-03 (off-layer port handle dimming) requires StreamNode.tsx to read `activeLayers` and dim ThermalPorts when Thermal is off, independent of node visibility. This dual-mechanism (node level = category, handle level = port type) matches the existing implementation pattern exactly.

### Pattern 3: `.scp` Layout Block Extension

The layout block in `projectIO.ts` currently holds:
- `active_left_tab` (string)
- `active_layer` (string — to be replaced/supplemented)
- `snap_to_grid` (boolean)

Phase 68 adds:
- `active_layers` (object: `{ Hydraulic: bool, Thermal: bool, Sources: bool, ReactorPhysics: bool }`)
- `hide_off_layer` (boolean)

Read-side compat shim (CONTEXT.md Claude's Discretion):
```typescript
// In deserializeProject, rawLayout handling:
const legacyLayer = rawLayout.active_layer as string | undefined;
const active_layers: Record<LayerKey, boolean> = rawLayout.active_layers
  ? rawLayout.active_layers as Record<LayerKey, boolean>
  : legacyLayer === "Hydraulic"
    ? { Hydraulic: true, Thermal: false, Sources: false, ReactorPhysics: false }
    : legacyLayer === "Thermal"
      ? { Hydraulic: false, Thermal: true, Sources: false, ReactorPhysics: false }
      : { Hydraulic: true, Thermal: true, Sources: true, ReactorPhysics: true }; // "Both" or missing
const hide_off_layer: boolean = (rawLayout.hide_off_layer as boolean) ?? false;
```

The `active_layer` key is no longer written on serialize. No migration script needed — the read-side shim covers existing saved files. [ASSUMED] — This is a minimal compat shim, NOT a full migrator, consistent with `feedback_no_back_compat_during_heavy_dev.md`.

### Pattern 4: Layer-Aware Connect

```typescript
// In CanvasPanel.tsx onConnect callback (extends existing addEdge call)
const onConnect = useCallback(
  (connection: Connection) => {
    addEdge(connection);
    // Auto-enable any off-layer involved in this connection
    const { nodes: currentNodes, activeLayers: currentLayers, setLayerVisible } = useStore.getState();
    const ids = [connection.source, connection.target].filter(Boolean);
    for (const nodeId of ids) {
      const node = currentNodes.find(n => n.id === nodeId);
      if (!node) continue;
      const comp = getComponent((node.data as unknown as StreamNodeData).componentId);
      if (!comp) continue;
      const layers = getComponentLayers(comp);
      for (const key of layers) {
        if (!currentLayers[key]) setLayerVisible(key, true);
      }
    }
  },
  [addEdge],
);
```

**ReactFlow `Connection` type confirmed fields:** `source: string`, `target: string`, `sourceHandle: string | null`, `targetHandle: string | null`. [VERIFIED: existing CanvasPanel.tsx usage at lines 184-200]

### Pattern 5: BottomPanel Stub Strip

Replace the early return `if (!bottomPanelOpen) return null` with a conditional render:

```typescript
// BottomPanel.tsx
if (!bottomPanelOpen) {
  return (
    <div
      className="h-5 border-t flex items-center justify-center gap-1 cursor-pointer bg-chrome hover:bg-accent transition-colors select-none"
      onClick={toggleBottomPanel}
      aria-label="Expand code panel"
      role="button"
    >
      <span className="text-[12px] font-normal text-muted-foreground">Code</span>
      <ChevronUp className="w-3 h-3 text-muted-foreground" />
    </div>
  );
}
```

The collapse button in the open state goes in the existing `<div className="mx-2 mt-1 flex items-center">` row (line ~82 in BottomPanel.tsx), after the `<TabsList>` and before the Copy/Export buttons (`ml-auto` div).

### Anti-Patterns to Avoid

- **Don't use event guards in `onNodeClick` for off-layer locking.** The existing `onNodeClick` guard (`if (dimmed) return`) was a workaround for missing per-node props. After setting `selectable: false`, ReactFlow itself prevents clicks — remove the guard.
- **Don't use `isComponentVisibleInLayer(comp, activeLayer)` in ToolboxPanel.** That function uses the old three-mode API. Rewrite ToolboxPanel to use `activeLayers[comp.category as LayerKey]` directly, or update `isNodeVisible` to handle the toolbox case. ToolboxPanel's existing `visibleSources` bypass (Sources always visible) should be reconsidered — with the new system, Sources is a real layer that can be toggled off; the toolbox should continue showing all draggable components regardless of layer state.
- **Don't set `pointerEvents: "none"` via CSS only.** ReactFlow's internal event handlers (drag, select) bypass CSS `pointer-events` in some cases. Use the `selectable: false` and `draggable: false` node props together with the CSS guard.
- **Don't animate hidden nodes.** The `hidden: true` transition is instantaneous (`display: none`). Do not add `transition` styles to hidden nodes.
- **Don't block connections cross-layer.** D-08: auto-enable, never block.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Popover with outside-click dismiss | Custom positioned div + document click listener | shadcn `<Popover>` (already installed) | Radix handles outside-click, keyboard dismiss (Esc), focus trap, accessibility |
| Checkbox with label association | Custom div+input | shadcn `<Checkbox>` (needs install) | Radix handles aria-checked, keyboard toggle, focus-visible |
| Per-mode Dim/Hide toggle | Custom radio group | shadcn `<Toggle>` (already installed) | Already used in codebase; pair of variant="outline" size="sm" |
| Node hidden-state management | Manual DOM show/hide | ReactFlow `hidden: true` prop | ReactFlow correctly excludes hidden nodes from fitView, connection targets, etc. |
| Shortcut key registration for Ctrl+` | Global document listener in component | `useEffect` in `App.tsx` (existing pattern) | Consistent with Ctrl+S, Ctrl+O, Ctrl+N — all registered in App.tsx handleKeyDown |

---

## Blast Radius: SecondaryToolbar Deletion

### Files that import or render SecondaryToolbar

| File | Change Required |
|------|----------------|
| `gui/src/App.tsx` (line 10, 397) | Remove import + JSX render |
| `gui/src/components/SecondaryToolbar.tsx` | **Delete entirely** |

**No other file imports SecondaryToolbar.** [VERIFIED: `grep -rn "SecondaryToolbar"` found only App.tsx and the component itself]

**CustomTitlebar.tsx does NOT render SecondaryToolbar.** CONTEXT.md's canonical_refs mention it, but the actual render site is `App.tsx` line 397 only. [VERIFIED: grep found nothing in CustomTitlebar.tsx]

### Items SecondaryToolbar currently owns (migration targets)

| Item | Current Location | Migration Target |
|------|-----------------|-----------------|
| Layer ToggleGroup (Hydraulic/Both/Thermal) | SecondaryToolbar | DELETED (replaced by LayersChip) |
| Code Preview toggle button | SecondaryToolbar + BottomPanel (Export button) | BottomPanel header (D-10) |
| Export button | SecondaryToolbar | FileMenu.tsx as "Export to Julia…" (D-09) |
| `handleExport()` function | SecondaryToolbar (calls `generateCode` + `exportCode`) | FileMenu.tsx (same implementation; `exportCode` util is in `gui/src/lib/exportCode.ts`) |

**Note:** BottomPanel.tsx already has its OWN Export button (line ~109) and `handleExport()`. The "Export" in SecondaryToolbar is a duplicate. After deletion, FileMenu.tsx gets the export and BottomPanel.tsx can keep or remove its own Export button — that's an independent choice. CONTEXT.md D-09 only mandates File menu placement, not removal from BottomPanel. Planner should decide whether to remove the BottomPanel Export button simultaneously.

### Tests against SecondaryToolbar

**None.** [VERIFIED: `grep -rn "SecondaryToolbar" gui/src --include="*.test.*"` returned no output]

### Keyboard shortcuts only in SecondaryToolbar

**None.** SecondaryToolbar has no `useEffect` or keyboard event listeners. The Tab → cycleLayer shortcut lives in **CanvasPanel.tsx** (lines 274-286), not SecondaryToolbar.

---

## Tab Key Shortcut Removal

**Current location:** `CanvasPanel.tsx` useEffect handleKeyDown (lines ~274-286):
```typescript
if (e.key === "Tab") {
  // ... input-focus guard ...
  e.preventDefault();
  useStore.getState().cycleLayer();
}
```

**After removal:** Delete the entire `if (e.key === "Tab")` block. The `e.preventDefault()` call was preventing browser-native Tab focus rotation. After removal, Tab navigates normally through focusable elements.

**No other Tab bindings exist** in the codebase for layer cycling. [VERIFIED: `grep -rn "cycleLayer\|Tab.*layer"` — only found in CanvasPanel.tsx and useStore.ts]

**Tab is safe to free:** ReactFlow's canvas already handles Tab for node focus navigation. The CanvasPanel.tsx handler already guards against Tab when text inputs have focus — the removal is clean.

---

## View Menu State

**Current ViewMenu.tsx state:** After Phase 67 UAT round 2 (#6 and #7), the View menu already has ONLY the Theme submenu. The "Toggle Code Preview" and "Layer" entries were removed in the round-2 trim. [VERIFIED: read ViewMenu.tsx — lines 27-31 document this]

**Implication for Phase 68 D-07:** The "Layer" radio submenu is ALREADY GONE. Phase 68 does not need to remove it — but D-07 says "remove View menu 'Layer' radio submenu (corrects Phase 67 D-11)." This is a no-op on the ViewMenu itself.

**What Phase 68 DOES add to ViewMenu:** D-10 says "View menu 'Toggle Code Preview' entry stays as the keyboard-shortcut path." The UI-SPEC shows the resulting View menu structure including "Toggle Code Preview Ctrl+`". This entry is NOT currently in ViewMenu.tsx — it was removed in Phase 67 UAT. Phase 68 must ADD IT BACK.

**Summary:**
- View menu currently: Theme submenu only
- Phase 68 target: Toggle Code Preview (Ctrl+`) + Theme submenu
- Action: Add `<MenubarItem>` for "Toggle Code Preview" with keyboard shortcut hint + wire `toggleBottomPanel()`

**Ctrl+` keyboard shortcut:** Currently NOT registered anywhere. Phase 68 must add a `useEffect` in `App.tsx` (following the existing Ctrl+S/Ctrl+N/Ctrl+O pattern) to bind `e.key === "\`"` + `e.ctrlKey` → `toggleBottomPanel()`. [VERIFIED: exhaustive grep found no Ctrl+` binding]

---

## Layer Membership Findings: Category Verification

All components' categories confirmed from `components.json`: [VERIFIED: `python3` script reading components.json]

| Component | Category | Layer |
|-----------|---------|-------|
| Channel, ChannelAndContacts, ChannelHeatFlux, Pump, Flapper, Friction, Gravity, Resistor, Inertia, HeatExchanger | `"Hydraulic"` | Hydraulic |
| ConstantTemperature, HeatDiffusion | `"Thermal"` | Thermal |
| WallTemperature, HeatFluxSource | `"Sources"` | Sources |
| PointKinetics | `"Reactor Physics"` | Reactor Physics |
| ReactivityController | `"Resources"` | (not a canvas layer — no canvas nodes) |

**Key finding:** `ConstantTemperature` is `"Thermal"`, NOT `"Sources"`. This matches the design-decisions doc §3.13 ("ConstantTemperature lives in Thermal because it has a real ThermalPort (port-based), not in Sources"). The layer taxonomy in the registry is already correct.

**Reactor Physics layer:** `PointKinetics` exists with `category: "Reactor Physics"`. Phase 68 builds the layer infrastructure; PK GUI integration is deferred. The chip and checkbox UI for Reactor Physics still renders — it just has no visible nodes to affect in current projects.

**"Resources" category → no layer:** `ReactivityController` has `category: "Resources"`. This is NOT a canvas component (it's a non-draggable resource). The `CATEGORY_TO_LAYER` map should NOT include `"Resources"` — `getComponentLayers()` returns `[]` for Resources components, making them always-visible (consistent with current behavior where they don't appear on canvas at all).

---

## ToolboxPanel Layer Filtering Impact

ToolboxPanel currently calls `isComponentVisibleInLayer(comp, activeLayer)` (the old three-mode function) to filter visible Hydraulic and Thermal components. [VERIFIED: read ToolboxPanel.tsx]

After the layers.ts rewrite, `isComponentVisibleInLayer` is deleted (replaced by `isNodeVisible`). ToolboxPanel must be updated.

**Decision needed by planner:** Should the Toolbox filter by layer (hide Hydraulic components from toolbox when Hydraulic layer is off)? OR should the Toolbox always show all components regardless of layer state?

Current behavior: Toolbox hides Hydraulic components in "Thermal" mode and vice versa. This was a side effect of the old three-mode system. With independent checkboxes, filtering the toolbox by `activeLayers` would hide Hydraulic components when the Hydraulic checkbox is unchecked — which may confuse users who want to add a Hydraulic component while reviewing a Thermal-only view.

**Recommendation (Claude's discretion):** Remove layer filtering from ToolboxPanel entirely. The toolbox shows all available components always. The canvas layer filter is the primary decluttering mechanism; the toolbox should remain a stable drag palette. This simplifies ToolboxPanel and avoids the "where did my Pump go?" confusion.

---

## Common Pitfalls

### Pitfall 1: `selectable: false` Does Not Prevent `onNodeClick` Guard
**What goes wrong:** After setting `selectable: false`, the existing `onNodeClick` handler has an explicit `if (dimmed) return` guard using the old `isNodeDimmed` function. That guard will be stale / referencing deleted API.
**Why it happens:** Two-path protection was originally needed because per-node `selectable` was not set.
**How to avoid:** Delete the `onNodeClick` dimming guard entirely. With `selectable: false` on the enriched node, ReactFlow does not fire `onNodeClick` for non-selectable nodes. [VERIFIED: ReactFlow source — `isSelectable` gates the click handler]
**Warning signs:** If off-layer nodes can still be selected after the refactor, the guard removal was correct but the `selectable` prop enrichment failed.

### Pitfall 2: Store Serialize/Deserialize Call Sites Miss New Fields
**What goes wrong:** `useStore.ts` has multiple places that call `serializeProject(...)`: `saveProject` (~line 2161) and `saveProjectAs` (~line 2227). Both currently pass `activeLayer: state.activeLayer`. After the refactor, these must pass `activeLayers: state.activeLayers, hideOffLayer: state.hideOffLayer` instead.
**Why it happens:** Two serialization call sites. Easy to update one and miss the other.
**How to avoid:** Grep for `activeLayer:` in useStore.ts and update all occurrences (2 found). Also update `newProject` reset (~line 2453) and `loadProject` deserialization (~line 2373).
**Warning signs:** Save/load round-trip test fails with stale `active_layer` string.

### Pitfall 3: projectIO.ts Tests Hardcode `activeLayer` in Fixtures
**What goes wrong:** `projectIO.snapToGrid.test.ts` (line 61) and `saveAndOpenErrors.test.ts` (line 74) pass `activeLayer: "Both"` to `serializeProject`. After removing `activeLayer` from `SerializeProjectArgs`, these tests break.
**Why it happens:** Test fixtures mirror the old API.
**How to avoid:** Update test fixtures to use `activeLayers: { Hydraulic: true, Thermal: true, Sources: true, ReactorPhysics: true }, hideOffLayer: false`.
**Warning signs:** TypeScript compilation fails on test files.

### Pitfall 4: `useStore.test.ts` Directly Tests Deleted Actions
**What goes wrong:** `useStore.test.ts` has `describe("activeLayer")` (line 308) testing `setActiveLayer`, `cycleLayer`, and their effects. These tests break after deletion.
**Why it happens:** Tests were written for the three-mode API.
**How to avoid:** Replace the `activeLayer` describe block with a new describe block testing `activeLayers`, `toggleLayer`, `setLayerVisible`, `setAllLayersVisible`, and `hideOffLayer` behaviors.
**Warning signs:** Vitest reports 6+ failures from useStore.test.ts.

### Pitfall 5: ReactFlow `hidden: true` and Edge Visibility
**What goes wrong:** An edge connecting two `hidden: true` nodes still renders if the edge itself does not have `hidden: true`.
**Why it happens:** ReactFlow treats node and edge visibility independently.
**How to avoid:** In `enrichedEdges`, set `hidden: true` on edges whose BOTH endpoints are hidden (or if the edge's own layer is off in hide mode). The edge enrichment pass already exists for opacity dimming — extend it.
**Warning signs:** Phantom edge lines visible on canvas when all nodes of a layer are hidden.

### Pitfall 6: ToolboxPanel Import of `isComponentVisibleInLayer`
**What goes wrong:** ToolboxPanel.tsx imports `isComponentVisibleInLayer` from `../lib/layers`. After the layers.ts rewrite deletes this function, ToolboxPanel.tsx fails to compile.
**Why it happens:** Deleted export, live import.
**How to avoid:** Update ToolboxPanel.tsx as part of the wave that rewrites layers.ts — remove the import and the filtering logic together.
**Warning signs:** TypeScript compilation error: `Module '"../lib/layers"' has no exported member 'isComponentVisibleInLayer'`.

### Pitfall 7: StreamNode.tsx LayerView Import Fails
**What goes wrong:** StreamNode.tsx (line 15) imports `type LayerView from "../lib/layers"` and uses it as the `activeLayer` store selector type. After deleting `LayerView` from layers.ts, StreamNode.tsx fails to compile.
**Why it happens:** Deleted type, live import.
**How to avoid:** Update StreamNode.tsx to import `LayerKey, ActiveLayers` (or whatever new types are exported) and rewrite the handle-dimming logic (`dimFlowHandles`, `dimThermalHandles`) to use `activeLayers.Thermal === false` / `activeLayers.Hydraulic === false` instead of `activeLayer === "Thermal"` / `activeLayer === "Hydraulic"`.
**Warning signs:** TypeScript error on `import type { LayerView }`.

### Pitfall 8: Popover `side="left"` Overflow on Narrow Canvas
**What goes wrong:** The Layers chip is in the top-right overlay. `PopoverContent side="left"` opens to the left of the chip. If the canvas is very narrow (e.g., right panel is wide), the popover may clip against the left edge.
**Why it happens:** Radix Floating UI by default tries to fit within viewport but the 208px popover needs 208px of horizontal space to the left of the chip.
**How to avoid:** Radix Popover automatically flips side if there is not enough space — this is handled by `avoidCollisions={true}` (Radix default). No explicit guard needed.
**Warning signs:** Popover renders off-screen in narrow windows.

---

## Code Examples

### layers.ts New API Skeleton (to be written from scratch)
```typescript
// Source: derived from CONTEXT.md Claude's Discretion + registry/types.ts category values [VERIFIED]
export type LayerKey = "Hydraulic" | "Thermal" | "Sources" | "ReactorPhysics";
export type ActiveLayers = Record<LayerKey, boolean>;

export const ALL_LAYERS_ON: ActiveLayers = {
  Hydraulic: true,
  Thermal: true,
  Sources: true,
  ReactorPhysics: true,
};

// Category string from registry → LayerKey (NOTE: "Reactor Physics" has a space)
const CATEGORY_TO_LAYER_KEY: Partial<Record<string, LayerKey>> = {
  "Hydraulic": "Hydraulic",
  "Thermal": "Thermal",
  "Sources": "Sources",
  "Reactor Physics": "ReactorPhysics",
  // "Resources" intentionally omitted — not a canvas layer
};

export function getComponentLayers(comp: ComponentDefinition): LayerKey[] {
  const key = CATEGORY_TO_LAYER_KEY[comp.category];
  return key ? [key] : [];
}

export function isNodeVisible(comp: ComponentDefinition, activeLayers: ActiveLayers): boolean {
  const layers = getComponentLayers(comp);
  if (layers.length === 0) return true;
  return layers.some(key => activeLayers[key]);
}

export function isEdgeDimmed(edgeLayerKey: LayerKey | null, activeLayers: ActiveLayers): boolean {
  if (!edgeLayerKey) return false;
  return !activeLayers[edgeLayerKey];
}
```

### LayersChip Color Squares Pattern
```typescript
// Source: UI-SPEC §"Layers Chip anatomy" + CONTEXT.md D-01 color values [VERIFIED]
const LAYER_COLORS: Record<LayerKey, string> = {
  Hydraulic: "#3b82f6",   // blue-500
  Thermal: "#f59e0b",     // amber-500
  Sources: "#8b5cf6",     // violet-500
  ReactorPhysics: "#f43f5e", // rose-500
};

const LAYER_KEYS: LayerKey[] = ["Hydraulic", "Thermal", "Sources", "ReactorPhysics"];

// In LayersChip render:
{LAYER_KEYS.map(key => (
  <span
    key={key}
    aria-hidden="true"
    className="w-3 h-3 rounded-[2px] inline-block transition-opacity duration-150"
    style={{
      backgroundColor: LAYER_COLORS[key],
      opacity: activeLayers[key] ? 1.0 : 0.35,
    }}
  />
))}
```

---

## Runtime State Inventory

SKIPPED — this is a greenfield feature phase (new component, API rewrites), not a rename/refactor/migration. The `.scp` format migration is additive (new fields) with a read-side compat shim, not a data migration.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Node.js / npm | `npx shadcn add checkbox` | ✓ | (existing) | — |
| shadcn CLI | checkbox install | ✓ | (npx invocation) | — |
| @xyflow/react | canvas layer enrichment | ✓ | ^12.10.2 | — |

**Missing dependencies with no fallback:** none

---

## Validation Architecture

SKIPPED — `workflow.nyquist_validation: false` in `.planning/config.json`.

---

## Security Domain

This phase has no authentication, data I/O, cryptography, or access control concerns. All changes are local UI state management and local file serialization. `security_enforcement` is not relevant.

---

## Sources

### Primary (HIGH confidence)
- `gui/src/lib/layers.ts` — current API (being replaced); read in full
- `gui/src/store/useStore.ts` — activeLayer/cycleLayer/setActiveLayer state + actions at lines 213-215, 828, 1031-1038; serialize call sites at lines 2161, 2227, 2373, 2453
- `gui/src/lib/projectIO.ts` — layout block schema (lines 58-63, 82-84, 141-148, 195-203)
- `gui/src/registry/types.ts` — ComponentDefinition.category type + values (line ~213)
- `gui/src/registry/components.json` — all 16 components' categories (verified via Python script)
- `gui/src/components/CanvasPanel.tsx` — enrichment pass (lines 96-131), Tab shortcut (lines 274-286), onConnect (lines 161-166), overlay stack (line 360)
- `gui/src/components/SecondaryToolbar.tsx` — full file; render site in App.tsx lines 10, 397
- `gui/src/components/BottomPanel.tsx` — current structure (early return line 72, drag handle + tabs lines 75-124)
- `gui/src/components/ViewMenu.tsx` — current state (Theme only; Toggle Code Preview and Layer removed in Phase 67 UAT)
- `gui/src/components/FileMenu.tsx` — current menu items + pattern for adding new item
- `gui/src/components/StreamNode.tsx` — dual-layer handle dim logic (lines 334, 346-349)
- `gui/src/components/ToolboxPanel.tsx` — isComponentVisibleInLayer usage (lines 25-29)
- `gui/src/components/ui/` listing — confirmed checkbox NOT present, toggle + popover present
- `gui/src/components/canvasMenus/SnapToGridButton.tsx` — overlay button pattern
- `gui/node_modules/@xyflow/react/dist/esm/index.js` — ReactFlow v12: hidden (line 2135), selectable (line 2119), draggable (line 2118) per-node behavior
- `.planning/phases/68-layers-system-overhaul/68-CONTEXT.md` — 10 locked decisions
- `.planning/phases/68-layers-system-overhaul/68-UI-SPEC.md` — visual contract

### Secondary (MEDIUM confidence)
- `gui/src/lib/__tests__/layers.test.ts` — existing test structure (rewrite guidance)
- `gui/src/store/__tests__/useStore.test.ts` — activeLayer test block (to be replaced)
- `gui/src/lib/__tests__/projectIO.snapToGrid.test.ts` — fixture pattern for layout fields
- `gui/src/store/__tests__/saveAndOpenErrors.test.ts` — activeLayer fixture usage
- `gui/src/App.tsx` — keyboard shortcut registration pattern (Ctrl+S/N/O/1/2/3)
- `.planning/notes/gui-redesign-design-decisions.md` §3.13 — Layers System design rationale
- `.planning/STATE.md` — branch: gui-redesign; current position: Phase 67 complete

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all existing dependencies, one confirmed-missing shadcn component
- Architecture: HIGH — existing enrichment pass pattern is directly extensible; ReactFlow API confirmed
- Pitfalls: HIGH — identified by reading all affected files; all confirmed from source
- Layer membership taxonomy: HIGH — confirmed from components.json directly

**Research date:** 2026-05-16
**Valid until:** 2026-06-15 (stable stack; @xyflow/react minor versions stable within ^12)

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `selectable: false` on a ReactFlow v12 node prevents `onNodeClick` from firing for that node | Pitfall 1, Pattern 1 | If ReactFlow still fires onNodeClick for selectable:false nodes, the old guard cannot be removed; must keep a check |
| A2 | ToolboxPanel should NOT filter by activeLayers (always show all components) | ToolboxPanel Impact section | If user expects toolbox to hide Hydraulic components when Hydraulic is off, this is a UX regression |
| A3 | The BottomPanel Export button stays (not removed as part of Phase 68) | Blast Radius section | If planner decides to remove it simultaneously, D-09 scope needs clarification |
| A4 | `active_layer` key is NOT written on serialize (new files write `active_layers` only) | Pattern 3 | If old code paths persist that write `active_layer`, deserialization may pick the stale value |

**If this table is empty:** It is not — 4 assumptions flagged for planner attention.

---

## Open Questions (RESOLVED)

1. **ToolboxPanel layer filtering behavior** — **RESOLVED (D-11):** Show all components always; remove `isComponentVisibleInLayer` filtering. Layer management is a canvas concern, not a toolbox concern. Encoded in Plan 68-03 Task 3.

2. **BottomPanel Export button (duplicate)** — **RESOLVED (D-12):** Leave the BottomPanel Export button in place. Phase 68 ADDS a File-menu "Export to Julia…" entry; both call the same `exportCode` util. Two entry points by design (discoverable + fast-export). Encoded in Plan 68-05.

3. **Ctrl+` keyboard shortcut — registration location** — **RESOLVED (D-13):** Register in `App.tsx` following the existing `handleLeftTabKey` pattern. App.tsx is the keyboard shortcut hub; BottomPanel does not own global shortcuts. Encoded in Plan 68-05.
