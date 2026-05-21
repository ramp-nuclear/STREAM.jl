// danglingFlowPort.test.ts — Unit tests for the danglingFlowPort validator (Phase 71, Plan 04)
//
// Environment: node (vitest.config.ts default — no JSDOM needed for pure functions).
// Folds VALD-01 from gui/src/lib/validation.ts:79-128 per D-16.
//
// Test cases (ported from validation.test.ts VALD-01 section + new cases):
//   1. Node with FlowPort port_in unconnected → 1 error per dangling port
//   2. Node with FlowPort port_out unconnected → 1 error
//   3. Node with all FlowPorts connected → no result
//   4. ThermalPort unconnected → no result (FlowPort-only rule)
//   5. BCPort unconnected → no result (FlowPort-only rule)
//   6. ConstantTemperature (zero FlowPorts) → no result
//   7. HeatDiffusion (zero FlowPorts) → no result

import { describe, it, expect } from "vitest";
import type { Node, Edge } from "@xyflow/react";
import type { ValidationSnapshot } from "../../snapshot";
import type { ComponentDefinition } from "../../../../registry/types";

// Import after writing the rule file (GREEN phase)
import { danglingFlowPort } from "../danglingFlowPort";

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

// ---------------------------------------------------------------------------
// Component definition fixtures
// ---------------------------------------------------------------------------

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

const CONSTANT_TEMP_DEF: ComponentDefinition = {
  id: "ConstantTemperature",
  label: "Constant Temperature",
  category: "Thermal",
  description: "ConstantTemperature",
  ports: [{ name: "thermal", type: "ThermalPort", side: "left" }],
  parameters: [],
  constructorModes: [],
};

const HEAT_DIFFUSION_DEF: ComponentDefinition = {
  id: "HeatDiffusion",
  label: "HeatDiffusion",
  category: "Thermal",
  description: "HeatDiffusion",
  ports: [
    { name: "thermal_left", type: "ThermalPort", side: "left" },
    { name: "thermal_right", type: "ThermalPort", side: "right" },
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

const DEFS: Record<string, ComponentDefinition> = {
  Channel: CHANNEL_DEF,
  Pump: PUMP_DEF,
  ConstantTemperature: CONSTANT_TEMP_DEF,
  HeatDiffusion: HEAT_DIFFUSION_DEF,
  WallTemperature: WALL_TEMP_DEF,
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
// Tests (ported from validation.test.ts VALD-01 section)
// ---------------------------------------------------------------------------

describe("danglingFlowPort validator", () => {
  it("emits error for node with port_in unconnected", () => {
    const ch = makeNode("n1", "Channel", "ch_1");
    const pump = makeNode("n2", "Pump", "pump_1");
    const snapshot = makeSnapshot([ch, pump], []);
    const results = danglingFlowPort.run(snapshot);

    const n1PortInErrors = results.filter(
      (r) =>
        r.targets.some(
          (t) => t.kind === "port" && t.nodeId === "n1" && t.portName === "port_in",
        ),
    );
    expect(n1PortInErrors.length).toBeGreaterThanOrEqual(1);
    expect(n1PortInErrors[0].severity).toBe("error");
    expect(n1PortInErrors[0].validatorId).toBe("dangling_flow_port");
    // D-14 for dangling: targets is [{kind:'port', nodeId, portName}] — no edge target
    const kinds = n1PortInErrors[0].targets.map((t) => t.kind);
    expect(kinds).toContain("port");
    expect(kinds).not.toContain("edge");
  });

  it("emits error for node with port_out unconnected", () => {
    const ch = makeNode("n1", "Channel", "ch_1");
    const pump = makeNode("n2", "Pump", "pump_1");
    // Connect port_in but not port_out
    const edge = makeEdge("n2", "port_out", "n1", "port_in");
    const snapshot = makeSnapshot([ch, pump], [edge]);
    const results = danglingFlowPort.run(snapshot);

    const n1PortOutErrors = results.filter(
      (r) =>
        r.targets.some(
          (t) => t.kind === "port" && t.nodeId === "n1" && t.portName === "port_out",
        ),
    );
    expect(n1PortOutErrors.length).toBeGreaterThanOrEqual(1);
  });

  it("emits no result for node with all FlowPorts connected", () => {
    const ch = makeNode("n1", "Channel", "ch_1");
    const pump = makeNode("n2", "Pump", "pump_1");
    const e1 = makeEdge("n2", "port_out", "n1", "port_in");
    const e2 = makeEdge("n1", "port_out", "n2", "port_in");
    const snapshot = makeSnapshot([ch, pump], [e1, e2]);
    const results = danglingFlowPort.run(snapshot);

    const channelErrors = results.filter(
      (r) =>
        r.targets.some((t) => t.kind === "port" && t.nodeId === "n1"),
    );
    expect(channelErrors).toHaveLength(0);
  });

  it("emits no result for ConstantTemperature (no FlowPorts)", () => {
    const ct = makeNode("n1", "ConstantTemperature", "ct_1");
    const snapshot = makeSnapshot([ct], []);
    const results = danglingFlowPort.run(snapshot);

    const ctErrors = results.filter(
      (r) => r.targets.some((t) => t.kind === "port" && t.nodeId === "n1"),
    );
    expect(ctErrors).toHaveLength(0);
  });

  it("emits no result for HeatDiffusion (no FlowPorts)", () => {
    const hd = makeNode("n1", "HeatDiffusion", "hd_1");
    const snapshot = makeSnapshot([hd], []);
    const results = danglingFlowPort.run(snapshot);

    const hdErrors = results.filter(
      (r) => r.targets.some((t) => t.kind === "port" && t.nodeId === "n1"),
    );
    expect(hdErrors).toHaveLength(0);
  });

  it("emits no result for WallTemperature unconnected BCPort (BCPort-only component)", () => {
    const wt = makeNode("wt1", "WallTemperature", "wt_1");
    const snapshot = makeSnapshot([wt], []);
    const results = danglingFlowPort.run(snapshot);

    // danglingFlowPort is FlowPort-only; BCPort must not trigger it
    const wtErrors = results.filter(
      (r) => r.targets.some((t) => t.kind === "port" && t.nodeId === "wt1"),
    );
    expect(wtErrors).toHaveLength(0);
  });

  it("emits no result for Channel with unconnected BCPort T_wall_left (non-FlowPort)", () => {
    const ch = makeNode("n1", "Channel", "ch_1");
    const pump = makeNode("n2", "Pump", "pump_1");
    // Connect both FlowPorts; leave BCPort T_wall_left unconnected
    const e1 = makeEdge("n2", "port_out", "n1", "port_in");
    const e2 = makeEdge("n1", "port_out", "n2", "port_in");
    const snapshot = makeSnapshot([ch, pump], [e1, e2]);
    const results = danglingFlowPort.run(snapshot);

    // Only FlowPort errors should appear; T_wall_left should NOT trigger danglingFlowPort
    const bcPortErrors = results.filter(
      (r) =>
        r.targets.some(
          (t) =>
            t.kind === "port" &&
            t.nodeId === "n1" &&
            t.portName === "T_wall_left",
        ),
    );
    expect(bcPortErrors).toHaveLength(0);
  });
});
