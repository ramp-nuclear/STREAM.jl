// autoflip.ts — Phase 64 Plan 01: pure geometric autoflip rules.
//
// Encodes every locked decision from `.planning/phases/64-connection-routing/64-CONTEXT.md`
// (D-08 .. D-18). Zero runtime imports from `@xyflow/react`, `react`, or `zustand` —
// only `import type` is allowed. Mirrors the pure-helper shape established by
// `gui/src/lib/layers.ts` and the selector-purity discipline of
// `gui/src/lib/selectors/nodeErrors.ts`.
//
// Consumers (Plans 03 and 04) wire these into the render path. Each function
// takes raw `(nodes, edges)` plus a `getComponent` callback so the module
// stays untangled from the registry singleton — caller injects the lookup.
//
// The "in vs out" port heuristic uses `portName.includes("in")`, matching the
// precedent in `StreamNode.tsx` `FlowPortHandle` (`port.name.includes("in")`).

import type { Node, Edge } from "@xyflow/react";
import type { ComponentDefinition } from "../registry/types";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type Side = "left" | "right" | "top" | "bottom";

// (Helpers for "one port per side" displacement removed in Phase 72; we now
// allow multiple ports on the same side and rely on xyflow auto-spreading.)

// ---------------------------------------------------------------------------
// reachableNodes — connected-component BFS over the (undirected) edge graph.
// ---------------------------------------------------------------------------
//
// Phase 73 — orphan-node bug fix. Both flow-axis classification (this module)
// and obstacle-avoiding edge routing (gui/src/lib/edgeRouting.ts consumers)
// were considering ALL nodes on the canvas, including ones with zero
// connections. An unrelated WallTemperature parked off to the right stretched
// the cluster bbox sideways, which flipped the dominant flow axis to
// horizontal in a clearly vertical loop. Same node also became an obstacle
// the edge router wrapped around even though no edge touched it.
//
// The fix is to restrict either computation to the connected component
// reachable from the seed node(s) via the edge graph. We treat edges as
// undirected for traversal — a flow edge from A→B still makes B reachable
// from A and vice versa.
//
// Cost: BFS over E edges, V vertices reachable. O(V+E) per call. The caller
// computes it once per render and reuses for every per-port resolver call.
export function reachableNodes(
  nodes: ReadonlyArray<Node>,
  edges: ReadonlyArray<Edge>,
  seeds: ReadonlyArray<string>,
): Set<string> {
  const adj = new Map<string, Set<string>>();
  for (const e of edges) {
    let s = adj.get(e.source);
    if (!s) {
      s = new Set();
      adj.set(e.source, s);
    }
    s.add(e.target);
    let t = adj.get(e.target);
    if (!t) {
      t = new Set();
      adj.set(e.target, t);
    }
    t.add(e.source);
  }
  const visited = new Set<string>();
  const queue: string[] = [];
  for (const seed of seeds) {
    if (visited.has(seed)) continue;
    visited.add(seed);
    queue.push(seed);
  }
  while (queue.length > 0) {
    const id = queue.shift()!;
    const neighbors = adj.get(id);
    if (!neighbors) continue;
    for (const n of neighbors) {
      if (visited.has(n)) continue;
      visited.add(n);
      queue.push(n);
    }
  }
  // Defensive: ensure the seed is present even if the node doesn't appear in
  // any edge — orphan source/target should still register as "reachable from
  // itself" so single-node cases don't fall through to an empty set.
  // (Set semantics already cover this; explicit comment for the reader.)
  void nodes; // currently unused — kept in the signature for parity with
              //   future callers that might filter on node properties.
  return visited;
}

// ---------------------------------------------------------------------------
// nodeCenter (internal)
// ---------------------------------------------------------------------------

/**
 * Center of a node in canvas coordinates.
 *
 * ReactFlow stores `position` as the top-left corner; `measured.width`/
 * `measured.height` are set after the first render. Use safe fallbacks for
 * un-measured nodes — 140px from `StreamNode.tsx` min-width, ~70px default
 * height. D-16: neighbor anchor = node center.
 */
function nodeCenter(n: Node): { x: number; y: number } {
  const measured = n.measured as { width?: number; height?: number } | undefined;
  const w = measured?.width ?? 140;
  const h = measured?.height ?? 70;
  return { x: n.position.x + w / 2, y: n.position.y + h / 2 };
}

// ---------------------------------------------------------------------------
// resolveFlowPortSide
// ---------------------------------------------------------------------------

/**
 * Resolve which side of a node a given FlowPort should render on, based on
 * the dominant axis of the node-center-to-node-center vector to its connected
 * neighbor.
 *
 * Rules:
 * - D-11: zero connections on the port → return `defaultSide` (registry default).
 * - D-13/D-16: pick horizontal vs vertical by `|dx| >= |dy|`; tie-break horizontal.
 * - D-14: strict comparison — no dead zone.
 *
 * The "in" port matches edges via `targetHandle === portName && target === nodeId`;
 * the "out" port matches via `sourceHandle === portName && source === nodeId`.
 * The heuristic is `portName.includes("in")` (precedent: StreamNode.tsx
 * `FlowPortHandle`).
 */
export function resolveFlowPortSide(
  nodes: Node[],
  edges: Edge[],
  nodeId: string,
  portName: string,
  defaultSide: Side,
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  _getComponent: (id: string) => ComponentDefinition | undefined,
): Side {
  const isInPort = portName.includes("in");
  // Find the FIRST edge wired to THIS port specifically.
  const myEdge = edges.find((e) =>
    isInPort
      ? e.target === nodeId && e.targetHandle === portName
      : e.source === nodeId && e.sourceHandle === portName,
  );
  if (!myEdge) return defaultSide; // D-11.

  const neighborId = isInPort ? myEdge.source : myEdge.target;
  const me = nodes.find((n) => n.id === nodeId);
  const them = nodes.find((n) => n.id === neighborId);
  if (!me || !them) return defaultSide;

  const a = nodeCenter(me);
  const b = nodeCenter(them);
  const dx = b.x - a.x;
  const dy = b.y - a.y;

  // D-13 tie-break: `|dx| >= |dy|` → horizontal.
  if (Math.abs(dx) >= Math.abs(dy)) {
    return dx >= 0 ? "right" : "left";
  }
  return dy >= 0 ? "bottom" : "top";
}

// ---------------------------------------------------------------------------
// resolveFlowPortAssignment
// ---------------------------------------------------------------------------

/**
 * Per-component FlowPort side assignment.
 *
 * Phase 72 rewrite — convention-driven with local-geometry refinement:
 *
 *   1. Determine the network's dominant flow axis from the cluster bbox
 *      (vertical if the canvas of nodes is taller than wide; horizontal
 *      otherwise). This is the "axis of flow" the user laid out, and ports
 *      should align with it.
 *
 *   2. Aggregate-across-edges: compute each port's local-geometry preference
 *      by summing the (dx, dy) vectors to ALL neighbors of that port (not
 *      just the first edge). port_in pulls from upstream, port_out pushes
 *      to downstream.
 *
 *   3. Axis snap: if a port's local preference is perpendicular to the
 *      dominant flow axis (e.g. the neighbor is slightly off to the side
 *      while the network as a whole runs vertically), snap to the natural
 *      side along the axis. Vertical natural: port_in=top, port_out=bottom.
 *      Horizontal natural: port_in=left, port_out=right.
 *
 *   4. Collision resolution (after snap):
 *      - Both ports connected and still want the same side → use the natural
 *        sides on the flow axis (the "convention" overrides local geometry
 *        when both ports' local pulls collide; the return-path edge wraps
 *        around the network, which is what the user expects in a hydraulic
 *        loop).
 *      - One port connected, the other disconnected → connected port keeps
 *        its (snapped) preference; disconnected port moves to opposite.
 */
const OPPOSITE: Record<Side, Side> = {
  left: "right",
  right: "left",
  top: "bottom",
  bottom: "top",
};

/** Sides that align with each flow axis. */
const AXIS_SIDES: Record<"vertical" | "horizontal", Set<Side>> = {
  vertical: new Set<Side>(["top", "bottom"]),
  horizontal: new Set<Side>(["left", "right"]),
};

/** Natural side per port kind, per flow axis. port_in flows "in from upstream"
 *  (top in vertical, left in horizontal); port_out flows "out to downstream"
 *  (bottom / right). */
function naturalSide(axis: "vertical" | "horizontal", isInPort: boolean): Side {
  if (axis === "vertical") return isInPort ? "top" : "bottom";
  return isInPort ? "left" : "right";
}

export function resolveFlowPortAssignment(
  nodes: Node[],
  edges: Edge[],
  nodeId: string,
  getComponent: (id: string) => ComponentDefinition | undefined,
): Record<string, Side> {
  const out: Record<string, Side> = {};
  const me = nodes.find((n) => n.id === nodeId);
  if (!me) return out;
  const componentId = (me.data as { componentId?: string } | undefined)?.componentId;
  if (!componentId) return out;
  const comp = getComponent(componentId);
  if (!comp) return out;
  const flowPorts = comp.ports.filter((p) => p.type === "FlowPort");
  if (flowPorts.length === 0) return out;

  const meC = nodeCenter(me);

  // Determine the dominant flow axis from the spread of NODE CENTERS — not
  // the full bbox including node widths. Hydraulic component nodes are
  // intrinsically wide rectangles (~280 px) and short (~80 px), so the full
  // bbox over-weights the horizontal dimension and misclassifies a clearly
  // vertical layout as horizontal. Centers reflect spatial arrangement, not
  // node geometry.
  //
  // We further apply a 1.5× vertical bias: hydraulic loops are gravity-driven
  // and read most naturally as top-down flow, so the algorithm should default
  // toward vertical unless the layout is clearly more horizontal.
  //
  // Phase 73 fix (v2): include ONLY nodes reachable via FLOW edges (type
  // "hydraulicEdge"). The previous filter used the full edge graph, which
  // pulled in BC sources and thermal-only nodes via their non-flow edges and
  // still let them deform the flow axis (e.g. a WallTemperature placed off
  // to the side, connected via a dashed BC edge to a Channel in the loop,
  // stretched spreadX and flipped vertical → horizontal). Flow direction
  // should be determined by flow components alone.
  const flowEdges = edges.filter((e) => e.type === "hydraulicEdge");
  const reachable = reachableNodes(nodes, flowEdges, [nodeId]);
  let minCx = Infinity,
    maxCx = -Infinity,
    minCy = Infinity,
    maxCy = -Infinity;
  for (const n of nodes) {
    if (!reachable.has(n.id)) continue;
    const measured = n.measured as { width?: number; height?: number } | undefined;
    const w = measured?.width ?? 140;
    const h = measured?.height ?? 70;
    const cx = n.position.x + w / 2;
    const cy = n.position.y + h / 2;
    if (cx < minCx) minCx = cx;
    if (cx > maxCx) maxCx = cx;
    if (cy < minCy) minCy = cy;
    if (cy > maxCy) maxCy = cy;
  }
  const spreadX = Number.isFinite(minCx) ? maxCx - minCx : 0;
  const spreadY = Number.isFinite(minCy) ? maxCy - minCy : 0;
  const flowAxis: "vertical" | "horizontal" =
    spreadY * 1.5 >= spreadX ? "vertical" : "horizontal";

  // First pass: per-port local preference + connection count.
  type Pref = { name: string; isInPort: boolean; preferred: Side; connections: number };
  const prefs: Pref[] = flowPorts.map((p) => {
    const isInPort = p.name.includes("in");
    const defaultSide = (p.side as Side | undefined) ?? "left";

    let sumDx = 0;
    let sumDy = 0;
    let connections = 0;
    for (const e of edges) {
      const isThisPort = isInPort
        ? e.target === nodeId && e.targetHandle === p.name
        : e.source === nodeId && e.sourceHandle === p.name;
      if (!isThisPort) continue;
      const neighborId = isInPort ? e.source : e.target;
      const them = nodes.find((n) => n.id === neighborId);
      if (!them) continue;
      const tc = nodeCenter(them);
      sumDx += tc.x - meC.x;
      sumDy += tc.y - meC.y;
      connections++;
    }

    let preferred: Side;
    if (connections === 0) {
      preferred = defaultSide;
    } else {
      // Project onto each side's outward normal; dominant axis wins.
      // D-13 horizontal-preferring tie-break via stable sort.
      const scores: { side: Side; score: number }[] = [
        { side: "right", score: sumDx },
        { side: "left", score: -sumDx },
        { side: "bottom", score: sumDy },
        { side: "top", score: -sumDy },
      ];
      scores.sort((a, b) => b.score - a.score);
      preferred = scores[0].side;
    }

    // Axis snap: if local pref is perpendicular to the flow axis, snap to the
    // natural side along the axis. Keep on-axis preferences untouched so
    // a clear "neighbor above" pull continues to put port_in on top.
    //
    // Disconnected ports are EXEMPT from snap — D-11 says isolated ports
    // render on the registry-declared default side. Snapping would override
    // that contract for any node that happens to live in a vertical cluster.
    if (connections > 0 && !AXIS_SIDES[flowAxis].has(preferred)) {
      preferred = naturalSide(flowAxis, isInPort);
    }

    return { name: p.name, isInPort, preferred, connections };
  });

  // Second pass: collision resolution (post-snap).
  // - Both connected & both still want the same side → convention wins:
  //   each port lands on its natural side along the flow axis.
  // - One connected, one disconnected, same side → connected keeps its
  //   (snapped) preference; disconnected port moves to opposite.
  for (let i = 0; i < prefs.length; i++) {
    for (let j = i + 1; j < prefs.length; j++) {
      if (prefs[i].preferred !== prefs[j].preferred) continue;
      const a = prefs[i];
      const b = prefs[j];
      const bothConnected = a.connections > 0 && b.connections > 0;
      if (bothConnected) {
        a.preferred = naturalSide(flowAxis, a.isInPort);
        b.preferred = naturalSide(flowAxis, b.isInPort);
        continue;
      }
      // Partial-connection collision — connected port keeps, disconnected moves.
      const aWins =
        a.connections > b.connections ||
        (a.connections === b.connections && !a.isInPort && b.isInPort);
      const loser = aWins ? b : a;
      loser.preferred = OPPOSITE[loser.preferred];
    }
  }

  for (const p of prefs) out[p.name] = p.preferred;
  return out;
}

// ---------------------------------------------------------------------------
// resolveThermalPairSides
// ---------------------------------------------------------------------------

/**
 * Resolve the sides for a thermal port pair (e.g., `thermal_left` /
 * `thermal_right`). D-12 / D-18:
 *
 * - The pair always occupies opposing faces (never same-side).
 * - The suffix is **definitive**: `thermal_left` maps to spatial `left` when
 *   the axis is horizontal, and to spatial `top` when the axis is vertical.
 *   `thermal_right` mirrors it. Only the axis flips.
 * - Axis selection: aggregate `|sumDx|` vs `|sumDy|` across ALL thermal edges
 *   touching either pair member; D-13 tie-break prefers horizontal.
 * - D-11: zero thermal edges → return the registry `default_axis`-derived pair.
 *
 * Phase 73 v2 — flow takes 100% priority for DIRECTIONS, but non-flow ports
 * are no longer relocated to avoid flow. They land on the side their neighbor
 * pulls them to (neighbor projection); when that side is also occupied by a
 * flow port, they get an inline OFFSET along the edge via `computePortOffset`.
 * The legacy `flowAxisHint` parameter is kept for backward compatibility but
 * is now intentionally ignored.
 */
export function resolveThermalPairSides(
  nodes: Node[],
  edges: Edge[],
  nodeId: string,
  thisPortName: string,
  pairWith: string,
  defaultAxis: "horizontal" | "vertical",
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  _getComponent: (id: string) => ComponentDefinition | undefined,
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  _flowAxisHint?: "horizontal" | "vertical" | null,
): { thisSide: Side; pairSide: Side } {
  const isLeftSuffix = thisPortName.endsWith("_left");

  // Helper: map an axis decision to a (thisSide, pairSide) pair using the
  // definitive-suffix rule (D-18).
  const apply = (
    horiz: boolean,
  ): { thisSide: Side; pairSide: Side } => {
    if (horiz) {
      return isLeftSuffix
        ? { thisSide: "left", pairSide: "right" }
        : { thisSide: "right", pairSide: "left" };
    }
    return isLeftSuffix
      ? { thisSide: "top", pairSide: "bottom" }
      : { thisSide: "bottom", pairSide: "top" };
  };

  // Collect every edge whose either endpoint touches one of the pair members
  // on this node — filter on handle name so we ignore non-thermal edges that
  // happen to terminate at the same nodeId.
  const thermalEdges = edges.filter(
    (e) =>
      (e.source === nodeId &&
        (e.sourceHandle === thisPortName || e.sourceHandle === pairWith)) ||
      (e.target === nodeId &&
        (e.targetHandle === thisPortName || e.targetHandle === pairWith)),
  );

  if (thermalEdges.length === 0) {
    // D-11 default — fall back to the registry-declared axis.
    return apply(defaultAxis === "horizontal");
  }

  const me = nodes.find((n) => n.id === nodeId);
  if (!me) return apply(defaultAxis === "horizontal");
  const meC = nodeCenter(me);

  let sumDx = 0;
  let sumDy = 0;
  for (const e of thermalEdges) {
    const otherId = e.source === nodeId ? e.target : e.source;
    const other = nodes.find((n) => n.id === otherId);
    if (!other) continue;
    const oc = nodeCenter(other);
    sumDx += Math.abs(oc.x - meC.x);
    sumDy += Math.abs(oc.y - meC.y);
  }

  // D-13 tie-break: `sumDx >= sumDy` → horizontal axis.
  return apply(sumDx >= sumDy);
}

// ---------------------------------------------------------------------------
// getFlowAxis — derive the flow axis a node's flow ports resolved to.
// ---------------------------------------------------------------------------

/**
 * Phase 73 — read which axis a node's FlowPorts ended up on, so dependent
 * resolvers (thermal pair, BC port) can place themselves perpendicular.
 * Returns `null` when the component has no FlowPorts.
 *
 * Uses `resolveFlowPortAssignment` as the source of truth so flow's resolved
 * sides — including its convention-driven natural-side fallback — drive the
 * axis answer, not the registry's static `side` field.
 */
export function getFlowAxis(
  nodes: Node[],
  edges: Edge[],
  nodeId: string,
  getComponent: (id: string) => ComponentDefinition | undefined,
): "horizontal" | "vertical" | null {
  const assignment = resolveFlowPortAssignment(nodes, edges, nodeId, getComponent);
  const sides = Object.values(assignment);
  if (sides.length === 0) return null;
  // Both flow ports collapse to one axis by construction (collision resolution
  // ensures port_in + port_out land on the same axis). Read either to decide.
  for (const s of sides) {
    if (s === "left" || s === "right") return "horizontal";
    if (s === "top" || s === "bottom") return "vertical";
  }
  return null;
}

// ---------------------------------------------------------------------------
// resolveBCPortSide — BC port placement that yields to flow + thermal.
// ---------------------------------------------------------------------------

/**
 * Phase 73 v2 — resolve which side of a node a BCPort renders on.
 *
 * Pure neighbor projection: BC ports land on the side closest to their
 * connected source. The registry's `port.side` is the no-edge default.
 *
 * BC ports DO NOT get relocated to dodge flow/thermal — they're allowed to
 * share a side. The visual collision is resolved by `computePortOffset`,
 * which slides the BC mark along the edge so it sits next to (not under)
 * the flow port that occupies that side's center.
 */
export function resolveBCPortSide(
  nodes: Node[],
  edges: Edge[],
  nodeId: string,
  port: { name: string; side?: string },
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  _getComponent: (id: string) => ComponentDefinition | undefined,
): Side {
  const defaultSide = (port.side as Side | undefined) ?? "bottom";

  // Find a BC edge touching this port. BC ports usually carry at most one
  // edge but loops are theoretically allowed — pick the first.
  const myEdge = edges.find(
    (e) =>
      (e.source === nodeId && e.sourceHandle === port.name) ||
      (e.target === nodeId && e.targetHandle === port.name),
  );

  if (!myEdge) return defaultSide;

  const neighborId =
    myEdge.source === nodeId ? myEdge.target : myEdge.source;
  const me = nodes.find((n) => n.id === nodeId);
  const them = nodes.find((n) => n.id === neighborId);
  if (!me || !them) return defaultSide;

  const a = nodeCenter(me);
  const b = nodeCenter(them);
  const dx = b.x - a.x;
  const dy = b.y - a.y;

  // D-13 tie-break: `|dx| >= |dy|` → horizontal.
  if (Math.abs(dx) >= Math.abs(dy)) {
    return dx >= 0 ? "right" : "left";
  }
  return dy >= 0 ? "bottom" : "top";
}

// ---------------------------------------------------------------------------
// computePortOffset — along-edge offset when non-flow port collides with flow.
// ---------------------------------------------------------------------------

/**
 * Phase 73 v2 — when a non-flow port (thermal / BC) resolves to a side that's
 * also occupied by a flow port, return an inline-style offset that slides it
 * along that edge so it sits adjacent to the flow port, not on top of it.
 *
 * Returns `null` when no collision — the port renders centered (default).
 *
 * Two offset strategies:
 *
 *   - **Uniform** (`options.uniformOffset`): both pair members at the same
 *     percentage. Used for thermal pairs so the two thermal marks visually
 *     line up across the node (e.g. both at top-25% on opposite edges → reads
 *     as a "thermal shelf" parallel to the flow axis).
 *   - **Suffix-based** (default): `_left` → 25%, `_right` → 75`, no suffix
 *     → 75%. Used for BC ports, where the `_left/_right` suffix encodes
 *     spatial intent in the underlying simulation (left vs right channel
 *     wall) and should be preserved in the rendered position.
 *
 * The percentage gets written to `top` (when port is on `left`/`right` edge)
 * or `left` (when on `top`/`bottom` edge); xyflow's default Handle CSS uses
 * those properties for cross-edge centering, so inline overrides win.
 */
export function computePortOffset(
  portName: string,
  side: Side,
  flowOccupiedSides: ReadonlySet<Side>,
  options?: { uniformOffset?: string },
): { top?: string; left?: string } | null {
  if (!flowOccupiedSides.has(side)) return null;

  let pct: string;
  if (options?.uniformOffset) {
    pct = options.uniformOffset;
  } else {
    const isLeftSuffix = portName.endsWith("_left");
    pct = isLeftSuffix ? "25%" : "75%";
  }

  if (side === "left" || side === "right") {
    return { top: pct };
  }
  return { left: pct };
}

// ---------------------------------------------------------------------------
// detectAxisCollision
// ---------------------------------------------------------------------------

/**
 * D-15 crowded-edge predicate: returns `true` when a node has BOTH a FlowPort
 * AND a thermal pair AND both axes resolve to the same orientation
 * (both horizontal or both vertical). Used by Plan 04's topology-hint
 * validator to surface the yellow non-blocking warning chip.
 *
 * Returns `false` for components missing either the FlowPort or the thermal
 * pair (e.g., a plain Pump or a plain HeatDiffusion).
 */
export function detectAxisCollision(
  nodes: Node[],
  edges: Edge[],
  nodeId: string,
  getComponent: (id: string) => ComponentDefinition | undefined,
): boolean {
  const node = nodes.find((n) => n.id === nodeId);
  if (!node) return false;
  const componentId = (node.data as { componentId?: string } | undefined)?.componentId;
  if (!componentId) return false;
  const comp = getComponent(componentId);
  if (!comp) return false;

  const portIn = comp.ports.find(
    (p) => p.type === "FlowPort" && p.name.includes("in"),
  );
  const thLeft = comp.ports.find(
    (p) => p.type === "ThermalPort" && p.name.endsWith("_left") && p.pair_with,
  );
  if (!portIn || !thLeft || !thLeft.pair_with || !thLeft.default_axis) return false;

  const flowSide = resolveFlowPortSide(
    nodes,
    edges,
    nodeId,
    portIn.name,
    (portIn.side as Side | undefined) ?? "left",
    getComponent,
  );
  const { thisSide: thermalSide } = resolveThermalPairSides(
    nodes,
    edges,
    nodeId,
    thLeft.name,
    thLeft.pair_with,
    thLeft.default_axis,
    getComponent,
  );

  // Phase 73 v2 — flow + thermal can legitimately share the axis now; the
  // collision is resolved visually via `computePortOffset`. This predicate
  // remains a pure geometric fact lookup ("are they on the same axis?"), not
  // a warning. Callers decide whether to surface it.
  const flowHoriz = flowSide === "left" || flowSide === "right";
  const thermalHoriz = thermalSide === "left" || thermalSide === "right";
  return flowHoriz === thermalHoriz;
}

