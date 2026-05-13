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

describe("CR-03: symmetric ON mirrors source-mode and adds the right-side BC edge (D-21)", () => {
  it("mirrors source-mode left → right AND materializes a bcEdge to the right handle", () => {
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
    const rightEdge = state.edges.find(
      (e) =>
        e.target === "ch1" &&
        e.targetHandle === "T_wall_right" &&
        e.type === "bcEdge",
    );
    expect(rightEdge).toBeDefined();
  });
});
