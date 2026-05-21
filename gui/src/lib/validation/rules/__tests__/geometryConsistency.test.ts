// geometryConsistency.test.ts — Unit tests for geometryConsistency validator
// (Phase 71, Plan 05)
//
// D-15 rule 9: geometry consistency across shared coupling.
// When two CACs share one HD plate (each connected via a thermal port),
// their geometry resources must agree on cross-section fields (Dh = L/n, Wz).
// Planner discretion: navigation-only (no mechanical fix) — see behavior block.
//
// Test cases:
//   1. Two CACs with same geometry UUID → no result (trivially consistent)
//   2. Two CACs with different UUIDs but same Dh/L/W → no result (values match)
//   3. Two CACs with Dh mismatch → 1 warning result, navigation-only
//   4. Single CAC on an HD → no result (rule only fires for 2+ CACs)
//   5. No thermal edges → no result
//   6. fixAction is navigation-only with label 'Go to components' and no apply

import { describe, it, expect } from "vitest";
import type { Node, Edge } from "@xyflow/react";
import type { ValidationSnapshot } from "../../snapshot";
import type { ComponentDefinition } from "../../../../registry/types";

import { geometryConsistency } from "../geometryConsistency";

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
    { name: "nz", type: "Int", default: 4, required: true, positional: false },
    { name: "Lz", type: "Real", default: 0.5, required: true, positional: false },
  ],
  constructorModes: [],
};

const DEFS: Record<string, ComponentDefinition> = {
  ChannelAndContacts: CAC_DEF,
  HeatDiffusion: HD_DEF,
};

// ---------------------------------------------------------------------------
// Geometry resource fixtures
// ---------------------------------------------------------------------------

const GEOM_UUID_1 = "uuid-geom-1";
const GEOM_UUID_2 = "uuid-geom-2";

const GEOM_1_MATCHING = {
  uuid: GEOM_UUID_1,
  name: "geometry_1",
  kind: "rectangular" as const,
  params: { L: 0.5, W: 0.1, H: 0.01 },
};

const GEOM_2_MATCHING = {
  uuid: GEOM_UUID_2,
  name: "geometry_2",
  kind: "rectangular" as const,
  params: { L: 0.5, W: 0.1, H: 0.01 },
};

const GEOM_2_MISMATCHING = {
  uuid: GEOM_UUID_2,
  name: "geometry_2",
  kind: "rectangular" as const,
  params: { L: 0.5, W: 0.1, H: 0.02 }, // H differs
};

// ---------------------------------------------------------------------------
// Snapshot factory
// ---------------------------------------------------------------------------

function makeSnapshot(
  nodes: Node[],
  edges: Edge[],
  geometries: Record<string, typeof GEOM_1_MATCHING> = {},
): ValidationSnapshot {
  return {
    nodes,
    edges,
    anchors: {},
    bcMode: {},
    resources: {
      geometries: geometries as ValidationSnapshot["resources"]["geometries"],
      powerShapes: {},
      fluids: {},
    },
    getComponentDef: (id: string) => DEFS[id],
  };
}

// ---------------------------------------------------------------------------
// Helper: build the two-CAC + one-HD topology
// ---------------------------------------------------------------------------

function makeTwoCacTopology(
  geom1: typeof GEOM_1_MATCHING,
  geom2: typeof GEOM_1_MATCHING,
) {
  const cac1 = makeNode("cac1", "ChannelAndContacts", "cac_1", {
    n: 4,
    geometry: geom1.uuid,
  });
  const cac2 = makeNode("cac2", "ChannelAndContacts", "cac_2", {
    n: 4,
    geometry: geom2.uuid,
  });
  const hd = makeNode("hd1", "HeatDiffusion", "hd_1", { nz: 4, Lz: 0.5 });

  // CAC1.thermal_right → HD.thermal_left
  const edge1 = makeEdge("e1", "cac1", "thermal_right", "hd1", "thermal_left");
  // CAC2.thermal_left → HD.thermal_right
  const edge2 = makeEdge("e2", "cac2", "thermal_left", "hd1", "thermal_right");

  const geometries = {
    [geom1.uuid]: geom1,
    [geom2.uuid]: geom2,
  };

  return makeSnapshot([cac1, cac2, hd], [edge1, edge2], geometries);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("geometryConsistency", () => {
  it("returns no result when two CACs share the same geometry UUID", () => {
    // Both CACs point to the same resource — trivially consistent.
    const cac1 = makeNode("cac1", "ChannelAndContacts", "cac_1", {
      n: 4,
      geometry: GEOM_UUID_1,
    });
    const cac2 = makeNode("cac2", "ChannelAndContacts", "cac_2", {
      n: 4,
      geometry: GEOM_UUID_1, // same UUID
    });
    const hd = makeNode("hd1", "HeatDiffusion", "hd_1", { nz: 4, Lz: 0.5 });
    const edge1 = makeEdge("e1", "cac1", "thermal_right", "hd1", "thermal_left");
    const edge2 = makeEdge("e2", "cac2", "thermal_left", "hd1", "thermal_right");
    const snapshot = makeSnapshot(
      [cac1, cac2, hd],
      [edge1, edge2],
      { [GEOM_UUID_1]: GEOM_1_MATCHING },
    );
    const results = geometryConsistency.run(snapshot);
    expect(results).toHaveLength(0);
  });

  it("returns no result when two CACs have different UUIDs but identical geometry values", () => {
    const snapshot = makeTwoCacTopology(GEOM_1_MATCHING, GEOM_2_MATCHING);
    const results = geometryConsistency.run(snapshot);
    expect(results).toHaveLength(0);
  });

  it("emits one warning when two CACs on the same HD have mismatching geometry (H differs)", () => {
    const snapshot = makeTwoCacTopology(GEOM_1_MATCHING, GEOM_2_MISMATCHING);
    const results = geometryConsistency.run(snapshot);
    expect(results).toHaveLength(1);
    const r = results[0];
    expect(r.validatorId).toBe("geometry_consistency");
    expect(r.severity).toBe("warning");
    // Targets: both CAC field targets (fieldPath:'geometry'), both CAC node targets, HD node target
    const fieldTargets = r.targets.filter((t) => t.kind === "field");
    const nodeTargets = r.targets.filter((t) => t.kind === "node");
    expect(fieldTargets.every((t) => t.kind === "field" && t.fieldPath === "geometry")).toBe(true);
    expect(fieldTargets.length).toBeGreaterThanOrEqual(2);
    // Both CACs + HD
    expect(nodeTargets.length).toBeGreaterThanOrEqual(3);
    // Phase 71 UAT (2026-05-21): FixActions removed across all rules.
    expect(r.fixAction).toBeUndefined();
  });

  it("returns no result for a single CAC connected to an HD (no shared coupling)", () => {
    const cac = makeNode("cac1", "ChannelAndContacts", "cac_1", {
      n: 4,
      geometry: GEOM_UUID_1,
    });
    const hd = makeNode("hd1", "HeatDiffusion", "hd_1", { nz: 4, Lz: 0.5 });
    const edge = makeEdge("e1", "cac1", "thermal_right", "hd1", "thermal_left");
    const snapshot = makeSnapshot(
      [cac, hd],
      [edge],
      { [GEOM_UUID_1]: GEOM_1_MATCHING },
    );
    const results = geometryConsistency.run(snapshot);
    expect(results).toHaveLength(0);
  });

  it("returns no result when there are no thermal edges", () => {
    const cac1 = makeNode("cac1", "ChannelAndContacts", "cac_1", {
      n: 4,
      geometry: GEOM_UUID_1,
    });
    const cac2 = makeNode("cac2", "ChannelAndContacts", "cac_2", {
      n: 4,
      geometry: GEOM_UUID_2,
    });
    const hd = makeNode("hd1", "HeatDiffusion", "hd_1", { nz: 4, Lz: 0.5 });
    const snapshot = makeSnapshot(
      [cac1, cac2, hd],
      [],
      { [GEOM_UUID_1]: GEOM_1_MATCHING, [GEOM_UUID_2]: GEOM_2_MISMATCHING },
    );
    const results = geometryConsistency.run(snapshot);
    expect(results).toHaveLength(0);
  });

  it("emits no fixAction (Phase 71 UAT 2026-05-21 removed FixActions)", () => {
    const snapshot = makeTwoCacTopology(GEOM_1_MATCHING, GEOM_2_MISMATCHING);
    const results = geometryConsistency.run(snapshot);
    expect(results).toHaveLength(1);
    expect(results[0].fixAction).toBeUndefined();
  });
});
