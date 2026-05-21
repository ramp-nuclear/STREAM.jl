// nMatch.ts — BC source n-mismatch validator (Phase 71, Plan 06)
//
// Supersedes gui/src/lib/selectors/nodeErrors.ts:selectNodeErrors per D-20.
// Plan 13 removes the selectNodeErrors + hasBCError subscription from
// gui/src/components/StreamNode.tsx after this rule is live.
// Emits a FixAction lossless-sync (channel n wins) per §3.9 line 794.
//
// D-15 rule 3: "n-match (sources)" — when a value-source (WallTemperature /
// HeatFluxSource) is bound to a Channel/CHF/CAC via bcMode entry
// mode='source', the source.n must equal consumer.n.
//
// §3.9 lines 793-795: error severity; lossless-sync fix.
// "Same error, identical treatment" as z_N match — same UX shape.
//
// D-13: Array-shaped BC fields (T_wall_left[1:n]) use whole-array fieldPath.
// D-14: Symmetric emission — targets include BOTH consumer and source field
//        targets (fieldPath:'n' on both) AND BOTH node targets so the property
//        panel highlights `n` on BOTH sides.
// D-20: Single source of truth — replaces selectNodeErrors n-mismatch check.
//
// FixAction: lossless-sync — channel n is canonical (derives from z_N / L);
// the source is downstream of that decision. apply() propagates consumer→source
// (NOT max-wins — channel always wins). This differs from zNMatch (Plan 05)
// which uses max-wins because that pair has no canonical side.
//
// Pure function: zero store imports, zero React imports (D-06).

import type { Validator, ValidationResult } from "../types";
import type { ValidationSnapshot } from "../snapshot";

export const nMatch: Validator = {
  id: "n_match",
  severity: "error",
  description: "Value-source n does not match the bound channel's n",
  scope: ["nodes", "bcMode"],

  run(snapshot: ValidationSnapshot): ValidationResult[] {
    const results: ValidationResult[] = [];

    for (const [key, entry] of Object.entries(snapshot.bcMode)) {
      // Only source-mode bindings are relevant.
      if (entry.mode !== "source") continue;
      if (!entry.sourceNodeId) continue;

      // Parse the key: `${consumerId}::${externalInputName}`
      const sepIdx = key.indexOf("::");
      if (sepIdx < 0) continue;

      const consumerId = key.slice(0, sepIdx);
      const externalInputName = key.slice(sepIdx + 2);
      const sourceId = entry.sourceNodeId;

      const consumerNode = snapshot.nodes.find((n) => n.id === consumerId);
      const sourceNode = snapshot.nodes.find((n) => n.id === sourceId);
      if (!consumerNode || !sourceNode) continue;

      const consumerParams = (
        consumerNode.data as { parameters?: Record<string, unknown> }
      ).parameters;
      const sourceParams = (
        sourceNode.data as { parameters?: Record<string, unknown> }
      ).parameters;

      if (!consumerParams || !sourceParams) continue;

      const consumerN = consumerParams["n"];
      const sourceN = sourceParams["n"];

      // Defensive: if either n is not a number (undefined / unset), skip.
      // Another validator should flag the missing parameter.
      if (typeof consumerN !== "number" || typeof sourceN !== "number") continue;

      // No mismatch — nothing to emit.
      if (consumerN === sourceN) continue;

      const consumerData = consumerNode.data as {
        componentId: string;
        instanceName: string;
      };
      const sourceData = sourceNode.data as {
        componentId: string;
        instanceName: string;
      };

      // Capture primitives at rule-run time for the closure — safe (no snapshot
      // reference). Channel n is canonical; propagate consumer→source.
      const consumerNCapture: number = consumerN;
      const sourceIdCapture: string = sourceId;

      results.push({
        id: `n_match::${consumerId}::${externalInputName}::${sourceId}`,
        validatorId: "n_match",
        severity: "error",
        description:
          `${sourceData.instanceName} (n=${sourceN}) bound to ` +
          `${consumerData.instanceName} (n=${consumerN}) — mismatched cell counts`,
        targets: [
          // D-14: node targets for canvas red-ring on both sides.
          { kind: "node", nodeId: consumerId },
          { kind: "node", nodeId: sourceId },
          // D-14: field targets for property-panel highlights on both n fields.
          { kind: "field", nodeId: consumerId, fieldPath: "n" },
          { kind: "field", nodeId: sourceId, fieldPath: "n" },
          // D-13: whole-array fieldPath for the BC field row on the consumer side.
          { kind: "field", nodeId: consumerId, fieldPath: externalInputName },
        ],
        fixAction: {
          kind: "lossless-sync",
          // §3.9 lines 993-995 canonical example: "Sync n to 3"
          // Channel n wins — terse label names the parameter and the winning value.
          label: `Sync n to ${consumerNCapture}`,
          apply: (_set, get) => {
            // Re-read live state at invocation time (RESEARCH §Pitfall 7).
            // Channel n is canonical (derives from z_N / L); propagate to source.
            const live = get();
            live.updateNodeParams(sourceIdCapture, {
              parameters: { n: consumerNCapture },
            });
          },
        },
      });
    }

    return results;
  },
};
