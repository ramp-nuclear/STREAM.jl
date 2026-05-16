---
phase: 68-layers-system-overhaul
reviewed: 2026-05-16T00:00:00Z
depth: standard
files_reviewed: 20
files_reviewed_list:
  - gui/src/App.tsx
  - gui/src/components/BottomPanel.tsx
  - gui/src/components/CanvasPanel.tsx
  - gui/src/components/FileMenu.tsx
  - gui/src/components/LayersChip.tsx
  - gui/src/components/StreamNode.tsx
  - gui/src/components/ToolboxPanel.tsx
  - gui/src/components/ViewMenu.tsx
  - gui/src/components/__tests__/LayersChip.test.tsx
  - gui/src/components/__tests__/ToolboxPanel.test.tsx
  - gui/src/components/ui/checkbox.tsx
  - gui/src/lib/__tests__/layers.test.ts
  - gui/src/lib/__tests__/projectIO.snapToGrid.test.ts
  - gui/src/lib/layers.ts
  - gui/src/lib/projectIO.ts
  - gui/src/store/__tests__/saveAndOpenErrors.test.ts
  - gui/src/store/__tests__/useStore.codePanel.test.ts
  - gui/src/store/__tests__/useStore.test.ts
  - gui/src/store/useStore.ts
findings:
  critical: 0
  warning: 4
  info: 4
  total: 8
status: issues_found
---

# Phase 68: Code Review Report

**Reviewed:** 2026-05-16T00:00:00Z
**Depth:** standard
**Files Reviewed:** 20
**Status:** issues_found

## Summary

The Phase 68 layers-system overhaul is structurally clean: pure `layers.ts` helpers are well-typed and well-tested; the .scp v2.0 schema migration (`active_layer` → `active_layers` + `hide_off_layer`) includes a one-shot legacy shim with a comprehensive round-trip test matrix; the LayersChip component is a faithful implementation of the locked UI spec. No security or data-loss defects.

The adversarial pass surfaced four warnings concentrated in two areas:
1. **Re-render fanout in `StreamNode`** — the per-node `activeLayers` selector returns the whole object, defeating zustand shallow equality and re-rendering every node on any layer toggle (the file explicitly documents Pitfall 1 elsewhere and breaks its own rule here).
2. **Edge-layer classification fragility in `CanvasPanel`** — `else → "Thermal"` swallows any edge whose `type` is not exactly `"hydraulicEdge"` or `"bcEdge"`, including stray `"smoothstep"` defaults from `defaultEdgeOptions` and unrecognized future edge types, silently dimming/hiding them on Thermal toggle.

Two minor a11y issues (BottomPanel keyboard-inaccessible expand strip, redundant snap-to-grid default) round out the warnings. Info-tier findings cover undo-stack semantics for layer state, unvalidated deserialization input, and a redundant fallback.

## Warnings

### WR-01: `StreamNode.tsx` selects the whole `activeLayers` object — re-renders every node on any layer toggle

**File:** `gui/src/components/StreamNode.tsx:355-360`
**Issue:** The header comments and sibling selectors in this file (`hasAnchor`, `hasBCError`, `isCodeHovered`, `isCodePinned`) document Pitfall 1: "return a primitive boolean, never a fresh object/array, so zustand's shallow equality keeps re-renders bounded." This component then breaks that rule:

```tsx
const activeLayers = useStore(
  useCallback((s: { activeLayers: ActiveLayers }) => s.activeLayers, []),
);
```

`toggleLayer` / `setLayerVisible` / `setAllLayersVisible` all replace `state.activeLayers` with a fresh object reference. Zustand's default equality is `Object.is`, so the selector treats every layer mutation as a change and re-renders **every** mounted `StreamNode` — including single-Hydraulic nodes when only `ReactorPhysics` flips. With ~N nodes on the canvas this is O(N) re-renders per layer click, exactly the fanout the rest of the file works to avoid.

**Fix:** Replace the object selector with the two primitive booleans the component actually consumes:

```tsx
const isDualLayer = component &&
  getComponentLayers(component).includes("Hydraulic") &&
  getComponentLayers(component).includes("Thermal");

const hydraulicActive = useStore((s) => s.activeLayers.Hydraulic);
const thermalActive = useStore((s) => s.activeLayers.Thermal);
const hideOffLayer = useStore((s) => s.hideOffLayer);

const flowOff = isDualLayer && hydraulicActive === false;
const thermalOff = isDualLayer && thermalActive === false;
```

Only nodes whose layer state actually changed will re-render.

---

### WR-02: `CanvasPanel.tsx` edge-layer classifier silently buckets unknown edge types as "Thermal"

**File:** `gui/src/components/CanvasPanel.tsx:144-149`
**Issue:** The edge enrichment derives layer membership from `edge.type` with a catch-all `else` branch:

```tsx
let edgeLayerKey: LayerKey | null;
if (edge.type === "hydraulicEdge") edgeLayerKey = "Hydraulic";
else if (edge.type === "bcEdge") edgeLayerKey = "Sources";
else edgeLayerKey = "Thermal";
```

Two problems:

1. **`defaultEdgeOptions = { type: "smoothstep" }`** (line 65) is applied by ReactFlow at render-time. If `enrichEdges` ever returns an edge that doesn't match the ThermalPort early-return path nor the BCPort/hydraulic explicit-type assignments (e.g. an edge whose source node isn't in `nodes` — see `enrichEdges` lines 766-768 returning `e` unchanged), the residual edge can carry `type: "smoothstep"` and be misclassified as "Thermal", silently dimming/hiding on the Thermal toggle.
2. **No assertion / never-default** — any future edge type added to the codebase will land in the Thermal bucket by accident. There is no compile-time exhaustiveness check.

**Fix:** Make the classifier explicit and fail-loud for unknowns:

```tsx
let edgeLayerKey: LayerKey | null;
if (edge.type === "hydraulicEdge") edgeLayerKey = "Hydraulic";
else if (edge.type === "bcEdge") edgeLayerKey = "Sources";
else if (edge.type === undefined || edge.type === "smoothstep") {
  // Thermal edges intentionally have no custom type (enrichEdges strips it)
  edgeLayerKey = "Thermal";
} else {
  // Unknown future edge type — opt out of layer dimming rather than guess
  edgeLayerKey = null;
  if (import.meta.env.DEV) {
    console.warn(`[CanvasPanel] unknown edge.type=${edge.type}, not classified for layer dim/hide`);
  }
}
```

This makes the contract visible and avoids silent misclassification of stray edge types.

---

### WR-03: BottomPanel collapsed stub is `role="button"` on a `<div>` but is not keyboard-operable

**File:** `gui/src/components/BottomPanel.tsx:80-94`
**Issue:** The collapsed-state stub strip:

```tsx
<div
  className="h-5 ... cursor-pointer ..."
  onClick={toggleBottomPanel}
  role="button"
  aria-label="Expand code panel"
>
```

Claims the button role but lacks `tabIndex` and any keyboard handler. Screen-reader and keyboard-only users cannot expand the code panel from this affordance — only mouse users can. The View menu and Ctrl+\` shortcut remain available, but the stub itself is the on-screen affordance most users will see, and a `role="button"` without keyboard wiring is a WCAG 2.1 SC 2.1.1 (Keyboard) failure.

**Fix:** Use a real `<button>` element (which inherits keyboard semantics automatically) and keep the visual styling:

```tsx
<button
  type="button"
  className="h-5 w-full border-t flex items-center justify-center gap-1 cursor-pointer bg-chrome hover:bg-accent transition-colors select-none"
  onClick={toggleBottomPanel}
  aria-label="Expand code panel"
>
  <span className="text-[12px] font-normal text-muted-foreground">Code</span>
  <ChevronUp className="w-3 h-3 text-muted-foreground" />
</button>
```

This eliminates the `role="button"` workaround and gives Enter/Space activation for free.

---

### WR-04: `CanvasPanel.onConnect` auto-enables layers but the change is not reversible by Ctrl+Z

**File:** `gui/src/components/CanvasPanel.tsx:198-223` (with `gui/src/store/useStore.ts:925-951`)
**Issue:** The D-04 "forgiving rule" auto-enables any off-layer associated with a freshly connected endpoint:

```tsx
for (const key of getComponentLayers(comp)) {
  if (!currentActive[key]) setLayerVisible(key, true);
}
```

`setLayerVisible` does **not** push an undo snapshot, and `_pushSnapshot` (`useStore.ts:925-951`) deliberately omits `activeLayers` / `hideOffLayer` from the captured slice. After the user drags a connection that flips a layer ON, pressing Ctrl+Z reverses the edge add but leaves the layer ON — a state the user never explicitly requested. This silently couples two pieces of state in one direction only (drag-connect turns layer on; undo doesn't turn it back off).

The inherited comment at `useStore.ts:145` ("activeLayer is NOT undoable") was written when the layer was a user-explicit three-mode toggle. With auto-enable-on-connect added in Phase 68, that assumption no longer holds — a layer can now change as a side effect of a node operation, so it should participate in that operation's undo unit.

**Fix:** Either include `activeLayers` + `hideOffLayer` in `_pushSnapshot` (and `undo` / `redo` restoration), or have `addEdge` defer the auto-enable into its own pre-snapshot path so the snapshot captures pre-change layer state. Preferred (smaller blast radius):

```ts
// In _pushSnapshot:
const { nodes, edges, anchors, resources, modelOptions, bcMode, bcSymmetric,
        activeLayers, hideOffLayer, _undoPast } = get();
set({
  _undoPast: [
    ..._undoPast,
    { nodes, edges, anchors, resources, modelOptions, bcMode, bcSymmetric,
      activeLayers, hideOffLayer },
  ].slice(-50),
  _undoFuture: [],
});
// Mirror in undo() and redo() restore paths.
```

If the design intent really is "layer changes are never undoable," then the auto-enable in `onConnect` should be removed instead — but that contradicts D-04.

## Info

### IN-01: `deserializeProject` does not validate `active_layers` value types

**File:** `gui/src/lib/projectIO.ts:223-247`
**Issue:** The legacy shim accepts any partial record and spreads it onto `ALL_LAYERS_ON`:

```ts
const rawActiveLayers = rawLayout.active_layers as
  | Partial<Record<LayerKey, boolean>>
  | undefined;
// ...
active_layers = { ...ALL_LAYERS_ON, ...rawActiveLayers };
```

A malformed `.scp` file with `active_layers: { Hydraulic: "no", FakeKey: true }` would produce `active_layers.Hydraulic === "no"` (truthy string) and leak `FakeKey` into the object. Downstream `activeLayers[key]` comparisons would behave unexpectedly. Per CLAUDE.md "no back-compat during heavy dev" this is acceptable for now, but a strict validator (only the four `LayerKey`s, only boolean values) would be cheap insurance and bring this in line with the rest of the file's tone (e.g. `format_version` is strictly checked).

**Fix:** Normalize through `LAYER_KEYS`:

```ts
import { LAYER_KEYS } from "./layers";
// ...
if (rawActiveLayers && typeof rawActiveLayers === "object") {
  active_layers = { ...ALL_LAYERS_ON };
  for (const k of LAYER_KEYS) {
    const v = (rawActiveLayers as Record<string, unknown>)[k];
    if (typeof v === "boolean") active_layers[k] = v;
  }
} // ... rest of branches unchanged
```

---

### IN-02: `loadProjectFromPath` has a redundant `?? false` for snap-to-grid

**File:** `gui/src/store/useStore.ts:2407` and `gui/src/store/useStore.ts:2685`
**Issue:** `deserializeProject` already coerces `snap_to_grid` to a boolean with `?? false` (`projectIO.ts:257`), so:

```ts
snapToGrid: project.layout.snap_to_grid ?? false,
```

is a no-op fallback. Cosmetic, but it suggests the author was unsure of the contract; either remove the redundant `??` here or remove the default in `deserializeProject`. Pick one site to own the default.

**Fix:** Drop `?? false` at both call sites (`useStore.ts:2407` and `useStore.ts:2685`) since `project.layout.snap_to_grid` is already typed `boolean` (not `boolean | undefined`) by `StreamProject`.

---

### IN-03: `LayersChip` Dim/Hide toggle pair ignores the `pressed` value Radix supplies

**File:** `gui/src/components/LayersChip.tsx:135-149`
**Issue:** Both `Toggle`s receive `onPressedChange={() => setHideOffLayer(false)}` (or `true`) with no argument from the callback. Clicking the already-pressed toggle still calls `setHideOffLayer` with the same value (idempotent — harmless). The pattern works but reads as a radio-button group implemented with two single-state toggles. If a future contributor expects standard `Toggle` semantics (where clicking a pressed toggle un-presses it), they will be surprised that pressing Dim twice does **not** clear `hideOffLayer` to some neutral third state. Consider using a `ToggleGroup type="single"` or a single two-state switch labelled "Hide off-layer nodes" to make the radio semantic explicit.

**Fix:** Optional refactor to `ToggleGroup`:

```tsx
<ToggleGroup
  type="single"
  value={hideOffLayer ? "hide" : "dim"}
  onValueChange={(v) => {
    if (v) setHideOffLayer(v === "hide");
  }}
>
  <ToggleGroupItem value="dim">Dim</ToggleGroupItem>
  <ToggleGroupItem value="hide">Hide</ToggleGroupItem>
</ToggleGroup>
```

This also avoids the empty-value case where the user un-presses the active toggle (current code prevents that by always calling the setter; `ToggleGroup` does too, via the `if (v)` guard).

---

### IN-04: `LayersChip.tsx` re-declares `LAYER_COLORS` already present in `StreamNode.tsx`

**File:** `gui/src/components/LayersChip.tsx:26-31` and `gui/src/components/StreamNode.tsx:26-29`
**Issue:** Two files independently encode the LayerKey→hex mapping:
- `LayersChip.tsx`: `Hydraulic: "#3b82f6"`, `Thermal: "#f59e0b"`, `Sources: "#8b5cf6"`, `ReactorPhysics: "#f43f5e"`
- `StreamNode.tsx` `CATEGORY_LEFT_BORDER_COLOR`: `Hydraulic: "#3b82f6"`, `Thermal: "#f59e0b"` (only two of four — Sources and ReactorPhysics absent because they don't yet drive a left-border accent).

The phase doc calls D-01 the palette "locked" — but if it's later relaxed, two files need editing in lockstep. Promote the palette to `gui/src/lib/layers.ts` (next to `LAYER_KEYS`) so both consumers import a single source of truth.

**Fix:** Add to `gui/src/lib/layers.ts`:

```ts
export const LAYER_HEX: Record<LayerKey, string> = {
  Hydraulic: "#3b82f6",
  Thermal: "#f59e0b",
  Sources: "#8b5cf6",
  ReactorPhysics: "#f43f5e",
};
```

Then import in both components. `StreamNode.tsx`'s `CATEGORY_LEFT_BORDER_COLOR` becomes a derived two-key subset.

---

_Reviewed: 2026-05-16T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
