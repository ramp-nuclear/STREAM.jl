# Phase 64: Connection routing - Research

**Researched:** 2026-05-14
**Domain:** ReactFlow custom-node handle routing + Zustand-derived geometry + custom edge geometry tweaks (TS/React/`@xyflow/react@^12.10.2`)
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Recomputation & Persistence**
- **D-01:** Autoflip recomputes **live during drag**. Every position update re-evaluates handle sides. ReactFlow already re-renders on drag; the marginal cost is the autoflip function itself.
- **D-02:** Resolved side is **pure derivation** — a function of `(connections, node positions)` computed each render. Nothing new added to node data; nothing serialized to `.scp`. Same file always renders identically because positions + connections are already persisted.
- **D-03:** A `useMemo` / Zustand selector cache is allowed as an implementation detail (perf), but the cache is NOT persisted.
- **D-04:** Anchor glyphs (introduced in Phase 63.1) **follow the autoflipped handle side**. When `port_in` flips to bottom, its anchor glyph renders at the bottom too. Anchor and handle never decouple visually.
- **D-05:** Layer dimming is purely visual — autoflip **always** considers ALL connections regardless of `activeLayer`. Switching between Hydraulic and Thermal layers never re-routes edges.

**Anti-Parallel Offset Polish**
- **D-06:** Anti-parallel offset for bidirectional pairs **is in scope** for Phase 64 (closes Example-1 X-cross fully). Implemented as a custom-edge tweak — not architectural.
- **D-07:** Offset is a **small constant perpendicular bow of ±8px** on the smoothstep midpoint. No distance-proportional scaling. Not user-tunable in v1.2 (no Settings entry).
- **D-08:** "Bidirectional pair" detection rule: two edges where `(sourceNode, targetNode)` of one == `(targetNode, sourceNode)` of the other. Any port pair counts — port identity does not need to match.

**Asymmetric Placement Geometry**
- **D-09:** When both FlowPorts share a side, position them at **25% / 75%** along that side. Scales with node width; uses ReactFlow handle `style.left` / `style.top` percentage offsets.
- **D-10:** "First port toward leading end" follows **reading direction**:
  - Top side: `port_in` left (25%), `port_out` right (75%)
  - Bottom side: `port_in` left (25%), `port_out` right (75%)
  - Left side: `port_in` top (25%), `port_out` bottom (75%)
  - Right side: `port_in` top (25%), `port_out` bottom (75%)
  Always reads in→out left-to-right or top-to-bottom — matches §3.3 spec verbatim.
- **D-11:** Default (zero connections): handles render at their **registry-default sides** — no autoflip evaluation at all until at least one connection exists on the port. Per §3.3.
- **D-12:** Asymmetric placement does **NOT** apply to thermal pairs — they are always on opposing faces by construction (per §3.4).

**Edge Cases**
- **D-13:** Tie-breaking when `|dx| ≈ |dy|`: **prefer horizontal**. Use `|dx| ≥ |dy| → horizontal, else vertical`. Deterministic; no hysteresis state.
- **D-14:** **No dead zone** for live-drag axis switching — strict comparison. Flicker risk at exactly 45° is a 1-pixel band; unlikely in real drags.
- **D-15:** Crowded-edge case (CAC where flow + thermal both want the same axis → 4 handles on 2 edges): **interleave handles AND surface a topology-hint validation chip**. Interleaving: flow at 25%/75% (already locked by D-09); thermal centered at 50% on each face. Validation chip: yellow / non-blocking — "Hydraulic and thermal neighbors on same axis — consider repositioning." Wired into the existing validation panel surface used by Phase 63.1 BC errors.
- **D-16:** Neighbor anchor for the `dx` / `dy` computation is **node center to node center** (`x + width/2, y + height/2`). Cheap, stable, doesn't depend on which handle is involved.

### Claude's Discretion
- Internal data shape of the autoflip selector (Zustand selector vs `useMemo` vs custom hook) — pick whatever fits cleanly with the current `StreamNode.tsx` rendering path.
- Exact name and location of the autoflip function (e.g. `gui/src/lib/autoflip.ts` vs colocation in `StreamNode.tsx`) — planner decides.
- Validation chip wiring details (which Zustand store slice surfaces the topology hint) — follow Phase 63.1 BC-error precedent (selector-derived per D-15/D-19 of Phase 63.1).
- Test surface: unit tests for the geometric rules + a small set of representative ReactFlow layouts covering the §3.3 examples (Example 1 X-cross, Examples 3-4 vertical stack, Example 2 long return, the CAC crowded-edge case).

### Deferred Ideas (OUT OF SCOPE)
- **Per-component rotation override** (right-click → Rotate 90°) — explicitly rejected; future phase if autoflip misbehaves.
- **Manual handle override** (user drags a port to a different side) — not in v1.2 scope.
- **Distance-proportional anti-parallel bow** — defer; constant ±8px only.
- **User-tunable bow amount in Settings panel** — defer; no Settings entry.
- **10° dead zone / hysteresis for axis switching** — defer; add only if real-world flicker observed.
- **Thermal handle visual restyle** (yellow rotated diamond → cleaner glyph) — Phase 72 design system.
- **Auto-Layout** (full-graph reflow) — Phase 65 will stub the menu entry only.
</user_constraints>

## Summary

Phase 64 is a **two-file localized change** with one new pure-logic module: rework `StreamNode.tsx`'s handle-render section (`flowPorts.map`, `thermalPorts.map`) so the `side` consumed by `sideToPosition[…]` is no longer the registry-default but a **live-derived value** from a new `autoflip` pure function that takes `(nodeId, portName, nodes, edges, components)` and returns `{ side: "left"|"right"|"top"|"bottom", offsetPct?: number }`. The same data feeds the anchor glyph (already co-located in `FlowPortHandle`, D-04 is satisfied by construction). `HydraulicEdge.tsx` gains a bidirectional-pair detection + ±8px perpendicular bow (D-06..D-08). One validation tag (`topology-axis-collision`) joins the Phase 63.1 selector-derived validator family for D-15.

The registry already carries the inputs Phase 64 needs (`default_axis`, `pair_with` on thermal pairs; `side` on FlowPorts as the default). The Zustand store already exposes `nodes[]` (with `node.position: {x, y}`) and `edges[]` as plain arrays — no new slice is required. ReactFlow's documented API supports the 25%/75% asymmetric placement via inline `style.left`/`style.top` on `<Handle>` while keeping `position={Position.Bottom}` set; the library computes edge endpoints from the offset handles.

**Primary recommendation:** Create `gui/src/lib/autoflip.ts` exposing two pure functions, `resolveFlowPortSide(...)` and `resolveThermalPairAxis(...)`, plus a `detectAxisCollision(nodeId, ...)` predicate for the D-15 validation chip. Consume them inside `StreamNode.tsx` via `useStore` selector that returns a stable primitive (the resolved side string). Add `useUpdateNodeInternals(id)` once per `StreamNode` instance — call it inside a `useEffect` keyed on the resolved-side values to force ReactFlow to re-measure handle positions on flip. Patch `HydraulicEdge.tsx` to look up its own anti-parallel sibling via a Zustand `getState()` read (no hook in the edge path; edges re-render at high frequency). Plan to test the rules as pure functions (cheap) plus three or four ReactFlow-rendered layouts asserting visible handle Position values (already-precedented test pattern from `StreamNode.test.tsx`).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Geometric autoflip rule (which side does each FlowPort prefer?) | Pure TS module (`gui/src/lib/autoflip.ts`) | — | Trivially testable, no React/ReactFlow/Zustand dependency, mirrors `gui/src/lib/layers.ts` and `gui/src/lib/selectors/nodeErrors.ts` precedent |
| Thermal-pair axis selection (which axis hosts the pair?) | Pure TS module (`gui/src/lib/autoflip.ts`) | — | Same as above; the pair-axis rule is a strict variant of the FlowPort rule |
| Asymmetric same-side placement (25%/75% offset) | Pure TS module + `StreamNode.tsx` consumer | — | Rule lives in autoflip; the `style.left`/`style.top` injection happens at handle render time |
| Anti-parallel bow detection (is this edge half of a bidirectional pair?) | `HydraulicEdge.tsx` render-time read of `useStore.getState().edges` | Pure TS helper `findAntiParallelSibling(edge, edges)` | Edges re-render every drag frame — a hook-free `getState()` read avoids subscription churn; the predicate itself is pure |
| Anti-parallel ±8px bow application (geometric perturbation) | `HydraulicEdge.tsx` (custom edge) | — | smoothstep path is built inside the edge component; the bow tweak is local |
| Validation chip (D-15 topology-axis-collision) | `gui/src/lib/selectors/topologyHints.ts` (new selector, sibling of `nodeErrors.ts`) | Existing validation panel UX | Phase 63.1 D-19 locked the selector-derived validator pattern; Phase 64 extends it |
| Anchor glyph following autoflip (D-04) | `FlowPortHandle` (already in `StreamNode.tsx`) | — | Anchor glyph reads the same resolved `side` value as the `<Handle>`; co-location is structural |
| Registry-default fallback (zero connections, D-11) | `gui/src/lib/autoflip.ts` (returns `port.side` when no edges touch the port) | — | Pure logic; no special case at render time |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `@xyflow/react` | `^12.10.2` (verified — `gui/package.json:18`) | Canvas, custom nodes, custom edges, `Handle` component, `Position` enum, `getSmoothStepPath`, `useUpdateNodeInternals` | Already the canvas framework; Phase 64 stays inside its API surface |
| `zustand` | `^5.0.12` (verified — `gui/package.json:28`) | `nodes[]`, `edges[]`, `activeLayer` state; **read-only** consumer in Phase 64 | Existing store; no new slice needed (D-02 — pure derivation, no persistence) |
| `react` | `^19.1.0` (verified — `gui/package.json:23`) | `useMemo`, `useEffect`, `useCallback`, sub-component hook isolation | Already in use; Phase 64 introduces no new React surface beyond `useUpdateNodeInternals` |
| `vitest` | `^4.1.2` (verified — `gui/package.json:48`) | Unit tests for pure rules; `@testing-library/react` (`^16.3.2`) for the rendered-handle assertions | Project test runner; `gui/src/components/__tests__/StreamNode.test.tsx` is the precedent template |
| `happy-dom` | `^20.8.9` (verified — `gui/package.json:41`) | DOM environment for rendered-handle tests via `@vitest-environment happy-dom` docblock | Already adopted in `StreamNode.test.tsx:1` |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `lucide-react` | `^1.7.0` | Anchor glyph icon (already used at `StreamNode.tsx:3,176`) | Reused — no new icon added in Phase 64 |
| `@testing-library/react` | `^16.3.2` | Rendered-handle test assertions (`container.querySelectorAll('.react-flow__handle')`) | The two example tests we will add |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Pure-function `autoflip.ts` module | Colocate logic inside `FlowPortHandle` | Rejected — D-04 requires both the handle *and* the anchor glyph to consume the same resolved side; pulling logic into a sub-component duplicates it. A pure module keeps both consumers consistent and testable in isolation. |
| `useStore` selector for `autoflip` | `getState()` direct read | Rejected for the handle path — we need React to re-render when neighbor positions change. The edge path (anti-parallel sibling detection) is the only place `getState()` is appropriate because edges re-render on every drag frame anyway via their `sourceX/Y/targetX/Y` props. |
| Single combined "topology hint" validation slot | Separate selector | Use the existing selector-derived validator pattern from Phase 63.1 (`gui/src/lib/selectors/nodeErrors.ts`). A new `gui/src/lib/selectors/topologyHints.ts` that returns `string[]` and is composed with `selectNodeErrors` into the existing red/yellow-chip path. |

**No new packages required.** Phase 64 ships entirely on the existing dependency set.

**Version verification:** All versions read from `gui/package.json` on 2026-05-14 — no remote npm registry call needed. `@xyflow/react` 12.x is the current React Flow major series.

## Architecture Patterns

### System Architecture Diagram

```
                     [Zustand store: nodes[], edges[]]
                                |
                                | (subscribe via useStore)
                                v
                    +---------------------------+
                    |  StreamNode.tsx (custom)  |
                    |  - component meta lookup  |
                    |  - selects activeLayer    |
                    +---------------------------+
                                |
       +------------------------+------------------------+
       |                        |                        |
       v                        v                        v
[FlowPortHandle]         [thermalPorts.map]        [bcPorts.map]
       |                        |                        |
       | calls                  | calls                  | (unchanged in P64)
       v                        v
+------------------+   +-------------------------+
| autoflip.ts      |   | autoflip.ts             |
| resolveFlowPort  |   | resolveThermalPairAxis  |
| Side(nodeId,     |   | (nodeId, defaultAxis,   |
|   portName,      |   |  pairWith, nodes,edges) |
|   nodes, edges,  |   +-------------------------+
|   getComponent)  |              |
+------------------+              |
       |                          |
       v                          v
returns:                  returns:
{ side, offsetPct? }      { axisSides: { left/right OR top/bottom } }
       |                          |
       v                          v
   <Handle position=sideToPosition[side]
           style={{ [side]: offsetPct + "%" }} ... />
                                |
                                | (handle position changed?)
                                v
                useUpdateNodeInternals(nodeId) ← useEffect keyed on side string
                                |
                                v
                  ReactFlow recomputes edge endpoints
                                |
                                v
                  +---------------------------+
                  |  HydraulicEdge.tsx        |
                  |  - inbound: sourceX/Y,    |
                  |    targetX/Y, source,     |
                  |    target                 |
                  |  - reads getState().edges |
                  |    to find anti-parallel  |
                  |    sibling                |
                  |  - applies ±8px           |
                  |    perpendicular bow      |
                  +---------------------------+
                                |
                                v
                       getSmoothStepPath(...)
                                |
                                v
                            <BaseEdge />

Validation surface (D-15):
[Zustand bcMode/nodes/edges] → selectTopologyHints(state, nodeId) → existing chip path
```

### Recommended Project Structure

```
gui/src/
├── lib/
│   ├── autoflip.ts             # NEW — pure geometric rules
│   ├── autoflip.test.ts        # NEW — unit tests for the rules
│   └── selectors/
│       └── topologyHints.ts    # NEW — D-15 selector (sibling of nodeErrors.ts)
├── components/
│   ├── StreamNode.tsx          # PATCH — FlowPortHandle + thermal map consume autoflip
│   ├── HydraulicEdge.tsx       # PATCH — anti-parallel offset (D-06..D-08)
│   └── __tests__/
│       ├── StreamNode.autoflip.test.tsx   # NEW — render assertions on Example 1..4 layouts
│       └── HydraulicEdge.bow.test.tsx     # NEW — anti-parallel bow path geometry
```

Note: `gui/src/lib/selectors/topologyHints.ts` mirrors the layout established by Phase 63.1's `gui/src/lib/selectors/nodeErrors.ts` (95 lines, pure, zero React/zustand imports — see file). New tests follow the precedent set by `gui/src/components/__tests__/StreamNode.test.tsx`.

### Pattern 1: Pure-function selector consumed via a primitive-returning `useStore` hook

**What:** Phase 63.1 D-15/D-19 locked the pattern: validators and derived state are pure `(state, nodeId) => primitive | string[]` functions; React consumers wrap them in `useStore(useCallback(s => fn(s, id).length > 0, [id]))` and read a **primitive boolean**, never a fresh object/array, to keep zustand shallow equality stable.

**When to use:** Every Phase 64 derivation that hits the StreamNode render path.

**Example (from `gui/src/components/StreamNode.tsx:154-160` — the anchor-presence read):**

```typescript
// Source: gui/src/components/StreamNode.tsx
const hasAnchor = useStore(
  useCallback(
    (s: { anchors: Record<string, { portField: string } | undefined> }) =>
      s.anchors[nodeId]?.portField === portFieldKey,
    [nodeId, portFieldKey],
  ),
);
```

**Phase 64 adaptation (FlowPort side resolution):**

```typescript
// Pattern for Phase 64 — selector returns a primitive side string
import { resolveFlowPortSide } from "@/lib/autoflip";

const resolvedSide = useStore(
  useCallback(
    (s: { nodes: Node[]; edges: Edge[] }) =>
      resolveFlowPortSide(s.nodes, s.edges, nodeId, port.name, port.side ?? "left", getComponent),
    [nodeId, port.name, port.side],
  ),
);
```

Zustand 5.x's default `Object.is` equality on the returned string keeps re-renders bounded — handle re-renders only when its resolved side changes, not on every neighbor position tick.

### Pattern 2: `useUpdateNodeInternals` after dynamic handle reposition

**What:** ReactFlow caches each node's handle geometry on its first measurement. When a handle's `Position` or inline-style offset changes, **the cache goes stale and edges stick to the old endpoints** [CITED: reactflow.dev/api-reference/hooks/use-update-node-internals]. The cure is `useUpdateNodeInternals` — calling `updateNodeInternals(nodeId)` tells ReactFlow to re-measure.

**When to use:** Every `StreamNode` instance, in a `useEffect` keyed on the resolved-side strings for all of its ports.

**Example (from React Flow docs):**

```typescript
// Source: https://reactflow.dev/api-reference/hooks/use-update-node-internals
import { useUpdateNodeInternals } from "@xyflow/react";

const updateNodeInternals = useUpdateNodeInternals();

useEffect(() => {
  updateNodeInternals(id);
}, [id, resolvedSideKey, updateNodeInternals]);
// resolvedSideKey = JSON-stringified or simple-concatenated string of every
// port's resolved side; changes only when at least one port flips.
```

**Pitfall:** A known issue [CITED: github.com/xyflow/xyflow/issues/2008] is that an immediate `updateNodeInternals` call inside a render can race with React's state-batching and leave edges stuck. The community workaround is `setTimeout(() => updateNodeInternals(id), 0)` to defer past the current microtask. **Plan defensively:** start without the timeout (cleaner); if edges visibly lag on drag during smoke testing, switch to the deferred form.

### Pattern 3: Read-only edge enrichment via `getState()` (no hook subscription)

**What:** Edges in ReactFlow re-render on every drag frame because their `sourceX/Y/targetX/Y` props change. Subscribing to the full edges array via `useStore(s => s.edges)` inside an edge component would trigger a render storm. The pattern is to call `useStore.getState().edges` **synchronously inside the render function** for read-only sibling detection — ReactFlow's own re-render cycle drives consistency.

**When to use:** `HydraulicEdge.tsx`'s bidirectional-sibling lookup.

**Example pattern:**

```typescript
// Source: pattern derived from gui/src/components/CanvasPanel.tsx:28 (getPortType)
// and BCEdge.tsx:59-83 (primitive-returning subscription for label state)
function HydraulicEdge({ source, target, sourceX, sourceY, targetX, targetY, sourcePosition, targetPosition, id, style, markerEnd }: EdgeProps) {
  // Synchronous read — no subscription. ReactFlow re-runs this render whenever
  // the edge's own props change, which happens on every drag tick already.
  const hasAntiParallelSibling = useStore.getState().edges.some(
    (e) => e.id !== id && e.source === target && e.target === source,
  );
  const bow = hasAntiParallelSibling ? 8 : 0;
  // ... bend smoothstep midpoint by ±bow px perpendicular to (source → target) ...
}
```

`CanvasPanel.tsx:27-34` (`getPortType`) already uses `useStore.getState()` for read-only lookups in a non-render context. The same pattern applies inside an edge body for a per-frame read.

### Anti-Patterns to Avoid

- **Storing `resolvedSide` in node.data:** Forbidden by D-02. The pure-derivation contract keeps `.scp` files reproducible across sessions and avoids stale state when neighbors move.
- **Subscribing to the full `edges` array inside `HydraulicEdge`:** Triggers a re-render storm at drag time. Use `getState()` synchronously.
- **Returning a fresh object from a `useStore` selector** (e.g. `useStore(s => ({ side: ..., offset: ... }))`): zustand's shallow equality will think every render is a change. Either return a primitive string (preferred) or memoize the selector output. The codebase precedent (`StreamNode.tsx:154-160`, `BCEdge.tsx:59-83`) is **primitive return only**.
- **Hand-rolling a "smart Manhattan router":** Out of scope per CONTEXT — smoothstep stays. Phase 64 changes *where* edges enter and exit nodes, not how they route between.
- **`useUpdateNodeInternals` inside the inner `FlowPortHandle` sub-component:** Each handle would call it for every port; one call per node per render storm. Hoist it into the outer `StreamNode` body, key the `useEffect` on a concatenated string of all resolved sides.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Smoothstep edge routing | A custom Manhattan router | `getSmoothStepPath` from `@xyflow/react` | Already in `HydraulicEdge.tsx:19`; CONTEXT keeps it. ReactFlow handles waypoints, rounded corners, and centerline math. |
| Handle measurement on dynamic position changes | A `getBoundingClientRect` loop | `useUpdateNodeInternals` | Documented ReactFlow API; the community has battle-tested it across the issues we cited. |
| Edge endpoint computation when handle offsets via `style.left` | Manual `sourceX`/`sourceY` recalculation | ReactFlow computes from the rendered handle DOM position automatically | [CITED: reactflow.dev/learn/customization/handles] explicitly documents inline-style offset as the supported multiple-handles-per-side technique. |
| Node-position subscription | A new `nodePositions` slice | `useStore(s => s.nodes)` (already there) with primitive-returning selector | Existing store; no new slice needed (D-02). `nodes[i].position.{x,y}` is the canonical position field — set by ReactFlow's `onNodesChange` → `applyNodeChanges` in `useStore.ts:1010`. |
| Validation chip plumbing | A new "warnings" Zustand slice | New pure selector `selectTopologyHints(state, nodeId)` | Phase 63.1 D-15/D-19 locked the selector-derived pattern. `gui/src/lib/selectors/nodeErrors.ts` is the template (95 lines). |

**Key insight:** ReactFlow's `<Handle>` + `useUpdateNodeInternals` + `getSmoothStepPath` together provide every primitive Phase 64 needs. The phase is **glue logic** — a pure geometric rule and three integration points (StreamNode handle render, HydraulicEdge sibling detection, validation selector). There is no general-purpose graph-layout library to reach for, and `dagre` / `elkjs` (full-graph layout) would be a different feature (deferred as "Auto-Layout" in Phase 65).

## Runtime State Inventory

> Phase 64 is a **rendering/derivation change only**. No stored state changes. The categories below are answered for completeness.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — D-02 forbids persistence of resolved sides. `.scp` schema unchanged. | None |
| Live service config | None — pure client-side TS/React. | None |
| OS-registered state | None. | None |
| Secrets/env vars | None. | None |
| Build artifacts | `gui/dist/` will be rebuilt on next `npm run build`; no install-time artifacts persist. | None — dev-loop only |

**Nothing found in any category requires migration.** Phase 64's contract is "open the same file, see prettier edges" — the persisted `.scp` already encodes `nodes[].position` and `edges[].source/target/sourceHandle/targetHandle`, which are sufficient inputs for autoflip.

## Common Pitfalls

### Pitfall 1: ReactFlow caches handle geometry; edges stick to stale endpoints

**What goes wrong:** A `<Handle>`'s `position` prop changes from `Position.Right` to `Position.Bottom` (or its `style.left` shifts from `50%` to `25%`), but the connected edge keeps drawing to the old position.
**Why it happens:** ReactFlow measures handle DOM positions **once** when a node mounts and caches them. Subsequent inline-style changes are invisible to the cache.
**How to avoid:** Call `useUpdateNodeInternals(nodeId)` inside a `useEffect` keyed on the resolved-side string for every port of that node. One effect per node, fires only when at least one port flips.
**Warning signs:** Edges visibly disconnected from handles after dragging a neighbor; edge endpoint visually "snaps back" when you click elsewhere (forcing a re-render).
**Sources:** [CITED: reactflow.dev/api-reference/hooks/use-update-node-internals], [CITED: github.com/xyflow/xyflow/issues/2008]

### Pitfall 2: `useUpdateNodeInternals` race with state batching

**What goes wrong:** Even after calling `updateNodeInternals(id)`, edges still occasionally stick to old positions, especially after rapid drag motions.
**Why it happens:** React batches state updates; the `updateNodeInternals` call can execute before ReactFlow's internal node-measurement loop has seen the new handle DOM. Issue #2008 documents this; the workaround is `setTimeout(() => updateNodeInternals(id), 0)` to defer past the current microtask.
**How to avoid:** Start without the timeout (cleaner code). If smoke testing reveals lag, switch to the deferred form. **Document this as a known pitfall in the plan so the executor knows what to test for.**
**Warning signs:** Mostly-fine edges, but occasional "stuck endpoint" after very fast drag releases.
**Source:** [CITED: github.com/xyflow/xyflow/issues/2008]

### Pitfall 3: Fresh-object selector → re-render storm

**What goes wrong:** `useStore(s => ({ side: resolveFlowPortSide(...), offsetPct: ... }))` returns a new object every call. Zustand's default `Object.is` equality flags every render as a change → React re-renders the handle on every store update (anywhere in the app), causing performance death and the maximum-update-depth loops that bit Phase 63.1 (see `StreamNode.tsx:113` comment).
**Why it happens:** Object/array literals never satisfy reference equality.
**How to avoid:** **Return a primitive.** Encode `(side, offsetPct)` as a string like `"bottom@25"` if you must, or split into two selectors each returning a string/number. Phase 63.1's `hasAnchor` (StreamNode.tsx:154-160) and `hasBCError` (StreamNode.tsx:199-204) are the templates.
**Warning signs:** Browser DevTools "Maximum update depth exceeded" warnings; CPU pegged on cursor move.

### Pitfall 4: Anti-parallel detection across all edge types

**What goes wrong:** A hydraulic forward edge between two CACs has a thermal return edge between the same two nodes (CAC topology with shared plate). `HydraulicEdge` detects "anti-parallel sibling" and bows itself — visually wrong because the sibling is a different edge family.
**Why it happens:** D-08's "(sourceNode, targetNode) swap" rule does not filter by edge type.
**How to avoid:** Filter the sibling lookup to **same edge type only** — `e.type === "hydraulicEdge"`. CONTEXT D-08 says "any port pair counts" — interpret as "any FlowPort↔FlowPort port pair within the hydraulic family." Re-confirm with user during planning if ambiguous; this research interprets it as same-family.
**Warning signs:** Random bows on edges that don't have a hydraulic sibling.

### Pitfall 5: Layer-dimmed neighbors must still influence autoflip

**What goes wrong:** User switches to Thermal layer; hydraulic edges are dimmed (`enrichedEdges` in `CanvasPanel.tsx:78-93` sets `opacity: 0.15`). Autoflip rule sees only the active layer and re-routes thermal edges to ignore the dimmed flow neighbors.
**Why it happens:** Dimming is a render-time CSS overlay (`opacity: 0.15`); the underlying `edges` array remains complete. But a careless implementation could filter by `e.style?.stroke === "#f59e0b"` or similar.
**How to avoid:** D-05 locks this. The autoflip function takes the **raw** `nodes[]` and `edges[]` from the store — never the `enrichedEdges` from `CanvasPanel`. `enrichedEdges` is a render-time decoration only.
**Warning signs:** Edges visibly re-routing when the user toggles layers.

### Pitfall 6: CAC's thermal ports don't have a `side` field — current behavior is undefined

**What goes wrong:** Look at registry — `gui/src/registry/components.json:116-117` declares CAC's thermal ports with only `default_axis` and `pair_with`, no `side`. `StreamNode.tsx:276` reads `port.side!` (non-null assertion) → today's runtime gets `undefined` → `sideToPosition[undefined]` → `undefined` → `<Handle position={undefined}>`. ReactFlow likely falls back to its own default. This is the visual bug Phase 64 fixes for thermal ports.
**Why it happens:** Phase 61 staged the schema (the `default_axis` field) but did NOT staged the render-side consumer; that consumer is Phase 64's job.
**How to avoid:** Plan a **strict invariant**: after Phase 64, every `<Handle>` in `StreamNode.tsx` resolves to a defined Position. Add an assertion or fallback (`?? sideToPosition["left"]`) and a unit test that walks every component in the registry and renders it with no edges to confirm all handles get a real Position.
**Warning signs:** Console warnings about invalid `Position` from ReactFlow; thermal handles rendering at the top-left corner of the node.

### Pitfall 7: `addNode` default position causes deterministic edge re-route at first connection

**What goes wrong:** `useStore.addNode` at `useStore.ts:1051-1076` places new nodes at the provided position (no offset). The first connection drawn from a new node will autoflip both endpoints; if the user wasn't expecting this, the visual change can surprise. Not a bug — but document.
**How to avoid:** Plan can include a brief note in the human-verify checkpoint: "First connection to/from a new node may flip its handles — expected."

### Pitfall 8: 25%/75% on left/right side uses `top` not `left`

**What goes wrong:** When both `port_in` and `port_out` flip to the LEFT side, D-10 says "port_in top, port_out bottom." The percentage is along the **vertical** axis — so the inline style is `{ top: '25%' }` (port_in) and `{ top: '75%' }` (port_out). A reflexive `{ left: '25%' }` would push handles off the node horizontally.
**How to avoid:** The autoflip return shape MUST encode "which percentage axis," not just a number. Recommended:
```ts
type ResolvedHandle = { position: Position; offsetStyle: { left?: string; top?: string } | undefined };
```
Or compute it inline: `offsetStyle = side === "left" || side === "right" ? { top: pct } : { left: pct }`.

## Code Examples

Verified patterns to follow:

### Resolving FlowPort side (pure rule, no React)

```typescript
// Source: pattern synthesized from CONTEXT D-13/D-16 + StreamNode.tsx:212-269
// File: gui/src/lib/autoflip.ts (new)

import type { Node, Edge } from "@xyflow/react";
import type { ComponentDefinition } from "../registry/types";

export type Side = "left" | "right" | "top" | "bottom";

function nodeCenter(n: Node): { x: number; y: number } {
  // ReactFlow stores position as the top-left corner; measured.width/height
  // is set after first render. Use safe fallbacks for un-measured nodes
  // (140px min-width from StreamNode.tsx:242, ~70px default height).
  const w = (n.measured?.width as number | undefined) ?? 140;
  const h = (n.measured?.height as number | undefined) ?? 70;
  return { x: n.position.x + w / 2, y: n.position.y + h / 2 };
}

/**
 * D-13: tie-break `|dx| >= |dy|` → horizontal.
 * D-16: neighbor anchor = node center.
 * D-11: zero connections → return registry default side.
 */
export function resolveFlowPortSide(
  nodes: Node[],
  edges: Edge[],
  nodeId: string,
  portName: string,
  defaultSide: Side,
  _getComponent: (id: string) => ComponentDefinition | undefined,
): Side {
  const isInPort = portName.includes("in");
  // Find the neighbor connected to THIS port specifically.
  const myEdge = edges.find((e) =>
    isInPort
      ? e.target === nodeId && e.targetHandle === portName
      : e.source === nodeId && e.sourceHandle === portName,
  );
  if (!myEdge) return defaultSide; // D-11

  const neighborId = isInPort ? myEdge.source : myEdge.target;
  const me = nodes.find((n) => n.id === nodeId);
  const them = nodes.find((n) => n.id === neighborId);
  if (!me || !them) return defaultSide;

  const a = nodeCenter(me);
  const b = nodeCenter(them);
  const dx = b.x - a.x;
  const dy = b.y - a.y;

  if (Math.abs(dx) >= Math.abs(dy)) {
    return dx >= 0 ? "right" : "left";
  }
  return dy >= 0 ? "bottom" : "top";
}
```

### Resolving same-side asymmetric offset

```typescript
// File: gui/src/lib/autoflip.ts (new — continuation)
//
// D-09: 25% / 75%.
// D-10: in→out reading direction (top/bottom: left→right; left/right: top→bottom).

export type OffsetStyle = { left?: string; top?: string };

export function resolveAsymmetricOffset(
  nodes: Node[],
  edges: Edge[],
  nodeId: string,
  side: Side,
  portName: string,
  defaultSide: Side,
  getComponent: (id: string) => ComponentDefinition | undefined,
): OffsetStyle | undefined {
  // Look up the SIBLING FlowPort on this same node.
  const me = nodes.find((n) => n.id === nodeId);
  if (!me) return undefined;
  const comp = getComponent((me.data as { componentId: string }).componentId);
  if (!comp) return undefined;
  const myFlowPorts = comp.ports.filter((p) => p.type === "FlowPort");
  const sibling = myFlowPorts.find((p) => p.name !== portName);
  if (!sibling) return undefined;

  const siblingSide = resolveFlowPortSide(
    nodes, edges, nodeId, sibling.name,
    (sibling.side as Side | undefined) ?? defaultSide,
    getComponent,
  );
  if (siblingSide !== side) return undefined; // Different sides — no asymmetry needed (D-09).

  // Both ports on same side. Apply 25%/75% along reading-direction axis.
  const isInPort = portName.includes("in");
  const pct = isInPort ? "25%" : "75%";

  if (side === "top" || side === "bottom") return { left: pct };
  return { top: pct };
}
```

### Resolving thermal-pair axis

```typescript
// File: gui/src/lib/autoflip.ts (new — continuation)
//
// D-12: thermal pairs never share a side (always opposing faces).
// Compute average dx/dy across ALL thermal edges touching either pair member;
// pick horizontal vs vertical accordingly; map default_axis="vertical" CAC to
// top/bottom, default_axis="horizontal" HD to left/right.

export function resolveThermalPairSides(
  nodes: Node[],
  edges: Edge[],
  nodeId: string,
  thisPortName: string, // e.g. "thermal_left" or "thermal_right"
  pairWith: string,
  defaultAxis: "horizontal" | "vertical",
  getComponent: (id: string) => ComponentDefinition | undefined,
): { thisSide: Side; pairSide: Side } {
  // Collect every neighbor connected to either thermal port on this node.
  const thermalEdges = edges.filter((e) =>
    (e.source === nodeId && (e.sourceHandle === thisPortName || e.sourceHandle === pairWith)) ||
    (e.target === nodeId && (e.targetHandle === thisPortName || e.targetHandle === pairWith)),
  );

  if (thermalEdges.length === 0) {
    // D-11 default — use default_axis.
    const horiz = defaultAxis === "horizontal";
    // Per spec: thermal_left → "left" (or "top"), thermal_right → opposite.
    const isLeft = thisPortName.endsWith("_left");
    if (horiz) return { thisSide: isLeft ? "left" : "right", pairSide: isLeft ? "right" : "left" };
    return { thisSide: isLeft ? "top" : "bottom", pairSide: isLeft ? "bottom" : "top" };
  }

  // Aggregate |dx| vs |dy| across all thermal neighbors.
  const me = nodes.find((n) => n.id === nodeId);
  if (!me) return resolveThermalPairSides(nodes, [], nodeId, thisPortName, pairWith, defaultAxis, getComponent);
  const meC = nodeCenter(me);
  let sumDx = 0, sumDy = 0;
  for (const e of thermalEdges) {
    const otherId = e.source === nodeId ? e.target : e.source;
    const other = nodes.find((n) => n.id === otherId);
    if (!other) continue;
    const oc = nodeCenter(other);
    sumDx += Math.abs(oc.x - meC.x);
    sumDy += Math.abs(oc.y - meC.y);
  }

  // Decide axis (D-13 tie-break: horizontal wins).
  const horiz = sumDx >= sumDy;
  const isLeft = thisPortName.endsWith("_left");
  if (horiz) {
    // thermal_left on the side facing the average-leftward neighbor; simplification:
    // use the SIGN of (sum of signed dx) to pick which suffix maps to which side.
    // For aggregate-position decisions we keep _left → left, _right → right.
    return { thisSide: isLeft ? "left" : "right", pairSide: isLeft ? "right" : "left" };
  }
  return { thisSide: isLeft ? "top" : "bottom", pairSide: isLeft ? "bottom" : "top" };
}
```

> **Planner note:** the "which name maps to which physical side" question (does `thermal_left` always render on the spatial-left when axis is horizontal, regardless of where neighbors are?) needs a 1-line confirmation during plan. The spec wording in §3.4 is "thermal_left on left edge, thermal_right on right edge" for horizontal axis — implying the suffix is **definitive**, the axis is the only thing that flips. This research follows that reading.

### Anti-parallel bow inside HydraulicEdge

```typescript
// Source: pattern synthesized from gui/src/components/HydraulicEdge.tsx +
// gui/src/components/CanvasPanel.tsx:27-34 (getState() read pattern)
// File: gui/src/components/HydraulicEdge.tsx (patched)

import { memo } from "react";
import { getSmoothStepPath, BaseEdge, type EdgeProps } from "@xyflow/react";
import useStore from "../store/useStore";

const BOW_PX = 8; // D-07

function HydraulicEdge({ id, source, target, sourceX, sourceY, targetX, targetY, sourcePosition, targetPosition, style, markerEnd }: EdgeProps) {
  // Pitfall 4 — same-type sibling only. enrichEdges sets type="hydraulicEdge"
  // for hydraulic; thermal edges have type set elsewhere via styling.
  const hasAntiParallel = useStore
    .getState()
    .edges.some((e) => e.id !== id && e.type === "hydraulicEdge" && e.source === target && e.target === source);

  // Stable ordering so the two siblings bow in OPPOSITE directions:
  // smaller-id edge gets +bow, larger-id gets -bow.
  let bow = 0;
  if (hasAntiParallel) {
    const sibling = useStore.getState().edges.find((e) => e.id !== id && e.source === target && e.target === source);
    if (sibling) bow = id < sibling.id ? BOW_PX : -BOW_PX;
  }

  // Apply bow as an `offset` to getSmoothStepPath, which shifts the midline.
  const [path] = getSmoothStepPath({
    sourceX, sourceY, targetX, targetY, sourcePosition, targetPosition,
    offset: 20, // ReactFlow default smoothstep offset; tune only via bow.
    // Note: getSmoothStepPath has no native perpendicular-bow param. The
    // simplest concrete implementation is to nudge the source/target X or Y by
    // ±bow perpendicular to the dominant axis BEFORE calling the path fn:
  });

  // ALTERNATIVE PATH SHAPE (recommended for cleaner geometry):
  // 1. Compute the midpoint axis (horizontal or vertical based on
  //    sourcePosition/targetPosition).
  // 2. Pass tweaked source/target coords with perpendicular ±bow offset.
  // 3. Render via getSmoothStepPath.

  return <BaseEdge id={id} path={path} style={style} markerEnd={markerEnd} />;
}

export default memo(HydraulicEdge);
```

> **Implementation note:** `getSmoothStepPath` does not expose a "midpoint bow" knob. The two practical strategies are: (a) offset the source/target coordinates perpendicular to the dominant axis by `±bow` before calling; (b) build a custom SVG path string that inserts a perpendicular kink at the midpoint. Option (a) is simpler and keeps using ReactFlow's primitives. The planner should pick one explicitly and the verifier should eyeball-test against `example_1.png`.

### Topology-hint validator (D-15)

```typescript
// Source: pattern derived from gui/src/lib/selectors/nodeErrors.ts (Phase 63.1)
// File: gui/src/lib/selectors/topologyHints.ts (new)

import type { Node, Edge } from "@xyflow/react";
import { resolveFlowPortSide, resolveThermalPairSides } from "../autoflip";
import type { ComponentDefinition } from "../../registry/types";

export interface TopologyHintsInput {
  nodes: Node[];
  edges: Edge[];
}

const HINT_AXIS_COLLISION = "topology-axis-collision";

/**
 * Pure selector. Emits 'topology-axis-collision' when a single component
 * (e.g. CAC) has BOTH its FlowPort autoflip axis AND its thermal-pair axis
 * resolved to the same orientation — the rare crowded-edge case per D-15.
 */
export function selectTopologyHints(
  state: TopologyHintsInput,
  nodeId: string,
  getComponent: (id: string) => ComponentDefinition | undefined,
): string[] {
  const node = state.nodes.find((n) => n.id === nodeId);
  if (!node) return [];
  const comp = getComponent((node.data as { componentId: string }).componentId);
  if (!comp) return [];

  const hasFlow = comp.ports.some((p) => p.type === "FlowPort");
  const hasThermalPair = comp.ports.some(
    (p) => p.type === "ThermalPort" && p.pair_with,
  );
  if (!hasFlow || !hasThermalPair) return [];

  // Resolve flow port side (use port_in as the canonical FlowPort).
  const portIn = comp.ports.find((p) => p.type === "FlowPort" && p.name.includes("in"));
  if (!portIn) return [];
  const flowSide = resolveFlowPortSide(
    state.nodes, state.edges, nodeId, portIn.name,
    (portIn.side as "left" | "right" | "top" | "bottom" | undefined) ?? "left",
    getComponent,
  );

  // Resolve thermal axis.
  const thLeft = comp.ports.find((p) => p.type === "ThermalPort" && p.name.endsWith("_left"));
  if (!thLeft || !thLeft.pair_with || !thLeft.default_axis) return [];
  const { thisSide: thermalSide } = resolveThermalPairSides(
    state.nodes, state.edges, nodeId, thLeft.name, thLeft.pair_with,
    thLeft.default_axis, getComponent,
  );

  // Axis collision: both on horizontal (left/right) OR both on vertical (top/bottom).
  const flowHoriz = flowSide === "left" || flowSide === "right";
  const thermalHoriz = thermalSide === "left" || thermalSide === "right";
  if (flowHoriz === thermalHoriz) return [HINT_AXIS_COLLISION];
  return [];
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Registry-static port sides (`"side": "left"` baked in) | Live autoflip derived from `(nodes, edges)` at render time | Phase 64 (this phase) | All FlowPort and thermal-pair handles compute side per render; CAC's thermal ports now have a defined Position (today they read `side: undefined`) |
| Stored derived state (`errorTagsByNodeId` slice) | Pure selectors over the canonical slices | Phase 63.1 D-15 (shipped 2026-05-14) | Validators are pure functions; no event-driven cleanup needed |
| BCModePicker 5-pill | Dropdown | Phase 63.1 D-11 | Rare action moved one click away |
| `streamgui` file extension | `.scp` (STREAM Composer Project) | Phase 62 | `gui/export_examples/*.streamgui` files in repo are pre-Phase-62 artifacts — ignore for Phase 64 testing; use the Phase 62 fixture `simple_loop.scp` instead |

**Not deprecated (still in active use):** `getSmoothStepPath`, `@xyflow/react`'s `<Handle>` with inline-style offsets, `useUpdateNodeInternals`. These are the documented v12.x API surface.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `useUpdateNodeInternals` is the correct primitive for handle-side flips | Pattern 2 | If wrong, edges will visually lag after autoflip. Workaround documented (setTimeout deferral). Mitigation: smoke test as part of human-verify checkpoint. |
| A2 | The "anti-parallel sibling" filter should be **same edge type only** (`e.type === "hydraulicEdge"`) per Pitfall 4 | Pitfall 4 | If wrong (CONTEXT D-08 meant "any sibling regardless of type"), hydraulic edges will spuriously bow when a thermal sibling exists. **Planner should confirm during plan-phase.** |
| A3 | Thermal-pair port suffix is definitive: `thermal_left` always renders on left/top, `thermal_right` always on right/bottom; only the axis flips | Code Examples §"Resolving thermal-pair axis" | If wrong (suffix is just nominal, actual side depends on neighbor direction), the resolution logic needs to compute signed-dx-aggregate, not just `endsWith("_left")`. Reading of §3.4 supports this assumption: "thermal_left on left edge, thermal_right on right edge" for horizontal axis. |
| A4 | A primitive-string return from the autoflip selector is sufficient to keep re-renders bounded | Pattern 1 | If wrong, zustand fires re-renders on unrelated store updates. Mitigation: existing `hasAnchor` / `hasBCError` precedents use the same pattern and work; Phase 63.1 stress-tested this. |
| A5 | `gui/src/components/__tests__/StreamNode.test.tsx` template (happy-dom + `@testing-library/react` + `ReactFlowProvider`) supports asserting on `<Handle>` rendered position class names (`.react-flow__handle-bottom`, etc.) | Test Strategy | If happy-dom misrenders ReactFlow handles' position class, fall back to asserting on inline `style` attributes only. Both are queryable. |
| A6 | `getSmoothStepPath` accepts perpendicular bow indirectly by tweaking source/target coords; no third-party SVG path library needed | Code Examples §"Anti-parallel bow" | If the visual result is jagged, an alternative is to hand-build the SVG path string. Eyeball test against `example_1.png` is the gate. |

## Open Questions

1. **Anti-parallel filter scope (A2):**
   - What we know: D-08 says "any port pair counts; port identity does not need to match." Says nothing about edge type.
   - What's unclear: Does an anti-parallel hydraulic↔thermal pair count?
   - Recommendation: Default to same-type-only (safer; matches the spirit of "bidirectional hydraulic flow"). Surface as a one-line plan-phase confirmation question.

2. **Anti-parallel bow geometry (A6):**
   - What we know: ±8px perpendicular at midpoint.
   - What's unclear: Implementation strategy — pre-offset coords vs custom path string.
   - Recommendation: Plan picks pre-offset coords (simpler); verifier checks against `example_1.png`. Ship-stop only if visibly broken.

3. **Validation chip visual treatment for D-15 hint:**
   - What we know: Phase 63.1 surfaced BC errors via the validation panel + red ring around offending nodes. D-15 says yellow non-blocking with text.
   - What's unclear: Does Phase 64 add a new "warning"/"hint" severity to the existing surface, or stay within Phase 63.1's binary error/no-error contract?
   - Recommendation: Plan adds a `severity: "warning"` discriminator to the selector return and to the existing chip render path. Mark as scope-additive; verify with a single rendered test.

4. **Node measurement timing (A1 latent):**
   - What we know: `node.measured?.width/height` is only set after first ReactFlow render. Before that, autoflip uses fallback dims (140×70).
   - What's unclear: Could the first-render flicker (fallback dims → measured dims) cause a visible re-flip on initial paint?
   - Recommendation: Plan smoke-tests "open `simple_loop.scp`, observe no visible re-flip." If observed, gate the autoflip behind `node.measured` being set (return registry default until measured arrives).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Node.js | `npm run dev`, vitest | ✓ | (system) | — |
| `npm` | install + scripts | ✓ | (system) | — |
| `@xyflow/react` | render + path | ✓ | 12.10.2 (lockfile) | — |
| `zustand` | store reads | ✓ | 5.0.12 | — |
| `vitest` + `happy-dom` | tests | ✓ | 4.1.2 / 20.8.9 | — |
| Tauri runtime | not used by Phase 64's logic (web-only changes) | ✓ | 2.x | — |
| `example_*.png` reference screenshots | visual verification | partially — referenced in `.planning/notes/gui-redesign-design-decisions.md` §3.3 but not present in the repo | — | Human verifier eyeball-tests against the `gui/export_examples/*.scp` fixtures or constructs a fresh simple_loop |

**Missing dependencies with no fallback:** None — Phase 64 is fully self-contained in the GUI tree.

**Missing dependencies with fallback:** `example_*.png` are not in the repo; verify against either (a) the in-repo `gui/export_examples/project.streamgui` / `system.streamgui` (legacy, may fail to open in current Phase 62+ `.scp` GUI), or (b) ad-hoc construct of pump-CAC-pump loop in a running `npm run dev` and compare against §3.3 prose descriptions. The Phase 62 fixture `simple_loop.scp` is the cleanest baseline.

## Project Constraints (from CLAUDE.md)

- **Branching policy:** Work stays on `gui-redesign` working branch. Do NOT create `gsd/<...>` branches. `.planning/config.json` `git.branching_strategy` MUST stay `"none"` (verified — see `.planning/config.json:20`). Worktree-isolated executors creating `worktree-agent-*` branches are exempt (auto-deleted after merge).
- **No back-compat during heavy dev:** Phase 64 may break behavior of any old saved file shape. The `.scp` schema does not change in Phase 64 anyway (D-02), but if an executor is tempted to handle a "missing handle side" case by writing it to `node.data`, that violates D-02 AND the no-back-compat rule.
- **`.scp` extension:** Save format is `.scp`, not `.streamgui` (memory `project_scp_file_extension`). The five stale `gui/export_examples/*.streamgui` files (current git status) are pre-Phase-62 artifacts; do not use them as fixtures for Phase 64.
- **File structure standard:** Phase 64 is a `gui/` change only; the Julia `src/` tree (governed by the canonical layout in CLAUDE.md) is untouched.

## Sources

### Primary (HIGH confidence)
- `gui/src/components/StreamNode.tsx` — 315 lines, full read 2026-05-14. Lines 28-32 (sideToPosition), 141-187 (FlowPortHandle), 212-313 (handle render block).
- `gui/src/components/HydraulicEdge.tsx` — 32 lines, full read. The anti-parallel bow integration point.
- `gui/src/components/CanvasPanel.tsx` — 233 lines, full read. edgeTypes registration at lines 40-43; `defaultEdgeOptions = { type: "smoothstep" }` at line 45.
- `gui/src/registry/components.json` — port definitions verified: CAC thermal pair at 116-117 has `default_axis: "vertical"`, `pair_with`; HD at 917-918 has `default_axis: "horizontal"`. No `side` on thermal pairs — this is the bug Phase 64 fixes.
- `gui/src/registry/types.ts` — Port interface: `side?` optional, `default_axis?` optional, `pair_with?` optional. Schema already supports autoflip.
- `gui/src/store/useStore.ts:149-294` — AppState shape. `nodes: Node[]`, `edges: Edge[]`, `activeLayer`, `anchors` Record; `node.position: {x, y}` is the canonical position field.
- `gui/src/lib/selectors/nodeErrors.ts` — 95 lines, the Phase 63.1 D-15 selector template Phase 64 mirrors.
- `gui/src/lib/layers.ts` — 105 lines, the pure-helper template (`gui/src/lib/autoflip.ts` mirrors this shape).
- `gui/src/components/BCEdge.tsx` — 113 lines, the primitive-returning `useStore` selector inside an edge component (Pattern 3 precedent).
- `gui/src/components/__tests__/StreamNode.test.tsx` — 80+ lines, the `@vitest-environment happy-dom` + `ReactFlowProvider` rendered-node test template.
- `.planning/phases/64-connection-routing/64-CONTEXT.md` — Locked decisions D-01..D-16. Read in full.
- `.planning/notes/gui-redesign-design-decisions.md` §3.3 (lines 314-396) and §3.4 (lines 398-461) — Definitive design intent.
- `.planning/phases/63.1-bc-architecture-rework-unified-bcs-tab/63.1-CONTEXT.md` — D-13 anchor indicator (consumer of D-04 in this phase), D-15 selector-derived validator pattern.
- `gui/package.json` — Version verification (no remote registry call needed; lockfile is the canonical source for this project).

### Secondary (MEDIUM confidence)
- `https://reactflow.dev/learn/customization/handles` — "If you want to display multiple handles on a side, you can adjust the position via inline styles or overwrite the default CSS." Confirms D-09 implementation.
- `https://reactflow.dev/api-reference/hooks/use-update-node-internals` — `useUpdateNodeInternals` is required when dynamically changing handle position; verified twice via WebFetch + WebSearch.
- `https://reactflow.dev/api-reference/components/handle` — Handle prop surface; no contradiction with assumed usage.

### Tertiary (LOW confidence — flagged for validation)
- `https://github.com/xyflow/xyflow/issues/2008` — `setTimeout` workaround for `useUpdateNodeInternals` race. Confidence MEDIUM-LOW: documented community workaround but may not apply to v12.x. **Test-and-see during implementation.**
- `https://github.com/xyflow/xyflow/discussions/4743` — nested ReactFlow positioning issue; not directly relevant but surfaced repeatedly in search. Confidence LOW. Ignore unless Phase 64 introduces nested provider scopes (it doesn't).

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — versions verified from `gui/package.json`; no new deps; pattern templates exist in-tree (`layers.ts`, `selectors/nodeErrors.ts`, `BCEdge.tsx`).
- Architecture: HIGH — three integration points enumerated, each backed by a precedent file. The autoflip module is brand new but follows the established pure-helper shape.
- Pitfalls: HIGH — `useUpdateNodeInternals` race documented in two independent ReactFlow sources; primitive-vs-object selector pitfall is in-tree comment at `StreamNode.tsx:113` and `BCEdge.tsx:58`. Pitfall 6 (CAC thermal `side` undefined) is a structural observation from the registry file.
- Open questions: MEDIUM — A2 (anti-parallel sibling filter scope) and A3 (thermal port suffix definitiveness) are spec interpretation calls; planner should one-line confirm before code lands.

**Research date:** 2026-05-14
**Valid until:** 2026-06-14 (stable surface — ReactFlow 12.x stable, Phase 63.1 selector pattern locked, no upcoming dependency upgrades that would invalidate findings)
