// geometryConsistency.ts — Geometry consistency across shared coupling (Phase 71, Plan 05)
//
// D-15 rule 9: "geometry consistency across shared coupling" — when two CACs
// share one HD plate (each thermally connected to the same HD on opposite sides),
// their geometry resources must agree on cross-section fields (L, W/H/D).
//
// Planner-discretion rationale (§3.9 spirit — rule 9 has no explicit FixAction assignment):
//   Navigation-only is the right disposition here because:
//   (a) The mismatch can span multiple fields of the geometry resource (L, W, H, D).
//   (b) When 3+ surfaces (CAC1, CAC2, HD) participate, there is no single dominant
//       pair to transfer between.
//   (c) The Julia solver tolerates this with a runtime warning — it's a config smell,
//       not a hard invariant. Manual review is safer than an automatic fix.
//
// Severity: 'warning' (not 'error') — Julia does not hard-fail on this.
// FixAction: navigation-only — "Go to components"; no apply closure.
//
// Pure function: zero useStore imports, zero React imports (D-06).

import type { Validator, ValidationResult } from "../types";
import type { ValidationSnapshot } from "../snapshot";

export const geometryConsistency: Validator = {
  id: "geometry_consistency",
  severity: "warning",
  description: "Inconsistent geometry on shared HD",
  scope: ["nodes", "edges", "resources"],

  run(snapshot: ValidationSnapshot): ValidationResult[] {
    const results: ValidationResult[] = [];

    // Build a map: hdId → Set<cacId> (CACs thermally connected to this HD).
    // Also track: hdId → Map<cacId, firstEdgeId> for edge targets.
    const hdToCacs = new Map<string, Map<string, string>>(); // hdId → (cacId → edgeId)

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

      // Identify CAC and HD sides.
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

      if (!hdToCacs.has(hdId)) {
        hdToCacs.set(hdId, new Map());
      }
      const cacMap = hdToCacs.get(hdId)!;
      if (!cacMap.has(cacId)) {
        cacMap.set(cacId, edge.id);
      }
    }

    // For each HD with 2+ connected CACs, check geometry consistency.
    for (const [hdId, cacMap] of hdToCacs) {
      if (cacMap.size < 2) continue; // rule only fires for shared coupling (2+ CACs)

      const hdNode = snapshot.nodes.find((n) => n.id === hdId);
      if (!hdNode) continue;
      const hdData = hdNode.data as { componentId: string; instanceName: string };

      // Resolve geometry params for each CAC.
      const cacGeomParams: Array<{
        cacId: string;
        instanceName: string;
        geomParams: Record<string, unknown>;
        edgeId: string;
      }> = [];

      for (const [cacId, edgeId] of cacMap) {
        const cacNode = snapshot.nodes.find((n) => n.id === cacId);
        if (!cacNode) continue;
        const cacData = cacNode.data as {
          componentId: string;
          instanceName: string;
          parameters: Record<string, unknown>;
        };

        const geomUuid = cacData.parameters.geometry;
        if (typeof geomUuid !== "string" || !geomUuid) continue;

        const geomResource = snapshot.resources.geometries[geomUuid];
        if (!geomResource) continue;

        cacGeomParams.push({
          cacId,
          instanceName: cacData.instanceName,
          geomParams: geomResource.params as Record<string, unknown>,
          edgeId,
        });
      }

      if (cacGeomParams.length < 2) continue;

      // Compare pairwise — any field disagreement triggers a warning.
      const refParams = cacGeomParams[0].geomParams;
      let hasDisagreement = false;

      for (let i = 1; i < cacGeomParams.length; i++) {
        const otherParams = cacGeomParams[i].geomParams;
        for (const key of new Set([
          ...Object.keys(refParams),
          ...Object.keys(otherParams),
        ])) {
          const refVal = refParams[key];
          const otherVal = otherParams[key];
          // Only compare defined numeric fields; undefined on one side is OK
          // (different geometry types may have different optional fields).
          if (
            typeof refVal === "number" &&
            typeof otherVal === "number" &&
            refVal !== otherVal
          ) {
            hasDisagreement = true;
            break;
          }
        }
        if (hasDisagreement) break;
      }

      if (!hasDisagreement) continue;

      // Build targets: both CAC field targets + all node targets (both CACs + HD).
      const targets: ValidationResult["targets"] = [];

      // Edge targets: first edge for each CAC pair.
      if (cacGeomParams[0]) {
        targets.push({ kind: "edge", edgeId: cacGeomParams[0].edgeId });
      }

      // Field targets for each CAC (fieldPath: 'geometry' per Phase 62 resource-FK).
      for (const { cacId } of cacGeomParams) {
        targets.push({ kind: "field", nodeId: cacId, fieldPath: "geometry" });
      }

      // Node targets for all involved nodes.
      for (const { cacId } of cacGeomParams) {
        targets.push({ kind: "node", nodeId: cacId });
      }
      targets.push({ kind: "node", nodeId: hdId });

      // Build the result id: stable per HD node.
      const pairKey = [hdId, ...cacGeomParams.map((c) => c.cacId).sort()].join("::");
      const cacNames = cacGeomParams.map((c) => c.instanceName).join(", ");

      // Phase 71 UAT (2026-05-21): FixActions removed across all rules.
      results.push({
        id: `geometry_consistency::${pairKey}`,
        validatorId: "geometry_consistency",
        severity: "warning",
        description: `${cacNames} → ${hdData.instanceName}: geometry resources differ`,
        targets,
      });
    }

    return results;
  },
};
