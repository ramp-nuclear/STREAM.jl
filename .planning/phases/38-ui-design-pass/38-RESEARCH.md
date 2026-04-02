# Phase 38: UI Design Pass - Research

**Researched:** 2026-04-03
**Domain:** React UI design system, shadcn/ui integration, panel resize, Lucide icons
**Confidence:** HIGH

## Summary

Phase 38 is a visual polish pass that upgrades the STREAM Composer GUI from functional-but-plain to design-system-consistent. The scope covers four areas: (1) adding Lucide icons to canvas nodes and toolbox items with a single-source-of-truth icon map, (2) adding category color differentiation (blue/amber left-border stripe) to canvas nodes, (3) making both toolbox and sidebar panels collapsible (chevron toggle) and resizable (drag handle), and (4) auditing all UI elements for shadcn/ui compliance.

The existing codebase is well-structured for these changes. `StreamNode.tsx` is a 38-line component that needs icon + border additions. `ToolboxItem.tsx` is 21 lines needing an icon prop. `ToolboxPanel.tsx` needs collapse/resize wrapping. `SidebarPanel.tsx` needs the same treatment. The Zustand store needs two boolean fields. No new npm dependencies are needed -- all 16 Lucide icons specified in the UI-SPEC are verified to exist in the installed `lucide-react ^1.7.0`.

**Primary recommendation:** Implement in two plans: Plan 01 for data layer (icon map, store additions, resize hook) + node/toolbox visual changes; Plan 02 for panel collapse/resize behavior + shadcn audit + human verification.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Use Lucide React icons (already installed). Claude picks the icon mapping for all 12 STREAM components; mapping reviewed in UI-SPEC.md before coding.
- **D-02:** The icon mapping covers all 12 components: Channel, ChannelAndContacts, ChannelHeatFlux, Pump, Flapper, Friction, Gravity, Resistor, Inertia, HeatExchanger, ConstantTemperature, HeatDiffusion.
- **D-03:** Canvas nodes are differentiated by category color + icon. Two categories: Hydraulic (blue-ish accent) and Thermal (amber accent).
- **D-04:** Color accent appears as a colored left border stripe (~3-4px) in the category color. The rest of the card stays neutral/white. Icon appears in the top-left of the card alongside the component type label.
- **D-05:** Node card layout: `[icon] ComponentType` (small, accented) on first line; `instanceName` (bold) on second line. Left border stripe carries the category color.
- **D-06:** Both toolbox (left) and sidebar (right) panels support two affordances: (1) Chevron toggle button on the inner edge -- click to collapse/expand. (2) Drag handle on the inner edge -- drag to resize freely between min (~120px) and max (~400px).
- **D-07:** Collapsed state tracked in Zustand store (`toolboxCollapsed`, `sidebarCollapsed`). No disk persistence -- resets on restart.
- **D-08:** Toolbox items use icon + label rows: Lucide icon on the left, component label text on the right.
- **D-09:** The icon displayed in the toolbox item is the same icon used in the canvas node -- single source of truth from a `COMPONENT_ICONS` map.
- **D-10:** ToolboxItem stays a `<div>` (drag semantics) but gets shadcn-compatible Tailwind styling.
- **D-11:** All remaining raw `<button>` / `<input>` elements replaced with shadcn primitives as discovered during audit.

### Claude's Discretion
- Exact Lucide icon per component (documented in UI-SPEC.md -- mapping already defined there)
- Exact blue/amber Tailwind color tokens
- Drag handle implementation approach (custom mouse events vs library)
- Minimum/maximum panel widths
- Chevron button exact positioning

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DSGN-01 | App uses shadcn/ui for all UI primitives -- no hand-rolled CSS component implementations | Audit section documents current state: all buttons/inputs already use shadcn; ToolboxItem stays `<div>` per D-10; collapse chevrons use shadcn `Button` |
| DSGN-02 | App has fixed three-panel layout: left toolbox (collapsible) -> center canvas -> right sidebar (collapsible) | Panel collapse/resize architecture documented; Zustand store additions specified |
| DSGN-03 | Toolbox groups components into labeled categories with distinct icon per component type | Icon map and category grouping architecture documented; all 16 Lucide icons verified to exist |
| DSGN-04 | Canvas nodes visually differentiated by component type using color coding and/or icons | Node card layout with category border stripe + icon documented per UI-SPEC |
| DSGN-05 | Every frontend phase preceded by UI-SPEC contract; output audited by UI-REVIEW | UI-SPEC.md already created and approved; UI-REVIEW is a post-implementation step |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| lucide-react | ^1.7.0 | Component icons (16 icons) | Already installed; all 16 needed icons verified to exist |
| shadcn/ui (Radix) | New York/Zinc preset | UI primitives | Already initialized; button, input, label, select, scroll-area, tabs, tooltip, badge, dropdown-menu, separator installed |
| Tailwind CSS | ^4.2.2 | Utility-first styling | Already configured with @tailwindcss/vite |
| Zustand | ^5.0.12 | State management (collapse state) | Already the app's state manager |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| @xyflow/react | ^12.10.2 | Canvas nodes, handles | Already in use; StreamNode is a custom node type |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Custom mouse resize handler | shadcn `resizable` (react-resizable-panels) | shadcn resizable has known compatibility issues with v4 (GitHub issues #9118, #9136). Custom handler is ~40 lines, zero new dependencies, and gives full control over min/max width constraints. Use custom. |

**Installation:**
No new packages needed. All dependencies already installed.

## Architecture Patterns

### COMPONENT_ICONS Map (Single Source of Truth)

The icon map must be a standalone constant importable by both `StreamNode` and `ToolboxItem`. Place it in a new file or in the registry module.

**Recommended location:** `gui/src/registry/icons.ts`

```typescript
// Source: UI-SPEC.md Component Icon Map
import {
  RectangleHorizontal, Layers, Flame, Gauge, ToggleRight,
  Slash, ArrowDown, Minus, Weight, Thermometer,
  ThermometerSun, Grid3x3, Box,
  type LucideIcon,
} from "lucide-react";

export const COMPONENT_ICONS: Record<string, LucideIcon> = {
  Channel: RectangleHorizontal,
  ChannelAndContacts: Layers,
  ChannelHeatFlux: Flame,
  Pump: Gauge,
  Flapper: ToggleRight,
  Friction: Slash,
  Gravity: ArrowDown,
  Resistor: Minus,
  Inertia: Weight,
  HeatExchanger: Thermometer,
  ConstantTemperature: ThermometerSun,
  HeatDiffusion: Grid3x3,
};

export const FALLBACK_ICON: LucideIcon = Box;
```

### Category Color Map

```typescript
export const CATEGORY_COLORS: Record<string, string> = {
  Hydraulic: "border-l-blue-500",
  Thermal: "border-l-amber-500",
};
```

These Tailwind classes (`border-l-blue-500`, `border-l-amber-500`) must appear as complete string literals so Tailwind's JIT scanner can detect them. Never construct them dynamically (e.g., `border-l-${color}-500`).

### Panel Resize Hook Pattern

Custom `useResizable` hook using mouse events:

```typescript
function useResizable(options: {
  direction: "left" | "right";
  minWidth: number;
  maxWidth: number;
  defaultWidth: number;
}) {
  const [width, setWidth] = useState(options.defaultWidth);
  const isResizing = useRef(false);

  const onMouseDown = useCallback((e: React.MouseEvent) => {
    e.preventDefault();
    isResizing.current = true;
    const startX = e.clientX;
    const startWidth = width;

    const onMouseMove = (moveEvent: MouseEvent) => {
      const delta = options.direction === "left"
        ? moveEvent.clientX - startX
        : startX - moveEvent.clientX;
      const newWidth = Math.min(options.maxWidth,
        Math.max(options.minWidth, startWidth + delta));
      setWidth(newWidth);
    };

    const onMouseUp = () => {
      isResizing.current = false;
      document.removeEventListener("mousemove", onMouseMove);
      document.removeEventListener("mouseup", onMouseUp);
    };

    document.addEventListener("mousemove", onMouseMove);
    document.addEventListener("mouseup", onMouseUp);
  }, [width, options]);

  return { width, onMouseDown };
}
```

**Key detail:** The drag handle is on the **inner edge** of each panel. For the toolbox (left panel), the handle is on the right edge. For the sidebar (right panel), the handle is on the left edge.

### Updated StreamNode Layout

```tsx
// Per D-04, D-05
<div className={`border rounded-[var(--radius)] bg-card p-2 min-w-[140px]
  border-l-[3px] ${categoryColor}
  ${selected ? "ring-2 ring-[var(--ring)]" : ""}`}>
  <div className="flex items-center gap-1 text-[11px] text-muted-foreground">
    <Icon className="w-3.5 h-3.5" />
    <span>{component.label}</span>
  </div>
  <div className="font-semibold text-sm">{data.instanceName}</div>
  {/* Handle ports unchanged */}
</div>
```

### Updated ToolboxItem Layout

```tsx
// Per D-08, D-09
<div draggable onDragStart={onDragStart}
  className="flex items-center gap-2 px-2 py-1.5 rounded-md cursor-grab hover:bg-accent transition-colors text-sm">
  <Icon className="w-4 h-4 text-muted-foreground" />
  <span>{label}</span>
</div>
```

### Zustand Store Additions

Add to `AppState` interface and initial state:

```typescript
toolboxCollapsed: boolean;    // default: false
sidebarCollapsed: boolean;    // default: false
setToolboxCollapsed: (collapsed: boolean) => void;
setSidebarCollapsed: (collapsed: boolean) => void;
```

These are NOT content-mutating -- do NOT set `isDirty`. Exclude from zundo `partialize`.

### App.tsx Layout Update

```tsx
<div className="flex flex-1 min-h-0">
  {!toolboxCollapsed && <ToolboxPanel width={toolboxWidth} />}
  <CollapseButton panel="toolbox" />
  <div className="flex flex-col flex-1">
    <Toolbar />
    <CanvasPanel />
  </div>
  <CollapseButton panel="sidebar" />
  {!sidebarCollapsed && <SidebarPanel width={sidebarWidth} />}
</div>
```

The collapse chevron button should remain visible even when the panel is collapsed (as a 32px-wide strip) so the user can re-expand it.

### Anti-Patterns to Avoid
- **Dynamic Tailwind class construction:** Never `border-l-${color}-500` -- Tailwind JIT cannot scan dynamic strings. Use full literal class names in the category color map.
- **Inline styles for widths in collapsed state:** Use Tailwind `w-0` or conditional rendering, not `style={{width: 0}}`.
- **Resizable library for simple case:** The panel resize is two panels with fixed min/max -- a 40-line custom hook is simpler and more maintainable than adding react-resizable-panels.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Icon library | SVG icons as React components | lucide-react (already installed) | Consistent icon set, tree-shakeable, matches shadcn ecosystem |
| Button primitives | Custom `<button>` with styles | shadcn `Button` component | Accessibility (focus rings, disabled state), variant system |
| Scroll containers | Custom overflow scroll styling | shadcn `ScrollArea` | Cross-browser scrollbar consistency |

**Key insight:** Phase 38 is about consistency and polish, not new functionality. The main risk is missing a raw HTML element during the audit, not the complexity of any single change.

## Common Pitfalls

### Pitfall 1: Tailwind JIT Class Detection
**What goes wrong:** Dynamic class strings like `border-l-${category === 'Hydraulic' ? 'blue' : 'amber'}-500` are not detected by Tailwind's JIT compiler and produce no CSS output.
**Why it happens:** Tailwind scans source files for complete class strings at build time.
**How to avoid:** Always use complete literal strings. Store the full class (`"border-l-blue-500"`) in the lookup map, not partial tokens.
**Warning signs:** Border stripe renders with no visible color; inspect shows the class but no matching CSS rule.

### Pitfall 2: Panel Collapse Button Disappearing
**What goes wrong:** When a panel is collapsed via conditional rendering (`{!collapsed && <Panel />}`), the collapse toggle button also disappears, leaving no way to re-expand.
**How to avoid:** The chevron toggle button must be rendered independently of the panel content. Either: (a) render the button in `App.tsx` adjacent to the panel, or (b) render the panel container always but with zero width when collapsed, with only the button visible.
**Warning signs:** Collapsing a panel makes it impossible to re-expand without a keyboard shortcut.

### Pitfall 3: Resize Handler Mouse Event Leaking
**What goes wrong:** If the user moves the mouse fast during resize and leaves the panel area, `mouseup` fires on the document but the `mousemove` listener is not cleaned up.
**How to avoid:** Attach both `mousemove` and `mouseup` to `document` (not the drag handle element). Always remove both listeners in `mouseup` handler.
**Warning signs:** Panel keeps resizing after releasing the mouse button.

### Pitfall 4: Selection Ring vs Category Border Conflict
**What goes wrong:** The existing selected-state ring (`ring-2 ring-[var(--ring)]`) and the new category left border may visually clash or overlap.
**Why it happens:** CSS `ring` is a box-shadow; `border-l` is a real border. They occupy different visual layers.
**How to avoid:** The ring sits outside the border -- they should not conflict. However, verify that the 3px left border does not cause visual asymmetry with the ring on all four sides. If needed, adjust with `ring-offset`.
**Warning signs:** Node looks lopsided when selected due to thicker left edge.

### Pitfall 5: Zustand Temporal (zundo) Including Panel State
**What goes wrong:** If `toolboxCollapsed`/`sidebarCollapsed` are included in zundo's `partialize`, undo/redo will toggle panel collapse state, confusing users.
**How to avoid:** Exclude them from the `partialize` function. The existing partialize already only includes `nodes`, `edges`, `selectedNodeId`, `bcs` -- do NOT add the new fields.
**Warning signs:** Pressing Ctrl+Z toggles panel visibility instead of undoing canvas changes.

### Pitfall 6: ToolboxItem Drag Not Working After Icon Addition
**What goes wrong:** Adding child elements inside a `draggable` div can interfere with drag events if the child elements have `pointer-events` that intercept the dragstart.
**How to avoid:** Ensure the icon element does not have its own drag behavior. The `draggable` attribute on the parent div and `onDragStart` handler should work fine with inline SVG children from Lucide. No `pointer-events-none` needed on the icon -- Lucide icons are inline SVGs that don't intercept drag events.
**Warning signs:** Dragging from the icon part of the toolbox item does not initiate a drag operation.

## Code Examples

### Icon Map Import and Usage in StreamNode

```typescript
// gui/src/registry/icons.ts
import { RectangleHorizontal, Layers, Flame, Gauge, ToggleRight,
  Slash, ArrowDown, Minus, Weight, Thermometer, ThermometerSun,
  Grid3x3, Box, type LucideIcon } from "lucide-react";

export const COMPONENT_ICONS: Record<string, LucideIcon> = {
  Channel: RectangleHorizontal,
  ChannelAndContacts: Layers,
  ChannelHeatFlux: Flame,
  Pump: Gauge,
  Flapper: ToggleRight,
  Friction: Slash,
  Gravity: ArrowDown,
  Resistor: Minus,
  Inertia: Weight,
  HeatExchanger: Thermometer,
  ConstantTemperature: ThermometerSun,
  HeatDiffusion: Grid3x3,
};

export const FALLBACK_ICON: LucideIcon = Box;

export function getComponentIcon(componentId: string): LucideIcon {
  return COMPONENT_ICONS[componentId] ?? FALLBACK_ICON;
}
```

### Category Color Lookup

```typescript
// gui/src/registry/icons.ts (same file)
export const CATEGORY_BORDER_CLASSES: Record<string, string> = {
  Hydraulic: "border-l-blue-500",
  Thermal: "border-l-amber-500",
};

export function getCategoryBorderClass(category: string): string {
  return CATEGORY_BORDER_CLASSES[category] ?? "";
}
```

### Collapse Chevron Button

```tsx
// Per UI-SPEC: Button variant="ghost" size="icon" (32x32px)
import { Button } from "@/components/ui/button";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";

function PanelCollapseButton({ side, collapsed, onToggle }: {
  side: "left" | "right";
  collapsed: boolean;
  onToggle: () => void;
}) {
  const icon = side === "left"
    ? (collapsed ? <ChevronRight /> : <ChevronLeft />)
    : (collapsed ? <ChevronLeft /> : <ChevronRight />);
  const label = collapsed
    ? `Expand ${side === "left" ? "toolbox" : "sidebar"}`
    : `Collapse ${side === "left" ? "toolbox" : "sidebar"}`;

  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <Button variant="ghost" size="icon" onClick={onToggle}
          className="h-8 w-8 shrink-0">
          {icon}
        </Button>
      </TooltipTrigger>
      <TooltipContent side={side === "left" ? "right" : "left"}>
        {label}
      </TooltipContent>
    </Tooltip>
  );
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| react-resizable-panels v3 (shadcn resizable) | react-resizable-panels v4 | Early 2026 | v4 has breaking changes to export names; shadcn wrapper has compatibility issues (GitHub #9118, #9136). Custom resize handler avoids this. |
| Tailwind v3 with tailwind.config.js | Tailwind v4 with CSS-native config | 2025 | This project already uses Tailwind v4. No migration needed. |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Vitest ^4.1.2 |
| Config file | gui/vitest.config.ts |
| Quick run command | `cd gui && npx vitest run --passWithNoTests` |
| Full suite command | `cd gui && npx vitest run --passWithNoTests` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DSGN-01 | All UI elements use shadcn primitives | manual | Visual audit against UI-SPEC | N/A |
| DSGN-02 | Three-panel layout with collapse | unit | `npx vitest run src/components/__tests__/StreamNode.test.tsx` | Exists (update needed) |
| DSGN-03 | Toolbox has icons per component | unit | `npx vitest run src/registry/__tests__/icons.test.ts` | Wave 0 |
| DSGN-04 | Canvas nodes have category color + icon | unit | `npx vitest run src/components/__tests__/StreamNode.test.tsx` | Exists (update needed) |
| DSGN-05 | UI-SPEC precedes coding; UI-REVIEW after | process | UI-SPEC.md exists; UI-REVIEW.md created post-implementation | N/A |

### Sampling Rate
- **Per task commit:** `cd gui && npx vitest run --passWithNoTests`
- **Per wave merge:** `cd gui && npx vitest run --passWithNoTests`
- **Phase gate:** Full suite green + human visual verification

### Wave 0 Gaps
- [ ] `gui/src/registry/__tests__/icons.test.ts` -- covers DSGN-03: all 12 components have an icon mapping
- [ ] Update `gui/src/components/__tests__/StreamNode.test.tsx` -- covers DSGN-04: node renders icon and category border class
- [ ] `gui/src/store/__tests__/useStore.test.ts` -- add tests for `setToolboxCollapsed`/`setSidebarCollapsed` (file exists, extend)

## Open Questions

1. **Chevron button positioning when collapsed**
   - What we know: The button must remain visible when panel is collapsed (per D-06). UI-SPEC says a "32px-wide strip" remains.
   - What's unclear: Should this be implemented as the panel always rendering at min 32px width, or as a separate button element outside the panel?
   - Recommendation: Separate button element in App.tsx, not inside the panel. This avoids the panel needing to know about its collapsed state affecting its own rendering.

2. **Drag handle and chevron overlap**
   - What we know: UI-SPEC says "The drag handle overlaps with or is adjacent to the chevron button area."
   - What's unclear: Exact visual relationship.
   - Recommendation: Place the chevron button at vertical center of the panel edge. The drag handle is the full-height edge strip (8px). The chevron sits on top of the drag handle. When user grabs the handle area outside the button, it resizes; when they click the button, it collapses.

## Sources

### Primary (HIGH confidence)
- Lucide React icon verification: runtime check against installed `lucide-react ^1.7.0` -- all 16 icons confirmed to exist
- Existing codebase: `gui/src/components/StreamNode.tsx`, `ToolboxItem.tsx`, `ToolboxPanel.tsx`, `SidebarPanel.tsx`, `App.tsx`, `store/useStore.ts`
- UI-SPEC.md: `.planning/phases/38-ui-design-pass/38-UI-SPEC.md`
- CONTEXT.md: `.planning/phases/38-ui-design-pass/38-CONTEXT.md`

### Secondary (MEDIUM confidence)
- shadcn resizable compatibility issues: GitHub issues #9118, #9136 -- confirmed multiple reports of v4 breaking changes

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - all libraries already installed and in use; icon existence verified at runtime
- Architecture: HIGH - changes are straightforward edits to existing 20-40 line components; patterns are standard React
- Pitfalls: HIGH - based on direct codebase inspection and known Tailwind/React patterns

**Research date:** 2026-04-03
**Valid until:** 2026-05-03 (stable -- no fast-moving dependencies)
