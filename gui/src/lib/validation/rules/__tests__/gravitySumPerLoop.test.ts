// gravitySumPerLoop.test.ts — Unit tests for the gravitySumPerLoop validator (Phase 71, Plan 07)
//
// D-15 rule 8: "gravity-sum-per-loop" — for each closed hydraulic loop, the signed
// gravity contributions must net to zero. A non-zero net means the pressure bookkeeping
// is inconsistent and the solver will produce wrong steady-state dP values.
//
// Test environment: node (pure function, no DOM needed).

import { describe, it, expect } from "vitest";
import type { Node, Edge } from "@xyflow/react";
import type { ValidationSnapshot } from "../../snapshot";
import type { ComponentDefinition } from "../../../../registry/types";

// Import after writing the rule file (GREEN phase)
import { gravitySumPerLoop } from "../gravitySumPerLoop";

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
  ],
  parameters: [],
  constructorModes: [],
};

const DEFS: Record<string, ComponentDefinition> = {
  Pump: PUMP_DEF,
  Gravity: GRAVITY_DEF,
  Channel: CHANNEL_DEF,
};

// ---------------------------------------------------------------------------
// Factory helpers
// ---------------------------------------------------------------------------

function makeNode(
  id: string,
  componentId: string,
  parameters: Record<string, unknown> = {},
): Node {
  return {
    id,
    type: "streamNode",
    position: { x: 0, y: 0 },
    data: {
      componentId,
      instanceName: id,
      parameters,
    },
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

describe("gravitySumPerLoop validator", () => {
  it("emits no result for closed loop with balanced gravity (H=+10 and H=-10)", () => {
    // Loop: g_up(H=+10) → ch → g_down(H=-10) → pump → g_up
    // Gravity g_up traversed source→target: source is g_up → add +10
    // Gravity g_down traversed source→target: source is g_down → add -10
    // Net = 0 → no error
    const pump = makeNode("pump1", "Pump");
    const ch = makeNode("ch1", "Channel");
    const gUp = makeNode("g_up", "Gravity", { H: 10 });
    const gDown = makeNode("g_down", "Gravity", { H: -10 });
    const snapshot = makeSnapshot([pump, ch, gUp, gDown], [
      makeEdge("e1", "pump1", "port_out", "g_up", "port_in"),
      makeEdge("e2", "g_up", "port_out", "ch1", "port_in"),
      makeEdge("e3", "ch1", "port_out", "g_down", "port_in"),
      makeEdge("e4", "g_down", "port_out", "pump1", "port_in"),
    ]);
    const results = gravitySumPerLoop.run(snapshot);
    expect(results).toHaveLength(0);
  });

  it("emits 1 error for closed loop with unbalanced gravity (H=+10 only)", () => {
    // Loop: pump → g_up(H=+10) → ch → pump
    // g_up traversed source→target (pump→g_up→ch): source is g_up → add +10
    // Net = +10 ≠ 0 → error
    const pump = makeNode("pump1", "Pump");
    const ch = makeNode("ch1", "Channel");
    const gUp = makeNode("g_up", "Gravity", { H: 10 });
    const snapshot = makeSnapshot([pump, ch, gUp], [
      makeEdge("e1", "pump1", "port_out", "g_up", "port_in"),
      makeEdge("e2", "g_up", "port_out", "ch1", "port_in"),
      makeEdge("e3", "ch1", "port_out", "pump1", "port_in"),
    ]);
    const results = gravitySumPerLoop.run(snapshot);
    expect(results).toHaveLength(1);
    expect(results[0].severity).toBe("error");
    expect(results[0].validatorId).toBe("gravity_sum_per_loop");
    // Description should mention the net value
    expect(results[0].description).toContain("10");
    // Targets must include the Gravity node
    const nodeTargets = results[0].targets.filter((t) => t.kind === "node");
    expect(nodeTargets.some((t) => t.kind === "node" && t.nodeId === "g_up")).toBe(true);
    // Targets must include field target for H (property-panel highlight bridge)
    const fieldTargets = results[0].targets.filter((t) => t.kind === "field");
    expect(fieldTargets.length).toBeGreaterThanOrEqual(1);
    expect(
      fieldTargets.some(
        (t) => t.kind === "field" && t.nodeId === "g_up" && t.fieldPath === "H",
      ),
    ).toBe(true);
  });

  it("emits no result for closed loop with no Gravity components", () => {
    // Loop: pump ↔ channel — no gravity, net = 0
    const pump = makeNode("pump1", "Pump");
    const ch = makeNode("ch1", "Channel");
    const snapshot = makeSnapshot([pump, ch], [
      makeEdge("e1", "pump1", "port_out", "ch1", "port_in"),
      makeEdge("e2", "ch1", "port_out", "pump1", "port_in"),
    ]);
    const results = gravitySumPerLoop.run(snapshot);
    expect(results).toHaveLength(0);
  });

  it("respects traversal direction: Gravity traversed backward (port_out → port_in) contributes -H", () => {
    // The signed-traversal convention is based on the sourceHandle of the outgoing edge
    // from the Gravity node:
    //   sourceHandle = 'port_out' → forward traversal (port_in → port_out) → +H
    //   sourceHandle = 'port_in'  → backward traversal (port_out → port_in) → -H
    //
    // This loop has one Gravity traversed forward (+H) and one traversed backward (-H):
    //   g_fwd(H=10): outgoing edge uses port_out → +10
    //   g_bwd(H=10): outgoing edge uses port_in  → -10  (flow goes "downhill" through it)
    //   Net = +10 - 10 = 0 → no error
    const pump = makeNode("pump1", "Pump");
    const g_fwd = makeNode("g_fwd", "Gravity", { H: 10 });
    const ch = makeNode("ch1", "Channel");
    const g_bwd = makeNode("g_bwd", "Gravity", { H: 10 });
    // Loop: pump → g_fwd (forward) → ch → g_bwd (backward: exits via port_in) → pump
    const snapshot = makeSnapshot([pump, g_fwd, ch, g_bwd], [
      makeEdge("e1", "pump1", "port_out", "g_fwd", "port_in"),    // entering g_fwd
      makeEdge("e2", "g_fwd", "port_out", "ch1", "port_in"),      // g_fwd forward: sourceHandle=port_out → +10
      makeEdge("e3", "ch1", "port_out", "g_bwd", "port_out"),     // entering g_bwd via port_out
      makeEdge("e4", "g_bwd", "port_in", "pump1", "port_in"),     // g_bwd backward: sourceHandle=port_in → -10
    ]);
    // Net = +10 (g_fwd forward) + (-10) (g_bwd backward) = 0 → no error
    const results = gravitySumPerLoop.run(snapshot);
    expect(results).toHaveLength(0);
  });

  it("emits error with stable id based on loop node ids", () => {
    const pump = makeNode("pump1", "Pump");
    const ch = makeNode("ch1", "Channel");
    const g = makeNode("g1", "Gravity", { H: 5 });
    const snapshot = makeSnapshot([pump, ch, g], [
      makeEdge("e1", "pump1", "port_out", "g1", "port_in"),
      makeEdge("e2", "g1", "port_out", "ch1", "port_in"),
      makeEdge("e3", "ch1", "port_out", "pump1", "port_in"),
    ]);
    const results = gravitySumPerLoop.run(snapshot);
    expect(results).toHaveLength(1);
    // Stable id must start with the validatorId prefix
    expect(results[0].id).toMatch(/^gravity_sum_per_loop::/);
    // Description mentions the net value (5.00 or similar)
    expect(results[0].description).toContain("5");
  });
});
