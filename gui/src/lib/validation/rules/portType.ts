// portType.ts — Port-type compatibility validator (Phase 71, Plan 04)
//
// D-15 rule 5: "port-type match" — every edge must connect compatible port types.
// D-19: This is the SINGLE SOURCE OF TRUTH for port-type compatibility.
//       Plan 13 reroutes CanvasPanel.isValidConnection through this rule.
//
// Logic:
//   - BCPort ↔ BCPort: delegate to isAllowedBCConnection(srcComponentId, tgtComponentId)
//   - BCPort ↔ non-BCPort: always emit error (mixed BC/non-BC is invalid)
//   - Non-BCPort mismatch (FlowPort ↔ ThermalPort): emit error
//   - Same type (FlowPort ↔ FlowPort, ThermalPort ↔ ThermalPort): no emit
//
// D-14: edge-level rules emit edge + both endpoint port targets symmetrically.
// D-11: stable result id `port_type::${edge.id}` for dedup.
//
// Pure function: zero useStore imports, zero React imports.

import type { Validator, ValidationResult } from "../types";
import type { ValidationSnapshot } from "../snapshot";
import { isAllowedBCConnection } from "../../bcMode";

export const portType: Validator = {
  id: "port_type",
  severity: "error",
  description: "Incompatible port types",
  scope: ["edges"],

  run(snapshot: ValidationSnapshot): ValidationResult[] {
    const results: ValidationResult[] = [];

    for (const edge of snapshot.edges) {
      const srcNode = snapshot.nodes.find((n) => n.id === edge.source);
      const tgtNode = snapshot.nodes.find((n) => n.id === edge.target);

      if (!srcNode || !tgtNode) {
        // Defensive: cannot validate an edge with missing nodes
        continue;
      }

      const srcData = srcNode.data as {
        componentId: string;
        instanceName: string;
      };
      const tgtData = tgtNode.data as {
        componentId: string;
        instanceName: string;
      };

      // Phase 71 UAT (2026-05-21): reject self-loops outright.
      // A component connecting to itself is never physically meaningful in
      // the steady-state network model. Because CanvasPanel.isValidConnection
      // delegates to this rule via D-19, this also hard-blocks the candidate
      // edge at drop time — the user cannot draw a self-loop on the canvas.
      if (edge.source === edge.target) {
        const srcHandle = edge.sourceHandle ?? "unknown";
        const tgtHandle = edge.targetHandle ?? "unknown";
        results.push({
          id: `port_type::${edge.id}`,
          validatorId: "port_type",
          severity: "error",
          description: `${srcData.instanceName}.${srcHandle} → ${srcData.instanceName}.${tgtHandle}: self-loop`,
          targets: [
            { kind: "edge", edgeId: edge.id },
            { kind: "port", nodeId: edge.source, portName: srcHandle },
          ],
        });
        continue;
      }

      const srcDef = snapshot.getComponentDef(srcData.componentId);
      const tgtDef = snapshot.getComponentDef(tgtData.componentId);

      if (!srcDef || !tgtDef) {
        // Cannot validate without component definitions
        continue;
      }

      const srcPort = srcDef.ports.find((p) => p.name === edge.sourceHandle);
      const tgtPort = tgtDef.ports.find((p) => p.name === edge.targetHandle);

      if (!srcPort || !tgtPort) {
        // Cannot validate without resolved port objects (e.g., handle name mismatch)
        continue;
      }

      const srcType = srcPort.type;
      const tgtType = tgtPort.type;

      let isInvalid = false;

      if (srcType === "BCPort" && tgtType === "BCPort") {
        // Both BCPort: consult the allow-list
        if (!isAllowedBCConnection(srcData.componentId, tgtData.componentId)) {
          isInvalid = true;
        }
      } else if (srcType === "BCPort" || tgtType === "BCPort") {
        // Mixed BCPort with non-BCPort: always invalid
        isInvalid = true;
      } else if (srcType !== tgtType) {
        // Incompatible non-BCPort types (e.g., FlowPort ↔ ThermalPort)
        isInvalid = true;
      }

      if (isInvalid) {
        const srcHandle = edge.sourceHandle ?? "unknown";
        const tgtHandle = edge.targetHandle ?? "unknown";

        results.push({
          id: `port_type::${edge.id}`,
          validatorId: "port_type",
          severity: "error",
          description: `${srcData.instanceName}.${srcHandle} → ${tgtData.instanceName}.${tgtHandle}: ${srcType} ↔ ${tgtType}`,
          targets: [
            { kind: "edge", edgeId: edge.id },
            { kind: "port", nodeId: edge.source, portName: srcHandle },
            { kind: "port", nodeId: edge.target, portName: tgtHandle },
          ],
        });
      }
    }

    return results;
  },
};
