# Phase 68: Layers system overhaul - Context

**Gathered:** 2026-05-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Replace the v0.8 three-mode layer toggle (Hydraulic / Both / Thermal) with a four-layer independent-checkbox system. Deliver: a floating Layers chip pinned top-right of the canvas, per-project hide-vs-dim preference, full non-interactive locking of off-layer items, and a forgiving layer-aware connect tool that auto-enables layers rather than blocking.

As a side effect of removing the layer toggle from the SecondaryToolbar, this phase **deletes the SecondaryToolbar entirely** and migrates its two remaining controls: Export → File menu, Code Preview toggle → bottom panel header.

**In scope:**
- Four-layer taxonomy: Hydraulic, Thermal, Sources, Reactor Physics — independent boolean toggles
- Floating "Layers" chip top-right of canvas — click to expand popover with 4 checkboxes + hide/dim toggle
- Four color-square layer-state indicator on the chip (always visible)
- Off-layer items: dimmed (opacity 0.2) or hidden, fully non-interactive (not selectable, not draggable, not connectable)
- Hide-vs-dim setting: per-project, persisted in `.scp` `layout` block
- Layer-aware connect: auto-enable the relevant layer when user completes a cross-layer connection
- Delete `SecondaryToolbar.tsx` — the strip that held Layer toggle + Code toggle + Export
- Move Export button to File menu as "File → Export…"
- Bottom panel collapse/expand button in its own header + persistent thin stub strip when closed
- Remove View menu "Layer" radio submenu (corrects Phase 67 D-11)
- Remove `cycleLayer()` store action + Tab shortcut binding

**Out of scope:**
- New accent colors in the design system beyond the layer indicator squares (Phase 72)
- Settings dialog UI shell (Phase 72 — the hide/dim toggle lives in the popover for now)
- Reactor Physics layer components (PointKinetics/ReactivityController) — layer infrastructure is built but PK GUI integration deferred
- Per-component rotation as fallback (Section 6 parked)

</domain>

<decisions>
## Implementation Decisions

### Layer accent palette

- **D-01:** Four color squares on the Layers chip use these accents:
  - **Hydraulic** → Blue (existing, unchanged)
  - **Thermal** → Amber (existing, unchanged)
  - **Sources / BCs** → Purple/violet (new; Claude's choice — most distinct from Blue and Amber, signals the unique v1.1 value-source concept)
  - **Reactor Physics** → Red/rose (new; Claude's choice — strong nuclear connotation, distinct from all three others)
  
  These accents apply to the chip indicator squares and to any layer-specific UI chrome (e.g., popover checkbox labels). Full design-system integration of these accents (into port handles, node borders, etc.) is Phase 72's job; Phase 68 uses them only on the Layers chip.

### Dual-layer visibility rule

- **D-02:** A component that belongs to multiple layers (e.g. `ChannelAndContacts` = Hydraulic + Thermal) is **visible if ANY of its layers is active**. It dims or hides only when ALL of its layers are unchecked simultaneously.
- **D-03:** When a dual-layer component is visible but one of its layers is off, its **off-layer port handles dim to opacity 0.2 and are locked non-interactive**. Its active-layer port handles remain fully interactive. Example: CAC with Hydraulic ON / Thermal OFF → CAC node fully visible, FlowPort handles interactive, ThermalPort handles dimmed + locked.
- **D-04:** **Edges follow their own layer**, not the node. A thermal edge between two visible CAC nodes still dims when Thermal is off, because the edge belongs to the Thermal layer regardless of whether its endpoints are visible.

### Shortcut and menu cleanup

- **D-05:** `cycleLayer()` store action is **removed**. The old `LayerView = "Hydraulic" | "Both" | "Thermal"` type is deleted and replaced with the new independent-toggle state shape.
- **D-06:** The **Tab key shortcut** in `CanvasPanel.tsx` that called `cycleLayer()` is **removed**. No replacement — the Layers chip is always visible on the canvas.
- **D-07:** The **View menu "Layer" radio submenu** introduced in Phase 67 (D-11) is **removed**. The floating chip is the sole layer UI. The View menu retains only "Toggle Code Preview" and the Theme submenu.

### SecondaryToolbar removal

- **D-08:** `SecondaryToolbar.tsx` is **deleted entirely**. The two-strip layout (titlebar + secondary) introduced in Phase 67 collapses back to a single titlebar strip. The canvas gains ~32px of vertical space.
- **D-09:** The **Export button** moves to the **File menu** as `"Export to Julia…"` (between Save As and any future entries). Same `exportCode` util, same keyboard shortcut if one existed — just triggered from the menu.
- **D-10:** The **Code Preview toggle** moves to the **bottom panel's own header bar**:
  - When the panel is **open**: a collapse/close button (chevron-down or ×) appears in the right side of the bottom panel's tab header.
  - When the panel is **closed**: a persistent thin stub strip (~20px) remains at the very bottom of the window, showing "Code ▲" (or equivalent label + icon). Clicking anywhere on the strip re-opens the panel.
  - The View menu "Toggle Code Preview" entry (Phase 67 D-11) stays as the keyboard-shortcut path — the menu entry and the header button both call the same `toggleBottomPanel()` store action.
  - This pattern mirrors VS Code / JetBrains bottom-panel UX.

### Claude's Discretion

The following are implementation details left to the planner/executor:

- **State shape:** Replace `activeLayer: LayerView` with `activeLayers: Record<LayerKey, boolean>` where `LayerKey = "Hydraulic" | "Thermal" | "Sources" | "ReactorPhysics"`. Default: all true. Add `hideOffLayer: boolean` (default: false). Persist both in `.scp` `layout` block alongside existing layout fields. Store actions: `toggleLayer(key)`, `setLayerVisible(key, visible)`, `setAllLayersVisible(visible)`.
- **Layer membership derivation:** Use the `category` field from the registry `ComponentDefinition` as the primary source of truth (`"Hydraulic"` → Hydraulic layer, `"Thermal"` → Thermal layer, `"Sources"` → Sources layer, `"Reactor Physics"` → Reactor Physics layer). This is more reliable than port-type detection for Sources (BCPort) and Reactor Physics (no ports). `layers.ts` rewrite should use `category`, not port sniffing.
- **Off-layer locking mechanism:** Enrich off-layer nodes with per-node ReactFlow props `{ selectable: false, draggable: false }` in the same enrichment pass that applies opacity — not via scattered event guards. In hide mode, use `{ hidden: true }`. This is cleaner than the current `onNodesChange.select` guard and extends correctly to `draggable`.
- **Floating chip placement:** Top-right of canvas, near the existing Phase 65 overlay buttons (ZoomIn/ZoomOut/FitView/InteractiveLock). Exact layout relative to those buttons is at the planner's discretion — separate cluster or integrated row.
- **Popover design:** shadcn Popover (already installed) around the chip. Contents: four `<Checkbox>` items with color-square labels + a small "Off-layer: Dim / Hide" toggle. Close on outside-click (standard Popover behavior).
- **Auto-enable on connect:** Hook into ReactFlow's `onConnect` callback. After a connection is created, check both endpoint nodes' layer memberships. If any involved layer is currently hidden, auto-enable it (call `setLayerVisible(key, true)`). Do NOT block the connection — just enable the layer post-hoc so the user sees the result.
- **`.scp` migration:** Old `layout.active_layer` string field → new `layout.active_layers` object + `layout.hide_off_layer` boolean. On load, if `active_layers` is missing but `active_layer` is present, convert: `"Both"` → all true, `"Hydraulic"` → hydraulic true + others false, `"Thermal"` → thermal true + others false.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Design decisions (authoritative — re-debate not allowed)
- `.planning/notes/gui-redesign-design-decisions.md` §3.13 — Layers System: full spec for four-layer taxonomy, independent toggles, floating chip, hide/dim setting, off-layer locking, layer-aware connect, rejected alternatives. Lines ~1073–1148.
- `.planning/notes/gui-redesign-design-decisions.md` §3.8 — Design System / Interaction Contract: visual restraint, accent palette discipline, density expectations. Lines ~616–710.
- `.planning/notes/gui-redesign-design-decisions.md` §4 — Cross-Cutting Invariants: includes "Off-layer items are non-interactive." Line ~1270–1275.

### Existing layers implementation (being rewritten)
- `gui/src/lib/layers.ts` — current pure-utility layer module (`LayerView`, `isNodeDimmed`, `isEdgeDimmed`, `getComponentLayers`); Phase 68 rewrites this wholesale for 4-layer independent toggles
- `gui/src/lib/__tests__/layers.test.ts` — existing tests (will need full rewrite to match new API)
- `gui/src/store/useStore.ts` — `activeLayer: LayerView`, `setActiveLayer`, `cycleLayer` (lines ~213–215, ~1028–1038, ~1031–1035); state shape replacement is the core store change
- `gui/src/components/CanvasPanel.tsx` — current dimming enrichment (lines ~96–131) + Tab→cycleLayer shortcut (line ~285) + dimmed-node selection guard (line ~171); all three change

### Components being deleted/migrated
- `gui/src/components/SecondaryToolbar.tsx` — entire file deleted in Phase 68
- `gui/src/components/ViewMenu.tsx` — remove "Layer" submenu items (lines referencing `setActiveLayer` / `activeLayer` / Layer radio group)
- `gui/src/components/FileMenu.tsx` — add "Export to Julia…" menu item (the export button migrates here)

### Phase 67 deliverables affected
- `gui/src/components/CustomTitlebar.tsx` — remove the `<SecondaryToolbar>` render from the layout (App.tsx integration point)
- `gui/src/App.tsx` — remove SecondaryToolbar from the JSX tree

### Registry types (layer membership source)
- `gui/src/registry/types.ts` — `ComponentDefinition.category` field: `"Hydraulic" | "Thermal" | "Sources" | "Resources" | "Reactor Physics"` (line ~213); this is the authoritative source for layer membership

### Phase context
- `.planning/ROADMAP.md` §"Phase 68" — goal text and dependency note (depends on Phase 62 for Sources layer)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `shadcn Popover` (`gui/src/components/ui/popover.tsx`) — already installed (used in Phase 62 ResourceReferencePicker); use for the Layers chip expand panel
- `shadcn Checkbox` — check if installed; standard shadcn component for the four layer toggles
- `useStore` selectors `isDirty`, `setActiveLayer` pattern — replace with new `activeLayers` slice following same setter pattern
- `gui/src/lib/exportCode.ts` — `exportCode` util unchanged; just wired from File menu instead of SecondaryToolbar button
- `SnapToGridButton.tsx` — pattern for canvas overlay buttons (absolute-positioned, z-10, rounded, bg-background shadow); Layers chip follows same pattern

### Established Patterns
- Per-node style enrichment in `CanvasPanel.tsx` (useMemo over nodes array, lines ~96–113) — extend this same pass to set `selectable`, `draggable`, and `hidden` props alongside opacity
- `isNodeDimmed` / `isEdgeDimmed` pure-function pattern in `layers.ts` — rewrite as `isNodeVisible(node, activeLayers)` and `isEdgeDimmed(edge, activeLayers)` with the same pure-function shape
- `.scp` layout block persistence — `activeLayer` is already in the layout block (lines ~2161, ~2227, ~2373, ~2453); `activeLayers` and `hideOffLayer` follow the same pattern
- shadcn DropdownMenu pattern for File menu additions — see `FileMenu.tsx` for the existing item structure

### Integration Points
- `App.tsx` — remove `<SecondaryToolbar>` from JSX; remove any props passed to it
- `CanvasPanel.tsx` — three integration points: (1) node enrichment for dimming/locking, (2) edge enrichment for dimming, (3) Tab shortcut removal
- `BottomPanel.tsx` or equivalent — add collapse/expand button to the bottom panel header; add persistent thin stub strip when `bottomPanelOpen === false`
- `projectIO.ts` — `.scp` save/load: add `active_layers` object + `hide_off_layer` field to layout block; add backward-compat read for old `active_layer` string

</code_context>

<specifics>
## Specific Ideas

- The thin bottom-panel stub strip when closed should show "Code ▲" (or a code icon + chevron) — the user said "we can try it out and see how it looks," so exact wording/styling is exploratory; planner should propose something and executor should make it easy to tweak.
- The Layers chip four color squares: lit (full opacity) when the layer is active, dim (opacity ~0.4) when the layer is hidden. This gives at-a-glance layer state without opening the popover.
- Layer-aware connect is intentionally forgiving — auto-enable, never block. The user confirmed this framing in the design doc exploration.

</specifics>

<deferred>
## Deferred Ideas

- **Extended accent palette** (applying Sources purple / Reactor Physics red to node borders, port handles, etc.) — Phase 72 (Design system / interaction contract). Phase 68 only uses these colors on the Layers chip indicator squares.
- **Settings dialog shell** — Phase 72. The hide/dim toggle lives in the Layers chip popover for now; it moves to a Settings dialog when that surface is built.
- **Reactor Physics layer content** — PointKinetics and ReactivityController GUI integration is parked (Section 6 of design-decisions doc). Phase 68 builds the Reactor Physics layer infrastructure; the components themselves don't land until a future phase.
- **Per-component rotation as autoflip fallback** — parked in Section 6 of the design-decisions doc; not v1.

</deferred>

---

*Phase: 68-layers-system-overhaul*
*Context gathered: 2026-05-16*
