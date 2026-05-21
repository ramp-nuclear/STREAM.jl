// lengthMatch.ts — Active length consistency validator (Phase 71, Plan 05)
//
// D-15 rule 2: "length match" — when a ChannelAndContacts (CAC) is thermally
// connected to a HeatDiffusion (HD), the CAC's geometry resource L must equal
// HD.Lz.
//
// Phase 62 reinterpretation: CAC.geometry is a Resource-FK UUID — the actual
// length lives in snapshot.resources.geometries[uuid].params.L. The rule must
// resolve the UUID before comparison.
//
// §3.9 line 792: error severity; value-transfer-picker fix.
// D-14: edge-level rule emits edge + both endpoint field and node targets.
// D-12: fieldPath 'geometry' for CAC (highlights the resource-picker),
//       'Lz' for HD.
//
// FixAction: value-transfer-picker — user picks which length is canonical.
//   applyLeft: CAC.geometry.L propagates to HD.Lz (node-param write).
//   applyRight: HD.Lz propagates to CAC geometry resource (resource write).
//
// Per §3.9 lines 768-778: "changing length makes the component physically
// different; the GUI cannot guess which side the user actually meant."
// Never auto-apply — always require user pick.
//
// The apply closures take (set, get) as parameters so ValidationPanel
// (Plan 09) passes fresh store handles at click time (RESEARCH §Pitfall 7).
//
// Pure function: zero useStore imports, zero React imports (D-06).

import type { Validator, ValidationResult } from "../types";
import type { ValidationSnapshot } from "../snapshot";

export const lengthMatch: Validator = {
  id: "length_match",
  severity: "error",
  description: "CAC geometry length (L) does not match HeatDiffusion Lz",
  scope: ["nodes", "edges", "resources"],

  run(snapshot: ValidationSnapshot): ValidationResult[] {
    const results: ValidationResult[] = [];

    // Collect thermal edges grouped by unordered (CAC, HD) node-pair.
    // key = `${sortedId1}::${sortedId2}`
    const pairEdges = new Map<
      string,
      { cacId: string; hdId: string; edgeIds: string[] }
    >();

    for (const edge of snapshot.edges) {
      const srcNode = snapshot.nodes.find((n) => n.id === edge.source);
      const tgtNode = snapshot.nodes.find((n) => n.id === edge.target);
      if (!srcNode || !tgtNode) continue;

      const srcData = srcNode.data as {
        componentId: string;
        instanceName: string;
        parameters: Record<string, unknown>;
      };
      const tgtData = tgtNode.data as {
        componentId: string;
        instanceName: string;
        parameters: Record<string, unknown>;
      };

      const srcDef = snapshot.getComponentDef(srcData.componentId);
      const tgtDef = snapshot.getComponentDef(tgtData.componentId);
      if (!srcDef || !tgtDef) continue;

      // Filter to thermal edges only.
      const srcPort = srcDef.ports.find((p) => p.name === edge.sourceHandle);
      const tgtPort = tgtDef.ports.find((p) => p.name === edge.targetHandle);
      if (!srcPort || !tgtPort) continue;
      if (srcPort.type !== "ThermalPort" || tgtPort.type !== "ThermalPort") continue;

      // Identify which side is CAC and which is HD.
      let cacId: string | null = null;
      let hdId: string | null = null;

      if (
        srcData.componentId === "ChannelAndContacts" &&
        tgtData.componentId === "HeatDiffusion"
      ) {
        cacId = edge.source;
        hdId = edge.target;
      } else if (
        tgtData.componentId === "ChannelAndContacts" &&
        srcData.componentId === "HeatDiffusion"
      ) {
        cacId = edge.target;
        hdId = edge.source;
      } else {
        continue;
      }

      if (!cacId || !hdId) continue;

      const pairKey = [cacId, hdId].sort().join("::");
      const existing = pairEdges.get(pairKey);
      if (existing) {
        existing.edgeIds.push(edge.id);
      } else {
        pairEdges.set(pairKey, { cacId, hdId, edgeIds: [edge.id] });
      }
    }

    // For each unique pair, compare geometry.params.L vs Lz.
    for (const [, { cacId, hdId, edgeIds }] of pairEdges) {
      const cacNode = snapshot.nodes.find((n) => n.id === cacId);
      const hdNode = snapshot.nodes.find((n) => n.id === hdId);
      if (!cacNode || !hdNode) continue;

      const cacData = cacNode.data as {
        componentId: string;
        instanceName: string;
        parameters: Record<string, unknown>;
      };
      const hdData = hdNode.data as {
        componentId: string;
        instanceName: string;
        parameters: Record<string, unknown>;
      };

      // Resolve the CAC's geometry resource UUID.
      const geomUuid = cacData.parameters.geometry;
      if (typeof geomUuid !== "string" || !geomUuid) continue;

      // Look up the resource.
      const geomResource = snapshot.resources.geometries[geomUuid];
      if (!geomResource) continue; // dangling UUID — skip (another rule handles it)

      const cacL = geomResource.params.L;
      if (typeof cacL !== "number") continue;

      // Read HD.Lz.
      const hdLz = hdData.parameters.Lz;
      if (typeof hdLz !== "number") continue;

      if (cacL === hdLz) continue;

      const edgeId = edgeIds[0];
      const pairKey = [cacId, hdId].sort().join("::");

      // Capture primitives for closures (safe — no snapshot reference).
      const cacIdCapture = cacId;
      const hdIdCapture = hdId;
      const cacLCapture = cacL;
      const hdLzCapture = hdLz;
      const geomUuidCapture = geomUuid;

      results.push({
        id: `length_match::${pairKey}`,
        validatorId: "length_match",
        severity: "error",
        description: `${cacData.instanceName} geometry L (${cacL}) does not match ${hdData.instanceName}.Lz (${hdLz})`,
        targets: [
          { kind: "edge", edgeId },
          { kind: "field", nodeId: cacId, fieldPath: "geometry" },
          { kind: "field", nodeId: hdId, fieldPath: "Lz" },
          { kind: "node", nodeId: cacId },
          { kind: "node", nodeId: hdId },
        ],
        fixAction: {
          kind: "value-transfer-picker",
          leftLabel: `Use ${cacLCapture}`,
          rightLabel: `Use ${hdLzCapture}`,
          applyLeft: (_set, get) => {
            // CAC's L propagates to HD.Lz — direct node-param write.
            const live = get();
            live.updateNodeParams(hdIdCapture, { parameters: { Lz: cacLCapture } });
          },
          applyRight: (_set, get) => {
            // HD's Lz propagates to the CAC's geometry resource.
            // Must read current geometry resource params to preserve other fields.
            const live = get();
            const currentGeom = live.resources?.geometries?.[geomUuidCapture];
            const currentParams = currentGeom?.params ?? {};
            live.updateResource("geometry", geomUuidCapture, {
              params: { ...currentParams, L: hdLzCapture },
            });
          },
        },
      });
    }

    return results;
  },
};
