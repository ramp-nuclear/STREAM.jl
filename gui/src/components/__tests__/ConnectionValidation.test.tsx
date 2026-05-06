// @vitest-environment happy-dom
import { describe, it, expect, beforeEach } from "vitest";
import useStore from "../../store/useStore";
import { getPortType } from "../CanvasPanel";
import type { Node } from "@xyflow/react";

function makeNode(id: string, componentId: string): Node {
  return {
    id,
    type: "streamNode",
    position: { x: 0, y: 0 },
    data: {
      componentId,
      instanceName: componentId.toLowerCase() + "_1",
      parameters: {},
    },
  };
}

describe("getPortType", () => {
  beforeEach(() => {
    useStore.setState({ nodes: [], edges: [] });
  });

  it("returns FlowPort for a FlowPort handle", () => {
    useStore.setState({ nodes: [makeNode("n1", "Pump")] });
    expect(getPortType("n1", "inlet")).toBe("FlowPort");
  });

  it("returns ThermalPort for a ThermalPort handle", () => {
    useStore.setState({ nodes: [makeNode("n1", "HeatDiffusion")] });
    expect(getPortType("n1", "thermal_left")).toBe("ThermalPort");
  });

  it("returns null for unknown nodeId", () => {
    expect(getPortType("nonexistent", "inlet")).toBeNull();
  });
});

describe("isValidConnection logic", () => {
  beforeEach(() => {
    useStore.setState({ nodes: [], edges: [] });
  });

  it("blocks FlowPort-to-ThermalPort connection", () => {
    useStore.setState({
      nodes: [makeNode("n1", "Pump"), makeNode("n2", "HeatDiffusion")],
    });
    const srcType = getPortType("n1", "outlet");
    const tgtType = getPortType("n2", "thermal_left");
    // Cross-type should be blocked
    expect(srcType).toBe("FlowPort");
    expect(tgtType).toBe("ThermalPort");
    expect(srcType !== tgtType).toBe(true);
  });

  it("allows ThermalPort-to-ThermalPort connection", () => {
    useStore.setState({
      nodes: [
        makeNode("n1", "ChannelAndContacts"),
        makeNode("n2", "HeatDiffusion"),
      ],
    });
    const srcType = getPortType("n1", "thermal_right");
    const tgtType = getPortType("n2", "thermal_left");
    expect(srcType).toBe("ThermalPort");
    expect(tgtType).toBe("ThermalPort");
    expect(srcType === tgtType).toBe(true);
  });

  it("allows FlowPort-to-FlowPort connection", () => {
    useStore.setState({
      nodes: [makeNode("n1", "Pump"), makeNode("n2", "Channel")],
    });
    const srcType = getPortType("n1", "outlet");
    const tgtType = getPortType("n2", "inlet");
    expect(srcType).toBe("FlowPort");
    expect(tgtType).toBe("FlowPort");
    expect(srcType === tgtType).toBe(true);
  });
});

describe("addEdge thermal styling", () => {
  beforeEach(() => {
    useStore.setState({
      nodes: [],
      edges: [],
      _undoPast: [],
      _undoFuture: [],
      errorNodeIds: new Set<string>(),
    });
  });

  it("applies amber dashed style for ThermalPort edges", () => {
    useStore.setState({
      nodes: [
        makeNode("n1", "ChannelAndContacts"),
        makeNode("n2", "HeatDiffusion"),
      ],
    });
    useStore.getState().addEdge({
      source: "n1",
      target: "n2",
      sourceHandle: "thermal_right",
      targetHandle: "thermal_left",
    });
    const edges = useStore.getState().edges;
    expect(edges.length).toBe(1);
    expect(edges[0].style?.stroke).toBe("#f59e0b");
    expect(edges[0].style?.strokeDasharray).toBe("6 3");
  });

  it("does not apply amber style for FlowPort edges", () => {
    useStore.setState({
      nodes: [makeNode("n1", "Pump"), makeNode("n2", "Channel")],
    });
    useStore.getState().addEdge({
      source: "n1",
      target: "n2",
      sourceHandle: "outlet",
      targetHandle: "inlet",
    });
    const edges = useStore.getState().edges;
    expect(edges.length).toBe(1);
    expect(edges[0].style?.stroke).not.toBe("#f59e0b");
  });
});
