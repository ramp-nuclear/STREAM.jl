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
import {
  selectNodeErrors,
  type NodeErrorsInput,
} from "../../lib/selectors/nodeErrors";

// Phase 63.1 D-15: errorTagsByNodeId slice dropped from store; ring/error
// state is now derived by selectNodeErrors. Tests that previously read
// state.errorTagsByNodeId[id] now call selectNodeErrors(state, id) instead.
function errorsFor(nodeId: string): string[] {
  const s = useStore.getState() as unknown as NodeErrorsInput & { anchors?: Record<string, never> };
  // Plan 03 lands the `anchors` slice; until then, fall back to {} so the
  // selector's typed input is satisfied without depending on slice ordering.
  return selectNodeErrors(
    { ...s, anchors: s.anchors ?? {} } as NodeErrorsInput,
    nodeId,
  );
}

// Reset to a clean slate before every test. Mirrors the canonical reset
// pattern in useStore.test.ts plus the Phase 63 BC slices.
beforeEach(() => {
  useStore.setState({
    nodes: [],
    edges: [],
    selectedNodeId: null,
    // Phase 63.1 D-02: legacy boundary-conditions slice removed; reset the
    // new per-node anchors Record instead.
    anchors: {},
    isDirty: false,
    _undoPast: [],
    _undoFuture: [],
    bcMode: {},
    bcSymmetric: {},
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
  it("creates edge AND flags both nodes when source.n !== consumer.n (via selectNodeErrors)", () => {
    const { channelId, wtId } = seedChannelAndWT(12, 10);
    useStore.getState().setBCSymmetric(channelId, "T_wall", false);
    useStore.getState().setBCMode(channelId, "T_wall_left", {
      mode: "source",
      sourceNodeId: wtId,
    });
    const state = useStore.getState();
    // Edge IS created (soft warning, not hard block).
    expect(state.edges.find((e) => e.type === "bcEdge")).toBeDefined();
    // Phase 63.1 D-15: assert via the selector, not a stored slice.
    expect(errorsFor(wtId)).toContain("bc-n-mismatch");
    expect(errorsFor(channelId)).toContain("bc-n-mismatch");
  });

  it("does NOT flag when source.n === consumer.n (via selectNodeErrors)", () => {
    const { channelId, wtId } = seedChannelAndWT(10, 10);
    useStore.getState().setBCSymmetric(channelId, "T_wall", false);
    useStore.getState().setBCMode(channelId, "T_wall_left", {
      mode: "source",
      sourceNodeId: wtId,
    });
    expect(errorsFor(wtId)).toEqual([]);
    expect(errorsFor(channelId)).toEqual([]);
  });

  it("auto-clears bc-n-mismatch when the BC edge is removed (D-23 via selector)", () => {
    const { channelId, wtId } = seedChannelAndWT(12, 10);
    useStore.getState().setBCSymmetric(channelId, "T_wall", false);
    useStore.getState().setBCMode(channelId, "T_wall_left", {
      mode: "source",
      sourceNodeId: wtId,
    });
    expect(errorsFor(wtId)).toContain("bc-n-mismatch");
    const edge = useStore.getState().edges.find((e) => e.type === "bcEdge")!;
    useStore.getState().onEdgesChange([{ type: "remove", id: edge.id }]);
    // Phase 63.1 D-15: removing the edge also reverts the bcMode entry (via
    // _revertBCModeForEdge); selectNodeErrors then re-derives [] for both.
    expect(errorsFor(wtId)).toEqual([]);
    expect(errorsFor(channelId)).toEqual([]);
  });

  it("addEdge → BCPort source-type makes selectNodeErrors flag the canvas-drag path (D-22 via selector)", () => {
    // Seed nodes with mismatched n, then call addEdge DIRECTLY (NOT via
    // setBCMode). The store no longer writes per-event tags (D-15 removed
    // _checkBCNMismatch); the canvas-drag path now relies on Plan 05's
    // addEdge→bcMode mirroring + selectNodeErrors. Until Plan 05 lands, this
    // test documents the contract by asserting on the selector applied to
    // bcMode (which Plan 05 must materialize). For now the canvas-drag path
    // creates an edge but no bcMode entry, so the selector reports no errors —
    // the same as before from the selector's POV.
    const ch = makeChannelNode("ch1", 12);
    const wt = makeWallTemperatureNode("wt1", 10);
    useStore.setState({ nodes: [ch, wt] });
    useStore.getState().addEdge({
      source: "wt1",
      sourceHandle: "T_wall_out",
      target: "ch1",
      targetHandle: "T_wall_left",
    });
    // Edge is materialized (enrichEdges assigns type='bcEdge').
    expect(useStore.getState().edges.find((e) => e.type === "bcEdge")).toBeDefined();
    // Selector contract: with no bcMode entry yet (Plan 05 owns mirroring),
    // selectNodeErrors returns []. Once Plan 05 writes the bcMode entry on
    // canvas-drag, this assertion flips to ['bc-n-mismatch'] for both sides.
    expect(errorsFor("wt1")).toEqual([]);
    expect(errorsFor("ch1")).toEqual([]);
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
  it("undo after setBCMode restores bcMode + edges to pre-mutation state; selectNodeErrors auto-clears", () => {
    const { channelId, wtId } = seedChannelAndWT(12, 10);
    useStore.getState().setBCSymmetric(channelId, "T_wall", false);
    useStore.getState().setBCMode(channelId, "T_wall_left", {
      mode: "source",
      sourceNodeId: wtId,
    });
    // Confirm post-mutation state.
    expect(Object.keys(useStore.getState().bcMode)).toHaveLength(1);
    expect(useStore.getState().edges.filter((e) => e.type === "bcEdge")).toHaveLength(1);
    // Phase 63.1 D-15: selector-derived bc-n-mismatch on both endpoints.
    expect(errorsFor(wtId)).toContain("bc-n-mismatch");
    // Undo and confirm both slices reset.
    useStore.getState().undo();
    const state = useStore.getState();
    expect(state.bcMode).toEqual({});
    expect(state.edges.filter((e) => e.type === "bcEdge")).toHaveLength(0);
    // Selector returns [] after undo because bcMode is empty.
    expect(errorsFor(wtId)).toEqual([]);
    expect(errorsFor(channelId)).toEqual([]);
  });
});
