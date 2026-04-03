# Phase 42: Edge & Path Visual Overhaul - Context

**Gathered:** 2026-04-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix edge rendering quality across the ReactFlow canvas: correct arrowheads on hydraulic edges, non-overlapping routing for parallel/loop edges, thermal edges already visually distinct (amber + dashed), cursor glitch fix on edge drag handles, rename counter reconstruction fix on project load, and FlowPort handle polarity coloring (port_in vs port_out distinct colors).

</domain>

<decisions>
## Implementation Decisions

### Arrowheads
- **D-01:** Hydraulic (FlowPort) edges get **filled arrowheads** (`MarkerType.ArrowClosed`) at the **target end only**. Applied via `markerEnd` on the edge object when the edge is created in `addEdge`.
- **D-02:** Thermal (ThermalPort, amber dashed) edges get **no arrowheads**. Thermal coupling is symmetric heat exchange — directionality would mislead. Amber + dashed is sufficient visual distinction.

### Parallel Edge Routing
- **D-03:** Keep `smoothstep` edge type. For **bidirectional edge pairs** (A→B and B→A on the same handle pair), auto-detect the pair and apply a **lateral offset (~20px)** via `pathOptions.offset` so the two edges route as parallel lines, visually distinct. No edge type change needed.
- **D-04:** Offset detection: when adding an edge, check if a reverse edge already exists (same source/target handles swapped). If so, apply offset to both edges in the pair. Detected at `addEdge` time.

### Thermal Edge Treatment
- **D-05:** No changes to thermal edge style beyond what's already implemented (`stroke: "#f59e0b"`, `strokeDasharray: "6 3"`). Once routing is fixed and arrowheads are absent, thermal edges are sufficiently distinct from hydraulic edges.

### FlowPort Handle Polarity Coloring
- **D-06:** `port_in` and `port_out` handles get **distinct colors** so connection direction is immediately visible. Claude picks the exact colors (must harmonize with the existing blue hydraulic category color and not clash with amber thermal handles).
- **D-07:** Port direction (`"in"` vs `"out"`) is derived from the `direction` field in `gui/src/registry/components.json` port entries. The `StreamNode` handle renderer reads `port.direction` to apply the color. No registry schema changes — the field already exists (or is added if missing per the component definitions).

### Cursor Glitch Fix
- **D-08:** Edge drag handle cursor disappearance is a CSS/pointer-events bug. Fix via CSS targeting `.react-flow__handle` or the specific handle element — ensure `cursor: crosshair` (or appropriate) is set and not overridden by conflicting rules. Claude investigates root cause and applies minimal fix.

### Rename Counter Bug Fix
- **D-09:** `reconstructInstanceCounters` in `gui/src/lib/projectIO.ts` currently uses a generic regex prefix (`.+` before `_N`) which is ambiguous for custom-named nodes. Fix: use `data.componentId.toLowerCase()` as the key and only update the counter when `instanceName` matches `^<componentId_lower>_(\d+)$`. This makes reconstruction type-aware and ignores renamed nodes that don't match the default pattern.

### Claude's Discretion
- Exact arrowhead size and color (should be visible against the canvas background, not oversized)
- Exact colors for port_in vs port_out handles (must harmonize with blue hydraulic category, not conflict with amber thermal)
- Whether offset is applied symmetrically (+10px / -10px) or asymmetrically (0 / +20px)
- CSS selector and property for cursor fix
- Whether offset detection uses an O(n) edge scan or a Set for O(1) lookup

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Roadmap
- `.planning/ROADMAP.md` §"Phase 42: Edge & Path Visual Overhaul" — Goal, success criteria (5 items)

### Existing GUI code (read before editing)
- `gui/src/components/CanvasPanel.tsx` — `defaultEdgeOptions`, `addEdge` callback, `isValidConnection`; arrowhead + offset logic goes here or in `addEdge` store action
- `gui/src/store/useStore.ts` — `addEdge` action (lines ~331–376): edge styling applied here; markerEnd and offset should be added at this point; `instanceCounters` module-level object and `getNextInstanceName`
- `gui/src/lib/projectIO.ts` — `reconstructInstanceCounters` function (~line 138); counter reconstruction bug fix goes here
- `gui/src/components/StreamNode.tsx` — Handle renderer; polarity coloring (port_in vs port_out) applied here via `port.direction`
- `gui/src/registry/components.json` — Per-port `direction` field ("in"/"out") for all 9 component types; verify field exists for all FlowPort entries

### Prior phase context
- `.planning/phases/40-thermal-composition/40-CONTEXT.md` — D-03: ThermalPort handles amber (#f59e0b); D-05/D-06: FlowPort/ThermalPort type distinction in handles
- `.planning/phases/41-layered-canvas/41-CONTEXT.md` — D-03: thermal edge dimming applies to dashed amber edges; D-08: FlowPort handles dimmed in Thermal view

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `defaultEdgeOptions = { type: "smoothstep" }` in `CanvasPanel.tsx` — central point for edge type; add `markerEnd` default here for hydraulic edges
- `addEdge` store action (`useStore.ts:331`) — already applies thermal edge styling; markerEnd + offset detection can be added here
- `reconstructInstanceCounters` (`projectIO.ts:138`) — function to fix; already has test coverage in `projectIO.test.ts:211`

### Established Patterns
- Thermal edge styling (amber + dashed) applied per-edge in `addEdge` by checking port type — same pattern applies for hydraulic arrowhead injection
- Handle styling in `StreamNode.tsx` uses `style` prop on `<Handle>` — polarity color follows the same pattern as the existing dimming logic
- Edge enrichment for layer dimming uses `useMemo` in `CanvasPanel.tsx` — offset detection could follow the same pattern (though ideally set at creation time, not on every render)

### Integration Points
- `CanvasPanel.tsx` `defaultEdgeOptions` → affects ALL new edges unless per-edge overrides exist
- `useStore.ts` `addEdge` → per-edge override (markerEnd + offset for hydraulic; no markerEnd for thermal)
- `StreamNode.tsx` handle render loop → port polarity color
- `projectIO.ts` `reconstructInstanceCounters` → counter reconstruction on project load

</code_context>

<specifics>
## Specific Ideas

- User confirmed: colored port handles (port_in vs port_out) are for visual clarity at connection time, NOT for free-form endpoint repositioning. Reconnectable edge endpoints are explicitly out of scope.

</specifics>

<deferred>
## Deferred Ideas

- **Floating/draggable edge endpoints** (draw.io-style repositionable connection points) — noted for backlog, significant ReactFlow architecture change
- **Edge waypoints / manual path bending** — midpoint drag to create custom bends; related to the routing clarity goal but out of scope for this phase

</deferred>

---

*Phase: 42-edge-path-visual-overhaul*
*Context gathered: 2026-04-03*
