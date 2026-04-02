# Phase 38: UI Design Pass - Context

**Gathered:** 2026-04-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Every UI surface uses shadcn/ui design system with consistent visual language: component icons throughout, category-level color differentiation on canvas nodes, collapsible + resizable panels, and shadcn/ui primitives replacing any remaining raw HTML elements. Quality gates: preceded by `/gsd:ui-phase` (UI-SPEC.md contract) and followed by `/gsd:ui-review` audit.

</domain>

<decisions>
## Implementation Decisions

### Component Icons
- **D-01:** Use Lucide React icons (already installed and in use for `Code2`, `Download`). Claude picks the icon mapping for all 12 STREAM components; mapping reviewed in UI-SPEC.md before coding.
- **D-02:** The icon mapping covers all 12 components: Channel, ChannelAndContacts, ChannelHeatFlux, Pump, Flapper, Friction, Gravity, Resistor, Inertia, HeatExchanger, ConstantTemperature, HeatDiffusion.

### Node Visual Design
- **D-03:** Canvas nodes are differentiated by **category color + icon**. Two categories: Hydraulic (blue-ish accent) and Thermal (amber accent).
- **D-04:** Color accent appears as a **colored left border stripe** (~3-4px) in the category color. The rest of the card stays neutral/white. Icon appears in the top-left of the card alongside the component type label.
- **D-05:** Node card layout (updated from Phase 34 D-01): `[icon] ComponentType` (small, accented) on first line; `instanceName` (bold) on second line. Left border stripe carries the category color.

### Panel Collapsibility
- **D-06:** Both toolbox (left) and sidebar (right) panels support **two affordances**:
  1. **Chevron toggle button** on the inner edge of each panel — click to collapse/expand. Collapsed = panel hidden entirely, canvas fills the space.
  2. **Drag handle** on the inner edge — drag to resize freely between a minimum width (~120px) and a maximum (~400px).
- **D-07:** Collapsed state is tracked in the Zustand store (`toolboxCollapsed: boolean`, `sidebarCollapsed: boolean`) so state survives re-renders. No persistence to disk needed — resets on app restart is acceptable.

### Toolbox Item Design
- **D-08:** Toolbox items use **icon + label rows**: the Lucide icon on the left, component label text on the right. Same compact row layout as today but with the icon. Draggable (existing `onDragStart` behavior unchanged).
- **D-09:** The icon displayed in the toolbox item is the same icon used in the canvas node — single source of truth from a `COMPONENT_ICONS` map in the codebase.

### shadcn/ui Audit
- **D-10:** `ToolboxItem` is currently a raw `<div>` with drag handling. It stays a `<div>` (draggable semantics require it) but gets shadcn-compatible styling (`rounded-md`, `hover:bg-accent`, `cursor-grab` — already partially there).
- **D-11:** All remaining raw `<button>` / `<input>` elements (if any) are replaced with shadcn primitives as discovered during UI-SPEC audit.

### Claude's Discretion
- Exact Lucide icon per component (documented in UI-SPEC.md)
- Exact blue/amber Tailwind color tokens (e.g., `border-l-blue-500` vs `border-l-primary`)
- Drag handle implementation approach (React drag resize library or custom mouse events)
- Minimum/maximum panel widths
- Chevron button exact positioning (absolute vs flex, which corner)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` §"UI Design" → DSGN-01..DSGN-05 — Exact acceptance criteria for this phase

### Roadmap
- `.planning/ROADMAP.md` §"Phase 38: UI Design Pass" — Success criteria, depends-on

### Existing UI code (read before making changes)
- `gui/src/components/StreamNode.tsx` — Current node: minimal card, no icons, no color. Phase 38 replaces this.
- `gui/src/components/ToolboxItem.tsx` — Current: raw `<div>` with drag. Phase 38 adds icon.
- `gui/src/components/ToolboxPanel.tsx` — Fixed `w-60`, no collapse. Phase 38 adds toggle + drag resize.
- `gui/src/components/SidebarPanel.tsx` — Top-level sidebar wrapper. Phase 38 adds collapse affordance.
- `gui/src/components/ui/` — Installed shadcn primitives: button, input, label, select, scroll-area, tabs, tooltip, badge, dropdown-menu, separator

### Prior phase context
- `.planning/phases/34-canvas-node-editor/34-CONTEXT.md` — D-01: node was intentionally left minimal for Phase 38 redesign; D-03: ThermalPort handles deferred to Phase 40
- `.planning/phases/33-project-scaffold/33-CONTEXT.md` — D-06: Zustand store shape (add `toolboxCollapsed`/`sidebarCollapsed` booleans here)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `lucide-react ^1.7.0` — Already installed. No new dependency needed for icons.
- `gui/src/components/ui/button.tsx` — shadcn Button; use for collapse chevron affordance.
- `gui/src/components/ui/tooltip.tsx` — Tooltip; use for icon-only tooltips if needed.
- `gui/src/store/useStore.ts` — Zustand store; add `toolboxCollapsed`/`sidebarCollapsed` fields here.

### Established Patterns
- Category grouping already implemented in `ToolboxPanel.tsx` (`getComponentsByCategory("Hydraulic")` / `getComponentsByCategory("Thermal")`). The icon map should use the same `category` field from the registry.
- `StreamNode.tsx` uses `bg-card`, `text-muted-foreground`, `ring-2 ring-[var(--ring)]` for selected state — new accent border must not conflict with the selection ring.
- Toolbar already uses `bg-muted border-b` for its bar styling — consistent header/bar convention established.

### Integration Points
- `gui/src/registry/components.json` — Source of truth for `category` field (determines blue vs amber accent). No registry changes needed for Phase 38.
- `gui/src/App.tsx` — Three-panel flex layout. Panel collapse state may need CSS class toggling here or in each panel component.
- Tauri window title and `getCurrentWindow()` already used in App.tsx — no new Tauri APIs needed.

</code_context>

<specifics>
## Specific Ideas

- Collapse mechanic: chevron toggle (click to hide/show) AND drag handle to resize — user wants both affordances.
- Left border stripe accent (not top header band) — subtler, VS Code / Linear convention.
- Icon + label rows in toolbox (not icon tiles) — keeps compact list layout, just adds icon on left.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 38-ui-design-pass*
*Context gathered: 2026-04-03*
