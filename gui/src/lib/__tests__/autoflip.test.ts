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
  resolveAsymmetricOffset,
  resolveThermalPairSides,
  detectAxisCollision,
  findAntiParallelSibling,
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
// resolveAsymmetricOffset
// ---------------------------------------------------------------------------

describe("resolveAsymmetricOffset", () => {
  const getComp = makeGetComponent({ Pump: pumpComponent() });

  it("D-09: both ports of a Pump resolve to the same side -> 25%/75% offsets", () => {
    // Pump with both neighbors to the right -> both ports flip to 'right'.
    // 'right' is a vertical-axis edge -> offset is along `top`.
    const nodes = [
      makeNode("p1", 0, 0, "Pump"),
      makeNode("p2", 300, -50, "Pump"),
      makeNode("p3", 300, 50, "Pump"),
    ];
    const edges = [
      makeEdge("e1", "p2", "p1", "port_out", "port_in"), // p1.port_in ← p2 (to the upper-right)
      makeEdge("e2", "p1", "p3", "port_out", "port_in"), // p1.port_out → p3 (to the lower-right)
    ];
    // Both target the right half-plane; both should resolve to 'right'.
    const inOffset = resolveAsymmetricOffset(
      nodes,
      edges,
      "p1",
      "right",
      "port_in",
      "left",
      getComp,
    );
    const outOffset = resolveAsymmetricOffset(
      nodes,
      edges,
      "p1",
      "right",
      "port_out",
      "right",
      getComp,
    );
    expect(inOffset).toEqual({ top: "25%" });
    expect(outOffset).toEqual({ top: "75%" });
  });

  it("D-10: both ports share 'bottom' -> offsets keyed on `left` with 25%/75%", () => {
    // 'bottom' is a horizontal-axis edge -> offset is along `left`.
    const nodes = [
      makeNode("p1", 0, 0, "Pump"),
      makeNode("p2", -50, 300, "Pump"),
      makeNode("p3", 50, 300, "Pump"),
    ];
    const edges = [
      makeEdge("e1", "p2", "p1", "port_out", "port_in"),
      makeEdge("e2", "p1", "p3", "port_out", "port_in"),
    ];
    const inOffset = resolveAsymmetricOffset(
      nodes,
      edges,
      "p1",
      "bottom",
      "port_in",
      "left",
      getComp,
    );
    const outOffset = resolveAsymmetricOffset(
      nodes,
      edges,
      "p1",
      "bottom",
      "port_out",
      "right",
      getComp,
    );
    expect(inOffset).toEqual({ left: "25%" });
    expect(outOffset).toEqual({ left: "75%" });
  });

  it("D-09 negative: when ports resolve to different sides, returns undefined", () => {
    // Standard pump: port_in flips to 'left' (default), port_out to 'right'.
    const nodes = [
      makeNode("p1", 0, 0, "Pump"),
      makeNode("p2", -200, 0, "Pump"),
      makeNode("p3", 200, 0, "Pump"),
    ];
    const edges = [
      makeEdge("e1", "p2", "p1", "port_out", "port_in"),
      makeEdge("e2", "p1", "p3", "port_out", "port_in"),
    ];
    const inOffset = resolveAsymmetricOffset(
      nodes,
      edges,
      "p1",
      "left",
      "port_in",
      "left",
      getComp,
    );
    const outOffset = resolveAsymmetricOffset(
      nodes,
      edges,
      "p1",
      "right",
      "port_out",
      "right",
      getComp,
    );
    expect(inOffset).toBeUndefined();
    expect(outOffset).toBeUndefined();
  });

  it("D-12: never applies to thermal pairs (no FlowPort sibling -> undefined)", () => {
    // HeatDiffusion has only thermal ports — passing a thermal port name yields
    // no FlowPort sibling, so the function returns undefined.
    const hdGetComp = makeGetComponent({ HeatDiffusion: hdComponent() });
    const nodes = [makeNode("h1", 0, 0, "HeatDiffusion")];
    const edges: Edge[] = [];
    const offset = resolveAsymmetricOffset(
      nodes,
      edges,
      "h1",
      "left",
      "thermal_left",
      "left",
      hdGetComp,
    );
    expect(offset).toBeUndefined();
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

  it("D-15: CAC with FlowPort axis horizontal AND thermal pair horizontal returns true", () => {
    // CAC at origin, hydraulic neighbor on the left, thermal neighbor on the right.
    // Both axes resolve to horizontal -> collision.
    const nodes = [
      makeNode("c1", 0, 0, "ChannelAndContacts"),
      makeNode("p1", -300, 0, "Pump"), // hydraulic neighbor (direct left)
      makeNode("hd1", 300, 0, "HeatDiffusion"), // thermal neighbor (direct right)
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
// findAntiParallelSibling
// ---------------------------------------------------------------------------

describe("findAntiParallelSibling", () => {
  it("D-08: A→B and B→A both hydraulicEdge -> returns the sibling", () => {
    const a = makeEdge("e1", "A", "B", "port_out", "port_in", "hydraulicEdge");
    const b = makeEdge("e2", "B", "A", "port_out", "port_in", "hydraulicEdge");
    const sibling = findAntiParallelSibling(a, [a, b]);
    expect(sibling?.id).toBe("e2");
  });

  it("D-17: A→B hydraulicEdge and B→A bcEdge -> no sibling (same-type-only)", () => {
    const a = makeEdge("e1", "A", "B", "port_out", "port_in", "hydraulicEdge");
    const b = makeEdge(
      "e2",
      "B",
      "A",
      "T_wall_out",
      "T_wall_left",
      "bcEdge",
    );
    expect(findAntiParallelSibling(a, [a, b])).toBeUndefined();
  });

  it("D-17: A→B hydraulicEdge and an unrelated thermal-styled edge between same nodes -> undefined", () => {
    const a = makeEdge("e1", "A", "B", "port_out", "port_in", "hydraulicEdge");
    // Thermal edges in the codebase don't carry type='hydraulicEdge'; they
    // are styled inline via stroke color. Use a generic non-hydraulic type.
    const thermal = makeEdge(
      "e2",
      "B",
      "A",
      "thermal_left",
      "thermal_right",
      "default",
    );
    expect(findAntiParallelSibling(a, [a, thermal])).toBeUndefined();
  });
});
