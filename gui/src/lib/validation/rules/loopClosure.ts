// loopClosure.ts — Loop closure validator (Phase 71, Plan 07)
//
// D-15 rule 7: "loop closure" — when the model has at least one driving element
// (Pump or Gravity) but findHydraulicLoops returns [], emit one error.
//
// Physical rationale: a driving element implies fluid is expected to circulate.
// Without a closed hydraulic loop the steady-state solver produces no circulation
// (or silently wrong results). Catching this in the GUI saves the user a
// Julia-side debug round-trip.
//
// Logic:
//   1. Detect driving elements: nodes whose componentId === 'Pump' OR === 'Gravity'.
//   2. If none → return [] (thermal-only or empty models are valid).
//   3. Call findHydraulicLoops. If any loops exist → return [].
//   4. Emit ONE ValidationResult; targets = all driving-element nodes +
//      all hydraulic-category nodes (kind:'node') so the canvas red-rings
//      every FlowPort-capable node that participates in the unclosed graph.
//   5. Stable result id: 'loop_closure::system' (one result per model state).
//
// Pure function: zero useStore imports, zero React imports.

import type { Validator, ValidationResult } from "../types";
import type { ValidationSnapshot } from "../snapshot";
import { findHydraulicLoops } from "../loopTraversal";

/**
 * loopClosure — flags models that have driving elements but no closed hydraulic loop.
 *
 * # Arguments
 * - `snapshot`: ValidationSnapshot — pure read-only model state
 *
 * # Returns
 * - Empty array when no driving elements are present or at least one loop is closed.
 * - One ValidationResult (severity 'error') when driving element(s) exist but no loop.
 */
export const loopClosure: Validator = {
  id: "loop_closure",
  severity: "error",
  description: "Driving element(s) present but no closed hydraulic loop",
  scope: ["nodes", "edges"],

  run(snapshot: ValidationSnapshot): ValidationResult[] {
    // Step 1: Detect driving elements (Pump or Gravity by componentId).
    const drivingNodes = snapshot.nodes.filter((n) => {
      const data = n.data as { componentId?: string };
      return data.componentId === "Pump" || data.componentId === "Gravity";
    });

    // Step 2: If no driving elements, loops are not required — no error.
    if (drivingNodes.length === 0) return [];

    // Step 3: Check for at least one closed loop.
    const loops = findHydraulicLoops(
      snapshot.nodes,
      snapshot.edges,
      snapshot.getComponentDef,
    );

    if (loops.length > 0) return [];

    // Step 4: No closed loop but driving element(s) exist — emit one error.
    // Targets: all driving-element nodes + all hydraulic-capable nodes.
    const hydraulicNodeIds = new Set<string>();
    for (const node of snapshot.nodes) {
      const data = node.data as { componentId?: string };
      if (!data.componentId) continue;
      const def = snapshot.getComponentDef(data.componentId);
      if (def && def.ports.some((p) => p.type === "FlowPort")) {
        hydraulicNodeIds.add(node.id);
      }
    }

    const targets = [...hydraulicNodeIds].map(
      (nodeId) => ({ kind: "node" as const, nodeId }),
    );

    const drivingCount = drivingNodes.length;
    const description =
      `${drivingCount} driving element${drivingCount === 1 ? "" : "s"} but no closed hydraulic loop. ` +
      "Fluid cannot circulate.";

    return [
      {
        id: "loop_closure::system",
        validatorId: "loop_closure",
        severity: "error",
        description,
        targets,
      },
    ];
  },
};
