// nMatch.test.ts — Unit tests for the nMatch validator (Phase 71, Plan 06)
//
// D-15 rule 3: "n-match (sources)" — when a value-source (WallTemperature /
// HeatFluxSource) is bound to a Channel/CHF/CAC via bcMode with mode='source',
// the source.n must equal the consumer.n.
//
// D-20: Supersedes selectNodeErrors n-mismatch check as the single source of truth.
//
// Test cases:
//   1. WT (n=3) bound to Channel (n=3) via bcMode source → no result (matching)
//   2. WT (n=4) bound to Channel (n=3) via bcMode source → 1 error (mismatch)
//   3. Same WT bound to two consumers, one matching one not → 1 result
//   4. No source-mode bindings → no result
//   5. Source-mode binding where consumer.n is undefined → no result (defensive)
//   6. HFS bound to CHF via source binding with n mismatch → symmetric error
//   7. fixAction is lossless-sync with label "Sync n to <consumerN>" (channel wins)
//   8. fixAction.apply calls updateNodeParams(sourceId, 'n', consumerN) — channel-wins policy

import { describe, it, expect } from "vitest";
import type { Node } from "@xyflow/react";
import type { BCModeEntry } from "../../../bcMode";
import type { ValidationSnapshot } from "../../snapshot";

import { nMatch } from "../nMatch";

// ---------------------------------------------------------------------------
// Node factory
// ---------------------------------------------------------------------------

function makeNode(
  id: string,
  componentId: string,
  instanceName: string,
  parameters: Record<string, unknown> = {},
): Node {
  return {
    id,
    type: "streamNode",
    position: { x: 0, y: 0 },
    data: { componentId, instanceName, parameters },
  };
}

// ---------------------------------------------------------------------------
// Snapshot factory
// ---------------------------------------------------------------------------

function makeSnapshot(
  nodes: Node[],
  bcMode: Record<string, BCModeEntry> = {},
): ValidationSnapshot {
  return {
    nodes,
    edges: [],
    anchors: {},
    bcMode,
    resources: { geometries: {}, powerShapes: {}, fluids: {} },
    getComponentDef: () => undefined,
  };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("nMatch", () => {
  it("returns no result when WT.n matches Channel.n (both 3)", () => {
    const ch = makeNode("ch1", "Channel", "ch_1", { n: 3 });
    const wt = makeNode("wt1", "WallTemperature", "wt_1", { n: 3 });
    const bcMode: Record<string, BCModeEntry> = {
      "ch1::T_wall_left": { mode: "source", sourceNodeId: "wt1" },
    };
    const snapshot = makeSnapshot([ch, wt], bcMode);
    const results = nMatch.run(snapshot);
    expect(results).toHaveLength(0);
  });

  it("emits one error when WT.n=4 and Channel.n=3 are source-bound", () => {
    const ch = makeNode("ch1", "Channel", "ch_1", { n: 3 });
    const wt = makeNode("wt1", "WallTemperature", "wt_1", { n: 4 });
    const bcMode: Record<string, BCModeEntry> = {
      "ch1::T_wall_left": { mode: "source", sourceNodeId: "wt1" },
    };
    const snapshot = makeSnapshot([ch, wt], bcMode);
    const results = nMatch.run(snapshot);
    expect(results).toHaveLength(1);

    const r = results[0];
    expect(r.validatorId).toBe("n_match");
    expect(r.severity).toBe("error");

    // Description must carry offending values verbatim (D-13).
    expect(r.description).toContain("wt_1");
    expect(r.description).toContain("ch_1");
    expect(r.description).toContain("n=4");
    expect(r.description).toContain("n=3");

    // D-14: BOTH node targets.
    const nodeTargets = r.targets.filter((t) => t.kind === "node");
    expect(nodeTargets).toHaveLength(2);
    const nodeIds = nodeTargets.map((t) => (t as { kind: "node"; nodeId: string }).nodeId);
    expect(nodeIds).toContain("ch1");
    expect(nodeIds).toContain("wt1");

    // D-14: BOTH `n` field targets (symmetric).
    const fieldN = r.targets.filter(
      (t) => t.kind === "field" && (t as { kind: "field"; fieldPath: string }).fieldPath === "n",
    );
    expect(fieldN).toHaveLength(2);
    const fieldNNodeIds = fieldN.map((t) => (t as { kind: "field"; nodeId: string }).nodeId);
    expect(fieldNNodeIds).toContain("ch1");
    expect(fieldNNodeIds).toContain("wt1");

    // D-13: whole-array fieldPath for the BC field row.
    const bcFieldTarget = r.targets.find(
      (t) =>
        t.kind === "field" &&
        (t as { kind: "field"; fieldPath: string }).fieldPath === "T_wall_left",
    );
    expect(bcFieldTarget).toBeDefined();
    expect((bcFieldTarget as { nodeId: string }).nodeId).toBe("ch1");
  });

  it("emits only one result for the mismatched binding when WT is bound to two consumers", () => {
    const ch1 = makeNode("ch1", "Channel", "ch_1", { n: 3 });
    const ch2 = makeNode("ch2", "Channel", "ch_2", { n: 5 });
    // WT.n=3 matches ch1 but mismatches ch2
    const wt = makeNode("wt1", "WallTemperature", "wt_1", { n: 3 });
    const bcMode: Record<string, BCModeEntry> = {
      "ch1::T_wall_left": { mode: "source", sourceNodeId: "wt1" },
      "ch2::T_wall_left": { mode: "source", sourceNodeId: "wt1" },
    };
    const snapshot = makeSnapshot([ch1, ch2, wt], bcMode);
    const results = nMatch.run(snapshot);
    // Only ch2::wt1 binding is mismatched
    expect(results).toHaveLength(1);
    const r = results[0];
    // The mismatched binding targets ch2 and wt1
    const nodeIds = r.targets
      .filter((t) => t.kind === "node")
      .map((t) => (t as { kind: "node"; nodeId: string }).nodeId);
    expect(nodeIds).toContain("ch2");
    expect(nodeIds).toContain("wt1");
  });

  it("returns no result when there are no source-mode bindings", () => {
    const ch = makeNode("ch1", "Channel", "ch_1", { n: 3 });
    const wt = makeNode("wt1", "WallTemperature", "wt_1", { n: 5 });
    const bcMode: Record<string, BCModeEntry> = {
      "ch1::T_wall_left": { mode: "value", value: 300 },
    };
    const snapshot = makeSnapshot([ch, wt], bcMode);
    const results = nMatch.run(snapshot);
    expect(results).toHaveLength(0);
  });

  it("returns no result when consumer.n is undefined (defensive — another validator flags missing param)", () => {
    // Channel with no n param set
    const ch = makeNode("ch1", "Channel", "ch_1", {});
    const wt = makeNode("wt1", "WallTemperature", "wt_1", { n: 4 });
    const bcMode: Record<string, BCModeEntry> = {
      "ch1::T_wall_left": { mode: "source", sourceNodeId: "wt1" },
    };
    const snapshot = makeSnapshot([ch, wt], bcMode);
    const results = nMatch.run(snapshot);
    expect(results).toHaveLength(0);
  });

  it("emits a symmetric error for HFS bound to CHF with n mismatch", () => {
    const chf = makeNode("chf1", "ChannelHeatFlux", "chf_1", { n: 5 });
    const hfs = makeNode("hfs1", "HeatFluxSource", "hfs_1", { n: 8 });
    const bcMode: Record<string, BCModeEntry> = {
      "chf1::q_left": { mode: "source", sourceNodeId: "hfs1" },
    };
    const snapshot = makeSnapshot([chf, hfs], bcMode);
    const results = nMatch.run(snapshot);
    expect(results).toHaveLength(1);

    const r = results[0];
    expect(r.validatorId).toBe("n_match");
    expect(r.severity).toBe("error");

    // Symmetric node targets.
    const nodeTargets = r.targets.filter((t) => t.kind === "node");
    expect(nodeTargets).toHaveLength(2);

    // D-13: whole-array fieldPath for q_left.
    const qTarget = r.targets.find(
      (t) =>
        t.kind === "field" &&
        (t as { kind: "field"; fieldPath: string }).fieldPath === "q_left",
    );
    expect(qTarget).toBeDefined();
    expect((qTarget as { nodeId: string }).nodeId).toBe("chf1");

    // D-14: n field targets on BOTH sides.
    const nTargets = r.targets.filter(
      (t) => t.kind === "field" && (t as { kind: "field"; fieldPath: string }).fieldPath === "n",
    );
    expect(nTargets).toHaveLength(2);
  });

  // Phase 71 UAT Test 8 (2026-05-21): user removed the FixAction on nMatch.
  // Rule degrades to navigation-only; result.fixAction must be undefined.
  it("emits no fixAction (rule is navigation-only after UAT Test 8)", () => {
    const ch = makeNode("ch1", "Channel", "ch_1", { n: 3 });
    const wt = makeNode("wt1", "WallTemperature", "wt_1", { n: 4 });
    const bcMode: Record<string, BCModeEntry> = {
      "ch1::T_wall_left": { mode: "source", sourceNodeId: "wt1" },
    };
    const snapshot = makeSnapshot([ch, wt], bcMode);
    const results = nMatch.run(snapshot);
    expect(results).toHaveLength(1);
    expect(results[0].fixAction).toBeUndefined();
  });

  // Phase 71 UAT Test 8 dedup: multiple BC bindings between the same
  // (consumerId, sourceId) pair must produce a single result.
  it("dedupes results by (consumerId, sourceId) pair across multiple bindings", () => {
    const ch = makeNode("ch1", "Channel", "ch_1", { n: 3 });
    const wt = makeNode("wt1", "WallTemperature", "wt_1", { n: 4 });
    const bcMode: Record<string, BCModeEntry> = {
      "ch1::T_wall_left": { mode: "source", sourceNodeId: "wt1" },
      "ch1::T_wall_right": { mode: "source", sourceNodeId: "wt1" },
    };
    const snapshot = makeSnapshot([ch, wt], bcMode);
    const results = nMatch.run(snapshot);
    expect(results).toHaveLength(1);
  });
});
