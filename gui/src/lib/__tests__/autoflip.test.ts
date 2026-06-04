// @vitest-environment node
//
// autoflip.test.ts — Phase 64 Plan 01 (RED).
//
// Unit tests for the pure geometric autoflip rules locked in CONTEXT decisions
// D-08 through D-18. The module under test is a pure function of
// (nodes, edges, getComponent) — no React, no ReactFlow runtime, no Zustand.
//
// Each `it(...)` carries a comment naming the D-ID it covers so that the
// must_haves traceability is grep-able.

import { describe, it, expect } from "vitest";
import type { Node, Edge } from "@xyflow/react";
import type { ComponentDefinition, Port } from "../../registry/types";
import {
  resolveFlowPortSide,
  resolveFlowPortAssignment,
  resolveThermalPairSides,
  resolveBCPortSide,
  computePortOffset,
  getFlowAxis,
  detectAxisCollision,
  type Side,
} from "../autoflip";

// ---------------------------------------------------------------------------
// Fixture helpers (inline, small, no shared module).
// ---------------------------------------------------------------------------

function makeNode(
  id: string,
  x: number,
  y: number,
  componentId: string,
  w = 140,
  h = 70,
): Node {
  return {
    id,
    type: "streamNode",
    position: { x, y },
    measured: { width: w, height: h },
    data: { componentId, instanceName: id },
  };
}

function makeEdge(
  id: string,
  source: string,
  target: string,
  sourceHandle: string,
  targetHandle: string,
  type: string = "hydraulicEdge",
): Edge {
  return { id, source, target, sourceHandle, targetHandle, type };
}

function pumpComponent(): ComponentDefinition {
  return {
    id: "Pump",
    label: "Pump",
    category: "Hydraulic",
    description: "Test fixture pump",
    ports: [
      { name: "port_in", type: "FlowPort", side: "left" } as Port,
      { name: "port_out", type: "FlowPort", side: "right" } as Port,
    ],
    parameters: [],
    constructorModes: [],
  };
}

function cacComponent(): ComponentDefinition {
  return {
    id: "ChannelAndContacts",
    label: "ChannelAndContacts",
    category: "Hydraulic",
    description: "Test fixture CAC",
    ports: [
      { name: "port_in", type: "FlowPort", side: "left" } as Port,
      { name: "port_out", type: "FlowPort", side: "right" } as Port,
      {
        name: "thermal_left",
        type: "ThermalPort",
        array_size: "n",
        default_axis: "vertical",
        pair_with: "thermal_right",
      } as Port,
      {
        name: "thermal_right",
        type: "ThermalPort",
        array_size: "n",
        default_axis: "vertical",
        pair_with: "thermal_left",
      } as Port,
    ],
    parameters: [],
    constructorModes: [],
  };
}

function hdComponent(): ComponentDefinition {
  return {
    id: "HeatDiffusion",
    label: "HeatDiffusion",
    category: "Thermal",
    description: "Test fixture HD",
    ports: [
      {
        name: "thermal_left",
        type: "ThermalPort",
        array_size: "nz",
        default_axis: "horizontal",
        pair_with: "thermal_right",
      } as Port,
      {
        name: "thermal_right",
        type: "ThermalPort",
        array_size: "nz",
        default_axis: "horizontal",
        pair_with: "thermal_left",
      } as Port,
    ],
    parameters: [],
    constructorModes: [],
  };
}

function makeGetComponent(
  map: Record<string, ComponentDefinition>,
): (id: string) => ComponentDefinition | undefined {
  return (id: string) => map[id];
}

// ---------------------------------------------------------------------------
// resolveFlowPortSide
// ---------------------------------------------------------------------------

describe("resolveFlowPortSide", () => {
  const getComp = makeGetComponent({ Pump: pumpComponent() });

  it("D-11: returns registry default when port has no connected edges", () => {
    const nodes = [makeNode("p1", 0, 0, "Pump")];
    const edges: Edge[] = [];
    expect(
      resolveFlowPortSide(nodes, edges, "p1", "port_in", "left", getComp),
    ).toBe("left");
  });

  it("D-13/D-16: neighbor directly to the right resolves to 'right' (port_out side)", () => {
    const nodes = [
      makeNode("p1", 0, 0, "Pump"),
      makeNode("p2", 200, 0, "Pump"),
    ];
    const edges = [makeEdge("e1", "p1", "p2", "port_out", "port_in")];
    // p1.port_out should face 'right' toward p2.
    expect(
      resolveFlowPortSide(nodes, edges, "p1", "port_out", "right", getComp),
    ).toBe("right");
    // p2.port_in should face 'left' toward p1.
    expect(
      resolveFlowPortSide(nodes, edges, "p2", "port_in", "left", getComp),
    ).toBe("left");
  });

  it("D-13/D-16: neighbor directly below resolves to 'bottom'", () => {
    const nodes = [
      makeNode("p1", 0, 0, "Pump"),
      makeNode("p2", 0, 200, "Pump"),
    ];
    const edges = [makeEdge("e1", "p1", "p2", "port_out", "port_in")];
    expect(
      resolveFlowPortSide(nodes, edges, "p1", "port_out", "right", getComp),
    ).toBe("bottom");
  });

  it("D-13 tie-break: |dx| == |dy| with positive dx resolves horizontal (right)", () => {
    const nodes = [
      makeNode("p1", 0, 0, "Pump"),
      makeNode("p2", 100, 100, "Pump"),
    ];
    const edges = [makeEdge("e1", "p1", "p2", "port_out", "port_in")];
    expect(
      resolveFlowPortSide(nodes, edges, "p1", "port_out", "right", getComp),
    ).toBe("right");
  });

  it("D-13 tie-break: |dx| == |dy| with negative dx resolves horizontal (left)", () => {
    const nodes = [
      makeNode("p1", 0, 0, "Pump"),
      makeNode("p2", -100, 100, "Pump"),
    ];
    const edges = [makeEdge("e1", "p1", "p2", "port_out", "port_in")];
    expect(
      resolveFlowPortSide(nodes, edges, "p1", "port_out", "right", getComp),
    ).toBe("left");
  });

  it("D-14: strict comparison — single-pixel asymmetry flips axis at 45°", () => {
    // |dx| = 100, |dy| = 101 → |dx| < |dy| → vertical
    const nodes = [
      makeNode("p1", 0, 0, "Pump"),
      makeNode("p2", 100, 101, "Pump"),
    ];
    const edges = [makeEdge("e1", "p1", "p2", "port_out", "port_in")];
    expect(
      resolveFlowPortSide(nodes, edges, "p1", "port_out", "right", getComp),
    ).toBe("bottom");
    // |dx| = 101, |dy| = 100 → horizontal
    const nodes2 = [
      makeNode("p1", 0, 0, "Pump"),
      makeNode("p2", 101, 100, "Pump"),
    ];
    const edges2 = [makeEdge("e1", "p1", "p2", "port_out", "port_in")];
    expect(
      resolveFlowPortSide(nodes2, edges2, "p1", "port_out", "right", getComp),
    ).toBe("right");
  });

  it("targetHandle filter: port_in only inspects edges targeting that port", () => {
    // port_out has an edge to a neighbor on the right; port_in has no edge.
    // Resolving port_in must NOT pick up the port_out edge.
    const nodes = [
      makeNode("p1", 0, 0, "Pump"),
      makeNode("p2", 200, 0, "Pump"),
    ];
    const edges = [makeEdge("e1", "p1", "p2", "port_out", "port_in")];
    expect(
      resolveFlowPortSide(nodes, edges, "p1", "port_in", "left", getComp),
    ).toBe("left"); // default — no edge actually wired to port_in.
  });
});

// ---------------------------------------------------------------------------
// resolveFlowPortAssignment — "one port per side" rule
// ---------------------------------------------------------------------------

describe("resolveFlowPortAssignment", () => {
  const getComp = makeGetComponent({ Pump: pumpComponent() });

  it("no collision: opposite-side neighbors keep their preferred sides", () => {
    const nodes = [
      makeNode("p1", 0, 0, "Pump"),
      makeNode("p2", -200, 0, "Pump"), // p1.port_in ← p2 on the left
      makeNode("p3", 200, 0, "Pump"), // p1.port_out → p3 on the right
    ];
    const edges = [
      makeEdge("e1", "p2", "p1", "port_out", "port_in"),
      makeEdge("e2", "p1", "p3", "port_out", "port_in"),
    ];
    expect(resolveFlowPortAssignment(nodes, edges, "p1", getComp)).toEqual({
      port_in: "left",
      port_out: "right",
    });
  });

  // Phase 72 — same-side collisions displace to the OPPOSITE side (not
  // perpendicular). Tiebreaker order: more connections wins; otherwise port_out
  // wins. Perpendicular preferences are kept as-is. Two ports never end up on
  // the same side of a node.

  it("collision (same dominant side, both 1 connection): port_out keeps preferred, port_in moves to opposite", () => {
    // port_in's neighbor is upper-right, port_out's is lower-right. Both
    // prefer right. Tied connection count → port_out wins by tiebreak →
    // port_in displaces to LEFT (opposite of right).
    const nodes = [
      makeNode("p1", 0, 0, "Pump"),
      makeNode("p2", 300, -50, "Pump"),
      makeNode("p3", 300, 50, "Pump"),
    ];
    const edges = [
      makeEdge("e1", "p2", "p1", "port_out", "port_in"),
      makeEdge("e2", "p1", "p3", "port_out", "port_in"),
    ];
    expect(resolveFlowPortAssignment(nodes, edges, "p1", getComp)).toEqual({
      port_in: "left",
      port_out: "right",
    });
  });

  it("pump with multiple consumers below + return from below: port_out=bottom, port_in=top", () => {
    // The canonical vertical-loop topology that motivated the Phase 72 fix:
    // pump on top, two consumers directly below feeding port_out (2 edges),
    // and one return into port_in (1 edge). port_out has more connections so
    // it wins the collision and keeps bottom; port_in displaces to TOP
    // (opposite). The return edge then wraps around the system.
    const nodes = [
      makeNode("p1", 0, 0, "Pump"),
      makeNode("c1", -100, 200, "Pump"),
      makeNode("c2", 100, 200, "Pump"),
      makeNode("c3", 0, 300, "Pump"), // returns into p1.port_in
    ];
    const edges = [
      makeEdge("e1", "p1", "c1", "port_out", "port_in"),
      makeEdge("e2", "p1", "c2", "port_out", "port_in"),
      makeEdge("e3", "c3", "p1", "port_out", "port_in"),
    ];
    const out = resolveFlowPortAssignment(nodes, edges, "p1", getComp);
    expect(out.port_out).toBe("bottom");
    expect(out.port_in).toBe("top");
  });

  it("unconnected port that defaults to the same side as a connected sibling displaces to opposite", () => {
    // Only port_in is wired; port_out has no edge → port_out falls back to its
    // registry default 'right'. port_in's neighbor is to the right → port_in
    // also wants 'right'. Collision. port_in has more connections (1 vs 0) →
    // port_in keeps 'right'; port_out displaces to LEFT (opposite).
    const nodes = [
      makeNode("p1", 0, 0, "Pump"),
      makeNode("p2", 200, 0, "Pump"),
    ];
    const edges = [makeEdge("e1", "p2", "p1", "port_out", "port_in")];
    const out = resolveFlowPortAssignment(nodes, edges, "p1", getComp);
    expect(out.port_in).toBe("right");
    expect(out.port_out).toBe("left");
  });

  // -------------------------------------------------------------------------
  // Phase 72 — convention-driven layout regressions.
  // -------------------------------------------------------------------------

  it("vertical 2-node loop: both nodes get port_in=top, port_out=bottom (convention)", () => {
    // imp_edge_bug.png scenario. Two nodes stacked vertically with two edges
    // between them forming a loop. Cluster bbox is tall → vertical axis.
    // Both nodes end up with the canonical port_in=top, port_out=bottom.
    const nodes = [
      makeNode("a", 0, 0, "Pump"),
      makeNode("b", 0, 300, "Pump"),
    ];
    const edges = [
      makeEdge("e1", "a", "b", "port_out", "port_in"),
      makeEdge("e2", "b", "a", "port_out", "port_in"),
    ];
    expect(resolveFlowPortAssignment(nodes, edges, "a", getComp)).toEqual({
      port_in: "top",
      port_out: "bottom",
    });
    expect(resolveFlowPortAssignment(nodes, edges, "b", getComp)).toEqual({
      port_in: "top",
      port_out: "bottom",
    });
  });

  it("off-axis neighbor pulls snap to natural side in vertical flow", () => {
    // imp_edge_bug2.png scenario. The cluster is vertical (height > width),
    // but one node's downstream consumer is off to the right (|dx| slightly
    // greater than |dy|). Local geometry would pick port_out=right, but the
    // axis-snap rule moves it to bottom (natural for port_out in vertical).
    const nodes = [
      makeNode("pump1", 500, 0, "Pump"),
      makeNode("a", 300, 400, "Pump"),    // middle-left — the node under test
      makeNode("b", 700, 400, "Pump"),    // middle-right
      makeNode("c", 800, 800, "Pump"),    // bottom-right
    ];
    const edges = [
      makeEdge("e1", "pump1", "a", "port_out", "port_in"),
      makeEdge("e2", "pump1", "b", "port_out", "port_in"),
      makeEdge("e3", "a", "c", "port_out", "port_in"), // a → c (right-and-down)
      makeEdge("e4", "b", "c", "port_out", "port_in"),
      makeEdge("e5", "c", "pump1", "port_out", "port_in"), // return
    ];
    // For 'a': port_in's neighbor is pump1 (above), local = top. port_out's
    // neighbor is c (right-and-down), local = right (|dx|=500 > |dy|=400).
    // Vertical axis → right snaps to bottom. No collision after snap.
    expect(resolveFlowPortAssignment(nodes, edges, "a", getComp)).toEqual({
      port_in: "top",
      port_out: "bottom",
    });
  });

  it("zero FlowPorts (HeatDiffusion-only component): returns empty assignment", () => {
    const hdGetComp = makeGetComponent({ HeatDiffusion: hdComponent() });
    const nodes = [makeNode("h1", 0, 0, "HeatDiffusion")];
    const edges: Edge[] = [];
    expect(resolveFlowPortAssignment(nodes, edges, "h1", hdGetComp)).toEqual(
      {},
    );
  });

  it("missing node or component: returns empty assignment", () => {
    const nodes = [makeNode("p1", 0, 0, "Pump")];
    expect(resolveFlowPortAssignment(nodes, [], "nope", getComp)).toEqual({});
  });
});

// ---------------------------------------------------------------------------
// resolveThermalPairSides
// ---------------------------------------------------------------------------

describe("resolveThermalPairSides", () => {
  const getComp = makeGetComponent({
    ChannelAndContacts: cacComponent(),
    HeatDiffusion: hdComponent(),
  });

  it("D-11: zero thermal edges + default_axis='vertical' -> thermal_left=top, thermal_right=bottom (D-18)", () => {
    const nodes = [makeNode("c1", 0, 0, "ChannelAndContacts")];
    const edges: Edge[] = [];
    const res = resolveThermalPairSides(
      nodes,
      edges,
      "c1",
      "thermal_left",
      "thermal_right",
      "vertical",
      getComp,
    );
    expect(res).toEqual({ thisSide: "top", pairSide: "bottom" });
  });

  it("D-11: zero thermal edges + default_axis='horizontal' -> thermal_left=left, thermal_right=right", () => {
    const nodes = [makeNode("h1", 0, 0, "HeatDiffusion")];
    const edges: Edge[] = [];
    const res = resolveThermalPairSides(
      nodes,
      edges,
      "h1",
      "thermal_left",
      "thermal_right",
      "horizontal",
      getComp,
    );
    expect(res).toEqual({ thisSide: "left", pairSide: "right" });
  });

  it("D-18: aggregated |dy| > |dx| -> vertical axis; suffix-locked thermal_left=top", () => {
    // CAC with two thermal neighbors directly above and below.
    const nodes = [
      makeNode("c1", 0, 0, "ChannelAndContacts"),
      makeNode("hd1", 0, -300, "HeatDiffusion"),
      makeNode("hd2", 0, 300, "HeatDiffusion"),
    ];
    const edges = [
      // both edges are thermal-typed (not hydraulicEdge); type doesn't matter
      // for thermal-pair aggregation — the handle-name filter does.
      makeEdge("t1", "c1", "hd1", "thermal_left", "thermal_right", "default"),
      makeEdge("t2", "c1", "hd2", "thermal_right", "thermal_left", "default"),
    ];
    const res = resolveThermalPairSides(
      nodes,
      edges,
      "c1",
      "thermal_left",
      "thermal_right",
      "horizontal",
      getComp,
    );
    expect(res.thisSide).toBe("top");
    expect(res.pairSide).toBe("bottom");
  });

  it("D-18: aggregated |dx| > |dy| -> horizontal axis; suffix-locked thermal_left=left", () => {
    const nodes = [
      makeNode("c1", 0, 0, "ChannelAndContacts"),
      makeNode("hd1", -300, 0, "HeatDiffusion"),
      makeNode("hd2", 300, 0, "HeatDiffusion"),
    ];
    const edges = [
      makeEdge("t1", "c1", "hd1", "thermal_left", "thermal_right", "default"),
      makeEdge("t2", "c1", "hd2", "thermal_right", "thermal_left", "default"),
    ];
    const res = resolveThermalPairSides(
      nodes,
      edges,
      "c1",
      "thermal_left",
      "thermal_right",
      "vertical",
      getComp,
    );
    expect(res.thisSide).toBe("left");
    expect(res.pairSide).toBe("right");
  });

  it("D-13 tie-break: aggregated |dx| == |dy| prefers horizontal axis", () => {
    const nodes = [
      makeNode("c1", 0, 0, "ChannelAndContacts"),
      makeNode("hd1", 100, 100, "HeatDiffusion"),
    ];
    const edges = [
      makeEdge("t1", "c1", "hd1", "thermal_left", "thermal_right", "default"),
    ];
    const res = resolveThermalPairSides(
      nodes,
      edges,
      "c1",
      "thermal_left",
      "thermal_right",
      "vertical",
      getComp,
    );
    // |dx| == |dy| -> horizontal axis -> thermal_left maps to 'left'.
    expect(res.thisSide).toBe("left");
    expect(res.pairSide).toBe("right");
  });
});

// ---------------------------------------------------------------------------
// detectAxisCollision
// ---------------------------------------------------------------------------

describe("detectAxisCollision", () => {
  const getComp = makeGetComponent({
    ChannelAndContacts: cacComponent(),
    HeatDiffusion: hdComponent(),
    Pump: pumpComponent(),
  });

  it("Phase 73 v2: CAC w/ flow horizontal + thermal neighbor right — both on horizontal axis (collision = true, handled visually by offset)", () => {
    // Phase 73 v2 — thermal pair uses neighbor projection, lands horizontal
    // when neighbor is horizontal. Same axis as flow → `detectAxisCollision`
    // returns true. The visual collision is resolved by `computePortOffset`
    // on the StreamNode side, not by relocating the thermal pair.
    const nodes = [
      makeNode("c1", 0, 0, "ChannelAndContacts"),
      makeNode("p1", -300, 0, "Pump"),
      makeNode("hd1", 300, 0, "HeatDiffusion"),
    ];
    const edges = [
      makeEdge("e1", "p1", "c1", "port_out", "port_in", "hydraulicEdge"),
      makeEdge(
        "t1",
        "c1",
        "hd1",
        "thermal_right",
        "thermal_left",
        "default",
      ),
    ];
    expect(detectAxisCollision(nodes, edges, "c1", getComp)).toBe(true);
  });

  it("D-15: CAC with FlowPort horizontal but thermal pair vertical returns false", () => {
    const nodes = [
      makeNode("c1", 0, 0, "ChannelAndContacts"),
      makeNode("p1", -300, 0, "Pump"),
      makeNode("hd1", 0, 300, "HeatDiffusion"),
    ];
    const edges = [
      makeEdge("e1", "p1", "c1", "port_out", "port_in", "hydraulicEdge"),
      makeEdge(
        "t1",
        "c1",
        "hd1",
        "thermal_right",
        "thermal_left",
        "default",
      ),
    ];
    expect(detectAxisCollision(nodes, edges, "c1", getComp)).toBe(false);
  });

  it("D-15: Pump (no thermal pair) returns false", () => {
    const nodes = [
      makeNode("p1", 0, 0, "Pump"),
      makeNode("p2", 300, 0, "Pump"),
    ];
    const edges = [
      makeEdge("e1", "p1", "p2", "port_out", "port_in", "hydraulicEdge"),
    ];
    expect(detectAxisCollision(nodes, edges, "p1", getComp)).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Phase 73 — getFlowAxis
// ---------------------------------------------------------------------------

describe("getFlowAxis", () => {
  const getComp = makeGetComponent({
    Pump: pumpComponent(),
    HeatDiffusion: hdComponent(),
  });

  it("returns null for a component with no FlowPorts", () => {
    const nodes = [makeNode("h1", 0, 0, "HeatDiffusion")];
    const edges: Edge[] = [];
    expect(getFlowAxis(nodes, edges, "h1", getComp)).toBeNull();
  });

  it("returns 'horizontal' when flow ports resolve to left/right", () => {
    const nodes = [
      makeNode("p1", 0, 0, "Pump"),
      makeNode("p2", 300, 0, "Pump"),
    ];
    const edges = [makeEdge("e1", "p1", "p2", "port_out", "port_in")];
    expect(getFlowAxis(nodes, edges, "p1", getComp)).toBe("horizontal");
  });

  it("returns 'vertical' for a vertical 2-node loop (convention-driven natural sides)", () => {
    // Mirrors the vertical-loop test in resolveFlowPortAssignment — both nodes
    // resolve port_in=top, port_out=bottom. Axis = vertical.
    const nodes = [
      makeNode("a", 0, 0, "Pump"),
      makeNode("b", 0, 300, "Pump"),
    ];
    const edges = [
      makeEdge("e1", "a", "b", "port_out", "port_in"),
      makeEdge("e2", "b", "a", "port_out", "port_in"),
    ];
    expect(getFlowAxis(nodes, edges, "a", getComp)).toBe("vertical");
  });
});

// ---------------------------------------------------------------------------
// Phase 73 v2 — resolveBCPortSide (neighbor projection, no occupied-avoidance)
// ---------------------------------------------------------------------------

describe("resolveBCPortSide", () => {
  const getComp = makeGetComponent({ Pump: pumpComponent() });

  it("returns the registry default when no BC edge is connected", () => {
    const nodes = [makeNode("c1", 0, 0, "Pump")];
    const edges: Edge[] = [];
    const result = resolveBCPortSide(
      nodes,
      edges,
      "c1",
      { name: "T_wall_left", side: "bottom" },
      getComp,
    );
    expect(result).toBe("bottom");
  });

  it("connected BC source directly above → resolves to 'top' (closest to neighbor)", () => {
    const nodes = [
      makeNode("c1", 0, 0, "Pump"),
      makeNode("wt1", 0, -300, "Pump"),
    ];
    const edges = [
      makeEdge("bc1", "wt1", "c1", "T_wall_out", "T_wall_left", "bcEdge"),
    ];
    const result = resolveBCPortSide(
      nodes,
      edges,
      "c1",
      { name: "T_wall_left", side: "bottom" },
      getComp,
    );
    expect(result).toBe("top");
  });

  it("connected BC source to the right → resolves to 'right'", () => {
    const nodes = [
      makeNode("c1", 0, 0, "Pump"),
      makeNode("wt1", 300, 0, "Pump"),
    ];
    const edges = [
      makeEdge("bc1", "wt1", "c1", "T_wall_out", "T_wall_left", "bcEdge"),
    ];
    const result = resolveBCPortSide(
      nodes,
      edges,
      "c1",
      { name: "T_wall_left", side: "bottom" },
      getComp,
    );
    expect(result).toBe("right");
  });

  it("WallTemperature source-side: BC port routes toward its consumer's direction", () => {
    // WT at (0,0) with T_wall_out, Channel at (300, 0). Neighbor is right.
    const nodes = [
      makeNode("wt1", 0, 0, "Pump"),
      makeNode("c1", 300, 0, "Pump"),
    ];
    const edges = [
      makeEdge("bc1", "wt1", "c1", "T_wall_out", "T_wall_left", "bcEdge"),
    ];
    const result = resolveBCPortSide(
      nodes,
      edges,
      "wt1",
      { name: "T_wall_out", side: "right" },
      getComp,
    );
    expect(result).toBe("right");
  });
});

// ---------------------------------------------------------------------------
// Phase 73 v2 — computePortOffset (along-edge offset when colliding w/ flow)
// ---------------------------------------------------------------------------

describe("computePortOffset", () => {
  it("returns null when the side has no flow port (no collision)", () => {
    expect(
      computePortOffset("T_wall_left", "top", new Set<Side>(["left", "right"])),
    ).toBeNull();
  });

  it("`_left` suffix on a left/right edge offsets via top: 25%", () => {
    const off = computePortOffset(
      "thermal_left",
      "left",
      new Set<Side>(["left"]),
    );
    expect(off).toEqual({ top: "25%" });
  });

  it("`_right` suffix on a left/right edge offsets via top: 75% (suffix-based, no options)", () => {
    const off = computePortOffset(
      "thermal_right",
      "right",
      new Set<Side>(["right"]),
    );
    expect(off).toEqual({ top: "75%" });
  });

  it("uniformOffset option overrides suffix-based — both pair members land at the same %", () => {
    // Thermal pair calls pass `uniformOffset: "25%"` so thermal_left and
    // thermal_right read as a coherent shelf across opposite edges instead
    // of a zigzag (25% on one edge, 75% on the other).
    const left = computePortOffset(
      "thermal_left",
      "left",
      new Set<Side>(["left"]),
      { uniformOffset: "25%" },
    );
    const right = computePortOffset(
      "thermal_right",
      "right",
      new Set<Side>(["right"]),
      { uniformOffset: "25%" },
    );
    expect(left).toEqual({ top: "25%" });
    expect(right).toEqual({ top: "25%" });
  });

  it("`_left` suffix on a top/bottom edge offsets via left: 25%", () => {
    const off = computePortOffset(
      "T_wall_left",
      "bottom",
      new Set<Side>(["bottom"]),
    );
    expect(off).toEqual({ left: "25%" });
  });

  it("`_right` suffix on a top/bottom edge offsets via left: 75%", () => {
    const off = computePortOffset(
      "q_right",
      "top",
      new Set<Side>(["top"]),
    );
    expect(off).toEqual({ left: "75%" });
  });

  it("no `_left/_right` suffix → defaults to 75% so the mark sits clear of flow's centered position", () => {
    const off = computePortOffset(
      "T_wall_out",
      "bottom",
      new Set<Side>(["bottom"]),
    );
    expect(off).toEqual({ left: "75%" });
  });
});
