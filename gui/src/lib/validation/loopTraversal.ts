/**
 * loopTraversal.ts — Closed hydraulic-loop traversal utility (Phase 71, D-15)
 *
 * findHydraulicLoops is a pure, deterministic function. It has no React, no zustand,
 * and no DOM dependencies. Tests assert on Set equality of nodeIds (not array order)
 * because DFS discovery order is stable but rotation-arbitrary for a given cycle.
 *
 * Algorithm: DFS with a visiting-stack (standard iterative cycle detection).
 * Each call to findHydraulicLoops builds a fresh adjacency map and returns a new
 * array — there is no shared mutable state between calls.
 *
 * Only FlowPort edges participate. An edge is a FlowPort edge when BOTH its
 * sourceHandle resolves to a Port of type 'FlowPort' on the source component AND
 * its targetHandle resolves to a Port of type 'FlowPort' on the target component.
 * Thermal-only nodes (no FlowPort in their component definition) are excluded from
 * the graph entirely (Pitfall 6 in 71-RESEARCH.md).
 *
 * Complexity: O(V + E) per strongly-connected-component pass. Realistic STREAM
 * models have ~5-50 nodes; performance is not a concern.
 */

import type { Node, Edge } from "@xyflow/react";
import type { ComponentDefinition } from "@/registry/types";

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/** A closed hydraulic loop as returned by findHydraulicLoops. */
export interface HydraulicLoop {
  /** Unique node IDs participating in this loop (one per graph node). */
  nodeIds: string[];
  /** Edge IDs of the FlowPort edges that form this loop. */
  edgeIds: string[];
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/** Returns true when the named port on the given component is a FlowPort. */
function isFlowPort(
  compDef: ComponentDefinition | undefined,
  portName: string,
): boolean {
  if (!compDef) return false;
  const port = compDef.ports.find((p) => p.name === portName);
  return port?.type === "FlowPort";
}

/** Returns true when a component has at least one FlowPort. */
function hasFlowPort(compDef: ComponentDefinition | undefined): boolean {
  if (!compDef) return false;
  return compDef.ports.some((p) => p.type === "FlowPort");
}

// Adjacency entry for the directed hydraulic graph.
interface AdjEntry {
  targetNodeId: string;
  edgeId: string;
}

// ---------------------------------------------------------------------------
// Main export
// ---------------------------------------------------------------------------

/**
 * Find all closed hydraulic loops in the canvas graph.
 *
 * @param nodes - All ReactFlow nodes in the canvas.
 * @param edges - All ReactFlow edges in the canvas.
 * @param getComponentDef - Lookup function for component definitions by componentId.
 * @returns Array of HydraulicLoop objects, one per distinct closed loop.
 *          Returns a NEW array on every call (no shared state).
 */
export function findHydraulicLoops(
  nodes: Node[],
  edges: Edge[],
  getComponentDef: (id: string) => ComponentDefinition | undefined,
): HydraulicLoop[] {
  if (nodes.length === 0 || edges.length === 0) return [];

  // Build a lookup from nodeId → componentId for quick resolution.
  const compIdByNodeId = new Map<string, string>();
  for (const node of nodes) {
    const componentId = (node.data as { componentId?: string }).componentId;
    if (componentId) compIdByNodeId.set(node.id, componentId);
  }

  // Resolve componentDef for a nodeId.
  const getDefForNode = (nodeId: string): ComponentDefinition | undefined => {
    const cid = compIdByNodeId.get(nodeId);
    return cid ? getComponentDef(cid) : undefined;
  };

  // Filter to only hydraulic nodes (those with at least one FlowPort).
  const hydraulicNodeIds = new Set<string>();
  for (const node of nodes) {
    if (hasFlowPort(getDefForNode(node.id))) {
      hydraulicNodeIds.add(node.id);
    }
  }

  if (hydraulicNodeIds.size === 0) return [];

  // Build directed adjacency map — only FlowPort edges between hydraulic nodes.
  // Sort nodeIds before iterating to ensure deterministic Map insertion order.
  const adj = new Map<string, AdjEntry[]>();
  for (const nodeId of [...hydraulicNodeIds].sort()) {
    adj.set(nodeId, []);
  }

  for (const edge of edges) {
    const { source, sourceHandle, target, targetHandle, id: edgeId } = edge;
    if (!hydraulicNodeIds.has(source) || !hydraulicNodeIds.has(target)) continue;
    if (!sourceHandle || !targetHandle) continue;

    const sourceDef = getDefForNode(source);
    const targetDef = getDefForNode(target);

    if (
      isFlowPort(sourceDef, sourceHandle) &&
      isFlowPort(targetDef, targetHandle)
    ) {
      adj.get(source)!.push({ targetNodeId: target, edgeId });
    }
  }

  // Tarjan-style DFS: find all strongly connected components (SCCs) of size >= 2.
  // Each SCC of size >= 2 forms one HydraulicLoop.
  //
  // Implementation: iterative DFS with low-link tracking (Tarjan's algorithm).
  // We use index/lowlink arrays + a stack to find SCCs in O(V+E).

  let index = 0;
  const nodeIndex = new Map<string, number>();
  const nodeLowlink = new Map<string, number>();
  const onStack = new Map<string, boolean>();
  const stack: string[] = [];
  const loops: HydraulicLoop[] = [];

  // For each SCC, also collect the edge IDs that form cycles within it.
  // We need to rebuild which edges belong to the SCC after finding SCC members.

  function strongConnect(v: string): void {
    nodeIndex.set(v, index);
    nodeLowlink.set(v, index);
    index++;
    stack.push(v);
    onStack.set(v, true);

    const neighbors = adj.get(v) ?? [];
    for (const { targetNodeId: w } of neighbors) {
      if (!nodeIndex.has(w)) {
        strongConnect(w);
        nodeLowlink.set(v, Math.min(nodeLowlink.get(v)!, nodeLowlink.get(w)!));
      } else if (onStack.get(w)) {
        nodeLowlink.set(v, Math.min(nodeLowlink.get(v)!, nodeIndex.get(w)!));
      }
    }

    // v is a root of an SCC
    if (nodeLowlink.get(v) === nodeIndex.get(v)) {
      const sccNodes: string[] = [];
      let w: string;
      do {
        w = stack.pop()!;
        onStack.set(w, false);
        sccNodes.push(w);
      } while (w !== v);

      if (sccNodes.length >= 2) {
        // Collect edges that are internal to this SCC.
        const sccSet = new Set(sccNodes);
        const sccEdgeIds: string[] = [];
        for (const node of sccNodes) {
          for (const { targetNodeId, edgeId } of adj.get(node) ?? []) {
            if (sccSet.has(targetNodeId)) {
              sccEdgeIds.push(edgeId);
            }
          }
        }
        loops.push({
          nodeIds: sccNodes,
          edgeIds: sccEdgeIds,
        });
      }
    }
  }

  // Run strongConnect for every hydraulic node not yet visited.
  // Sort for determinism.
  for (const nodeId of [...hydraulicNodeIds].sort()) {
    if (!nodeIndex.has(nodeId)) {
      strongConnect(nodeId);
    }
  }

  return loops;
}
