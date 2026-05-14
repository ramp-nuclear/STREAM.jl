// topologyHints.ts — Phase 64 Plan 04 (D-15): selector-derived topology-hint
// validator. Mirrors the pure-selector template from `nodeErrors.ts` but
// surfaces a "warning"-severity tag instead of a blocking-error tag — the
// rendered surface is a non-blocking yellow chip inside `StreamNode.tsx`,
// independent of the red-ring `hasAnyError` path.
//
// Zero React dependencies, zero Zustand dependencies, zero ReactFlow runtime
// imports — only `import type` from peer pure modules is allowed. Phase 71
// validator-as-selector foundation continues here: every new validator
// returns a `string[]` of tags, and the consumer wraps with
// `useStore(useCallback(s => selectTopologyHints(s, id, getComponent).length > 0, [...]))`
// to surface a primitive boolean — never a fresh array — to avoid Zustand's
// shallow-equality re-render loop (Pitfall 3).
//
// Body delegates the geometric math to `detectAxisCollision` (Plan 01); this
// module only adds the dual-layer presence pre-check (BOTH a FlowPort AND a
// thermal pair must exist on the component for D-15 to fire) and the public
// tag constant.

import type { Node, Edge } from "@xyflow/react";
import type { ComponentDefinition } from "../../registry/types";
import { detectAxisCollision } from "../autoflip";

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/**
 * Sub-state shape consumed by `selectTopologyHints`. The selector is
 * intentionally NOT typed against the full AppState — it takes only the
 * `nodes` / `edges` it needs, mirroring the purity contract of
 * `NodeErrorsInput` and `validateTopology`.
 */
export interface TopologyHintsInput {
  nodes: Node[];
  edges: Edge[];
}

/**
 * Tag emitted when D-15's crowded-edge condition holds. Re-exported so
 * consumers reference the constant instead of stringly-typing the tag.
 */
export const HINT_AXIS_COLLISION = "topology-axis-collision";

// ---------------------------------------------------------------------------
// selectTopologyHints
// ---------------------------------------------------------------------------

/**
 * Pure selector: returns the topology-hint tags that apply to `nodeId` for
 * the current `(nodes, edges)` slice.
 *
 * Currently emits `'topology-axis-collision'` (D-15) when:
 *   - the node exists,
 *   - the registry lookup for the node's `componentId` succeeds,
 *   - the component has BOTH a FlowPort AND a thermal pair (a thermal port
 *     carrying `pair_with`), and
 *   - `detectAxisCollision(nodes, edges, nodeId, getComponent)` from
 *     `autoflip.ts` returns `true` — i.e., both layers resolve to the same
 *     orientation (both horizontal or both vertical).
 *
 * Returns `[]` for any pre-check miss (unknown node, missing component,
 * thermal-only or flow-only component, or no collision detected).
 *
 * Pure function — no side effects, no store dependency, no React.
 *
 * D-15 severity: this hint is NON-BLOCKING. The consumer (`StreamNode.tsx`)
 * renders the result as a yellow chip independent of the red-ring outline;
 * it does NOT contribute to `hasAnyError`, `errorNodeIds`, or code-gen
 * gating.
 */
export function selectTopologyHints(
  state: TopologyHintsInput,
  nodeId: string,
  getComponent: (id: string) => ComponentDefinition | undefined,
): string[] {
  const node = state.nodes.find((n) => n.id === nodeId);
  if (!node) return [];

  const componentId = (node.data as { componentId?: string } | undefined)
    ?.componentId;
  if (!componentId) return [];

  const comp = getComponent(componentId);
  if (!comp) return [];

  // D-15 dual-layer pre-check: only fires when BOTH a FlowPort AND a thermal
  // pair (i.e., a ThermalPort carrying `pair_with`) exist on the component.
  // Plain Pumps (flow-only) and plain HeatDiffusions (thermal-only) are
  // exempt by construction.
  const hasFlowPort = comp.ports.some((p) => p.type === "FlowPort");
  const hasThermalPair = comp.ports.some(
    (p) => p.type === "ThermalPort" && typeof p.pair_with === "string",
  );
  if (!hasFlowPort || !hasThermalPair) return [];

  // Delegate the axis-collision math to Plan 01's pure helper. Note that
  // `detectAxisCollision` also performs its own pre-checks (component
  // lookup, port presence, default_axis presence); duplicating the
  // dual-layer guard here keeps `selectTopologyHints` self-documenting and
  // ensures the tag's contract is locally legible.
  if (!detectAxisCollision(state.nodes, state.edges, nodeId, getComponent)) {
    return [];
  }

  return [HINT_AXIS_COLLISION];
}
