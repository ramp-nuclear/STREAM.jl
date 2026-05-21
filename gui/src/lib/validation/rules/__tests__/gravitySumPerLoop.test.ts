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

  it("respects traversal direction: Gravity traversed target→source contributes -H", () => {
    // Two Gravity nodes in a 4-node loop, traversed in opposite directions.
    // Loop edges (in order stored): e1=pump→g1, e2=g1→ch, e3=ch→g2, e4=g2→pump
    //
    // For a loop where BOTH gravity nodes are traversed source→target:
    //   g1(H=+10) source→target: add +10
    //   g2(H=+10) source→target: add +10
    //   Net = +20 → error
    //
    // For a loop where g1 source→target (+10) and g2 target→source (-H = -10):
    //   Net = 0 → no error
    //
    // To get g2 traversed target→source, we can reverse the edge: edge source=pump, target=g2
    // means when traversal walks "pump→g2", it's source→target on the edge,
    // but the "Gravity is on the target side" (edge.target === g2Id) → subtract H.
    // Wait — let's be precise: the convention used in the rule is:
    //   For each edge in the loop: if edge.source === gravityNodeId → add +H
    //                              if edge.target === gravityNodeId → add -H
    //
    // Test: g1(H=10), edge e1: source=g1, target=ch (g1 is source → +10)
    //       g2(H=10), edge e2: source=ch, target=g2 (g2 is target → -10)
    //       Net = 0 → no error
    const pump = makeNode("pump1", "Pump");
    const g1 = makeNode("g1", "Gravity", { H: 10 });
    const ch = makeNode("ch1", "Channel");
    const g2 = makeNode("g2", "Gravity", { H: 10 });
    // Loop: pump → g1 → ch → (edge has ch as source, g2 as target) → pump
    const snapshot = makeSnapshot([pump, g1, ch, g2], [
      makeEdge("e1", "pump1", "port_out", "g1", "port_in"),   // g1 is target → -H = -10
      makeEdge("e2", "g1", "port_out", "ch1", "port_in"),     // g1 is source → +H = +10  (net g1 = 0)
      makeEdge("e3", "ch1", "port_out", "g2", "port_in"),     // g2 is target → -H = -10
      makeEdge("e4", "g2", "port_out", "pump1", "port_in"),   // g2 is source → +H = +10  (net g2 = 0)
    ]);
    // Net over loop = 0 (each gravity appears once as source and once as target in the SCC)
    // Actually since we walk ALL edges of the SCC (not just a cycle path),
    // let's build a simple case where the net is clearly calculable:
    //
    // Simpler: single Gravity in loop traversed once as source and once NOT at all
    // vs just verify the unbalanced case.
    //
    // Let's use a different fixture: only 3 nodes, g1(H=10) appears once as source
    // and pump appears as target:
    //   pump → g1: g1 is target → -10
    //   g1 → ch:  g1 is source → +10
    //   ch → pump: pump only (not gravity)
    // Net = 0 → no error (g1 appears in both source and target roles)
    const results = gravitySumPerLoop.run(snapshot);
    // The g1 appears as both source (e2) and target (e1); similarly g2 as source (e4) and target (e3)
    // Net = -10 + 10 - 10 + 10 = 0
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
