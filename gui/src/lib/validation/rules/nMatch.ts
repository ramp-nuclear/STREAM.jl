// nMatch.ts — BC source n-mismatch validator.
//
// Supersedes gui/src/lib/selectors/nodeErrors.ts:selectNodeErrors per D-20.
//
// D-15 rule 3: "n-match (sources)" — when a value-source (WallTemperature /
// HeatFluxSource) is bound to a Channel/CHF/CAC via bcMode entry
// mode='source', the source.n must equal consumer.n.
//
// D-13: Array-shaped BC fields (T_wall_left[1:n]) use whole-array fieldPath.
// D-14: Symmetric emission — targets include BOTH consumer and source field
//        targets (fieldPath:'n' on both) AND BOTH node targets so the property
//        panel highlights `n` on BOTH sides.
// D-20: Single source of truth — replaces selectNodeErrors n-mismatch check.
//
// Navigation-only: row click in ValidationPanel focuses the offending pair;
// user fixes n manually. Auto-fix buttons were removed Phase 71 UAT
// (feedback_no_validator_fixaction_buttons).
//
// Pure function: zero store imports, zero React imports (D-06).

import type { Validator, ValidationResult } from "../types";
import type { ValidationSnapshot } from "../snapshot";

export const nMatch: Validator = {
  id: "n_match",
  severity: "error",
  description: "n mismatch on source binding",
  scope: ["nodes", "bcMode"],

  run(snapshot: ValidationSnapshot): ValidationResult[] {
    const results: ValidationResult[] = [];
    // Phase 71 UAT Test 8 (2026-05-21): dedup by (consumerId, sourceId) pair.
    // Multiple external-input bindings between the same consumer/source produced
    // duplicate rows in the panel; the user-observable mismatch is one fact.
    const seen = new Set<string>();

    for (const [key, entry] of Object.entries(snapshot.bcMode)) {
      if (entry.mode !== "source") continue;
      if (!entry.sourceNodeId) continue;

      const sepIdx = key.indexOf("::");
      if (sepIdx < 0) continue;

      const consumerId = key.slice(0, sepIdx);
      const externalInputName = key.slice(sepIdx + 2);
      const sourceId = entry.sourceNodeId;

      const pairKey = `${consumerId}::${sourceId}`;
      if (seen.has(pairKey)) continue;

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

      if (typeof consumerN !== "number" || typeof sourceN !== "number") continue;
      if (consumerN === sourceN) continue;

      seen.add(pairKey);

      const consumerData = consumerNode.data as {
        componentId: string;
        instanceName: string;
      };
      const sourceData = sourceNode.data as {
        componentId: string;
        instanceName: string;
      };

      // Phase 71 UAT Test 8: fix action removed by user request. Channel-wins
      // direction is opinionated; user wants to set both sides manually.
      // Rule degrades to navigation-only (no apply closure, row click focuses
      // the consumer node via ValidationPanel's standard handler).
      results.push({
        id: `n_match::${consumerId}::${sourceId}`,
        validatorId: "n_match",
        severity: "error",
        description: `${consumerData.instanceName}.n=${consumerN} ≠ ${sourceData.instanceName}.n=${sourceN}`,
        targets: [
          { kind: "node", nodeId: consumerId },
          { kind: "node", nodeId: sourceId },
          { kind: "field", nodeId: consumerId, fieldPath: "n" },
          { kind: "field", nodeId: sourceId, fieldPath: "n" },
          { kind: "field", nodeId: consumerId, fieldPath: externalInputName },
        ],
      });
    }

    return results;
  },
};
