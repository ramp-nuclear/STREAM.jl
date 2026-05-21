// zNMatch.ts — Z-axis node-count consistency validator (Phase 71, Plan 05)
//
// D-15 rule 1: "z_N match" — when a ChannelAndContacts (CAC) is thermally
// connected to a HeatDiffusion (HD), CAC.n must equal HD.nz.
//
// §3.9 line 790: error severity; lossless-sync fix.
// D-14: edge-level rule emits edge + both endpoint field and node targets.
// D-12: fieldPath 'n' for CAC, 'nz' for HD (property-panel red highlight).
//
// FixAction: lossless-sync — picks Math.max(cac.n, hd.nz) and writes to both
// sides. The apply closure takes (set, get) as parameters so ValidationPanel
// (Plan 09) passes fresh store handles at click time (RESEARCH §Pitfall 7).
//
// Pure function: zero useStore imports, zero React imports (D-06).

import type { Validator, ValidationResult } from "../types";
import type { ValidationSnapshot } from "../snapshot";

export const zNMatch: Validator = {
  id: "z_n_match",
  severity: "error",
  description: "CAC.n ≠ HD.nz",
  scope: ["nodes", "edges"],

  run(snapshot: ValidationSnapshot): ValidationResult[] {
    const results: ValidationResult[] = [];

    // Collect thermal edges grouped by unordered node-pair.
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
      // Either order (source=CAC, target=HD or reversed) is valid.
      let cacId: string | null = null;
      let hdId: string | null = null;

      if (srcData.componentId === "ChannelAndContacts" && tgtData.componentId === "HeatDiffusion") {
        cacId = edge.source;
        hdId = edge.target;
      } else if (tgtData.componentId === "ChannelAndContacts" && srcData.componentId === "HeatDiffusion") {
        cacId = edge.target;
        hdId = edge.source;
      } else {
        // Neither or one side is unknown — check if one side has `nz` and the other has `n`
        // as a fallback for non-standard topologies (Plate-style nodes).
        const srcParams = srcData.parameters as Record<string, unknown>;
        const tgtParams = tgtData.parameters as Record<string, unknown>;
        const srcHasN = "n" in srcParams && typeof srcParams.n === "number";
        const tgtHasNz = "nz" in tgtParams && typeof tgtParams.nz === "number";
        const tgtHasN = "n" in tgtParams && typeof tgtParams.n === "number";
        const srcHasNz = "nz" in srcParams && typeof srcParams.nz === "number";

        if (srcHasN && tgtHasNz) {
          cacId = edge.source;
          hdId = edge.target;
        } else if (tgtHasN && srcHasNz) {
          cacId = edge.target;
          hdId = edge.source;
        } else {
          continue;
        }
      }

      if (!cacId || !hdId) continue;

      // Build a stable unordered pair key.
      const pairKey = [cacId, hdId].sort().join("::");
      const existing = pairEdges.get(pairKey);
      if (existing) {
        existing.edgeIds.push(edge.id);
      } else {
        pairEdges.set(pairKey, { cacId, hdId, edgeIds: [edge.id] });
      }
    }

    // For each unique pair, compare n vs nz.
    for (const [, { cacId, hdId, edgeIds }] of pairEdges) {
      const cacNode = snapshot.nodes.find((n) => n.id === cacId);
      const hdNode = snapshot.nodes.find((n) => n.id === hdId);
      if (!cacNode || !hdNode) continue;

      const cacParams = (cacNode.data as { parameters: Record<string, unknown> }).parameters;
      const hdParams = (hdNode.data as { parameters: Record<string, unknown> }).parameters;

      const cacData = cacNode.data as { componentId: string; instanceName: string };
      const hdData = hdNode.data as { componentId: string; instanceName: string };

      // Resolve n on the CAC side.
      let cacN: number | null = null;
      if (cacData.componentId === "ChannelAndContacts") {
        if (typeof cacParams.n === "number") cacN = cacParams.n;
      } else {
        // Fallback: whichever field is present.
        if (typeof cacParams.n === "number") cacN = cacParams.n;
      }

      // Resolve nz on the HD side.
      let hdNz: number | null = null;
      if (hdData.componentId === "HeatDiffusion") {
        if (typeof hdParams.nz === "number") hdNz = hdParams.nz;
      } else {
        if (typeof hdParams.nz === "number") hdNz = hdParams.nz;
      }

      if (cacN === null || hdNz === null) continue;
      if (cacN === hdNz) continue;

      const edgeId = edgeIds[0]; // first edge for the edge target

      const pairKey = [cacId, hdId].sort().join("::");
      // Phase 71 UAT (2026-05-21): FixActions removed across all rules.
      // User rejected opinionated auto-fix directions — set values manually.
      // Row click still focuses node via ValidationPanel.
      results.push({
        id: `z_n_match::${pairKey}`,
        validatorId: "z_n_match",
        severity: "error",
        description: `${cacData.instanceName}.n=${cacN} ≠ ${hdData.instanceName}.nz=${hdNz}`,
        targets: [
          { kind: "edge", edgeId },
          { kind: "field", nodeId: cacId, fieldPath: "n" },
          { kind: "field", nodeId: hdId, fieldPath: "nz" },
          { kind: "node", nodeId: cacId },
          { kind: "node", nodeId: hdId },
        ],
      });
    }

    return results;
  },
};
