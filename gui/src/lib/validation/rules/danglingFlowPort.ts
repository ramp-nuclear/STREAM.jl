// danglingFlowPort.ts — Dangling FlowPort validator (Phase 71, Plan 04)
//
// Folds VALD-01 from gui/src/lib/validation.ts:79-128 per D-16.
// Coexists with requiredConnections.ts (Task 2): this rule is FlowPort-specific
// (mirrors the legacy validateTopology behavior), requiredConnections is broader
// (covers ThermalPort cells too). Cross-rule dedup is deferred per CONTEXT.md.
//
// D-15 rule 6: "dangling FlowPort" — every FlowPort on every node must be connected.
// D-14: dangling case emits [{kind:'port', nodeId, portName}] only — no edge target
//       (there is no edge to reference when a port is unconnected).
// D-11: stable result id `dangling_flow_port::${nodeId}::${portName}` for dedup.
//
// Pure function: zero useStore imports, zero React imports.

import type { Validator, ValidationResult } from "../types";
import type { ValidationSnapshot } from "../snapshot";

export const danglingFlowPort: Validator = {
  id: "dangling_flow_port",
  severity: "error",
  description: "Unconnected FlowPort",
  scope: ["nodes", "edges"],

  run(snapshot: ValidationSnapshot): ValidationResult[] {
    const results: ValidationResult[] = [];

    for (const node of snapshot.nodes) {
      const data = node.data as {
        componentId: string;
        instanceName: string;
      };

      const def = snapshot.getComponentDef(data.componentId);
      if (!def) continue;

      // This rule is FlowPort-only — mirrors VALD-01 validateTopology behavior.
      // ThermalPort and BCPort are handled by requiredConnections (broader rule).
      const flowPorts = def.ports.filter((p) => p.type === "FlowPort");

      for (const port of flowPorts) {
        // Direction convention from validateTopology:
        //   port name contains "in"  → target handle (incoming edge)
        //   port name contains "out" → source handle (outgoing edge)
        const isInput = port.name.includes("in");
        const connected = snapshot.edges.some((e) =>
          isInput
            ? e.target === node.id && e.targetHandle === port.name
            : e.source === node.id && e.sourceHandle === port.name,
        );

        if (!connected) {
          results.push({
            id: `dangling_flow_port::${node.id}::${port.name}`,
            validatorId: "dangling_flow_port",
            severity: "error",
            description: `${data.instanceName}.${port.name} unconnected`,
            targets: [
              { kind: "port", nodeId: node.id, portName: port.name },
            ],
          });
        }
      }
    }

    return results;
  },
};
