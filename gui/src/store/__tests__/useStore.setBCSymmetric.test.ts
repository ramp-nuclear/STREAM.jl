// @vitest-environment happy-dom
// useStore.setBCSymmetric.test.ts — Phase 63.1 Plan 01 (Wave-0 RED).
//
// CR-02 (D-21): when symmetric is turned ON, and the left entry is undefined
//   while the right entry IS defined, the right entry must be DELETED (so
//   the pair collapses to "neither set" cleanly).
// CR-03 (D-21): when symmetric is turned ON and the left entry has mode
//   "source", the right entry must mirror that source-mode entry AND a
//   matching `type: "bcEdge"` edge from the source node to the right target
//   handle must be materialized.
//
// Today's setBCSymmetric (useStore.ts:1283-1303) only copies left → right
// in the bcMode map. It does NOT materialize the right-side edge and does
// NOT handle the CR-02 deletion path. The rewrite lands in Plan 05/06.
// @ts-nocheck — setBCSymmetric rewrite lands in Wave 1/2 / Plan 05/06.

import { describe, it, expect, beforeEach } from "vitest";
import type { Node } from "@xyflow/react";
import useStore from "../useStore";
import { bcModeKey } from "../../lib/bcMode";

beforeEach(() => {
  useStore.setState({
    nodes: [],
    edges: [],
    selectedNodeId: null,
    isDirty: false,
    _undoPast: [],
    _undoFuture: [],
    bcMode: {},
    bcSymmetric: {},
    anchors: {},
  });
});

function makeChannelNode(id: string, n: number): Node {
  return {
    id,
    type: "streamNode",
    position: { x: 0, y: 0 },
    data: {
      componentId: "Channel",
      instanceName: id,
      parameters: { n },
      constructorMode: "default",
    },
  };
}

function makeWallTemperatureNode(id: string, n: number): Node {
  return {
    id,
    type: "streamNode",
    position: { x: 100, y: 0 },
    data: {
      componentId: "WallTemperature",
      instanceName: id,
      parameters: { n, T_wall: 320 },
      constructorMode: "default",
    },
  };
}

describe("CR-02: symmetric ON with leftEntry undefined + rightEntry defined deletes right (D-21)", () => {
  it("deletes the right entry when left is undefined and right is value-mode", () => {
    useStore.setState({
      nodes: [makeChannelNode("ch1", 4)],
      bcMode: {
        [bcModeKey("ch1", "T_wall_right")]: { mode: "value", value: 300 },
      },
    });
    useStore.getState().setBCSymmetric("ch1", "T_wall", true);
    const rightEntry =
      useStore.getState().bcMode[bcModeKey("ch1", "T_wall_right")];
    expect(rightEntry).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// Plan 63.1-12 amend — regression tests for the per-baseField edge contract.
// Mirrors the user's failure-mode reproduction (2026-05-14):
//   1) Symmetric promote → asymmetric → set RIGHT to value → label flips to L
//      (edge survives, anchored to T_wall_left handle).
//   2) Symmetric promote → asymmetric → set LEFT to value → label flips to R
//      (edge survives, still anchored to T_wall_left handle).
//   3) Asymmetric promote of one side spawns a single edge regardless of
//      whether the promoted side is left or right.
// ---------------------------------------------------------------------------
describe("Plan 63.1-12 amend — bcEdge survives when only one side stays source-bound", () => {
  function seedSymmetricallyPromoted() {
    useStore.setState({
      nodes: [makeWallTemperatureNode("wt1", 4), makeChannelNode("ch1", 4)],
      edges: [
        {
          id: "e1",
          source: "wt1",
          sourceHandle: "T_wall_out",
          target: "ch1",
          targetHandle: "T_wall_left",
          type: "bcEdge",
          data: {
            componentId: "ch1",
            externalInputName: "T_wall_left",
            targetSide: "both",
          },
        },
      ],
      bcMode: {
        [bcModeKey("ch1", "T_wall_left")]: { mode: "source", sourceNodeId: "wt1" },
        [bcModeKey("ch1", "T_wall_right")]: { mode: "source", sourceNodeId: "wt1" },
      },
      bcSymmetric: { "ch1::T_wall": false },
    });
  }

  it("asymmetric: setting RIGHT to value keeps the edge (left still bound)", () => {
    seedSymmetricallyPromoted();
    useStore
      .getState()
      .setBCMode("ch1", "T_wall_right", { mode: "value", value: 320 });
    const state = useStore.getState();
    const leftEntry = state.bcMode[bcModeKey("ch1", "T_wall_left")];
    expect(leftEntry).toEqual({ mode: "source", sourceNodeId: "wt1" });
    const bcEdges = state.edges.filter((e) => e.type === "bcEdge" && e.target === "ch1");
    expect(bcEdges).toHaveLength(1);
    expect(bcEdges[0].targetHandle).toBe("T_wall_left");
  });

  it("asymmetric: setting LEFT to value keeps the edge (right still bound)", () => {
    seedSymmetricallyPromoted();
    useStore
      .getState()
      .setBCMode("ch1", "T_wall_left", { mode: "value", value: 320 });
    const state = useStore.getState();
    const rightEntry = state.bcMode[bcModeKey("ch1", "T_wall_right")];
    expect(rightEntry).toEqual({ mode: "source", sourceNodeId: "wt1" });
    const bcEdges = state.edges.filter((e) => e.type === "bcEdge" && e.target === "ch1");
    expect(bcEdges).toHaveLength(1);
    // Edge MUST stay anchored to the consumer's actual BCPort handle.
    expect(bcEdges[0].targetHandle).toBe("T_wall_left");
  });

  it("asymmetric: setting BOTH sides to value removes the edge", () => {
    seedSymmetricallyPromoted();
    useStore
      .getState()
      .setBCMode("ch1", "T_wall_left", { mode: "value", value: 320 });
    useStore
      .getState()
      .setBCMode("ch1", "T_wall_right", { mode: "value", value: 350 });
    const state = useStore.getState();
    const bcEdges = state.edges.filter((e) => e.type === "bcEdge" && e.target === "ch1");
    expect(bcEdges).toHaveLength(0);
  });

  it("asymmetric: setting only the RIGHT side to source materializes an edge anchored to T_wall_left", () => {
    // No prior bcMode entries; symmetric off; set right alone.
    useStore.setState({
      nodes: [makeWallTemperatureNode("wt1", 4), makeChannelNode("ch1", 4)],
      edges: [],
      bcMode: {},
      bcSymmetric: { "ch1::T_wall": false },
    });
    useStore
      .getState()
      .setBCMode("ch1", "T_wall_right", { mode: "source", sourceNodeId: "wt1" });
    const state = useStore.getState();
    const bcEdges = state.edges.filter((e) => e.type === "bcEdge" && e.target === "ch1");
    expect(bcEdges).toHaveLength(1);
    expect(bcEdges[0].targetHandle).toBe("T_wall_left"); // consumer's real BCPort handle
    expect(bcEdges[0].source).toBe("wt1");
  });

  it("asymmetric: switching from source-A to source-B on one side swaps the edge source", () => {
    useStore.setState({
      nodes: [
        makeWallTemperatureNode("wt1", 4),
        makeWallTemperatureNode("wt2", 4),
        makeChannelNode("ch1", 4),
      ],
      edges: [
        {
          id: "e1",
          source: "wt1",
          sourceHandle: "T_wall_out",
          target: "ch1",
          targetHandle: "T_wall_left",
          type: "bcEdge",
          data: {
            componentId: "ch1",
            externalInputName: "T_wall_left",
            targetSide: "both",
          },
        },
      ],
      bcMode: {
        [bcModeKey("ch1", "T_wall_left")]: { mode: "source", sourceNodeId: "wt1" },
      },
      bcSymmetric: { "ch1::T_wall": false },
    });
    useStore
      .getState()
      .setBCMode("ch1", "T_wall_left", { mode: "source", sourceNodeId: "wt2" });
    const state = useStore.getState();
    const bcEdges = state.edges.filter((e) => e.type === "bcEdge" && e.target === "ch1");
    expect(bcEdges).toHaveLength(1);
    expect(bcEdges[0].source).toBe("wt2");
  });
});

describe("CR-03: symmetric ON mirrors source-mode and preserves the BC edge (D-21, amended Plan 63.1-12)", () => {
  it("mirrors source-mode left → right AND keeps a single bcEdge bound to the consumer's BCPort handle", () => {
    // Plan 63.1-12 amend: bcEdges are now keyed per (source, consumer,
    // baseField) with targetHandle = consumer's actual BCPort handle name
    // (T_wall_left on Channel). The mirror does NOT spawn a second edge
    // targeting "T_wall_right" — that handle does not exist on the consumer.
    useStore.setState({
      nodes: [makeWallTemperatureNode("wt1", 4), makeChannelNode("ch1", 4)],
      edges: [
        {
          id: "e1",
          source: "wt1",
          sourceHandle: "T_wall_out",
          target: "ch1",
          targetHandle: "T_wall_left",
          type: "bcEdge",
          data: {
            componentId: "ch1",
            externalInputName: "T_wall_left",
            targetSide: "both",
          },
        },
      ],
      bcMode: {
        [bcModeKey("ch1", "T_wall_left")]: {
          mode: "source",
          sourceNodeId: "wt1",
        },
      },
    });
    useStore.getState().setBCSymmetric("ch1", "T_wall", true);
    const state = useStore.getState();
    const rightEntry = state.bcMode[bcModeKey("ch1", "T_wall_right")];
    expect(rightEntry).toEqual({ mode: "source", sourceNodeId: "wt1" });
    // Exactly one bcEdge exists (the original T_wall_left edge survives).
    const bcEdges = state.edges.filter(
      (e) => e.type === "bcEdge" && e.target === "ch1",
    );
    expect(bcEdges).toHaveLength(1);
    expect(bcEdges[0].targetHandle).toBe("T_wall_left");
    expect(bcEdges[0].source).toBe("wt1");
  });
});
