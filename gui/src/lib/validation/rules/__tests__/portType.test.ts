// portType.test.ts — Unit tests for the portType validator (Phase 71, Plan 04)
//
// Environment: node (vitest.config.ts default — no JSDOM needed for pure functions).
// Covers D-15 rule 5: port-type mismatch + BCPort allow-list (D-19 single source of truth).
//
// Test cases:
//   1. FlowPort → ThermalPort edge → 1 error result
//   2. FlowPort → FlowPort edge → no result
//   3. ThermalPort → ThermalPort edge → no result
//   4. BCPort (WallTemperature → Channel.T_wall_left) → no result (allowed)
//   5. BCPort (WallTemperature → HeatDiffusion) → 1 error (not allowed)
//   6. Missing source/target node → no result (defensive)
//   7. Mixed BCPort with FlowPort → 1 error
//   8. BCPort (HeatFluxSource → ChannelHeatFlux.q_left) → no result (allowed)

import { describe, it, expect } from "vitest";
import type { Node, Edge } from "@xyflow/react";
import type { ValidationSnapshot } from "../../snapshot";
import type { ComponentDefinition } from "../../../../registry/types";

// Import after writing the rule file (GREEN phase)
import { portType } from "../portType";

// ---------------------------------------------------------------------------
// Minimal node factory
// ---------------------------------------------------------------------------

function makeNode(
  id: string,
  componentId: string,
  instanceName: string,
): Node {
  return {
    id,
    type: "streamNode",
    position: { x: 0, y: 0 },
    data: {
      componentId,
      instanceName,
      parameters: {},
    },
  };
}

// ---------------------------------------------------------------------------
// Minimal edge factory
// ---------------------------------------------------------------------------

function makeEdge(
  id: string,
  source: string,
  sourceHandle: string,
  target: string,
  targetHandle: string,
): Edge {
  return {
    id,
    source,
    sourceHandle,
    target,
    targetHandle,
  };
}

// ---------------------------------------------------------------------------
// Component definition fixtures (matching components.json ports)
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

const CHANNEL_HEAT_FLUX_DEF: ComponentDefinition = {
  id: "ChannelHeatFlux",
  label: "ChannelHeatFlux",
  category: "Hydraulic",
  description: "ChannelHeatFlux",
  ports: [
    { name: "port_in", type: "FlowPort", side: "left" },
    { name: "port_out", type: "FlowPort", side: "right" },
    { name: "q_left", type: "BCPort", side: "bottom" },
  ],
  parameters: [],
  constructorModes: [],
};

const WALL_TEMP_DEF: ComponentDefinition = {
  id: "WallTemperature",
  label: "WallTemperature",
  category: "Sources",
  description: "WallTemperature",
  ports: [{ name: "T_wall_out", type: "BCPort", side: "right" }],
  parameters: [],
  constructorModes: [],
};

const HEAT_FLUX_SOURCE_DEF: ComponentDefinition = {
  id: "HeatFluxSource",
  label: "HeatFluxSource",
  category: "Sources",
  description: "HeatFluxSource",
  ports: [{ name: "q_out", type: "BCPort", side: "right" }],
  parameters: [],
  constructorModes: [],
};

const HEAT_DIFFUSION_DEF: ComponentDefinition = {
  id: "HeatDiffusion",
  label: "HeatDiffusion",
  category: "Thermal",
  description: "HeatDiffusion",
  ports: [
    { name: "thermal_left", type: "ThermalPort" },
    { name: "thermal_right", type: "ThermalPort" },
  ],
  parameters: [],
  constructorModes: [],
};

const CONSTANT_TEMP_DEF: ComponentDefinition = {
  id: "ConstantTemperature",
  label: "ConstantTemperature",
  category: "Thermal",
  description: "ConstantTemperature",
  ports: [{ name: "thermal", type: "ThermalPort", side: "right" }],
  parameters: [],
  constructorModes: [],
};

const DEFS: Record<string, ComponentDefinition> = {
  Pump: PUMP_DEF,
  Channel: CHANNEL_DEF,
  ChannelHeatFlux: CHANNEL_HEAT_FLUX_DEF,
  WallTemperature: WALL_TEMP_DEF,
  HeatFluxSource: HEAT_FLUX_SOURCE_DEF,
  HeatDiffusion: HEAT_DIFFUSION_DEF,
  ConstantTemperature: CONSTANT_TEMP_DEF,
};

// ---------------------------------------------------------------------------
// Snapshot factory
// ---------------------------------------------------------------------------

function makeSnapshot(
  nodes: Node[],
  edges: Edge[],
): ValidationSnapshot {
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

describe("portType validator", () => {
  it("emits error for FlowPort → ThermalPort mismatch", () => {
    const pump = makeNode("pump1", "Pump", "pump1");
    const hd = makeNode("hd1", "HeatDiffusion", "hd1");
    const edge = makeEdge("e1", "pump1", "port_out", "hd1", "thermal_left");

    const snapshot = makeSnapshot([pump, hd], [edge]);
    const results = portType.run(snapshot);

    expect(results).toHaveLength(1);
    expect(results[0].severity).toBe("error");
    expect(results[0].validatorId).toBe("port_type");
    // D-14: targets must include edge + both port endpoints
    const targetKinds = results[0].targets.map((t) => t.kind);
    expect(targetKinds).toContain("edge");
    expect(targetKinds.filter((k) => k === "port")).toHaveLength(2);
  });

  it("emits no result for FlowPort → FlowPort (compatible)", () => {
    const pump = makeNode("pump1", "Pump", "pump1");
    const ch = makeNode("ch1", "Channel", "ch1");
    const edge = makeEdge("e1", "pump1", "port_out", "ch1", "port_in");

    const snapshot = makeSnapshot([pump, ch], [edge]);
    const results = portType.run(snapshot);
    expect(results).toHaveLength(0);
  });

  it("emits no result for ThermalPort → ThermalPort (compatible)", () => {
    const ct = makeNode("ct1", "ConstantTemperature", "ct1");
    const hd = makeNode("hd1", "HeatDiffusion", "hd1");
    const edge = makeEdge("e1", "ct1", "thermal", "hd1", "thermal_left");

    const snapshot = makeSnapshot([ct, hd], [edge]);
    const results = portType.run(snapshot);
    expect(results).toHaveLength(0);
  });

  it("emits no result for allowed BCPort: WallTemperature → Channel.T_wall_left", () => {
    const wt = makeNode("wt1", "WallTemperature", "wt1");
    const ch = makeNode("ch1", "Channel", "ch1");
    const edge = makeEdge("e1", "wt1", "T_wall_out", "ch1", "T_wall_left");

    const snapshot = makeSnapshot([wt, ch], [edge]);
    const results = portType.run(snapshot);
    expect(results).toHaveLength(0);
  });

  it("emits error for disallowed BCPort: WallTemperature → HeatDiffusion", () => {
    const wt = makeNode("wt1", "WallTemperature", "wt1");
    const hd = makeNode("hd1", "HeatDiffusion", "hd1");
    const edge = makeEdge("e1", "wt1", "T_wall_out", "hd1", "thermal_left");

    const snapshot = makeSnapshot([wt, hd], [edge]);
    const results = portType.run(snapshot);

    expect(results).toHaveLength(1);
    expect(results[0].severity).toBe("error");
    expect(results[0].validatorId).toBe("port_type");
  });

  it("emits no result when source node is missing (defensive)", () => {
    // Edge references a non-existent source node
    const ch = makeNode("ch1", "Channel", "ch1");
    const edge = makeEdge("e1", "missing-node", "port_out", "ch1", "port_in");

    const snapshot = makeSnapshot([ch], [edge]);
    const results = portType.run(snapshot);
    expect(results).toHaveLength(0);
  });

  it("emits error for mixed BCPort → FlowPort edge", () => {
    const wt = makeNode("wt1", "WallTemperature", "wt1");
    const pump = makeNode("pump1", "Pump", "pump1");
    // Trying to connect BCPort T_wall_out → FlowPort port_in
    const edge = makeEdge("e1", "wt1", "T_wall_out", "pump1", "port_in");

    const snapshot = makeSnapshot([wt, pump], [edge]);
    const results = portType.run(snapshot);

    expect(results).toHaveLength(1);
    expect(results[0].severity).toBe("error");
  });

  it("emits no result for allowed BCPort: HeatFluxSource → ChannelHeatFlux.q_left", () => {
    const hfs = makeNode("hfs1", "HeatFluxSource", "hfs1");
    const chf = makeNode("chf1", "ChannelHeatFlux", "chf1");
    const edge = makeEdge("e1", "hfs1", "q_out", "chf1", "q_left");

    const snapshot = makeSnapshot([hfs, chf], [edge]);
    const results = portType.run(snapshot);
    expect(results).toHaveLength(0);
  });
});
