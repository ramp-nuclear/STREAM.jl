// @vitest-environment happy-dom
// useStore.anchors.test.ts — Phase 63.1 Plan 01 (Wave-0 RED scaffolding).
//
// Covers the new anchors slice contract (D-02):
//   - setAnchor writes a Record entry keyed by nodeId.
//   - clearAnchor deletes the entry.
//   - setAnchor overwrites on same nodeId (at-most-one semantics).
//   - setAnchor pushes a snapshot for undo (PATTERNS Pitfall 4).
//
// All assertions target the post-implementation state of the anchors slice
// that lands in a later wave (Plan 03). These tests are RED until then.
// @ts-nocheck — anchors slice + AnchorEntry land in Wave 2 / Plan 03.

import { describe, it, expect, beforeEach } from "vitest";
import type { Node } from "@xyflow/react";
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

function makePumpNode(id: string): Node {
  return {
    id,
    type: "streamNode",
    position: { x: 0, y: 0 },
    data: {
      componentId: "Pump",
      instanceName: id,
      parameters: {},
      constructorMode: "default",
    },
  };
}

describe("anchors slice (D-02)", () => {
  it("setAnchor writes a Record entry keyed by nodeId", () => {
    useStore.setState({ nodes: [makePumpNode("n1")] });
    useStore.getState().setAnchor("n1", { portField: "port_in.P", value: 1e5 });
    const state = useStore.getState();
    expect(state.anchors["n1"]).toEqual({ portField: "port_in.P", value: 1e5 });
  });

  it("clearAnchor deletes the entry", () => {
    useStore.setState({ nodes: [makePumpNode("n1")] });
    useStore.getState().setAnchor("n1", { portField: "port_in.P", value: 1e5 });
    useStore.getState().clearAnchor("n1");
    const state = useStore.getState();
    expect(Object.keys(state.anchors).length).toBe(0);
  });

  it("setAnchor overwrites a prior entry on the same nodeId (at-most-one)", () => {
    useStore.setState({ nodes: [makePumpNode("n1")] });
    useStore.getState().setAnchor("n1", { portField: "port_in.P", value: 1e5 });
    useStore.getState().setAnchor("n1", { portField: "port_out.P", value: 2e5 });
    const state = useStore.getState();
    expect(Object.keys(state.anchors).length).toBe(1);
    expect(state.anchors["n1"]).toEqual({ portField: "port_out.P", value: 2e5 });
  });

  it("setAnchor pushes an undo snapshot (Pitfall 4)", () => {
    useStore.setState({ nodes: [makePumpNode("n1")] });
    expect(useStore.getState()._undoPast.length).toBe(0);
    useStore.getState().setAnchor("n1", { portField: "port_in.P", value: 1e5 });
    expect(useStore.getState()._undoPast.length).toBe(1);
  });
});
