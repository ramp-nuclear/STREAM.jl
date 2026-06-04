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
// Targets per result (Phase 72 redesign — loop highlight, not single-component):
//   - {kind:'node', nodeId} for EVERY node on the offending loop (Channels,
//     Pumps, Gravities — every node the cycle visits). The gravity-sum
//     mismatch is a property of the loop as a whole, not of any one
//     component; targeting only the Gravities was misleading.
//   - {kind:'edge', edgeId} for every edge on the loop. CanvasPanel renders
//     these as a marching-ants flow trace, conveying which cycle is broken
//     AND its flow direction. See .validation-flow-trace in index.css.
//   - NO `field` targets. The previous H-field highlight singled out one
//     property when there is no per-field action to take.
//
// Stable result id: `gravity_sum_per_loop::${sortedLoopNodeIds.join(',')}`
//   One result per offending loop.
//
// Pure function: zero useStore imports, zero React imports.

import type { Validator, ValidationResult, Target } from "../types";
import type { Edge } from "@xyflow/react";
import type { ValidationSnapshot } from "../snapshot";
import { findAllSimpleCycles } from "../loopTraversal";

// Earth's gravity. The Julia STREAM `Gravity` component hardcodes this in its
// hydrostatic-pressure equation (see Julia-STREAM/src/components/resistors.jl
// Gravity()); we mirror it here so the validator's view matches what the
// generated Julia will actually compute. Channel-family components use their
// OWN `g` parameter (which is project-level by default; see addNode in
// useStore.ts).
const G_EARTH = 9.80665;

// Tolerance is tight: 1e-5 m²/s² ≈ 1 µm of effective height when g ≈ Earth's.
// Looser tolerances are tempting (1 mm reads visually balanced) but a residual
// 1 mm of unbalanced hydrostatic head IS a constant pressure source in the
// Julia solver — it drives a fake mass flow indefinitely. Tight tolerance is
// the physically correct behavior; the warning message handles small-magnitude
// readability by adaptive units (µm / mm / m).
const GRAVITY_TOLERANCE = 1e-5;

/** Format an effective-height value (meters) with adaptive units so the
 *  user sees the imbalance at native scale: µm for sub-mm, mm for sub-m,
 *  m otherwise. Always uses 2 decimal places at the chosen unit, which is
 *  enough for the engineer to distinguish "still imbalanced by N units"
 *  vs "rounded to zero." */
function formatEffectiveHeight(meters: number): string {
  const abs = Math.abs(meters);
  const sign = meters > 0 ? "+" : meters < 0 ? "−" : "";
  const absVal = Math.abs(meters);
  if (abs >= 1) return `${sign}${absVal.toFixed(3)} m`;
  if (abs >= 1e-3) return `${sign}${(absVal * 1e3).toFixed(2)} mm`;
  if (abs >= 1e-6) return `${sign}${(absVal * 1e6).toFixed(2)} µm`;
  return `${sign}${absVal.toExponential(2)} m`;
}

/**
 * gravitySumPerLoop — flags broken simple cycles whose signed gravity sum is
 * non-zero.
 *
 * Phase 72 rewrite. Previously this rule operated on SCCs from
 * findHydraulicLoops, which collapsed two cycles sharing a return edge into
 * one 4-node "loop" and reported the wrong sum. It now uses
 * findAllSimpleCycles, which enumerates each simple directed cycle
 * independently and walks it in order. Each broken cycle is reported on its
 * own, with targets restricted to just the nodes and edges along that one
 * cycle's path.
 *
 * # Returns
 * - One ValidationResult (severity 'warning') per broken simple cycle.
 * - Empty array when every cycle's signed gravity sum is within tolerance.
 *
 * # Sign convention per Gravity node
 * For each Gravity node N visited in the cycle, we compute the contribution
 * from the (entry-port, exit-port) pair:
 *   - enter port_in, exit port_out → +H_N  (forward transit, hydrostatic rise)
 *   - enter port_out, exit port_in → −H_N  (reverse transit)
 *   - enter port_X, exit port_X    → 0     (bounce: both edges incident at
 *                                            the same port; legal for FlowPort
 *                                            connectors with parallel paths)
 *
 * Entry-port is determined by the INCOMING edge at this node (the edge at
 * walkEdges[(k-1+len) % len], at its source-or-target end depending on
 * which end is this node). Exit-port is determined likewise from the
 * outgoing edge at walkEdges[k]. The bounce case is real — see the
 * Phase 72 user scenario where g_2 has two incoming edges (both at port_in)
 * and one outgoing edge (at port_out); a 4-node fundamental cycle would
 * have entered g_2 via port_in and exited via port_in, contributing 0.
 * Simple cycles enumerated by findAllSimpleCycles don't usually bounce, but
 * the entry/exit-port computation is correct for any walk.
 */
export const gravitySumPerLoop: Validator = {
  id: "gravity_sum_per_loop",
  // Phase 72 severity audit: dropped from error → warning. The Julia code
  // compiles and the solver runs; ΣH≠0 means the resulting steady state is
  // non-physical, not that the model can't be evaluated.
  severity: "warning",
  description: "Loop ΣH ≠ 0",
  scope: ["nodes", "edges"],

  run(snapshot: ValidationSnapshot): ValidationResult[] {
    // Enumerate every simple directed cycle. See findAllSimpleCycles vs
    // findHydraulicLoops in loopTraversal.ts for the SCC-vs-simple-cycle
    // distinction.
    const cycles = findAllSimpleCycles(
      snapshot.nodes,
      snapshot.edges,
      snapshot.getComponentDef,
    );

    if (cycles.length === 0) return [];

    // Build a lookup: nodeId → signed (g × h) product for every component
    // that contributes hydrostatic pressure drop.
    //   - Gravity: 9.80665 × H. Julia's Gravity component hardcodes Earth's
    //     gravity in `port_in.P − port_out.P ~ rho × 9.80665 × H` — the
    //     project-level `g_default` does NOT apply here.
    //   - Channel family (Channel / ChannelAndContacts / ChannelHeatFlux):
    //     `g × geometry.L`, where g is the channel's own parameter (cascaded
    //     from `modelOptions.g_default` on creation but user-editable
    //     per-channel). g === 0 → horizontal → no contribution.
    //
    // This matches Python STREAM `check_gravity_mismatch`: sum ΣΔp around
    // each loop at zero flow; at zero flow only hydrostatic terms survive.
    // We work in (g × h) directly (m²/s² up to a ρ factor) so loops where
    // channel.g differs from Earth's gravity validate against the value
    // the generated Julia would actually use.
    const componentGH = new Map<string, number>();
    const channelFamily = new Set(["Channel", "ChannelAndContacts", "ChannelHeatFlux"]);

    function readNumber(v: unknown): number | undefined {
      if (typeof v === "number") return v;
      if (typeof v === "string") {
        const n = parseFloat(v);
        return Number.isNaN(n) ? undefined : n;
      }
      return undefined;
    }

    for (const node of snapshot.nodes) {
      const data = node.data as { componentId?: string; parameters?: Record<string, unknown> };
      if (!data.componentId) continue;

      if (data.componentId === "Gravity") {
        const H = readNumber(data.parameters?.["H"]);
        if (H !== undefined) componentGH.set(node.id, G_EARTH * H);
        continue;
      }

      if (channelFamily.has(data.componentId)) {
        const g = readNumber(data.parameters?.["g"]) ?? 0;
        if (g === 0) continue; // horizontal channel — zero hydrostatic head

        const geomUuid = data.parameters?.["geometry"];
        if (typeof geomUuid !== "string" || !geomUuid) continue;

        const geom = snapshot.resources.geometries[geomUuid];
        if (!geom) continue;

        const L = readNumber(geom.params?.["L"]);
        if (L === undefined) continue;
        componentGH.set(node.id, g * L);
      }
    }

    const edgeById = new Map(snapshot.edges.map((e) => [e.id, e]));

    // Helper — at node `nodeId`, the port at which the given edge attaches.
    // null if the edge isn't incident to this node (defensive).
    function portAt(nodeId: string, edge: Edge): string | null {
      if (edge.source === nodeId) return edge.sourceHandle ?? null;
      if (edge.target === nodeId) return edge.targetHandle ?? null;
      return null;
    }

    const results: ValidationResult[] = [];

    for (const cycle of cycles) {
      // Walk the cycle in order, accumulating ±(g·h) for every height-bearing
      // component. cycle.edgeIds[k] connects cycle.nodeIds[k] →
      // cycle.nodeIds[(k+1) % len]. INCOMING edge at step k is
      // cycle.edgeIds[(k-1+len) % len]; OUTGOING is cycle.edgeIds[k].
      let netGH = 0;
      const len = cycle.nodeIds.length;
      for (let k = 0; k < len; k++) {
        const currentNodeId = cycle.nodeIds[k];
        const gh = componentGH.get(currentNodeId);
        if (gh === undefined) continue;

        const incomingEdge = edgeById.get(cycle.edgeIds[(k - 1 + len) % len]);
        const outgoingEdge = edgeById.get(cycle.edgeIds[k]);
        if (!incomingEdge || !outgoingEdge) continue;

        const entryPort = portAt(currentNodeId, incomingEdge);
        const exitPort = portAt(currentNodeId, outgoingEdge);
        if (entryPort === null || exitPort === null) continue;

        if (entryPort === exitPort) {
          // Bounce — no transit through the node, no hydrostatic contribution.
          continue;
        }
        // Forward transit: enter port_in → exit port_out (+gh).
        // Reverse transit: enter port_out → exit port_in (−gh).
        if (entryPort === "port_in" && exitPort === "port_out") {
          netGH += gh;
        } else if (entryPort === "port_out" && exitPort === "port_in") {
          netGH -= gh;
        }
      }

      // Within tolerance → balanced cycle, skip.
      if (Math.abs(netGH) < GRAVITY_TOLERANCE) continue;

      // Build targets: every node + every edge ON THIS CYCLE only. Other
      // cycles in the network — even sharing return edges — are not
      // implicated and stay un-highlighted. CanvasPanel's multi-target
      // handler renders the cycle as a marching-ants flow trace.
      const targets: Target[] = [];
      for (const nodeId of cycle.nodeIds) {
        targets.push({ kind: "node", nodeId });
      }
      for (const edgeId of cycle.edgeIds) {
        targets.push({ kind: "edge", edgeId });
      }

      // Stable id: sorted node ids of this cycle joined with commas.
      const sortedNodeIds = [...cycle.nodeIds].sort().join(",");
      const stableId = `gravity_sum_per_loop::${sortedNodeIds}`;

      // Display the net as an effective height (Σ(g·h) / 9.80665) so the
      // value reads in meters — matches the engineer's mental model and
      // collapses to ΣH when every component uses Earth's g (the common
      // case). Sub-meter imbalances are formatted in mm or µm so the user
      // can see them; tolerance is disclosed inline so the threshold is
      // self-documenting.
      const effectiveDeltaH = netGH / G_EARTH;
      const tolDisplay = formatEffectiveHeight(GRAVITY_TOLERANCE / G_EARTH);
      // Strip leading sign from the tolerance (always positive).
      const tolNumber = tolDisplay.replace(/^[+−]/, "");
      const description = `Loop ΣH = ${formatEffectiveHeight(effectiveDeltaH)} (tol ${tolNumber})`;

      results.push({
        id: stableId,
        validatorId: "gravity_sum_per_loop",
        severity: "warning",
        description,
        targets,
      });
    }

    return results;
  },
};
