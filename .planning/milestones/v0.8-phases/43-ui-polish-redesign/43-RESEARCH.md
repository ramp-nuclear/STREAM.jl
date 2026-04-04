# Phase 43: UI Polish & Redesign - Research

**Researched:** 2026-04-04
**Domain:** React/TypeScript GUI polish — shadcn/ui, ReactFlow handles, panel resize, tooltips
**Confidence:** HIGH

## Summary

Phase 43 is a visual polish pass across four well-scoped areas: (1) bottom panel drag-to-resize, (2) parameter field description tooltips, (3) thermal handle proportion adjustment, and (4) toolbar/sidebar button audit. The codebase already contains all required primitives — the sidebar resize pattern (`useResizable` hook + drag handle div) provides a direct template for bottom panel resize, `NumericField.tsx` provides the exact tooltip pattern to replicate, and all shadcn components are already installed.

The research confirms there are no new library dependencies needed. Every change is a modification to existing files using established patterns. The primary technical consideration is adapting the existing horizontal `useResizable` hook to support vertical resizing (or creating a parallel `useVerticalResizable` hook), and wiring the store-backed `bottomPanelHeight` into `BottomPanel.tsx` and `App.tsx`.

**Primary recommendation:** Follow the existing `useResizable` + `SidebarPanel` resize pattern exactly, adapting direction from horizontal to vertical. Copy the `NumericField` tooltip pattern verbatim into the 3 remaining field components and the bool toggle in `ParameterForm`.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Add a draggable resize handle at the top border of BottomPanel. User drags to resize the canvas/bottom panel split.
- **D-02:** Panel height is stored in Zustand as `bottomPanelHeight: number` (default 240). Height survives panel close/reopen within the session. No disk persistence needed.
- **D-03:** Height bounds: minimum ~120px, maximum ~60% of viewport height.
- **D-04:** All parameter field types get the Info icon + tooltip pattern already used in NumericField.
- **D-05:** The description string from Parameter in the registry is already populated. No registry changes needed.
- **D-06:** Bool toggle fields also get the Info icon + tooltip if param.description is present.
- **D-07:** ChannelAndContacts has exactly two thermal handles (one per side). No per-cell handles.
- **D-08:** Claude adjusts the diamond handle size and proportions. Exact size is Claude's discretion.
- **D-09:** Audit scope is Toolbar + sidebar only. Dialogs, menus, and WelcomeOverlay excluded.
- **D-10:** Toolbar buttons should have consistent size="sm" and matching hover states.
- **D-11:** Bool parameter toggle uses Button with variant="default"/"outline" -- acceptable; ensure size="sm".

### Claude's Discretion
- Exact thermal diamond handle size (current 10x10px; UI-SPEC recommends 12x12px with 1.5px border)
- Drag handle appearance (1-2px top border highlight on hover vs explicit grab zone)
- Whether bottomPanelHeight is clamped client-side during drag vs only validated on mouse-up
- Exact cursor style for resize handle (row-resize)
- Any minor spacing/padding inconsistencies discovered during audit

### Deferred Ideas (OUT OF SCOPE)
None.
</user_constraints>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| React | 19.1.0 | UI framework | Already installed |
| zustand | 5.0.12 | State management | Already installed; bottomPanelHeight goes here |
| @xyflow/react | 12.10.2 | Canvas/node editor | Already installed; Handle style props for thermal diamonds |
| shadcn/ui (Radix) | radix-ui 1.4.3 | Tooltip, Button, ToggleGroup primitives | Already installed; all needed primitives present |
| lucide-react | 1.7.0 | Info icon for tooltips | Already installed; Info icon already used in NumericField |

### Supporting
No new libraries needed. All primitives are already installed.

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Custom resize hook | react-resizable-panels | Overkill -- existing `useResizable` hook works perfectly; adding a dependency for one panel resize is unnecessary |
| Custom tooltip | @radix-ui/react-tooltip directly | Already wrapped by shadcn -- use the shadcn wrapper consistently |

## Architecture Patterns

### Current Layout Structure
```
App.tsx
  div.flex.flex-col.h-screen
    div.flex.flex-1.min-h-0          (main row)
      ToolboxPanel (width from useResizable)
      PanelCollapseButton (left)
      div.flex.flex-col.flex-1       (center column)
        Toolbar
        CanvasPanel
      PanelCollapseButton (right)
      SidebarPanel (width from useResizable)
    BottomPanel                       (currently fixed h-[240px])
```

### Pattern 1: Panel Resize via useResizable Hook
**What:** The existing `useResizable` hook handles horizontal panel resize via mousedown/mousemove/mouseup on document. It stores width in React state. The sidebar and toolbox both use this pattern.
**When to use:** Bottom panel resize follows the same pattern but for vertical direction.
**Adaptation needed:** The current hook only supports `direction: "left" | "right"` (horizontal). For the bottom panel, we need vertical resize with `minHeight`/`maxHeight` and `clientY` delta instead of `clientX` delta. Two options:
1. Extend `useResizable` to support `direction: "top"` (vertical).
2. Create a separate `useVerticalResizable` hook.

Option 1 is cleaner since the logic is nearly identical. However, the interface changes from `width` to a generic `size` return, which could be a breaking change for existing callers. **Recommendation:** Create a small `useVerticalResizable` hook (copy of `useResizable` adapted for Y-axis) to avoid touching working code. It is ~30 lines.

**Store integration:** Unlike sidebar/toolbox (which use local React state via `useResizable`), bottomPanelHeight needs to survive panel close/reopen. Store it in Zustand per D-02. The hook should read initial value from store and write back on drag.

### Pattern 2: Tooltip Replication
**What:** `NumericField.tsx` lines 42-51 contain the exact JSX pattern for Info icon + tooltip.
**When to use:** Every field component label that receives a `param` with a `description` property.
**Files needing the pattern:**
- `MatrixBadge.tsx` -- currently has NO tooltip at all (confirmed by reading the file)
- `ParameterForm.tsx` Bool toggle section -- currently has NO tooltip (confirmed)
- `FunctionSelect.tsx` -- ALREADY HAS the tooltip pattern (confirmed at lines 97-109)
- `PipeGeometryPicker.tsx` -- ALREADY HAS the tooltip pattern in DimensionField (confirmed at lines 57-69)

**Important finding:** Only `MatrixBadge` and the Bool toggle in `ParameterForm` actually need tooltip addition. `FunctionSelect` and `PipeGeometryPicker` already have the pattern. The UI-SPEC and CONTEXT.md list all four, but two are already done. The planner should verify this at implementation time and skip the ones already complete.

### Pattern 3: Handle Style Props in ReactFlow
**What:** `StreamNode.tsx` thermal handle styling uses inline `style` prop on `<Handle>` with width, height, borderRadius, transform, border, and background.
**When to use:** Adjusting thermal diamond proportions.
**Change:** Update width: 10 to 12, height: 10 to 12, border: `1px solid` to `1.5px solid`. Three values in one `style` object.

### Anti-Patterns to Avoid
- **Adding new npm dependencies for single-use UI features:** The codebase has everything needed. Do not add react-resizable-panels or similar.
- **Modifying useResizable to be generic:** The horizontal resize hook works for its consumers. Create a parallel vertical hook rather than risk breaking sidebar/toolbox resize.
- **Wrapping entire App in TooltipProvider:** App.tsx already wraps everything in `<TooltipProvider>` (line 183). Individual `<TooltipProvider>` wrappers inside field components are redundant but harmless and match the established pattern. Do not refactor them out during a polish phase.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Tooltips | Custom hover/popover | shadcn Tooltip (already used) | Accessibility, positioning, z-index handled |
| Drag resize | requestAnimationFrame + manual state | mousedown/mousemove/mouseup pattern from `useResizable` | Document-level listeners prevent mouse escape; proven pattern |
| Button consistency | CSS overrides | shadcn `size="sm"` prop | Consistent sizing baked into the design system |

## Common Pitfalls

### Pitfall 1: Bottom Panel Max Height Calculation
**What goes wrong:** Using a fixed pixel value for max height instead of percentage of viewport. On small screens the bottom panel can consume the entire canvas.
**Why it happens:** D-03 says "maximum ~60% of viewport height" which requires `window.innerHeight` reading.
**How to avoid:** Calculate `maxHeight` as `Math.floor(window.innerHeight * 0.6)` during drag. Recalculate on each mousemove event (viewport may have resized since drag started). Or use a ref that updates on window resize.
**Warning signs:** Bottom panel covering the toolbar on small screens.

### Pitfall 2: BottomPanel Height Not Surviving Close/Reopen
**What goes wrong:** Using local React state for height means it resets when the component unmounts (panel closed via `toggleBottomPanel`).
**Why it happens:** BottomPanel returns `null` when closed, unmounting the component.
**How to avoid:** Store `bottomPanelHeight` in Zustand (D-02). Read from store, write to store on drag. The component reads store value on re-mount.
**Warning signs:** Panel always reopening at 240px after being resized.

### Pitfall 3: MatrixBadge Missing param Prop for Tooltip
**What goes wrong:** MatrixBadge receives `param: Parameter` which includes `description`, but the component currently does not import or render Tooltip components.
**Why it happens:** MatrixBadge was written as a minimal read-only badge; tooltip imports were not included.
**How to avoid:** Add the same imports and JSX pattern from NumericField. The `param.description` field is already available via the prop.
**Warning signs:** Info icon missing next to "materials" or "power_shape" labels.

### Pitfall 4: ToggleGroup Height Mismatch
**What goes wrong:** `ToggleGroup` with `size="sm"` may render at a different height than `Button` with `size="sm"` due to different internal padding.
**Why it happens:** shadcn ToggleGroupItem and Button have independently defined size variants.
**How to avoid:** Verify both render at 32px height. If not, add explicit `h-8` to the ToggleGroup container to match.
**Warning signs:** Buttons and toggle group visually misaligned in the toolbar.

## Code Examples

### Bottom Panel Resize Hook (vertical adaptation)
```typescript
// Adapted from gui/src/hooks/useResizable.ts for vertical direction
import { useCallback, useRef } from "react";
import useStore from "@/store/useStore";

export function useBottomPanelResize() {
  const startYRef = useRef(0);
  const startHeightRef = useRef(0);

  const onMouseDown = useCallback((e: React.MouseEvent) => {
    e.preventDefault();
    const height = useStore.getState().bottomPanelHeight;
    startYRef.current = e.clientY;
    startHeightRef.current = height;

    const onMouseMove = (moveEvent: MouseEvent) => {
      const deltaY = startYRef.current - moveEvent.clientY; // inverted: drag up = taller
      const maxHeight = Math.floor(window.innerHeight * 0.6);
      const newHeight = Math.min(maxHeight, Math.max(120, startHeightRef.current + deltaY));
      useStore.getState().setBottomPanelHeight(newHeight);
    };

    const onMouseUp = () => {
      document.removeEventListener("mousemove", onMouseMove);
      document.removeEventListener("mouseup", onMouseUp);
    };

    document.addEventListener("mousemove", onMouseMove);
    document.addEventListener("mouseup", onMouseUp);
  }, []);

  return { onMouseDown };
}
```

### Drag Handle in BottomPanel
```typescript
// Top edge of BottomPanel, matching sidebar left-edge pattern
<div
  className="h-2 w-full cursor-row-resize hover:bg-ring/30 transition-colors"
  onMouseDown={onResizeMouseDown}
/>
```

### Tooltip Pattern for MatrixBadge
```typescript
// Copy from NumericField.tsx lines 42-51
import { Info } from "lucide-react";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";

// In the Label:
<Label className="text-[13px] font-semibold leading-[1.4] flex items-center gap-1">
  {param.name}
  {param.description && (
    <TooltipProvider>
      <Tooltip>
        <TooltipTrigger asChild>
          <Info className="h-3 w-3 text-muted-foreground cursor-default" />
        </TooltipTrigger>
        <TooltipContent>{param.description}</TooltipContent>
      </Tooltip>
    </TooltipProvider>
  )}
</Label>
```

### Thermal Handle Size Update
```typescript
// In StreamNode.tsx thermal handle style object:
style={{
  background: THERMAL_HANDLE_COLOR,
  border: `1.5px solid ${THERMAL_HANDLE_BORDER}`,  // was: 1px
  width: 12,   // was: 10
  height: 12,  // was: 10
  borderRadius: 0,
  transform: "rotate(45deg)",
  ...(dimThermalHandles ? { opacity: 0.2, pointerEvents: "none" as const } : {}),
}}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Fixed 240px bottom panel | Resizable via drag handle | Phase 43 | Better UX for code preview |
| Tooltips only on NumericField | All field types get tooltips | Phase 43 | Discoverability of param descriptions |

## Open Questions

None. All decisions are locked, all primitives are available, and the patterns are established in the codebase.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | vitest (node env default, jsdom per-file) |
| Config file | gui/vitest.config.ts |
| Quick run command | `cd gui && npx vitest run --passWithNoTests` |
| Full suite command | `cd gui && npx vitest run --passWithNoTests` |

### Phase Requirements to Test Map

Phase 43 has no formal requirement IDs (TBD in REQUIREMENTS.md). The success criteria from the ROADMAP map to these verifiable items:

| Criterion | Behavior | Test Type | Automated Command | Notes |
|-----------|----------|-----------|-------------------|-------|
| SC-1: Button consistency | All toolbar/sidebar buttons use size="sm" | Code audit / grep | `grep -rn 'size=' gui/src/components/Toolbar.tsx gui/src/components/sidebar/ParameterForm.tsx` | Manual verification during review |
| SC-2: Thermal handle proportions | Diamond is 12x12 with 1.5px border | Unit test | Existing `StreamNode.test.tsx` can verify handle style | Extend existing test |
| SC-3: Sidebar param descriptions | All field types show tooltip when description present | Component test (jsdom) | `cd gui && npx vitest run src/components/sidebar/__tests__/` | Extend existing ParameterForm test |
| SC-4: Panel dividers draggable | Bottom panel height changes on drag | Store unit test | `cd gui && npx vitest run src/store/__tests__/` | Test setBottomPanelHeight action |
| SC-5: Professional appearance | No rough edges visible | Manual visual inspection | N/A | Screenshot comparison |

### Sampling Rate
- **Per task commit:** `cd /home/itay/projects/Julia-STREAM/gui && npx vitest run --passWithNoTests`
- **Per wave merge:** Same (single test suite)
- **Phase gate:** Full suite green + manual visual inspection

### Wave 0 Gaps
- [ ] `gui/src/store/__tests__/useStore.test.ts` -- add tests for `bottomPanelHeight`, `setBottomPanelHeight` store fields
- [ ] Optionally extend `gui/src/components/sidebar/__tests__/ParameterForm.test.tsx` to verify tooltip renders for Bool fields with description

*(Existing test infrastructure covers store and component testing. No new framework setup needed.)*

## Sources

### Primary (HIGH confidence)
- Direct codebase inspection of all files listed in CONTEXT.md canonical_refs section
- `gui/src/hooks/useResizable.ts` -- existing horizontal resize hook pattern
- `gui/src/components/sidebar/NumericField.tsx` -- existing tooltip pattern
- `gui/src/components/StreamNode.tsx` -- existing thermal handle style values
- `gui/src/App.tsx` -- current layout structure and panel wiring
- `gui/src/store/useStore.ts` -- current store shape and patterns

### Secondary (MEDIUM confidence)
- ReactFlow Handle component `style` prop documentation (inline styles are the standard approach for per-handle customization)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all libraries already installed, versions confirmed from package.json
- Architecture: HIGH -- direct codebase inspection of every file involved
- Pitfalls: HIGH -- derived from reading actual implementation patterns and identifying specific gaps

**Key finding: Tooltip work is partially done.** FunctionSelect and PipeGeometryPicker already have the Info+tooltip pattern. Only MatrixBadge and the Bool toggle in ParameterForm need it added. This reduces the tooltip task scope by ~50%.

**Research date:** 2026-04-04
**Valid until:** 2026-05-04 (stable -- all changes are to existing codebase with no external dependency changes)
