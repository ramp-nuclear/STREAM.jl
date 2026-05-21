// gravitySumPerLoop.ts — Gravity-sum-per-loop validator (Phase 71, Plan 07)
//
// D-15 rule 8: "gravity-sum-per-loop" — for every closed hydraulic loop, the
// signed sum of Gravity component H values must equal zero (within tolerance 1e-6).
// A non-zero net means the hydrostatic pressure bookkeeping is inconsistent and
// the solver will produce wrong steady-state pressure / mass-flow results.
//
// Signed-traversal convention (per §4 per-channel signed gravity invariant):
//   For each edge in the SCC edge set:
//     if edge.source === gravityNodeId → contribute +H  (gravity acts downstream)
//     if edge.target === gravityNodeId → contribute -H  (gravity acts upstream)
//   A Gravity node that appears in both roles (once as source, once as target)
//   contributes zero net — this is physically correct for a component that is
//   fully interior to the loop traversal.
//
// Numerical tolerance: |net| < 1e-6 counts as zero (user-entered floats).
//
// Targets per error:
//   - {kind:'node', nodeId: gravityId} for each Gravity in the offending loop
//   - {kind:'field', nodeId: gravityId, fieldPath:'H'} for each Gravity node
//     (the fieldPath='H' target bridges to the property-panel red-highlight)
//
// Stable result id: `gravity_sum_per_loop::${sortedLoopNodeIds.join(',')}`
//   One result per offending loop.
//
// Pure function: zero useStore imports, zero React imports.

import type { Validator, ValidationResult, Target } from "../types";
import type { ValidationSnapshot } from "../snapshot";
import { findHydraulicLoops } from "../loopTraversal";

const GRAVITY_TOLERANCE = 1e-6;

/**
 * gravitySumPerLoop — flags closed hydraulic loops whose signed gravity sum is non-zero.
 *
 * # Arguments
 * - `snapshot`: ValidationSnapshot — pure read-only model state
 *
 * # Returns
 * - Empty array when all loops have balanced gravity or no loops exist.
 * - One ValidationResult (severity 'error') per offending loop.
 *
 * @pitfall The signed-traversal direction is determined by which side of an edge
 * the Gravity node sits on, not by the loop walk order. Walking an SCC edge set
 * in source→target order: edge.source === gravityId → add +H;
 * edge.target === gravityId → add -H. A node appearing in both roles contributes
 * net zero (interior pass-through). This matches the per-channel signed gravity
 * invariant in §4 of the design decisions.
 */
export const gravitySumPerLoop: Validator = {
  id: "gravity_sum_per_loop",
  severity: "error",
  description: "Gravity contributions do not net to zero around a hydraulic loop",
  scope: ["nodes", "edges"],

  run(snapshot: ValidationSnapshot): ValidationResult[] {
    // Find all closed hydraulic loops.
    const loops = findHydraulicLoops(
      snapshot.nodes,
      snapshot.edges,
      snapshot.getComponentDef,
    );

    if (loops.length === 0) return [];

    // Build a lookup: nodeId → H parameter value (only for Gravity nodes).
    const gravityH = new Map<string, number>();
    for (const node of snapshot.nodes) {
      const data = node.data as { componentId?: string; parameters?: Record<string, unknown> };
      if (data.componentId !== "Gravity") continue;
      const H = data.parameters?.["H"];
      if (typeof H === "number") {
        gravityH.set(node.id, H);
      } else if (typeof H === "string") {
        const parsed = parseFloat(H);
        if (!isNaN(parsed)) gravityH.set(node.id, parsed);
      }
      // If H is missing or unparseable, treat as 0 (no contribution).
    }

    // Build a lookup: edgeId → Edge for fast access.
    const edgeById = new Map(snapshot.edges.map((e) => [e.id, e]));

    const results: ValidationResult[] = [];

    for (const loop of loops) {
      // Compute the signed gravity sum for this loop.
      //
      // For each Gravity node in the loop, determine the traversal direction by
      // finding which edge has this Gravity as its source. The sourceHandle tells
      // us which port the flow exits from:
      //   sourceHandle = 'port_out' → forward traversal (port_in → port_out) → +H
      //   sourceHandle = 'port_in'  → reverse traversal (port_out → port_in) → -H
      //
      // This is the physical convention: H is the signed height that the fluid
      // "climbs" when flowing port_in → port_out. If the fluid flows in the same
      // direction as port_in → port_out, the hydrostatic pressure change is +ρgH
      // (the pump must work against gravity). If reversed, it's -ρgH.
      //
      // Note: A Gravity node always appears exactly once as source in its loop
      // (acausal FlowPort networks are bidirectional edges; each hydraulic node
      // connects in and out exactly once in a simple loop).
      let netH = 0;

      const loopNodeSet = new Set(loop.nodeIds);

      for (const gravNodeId of loop.nodeIds) {
        const H = gravityH.get(gravNodeId);
        if (H === undefined) continue; // Not a Gravity node

        // Find the edge in this loop where this Gravity is the source.
        let sourceEdge: ReturnType<typeof edgeById.get> | undefined;
        for (const edgeId of loop.edgeIds) {
          const edge = edgeById.get(edgeId);
          if (edge && edge.source === gravNodeId && loopNodeSet.has(edge.target)) {
            sourceEdge = edge;
            break;
          }
        }

        if (!sourceEdge) continue;

        // Determine sign from the sourceHandle.
        // port_out as source: forward traversal → +H
        // port_in  as source: reverse traversal → -H (flows backward through the component)
        const sign = sourceEdge.sourceHandle === "port_out" ? 1 : -1;
        netH += sign * H;
      }

      // Skip loops with balanced gravity (within numerical tolerance).
      if (Math.abs(netH) < GRAVITY_TOLERANCE) continue;

      // Collect Gravity nodes that participate in this loop.
      const gravityNodesInLoop = loop.nodeIds.filter((id) => gravityH.has(id));

      // Build targets: node + field targets for each Gravity node.
      const targets: Target[] = [];
      for (const gravId of gravityNodesInLoop) {
        targets.push({ kind: "node", nodeId: gravId });
        targets.push({ kind: "field", nodeId: gravId, fieldPath: "H" });
      }

      // Stable id: sorted node ids of the loop joined with commas.
      const sortedNodeIds = [...loop.nodeIds].sort().join(",");
      const stableId = `gravity_sum_per_loop::${sortedNodeIds}`;

      // Format the net value for the description (sign prefix, 2 decimal places).
      const sign = netH > 0 ? "+" : "";
      const netFormatted = `${sign}${netH.toFixed(2)} m`;

      const description =
        `Gravity sum across loop [${gravityNodesInLoop.join(", ")}] ` +
        `is ${netFormatted} (expected 0.00 m). ` +
        "Check H signs on each Gravity component.";

      results.push({
        id: stableId,
        validatorId: "gravity_sum_per_loop",
        severity: "error",
        description,
        targets,
      });
    }

    return results;
  },
};
