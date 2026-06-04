// codeGenerator.sections.test.ts — Phase 66 Plan 01 (RED)
//
// Locks the structured CodeSection[] / CodeSubBlock contract for Phase 66.
// Plan 02 turns this file green by refactoring codeGenerator.ts to return
// CodeSection[] instead of `string`.
//
// References:
//   .planning/phases/66-code-preview-rework/66-CONTEXT.md D-01..D-04
//   .planning/phases/66-code-preview-rework/66-RESEARCH.md Pattern 10
//
// Test surface scope:
//   - Imports section: single sub-block, sourceIds=[]
//   - Components section: one sub-block per @named, sourceIds=[node_uuid]
//   - Composition section: one sub-block per connect(), sourceIds=[uuid,uuid]
//   - Composition section: one sub-block per helper call (symmetric_plate),
//     sourceIds=[all CAC+HD UUIDs]
//   - Resources section: one sub-block per Geometry (kind:'resource')
//   - Resources section: one sub-block per per-HD consumer-keyed power_shape
//     (kind:'consumer-ps', sourceIds=[ps_uuid, hd_uuid])
//   - Main section: single sub-block, sourceIds=[], contains @named sys / mtkcompile
//   - Section order: Imports < Resources < Components < Composition < Main
//
// RED state: this file references type names (CodeSection, CodeSubBlock,
// CodeSectionName, CodeSubBlockKind) that do NOT yet exist as exports on
// `../codeGenerator`. tsc compilation will fail with "Module has no exported
// member 'CodeSection'" etc. — that is the intended failure category. Plan 02
// adds those exports.

import { describe, it, expect } from "vitest";
import {
  generateCode,
  type CodegenResources,
  // Phase 66 Plan 02 will export the four type names below from
  // `../codeGenerator`. Importing them here in the RED test surface locks the
  // contract before any production-code refactor.
  type CodeSection,
  type CodeSubBlock,
  type CodeSectionName,
  type CodeSubBlockKind,
} from "../codeGenerator";
import type { CodegenAnchorsState } from "../anchors";
import type { ComponentDefinition } from "../../registry/types";
import type { Node, Edge } from "@xyflow/react";

// ---------------------------------------------------------------------------
// Mock component definitions (subset of the real registry).
// Mirrors the fixture shape used by codeGenerator.resources.test.ts /
// codeGenerator.smoke.test.ts — copied rather than imported to keep test files
// independent.
// ---------------------------------------------------------------------------

const pumpDef: ComponentDefinition = {
  id: "Pump",
  label: "Pump",
  category: "Hydraulic",
  description: "Pump",
  ports: [
    { name: "port_in", type: "FlowPort", side: "left" },
    { name: "port_out", type: "FlowPort", side: "right" },
  ],
  parameters: [
    {
      name: "dP_pump",
      type: "Real",
      unit: "Pa",
      description: "Fixed pressure rise",
      required: true,
      positional: true,
    },
  ],
  constructorModes: [
    { mode: "fixed-dP", signature: "Pump(dP_pump::Real; name)", parameters: ["dP_pump"] },
  ],
};

const channelDef: ComponentDefinition = {
  id: "Channel",
  label: "Channel",
  category: "Hydraulic",
  description: "Channel",
  ports: [
    { name: "port_in", type: "FlowPort", side: "left" },
    { name: "port_out", type: "FlowPort", side: "right" },
    { name: "thermal", type: "ThermalPort", side: "top" },
  ],
  parameters: [
    { name: "n", type: "Int", description: "Cells", required: true, positional: false },
    {
      name: "geometry",
      type: "PipeGeometry",
      description: "Geometry FK",
      required: true,
      positional: false,
    },
  ],
  constructorModes: [
    {
      mode: "default",
      signature: "Channel(; name, n, geometry)",
      parameters: ["n", "geometry"],
    },
  ],
};

const cacDef: ComponentDefinition = {
  id: "ChannelAndContacts",
  label: "Channel And Contacts",
  category: "Hydraulic",
  description: "CAC",
  ports: [
    { name: "port_in", type: "FlowPort", side: "left" },
    { name: "port_out", type: "FlowPort", side: "right" },
    { name: "thermal_left", type: "ThermalPort", side: "top", array: true, arrayParam: "n" },
    { name: "thermal_right", type: "ThermalPort", side: "bottom", array: true, arrayParam: "n" },
  ],
  parameters: [
    { name: "n", type: "Int", description: "Cells", required: true, positional: false },
    {
      name: "geometry",
      type: "PipeGeometry",
      description: "Geometry FK",
      required: true,
      positional: false,
    },
  ],
  constructorModes: [
    {
      mode: "default",
      signature: "ChannelAndContacts(; name, n, geometry)",
      parameters: ["n", "geometry"],
    },
  ],
};

const hdDef: ComponentDefinition = {
  id: "HeatDiffusion",
  label: "Heat Diffusion",
  category: "Thermal",
  description: "HD",
  ports: [
    { name: "thermal_left", type: "ThermalPort", side: "left", array: true, arrayParam: "nz" },
    { name: "thermal_right", type: "ThermalPort", side: "right", array: true, arrayParam: "nz" },
  ],
  parameters: [
    { name: "nz", type: "Int", description: "Axial nodes", required: true, positional: false },
    { name: "nx", type: "Int", description: "Radial nodes", required: true, positional: false },
    { name: "Lz", type: "Real", description: "Axial length", required: true, positional: false },
    { name: "Lx", type: "Real", description: "Radial thickness", required: true, positional: false },
    { name: "y", type: "Real", description: "Half-gap", required: true, positional: false },
    { name: "k_s", type: "Real", description: "Conductivity", required: true, positional: false },
    { name: "rho_s", type: "Real", description: "Density", required: true, positional: false },
    { name: "cp_s", type: "Real", description: "Specific heat", required: true, positional: false },
    {
      name: "power_shape",
      type: "Matrix",
      description: "Normalized power distribution matrix",
      required: true,
      positional: false,
    },
  ],
  constructorModes: [
    {
      mode: "default",
      signature:
        "HeatDiffusion(; name, nz, nx, Lz, Lx, y, k_s, rho_s, cp_s, power_shape)",
      parameters: ["nz", "nx", "Lz", "Lx", "y", "k_s", "rho_s", "cp_s", "power_shape"],
    },
  ],
};

const componentMap: Record<string, ComponentDefinition> = {
  Pump: pumpDef,
  Channel: channelDef,
  ChannelAndContacts: cacDef,
  HeatDiffusion: hdDef,
};

function mockGetComponent(id: string): ComponentDefinition | undefined {
  return componentMap[id];
}

function makeNode(
  id: string,
  componentId: string,
  instanceName: string,
  params: Record<string, unknown>,
  mode?: string,
): Node {
  return {
    id,
    type: "streamNode",
    position: { x: 0, y: 0 },
    data: {
      componentId,
      instanceName,
      parameters: params,
      constructorMode: mode,
    },
  };
}

const NO_ANCHORS: CodegenAnchorsState = { anchors: {} };

function emptyResources(): CodegenResources {
  return { geometries: {}, powerShapes: {}, fluids: {} };
}

// ---------------------------------------------------------------------------
// Fixture builders
// ---------------------------------------------------------------------------

/** Minimal pump+channel graph with one connect() edge. */
function pumpPlusChannelFixture(): { nodes: Node[]; edges: Edge[] } {
  const pump = makeNode("pump-uuid", "Pump", "pump_1", { dP_pump: 1.0 }, "fixed-dP");
  const ch = makeNode("ch-uuid", "Channel", "ch_1", {
    n: 5,
    geometry_ref: "geo-1",
  });
  const edge: Edge = {
    id: "e1",
    source: "pump-uuid",
    target: "ch-uuid",
    sourceHandle: "port_out",
    targetHandle: "port_in",
  };
  return { nodes: [pump, ch], edges: [edge] };
}

/** Symmetric-plate topology: one CAC wired to both sides of one HD. */
function symmetricPlateFixture(): {
  nodes: Node[];
  edges: Edge[];
  cacId: string;
  hdId: string;
} {
  const cac = makeNode("cac-uuid", "ChannelAndContacts", "cac_1", {
    n: 5,
    geometry_ref: "geo-1",
  });
  const hd = makeNode("hd-uuid", "HeatDiffusion", "hd_1", {
    nz: 5,
    nx: 3,
    Lz: 0.6,
    Lx: 0.001,
    y: 0.0015,
    k_s: 15.0,
    rho_s: 6500.0,
    cp_s: 300.0,
    power_shape_ref: "ps-1",
  });
  // Symmetric_plate topology: CAC.thermal_right -> HD.thermal_left AND
  // CAC.thermal_left -> HD.thermal_right. The thermal ports are array-shaped
  // (per `array_size: "n"`), but the codegen detector keys on base port names
  // — matches the convention used throughout codeGenerator.test.ts and the
  // Phase 40 topology detector (D-07..D-10). Plan 02 Rule 1: corrected from
  // the per-cell `thermal_left__${i}` shape that didn't match codegen's exact-
  // name port lookup.
  const edges: Edge[] = [
    {
      id: "e_t_left",
      source: "cac-uuid",
      target: "hd-uuid",
      sourceHandle: "thermal_right",
      targetHandle: "thermal_left",
    },
    {
      id: "e_t_right",
      source: "cac-uuid",
      target: "hd-uuid",
      sourceHandle: "thermal_left",
      targetHandle: "thermal_right",
    },
  ];
  return { nodes: [cac, hd], edges, cacId: "cac-uuid", hdId: "hd-uuid" };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("generateCode returns CodeSection[] with source tracking (Phase 66 D-01..D-04)", () => {
  // ---- Section-shape contract --------------------------------------------

  it("returns a CodeSection[] (typed array, not a string)", () => {
    const { nodes, edges } = pumpPlusChannelFixture();
    const sections = generateCode(nodes, edges, NO_ANCHORS, mockGetComponent);
    // Runtime shape assertions
    expect(Array.isArray(sections)).toBe(true);
    expect(sections.length).toBeGreaterThan(0);
    // Every section has a name + subBlocks
    for (const section of sections as unknown as CodeSection[]) {
      expect(typeof section.name).toBe("string");
      expect(Array.isArray(section.subBlocks)).toBe(true);
    }
  });

  it("section names are drawn from the locked CodeSectionName union", () => {
    const { nodes, edges } = pumpPlusChannelFixture();
    const sections = generateCode(nodes, edges, NO_ANCHORS, mockGetComponent) as unknown as CodeSection[];
    const validNames: CodeSectionName[] = [
      "Imports",
      "Resources",
      "Components",
      "Composition",
      "Main",
    ];
    for (const section of sections) {
      expect(validNames).toContain(section.name);
    }
  });

  it("section order: Imports < Components < Composition < Main (present sections only)", () => {
    const { nodes, edges } = pumpPlusChannelFixture();
    const sections = generateCode(nodes, edges, NO_ANCHORS, mockGetComponent) as unknown as CodeSection[];
    const order = sections.map((s) => s.name);
    const idx = (n: CodeSectionName) => order.indexOf(n);
    // Imports + Components + Composition + Main are always present for a
    // non-empty graph.
    expect(idx("Imports")).toBeGreaterThanOrEqual(0);
    expect(idx("Components")).toBeGreaterThan(idx("Imports"));
    expect(idx("Composition")).toBeGreaterThan(idx("Components"));
    expect(idx("Main")).toBeGreaterThan(idx("Composition"));
  });

  // ---- Imports section (D-04) --------------------------------------------

  it("Imports section is a single sub-block with sourceIds=[]", () => {
    const { nodes, edges } = pumpPlusChannelFixture();
    const sections = generateCode(nodes, edges, NO_ANCHORS, mockGetComponent) as unknown as CodeSection[];
    const imports = sections.find((s) => s.name === "Imports");
    expect(imports).toBeDefined();
    expect(imports!.subBlocks).toHaveLength(1);
    const sub: CodeSubBlock = imports!.subBlocks[0];
    expect(sub.sourceIds).toEqual([]);
    // First non-comment line is the `using ModelingToolkit...` line.
    const firstUsing = sub.lines.find((l) => l.startsWith("using ModelingToolkit"));
    expect(firstUsing).toBeDefined();
  });

  // ---- Components section (D-04) -----------------------------------------

  it("emits one Components sub-block per @named with sourceIds=[node_uuid]", () => {
    const { nodes, edges } = pumpPlusChannelFixture();
    const sections = generateCode(nodes, edges, NO_ANCHORS, mockGetComponent) as unknown as CodeSection[];
    const components = sections.find((s) => s.name === "Components");
    expect(components).toBeDefined();
    // Two @named declarations: pump_1 + ch_1 → two sub-blocks.
    expect(components!.subBlocks.length).toBe(2);

    // Each sub-block has exactly one sourceId (the node's id) and its `lines`
    // contain the `@named <name> = <Constructor>(...)` text.
    const pumpSub = components!.subBlocks.find(
      (sb) => sb.lines.some((l) => l.includes("@named pump_1")),
    );
    expect(pumpSub).toBeDefined();
    expect(pumpSub!.sourceIds).toEqual(["pump-uuid"]);
    expect(pumpSub!.kind as CodeSubBlockKind | undefined).toBe("component");

    const chSub = components!.subBlocks.find(
      (sb) => sb.lines.some((l) => l.includes("@named ch_1")),
    );
    expect(chSub).toBeDefined();
    expect(chSub!.sourceIds).toEqual(["ch-uuid"]);
    expect(chSub!.kind as CodeSubBlockKind | undefined).toBe("component");
  });

  // ---- Composition section: connect() (D-02) -----------------------------

  it("emits one Composition sub-block per connect() with kind:'connect' and both endpoint UUIDs", () => {
    const { nodes, edges } = pumpPlusChannelFixture();
    const sections = generateCode(nodes, edges, NO_ANCHORS, mockGetComponent) as unknown as CodeSection[];
    const composition = sections.find((s) => s.name === "Composition");
    expect(composition).toBeDefined();

    const connectSubs = composition!.subBlocks.filter(
      (sb) => (sb.kind as CodeSubBlockKind | undefined) === "connect",
    );
    expect(connectSubs.length).toBeGreaterThanOrEqual(1);

    // The pump→ch edge sub-block has BOTH endpoints in sourceIds (sorted or not).
    const pumpChConnect = connectSubs.find((sb) =>
      sb.lines.some(
        (l) => l.includes("connect(") && l.includes("pump_1") && l.includes("ch_1"),
      ),
    );
    expect(pumpChConnect).toBeDefined();
    expect(pumpChConnect!.sourceIds.sort()).toEqual(["ch-uuid", "pump-uuid"].sort());
  });

  // ---- Composition section: helper call (D-02) ---------------------------

  it("emits one Composition sub-block per helper call (symmetric_plate) with kind:'helper' and all CAC+HD UUIDs", () => {
    const { nodes, edges, cacId, hdId } = symmetricPlateFixture();
    const sections = generateCode(nodes, edges, NO_ANCHORS, mockGetComponent) as unknown as CodeSection[];
    const composition = sections.find((s) => s.name === "Composition");
    expect(composition).toBeDefined();

    // The topology detector should produce a `symmetric_plate(...)` helper sub-block.
    const helperSubs = composition!.subBlocks.filter(
      (sb) => (sb.kind as CodeSubBlockKind | undefined) === "helper",
    );
    expect(helperSubs.length).toBeGreaterThanOrEqual(1);

    const symPlate = helperSubs.find((sb) =>
      sb.lines.some((l) => l.includes("symmetric_plate(")),
    );
    expect(symPlate).toBeDefined();
    // sourceIds list every CAC + HD UUID the helper consumes.
    expect(symPlate!.sourceIds.sort()).toEqual([cacId, hdId].sort());
  });

  // ---- Resources section: Geometry (D-03) --------------------------------

  it("emits one Resources sub-block per Geometry with kind:'resource' and sourceIds=[geometry_uuid]", () => {
    const geomUuid = "geo-uuid-A";
    const resources: CodegenResources = {
      ...emptyResources(),
      geometries: {
        [geomUuid]: {
          uuid: geomUuid,
          name: "geom_a",
          kind: "rectangular",
          params: { L: 0.6, W: 0.07, H: 0.0025 },
        },
      },
    };
    const nodes = [
      makeNode("ch-x", "Channel", "ch_1", { n: 5, geometry_ref: geomUuid }),
    ];
    const sections = generateCode(
      nodes,
      [],
      NO_ANCHORS,
      mockGetComponent,
      resources,
    ) as unknown as CodeSection[];

    const resSection = sections.find((s) => s.name === "Resources");
    expect(resSection).toBeDefined();

    const geomSub = resSection!.subBlocks.find(
      (sb) => (sb.kind as CodeSubBlockKind | undefined) === "resource",
    );
    expect(geomSub).toBeDefined();
    expect(geomSub!.sourceIds).toEqual([geomUuid]);
    expect(geomSub!.lines.some((l) => l.includes("PipeGeometry_rectangular"))).toBe(
      true,
    );
  });

  // ---- Resources section: per-HD consumer-keyed Power Shape (D-03) -------

  it("emits one Resources sub-block per consumer-keyed power_shape with kind:'consumer-ps' and sourceIds=[ps_uuid, hd_uuid]", () => {
    const psUuid = "ps-uuid-B";
    const resources: CodegenResources = {
      ...emptyResources(),
      powerShapes: {
        [psUuid]: {
          uuid: psUuid,
          name: "flat",
          kind: "uniform",
          params: {},
        },
      },
    };
    const hdId = "hd-uuid-B";
    const nodes = [
      makeNode(hdId, "HeatDiffusion", "hd_1", {
        nz: 10,
        nx: 5,
        Lz: 0.6,
        Lx: 0.001,
        y: 0.0015,
        k_s: 15.0,
        rho_s: 6500.0,
        cp_s: 300.0,
        power_shape_ref: psUuid,
      }),
    ];
    const sections = generateCode(
      nodes,
      [],
      NO_ANCHORS,
      mockGetComponent,
      resources,
    ) as unknown as CodeSection[];

    const resSection = sections.find((s) => s.name === "Resources");
    expect(resSection).toBeDefined();

    const psSub = resSection!.subBlocks.find(
      (sb) => (sb.kind as CodeSubBlockKind | undefined) === "consumer-ps",
    );
    expect(psSub).toBeDefined();
    // sourceIds include both the resource UUID and the consuming HD UUID
    expect(psSub!.sourceIds.sort()).toEqual([psUuid, hdId].sort());
    expect(psSub!.lines.some((l) => l.includes("power_shape"))).toBe(true);
  });

  // ---- Main section (D-04) -----------------------------------------------

  it("Main section is a single sub-block with sourceIds=[] containing @named sys + mtkcompile", () => {
    const { nodes, edges } = pumpPlusChannelFixture();
    const sections = generateCode(nodes, edges, NO_ANCHORS, mockGetComponent) as unknown as CodeSection[];
    const main = sections.find((s) => s.name === "Main");
    expect(main).toBeDefined();
    expect(main!.subBlocks).toHaveLength(1);
    const sub: CodeSubBlock = main!.subBlocks[0];
    expect(sub.sourceIds).toEqual([]);
    // The system-construction line + mtkcompile (or the existing finalization
    // lines) must appear.
    const hasNamedSys = sub.lines.some((l) => l.includes("@named sys"));
    const hasMtkcompile = sub.lines.some((l) => l.includes("mtkcompile"));
    expect(hasNamedSys).toBe(true);
    expect(hasMtkcompile).toBe(true);
  });
});
