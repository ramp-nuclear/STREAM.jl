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

/**
 * Inline-style offset payload for ReactFlow `<Handle>` `style.left` / `style.top`.
 * The choice of key (`left` vs `top`) depends on the resolved side: when the
 * handle sits on top/bottom (horizontal edge), the percentage axis is `left`;
 * when it sits on left/right (vertical edge), the percentage axis is `top`.
 * See Pitfall 8 in 64-RESEARCH.md.
 */
export type OffsetStyle = { left?: string; top?: string };

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
// resolveAsymmetricOffset
// ---------------------------------------------------------------------------

/**
 * When both FlowPorts of a component resolve to the same side, return the
 * inline-style offset payload that positions the ports at 25% (port_in) /
 * 75% (port_out) along that side, per D-09 / D-10.
 *
 * Reading-direction rule (D-10):
 * - top/bottom side: percentage axis is `left` (in → left, out → right).
 * - left/right side: percentage axis is `top`  (in → top,  out → bottom).
 *
 * Returns `undefined` when:
 * - the node is not found or has no component definition,
 * - the component has no other FlowPort sibling (e.g., thermal-only or single-port),
 * - the sibling FlowPort resolves to a different side (D-09 only fires on same-side
 *   collision).
 */
export function resolveAsymmetricOffset(
  nodes: Node[],
  edges: Edge[],
  nodeId: string,
  side: Side,
  portName: string,
  defaultSide: Side,
  getComponent: (id: string) => ComponentDefinition | undefined,
): OffsetStyle | undefined {
  const me = nodes.find((n) => n.id === nodeId);
  if (!me) return undefined;
  const componentId = (me.data as { componentId?: string } | undefined)?.componentId;
  if (!componentId) return undefined;
  const comp = getComponent(componentId);
  if (!comp) return undefined;

  const flowPorts = comp.ports.filter((p) => p.type === "FlowPort");
  const sibling = flowPorts.find((p) => p.name !== portName);
  if (!sibling) return undefined; // No sibling FlowPort → asymmetric offset has no peer.

  const siblingSide = resolveFlowPortSide(
    nodes,
    edges,
    nodeId,
    sibling.name,
    (sibling.side as Side | undefined) ?? defaultSide,
    getComponent,
  );
  if (siblingSide !== side) return undefined; // D-09 only fires on same-side collision.

  // Both ports on same side: apply 25% (in) / 75% (out) per D-10.
  const isInPort = portName.includes("in");
  const pct = isInPort ? "25%" : "75%";

  // Pitfall 8: top/bottom side → percentage axis is `left`; left/right side →
  // percentage axis is `top`.
  if (side === "top" || side === "bottom") return { left: pct };
  return { top: pct };
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

  const flowHoriz = flowSide === "left" || flowSide === "right";
  const thermalHoriz = thermalSide === "left" || thermalSide === "right";
  return flowHoriz === thermalHoriz;
}

// ---------------------------------------------------------------------------
// findAntiParallelSibling
// ---------------------------------------------------------------------------

/**
 * D-08 / D-17: find an anti-parallel sibling edge for a given hydraulic edge.
 *
 * Sibling rule: another edge whose `(source, target)` is the swap of this
 * edge's `(source, target)` AND whose `type === "hydraulicEdge"` (same-type
 * filter per D-17 — bcEdges and inline-styled thermal edges do NOT count).
 *
 * Returns `undefined` when no such sibling exists.
 */
export function findAntiParallelSibling(
  edge: Edge,
  edges: Edge[],
): Edge | undefined {
  if (edge.type !== "hydraulicEdge") return undefined;
  return edges.find(
    (e) =>
      e.id !== edge.id &&
      e.type === "hydraulicEdge" &&
      e.source === edge.target &&
      e.target === edge.source,
  );
}
