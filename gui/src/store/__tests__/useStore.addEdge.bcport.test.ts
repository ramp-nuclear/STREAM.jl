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

function makeCHFNode(id: string, n: number): Node {
  return {
    id,
    type: "streamNode",
    position: { x: 0, y: 0 },
    data: {
      componentId: "ChannelHeatFlux",
      instanceName: id,
      parameters: { n },
      constructorMode: "default",
    },
  };
}

function makeHFSNode(id: string, n: number): Node {
  return {
    id,
    type: "streamNode",
    position: { x: 100, y: 0 },
    data: {
      componentId: "HeatFluxSource",
      instanceName: id,
      parameters: { n, q: 1e5 },
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

// ---------------------------------------------------------------------------
// Plan 63.1-12 (RC-2): drag from a value-source BCPort to the new BCPort
// TARGET handle on Channel / ChannelHeatFlux materializes the edge AND mirrors
// the bcMode entry to the sibling external_input when bcSymmetric is ON.
// ---------------------------------------------------------------------------
describe("RC-2: BCPort target handle drag flow (Channel + ChannelHeatFlux)", () => {
  it("WT.T_wall_out → Channel.T_wall_left creates a bcEdge AND mirrors both sides", () => {
    useStore.setState({
      nodes: [makeWallTemperatureNode("wt1", 4), makeChannelNode("ch1", 4)],
    });
    useStore.getState().addEdge({
      source: "wt1",
      sourceHandle: "T_wall_out",
      target: "ch1",
      targetHandle: "T_wall_left",
    });

    // Edge appears in state.edges keyed on the BC target handle.
    const edges = useStore.getState().edges;
    const bcEdge = edges.find(
      (e) =>
        e.source === "wt1" &&
        e.target === "ch1" &&
        e.targetHandle === "T_wall_left",
    );
    expect(bcEdge).toBeDefined();

    // Both sides' bcMode entries reference the WT source.
    const leftEntry = useStore.getState().bcMode[bcModeKey("ch1", "T_wall_left")];
    const rightEntry = useStore.getState().bcMode[bcModeKey("ch1", "T_wall_right")];
    expect(leftEntry).toEqual({ mode: "source", sourceNodeId: "wt1" });
    expect(rightEntry).toEqual({ mode: "source", sourceNodeId: "wt1" });
  });

  it("HFS.q_out → ChannelHeatFlux.q_left creates a bcEdge AND mirrors both sides", () => {
    useStore.setState({
      nodes: [makeHFSNode("hfs1", 4), makeCHFNode("chf1", 4)],
    });
    useStore.getState().addEdge({
      source: "hfs1",
      sourceHandle: "q_out",
      target: "chf1",
      targetHandle: "q_left",
    });

    const edges = useStore.getState().edges;
    const bcEdge = edges.find(
      (e) =>
        e.source === "hfs1" &&
        e.target === "chf1" &&
        e.targetHandle === "q_left",
    );
    expect(bcEdge).toBeDefined();

    const leftEntry = useStore.getState().bcMode[bcModeKey("chf1", "q_left")];
    const rightEntry = useStore.getState().bcMode[bcModeKey("chf1", "q_right")];
    expect(leftEntry).toEqual({ mode: "source", sourceNodeId: "hfs1" });
    expect(rightEntry).toEqual({ mode: "source", sourceNodeId: "hfs1" });
  });
});
