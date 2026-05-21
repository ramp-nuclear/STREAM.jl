// zNMatch.test.ts — Unit tests for the zNMatch validator (Phase 71, Plan 05)
//
// D-15 rule 1: "z_N match" — when CAC.n != HD.nz on a thermal coupling.
// §3.9 line 790: error severity; lossless-sync fix.
//
// Test cases:
//   1. CAC (n=4) thermally connected to HD (nz=4) → no result (matching)
//   2. CAC (n=4) thermally connected to HD (nz=5) → 1 error result, lossless-sync
//   3. Multiple thermal edges for the same CAC↔HD pair → 1 result (deduped)
//   4. CAC connected to a non-HD component (no nz param) → no result
//   5. No thermal edges → no result
//   6. fixAction.apply calls updateNodeParam with correct args on both sides

import { describe, it, expect } from "vitest";
import type { Node, Edge } from "@xyflow/react";
import type { ValidationSnapshot } from "../../snapshot";
import type { ComponentDefinition } from "../../../../registry/types";

import { zNMatch } from "../zNMatch";

// ---------------------------------------------------------------------------
// Node factory
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
    data: { componentId, instanceName, parameters },
  };
}

// ---------------------------------------------------------------------------
// Edge factory
// ---------------------------------------------------------------------------

function makeEdge(
  id: string,
  source: string,
  sourceHandle: string,
  target: string,
  targetHandle: string,
): Edge {
  return { id, source, sourceHandle, target, targetHandle };
}

// ---------------------------------------------------------------------------
// Component definition fixtures
// ---------------------------------------------------------------------------

const CAC_DEF: ComponentDefinition = {
  id: "ChannelAndContacts",
  label: "Channel and Contacts",
  category: "Hydraulic",
  description: "CAC",
  ports: [
    { name: "port_in", type: "FlowPort", side: "left" },
    { name: "port_out", type: "FlowPort", side: "right" },
    { name: "thermal_left", type: "ThermalPort", side: "bottom" },
    { name: "thermal_right", type: "ThermalPort", side: "bottom" },
  ],
  parameters: [
    { name: "n", type: "Int", default: 4, required: true, positional: false },
    { name: "geometry", type: "PipeGeometry", default: "", required: true, positional: false },
  ],
  constructorModes: [],
};

const HD_DEF: ComponentDefinition = {
  id: "HeatDiffusion",
  label: "Heat Diffusion",
  category: "Thermal",
  description: "HD",
  ports: [
    { name: "thermal_left", type: "ThermalPort", side: "left" },
    { name: "thermal_right", type: "ThermalPort", side: "right" },
  ],
  parameters: [
    { name: "nz", type: "Int", default: 5, required: true, positional: false },
    { name: "nx", type: "Int", default: 3, required: true, positional: false },
    { name: "Lz", type: "Real", default: 0.5, required: true, positional: false },
  ],
  constructorModes: [],
};

const RESISTOR_DEF: ComponentDefinition = {
  id: "Resistor",
  label: "Resistor",
  category: "Hydraulic",
  description: "Resistor",
  ports: [
    { name: "port_in", type: "FlowPort", side: "left" },
    { name: "port_out", type: "FlowPort", side: "right" },
    { name: "thermal_left", type: "ThermalPort", side: "bottom" },
  ],
  parameters: [],
  constructorModes: [],
};

const DEFS: Record<string, ComponentDefinition> = {
  ChannelAndContacts: CAC_DEF,
  HeatDiffusion: HD_DEF,
  Resistor: RESISTOR_DEF,
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

describe("zNMatch", () => {
  it("returns no result when CAC.n matches HD.nz (both 4)", () => {
    const cac = makeNode("cac1", "ChannelAndContacts", "cac_1", { n: 4 });
    const hd = makeNode("hd1", "HeatDiffusion", "hd_1", { nz: 4 });
    const edge = makeEdge("e1", "cac1", "thermal_right", "hd1", "thermal_left");
    const snapshot = makeSnapshot([cac, hd], [edge]);
    const results = zNMatch.run(snapshot);
    expect(results).toHaveLength(0);
  });

  it("emits one error when CAC.n=4 and HD.nz=5 are thermally connected", () => {
    const cac = makeNode("cac1", "ChannelAndContacts", "cac_1", { n: 4 });
    const hd = makeNode("hd1", "HeatDiffusion", "hd_1", { nz: 5 });
    const edge = makeEdge("e1", "cac1", "thermal_right", "hd1", "thermal_left");
    const snapshot = makeSnapshot([cac, hd], [edge]);
    const results = zNMatch.run(snapshot);
    expect(results).toHaveLength(1);
    const r = results[0];
    expect(r.validatorId).toBe("z_n_match");
    expect(r.severity).toBe("error");
    // description must name both values
    expect(r.description).toContain("4");
    expect(r.description).toContain("5");
    // targets: edge + both field targets + both node targets
    const edgeTargets = r.targets.filter((t) => t.kind === "edge");
    const fieldTargets = r.targets.filter((t) => t.kind === "field");
    const nodeTargets = r.targets.filter((t) => t.kind === "node");
    expect(edgeTargets).toHaveLength(1);
    expect(fieldTargets.some((t) => t.kind === "field" && t.fieldPath === "n")).toBe(true);
    expect(fieldTargets.some((t) => t.kind === "field" && t.fieldPath === "nz")).toBe(true);
    expect(nodeTargets).toHaveLength(2);
  });

  it("deduplicates: multiple thermal edges for the same CAC↔HD pair → 1 result", () => {
    const cac = makeNode("cac1", "ChannelAndContacts", "cac_1", { n: 4 });
    const hd = makeNode("hd1", "HeatDiffusion", "hd_1", { nz: 6 });
    const edge1 = makeEdge("e1", "cac1", "thermal_right", "hd1", "thermal_left");
    const edge2 = makeEdge("e2", "cac1", "thermal_left", "hd1", "thermal_right");
    const snapshot = makeSnapshot([cac, hd], [edge1, edge2]);
    const results = zNMatch.run(snapshot);
    expect(results).toHaveLength(1);
  });

  it("returns no result when CAC is connected to a non-HD component (no nz param)", () => {
    const cac = makeNode("cac1", "ChannelAndContacts", "cac_1", { n: 4 });
    const res = makeNode("r1", "Resistor", "resistor_1", {});
    const edge = makeEdge("e1", "cac1", "thermal_left", "r1", "thermal_left");
    const snapshot = makeSnapshot([cac, res], [edge]);
    const results = zNMatch.run(snapshot);
    expect(results).toHaveLength(0);
  });

  it("returns no result when there are no thermal edges", () => {
    const cac = makeNode("cac1", "ChannelAndContacts", "cac_1", { n: 4 });
    const hd = makeNode("hd1", "HeatDiffusion", "hd_1", { nz: 5 });
    const snapshot = makeSnapshot([cac, hd], []);
    const results = zNMatch.run(snapshot);
    expect(results).toHaveLength(0);
  });

  // Phase 71 UAT (2026-05-21): FixActions removed across all rules.
  // Rule degrades to navigation-only behavior (row click focuses the node).
  it("emits no fixAction", () => {
    const cac = makeNode("cac1", "ChannelAndContacts", "cac_1", { n: 4 });
    const hd = makeNode("hd1", "HeatDiffusion", "hd_1", { nz: 5 });
    const edge = makeEdge("e1", "cac1", "thermal_right", "hd1", "thermal_left");
    const snapshot = makeSnapshot([cac, hd], [edge]);
    const results = zNMatch.run(snapshot);
    expect(results).toHaveLength(1);
    expect(results[0].fixAction).toBeUndefined();
  });
});
