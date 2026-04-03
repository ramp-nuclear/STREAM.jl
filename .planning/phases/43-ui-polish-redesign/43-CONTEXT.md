# Phase 43: UI Polish & Redesign - Context

**Gathered:** 2026-04-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Professional polish pass across every GUI surface: clean spacing, consistent visual hierarchy, no rough edges. Covers bottom panel resizable divider, parameter field descriptions in sidebar, thermal handle proportions, and a Toolbar/sidebar button consistency audit. Does NOT add new capabilities — existing functionality is preserved, only presentation improves.

</domain>

<decisions>
## Implementation Decisions

### Bottom Panel Resize
- **D-01:** Add a draggable resize handle at the **top border** of BottomPanel. User drags to resize the canvas↔bottom panel split.
- **D-02:** Panel height is stored in Zustand as `bottomPanelHeight: number` (default 240). Height survives panel close/reopen within the session. No disk persistence needed — resets on app restart is acceptable.
- **D-03:** Height bounds: minimum ~120px, maximum ~60% of viewport height. These prevent the bottom panel from crushing the canvas or becoming unusably small.

### Parameter Field Descriptions
- **D-04:** All parameter field types get the **Info icon + tooltip pattern** already used in `NumericField`. This covers: `PipeGeometryPicker`, `FunctionSelect`, `MatrixBadge`.
- **D-05:** The `description` string from `Parameter` in the registry is already populated for all components. No registry changes needed — just render the tooltip in the field components that currently omit it.
- **D-06:** Bool toggle fields (rendered inline in `ParameterForm`) also get the Info icon + tooltip if `param.description` is present.

### Thermal Handle Proportions
- **D-07:** ChannelAndContacts has exactly **two** thermal handles (one per side: `thermal_left` on top edge, `thermal_right` on bottom edge), matching Phase 40 D-01/D-04. No per-cell handles — the `array: true` registry field is code-gen only.
- **D-08:** Claude adjusts the diamond handle size and proportions so it looks clean and proportional next to FlowPort circle handles. Current 10×10px may need minor tweaking. Exact size is Claude's discretion.

### Button & Spacing Audit
- **D-09:** Audit scope is **Toolbar + sidebar only**. Dialogs, menus, and WelcomeOverlay already use shadcn primitives and are excluded.
- **D-10:** Toolbar buttons (Code, Download/Export, layer toggle `ToggleGroup`) should have consistent `size="sm"` and matching hover states. The `ToggleGroup` layer switcher and standalone `Button` elements should align visually.
- **D-11:** The Bool parameter toggle in `ParameterForm` uses `Button` with `variant="default"/"outline"` — this is acceptable; ensure it matches the `size="sm"` convention used elsewhere in the sidebar.

### Claude's Discretion
- Exact thermal diamond handle size (current 10×10px; adjust as needed for visual balance)
- Drag handle appearance (1-2px top border highlight on hover vs explicit grab zone)
- Whether `bottomPanelHeight` is clamped client-side during drag vs only validated on mouse-up
- Exact cursor style for resize handle (`row-resize`)
- Any minor spacing/padding inconsistencies discovered during audit that aren't called out above

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Roadmap
- `.planning/ROADMAP.md` §"Phase 43: UI Polish & Redesign" — Goal, success criteria (5 items), depends-on Phase 42

### Phase 40 thermal handle decisions (locked — do not re-debate)
- `.planning/phases/40-thermal-composition/40-CONTEXT.md` — D-01, D-04: one handle per side on ChannelAndContacts; `array: true` is code-gen only; renderer always renders one handle per ThermalPort entry

### Existing GUI code (read before editing)
- `gui/src/components/BottomPanel.tsx` — Fixed `h-[240px]`, `border-t`; drag handle and height prop go here
- `gui/src/store/useStore.ts` — Add `bottomPanelHeight: number` field; `toggleBottomPanel` already exists
- `gui/src/components/sidebar/NumericField.tsx` — Reference implementation for Info icon + tooltip pattern (copy this pattern to other field types)
- `gui/src/components/sidebar/PipeGeometryPicker.tsx` — Needs Info tooltip added
- `gui/src/components/sidebar/FunctionSelect.tsx` — Needs Info tooltip added
- `gui/src/components/sidebar/MatrixBadge.tsx` — Needs Info tooltip added
- `gui/src/components/sidebar/ParameterForm.tsx` — Bool toggle rendered here; add Info tooltip, verify `size="sm"`
- `gui/src/components/StreamNode.tsx` — ThermalPort handle rendering (lines near `thermalPorts.map`); adjust size if needed
- `gui/src/components/Toolbar.tsx` — Button audit: Code, Download/Export buttons, layer `ToggleGroup`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `NumericField.tsx` — Already has the complete Info+tooltip pattern (TooltipProvider, Tooltip, TooltipTrigger, TooltipContent from shadcn). Copy verbatim to other field components.
- `@/components/ui/tooltip` — Installed shadcn tooltip primitive; used in NumericField.
- Zustand store (`useStore.ts`) — Already has `bottomPanelHeight`-adjacent patterns (`toolboxWidth`, `sidebarWidth` from Phase 38 resize work). Add `bottomPanelHeight` following the same pattern.

### Established Patterns
- Panel resize: `SidebarPanel` already receives `onResizeMouseDown` prop and renders a `w-1 h-full cursor-col-resize` div on its left edge. Bottom panel resize follows the same pattern on the top edge (`h-1 w-full cursor-row-resize`).
- Button sizing: Toolbar uses `size="sm"` on shadcn `Button`. Sidebar should match.
- Thermal handles: `StreamNode.tsx` — amber (#f59e0b), `borderRadius: 0`, `transform: rotate(45deg)` — already diamond-shaped.

### Integration Points
- `App.tsx` or layout root: manages `onResizeMouseDown` for sidebar and will need to manage bottom panel height drag similarly.
- `useStore.ts`: source of truth for `bottomPanelHeight`; component reads from store, drag updates store.

</code_context>

<specifics>
## Specific Ideas

- The thermal handle question about "per-cell density" was a non-issue — confirmed by user: Phase 40 D-01 is correct and locked. ChannelAndContacts has exactly 2 thermal handles (one per side), never n handles.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 43-ui-polish-redesign*
*Context gathered: 2026-04-04*
