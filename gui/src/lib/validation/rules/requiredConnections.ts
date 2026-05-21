// requiredConnections.ts — Required-port connectivity validator (Phase 71, Plan 04)
//
// D-15 rule 4: "required-connections" — every required port must have an attached edge.
//
// Required-port heuristic (Port.required field is absent from the registry schema):
//   - FlowPort: always required
//   - ThermalPort: required on all components (HeatDiffusion, ChannelAndContacts,
//     ConstantTemperature). For array-shaped ports (array_size present), iterate
//     from 1 to node.data.parameters[array_size_param] and check each cell.
//   - BCPort: NEVER required. WallTemperature and HeatFluxSource are optional
//     value-source blocks; connections to them are at the user's discretion.
//
// D-14: emits [{kind:'port', nodeId, portName}, {kind:'node', nodeId}] per missing port.
// D-11: stable result id `required_connections::${nodeId}::${portName}` (or `::${index}`).
//
// Pure function: zero useStore imports, zero React imports.

import type { Validator, ValidationResult } from "../types";
import type { ValidationSnapshot } from "../snapshot";

export const requiredConnections: Validator = {
  id: "required_connections",
  severity: "error",
  description: "Required port missing a connection",
  scope: ["nodes", "edges"],

  run(snapshot: ValidationSnapshot): ValidationResult[] {
    const results: ValidationResult[] = [];

    for (const node of snapshot.nodes) {
      const data = node.data as {
        componentId: string;
        instanceName: string;
        parameters: Record<string, unknown>;
      };

      const def = snapshot.getComponentDef(data.componentId);
      if (!def) continue;

      for (const port of def.ports) {
        // BCPort is never required
        if (port.type === "BCPort") continue;

        if (port.array_size) {
          // Array-shaped port: iterate from 1 to the array size parameter value
          const arraySizeParam = port.array_size;
          const n = Number(data.parameters[arraySizeParam] ?? 0);
          if (!Number.isFinite(n) || n <= 0) continue;

          for (let i = 1; i <= n; i++) {
            const portName = `${port.name}[${i}]`;
            const connected = _isArrayPortCellConnected(
              snapshot,
              node.id,
              port.name,
              i,
            );
            if (!connected) {
              results.push({
                id: `required_connections::${node.id}::${port.name}::${i}`,
                validatorId: "required_connections",
                severity: "error",
                description: `${data.instanceName}.${portName} requires a connection`,
                targets: [
                  { kind: "port", nodeId: node.id, portName },
                  { kind: "node", nodeId: node.id },
                ],
              });
            }
          }
        } else {
          // Scalar port: check direct edge connection
          const isInput = port.name.includes("in");
          const connected = snapshot.edges.some((e) =>
            isInput
              ? e.target === node.id && e.targetHandle === port.name
              : e.source === node.id && e.sourceHandle === port.name,
          );
          if (!connected) {
            results.push({
              id: `required_connections::${node.id}::${port.name}`,
              validatorId: "required_connections",
              severity: "error",
              description: `${data.instanceName}.${port.name} requires a connection`,
              targets: [
                { kind: "port", nodeId: node.id, portName: port.name },
                { kind: "node", nodeId: node.id },
              ],
            });
          }
        }
      }
    }

    return results;
  },
};

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/**
 * Check if an array-shaped port cell is connected.
 *
 * Array-shaped ThermalPort cells use handle names in the form `portName[i]`
 * on the canvas edge. Checks both source and target handles for the cell.
 */
function _isArrayPortCellConnected(
  snapshot: ValidationSnapshot,
  nodeId: string,
  portBaseName: string,
  index: number,
): boolean {
  const cellHandle = `${portBaseName}[${index}]`;
  return snapshot.edges.some(
    (e) =>
      (e.source === nodeId && e.sourceHandle === cellHandle) ||
      (e.target === nodeId && e.targetHandle === cellHandle),
  );
}
