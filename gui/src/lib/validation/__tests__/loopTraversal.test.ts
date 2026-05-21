// loopTraversal.test.ts — Unit tests for findHydraulicLoops (Phase 71, Plan 02)
//
// Test environment: node (no DOM needed — pure function)
// Tests use Set equality for nodeIds because findHydraulicLoops returns nodes in
// discovery order, which is stable but rotation-arbitrary for a given cycle.

import { describe, it, expect } from "vitest";
import { findHydraulicLoops, type HydraulicLoop } from "../loopTraversal";
import type { Node, Edge } from "@xyflow/react";
import type { ComponentDefinition } from "@/registry/types";

// ---------------------------------------------------------------------------
// Fixture component definitions
// ---------------------------------------------------------------------------

const Pump: ComponentDefinition = {
  id: "Pump",
  label: "Pump",
  category: "Hydraulic",
  description: "",
  ports: [
    { name: "port_in", type: "FlowPort", side: "left" },
    { name: "port_out", type: "FlowPort", side: "right" },
  ],
  parameters: [],
  constructorModes: [],
};

const Channel: ComponentDefinition = {
  id: "Channel",
  label: "Channel",
  category: "Hydraulic",
  description: "",
  ports: [
    { name: "port_in", type: "FlowPort", side: "left" },
    { name: "port_out", type: "FlowPort", side: "right" },
    { name: "T_wall_left", type: "BCPort", side: "bottom" },
  ],
  parameters: [],
  constructorModes: [],
};

const HeatExchanger: ComponentDefinition = {
  id: "HeatExchanger",
  label: "Heat Exchanger",
  category: "Hydraulic",
  description: "",
  ports: [
    { name: "port_in", type: "FlowPort", side: "left" },
    { name: "port_out", type: "FlowPort", side: "right" },
  ],
  parameters: [],
  constructorModes: [],
};

// ChannelAndContacts has both FlowPort and ThermalPort
const ChannelAndContacts: ComponentDefinition = {
  id: "ChannelAndContacts",
  label: "Channel and Contacts",
  category: "Hydraulic",
  description: "",
  ports: [
    { name: "port_in", type: "FlowPort", side: "left" },
    { name: "port_out", type: "FlowPort", side: "right" },
    { name: "thermal_left", type: "ThermalPort" },
    { name: "thermal_right", type: "ThermalPort" },
  ],
  parameters: [],
  constructorModes: [],
};

// HeatDiffusion has only ThermalPorts — no FlowPorts
const HeatDiffusion: ComponentDefinition = {
  id: "HeatDiffusion",
  label: "Heat Diffusion",
  category: "Thermal",
  description: "",
  ports: [
    { name: "thermal_left", type: "ThermalPort" },
    { name: "thermal_right", type: "ThermalPort" },
  ],
  parameters: [],
  constructorModes: [],
};

const fixturesByCompId: Record<string, ComponentDefinition> = {
  Pump,
  Channel,
  HeatExchanger,
  ChannelAndContacts,
  HeatDiffusion,
};

// ---------------------------------------------------------------------------
// Factory helpers
// ---------------------------------------------------------------------------

function makeNode(id: string, componentId: string): Node {
  return {
    id,
    type: "streamNode",
    position: { x: 0, y: 0 },
    data: { componentId, instanceName: id, parameters: {} },
  };
}

function makeEdge(
  id: string,
  source: string,
  sourceHandle: string,
  target: string,
  targetHandle: string,
): Edge {
  return { id, source, sourceHandle, target, targetHandle };
}

function getComponentDef(id: string): ComponentDefinition | undefined {
  return fixturesByCompId[id];
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("findHydraulicLoops", () => {
  // 1. Empty graph returns []
  it("returns [] for empty graph", () => {
    const result = findHydraulicLoops([], [], getComponentDef);
    expect(result).toEqual([]);
  });

  // 2. Single open chain (no loop)
  it("returns [] for an open chain with no return edge", () => {
    const nodes = [
      makeNode("pump", "Pump"),
      makeNode("ch1", "Channel"),
      makeNode("hx", "HeatExchanger"),
    ];
    // Pump → Channel → HeatExchanger (no return edge)
    const edges = [
      makeEdge("e1", "pump", "port_out", "ch1", "port_in"),
      makeEdge("e2", "ch1", "port_out", "hx", "port_in"),
    ];
    const result = findHydraulicLoops(nodes, edges, getComponentDef);
    expect(result).toEqual([]);
  });

  // 3. Two-node closed loop
  it("returns 1 loop for a 2-node closed cycle (Pump ↔ Channel)", () => {
    const nodes = [
      makeNode("pump", "Pump"),
      makeNode("ch1", "Channel"),
    ];
    // Pump.port_out → Channel.port_in; Channel.port_out → Pump.port_in
    const edges = [
      makeEdge("e1", "pump", "port_out", "ch1", "port_in"),
      makeEdge("e2", "ch1", "port_out", "pump", "port_in"),
    ];
    const result = findHydraulicLoops(nodes, edges, getComponentDef);
    expect(result).toHaveLength(1);
    expect(new Set(result[0].nodeIds)).toEqual(new Set(["pump", "ch1"]));
    expect(new Set(result[0].edgeIds)).toEqual(new Set(["e1", "e2"]));
  });

  // 4. Three-node closed loop
  it("returns 1 loop with all 3 nodes for a 3-node cycle (Pump → Channel → HX → Pump)", () => {
    const nodes = [
      makeNode("pump", "Pump"),
      makeNode("ch1", "Channel"),
      makeNode("hx", "HeatExchanger"),
    ];
    const edges = [
      makeEdge("e1", "pump", "port_out", "ch1", "port_in"),
      makeEdge("e2", "ch1", "port_out", "hx", "port_in"),
      makeEdge("e3", "hx", "port_out", "pump", "port_in"),
    ];
    const result = findHydraulicLoops(nodes, edges, getComponentDef);
    expect(result).toHaveLength(1);
    expect(new Set(result[0].nodeIds)).toEqual(new Set(["pump", "ch1", "hx"]));
    expect(new Set(result[0].edgeIds)).toEqual(new Set(["e1", "e2", "e3"]));
  });

  // 5. Two disjoint loops
  it("returns exactly 2 loops with disjoint nodeId sets for two disconnected cycles", () => {
    const nodes = [
      // Loop A
      makeNode("pumpA", "Pump"),
      makeNode("chA", "Channel"),
      // Loop B
      makeNode("pumpB", "Pump"),
      makeNode("chB", "Channel"),
    ];
    const edges = [
      // Loop A
      makeEdge("eA1", "pumpA", "port_out", "chA", "port_in"),
      makeEdge("eA2", "chA", "port_out", "pumpA", "port_in"),
      // Loop B
      makeEdge("eB1", "pumpB", "port_out", "chB", "port_in"),
      makeEdge("eB2", "chB", "port_out", "pumpB", "port_in"),
    ];
    const result = findHydraulicLoops(nodes, edges, getComponentDef);
    expect(result).toHaveLength(2);
    const loopNodeSets = result.map((l) => new Set(l.nodeIds));
    expect(loopNodeSets[0]).not.toEqual(loopNodeSets[1]);
    // Together they cover all 4 nodes
    const allNodes = new Set([...loopNodeSets[0], ...loopNodeSets[1]]);
    expect(allNodes).toEqual(new Set(["pumpA", "chA", "pumpB", "chB"]));
    // Sets are disjoint
    for (const id of loopNodeSets[0]) {
      expect(loopNodeSets[1].has(id)).toBe(false);
    }
  });

  // 6. Pure-thermal node (HeatDiffusion) with only thermal edges is ignored
  it("ignores a thermal-only node even if thermal edges connect to it", () => {
    const nodes = [
      makeNode("pump", "Pump"),
      makeNode("ch1", "Channel"),
      makeNode("hd", "HeatDiffusion"),
    ];
    // Hydraulic loop: Pump ↔ Channel
    // Thermal edge from Channel.T_wall_left → HeatDiffusion (non-FlowPort handles)
    const edges = [
      makeEdge("e1", "pump", "port_out", "ch1", "port_in"),
      makeEdge("e2", "ch1", "port_out", "pump", "port_in"),
      makeEdge("e3", "ch1", "T_wall_left", "hd", "thermal_left"),
    ];
    const result = findHydraulicLoops(nodes, edges, getComponentDef);
    expect(result).toHaveLength(1);
    // HeatDiffusion node NOT in the loop
    expect(result[0].nodeIds).not.toContain("hd");
    // Thermal edge NOT in the loop
    expect(result[0].edgeIds).not.toContain("e3");
  });

  // 7. CAC node with both FlowPort cycle AND thermal edges — thermal edge excluded
  it("excludes thermal edges from a loop even when node has both FlowPort and ThermalPort", () => {
    const nodes = [
      makeNode("pump", "Pump"),
      makeNode("cac", "ChannelAndContacts"),
      makeNode("hd", "HeatDiffusion"),
    ];
    // FlowPort cycle: Pump ↔ CAC
    // Thermal edge: CAC.thermal_left → HeatDiffusion.thermal_left
    const edges = [
      makeEdge("e1", "pump", "port_out", "cac", "port_in"),
      makeEdge("e2", "cac", "port_out", "pump", "port_in"),
      makeEdge("e3", "cac", "thermal_left", "hd", "thermal_left"),
    ];
    const result = findHydraulicLoops(nodes, edges, getComponentDef);
    expect(result).toHaveLength(1);
    expect(new Set(result[0].nodeIds)).toEqual(new Set(["pump", "cac"]));
    // Thermal edge must not appear in the returned edgeIds
    expect(result[0].edgeIds).not.toContain("e3");
    // HeatDiffusion node not in loop
    expect(result[0].nodeIds).not.toContain("hd");
  });

  // 8. Referential inequality — two consecutive calls with same input return different arrays
  it("returns a new array per call (no shared mutable state)", () => {
    const nodes = [
      makeNode("pump", "Pump"),
      makeNode("ch1", "Channel"),
    ];
    const edges = [
      makeEdge("e1", "pump", "port_out", "ch1", "port_in"),
      makeEdge("e2", "ch1", "port_out", "pump", "port_in"),
    ];
    const result1 = findHydraulicLoops(nodes, edges, getComponentDef);
    const result2 = findHydraulicLoops(nodes, edges, getComponentDef);
    // Different array references
    expect(result1).not.toBe(result2);
    // But same contents (Set equality on nodeIds)
    expect(new Set(result1[0].nodeIds)).toEqual(new Set(result2[0].nodeIds));
    expect(new Set(result1[0].edgeIds)).toEqual(new Set(result2[0].edgeIds));
  });
});
