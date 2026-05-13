// @vitest-environment happy-dom
//
// Phase 63 D-21 / D-22 — canvas-side BC connection enforcement and
// n-mismatch flagging. These tests target `isAllowedBCConnection` (the
// pure validator behind `isValidConnection`) and the higher-level
// store path that materializes BC edges through `setBCMode` and
// `addEdge`. See CanvasPanel.tsx isValidConnection BCPort branch.
import { describe, it, expect, beforeEach } from "vitest";
import useStore from "../../store/useStore";
import { isAllowedBCConnection } from "../../lib/bcMode";
import type { Node } from "@xyflow/react";

function makeNode(id: string, componentId: string, n = 10): Node {
  return {
    id,
    type: "streamNode",
    position: { x: 0, y: 0 },
    data: {
      componentId,
      instanceName: componentId.toLowerCase() + "_1",
      parameters: { n },
    },
  };
}

describe("isAllowedBCConnection (D-21)", () => {
  it("isAllowedBCConnection(WT, Channel) returns true (D-21)", () => {
    expect(isAllowedBCConnection("WallTemperature", "Channel")).toBe(true);
  });

  it("isAllowedBCConnection(WT, ChannelHeatFlux) returns false (D-21)", () => {
    expect(isAllowedBCConnection("WallTemperature", "ChannelHeatFlux")).toBe(false);
  });

  it("isAllowedBCConnection(HFS, ChannelHeatFlux) returns true (D-21)", () => {
    expect(isAllowedBCConnection("HeatFluxSource", "ChannelHeatFlux")).toBe(true);
  });

  it("isAllowedBCConnection(HFS, Channel) returns false (D-21)", () => {
    expect(isAllowedBCConnection("HeatFluxSource", "Channel")).toBe(false);
  });

  it("isAllowedBCConnection(*, ChannelAndContacts) returns false for all sources (D-21 CAC carve-out)", () => {
    expect(isAllowedBCConnection("WallTemperature", "ChannelAndContacts")).toBe(false);
    expect(isAllowedBCConnection("HeatFluxSource", "ChannelAndContacts")).toBe(false);
    expect(isAllowedBCConnection("Channel", "ChannelAndContacts")).toBe(false);
    expect(isAllowedBCConnection("Pump", "ChannelAndContacts")).toBe(false);
  });

  it("isAllowedBCConnection rejects same-kind pairings", () => {
    expect(isAllowedBCConnection("WallTemperature", "WallTemperature")).toBe(false);
    expect(isAllowedBCConnection("HeatFluxSource", "HeatFluxSource")).toBe(false);
  });
});

describe("Store path — BC edge materialization", () => {
  beforeEach(() => {
    useStore.setState({
      nodes: [],
      edges: [],
      bcs: [],
      bcMode: {},
      bcSymmetric: {},
      errorTagsByNodeId: {},
      errorNodeIds: new Set<string>(),
      _undoPast: [],
      _undoFuture: [],
      isDirty: false,
    });
  });

  it("creating a WT→Channel BC edge through the store triggers enrichEdges to assign type=bcEdge", () => {
    useStore.setState({
      nodes: [makeNode("wt1", "WallTemperature", 10), makeNode("ch1", "Channel", 10)],
    });
    useStore.getState().setBCMode("ch1", "T_wall_left", {
      mode: "source",
      sourceNodeId: "wt1",
    });
    const bcEdge = useStore.getState().edges.find((e) => e.type === "bcEdge");
    expect(bcEdge).toBeTruthy();
    expect(bcEdge?.source).toBe("wt1");
    expect(bcEdge?.target).toBe("ch1");
  });

  it("creating an n-mismatched WT→Channel BC edge flags both endpoints in errorTagsByNodeId (D-22)", () => {
    useStore.setState({
      nodes: [makeNode("wt1", "WallTemperature", 10), makeNode("ch1", "Channel", 12)],
    });
    useStore.getState().setBCMode("ch1", "T_wall_left", {
      mode: "source",
      sourceNodeId: "wt1",
    });
    const tags = useStore.getState().errorTagsByNodeId;
    expect(tags["wt1"]).toContain("bc-n-mismatch");
    expect(tags["ch1"]).toContain("bc-n-mismatch");
  });

  it("creating a matched WT→Channel BC edge does NOT add an n-mismatch tag (D-22)", () => {
    useStore.setState({
      nodes: [makeNode("wt1", "WallTemperature", 10), makeNode("ch1", "Channel", 10)],
    });
    useStore.getState().setBCMode("ch1", "T_wall_left", {
      mode: "source",
      sourceNodeId: "wt1",
    });
    const tags = useStore.getState().errorTagsByNodeId;
    expect(tags["wt1"]).toBeUndefined();
    expect(tags["ch1"]).toBeUndefined();
  });

  it("canvas-drag path (addEdge) also runs _checkBCNMismatch — Blocker-2 gate (D-22)", () => {
    // Simulate the user dragging a BCPort connection on the canvas (the
    // entry point that bypasses setBCMode and goes through addEdge).
    useStore.setState({
      nodes: [makeNode("wt2", "WallTemperature", 10), makeNode("ch2", "Channel", 12)],
    });
    useStore.getState().addEdge({
      source: "wt2",
      target: "ch2",
      sourceHandle: "T_wall_out",
      targetHandle: "T_wall_left",
    });
    const tags = useStore.getState().errorTagsByNodeId;
    expect(tags["wt2"]).toContain("bc-n-mismatch");
    expect(tags["ch2"]).toContain("bc-n-mismatch");
  });
});
