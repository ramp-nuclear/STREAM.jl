// loopClosure.test.ts — Unit tests for the loopClosure validator (Phase 71, Plan 07)
//
// D-15 rule 7: "loop closure" — when a model has driving elements (Pump or Gravity)
// but no closed hydraulic loop, flag it (fluid cannot circulate).
//
// Test environment: node (pure function, no DOM needed).

import { describe, it, expect } from "vitest";
import type { Node, Edge } from "@xyflow/react";
import type { ValidationSnapshot } from "../../snapshot";
import type { ComponentDefinition } from "../../../../registry/types";

// Import after writing the rule file (GREEN phase)
import { loopClosure } from "../loopClosure";

// ---------------------------------------------------------------------------
// Component definition fixtures
// ---------------------------------------------------------------------------

const PUMP_DEF: ComponentDefinition = {
  id: "Pump",
  label: "Pump",
  category: "Hydraulic",
  description: "Pump",
  ports: [
    { name: "port_in", type: "FlowPort", side: "left" },
    { name: "port_out", type: "FlowPort", side: "right" },
  ],
  parameters: [],
  constructorModes: [],
};

const GRAVITY_DEF: ComponentDefinition = {
  id: "Gravity",
  label: "Gravity",
  category: "Hydraulic",
  description: "Gravity",
  ports: [
    { name: "port_in", type: "FlowPort", side: "left" },
    { name: "port_out", type: "FlowPort", side: "right" },
  ],
  parameters: [{ name: "H", type: "Real", unit: "m", description: "Height", required: true, positional: true }],
  constructorModes: [],
};

const CHANNEL_DEF: ComponentDefinition = {
  id: "Channel",
  label: "Channel",
  category: "Hydraulic",
  description: "Channel",
  ports: [
    { name: "port_in", type: "FlowPort", side: "left" },
    { name: "port_out", type: "FlowPort", side: "right" },
    { name: "T_wall_left", type: "BCPort", side: "bottom" },
  ],
  parameters: [],
  constructorModes: [],
};

const CONSTANT_TEMP_DEF: ComponentDefinition = {
  id: "ConstantTemperature",
  label: "Constant Temperature",
  category: "Thermal",
  description: "ConstantTemperature",
  ports: [{ name: "thermal", type: "ThermalPort", side: "left" }],
  parameters: [],
  constructorModes: [],
};

const DEFS: Record<string, ComponentDefinition> = {
  Pump: PUMP_DEF,
  Gravity: GRAVITY_DEF,
  Channel: CHANNEL_DEF,
  ConstantTemperature: CONSTANT_TEMP_DEF,
};

// ---------------------------------------------------------------------------
// Factory helpers
// ---------------------------------------------------------------------------

function makeNode(id: string, componentId: string, instanceName?: string): Node {
  return {
    id,
    type: "streamNode",
    position: { x: 0, y: 0 },
    data: {
      componentId,
      instanceName: instanceName ?? id,
      parameters: {},
    },
  };
}

function makeEdge(
  source: string,
  sourceHandle: string,
  target: string,
  targetHandle: string,
): Edge {
  return {
    id: `${source}-${sourceHandle}-${target}-${targetHandle}`,
    source,
    sourceHandle,
    target,
    targetHandle,
  };
}

function makeSnapshot(nodes: Node[], edges: Edge[]): ValidationSnapshot {
  return {
    nodes,
    edges,
    anchors: {},
    bcMode: {},
    resources: { geometries: {}, powerShapes: {}, fluids: {} },
    getComponentDef: (id: string) => DEFS[id],
  };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("loopClosure validator", () => {
  it("emits no result when Pump and Channel form a closed loop", () => {
    // Pump → Channel → Pump (closed)
    const pump = makeNode("pump1", "Pump");
    const ch = makeNode("ch1", "Channel");
    const snapshot = makeSnapshot([pump, ch], [
      makeEdge("pump1", "port_out", "ch1", "port_in"),
      makeEdge("ch1", "port_out", "pump1", "port_in"),
    ]);
    const results = loopClosure.run(snapshot);
    expect(results).toHaveLength(0);
  });

  it("emits 1 error when Pump exists but no closed loop (open chain)", () => {
    // Pump → Channel (no return edge)
    const pump = makeNode("pump1", "Pump");
    const ch = makeNode("ch1", "Channel");
    const snapshot = makeSnapshot([pump, ch], [
      makeEdge("pump1", "port_out", "ch1", "port_in"),
    ]);
    const results = loopClosure.run(snapshot);
    expect(results).toHaveLength(1);
    expect(results[0].severity).toBe("error");
    expect(results[0].validatorId).toBe("loop_closure");
    expect(results[0].id).toBe("loop_closure::system");
    // Should mention the count of driving elements
    expect(results[0].description).toContain("1");
    // Targets must include the pump node
    const nodeTargets = results[0].targets.filter((t) => t.kind === "node");
    expect(nodeTargets.some((t) => t.kind === "node" && t.nodeId === "pump1")).toBe(true);
  });

  it("emits no result when there is no driving element (thermal-only model)", () => {
    // Only ConstantTemperature — no Pump or Gravity
    const ct = makeNode("ct1", "ConstantTemperature");
    const snapshot = makeSnapshot([ct], []);
    const results = loopClosure.run(snapshot);
    expect(results).toHaveLength(0);
  });

  it("emits 1 error when Gravity exists but no closed loop", () => {
    // Gravity without a return path
    const gravity = makeNode("g1", "Gravity");
    const ch = makeNode("ch1", "Channel");
    const snapshot = makeSnapshot([gravity, ch], [
      makeEdge("g1", "port_out", "ch1", "port_in"),
    ]);
    const results = loopClosure.run(snapshot);
    expect(results).toHaveLength(1);
    expect(results[0].severity).toBe("error");
    expect(results[0].validatorId).toBe("loop_closure");
    // Gravity is a driving element
    const nodeTargets = results[0].targets.filter((t) => t.kind === "node");
    expect(nodeTargets.some((t) => t.kind === "node" && t.nodeId === "g1")).toBe(true);
  });

  it("emits no result when two disjoint loops are both closed", () => {
    // Loop A: pumpA ↔ chA
    // Loop B: pumpB ↔ chB
    const pumpA = makeNode("pumpA", "Pump");
    const chA = makeNode("chA", "Channel");
    const pumpB = makeNode("pumpB", "Pump");
    const chB = makeNode("chB", "Channel");
    const snapshot = makeSnapshot([pumpA, chA, pumpB, chB], [
      makeEdge("pumpA", "port_out", "chA", "port_in"),
      makeEdge("chA", "port_out", "pumpA", "port_in"),
      makeEdge("pumpB", "port_out", "chB", "port_in"),
      makeEdge("chB", "port_out", "pumpB", "port_in"),
    ]);
    const results = loopClosure.run(snapshot);
    expect(results).toHaveLength(0);
  });
});
