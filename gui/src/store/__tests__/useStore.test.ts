import { describe, it, expect, beforeEach } from "vitest";
import useStore from "../useStore";
import type { StreamNodeData } from "../useStore";

// Reset store and undo history before each test
beforeEach(() => {
  useStore.setState({ nodes: [], edges: [], selectedNodeId: null, bcs: [], isDirty: false, _undoPast: [], _undoFuture: [] });
});

describe("addNode", () => {
  it("creates a node with type streamNode", () => {
    useStore.getState().addNode("Pump", { x: 100, y: 200 });
    const { nodes } = useStore.getState();
    expect(nodes).toHaveLength(1);
    expect(nodes[0].type).toBe("streamNode");
  });

  it("sets componentId in node data", () => {
    useStore.getState().addNode("Pump", { x: 100, y: 200 });
    const node = useStore.getState().nodes[0];
    expect(node.data.componentId).toBe("Pump");
  });

  it("generates instanceName matching lowercase pattern", () => {
    useStore.getState().addNode("Pump", { x: 100, y: 200 });
    const node = useStore.getState().nodes[0];
    expect(node.data.instanceName).toMatch(/^pump_\d+$/);
  });

  it("increments instance names for same component type", () => {
    useStore.getState().addNode("Pump", { x: 100, y: 200 });
    useStore.getState().addNode("Pump", { x: 200, y: 200 });
    const { nodes } = useStore.getState();
    const names = nodes.map((n) => n.data.instanceName);
    expect(names[0]).not.toBe(names[1]);
    // Both should match pump_N pattern
    for (const name of names) {
      expect(name).toMatch(/^pump_\d+$/);
    }
  });

  it("uses per-type counters (channel_1 independent of pump count)", () => {
    useStore.getState().addNode("Pump", { x: 100, y: 200 });
    useStore.getState().addNode("Channel", { x: 200, y: 200 });
    const { nodes } = useStore.getState();
    expect(nodes[1].data.instanceName).toMatch(/^channel_\d+$/);
  });

  it("sets correct position", () => {
    useStore.getState().addNode("Pump", { x: 42, y: 99 });
    const node = useStore.getState().nodes[0];
    expect(node.position).toEqual({ x: 42, y: 99 });
  });
});

describe("removeNode", () => {
  it("removes the node and its connected edges", () => {
    useStore.getState().addNode("Pump", { x: 0, y: 0 });
    useStore.getState().addNode("Channel", { x: 100, y: 0 });
    const { nodes } = useStore.getState();
    const pumpId = nodes[0].id;
    const channelId = nodes[1].id;

    // Add an edge connecting them
    useStore.getState().addEdge({
      source: pumpId,
      target: channelId,
      sourceHandle: "port_out",
      targetHandle: "port_in",
    });
    expect(useStore.getState().edges).toHaveLength(1);

    // Remove pump node
    useStore.getState().removeNode(pumpId);
    expect(useStore.getState().nodes).toHaveLength(1);
    expect(useStore.getState().edges).toHaveLength(0);
  });

  it("sets selectedNodeId to null", () => {
    useStore.getState().addNode("Pump", { x: 0, y: 0 });
    const nodeId = useStore.getState().nodes[0].id;
    useStore.getState().selectNode(nodeId);
    expect(useStore.getState().selectedNodeId).toBe(nodeId);

    useStore.getState().removeNode(nodeId);
    expect(useStore.getState().selectedNodeId).toBeNull();
  });
});

describe("addEdge / removeEdge", () => {
  it("addEdge adds an edge from connection", () => {
    useStore.getState().addEdge({
      source: "a",
      target: "b",
      sourceHandle: "port_out",
      targetHandle: "port_in",
    });
    expect(useStore.getState().edges).toHaveLength(1);
  });

  it("removeEdge removes the specified edge", () => {
    useStore.getState().addEdge({
      source: "a",
      target: "b",
      sourceHandle: "port_out",
      targetHandle: "port_in",
    });
    const edgeId = useStore.getState().edges[0].id;
    useStore.getState().removeEdge(edgeId);
    expect(useStore.getState().edges).toHaveLength(0);
  });
});

describe("undo/redo", () => {
  it("undo reverses addNode", () => {
    useStore.getState().addNode("Pump", { x: 0, y: 0 });
    expect(useStore.getState().nodes).toHaveLength(1);

    useStore.getState().undo();
    expect(useStore.getState().nodes).toHaveLength(0);
  });

  it("redo re-applies addNode", () => {
    useStore.getState().addNode("Pump", { x: 0, y: 0 });
    useStore.getState().undo();
    expect(useStore.getState().nodes).toHaveLength(0);

    useStore.getState().redo();
    expect(useStore.getState().nodes).toHaveLength(1);
  });

  it("supports 10+ sequential undo operations (CANV-07)", () => {
    // Perform 10 addNode operations
    for (let i = 0; i < 10; i++) {
      useStore.getState().addNode("Pump", { x: i * 10, y: 0 });
    }
    expect(useStore.getState().nodes).toHaveLength(10);

    // Undo all 10
    for (let i = 0; i < 10; i++) {
      useStore.getState().undo();
    }
    expect(useStore.getState().nodes).toHaveLength(0);

    // Redo all 10
    for (let i = 0; i < 10; i++) {
      useStore.getState().redo();
    }
    expect(useStore.getState().nodes).toHaveLength(10);
  });
});

describe("updateNodeParams", () => {
  it("updates parameters for a node", () => {
    useStore.getState().addNode("Channel", { x: 0, y: 0 });
    const nodeId = useStore.getState().nodes[0].id;
    useStore.getState().updateNodeParams(nodeId, { parameters: { n: 10 } });
    const data = useStore.getState().nodes[0].data as unknown as StreamNodeData;
    expect(data.parameters.n).toBe(10);
  });

  it("merges parameters without overwriting others", () => {
    useStore.getState().addNode("Channel", { x: 0, y: 0 });
    const nodeId = useStore.getState().nodes[0].id;
    useStore.getState().updateNodeParams(nodeId, { parameters: { n: 10 } });
    useStore.getState().updateNodeParams(nodeId, { parameters: { g: 9.81 } });
    const data = useStore.getState().nodes[0].data as unknown as StreamNodeData;
    expect(data.parameters.n).toBe(10);
    expect(data.parameters.g).toBe(9.81);
  });

  it("updates instanceName", () => {
    useStore.getState().addNode("Pump", { x: 0, y: 0 });
    const nodeId = useStore.getState().nodes[0].id;
    useStore.getState().updateNodeParams(nodeId, { instanceName: "my_pump" });
    const data = useStore.getState().nodes[0].data as unknown as StreamNodeData;
    expect(data.instanceName).toBe("my_pump");
  });

  it("updates constructorMode", () => {
    useStore.getState().addNode("Pump", { x: 0, y: 0 });
    const nodeId = useStore.getState().nodes[0].id;
    useStore.getState().updateNodeParams(nodeId, { constructorMode: "fixed-mdot" });
    const data = useStore.getState().nodes[0].data as unknown as StreamNodeData;
    expect(data.constructorMode).toBe("fixed-mdot");
  });

  it("is covered by undo/redo", () => {
    useStore.getState().addNode("Channel", { x: 0, y: 0 });
    const nodeId = useStore.getState().nodes[0].id;
    useStore.getState().updateNodeParams(nodeId, { parameters: { n: 10 } });
    useStore.getState().undo();
    const data = useStore.getState().nodes[0].data as unknown as StreamNodeData;
    expect(data.parameters.n).not.toBe(10);
  });
});

describe("addNode default population", () => {
  it("populates default parameter values from registry", () => {
    useStore.getState().addNode("Channel", { x: 0, y: 0 });
    const data = useStore.getState().nodes[0].data as unknown as StreamNodeData;
    // Channel has g default 0.0, htc_correlation default dittus_boelter, friction_correlation default blasius_friction
    expect(data.parameters.g).toBe(0.0);
    expect(data.parameters.htc_correlation).toBe("dittus_boelter");
    expect(data.parameters.friction_correlation).toBe("blasius_friction");
  });

  it("sets constructorMode to first mode", () => {
    useStore.getState().addNode("Pump", { x: 0, y: 0 });
    const data = useStore.getState().nodes[0].data as unknown as StreamNodeData;
    expect(data.constructorMode).toBe("fixed-dP");
  });

  it("does not set defaults for required params with no default", () => {
    useStore.getState().addNode("Channel", { x: 0, y: 0 });
    const data = useStore.getState().nodes[0].data as unknown as StreamNodeData;
    // n is required with no default
    expect(data.parameters.n).toBeUndefined();
  });
});

describe("isDirty tracking", () => {
  it("isDirty starts false", () => {
    expect(useStore.getState().isDirty).toBe(false);
  });

  it("addNode sets isDirty true", () => {
    useStore.getState().addNode("Pump", { x: 0, y: 0 });
    expect(useStore.getState().isDirty).toBe(true);
  });

  it("removeNode sets isDirty true", () => {
    // Force isDirty to false first so we can verify the action sets it
    useStore.setState({ isDirty: false });
    useStore.getState().addNode("Pump", { x: 0, y: 0 });
    const nodeId = useStore.getState().nodes[0].id;
    useStore.setState({ isDirty: false });
    useStore.getState().removeNode(nodeId);
    expect(useStore.getState().isDirty).toBe(true);
  });

  it("addEdge sets isDirty true", () => {
    useStore.setState({ isDirty: false });
    useStore.getState().addEdge({
      source: "a",
      target: "b",
      sourceHandle: "port_out",
      targetHandle: "port_in",
    });
    expect(useStore.getState().isDirty).toBe(true);
  });

  it("removeEdge sets isDirty true", () => {
    useStore.getState().addEdge({
      source: "a",
      target: "b",
      sourceHandle: "port_out",
      targetHandle: "port_in",
    });
    const edgeId = useStore.getState().edges[0].id;
    useStore.setState({ isDirty: false });
    useStore.getState().removeEdge(edgeId);
    expect(useStore.getState().isDirty).toBe(true);
  });

  it("updateNodeParams sets isDirty true", () => {
    useStore.getState().addNode("Channel", { x: 0, y: 0 });
    const nodeId = useStore.getState().nodes[0].id;
    useStore.setState({ isDirty: false });
    useStore.getState().updateNodeParams(nodeId, { parameters: { n: 5 } });
    expect(useStore.getState().isDirty).toBe(true);
  });

  it("addBC sets isDirty true", () => {
    useStore.setState({ isDirty: false });
    useStore.getState().addBC({ nodeId: "n1", portField: "port_in.P", value: 1e5 });
    expect(useStore.getState().isDirty).toBe(true);
  });

  it("removeBC sets isDirty true", () => {
    useStore.getState().addBC({ nodeId: "n1", portField: "port_in.P", value: 1e5 });
    useStore.setState({ isDirty: false });
    useStore.getState().removeBC(0);
    expect(useStore.getState().isDirty).toBe(true);
  });

  it("selectNode does NOT set isDirty true", () => {
    useStore.setState({ isDirty: false });
    useStore.getState().selectNode("some-node-id");
    expect(useStore.getState().isDirty).toBe(false);
  });

  it("toggleBottomPanel does NOT set isDirty true", () => {
    useStore.setState({ isDirty: false });
    useStore.getState().toggleBottomPanel();
    expect(useStore.getState().isDirty).toBe(false);
  });
});
