// @vitest-environment happy-dom
// useStore.bc.test.ts — Phase 63-B-03: BC slice coverage.
//
// Covers the contract that 63-C (BCs-tab UI) and 63-D (canvas BC edge) consume:
//   - setBCMode / clearBCMode / setBCSymmetric / cycleBCEdgeTargetSide
//   - source-mode edge creation / replacement
//   - edge-deletion reverts bcMode (D-23 bidirectional sync — store layer)
//   - n-mismatch soft warning (D-22) — BOTH the BCs-tab path AND the
//     canvas-drag (addEdge) path
//   - snapshot / undo integration

import { describe, it, expect, beforeEach } from "vitest";
import type { Node } from "@xyflow/react";
import useStore from "../useStore";

// Reset to a clean slate before every test. Mirrors the canonical reset
// pattern in useStore.test.ts plus the Phase 63 BC slices.
beforeEach(() => {
  useStore.setState({
    nodes: [],
    edges: [],
    selectedNodeId: null,
    bcs: [],
    isDirty: false,
    _undoPast: [],
    _undoFuture: [],
    bcMode: {},
    bcSymmetric: {},
    errorTagsByNodeId: {},
  });
});

// ---------------------------------------------------------------------------
// Fixture builders
// ---------------------------------------------------------------------------

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
    position: { x: 0, y: 0 },
    data: {
      componentId: "WallTemperature",
      instanceName: id,
      parameters: { n, T_wall: 320 },
      constructorMode: "default",
    },
  };
}

function seedChannelAndWT(channelN: number, wtN: number) {
  const ch = makeChannelNode("ch1", channelN);
  const wt = makeWallTemperatureNode("wt1", wtN);
  useStore.setState({ nodes: [ch, wt] });
  return { channelId: "ch1", wtId: "wt1" };
}

// ---------------------------------------------------------------------------
// Group 1 — setBCMode core behavior
// ---------------------------------------------------------------------------

describe("bcMode slice — setBCMode", () => {
  it("creates a value-mode entry under the composite key (D-23)", () => {
    const { channelId } = seedChannelAndWT(10, 10);
    useStore.getState().setBCMode(channelId, "T_wall_left", { mode: "value", value: 320 });
    const state = useStore.getState();
    const entry = state.bcMode[`${channelId}::T_wall_left`];
    expect(entry).toBeDefined();
    expect(entry).toEqual({ mode: "value", value: 320 });
  });

  it("sets isDirty to true (D-23)", () => {
    const { channelId } = seedChannelAndWT(10, 10);
    expect(useStore.getState().isDirty).toBe(false);
    useStore.getState().setBCMode(channelId, "T_wall_left", { mode: "value", value: 320 });
    expect(useStore.getState().isDirty).toBe(true);
  });

  it("pushes a snapshot (undo restores prior state)", () => {
    const { channelId } = seedChannelAndWT(10, 10);
    useStore.getState().setBCMode(channelId, "T_wall_left", { mode: "value", value: 320 });
    expect(Object.keys(useStore.getState().bcMode).length).toBeGreaterThan(0);
    useStore.getState().undo();
    expect(useStore.getState().bcMode).toEqual({});
  });

  it("with symmetric ON (default), mirrors entry to sibling field (D-05)", () => {
    const { channelId } = seedChannelAndWT(10, 10);
    // symmetric defaults to ON (consumer reads `bcSymmetric[key] ?? true`)
    useStore.getState().setBCMode(channelId, "T_wall_left", { mode: "value", value: 320 });
    const state = useStore.getState();
    expect(state.bcMode[`${channelId}::T_wall_left`]).toEqual({ mode: "value", value: 320 });
    expect(state.bcMode[`${channelId}::T_wall_right`]).toEqual({ mode: "value", value: 320 });
  });

  it("with symmetric OFF, leaves sibling untouched (D-05)", () => {
    const { channelId } = seedChannelAndWT(10, 10);
    useStore.getState().setBCSymmetric(channelId, "T_wall", false);
    useStore.getState().setBCMode(channelId, "T_wall_left", { mode: "value", value: 320 });
    const state = useStore.getState();
    expect(state.bcMode[`${channelId}::T_wall_left`]).toEqual({ mode: "value", value: 320 });
    expect(state.bcMode[`${channelId}::T_wall_right`]).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// Group 2 — source-mode edge creation (D-23 bidirectional sync)
// ---------------------------------------------------------------------------

describe("bcMode slice — source-mode edge creation (D-23 bidirectional sync)", () => {
  it("creates an edge with type='bcEdge' when mode='source'", () => {
    const { channelId, wtId } = seedChannelAndWT(10, 10);
    // Symmetric OFF so we get exactly one edge for the asserted side.
    useStore.getState().setBCSymmetric(channelId, "T_wall", false);
    useStore.getState().setBCMode(channelId, "T_wall_left", {
      mode: "source",
      sourceNodeId: wtId,
    });
    const edges = useStore.getState().edges;
    const bcEdge = edges.find((e) => e.type === "bcEdge");
    expect(bcEdge).toBeDefined();
    expect(bcEdge?.source).toBe(wtId);
    expect(bcEdge?.sourceHandle).toBe("T_wall_out");
    expect(bcEdge?.target).toBe(channelId);
    expect(bcEdge?.targetHandle).toBe("T_wall_left");
  });

  it("edge data carries componentId, externalInputName, targetSide='both' (D-11 default)", () => {
    const { channelId, wtId } = seedChannelAndWT(10, 10);
    useStore.getState().setBCSymmetric(channelId, "T_wall", false);
    useStore.getState().setBCMode(channelId, "T_wall_left", {
      mode: "source",
      sourceNodeId: wtId,
    });
    const bcEdge = useStore.getState().edges.find((e) => e.type === "bcEdge");
    const data = bcEdge?.data as
      | { componentId: string; externalInputName: string; targetSide: string }
      | undefined;
    expect(data?.componentId).toBe(channelId);
    expect(data?.externalInputName).toBe("T_wall_left");
    expect(data?.targetSide).toBe("both");
  });

  it("removing the BC edge via onEdgesChange reverts bcMode to undefined (D-23)", () => {
    const { channelId, wtId } = seedChannelAndWT(10, 10);
    useStore.getState().setBCSymmetric(channelId, "T_wall", false);
    useStore.getState().setBCMode(channelId, "T_wall_left", {
      mode: "source",
      sourceNodeId: wtId,
    });
    const edge = useStore.getState().edges.find((e) => e.type === "bcEdge");
    expect(edge).toBeDefined();
    // Simulate a ReactFlow `remove` change.
    useStore.getState().onEdgesChange([{ type: "remove", id: edge!.id }]);
    const state = useStore.getState();
    expect(state.bcMode[`${channelId}::T_wall_left`]).toBeUndefined();
    expect(state.edges.find((e) => e.id === edge!.id)).toBeUndefined();
  });

  it("changing from source-A to source-B replaces the edge, not duplicates it", () => {
    const ch = makeChannelNode("ch1", 10);
    const wtA = makeWallTemperatureNode("wtA", 10);
    const wtB = makeWallTemperatureNode("wtB", 10);
    useStore.setState({ nodes: [ch, wtA, wtB] });
    useStore.getState().setBCSymmetric("ch1", "T_wall", false);
    useStore.getState().setBCMode("ch1", "T_wall_left", {
      mode: "source",
      sourceNodeId: "wtA",
    });
    expect(useStore.getState().edges.filter((e) => e.type === "bcEdge")).toHaveLength(1);
    useStore.getState().setBCMode("ch1", "T_wall_left", {
      mode: "source",
      sourceNodeId: "wtB",
    });
    const bcEdges = useStore.getState().edges.filter((e) => e.type === "bcEdge");
    expect(bcEdges).toHaveLength(1);
    expect(bcEdges[0].source).toBe("wtB");
  });
});

// ---------------------------------------------------------------------------
// Group 3 — n-mismatch soft warning (D-22)
// ---------------------------------------------------------------------------

describe("bcMode slice — n-mismatch soft warning (D-22)", () => {
  it("creates edge AND flags both nodes when source.n !== consumer.n", () => {
    const { channelId, wtId } = seedChannelAndWT(12, 10);
    useStore.getState().setBCSymmetric(channelId, "T_wall", false);
    useStore.getState().setBCMode(channelId, "T_wall_left", {
      mode: "source",
      sourceNodeId: wtId,
    });
    const state = useStore.getState();
    // Edge IS created (soft warning, not hard block).
    expect(state.edges.find((e) => e.type === "bcEdge")).toBeDefined();
    expect(state.errorTagsByNodeId[wtId]).toContain("bc-n-mismatch");
    expect(state.errorTagsByNodeId[channelId]).toContain("bc-n-mismatch");
  });

  it("does NOT flag when source.n === consumer.n", () => {
    const { channelId, wtId } = seedChannelAndWT(10, 10);
    useStore.getState().setBCSymmetric(channelId, "T_wall", false);
    useStore.getState().setBCMode(channelId, "T_wall_left", {
      mode: "source",
      sourceNodeId: wtId,
    });
    const tags = useStore.getState().errorTagsByNodeId;
    expect(tags[wtId]).toBeUndefined();
    expect(tags[channelId]).toBeUndefined();
  });

  it("clears bc-n-mismatch tag when the BC edge is removed", () => {
    const { channelId, wtId } = seedChannelAndWT(12, 10);
    useStore.getState().setBCSymmetric(channelId, "T_wall", false);
    useStore.getState().setBCMode(channelId, "T_wall_left", {
      mode: "source",
      sourceNodeId: wtId,
    });
    expect(useStore.getState().errorTagsByNodeId[wtId]).toContain("bc-n-mismatch");
    const edge = useStore.getState().edges.find((e) => e.type === "bcEdge")!;
    useStore.getState().onEdgesChange([{ type: "remove", id: edge.id }]);
    const tags = useStore.getState().errorTagsByNodeId;
    expect(tags[wtId]).toBeUndefined();
    expect(tags[channelId]).toBeUndefined();
  });

  it("addEdge → BCPort source-type triggers n-mismatch check on canvas-drag path (D-22)", () => {
    // Seed nodes with mismatched n, then call addEdge DIRECTLY (NOT via
    // setBCMode) to simulate the canvas-drag path that 63-D will exercise.
    const ch = makeChannelNode("ch1", 12);
    const wt = makeWallTemperatureNode("wt1", 10);
    useStore.setState({ nodes: [ch, wt] });
    useStore.getState().addEdge({
      source: "wt1",
      sourceHandle: "T_wall_out",
      target: "ch1",
      targetHandle: "T_wall_left",
    });
    const tags = useStore.getState().errorTagsByNodeId;
    expect(tags["wt1"]).toContain("bc-n-mismatch");
    expect(tags["ch1"]).toContain("bc-n-mismatch");
  });
});

// ---------------------------------------------------------------------------
// Group 4 — clearBCMode (D-09 required-unset)
// ---------------------------------------------------------------------------

describe("bcMode slice — clearBCMode (D-09 required-unset)", () => {
  it("removes the key entirely; lookup returns undefined", () => {
    const { channelId } = seedChannelAndWT(10, 10);
    useStore.getState().setBCSymmetric(channelId, "T_wall", false);
    useStore.getState().setBCMode(channelId, "T_wall_left", { mode: "value", value: 320 });
    expect(useStore.getState().bcMode[`${channelId}::T_wall_left`]).toBeDefined();
    useStore.getState().clearBCMode(channelId, "T_wall_left");
    expect(useStore.getState().bcMode[`${channelId}::T_wall_left`]).toBeUndefined();
  });

  it("removes the BC edge if it was source-mode", () => {
    const { channelId, wtId } = seedChannelAndWT(10, 10);
    useStore.getState().setBCSymmetric(channelId, "T_wall", false);
    useStore.getState().setBCMode(channelId, "T_wall_left", {
      mode: "source",
      sourceNodeId: wtId,
    });
    expect(useStore.getState().edges.filter((e) => e.type === "bcEdge")).toHaveLength(1);
    useStore.getState().clearBCMode(channelId, "T_wall_left");
    expect(useStore.getState().edges.filter((e) => e.type === "bcEdge")).toHaveLength(0);
  });

  it("with symmetric ON, also clears the sibling", () => {
    const { channelId } = seedChannelAndWT(10, 10);
    // symmetric defaults ON; set both via the symmetric mirror.
    useStore.getState().setBCMode(channelId, "T_wall_left", { mode: "value", value: 320 });
    expect(useStore.getState().bcMode[`${channelId}::T_wall_left`]).toBeDefined();
    expect(useStore.getState().bcMode[`${channelId}::T_wall_right`]).toBeDefined();
    useStore.getState().clearBCMode(channelId, "T_wall_left");
    expect(useStore.getState().bcMode[`${channelId}::T_wall_left`]).toBeUndefined();
    expect(useStore.getState().bcMode[`${channelId}::T_wall_right`]).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// Group 5 — bcSymmetric slice (CD-05)
// ---------------------------------------------------------------------------

describe("bcSymmetric slice (CD-05)", () => {
  it("setBCSymmetric(true) when left/right differ copies left to right (left wins)", () => {
    const { channelId } = seedChannelAndWT(10, 10);
    // Turn OFF first, set asymmetric entries.
    useStore.getState().setBCSymmetric(channelId, "T_wall", false);
    useStore.getState().setBCMode(channelId, "T_wall_left", { mode: "value", value: 320 });
    useStore.getState().setBCMode(channelId, "T_wall_right", { mode: "value", value: 999 });
    // Now turn ON — left should win.
    useStore.getState().setBCSymmetric(channelId, "T_wall", true);
    const state = useStore.getState();
    expect(state.bcMode[`${channelId}::T_wall_left`]).toEqual({ mode: "value", value: 320 });
    expect(state.bcMode[`${channelId}::T_wall_right`]).toEqual({ mode: "value", value: 320 });
  });

  it("setBCSymmetric(false) leaves existing entries untouched", () => {
    const { channelId } = seedChannelAndWT(10, 10);
    useStore.getState().setBCSymmetric(channelId, "T_wall", false);
    useStore.getState().setBCMode(channelId, "T_wall_left", { mode: "value", value: 320 });
    useStore.getState().setBCMode(channelId, "T_wall_right", { mode: "value", value: 999 });
    useStore.getState().setBCSymmetric(channelId, "T_wall", false); // no-op-style call
    const state = useStore.getState();
    expect(state.bcMode[`${channelId}::T_wall_left`]).toEqual({ mode: "value", value: 320 });
    expect(state.bcMode[`${channelId}::T_wall_right`]).toEqual({ mode: "value", value: 999 });
  });
});

// ---------------------------------------------------------------------------
// Group 6 — cycleBCEdgeTargetSide (D-11)
// ---------------------------------------------------------------------------

describe("cycleBCEdgeTargetSide (D-11)", () => {
  it("walks both → left → right → both on successive calls", () => {
    const { channelId, wtId } = seedChannelAndWT(10, 10);
    useStore.getState().setBCSymmetric(channelId, "T_wall", false);
    useStore.getState().setBCMode(channelId, "T_wall_left", {
      mode: "source",
      sourceNodeId: wtId,
    });
    const edgeId = useStore.getState().edges.find((e) => e.type === "bcEdge")!.id;
    const readSide = () => {
      const e = useStore.getState().edges.find((ed) => ed.id === edgeId)!;
      return (e.data as { targetSide: string }).targetSide;
    };
    expect(readSide()).toBe("both");
    useStore.getState().cycleBCEdgeTargetSide(edgeId);
    expect(readSide()).toBe("left");
    useStore.getState().cycleBCEdgeTargetSide(edgeId);
    expect(readSide()).toBe("right");
    useStore.getState().cycleBCEdgeTargetSide(edgeId);
    expect(readSide()).toBe("both");
  });
});

// ---------------------------------------------------------------------------
// Group 7 — snapshot integration (undo restores all three slices + edges)
// ---------------------------------------------------------------------------

describe("bcMode slice — snapshot / undo integration", () => {
  it("undo after setBCMode restores bcMode, edges, errorTagsByNodeId to pre-mutation state", () => {
    const { channelId, wtId } = seedChannelAndWT(12, 10);
    useStore.getState().setBCSymmetric(channelId, "T_wall", false);
    useStore.getState().setBCMode(channelId, "T_wall_left", {
      mode: "source",
      sourceNodeId: wtId,
    });
    // Confirm post-mutation state.
    expect(Object.keys(useStore.getState().bcMode)).toHaveLength(1);
    expect(useStore.getState().edges.filter((e) => e.type === "bcEdge")).toHaveLength(1);
    expect(useStore.getState().errorTagsByNodeId[wtId]).toContain("bc-n-mismatch");
    // Undo and confirm all three slices reset.
    useStore.getState().undo();
    const state = useStore.getState();
    expect(state.bcMode).toEqual({});
    expect(state.edges.filter((e) => e.type === "bcEdge")).toHaveLength(0);
    expect(state.errorTagsByNodeId[wtId]).toBeUndefined();
    expect(state.errorTagsByNodeId[channelId]).toBeUndefined();
  });
});
