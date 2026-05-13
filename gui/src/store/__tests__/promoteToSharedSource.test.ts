// @vitest-environment happy-dom
// promoteToSharedSource.test.ts — Phase 63.1 Plan 01 (Wave-0 RED).
//
// Covers the new `promoteToSharedSource(consumerId, externalInputName)` action
// (D-07 / D-08): "Promote to shared source" must
//   (a) spawn a new WallTemperature/HeatFluxSource node sized to the consumer's `n`,
//   (b) position it at (consumer.x - 160, consumer.y - 40) per RESEARCH §A6,
//   (c) write a `source`-mode bcMode entry for the consumer external input,
//   (d) materialize a `type: "bcEdge"` edge from the new node to the consumer.
//
// The action does not exist yet — this stub is RED until Plan 06 lands.
// @ts-nocheck — promoteToSharedSource lands in Wave 2 / Plan 06.

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

function makeChannelNode(id: string, n: number, x = 200, y = 100): Node {
  return {
    id,
    type: "streamNode",
    position: { x, y },
    data: {
      componentId: "Channel",
      instanceName: id,
      parameters: { n },
      constructorMode: "default",
    },
  };
}

describe("promoteToSharedSource (D-07 / D-08)", () => {
  it("spawns a WallTemperature node sized to consumer's n, positions it relatively, writes bcMode, and materializes the BC edge", () => {
    useStore.setState({ nodes: [makeChannelNode("ch1", 4, 200, 100)] });
    useStore.getState().promoteToSharedSource("ch1", "T_wall_left");
    const state = useStore.getState();

    // (a) a new WallTemperature node exists with the consumer's n.
    const newWT = state.nodes.find(
      (n) =>
        (n.data as unknown as { componentId: string }).componentId ===
        "WallTemperature",
    );
    expect(newWT).toBeDefined();
    expect(
      (newWT!.data as unknown as { parameters: { n: number } }).parameters.n,
    ).toBe(4);

    // (b) position is consumer.x - 160, consumer.y - 40 (RESEARCH §A6).
    expect(newWT!.position.x).toBe(200 - 160);
    expect(newWT!.position.y).toBe(100 - 40);

    // (c) bcMode source-mode entry exists for the consumer.
    const entry = state.bcMode[bcModeKey("ch1", "T_wall_left")];
    expect(entry).toBeDefined();
    expect(entry).toMatchObject({ mode: "source", sourceNodeId: newWT!.id });

    // (d) a bcEdge from the new WT to the consumer external input exists.
    const edge = state.edges.find(
      (e) =>
        e.source === newWT!.id &&
        e.target === "ch1" &&
        e.targetHandle === "T_wall_left" &&
        e.type === "bcEdge",
    );
    expect(edge).toBeDefined();
  });
});
