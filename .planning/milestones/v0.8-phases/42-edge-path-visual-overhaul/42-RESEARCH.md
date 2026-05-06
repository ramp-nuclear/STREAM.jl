# Phase 42: Edge & Path Visual Overhaul - Research

**Researched:** 2026-04-03
**Domain:** ReactFlow edge rendering, SVG markers, handle styling, Zustand store logic
**Confidence:** HIGH

## Summary

Phase 42 is a visual polish and bug-fix phase targeting five areas of the existing ReactFlow canvas: (1) adding filled arrowheads to hydraulic edges, (2) parallel edge routing with offset for bidirectional pairs, (3) FlowPort handle polarity coloring, (4) cursor CSS glitch fix, and (5) rename counter reconstruction bug fix. All changes are within the existing `gui/` codebase using established patterns.

The technical surface is well-understood. ReactFlow v12.10.2 (`@xyflow/react`) confirms support for `MarkerType.ArrowClosed`, `pathOptions.offset` on smoothstep edges, and per-edge `markerEnd`. The `addEdge` store action is the primary injection point for edge enrichment. The `reconstructInstanceCounters` bug is a straightforward regex fix. No new dependencies or libraries are needed.

**Primary recommendation:** Implement all five changes in two plans -- Plan 01 for edge rendering (arrowheads + parallel offset + project load re-enrichment), Plan 02 for handle polarity, cursor fix, and counter bug fix. All changes are to existing files only.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- D-01: Hydraulic (FlowPort) edges get filled arrowheads (MarkerType.ArrowClosed) at target end only, applied via markerEnd on the edge object in addEdge
- D-02: Thermal (ThermalPort, amber dashed) edges get no arrowheads -- thermal coupling is symmetric
- D-03: Keep smoothstep edge type; for bidirectional edge pairs, auto-detect and apply lateral offset (~20px) via pathOptions.offset
- D-04: Offset detection at addEdge time -- check if reverse edge already exists (same source/target handles swapped)
- D-05: No changes to thermal edge style beyond existing implementation
- D-06: port_in and port_out handles get distinct colors (blue-300 for in, blue-700 for out per UI-SPEC)
- D-07: Port direction derived from port.name (includes "in"/"out"); no registry schema changes
- D-08: Cursor glitch is CSS/pointer-events bug -- fix via CSS targeting .react-flow__handle
- D-09: reconstructInstanceCounters fix: use data.componentId.toLowerCase() as key, match ^<componentId_lower>_(\d+)$ pattern only

### Claude's Discretion
- Exact arrowhead size and color (UI-SPEC specifies 16x16, #b1b1b7)
- Exact colors for port_in vs port_out (UI-SPEC specifies blue-300/#93c5fd and blue-700/#1d4ed8)
- Symmetric vs asymmetric offset (UI-SPEC specifies symmetric +10/-10)
- CSS selector and property for cursor fix
- O(n) edge scan vs Set for offset detection

### Deferred Ideas (OUT OF SCOPE)
- Floating/draggable edge endpoints (significant ReactFlow architecture change)
- Edge waypoints / manual path bending
</user_constraints>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| @xyflow/react | 12.10.2 | ReactFlow canvas, edge rendering, MarkerType | Already installed; provides MarkerType.ArrowClosed, pathOptions.offset |
| zustand | (installed) | Store for addEdge, removeEdge, loadProject | Already used for all state management |
| react | 19.1.0 | UI framework | Already installed |

### Supporting
No new libraries needed. All changes use existing ReactFlow APIs and CSS.

### Alternatives Considered
None -- all decisions are locked.

## Architecture Patterns

### File Touch Map
```
gui/src/store/useStore.ts          # addEdge: markerEnd + offset; onEdgesChange: offset cleanup; loadProjectFromPath: re-enrichment
gui/src/components/StreamNode.tsx   # Handle polarity colors (port_in blue-300, port_out blue-700)
gui/src/lib/projectIO.ts           # reconstructInstanceCounters: componentId-based regex
gui/src/lib/__tests__/projectIO.test.ts  # Updated tests for counter fix
gui/src/index.css                  # Cursor fix CSS rule
gui/src/components/CanvasPanel.tsx  # Possibly defaultEdgeOptions (but per-edge override in addEdge is better)
```

### Pattern 1: Edge Enrichment in addEdge (existing pattern)
**What:** The `addEdge` store action already enriches edges with thermal styling by checking port types. Arrowhead and offset logic follows the same pattern.
**When to use:** Any time new edge properties need to be applied at creation time.
**Example:**
```typescript
// In addEdge, after rfAddEdge:
const styledEdges = newEdges.map((e) => {
  if (e.style) return e; // already styled (existing edge)
  
  // Check port types to determine hydraulic vs thermal
  const srcPort = srcComp.ports.find((p) => p.name === e.sourceHandle);
  const tgtPort = tgtComp.ports.find((p) => p.name === e.targetHandle);
  
  if (srcPort?.type === "ThermalPort" && tgtPort?.type === "ThermalPort") {
    // Thermal: amber dashed, NO markerEnd
    return { ...e, style: { stroke: "#f59e0b", strokeDasharray: "6 3" } };
  }
  
  // Hydraulic: add markerEnd
  return {
    ...e,
    markerEnd: {
      type: MarkerType.ArrowClosed,
      width: 16,
      height: 16,
      color: '#b1b1b7',
    },
  };
});
```

### Pattern 2: Parallel Edge Offset Detection
**What:** When adding an edge, scan existing edges for a reverse counterpart (same handles swapped). If found, apply symmetric pathOptions.offset to both.
**When to use:** Bidirectional edge pairs (A->B and B->A on same handle pair).
**Key detail:** ReactFlow's smoothstep edge type reads `edge.pathOptions.offset` directly -- verified in source. The property shifts the edge path laterally.
**Example:**
```typescript
// After creating the new edge with markerEnd:
const reverseIdx = currentEdges.findIndex(e =>
  e.source === connection.target &&
  e.target === connection.source &&
  e.sourceHandle === connection.targetHandle &&
  e.targetHandle === connection.sourceHandle
);

if (reverseIdx !== -1) {
  // Apply offset to existing edge
  currentEdges[reverseIdx] = {
    ...currentEdges[reverseIdx],
    pathOptions: { offset: 10 },
  };
  // Apply negative offset to new edge
  newEdge.pathOptions = { offset: -10 };
}
```

### Pattern 3: Edge Re-enrichment on Project Load
**What:** `loadProjectFromPath` deserializes edges from JSON. Edges saved before this phase lack markerEnd and pathOptions. Must re-apply enrichment after load.
**When to use:** Every project load.
**Key detail:** Create a pure helper function `enrichEdges(edges, nodes)` that applies markerEnd to hydraulic edges and detects/applies offsets to bidirectional pairs. Call it from `loadProjectFromPath` AND use it in `addEdge` to avoid logic duplication.

### Pattern 4: Offset Cleanup on Edge Removal
**What:** When an edge is removed, check if it was part of a bidirectional pair. If so, remove the offset from the surviving partner.
**Where:** `onEdgesChange` (handles keyboard delete) and `removeEdge` (handles programmatic removal).
**Key detail:** `onEdgesChange` receives `EdgeChange[]` with `type: "remove"`. Before applying changes, identify removed edges that have `pathOptions.offset`, find their partners, and clear the partner's offset.

### Anti-Patterns to Avoid
- **Setting markerEnd in defaultEdgeOptions:** Would apply to ALL edges including thermal. Must be per-edge in addEdge.
- **Checking edge.style.stroke to detect thermal edges at enrichment time:** Fragile. Check port types from the registry instead (already done in addEdge).
- **Mutating edges array in place in Zustand:** Always spread/map to create new references for React to detect changes.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SVG arrowheads | Custom SVG marker defs | `MarkerType.ArrowClosed` | ReactFlow handles SVG marker creation, positioning, and cleanup |
| Edge path offset | Custom edge component with manual path calculation | `pathOptions.offset` on smoothstep edges | Built into ReactFlow's smoothstep path calculation |
| Handle direction detection | Port registry `direction` field lookup | `port.name.includes("in")` / `port.name.includes("out")` | Already established in StreamNode.tsx (line 64); simpler and consistent |

## Common Pitfalls

### Pitfall 1: pathOptions Type on Edge Object
**What goes wrong:** TypeScript may not recognize `pathOptions` as a valid property on the Edge type.
**Why it happens:** The ReactFlow `Edge` type interface doesn't directly declare `pathOptions`. ReactFlow reads it via `'pathOptions' in edge ? edge.pathOptions : undefined` (confirmed in source).
**How to avoid:** Use type assertion or extend the Edge type. The runtime works regardless -- ReactFlow checks for the property dynamically.
**Warning signs:** TypeScript compile error on `edge.pathOptions`.

### Pitfall 2: Offset Cleanup Race with applyEdgeChanges
**What goes wrong:** `onEdgesChange` calls `applyEdgeChanges` which removes edges. If offset cleanup runs AFTER the removal, the partner edge lookup fails because the removed edge is already gone.
**Why it happens:** `applyEdgeChanges` applies all changes atomically.
**How to avoid:** Do offset cleanup BEFORE calling `applyEdgeChanges`. Scan the `changes` array for `type: "remove"`, find their partners in the CURRENT edges array, then apply changes plus partner modifications together.
**Warning signs:** Orphaned offset on a surviving edge after its partner is deleted.

### Pitfall 3: markerEnd Serialization in .streamgui Files
**What goes wrong:** `markerEnd` objects serialize to JSON fine, but older saved projects lack them. Loading such a file leaves hydraulic edges without arrowheads.
**Why it happens:** Projects saved before Phase 42 have no markerEnd property.
**How to avoid:** The `enrichEdges` helper called from `loadProjectFromPath` must unconditionally re-apply markerEnd and offset detection, treating the loaded edges as raw data.
**Warning signs:** Arrowheads disappear after loading a saved project.

### Pitfall 4: Counter Reconstruction Regex Escaping
**What goes wrong:** `componentId` values like `ChannelAndContacts` contain no special regex characters, but future component IDs might.
**Why it happens:** Using `new RegExp('^' + key + '_(\\d+)$')` with unescaped user-derived strings.
**How to avoid:** The current component IDs (Pump, Channel, ChannelAndContacts, etc.) are safe. But escapeRegex the key for robustness, or use a string split approach instead: `instanceName.startsWith(key + "_") && !isNaN(parseInt(suffix))`.
**Warning signs:** Test failure if a component ID contains regex special chars.

### Pitfall 5: Stale Closure in enrichedEdges useMemo
**What goes wrong:** `enrichedEdges` in CanvasPanel.tsx applies dimming but doesn't know about markerEnd or pathOptions. If it spreads edge style and overwrites markerEnd, arrowheads disappear in non-Both layers.
**Why it happens:** The dimming logic spreads `...edge` then overrides `style`. This is safe because markerEnd is a top-level edge property separate from style.
**How to avoid:** Verify that the `enrichedEdges` useMemo in CanvasPanel.tsx preserves `markerEnd` and `pathOptions` when adding dimming opacity. The current code spreads `...edge` which preserves all properties -- just verify it stays that way.
**Warning signs:** Arrowheads or offsets disappear when switching layer views.

## Code Examples

### Arrowhead Application in addEdge
```typescript
// Source: @xyflow/react v12.10.2 MarkerType enum
import { MarkerType } from "@xyflow/react";

// Per-edge markerEnd for hydraulic edges:
const hydraulicMarker = {
  type: MarkerType.ArrowClosed,
  width: 16,
  height: 16,
  color: '#b1b1b7',
};
```

### pathOptions.offset for Parallel Edges
```typescript
// Source: @xyflow/system SmoothStepPathOptions type
// Verified: node_modules/@xyflow/system/dist/esm/types/edges.d.ts
// SmoothStepPathOptions = { offset?: number; borderRadius?: number; stepPosition?: number; }

// Applied directly on the edge object:
const edgeWithOffset = { ...edge, pathOptions: { offset: 10 } };
// ReactFlow reads: 'pathOptions' in edge ? edge.pathOptions : undefined
```

### Handle Polarity Styling in StreamNode
```typescript
// Source: 42-UI-SPEC.md FlowPort Handle Polarity Colors
const FLOW_IN_BG = "#93c5fd";     // blue-300
const FLOW_IN_BORDER = "#3b82f6"; // blue-500
const FLOW_OUT_BG = "#1d4ed8";    // blue-700
const FLOW_OUT_BORDER = "#1e40af"; // blue-800

// In FlowPort handle render:
const isInPort = port.name.includes("in");
const handleStyle = {
  background: isInPort ? FLOW_IN_BG : FLOW_OUT_BG,
  border: `1.5px solid ${isInPort ? FLOW_IN_BORDER : FLOW_OUT_BORDER}`,
  ...(dimFlowHandles ? { opacity: 0.2, pointerEvents: "none" as const } : {}),
};
```

### Fixed reconstructInstanceCounters
```typescript
// Source: D-09 in 42-CONTEXT.md
export function reconstructInstanceCounters(nodes: Node[]): Record<string, number> {
  const counters: Record<string, number> = {};
  for (const node of nodes) {
    const data = node.data as { componentId?: string; instanceName?: unknown };
    if (!data?.componentId || typeof data.instanceName !== "string") continue;
    const key = data.componentId.toLowerCase();
    const pattern = new RegExp(`^${key}_(\\d+)$`);
    const match = data.instanceName.match(pattern);
    if (match) {
      const num = parseInt(match[1], 10);
      counters[key] = Math.max(counters[key] ?? 0, num);
    }
  }
  return counters;
}
```

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | vitest (via vitest.config.ts) |
| Config file | gui/vitest.config.ts |
| Quick run command | `cd gui && npx vitest run --passWithNoTests` |
| Full suite command | `cd gui && npx vitest run --passWithNoTests` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SC-01 | Arrowhead on hydraulic edge | unit | `cd gui && npx vitest run src/store/__tests__/useStore.test.ts -t "arrowhead"` | Needs update |
| SC-02 | No arrowhead on thermal edge | unit | `cd gui && npx vitest run src/store/__tests__/useStore.test.ts -t "thermal"` | Needs update |
| SC-03 | Parallel edge offset | unit | `cd gui && npx vitest run src/store/__tests__/useStore.test.ts -t "offset"` | Wave 0 |
| SC-04 | Offset cleanup on removal | unit | `cd gui && npx vitest run src/store/__tests__/useStore.test.ts -t "offset cleanup"` | Wave 0 |
| SC-05 | Handle polarity colors | component | Manual visual verification | N/A (visual) |
| SC-06 | Cursor CSS fix | manual | Manual drag test | N/A (CSS) |
| SC-07 | Counter reconstruction | unit | `cd gui && npx vitest run src/lib/__tests__/projectIO.test.ts -t "reconstructInstanceCounters"` | Exists, needs update |
| SC-08 | Edge re-enrichment on load | unit | `cd gui && npx vitest run src/lib/__tests__/projectIO.test.ts -t "enrichEdges"` | Wave 0 |

### Sampling Rate
- **Per task commit:** `cd gui && npx vitest run --passWithNoTests`
- **Per wave merge:** `cd gui && npx vitest run --passWithNoTests`
- **Phase gate:** Full suite green before /gsd:verify-work

### Wave 0 Gaps
- [ ] Store tests for markerEnd application on hydraulic edges (addEdge)
- [ ] Store tests for pathOptions.offset on bidirectional pairs
- [ ] Store tests for offset cleanup on edge removal
- [ ] projectIO tests for componentId-based counter reconstruction (update existing tests)
- [ ] Pure function tests for enrichEdges helper (if extracted)

## Sources

### Primary (HIGH confidence)
- @xyflow/react v12.10.2 installed in gui/node_modules -- MarkerType.ArrowClosed, pathOptions.offset verified from source
- @xyflow/system edge types -- SmoothStepPathOptions { offset?: number } confirmed
- ReactFlow edge renderer source -- reads `'pathOptions' in edge ? edge.pathOptions : undefined`
- gui/src/store/useStore.ts -- addEdge action (lines 329-378), removeEdge (line 380), onEdgesChange (line 245), loadProjectFromPath (line 521)
- gui/src/components/StreamNode.tsx -- handle rendering (full file, 90 lines)
- gui/src/lib/projectIO.ts -- reconstructInstanceCounters (lines 138-160)
- gui/src/index.css -- current CSS (no ReactFlow handle rules)

### Secondary (MEDIUM confidence)
- UI-SPEC.md design contract -- color values, arrowhead dimensions, offset values

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - all APIs verified from installed node_modules source
- Architecture: HIGH - all edit points identified, existing patterns well-understood
- Pitfalls: HIGH - verified edge rendering pipeline and type system constraints

**Research date:** 2026-04-03
**Valid until:** 2026-05-03 (stable -- no ReactFlow upgrade planned)
