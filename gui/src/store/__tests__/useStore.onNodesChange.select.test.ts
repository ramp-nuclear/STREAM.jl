// @vitest-environment happy-dom
// useStore.onNodesChange.select.test.ts — Phase 63.1 Plan 01 (Wave-0 RED).
//
// Covers D-22 click-vs-drag selection sync:
//   - When React Flow dispatches a NodeChange of type "select" with
//     selected:true (drag-select, click-select), `selectedNodeId` must
//     update in the store.
//
// Today, `onNodesChange` short-circuits on contentless "select" events and
// only mutates `state.nodes`. The selectedNodeId is not synced. The fix
// (Plan 05 / Wave 1) lands a side-effect that writes selectedNodeId.
// @ts-nocheck — sync action lands in Wave 1 / Plan 05.

import { describe, it, expect, beforeEach } from "vitest";
import type { Node, NodeChange } from "@xyflow/react";
import useStore from "../useStore";

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

function makeChannelNode(id: string): Node {
  return {
    id,
    type: "streamNode",
    position: { x: 0, y: 0 },
    data: {
      componentId: "Channel",
      instanceName: id,
      parameters: { n: 4 },
      constructorMode: "default",
    },
  };
}

describe("onNodesChange select sync (D-22)", () => {
  it("drag-select NodeChange.select with selected:true updates selectedNodeId", () => {
    useStore.setState({ nodes: [makeChannelNode("n1"), makeChannelNode("n2")] });
    const changes: NodeChange[] = [{ type: "select", id: "n2", selected: true }];
    useStore.getState().onNodesChange(changes);
    expect(useStore.getState().selectedNodeId).toBe("n2");
  });

  it("NodeChange.select with selected:false clears selectedNodeId for that node", () => {
    useStore.setState({
      nodes: [makeChannelNode("n1")],
      selectedNodeId: "n1",
    });
    const changes: NodeChange[] = [{ type: "select", id: "n1", selected: false }];
    useStore.getState().onNodesChange(changes);
    expect(useStore.getState().selectedNodeId).toBeNull();
  });
});
