// @vitest-environment happy-dom
// useStore.addEdge.bcport.test.ts — Phase 63.1 Plan 01 (Wave-0 RED).
//
// CR-01 (D-20): canvas-drag of a BC edge from a WallTemperature source to a
// channel external input must also WRITE the corresponding `bcMode` entry,
// not just append the edge. Today `addEdge` records the edge and only runs
// the n-mismatch check; it does not persist the source-mode bcMode entry,
// so codegen / re-render diverges from the visible canvas state.
//
// Sibling-symmetric requirement: when the dropped target is `T_wall_left`
// and symmetric is ON (default true), the right sibling entry must also be
// materialized so codegen emits both sides.
// @ts-nocheck — addEdge.BCPort branch is rewritten in Wave 1 / Plan 05.

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

describe("CR-01: addEdge BCPort branch writes bcMode entry (D-20)", () => {
  it("writes a source-mode bcMode entry on canvas-drag of a BC edge", () => {
    useStore.setState({
      nodes: [makeWallTemperatureNode("wt1", 4), makeChannelNode("ch1", 4)],
    });
    useStore.getState().addEdge({
      source: "wt1",
      sourceHandle: "T_wall_out",
      target: "ch1",
      targetHandle: "T_wall_left",
    });
    const entry = useStore.getState().bcMode[bcModeKey("ch1", "T_wall_left")];
    expect(entry).toEqual({ mode: "source", sourceNodeId: "wt1" });
  });

  it("writes sibling bcMode entry when symmetric (default true) and target is *_left", () => {
    useStore.setState({
      nodes: [makeWallTemperatureNode("wt1", 4), makeChannelNode("ch1", 4)],
    });
    useStore.getState().addEdge({
      source: "wt1",
      sourceHandle: "T_wall_out",
      target: "ch1",
      targetHandle: "T_wall_left",
    });
    const rightEntry = useStore.getState().bcMode[bcModeKey("ch1", "T_wall_right")];
    expect(rightEntry).toEqual({ mode: "source", sourceNodeId: "wt1" });
  });
});
