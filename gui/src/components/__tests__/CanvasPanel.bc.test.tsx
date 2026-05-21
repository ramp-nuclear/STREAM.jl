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

// Phase 71 D-20: selectNodeErrors deleted; inline the n-mismatch check here.
function readN(nodeId: string): number | undefined {
  const node = useStore.getState().nodes.find((n) => n.id === nodeId);
  const params = (node?.data as { parameters?: Record<string, unknown> } | undefined)?.parameters;
  const n = params?.["n"];
  return typeof n === "number" ? n : undefined;
}

function errorsFor(nodeId: string): string[] {
  const { bcMode } = useStore.getState();
  const myN = readN(nodeId);
  const tags: string[] = [];
  for (const [key, entry] of Object.entries(bcMode)) {
    if (entry.mode !== "source") continue;
    if (key.startsWith(`${nodeId}::`)) {
      const srcN = readN(entry.sourceNodeId);
      if (typeof myN === "number" && typeof srcN === "number" && myN !== srcN) {
        tags.push("bc-n-mismatch");
        break;
      }
    }
    if (entry.sourceNodeId === nodeId) {
      const sepIdx = key.indexOf("::");
      if (sepIdx < 0) continue;
      const consumerId = key.slice(0, sepIdx);
      const consN = readN(consumerId);
      if (typeof myN === "number" && typeof consN === "number" && myN !== consN) {
        tags.push("bc-n-mismatch");
        break;
      }
    }
  }
  return tags;
}

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
    // Phase 63.1 D-15: errorTagsByNodeId removed.
    useStore.setState({
      nodes: [],
      edges: [],
      anchors: {},
      bcMode: {},
      bcSymmetric: {},
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

  it("creating an n-mismatched WT→Channel BC edge surfaces bc-n-mismatch via selectNodeErrors (D-22, D-15)", () => {
    useStore.setState({
      nodes: [makeNode("wt1", "WallTemperature", 10), makeNode("ch1", "Channel", 12)],
    });
    useStore.getState().setBCMode("ch1", "T_wall_left", {
      mode: "source",
      sourceNodeId: "wt1",
    });
    // Phase 63.1 D-15: derived from bcMode + nodes, not from a stored slice.
    expect(errorsFor("wt1")).toContain("bc-n-mismatch");
    expect(errorsFor("ch1")).toContain("bc-n-mismatch");
  });

  it("creating a matched WT→Channel BC edge — selectNodeErrors returns [] for both (D-22, D-15)", () => {
    useStore.setState({
      nodes: [makeNode("wt1", "WallTemperature", 10), makeNode("ch1", "Channel", 10)],
    });
    useStore.getState().setBCMode("ch1", "T_wall_left", {
      mode: "source",
      sourceNodeId: "wt1",
    });
    expect(errorsFor("wt1")).toEqual([]);
    expect(errorsFor("ch1")).toEqual([]);
  });

  it("canvas-drag path (addEdge) — selectNodeErrors contract (D-22, D-15)", () => {
    // Phase 63.1 D-15: the canvas-drag path no longer writes per-event tags
    // (_checkBCNMismatch removed). selectNodeErrors derives ring state from
    // bcMode; Plan 63.1-10 CR-01 landed the addEdge → bcMode mirroring that
    // makes the canvas-drag path equivalent to setBCMode for selector purposes.
    // With ch2.n=12 and wt2.n=10, selectNodeErrors now returns
    // ['bc-n-mismatch'] on both sides — matching the setBCMode path above.
    useStore.setState({
      nodes: [makeNode("wt2", "WallTemperature", 10), makeNode("ch2", "Channel", 12)],
    });
    useStore.getState().addEdge({
      source: "wt2",
      target: "ch2",
      sourceHandle: "T_wall_out",
      targetHandle: "T_wall_left",
    });
    expect(useStore.getState().edges.find((e) => e.type === "bcEdge")).toBeDefined();
    expect(errorsFor("wt2")).toContain("bc-n-mismatch");
    expect(errorsFor("ch2")).toContain("bc-n-mismatch");
  });
});
