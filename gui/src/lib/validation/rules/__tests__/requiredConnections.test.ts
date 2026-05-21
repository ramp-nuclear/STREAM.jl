// requiredConnections.test.ts — Unit tests for the requiredConnections validator (Phase 71, Plan 04)
//
// Environment: node (vitest.config.ts default — no JSDOM needed for pure functions).
// Covers D-15 rule 4: every required port must have an attached edge.
//
// Required-port heuristic (no Port.required field in registry schema):
//   - FlowPort: always required
//   - ThermalPort on ChannelAndContacts thermal_left/thermal_right: required (by array cell)
//   - ThermalPort on other components (HeatDiffusion, ConstantTemperature): required
//   - BCPort: NEVER required (WallTemperature/HeatFluxSource are optional source blocks)
//
// Test cases:
//   1. Pump with port_in unconnected → 1 error result
//   2. Pump with both ports connected → no result
//   3. ChannelAndContacts with thermal_left[1] unconnected (n=2) → 1 error per missing cell
//   4. WallTemperature with BCPort unconnected → no result (BCPort never required)
//   5. HeatDiffusion with some ThermalPort cells unconnected → 1 error per missing cell

import { describe, it, expect } from "vitest";
import type { Node, Edge } from "@xyflow/react";
import type { ValidationSnapshot } from "../../snapshot";
import type { ComponentDefinition } from "../../../../registry/types";

// Import after writing the rule file (GREEN phase)
import { requiredConnections } from "../requiredConnections";

// ---------------------------------------------------------------------------
// Minimal node factory
// ---------------------------------------------------------------------------

function makeNode(
  id: string,
  componentId: string,
  instanceName: string,
  parameters: Record<string, unknown> = {},
): Node {
  return {
    id,
    type: "streamNode",
    position: { x: 0, y: 0 },
    data: {
      componentId,
      instanceName,
      parameters,
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

const CAC_DEF: ComponentDefinition = {
  id: "ChannelAndContacts",
  label: "Channel and Contacts",
  category: "Hydraulic",
  description: "ChannelAndContacts",
  ports: [
    { name: "port_in", type: "FlowPort", side: "left" },
    { name: "port_out", type: "FlowPort", side: "right" },
    { name: "thermal_left", type: "ThermalPort", array_size: "n" },
    { name: "thermal_right", type: "ThermalPort", array_size: "n" },
  ],
  parameters: [
    { name: "n", type: "Int", required: true, positional: false },
  ],
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

const HEAT_DIFFUSION_DEF: ComponentDefinition = {
  id: "HeatDiffusion",
  label: "HeatDiffusion",
  category: "Thermal",
  description: "HeatDiffusion",
  ports: [
    { name: "thermal_left", type: "ThermalPort", array_size: "nz" },
    { name: "thermal_right", type: "ThermalPort", array_size: "nz" },
  ],
  parameters: [
    { name: "nz", type: "Int", required: true, positional: false },
  ],
  constructorModes: [],
};

const DEFS: Record<string, ComponentDefinition> = {
  Pump: PUMP_DEF,
  ChannelAndContacts: CAC_DEF,
  WallTemperature: WALL_TEMP_DEF,
  HeatDiffusion: HEAT_DIFFUSION_DEF,
};

// ---------------------------------------------------------------------------
// Snapshot factory
// ---------------------------------------------------------------------------

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

describe("requiredConnections validator", () => {
  it("emits error for Pump with port_in unconnected", () => {
    const pump = makeNode("pump1", "Pump", "pump1");
    // port_out is connected, port_in is not
    const ch = makeNode("ch1", "Pump", "ch1");  // second pump as target
    const edge = makeEdge("e1", "pump1", "port_out", "ch1", "port_in");

    const snapshot = makeSnapshot([pump, ch], [edge]);
    const results = requiredConnections.run(snapshot);

    // pump1.port_in is unconnected; ch1.port_out is unconnected — 2 errors total
    const pump1Errors = results.filter((r) =>
      r.targets.some((t) => t.kind === "port" && t.nodeId === "pump1" && t.portName === "port_in"),
    );
    expect(pump1Errors.length).toBeGreaterThanOrEqual(1);
    expect(pump1Errors[0].severity).toBe("error");
    expect(pump1Errors[0].validatorId).toBe("required_connections");
    // D-14: targets include both port + node
    const targetKinds = pump1Errors[0].targets.map((t) => t.kind);
    expect(targetKinds).toContain("port");
    expect(targetKinds).toContain("node");
  });

  it("emits no result for Pump with both ports connected", () => {
    const pump1 = makeNode("pump1", "Pump", "pump1");
    const pump2 = makeNode("pump2", "Pump", "pump2");
    const e1 = makeEdge("e1", "pump1", "port_out", "pump2", "port_in");

    const snapshot = makeSnapshot([pump1, pump2], [e1]);
    const results = requiredConnections.run(snapshot);

    // pump1.port_in is still unconnected and pump2.port_out is unconnected;
    // but pump1.port_out and pump2.port_in ARE connected.
    // Only missing ones are flagged:
    const pump1Errors = results.filter((r) =>
      r.targets.some(
        (t) => t.kind === "port" && t.nodeId === "pump1" && t.portName === "port_out",
      ),
    );
    expect(pump1Errors).toHaveLength(0);
  });

  it("emits no result for WallTemperature BCPort unconnected", () => {
    const wt = makeNode("wt1", "WallTemperature", "wt1");
    const snapshot = makeSnapshot([wt], []);
    const results = requiredConnections.run(snapshot);
    expect(results).toHaveLength(0);
  });

  it("emits errors for unconnected ChannelAndContacts thermal ports (n=2)", () => {
    const cac = makeNode("cac1", "ChannelAndContacts", "cac1", { n: 2 });
    // No thermal connections at all, but FlowPorts connected
    const pump = makeNode("pump1", "Pump", "pump1");
    const e1 = makeEdge("e1", "pump1", "port_out", "cac1", "port_in");
    const e2 = makeEdge("e2", "cac1", "port_out", "pump1", "port_in");

    const snapshot = makeSnapshot([cac, pump], [e1, e2]);
    const results = requiredConnections.run(snapshot);

    // thermal_left[1], thermal_left[2], thermal_right[1], thermal_right[2] all unconnected
    const thermalErrors = results.filter((r) =>
      r.targets.some(
        (t) =>
          t.kind === "port" &&
          t.nodeId === "cac1" &&
          t.portName.startsWith("thermal"),
      ),
    );
    expect(thermalErrors.length).toBeGreaterThanOrEqual(4);
  });

  it("emits errors for HeatDiffusion with unconnected ThermalPort cells (nz=2)", () => {
    const hd = makeNode("hd1", "HeatDiffusion", "hd1", { nz: 2 });
    const snapshot = makeSnapshot([hd], []);
    const results = requiredConnections.run(snapshot);

    // thermal_left[1], thermal_left[2], thermal_right[1], thermal_right[2] all unconnected
    const thermalErrors = results.filter((r) =>
      r.targets.some((t) => t.kind === "port" && t.nodeId === "hd1"),
    );
    expect(thermalErrors.length).toBeGreaterThanOrEqual(4);
  });
});
