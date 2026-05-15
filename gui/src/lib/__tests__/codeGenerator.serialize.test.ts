// codeGenerator.serialize.test.ts — Phase 66 Plan 01 (RED)
//
// Locks the `serializeSections(CodeSection[]): string` adapter contract
// and the D-12 formatting floor (section headers, blank-line discipline,
// no trailing whitespace).
//
// Plan 02 turns this file green by exporting `serializeSections` from
// `../codeGenerator` and by switching the codegen output to D-12 headers.
//
// References:
//   .planning/phases/66-code-preview-rework/66-CONTEXT.md D-12
//   .planning/phases/66-code-preview-rework/66-RESEARCH.md Pattern 2, Pitfall 3
//
// RED state: `serializeSections` is not yet exported from `../codeGenerator`.
// Runtime calls hit `serializeSections is not a function` (or undefined call),
// AND the codegen still emits `# Resources` / dashed-block headers rather than
// the D-12 `# === Resources ===` form.

import { describe, it, expect } from "vitest";
import {
  generateCode,
  type CodegenResources,
  // Plan 02 adds this named export to ../codeGenerator. Importing it RED.
  serializeSections,
  type CodeSection,
} from "../codeGenerator";
import type { CodegenAnchorsState } from "../anchors";
import type { ComponentDefinition } from "../../registry/types";
import type { Node, Edge } from "@xyflow/react";

// ---------------------------------------------------------------------------
// Mock component definitions (subset of the real registry).
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

/** Non-trivial fixture: pump + channel + connect + one Geometry + one PowerShape + one HD. */
function fullFixture(): {
  nodes: Node[];
  edges: Edge[];
  resources: CodegenResources;
} {
  const geomUuid = "geo-1";
  const psUuid = "ps-1";
  const resources: CodegenResources = {
    geometries: {
      [geomUuid]: {
        uuid: geomUuid,
        name: "geom_main",
        kind: "rectangular",
        params: { L: 0.6, W: 0.07, H: 0.0025 },
      },
    },
    powerShapes: {
      [psUuid]: {
        uuid: psUuid,
        name: "flat",
        kind: "uniform",
        params: {},
      },
    },
    fluids: {},
  };
  const pump = makeNode("pump-uuid", "Pump", "pump_1", { dP_pump: 1.0 }, "fixed-dP");
  const ch = makeNode("ch-uuid", "Channel", "ch_1", {
    n: 5,
    geometry_ref: geomUuid,
  });
  const hd = makeNode("hd-uuid", "HeatDiffusion", "hd_1", {
    nz: 10,
    nx: 5,
    Lz: 0.6,
    Lx: 0.001,
    y: 0.0015,
    k_s: 15.0,
    rho_s: 6500.0,
    cp_s: 300.0,
    power_shape_ref: psUuid,
  });
  const edge: Edge = {
    id: "e1",
    source: "pump-uuid",
    target: "ch-uuid",
    sourceHandle: "port_out",
    targetHandle: "port_in",
  };
  return { nodes: [pump, ch, hd], edges: [edge], resources };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("serializeSections — D-12 formatting floor + round-trip", () => {
  // ---- Return type ------------------------------------------------------

  it("returns a string", () => {
    const { nodes, edges, resources } = fullFixture();
    const sections = generateCode(
      nodes,
      edges,
      NO_ANCHORS,
      mockGetComponent,
      resources,
    ) as unknown as CodeSection[];
    const serialized = serializeSections(sections);
    expect(typeof serialized).toBe("string");
  });

  // ---- D-12: section headers ---------------------------------------------

  it("emits `# === Imports ===` as a top-level section header (D-12)", () => {
    const { nodes, edges, resources } = fullFixture();
    const sections = generateCode(
      nodes,
      edges,
      NO_ANCHORS,
      mockGetComponent,
      resources,
    ) as unknown as CodeSection[];
    const serialized = serializeSections(sections);
    expect(serialized).toContain("# === Imports ===");
  });

  it("emits `# === Resources ===`, `# === Components ===`, `# === Composition ===`, `# === Main ===` for the full fixture (D-12)", () => {
    const { nodes, edges, resources } = fullFixture();
    const sections = generateCode(
      nodes,
      edges,
      NO_ANCHORS,
      mockGetComponent,
      resources,
    ) as unknown as CodeSection[];
    const serialized = serializeSections(sections);
    expect(serialized).toContain("# === Resources ===");
    expect(serialized).toContain("# === Components ===");
    expect(serialized).toContain("# === Composition ===");
    expect(serialized).toContain("# === Main ===");
  });

  // ---- D-12: blank-line discipline ---------------------------------------

  it("emits exactly one blank line between top-level sections (no triple newline — Pitfall 3)", () => {
    const { nodes, edges, resources } = fullFixture();
    const sections = generateCode(
      nodes,
      edges,
      NO_ANCHORS,
      mockGetComponent,
      resources,
    ) as unknown as CodeSection[];
    const serialized = serializeSections(sections);
    // Triple-newline (or more) anywhere in the output is a Pitfall 3 regression.
    expect(serialized).not.toMatch(/\n\n\n/);
  });

  it("emits exactly one blank line between sub-blocks within a section (no double blanks — D-12 + Pitfall 3)", () => {
    const { nodes, edges, resources } = fullFixture();
    const sections = generateCode(
      nodes,
      edges,
      NO_ANCHORS,
      mockGetComponent,
      resources,
    ) as unknown as CodeSection[];
    const serialized = serializeSections(sections);
    // Specifically: between `@named pump_1 = Pump(...)` (last line of one
    // sub-block) and `@named ch_1 = Channel(...)` (first line of the next),
    // there is exactly one blank line.
    const between = /@named pump_1[^\n]*\n\n@named ch_1/;
    expect(serialized).toMatch(between);
  });

  // ---- D-12: no trailing whitespace --------------------------------------

  it("has no trailing whitespace on any line (D-12)", () => {
    const { nodes, edges, resources } = fullFixture();
    const sections = generateCode(
      nodes,
      edges,
      NO_ANCHORS,
      mockGetComponent,
      resources,
    ) as unknown as CodeSection[];
    const serialized = serializeSections(sections);
    const offendingLines = serialized
      .split("\n")
      .map((line, i) => ({ line, i }))
      .filter(({ line }) => /[ \t]+$/.test(line));
    expect(offendingLines).toEqual([]);
  });

  // ---- Section order (D-04 / D-12) ---------------------------------------

  it("preserves section order Imports → Resources → Components → Composition → Main", () => {
    const { nodes, edges, resources } = fullFixture();
    const sections = generateCode(
      nodes,
      edges,
      NO_ANCHORS,
      mockGetComponent,
      resources,
    ) as unknown as CodeSection[];
    const serialized = serializeSections(sections);

    const idxImports = serialized.indexOf("# === Imports ===");
    const idxResources = serialized.indexOf("# === Resources ===");
    const idxComponents = serialized.indexOf("# === Components ===");
    const idxComposition = serialized.indexOf("# === Composition ===");
    const idxMain = serialized.indexOf("# === Main ===");

    expect(idxImports).toBeGreaterThanOrEqual(0);
    expect(idxResources).toBeGreaterThan(idxImports);
    expect(idxComponents).toBeGreaterThan(idxResources);
    expect(idxComposition).toBeGreaterThan(idxComponents);
    expect(idxMain).toBeGreaterThan(idxComposition);
  });

  // ---- Round-trip uniqueness ---------------------------------------------

  it("round-trip: every @named line appears exactly once", () => {
    const { nodes, edges, resources } = fullFixture();
    const sections = generateCode(
      nodes,
      edges,
      NO_ANCHORS,
      mockGetComponent,
      resources,
    ) as unknown as CodeSection[];
    const serialized = serializeSections(sections);

    // pump_1, ch_1, hd_1 → three @named (excluding @named sys = ... finalization).
    const namedComponents = serialized.match(/@named (pump_1|ch_1|hd_1)\b/g) ?? [];
    expect(namedComponents.length).toBe(3);

    // @named sys appears exactly once (the system construction line).
    const sysNamed = serialized.match(/@named sys\b/g) ?? [];
    expect(sysNamed.length).toBe(1);
  });

  it("round-trip: every connect( line appears exactly once", () => {
    const { nodes, edges, resources } = fullFixture();
    const sections = generateCode(
      nodes,
      edges,
      NO_ANCHORS,
      mockGetComponent,
      resources,
    ) as unknown as CodeSection[];
    const serialized = serializeSections(sections);

    // The fixture has one pump→ch edge → exactly one `connect(` line.
    const connects = serialized.match(/connect\(/g) ?? [];
    expect(connects.length).toBe(1);
  });

  // ---- Empty-section behavior (D-12: empty section omitted) --------------

  it("omits the Resources section header when no resources are present", () => {
    const pump = makeNode("p", "Pump", "pump_1", { dP_pump: 1.0 }, "fixed-dP");
    const sections = generateCode(
      [pump],
      [],
      NO_ANCHORS,
      mockGetComponent,
    ) as unknown as CodeSection[];
    const serialized = serializeSections(sections);
    // No Resources block when no Geometry/PowerShape/HD is on canvas.
    expect(serialized).not.toContain("# === Resources ===");
    // But Imports + Components + Main remain.
    expect(serialized).toContain("# === Imports ===");
    expect(serialized).toContain("# === Components ===");
  });
});
