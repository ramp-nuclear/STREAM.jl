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

  it("emits 1 warning for closed loop with unbalanced gravity (H=+10 only)", () => {
    // Loop: pump → g_up(H=+10) → ch → pump
    // g_up traversed source→target (pump→g_up→ch): source is g_up → add +10
    // Net = +10 ≠ 0 → warning (Phase 72 severity audit — non-physical
    // steady state but code still compiles and the solver runs).
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
    expect(results[0].severity).toBe("warning");
    expect(results[0].validatorId).toBe("gravity_sum_per_loop");
    // Description should mention the net value
    expect(results[0].description).toContain("10");
    // Phase 72 redesign — loop highlight, not single-component focus:
    // - Node targets cover EVERY node on the loop (Pump, Gravity, Channel).
    // - Edge targets cover EVERY edge on the loop, fed to the marching-ants
    //   flow trace.
    // - NO field targets (the H-field highlight singled out a property that
    //   has no per-field action to take).
    const nodeTargets = results[0].targets.filter((t) => t.kind === "node");
    expect(nodeTargets.some((t) => t.kind === "node" && t.nodeId === "g_up")).toBe(true);
    expect(nodeTargets.some((t) => t.kind === "node" && t.nodeId === "pump1")).toBe(true);
    expect(nodeTargets.some((t) => t.kind === "node" && t.nodeId === "ch1")).toBe(true);

    const edgeTargets = results[0].targets.filter((t) => t.kind === "edge");
    expect(edgeTargets.length).toBe(3);

    const fieldTargets = results[0].targets.filter((t) => t.kind === "field");
    expect(fieldTargets.length).toBe(0);
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

  // -------------------------------------------------------------------------
  // Phase 72 user-scenario regression — two simple cycles share a return edge,
  // exactly one is broken. The fix delivers two things:
  //   (1) findAllSimpleCycles enumerates each cycle independently (no SCC
  //       blob), and
  //   (2) the validator sums hydrostatic head across ALL height-bearing
  //       components, not just Gravity — so a vertical Channel with
  //       geometry.L = 1 contributes +1 (matches Python STREAM
  //       check_gravity_mismatch convention).
  //
  // Network (user setup, 2026-05-22):
  //   channel_1: vertical (g = 9.80665), geometry.L = 1
  //   gravity_1: H = +2
  //   gravity_2: H = -1
  //
  //   pump → channel_1 → gravity_2 → pump        [cycle A: +1 + (-1) = 0  OK]
  //   pump → gravity_1 → gravity_2 → pump        [cycle B: +2 + (-1) = +1 BAD]
  //
  // Expected: exactly ONE warning, on cycle B, with targets scoped to
  // {pump1, g1, g2} and {e_pump_g1, e_g1_g2, e_g2_pump}. Cycle A balances
  // because channel_1's vertical span (L=1) cancels gravity_2's H=-1.
  // -------------------------------------------------------------------------
  it("emits ONE warning on the unbalanced cycle when a vertical channel balances the other", () => {
    const GEOM_UUID = "geom-1m";

    const pump = makeNode("pump1", "Pump");
    // 9.80665 matches Earth's g exactly so the channel L=1 cancels gravity_2 H=-1
    // to within tolerance. Real canvas usage cascades this same value via
    // modelOptions.g_default → addNode → params.g.
    const ch = makeNode("ch1", "Channel", { g: 9.80665, geometry: GEOM_UUID });
    const g1 = makeNode("g1", "Gravity", { H: 2 });
    const g2 = makeNode("g2", "Gravity", { H: -1 });

    const snapshot: ValidationSnapshot = {
      nodes: [pump, ch, g1, g2],
      edges: [
        makeEdge("e_pump_ch", "pump1", "port_out", "ch1", "port_in"),
        makeEdge("e_ch_g2", "ch1", "port_out", "g2", "port_in"),
        makeEdge("e_pump_g1", "pump1", "port_out", "g1", "port_in"),
        makeEdge("e_g1_g2", "g1", "port_out", "g2", "port_in"),
        makeEdge("e_g2_pump", "g2", "port_out", "pump1", "port_in"),
      ],
      anchors: {},
      bcMode: {},
      resources: {
        // Channel's geometry resource: L = 1 (vertical span when g > 0).
        geometries: {
          [GEOM_UUID]: {
            id: GEOM_UUID,
            kind: "rectangular",
            params: { L: 1, W: 0.01, H: 0.001 },
          },
        },
        powerShapes: {},
        fluids: {},
      },
      getComponentDef: (id: string) => DEFS[id],
    } as unknown as ValidationSnapshot;

    const results = gravitySumPerLoop.run(snapshot);
    expect(results).toHaveLength(1);

    const r = results[0];
    expect(r.severity).toBe("warning");
    expect(r.description).toContain("1.00");

    const nodeTargets = new Set(
      r.targets.filter((t) => t.kind === "node").map((t) => (t.kind === "node" ? t.nodeId : "")),
    );
    const edgeTargets = new Set(
      r.targets.filter((t) => t.kind === "edge").map((t) => (t.kind === "edge" ? t.edgeId : "")),
    );

    // The reported broken cycle is the gravity cycle (pump → g1 → g2 → pump).
    expect(nodeTargets.has("pump1")).toBe(true);
    expect(nodeTargets.has("g1")).toBe(true);
    expect(nodeTargets.has("g2")).toBe(true);
    expect(edgeTargets.has("e_pump_g1")).toBe(true);
    expect(edgeTargets.has("e_g1_g2")).toBe(true);
    expect(edgeTargets.has("e_g2_pump")).toBe(true);

    // The channel cycle is balanced and not reported — ch1 and its edges
    // must NOT appear as targets.
    expect(nodeTargets.has("ch1")).toBe(false);
    expect(edgeTargets.has("e_pump_ch")).toBe(false);
    expect(edgeTargets.has("e_ch_g2")).toBe(false);

    expect(r.targets.filter((t) => t.kind === "field")).toHaveLength(0);
  });

  // -------------------------------------------------------------------------
  // Horizontal channel (g === 0) contributes nothing — both cycles broken.
  // -------------------------------------------------------------------------
  it("when a Channel has g = 0 (horizontal) it contributes 0 to ΣH", () => {
    const GEOM_UUID = "geom-1m";

    const pump = makeNode("pump1", "Pump");
    const ch = makeNode("ch1", "Channel", { g: 0, geometry: GEOM_UUID });
    const g1 = makeNode("g1", "Gravity", { H: 2 });
    const g2 = makeNode("g2", "Gravity", { H: -1 });

    const snapshot: ValidationSnapshot = {
      nodes: [pump, ch, g1, g2],
      edges: [
        makeEdge("e_pump_ch", "pump1", "port_out", "ch1", "port_in"),
        makeEdge("e_ch_g2", "ch1", "port_out", "g2", "port_in"),
        makeEdge("e_pump_g1", "pump1", "port_out", "g1", "port_in"),
        makeEdge("e_g1_g2", "g1", "port_out", "g2", "port_in"),
        makeEdge("e_g2_pump", "g2", "port_out", "pump1", "port_in"),
      ],
      anchors: {},
      bcMode: {},
      resources: {
        geometries: {
          [GEOM_UUID]: {
            id: GEOM_UUID,
            kind: "rectangular",
            params: { L: 1, W: 0.01, H: 0.001 },
          },
        },
        powerShapes: {},
        fluids: {},
      },
      getComponentDef: (id: string) => DEFS[id],
    } as unknown as ValidationSnapshot;

    const results = gravitySumPerLoop.run(snapshot);
    // Both cycles are now broken because channel can't balance anything.
    // Cycle A (channel path): only g2 contributes (-1)        → BROKEN
    // Cycle B (gravity path): g1 + g2 = +1                    → BROKEN
    expect(results).toHaveLength(2);
  });
});
