// lengthMatch.test.ts — Unit tests for the lengthMatch validator (Phase 71, Plan 05)
//
// D-15 rule 2: "length match" — when CAC.geometry.L (resolved via resource UUID)
// != HD.Lz on a thermal coupling.
// §3.9 line 792: error severity; value-transfer-picker fix.
//
// Test cases:
//   1. CAC (geom.L=0.5) thermally connected to HD (Lz=0.5) → no result (match)
//   2. CAC (geom.L=0.5) thermally connected to HD (Lz=0.6) → 1 error, value-transfer-picker
//   3. Dangling geometry UUID (not in resources) → no result (defensive)
//   4. No thermal edges → no result
//   5. fixAction.applyLeft propagates CAC.L → HD.Lz (updateNodeParams)
//   6. fixAction.applyRight propagates HD.Lz → CAC geometry resource (updateResource)

import { describe, it, expect } from "vitest";
import type { Node, Edge } from "@xyflow/react";
import type { ValidationSnapshot } from "../../snapshot";
import type { ComponentDefinition } from "../../../../registry/types";

import { lengthMatch } from "../lengthMatch";

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
    { name: "Lz", type: "Real", default: 0.5, required: true, positional: false },
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
    { name: "Lz", type: "Real", default: 0.5, required: true, positional: false },
  ],
  constructorModes: [],
};

const DEFS: Record<string, ComponentDefinition> = {
  ChannelAndContacts: CAC_DEF,
  HeatDiffusion: HD_DEF,
};

// ---------------------------------------------------------------------------
// Geometry resource fixture
// ---------------------------------------------------------------------------

const GEOM_UUID = "uuid-geom-1";

const GEOM_RESOURCE = {
  uuid: GEOM_UUID,
  name: "geometry_1",
  kind: "rectangular" as const,
  params: { L: 0.5, W: 0.1, H: 0.01 },
};

// ---------------------------------------------------------------------------
// Snapshot factory
// ---------------------------------------------------------------------------

function makeSnapshot(
  nodes: Node[],
  edges: Edge[],
  geometryL?: number,
  geomUuid?: string,
): ValidationSnapshot {
  const uuid = geomUuid ?? GEOM_UUID;
  const gL = geometryL ?? 0.5;
  return {
    nodes,
    edges,
    anchors: {},
    bcMode: {},
    resources: {
      geometries: {
        [uuid]: { ...GEOM_RESOURCE, uuid, params: { L: gL, W: 0.1, H: 0.01 } },
      },
      powerShapes: {},
      fluids: {},
    },
    getComponentDef: (id: string) => DEFS[id],
  };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("lengthMatch", () => {
  it("returns no result when CAC geometry L matches HD.Lz", () => {
    const cac = makeNode("cac1", "ChannelAndContacts", "cac_1", {
      n: 4,
      geometry: GEOM_UUID,
    });
    const hd = makeNode("hd1", "HeatDiffusion", "hd_1", { nz: 4, Lz: 0.5 });
    const edge = makeEdge("e1", "cac1", "thermal_right", "hd1", "thermal_left");
    const snapshot = makeSnapshot([cac, hd], [edge], 0.5);
    const results = lengthMatch.run(snapshot);
    expect(results).toHaveLength(0);
  });

  it("emits one error when CAC geometry L=0.5 and HD.Lz=0.6 are thermally connected", () => {
    const cac = makeNode("cac1", "ChannelAndContacts", "cac_1", {
      n: 4,
      geometry: GEOM_UUID,
    });
    const hd = makeNode("hd1", "HeatDiffusion", "hd_1", { nz: 4, Lz: 0.6 });
    const edge = makeEdge("e1", "cac1", "thermal_right", "hd1", "thermal_left");
    const snapshot = makeSnapshot([cac, hd], [edge], 0.5);
    const results = lengthMatch.run(snapshot);
    expect(results).toHaveLength(1);
    const r = results[0];
    expect(r.validatorId).toBe("length_match");
    expect(r.severity).toBe("warning");
    expect(r.description).toContain("0.5");
    expect(r.description).toContain("0.6");
    // Targets: edge, field('geometry') on CAC, field('Lz') on HD, both node targets
    const edgeTargets = r.targets.filter((t) => t.kind === "edge");
    const fieldTargets = r.targets.filter((t) => t.kind === "field");
    const nodeTargets = r.targets.filter((t) => t.kind === "node");
    expect(edgeTargets).toHaveLength(1);
    expect(
      fieldTargets.some((t) => t.kind === "field" && t.fieldPath === "geometry"),
    ).toBe(true);
    expect(
      fieldTargets.some((t) => t.kind === "field" && t.fieldPath === "Lz"),
    ).toBe(true);
    expect(nodeTargets).toHaveLength(2);
  });

  it("returns no result when CAC geometry UUID is not in resources (dangling ref)", () => {
    const cac = makeNode("cac1", "ChannelAndContacts", "cac_1", {
      n: 4,
      geometry: "non-existent-uuid",
    });
    const hd = makeNode("hd1", "HeatDiffusion", "hd_1", { nz: 4, Lz: 0.6 });
    const edge = makeEdge("e1", "cac1", "thermal_right", "hd1", "thermal_left");
    const snapshot = makeSnapshot([cac, hd], [edge], 0.5);
    const results = lengthMatch.run(snapshot);
    expect(results).toHaveLength(0);
  });

  it("returns no result when there are no thermal edges", () => {
    const cac = makeNode("cac1", "ChannelAndContacts", "cac_1", {
      n: 4,
      geometry: GEOM_UUID,
    });
    const hd = makeNode("hd1", "HeatDiffusion", "hd_1", { nz: 4, Lz: 0.6 });
    const snapshot = makeSnapshot([cac, hd], [], 0.5);
    const results = lengthMatch.run(snapshot);
    expect(results).toHaveLength(0);
  });

});
