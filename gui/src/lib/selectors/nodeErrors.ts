// nodeErrors.ts — Phase 63.1 (D-15..D-19, D-23): selector-derived validator
// that replaces the stored `errorTagsByNodeId` slice + `_checkBCNMismatch`
// event mutator with a pure pull-based function.
//
// Zero React dependencies, zero zustand dependencies, zero ReactFlow runtime
// imports — only `import type` from peer pure modules is allowed. This is the
// Phase 71 validator-as-selector foundation (D-19): each future validator
// follows the same `(state, nodeId) => string[]` shape.
//
// Consumers MUST wrap this in `useStore(useCallback(s => selectNodeErrors(s, id).length > 0, [id]))`
// and return a primitive boolean — never a fresh array — to avoid zustand's
// shallow-equality re-render loop (RESEARCH §"Pitfall 1").
//
// The body inverts the per-event `_checkBCNMismatch` mutator that used to
// live in useStore.ts (~1364-1385 pre-Phase-63.1): instead of writing tags on
// every (sourceNodeId, targetNodeId) event, we iterate `bcMode` once per
// render and surface a tag if any source-mode entry binds a (consumer, source)
// pair whose `parameters.n` values disagree.

import type { Node, Edge } from "@xyflow/react";
import type { BCModeEntry } from "../bcMode";

/** Shape of the (sub-)state slice that this selector consumes. The selector
 *  is intentionally NOT typed against the full AppState — it takes only the
 *  fields it needs, mirroring the purity contract on `validateTopology`. */
export interface NodeErrorsInput {
  nodes: Node[];
  edges: Edge[];
  bcMode: Record<string, BCModeEntry>;
  bcSymmetric: Record<string, boolean>;
  // reserved: anchors used by future validators (Phase 71)
  anchors: Record<string, { portField: "port_in.P" | "port_out.P"; value: number }>;
}

const TAG_BC_N_MISMATCH = "bc-n-mismatch";

function readN(node: Node | undefined): number | undefined {
  const params = (node?.data as { parameters?: Record<string, unknown> } | undefined)
    ?.parameters;
  const n = params?.["n"];
  return typeof n === "number" ? n : undefined;
}

/**
 * Pure selector: returns the BC-related error tags that apply to `nodeId`
 * for the current `state`. Currently emits `'bc-n-mismatch'` when a
 * source-mode bcMode entry binds two nodes whose `parameters.n` values
 * disagree — surfaced on BOTH the consumer side and the source side.
 *
 * Returns [] if the node has no source-mode binding, if the bound source's
 * n matches the consumer's n, or if either side's n is not a number.
 *
 * Pure function — no side effects, no store dependency, no React.
 */
export function selectNodeErrors(state: NodeErrorsInput, nodeId: string): string[] {
  const node = state.nodes.find((n) => n.id === nodeId);
  if (!node) return [];
  const myN = readN(node);
  const tags: string[] = [];

  // Iterate bcMode looking for either a consumer-side binding (key starts
  // with `${nodeId}::`) or a source-side binding (entry.sourceNodeId === nodeId).
  // First mismatched pair found pushes the tag; `break` guarantees
  // deduplication across multiple bindings.
  for (const [key, entry] of Object.entries(state.bcMode)) {
    if (entry.mode !== "source") continue;

    // Consumer-side iteration: this node is the consumer.
    if (key.startsWith(`${nodeId}::`)) {
      const sourceNode = state.nodes.find((n) => n.id === entry.sourceNodeId);
      const srcN = readN(sourceNode);
      if (typeof myN === "number" && typeof srcN === "number" && myN !== srcN) {
        tags.push(TAG_BC_N_MISMATCH);
        break;
      }
      continue;
    }

    // Source-side iteration: this node is the source for some consumer.
    if (entry.sourceNodeId === nodeId) {
      // Extract the consumer id from the key (`${consumerId}::${field}`).
      const sepIdx = key.indexOf("::");
      if (sepIdx < 0) continue;
      const consumerId = key.slice(0, sepIdx);
      const consumerNode = state.nodes.find((n) => n.id === consumerId);
      const consN = readN(consumerNode);
      if (typeof myN === "number" && typeof consN === "number" && myN !== consN) {
        tags.push(TAG_BC_N_MISMATCH);
        break;
      }
    }
  }

  return tags;
}
