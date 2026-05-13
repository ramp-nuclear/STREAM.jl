// validation.test.ts — Unit tests for topology validation (Phase 39)

import { describe, it, expect } from "vitest";
import {
  validateTopology,
  type TopologyResult,
  type NodeError,
  type SystemError,
} from "./validation";
import type { Node, Edge } from "@xyflow/react";
import type { ComponentDefinition } from "../registry/types";

// ---------------------------------------------------------------------------
// Mock helpers
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
    data: { componentId, instanceName, parameters: {} },
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

/** Minimal component definitions for testing. */
const mockDefs: Record<string, ComponentDefinition> = {
  Channel: {
    id: "Channel",
    label: "Channel",
    category: "Hydraulic",
    description: "",
    ports: [
      { name: "port_in", type: "FlowPort", side: "left" },
      { name: "port_out", type: "FlowPort", side: "right" },
    ],
    parameters: [],
    constructorModes: [],
  },
  Pump: {
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
  },
  Gravity: {
    id: "Gravity",
    label: "Gravity",
    category: "Hydraulic",
    description: "",
    ports: [
      { name: "port_in", type: "FlowPort", side: "left" },
      { name: "port_out", type: "FlowPort", side: "right" },
    ],
    parameters: [],
    constructorModes: [],
  },
  ConstantTemperature: {
    id: "ConstantTemperature",
    label: "Constant Temperature",
    category: "Thermal",
    description: "",
    ports: [
      { name: "thermal", type: "ThermalPort", side: "left" },
    ],
    parameters: [],
    constructorModes: [],
  },
  HeatDiffusion: {
    id: "HeatDiffusion",
    label: "Heat Diffusion",
    category: "Thermal",
    description: "",
    ports: [
      { name: "thermal_left", type: "ThermalPort", side: "left", array: true },
      { name: "thermal_right", type: "ThermalPort", side: "right", array: true },
    ],
    parameters: [],
    constructorModes: [],
  },
};

function mockGetComponent(id: string): ComponentDefinition | undefined {
  return mockDefs[id];
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("validateTopology", () => {
  // VALD-01: unconnected FlowPorts

  it("detects unconnected port_in on a node", () => {
    const nodes = [makeNode("n1", "Channel", "ch_1")];
    const edges: Edge[] = [];
    const bcs = { n1: { portField: "port_in.P" as const, value: 1e5 } };
    // Add a Pump so VALD-03 doesn't fire
    nodes.push(makeNode("n2", "Pump", "pump_1"));

    const result = validateTopology(nodes, edges, bcs, mockGetComponent);

    const n1Errors = result.nodeErrors.filter((e) => e.nodeId === "n1");
    expect(n1Errors.some((e) => e.portName === "port_in")).toBe(true);
  });

  it("detects unconnected port_out on a node", () => {
    const nodes = [
      makeNode("n1", "Channel", "ch_1"),
      makeNode("n2", "Pump", "pump_1"),
    ];
    // Connect port_in but not port_out
    const edges = [makeEdge("n2", "port_out", "n1", "port_in")];
    const bcs = { n1: { portField: "port_in.P" as const, value: 1e5 } };

    const result = validateTopology(nodes, edges, bcs, mockGetComponent);

    const n1Errors = result.nodeErrors.filter((e) => e.nodeId === "n1");
    expect(n1Errors.some((e) => e.portName === "port_out")).toBe(true);
  });

  it("returns no nodeErrors for a fully connected node", () => {
    const nodes = [
      makeNode("n1", "Channel", "ch_1"),
      makeNode("n2", "Pump", "pump_1"),
    ];
    // Connect both ports of n1
    const edges = [
      makeEdge("n2", "port_out", "n1", "port_in"),
      makeEdge("n1", "port_out", "n2", "port_in"),
    ];
    const bcs = { n1: { portField: "port_in.P" as const, value: 1e5 } };

    const result = validateTopology(nodes, edges, bcs, mockGetComponent);

    const n1Errors = result.nodeErrors.filter((e) => e.nodeId === "n1");
    expect(n1Errors).toHaveLength(0);
  });

  // VALD-02: missing pressure BCs

  it("detects missing pressure boundary condition when bcs is empty", () => {
    const nodes = [makeNode("n1", "Pump", "pump_1")];
    const edges: Edge[] = [];
    const bcs: Record<string, { portField: "port_in.P" | "port_out.P"; value: number }> = {};

    const result = validateTopology(nodes, edges, bcs, mockGetComponent);

    expect(
      result.systemErrors.some((e) => e.message.includes("pressure")),
    ).toBe(true);
  });

  it("produces no pressure error when bcs is non-empty", () => {
    const nodes = [makeNode("n1", "Pump", "pump_1")];
    const edges: Edge[] = [];
    const bcs = { n1: { portField: "port_in.P" as const, value: 1e5 } };

    const result = validateTopology(nodes, edges, bcs, mockGetComponent);

    expect(
      result.systemErrors.some((e) => e.message.includes("pressure")),
    ).toBe(false);
  });

  // VALD-03: missing driving element

  it("detects no driving element when no Pump or Gravity exists", () => {
    const nodes = [makeNode("n1", "Channel", "ch_1")];
    const edges: Edge[] = [];
    const bcs = { n1: { portField: "port_in.P" as const, value: 1e5 } };

    const result = validateTopology(nodes, edges, bcs, mockGetComponent);

    expect(
      result.systemErrors.some((e) => e.message.includes("driving")),
    ).toBe(true);
  });

  it("produces no driving error when Pump is present", () => {
    const nodes = [
      makeNode("n1", "Channel", "ch_1"),
      makeNode("n2", "Pump", "pump_1"),
    ];
    const edges: Edge[] = [];
    const bcs = { n1: { portField: "port_in.P" as const, value: 1e5 } };

    const result = validateTopology(nodes, edges, bcs, mockGetComponent);

    expect(
      result.systemErrors.some((e) => e.message.includes("driving")),
    ).toBe(false);
  });

  it("produces no driving error when Gravity is present", () => {
    const nodes = [
      makeNode("n1", "Channel", "ch_1"),
      makeNode("n2", "Gravity", "gravity_1"),
    ];
    const edges: Edge[] = [];
    const bcs = { n1: { portField: "port_in.P" as const, value: 1e5 } };

    const result = validateTopology(nodes, edges, bcs, mockGetComponent);

    expect(
      result.systemErrors.some((e) => e.message.includes("driving")),
    ).toBe(false);
  });

  // Thermal-only nodes: no false positives

  it("produces no nodeErrors for ConstantTemperature (zero FlowPorts)", () => {
    const nodes = [
      makeNode("n1", "ConstantTemperature", "ct_1"),
      makeNode("n2", "Pump", "pump_1"),
    ];
    const edges: Edge[] = [];
    const bcs = { n2: { portField: "port_in.P" as const, value: 1e5 } };

    const result = validateTopology(nodes, edges, bcs, mockGetComponent);

    const ctErrors = result.nodeErrors.filter((e) => e.nodeId === "n1");
    expect(ctErrors).toHaveLength(0);
  });

  it("produces no nodeErrors for HeatDiffusion (zero FlowPorts)", () => {
    const nodes = [
      makeNode("n1", "HeatDiffusion", "hd_1"),
      makeNode("n2", "Pump", "pump_1"),
    ];
    const edges: Edge[] = [];
    const bcs = { n2: { portField: "port_in.P" as const, value: 1e5 } };

    const result = validateTopology(nodes, edges, bcs, mockGetComponent);

    const hdErrors = result.nodeErrors.filter((e) => e.nodeId === "n1");
    expect(hdErrors).toHaveLength(0);
  });

  // Full valid topology

  it("returns valid=true when all ports connected, has BCs, has Pump", () => {
    const nodes = [
      makeNode("n1", "Channel", "ch_1"),
      makeNode("n2", "Pump", "pump_1"),
    ];
    const edges = [
      makeEdge("n2", "port_out", "n1", "port_in"),
      makeEdge("n1", "port_out", "n2", "port_in"),
    ];
    const bcs = { n1: { portField: "port_in.P" as const, value: 1e5 } };

    const result = validateTopology(nodes, edges, bcs, mockGetComponent);

    expect(result).toEqual({
      valid: true,
      nodeErrors: [],
      systemErrors: [],
    });
  });
});
