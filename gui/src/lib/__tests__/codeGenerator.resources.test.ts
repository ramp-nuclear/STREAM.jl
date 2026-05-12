// codeGenerator.resources.test.ts — Phase 62 Plan 62-10
//
// Resources-aware codegen tests covering INV-CG-01..04 + the four canonical
// Power Shape codegen forms (D-22 + CONTEXT.md Specifics) + Pitfall 4
// (resource-name-collides-with-component-name) + missing-ref handling.
//
// Reference: .planning/phases/62-resources-panel-architecture/62-VALIDATION.md
//
// Out of scope for this file: connections, BCs, activeLayer, thermal topology
// detection — those are owned by the pre-existing codeGenerator.test.ts. This
// file is laser-focused on the Resources block + _ref lookup pathway introduced
// by 62-10 (the new 5th argument to generateCode).

import { describe, it, expect } from "vitest";
import { generateCode } from "../codeGenerator";
import type { BCEntry, CodegenResources } from "../codeGenerator";
import type { ComponentDefinition } from "../../registry/types";
import type { Node } from "@xyflow/react";

// MUST match useStore.ts SENTINEL_UNSET_POWER_SHAPE (asserted by the codegen
// itself; the constant is duplicated to keep this test file dependency-free
// from the zustand store module).
const SENTINEL_UNSET_POWER_SHAPE = "00000000-0000-0000-0000-000000000000";

// ---------------------------------------------------------------------------
// Mock component definitions (subset of the real registry — only what the
// resources test cases reference).
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
      signature: "HeatDiffusion(; name, nz, nx, Lz, Lx, y, k_s, rho_s, cp_s, power_shape)",
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

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

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

function makeChannel(geometryRef: string, name = "ch_1"): Node {
  return makeNode("ch-node", "Channel", name, {
    n: 5,
    geometry_ref: geometryRef,
  });
}

function makeHD(
  powerShapeRef: string,
  nz: number,
  nx: number,
  name = "hd_1",
  id = "hd-node",
): Node {
  return makeNode(id, "HeatDiffusion", name, {
    nz,
    nx,
    Lz: 0.6,
    Lx: 0.001,
    y: 0.0015,
    k_s: 15.0,
    rho_s: 6500.0,
    cp_s: 300.0,
    power_shape_ref: powerShapeRef,
  });
}

function emptyResources(): CodegenResources {
  return { geometries: {}, powerShapes: {}, fluids: {} };
}

const NO_BCS: BCEntry[] = [];

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("generateCode — resources block (Phase 62 INV-CG-01..04)", () => {
  describe("INV-CG-01: Resources block precedes first @named declaration", () => {
    it("emits Geometry declaration BEFORE the first @named line", () => {
      const geomUuid = "geo-1";
      const resources: CodegenResources = {
        ...emptyResources(),
        geometries: {
          [geomUuid]: {
            uuid: geomUuid,
            name: "geom_mtr",
            kind: "rectangular",
            params: { L: 0.6, W: 0.07, H: 0.0025 },
          },
        },
      };
      const nodes = [makeNode("c", "ChannelAndContacts", "cac_1", {
        n: 5,
        geometry_ref: geomUuid,
      })];
      const code = generateCode(nodes, [], NO_BCS, mockGetComponent, resources);

      const geomIdx = code.indexOf("PipeGeometry_rectangular");
      const namedIdx = code.indexOf("@named");
      expect(geomIdx).toBeGreaterThanOrEqual(0);
      expect(namedIdx).toBeGreaterThanOrEqual(0);
      expect(geomIdx).toBeLessThan(namedIdx);
    });

    it("emits a # Resources comment header above the resource lines", () => {
      const resources: CodegenResources = {
        ...emptyResources(),
        geometries: {
          g1: {
            uuid: "g1",
            name: "geom_a",
            kind: "rectangular",
            params: { L: 0.5, W: 0.01, H: 0.003 },
          },
        },
      };
      const nodes = [makeChannel("g1")];
      const code = generateCode(nodes, [], NO_BCS, mockGetComponent, resources);
      expect(code).toContain("# Resources");
    });
  });

  describe("INV-CG-02: component constructors reference the resource by variable name", () => {
    it("Channel emits geometry=<resource_name> (not inlined PipeGeometry_*())", () => {
      const geomUuid = "geo-uuid-9";
      const resources: CodegenResources = {
        ...emptyResources(),
        geometries: {
          [geomUuid]: {
            uuid: geomUuid,
            name: "geom_main",
            kind: "rectangular",
            params: { L: 0.5, W: 0.01, H: 0.003 },
          },
        },
      };
      const nodes = [makeChannel(geomUuid)];
      const code = generateCode(nodes, [], NO_BCS, mockGetComponent, resources);
      expect(code).toContain("geometry=geom_main");
      // The Channel constructor MUST NOT inline the PipeGeometry. The
      // PipeGeometry_rectangular call appears once — only in the Resources
      // block — and the substring "geometry=PipeGeometry_rectangular(" is the
      // sigil of the legacy inline form.
      expect(code).not.toContain("geometry=PipeGeometry_rectangular(");
      expect(code).not.toContain("geometry=PipeGeometry_circular(");
    });
  });

  describe("INV-CG-03: file_loaded Power Shape emits rebin_extensive(readdlm(...))", () => {
    it("file_loaded -> rebin_extensive(readdlm(joinpath(@__DIR__, <path>), ','), (nz, nx))", () => {
      const psUuid = "ps-fl";
      const resources: CodegenResources = {
        ...emptyResources(),
        powerShapes: {
          [psUuid]: {
            uuid: psUuid,
            name: "mtr_axial",
            kind: "file_loaded",
            params: { path: "shapes/mtr.csv" },
          },
        },
      };
      const nodes = [makeHD(psUuid, 10, 5)];
      const code = generateCode(nodes, [], NO_BCS, mockGetComponent, resources);
      // Verbatim form — modulo whitespace inside the call signature.
      expect(code).toContain(
        `rebin_extensive(readdlm(joinpath(@__DIR__, "shapes/mtr.csv"), ','), (10, 5))`,
      );
    });
  });

  describe("INV-CG-04: unset Power Shape (sentinel) emits ones(nz, nx) + TODO comment", () => {
    it("SENTINEL_UNSET_POWER_SHAPE -> ones(10, 5)  # TODO: fill in your power shape", () => {
      // The unset sentinel is keyed under its fixed UUID; codegen detects it
      // either by UUID or by kind === "unset" (defensive).
      const resources: CodegenResources = {
        ...emptyResources(),
        powerShapes: {
          [SENTINEL_UNSET_POWER_SHAPE]: {
            uuid: SENTINEL_UNSET_POWER_SHAPE,
            name: "(leave unset — fill in code)",
            kind: "unset",
            params: {},
          },
        },
      };
      const nodes = [makeHD(SENTINEL_UNSET_POWER_SHAPE, 10, 5)];
      const code = generateCode(nodes, [], NO_BCS, mockGetComponent, resources);
      expect(code).toContain(
        "ones(10, 5)  # TODO: fill in your power shape",
      );
    });
  });

  describe("D-22 uniform Power Shape: ones(nz, nx) without TODO", () => {
    it("uniform -> ones(10, 5) and NO TODO comment on the same line", () => {
      const psUuid = "ps-uni";
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
      const nodes = [makeHD(psUuid, 10, 5)];
      const code = generateCode(nodes, [], NO_BCS, mockGetComponent, resources);
      // The uniform line must NOT carry the TODO comment.
      const flatLine = code
        .split("\n")
        .find((line) => line.includes("power_shape_flat_for_hd_1 ="));
      expect(flatLine).toBeDefined();
      expect(flatLine).toContain("ones(10, 5)");
      expect(flatLine).not.toContain("TODO");
    });
  });

  describe("D-22 z_cosine Power Shape: cosine_power_shape(nz, nx; amplitude=...)", () => {
    it("z_cosine amplitude=2.0 -> cosine_power_shape(10, 5; amplitude=2.0)", () => {
      const psUuid = "ps-zc";
      const resources: CodegenResources = {
        ...emptyResources(),
        powerShapes: {
          [psUuid]: {
            uuid: psUuid,
            name: "axial_cos",
            kind: "z_cosine",
            params: { amplitude: 2.0 },
          },
        },
      };
      const nodes = [makeHD(psUuid, 10, 5)];
      const code = generateCode(nodes, [], NO_BCS, mockGetComponent, resources);
      expect(code).toContain("cosine_power_shape(10, 5; amplitude=2.0)");
    });
  });

  describe("DelimitedFiles import is conditional on file_loaded presence", () => {
    it("emits `using DelimitedFiles` exactly once when a file_loaded shape exists", () => {
      const psUuid = "ps-fl-cond";
      const resources: CodegenResources = {
        ...emptyResources(),
        powerShapes: {
          [psUuid]: {
            uuid: psUuid,
            name: "from_file",
            kind: "file_loaded",
            params: { path: "shapes/x.csv" },
          },
        },
      };
      const nodes = [makeHD(psUuid, 8, 4)];
      const code = generateCode(nodes, [], NO_BCS, mockGetComponent, resources);
      const occurrences = (code.match(/using DelimitedFiles/g) ?? []).length;
      expect(occurrences).toBe(1);
    });

    it("does NOT emit `using DelimitedFiles` when no file_loaded shape exists", () => {
      const psUuid = "ps-uni-2";
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
      const nodes = [makeHD(psUuid, 8, 4)];
      const code = generateCode(nodes, [], NO_BCS, mockGetComponent, resources);
      expect(code).not.toContain("using DelimitedFiles");
    });
  });

  describe("Missing-ref handling", () => {
    it("Channel with geometry_ref pointing at an unknown UUID -> WARNING + geometry=missing", () => {
      const resources: CodegenResources = emptyResources();
      const nodes = [makeChannel("ghost-uuid")];
      const code = generateCode(nodes, [], NO_BCS, mockGetComponent, resources);
      expect(code).toContain("# WARNING: geometry_ref missing");
      expect(code).toContain("geometry=missing");
    });
  });

  describe("Pitfall 4: resource-name collides with component instance name", () => {
    it("a Geometry named `pump_1` colliding with a Pump named `pump_1` emits WARNING", () => {
      const geomUuid = "geo-collide";
      const resources: CodegenResources = {
        ...emptyResources(),
        geometries: {
          [geomUuid]: {
            uuid: geomUuid,
            // Pitfall 4: the Geometry name shadows the Pump instance name.
            name: "pump_1",
            kind: "rectangular",
            params: { L: 0.5, W: 0.01, H: 0.003 },
          },
        },
      };
      const nodes = [
        makeNode("p", "Pump", "pump_1", { dP_pump: 30000 }, "fixed-dP"),
        makeChannel(geomUuid, "ch_1"),
      ];
      const code = generateCode(nodes, [], NO_BCS, mockGetComponent, resources);
      // Match the WARNING — either the verbatim phrase or any "collides" hint
      // (RESEARCH leaves the exact wording flexible).
      expect(code).toMatch(
        /# WARNING: Resource name "pump_1" collides with component instance name "pump_1"/,
      );
    });
  });

  describe("Per-consumer Power Shape variable naming (RESEARCH Q2)", () => {
    it("two HDs referencing the same z_cosine PowerShape emit per-HD variable lines", () => {
      const psUuid = "ps-shared";
      const resources: CodegenResources = {
        ...emptyResources(),
        powerShapes: {
          [psUuid]: {
            uuid: psUuid,
            name: "axial_cos",
            kind: "z_cosine",
            params: { amplitude: 1.0 },
          },
        },
      };
      const nodes = [
        makeHD(psUuid, 10, 5, "hd_1", "hd-node-1"),
        makeHD(psUuid, 10, 5, "hd_2", "hd-node-2"),
      ];
      const code = generateCode(nodes, [], NO_BCS, mockGetComponent, resources);
      expect(code).toContain("power_shape_axial_cos_for_hd_1 = cosine_power_shape");
      expect(code).toContain("power_shape_axial_cos_for_hd_2 = cosine_power_shape");
      // Each HD constructor references its own variable.
      expect(code).toContain("power_shape=power_shape_axial_cos_for_hd_1");
      expect(code).toContain("power_shape=power_shape_axial_cos_for_hd_2");
    });
  });

  describe("Geometry kinds (both rectangular and circular)", () => {
    it("PipeGeometry_circular emitted for kind=circular", () => {
      const geomUuid = "geo-circ";
      const resources: CodegenResources = {
        ...emptyResources(),
        geometries: {
          [geomUuid]: {
            uuid: geomUuid,
            name: "tube_a",
            kind: "circular",
            params: { L: 0.6, D: 0.01 },
          },
        },
      };
      const nodes = [makeChannel(geomUuid)];
      const code = generateCode(nodes, [], NO_BCS, mockGetComponent, resources);
      expect(code).toContain("tube_a = PipeGeometry_circular(0.6, 0.01)");
      expect(code).toContain("geometry=tube_a");
    });
  });

  describe("Default 4-arg call (resources omitted) keeps the legacy inline-emit path", () => {
    it("legacy call without resources still produces inline geometry value (back-compat)", () => {
      // This guards the existing codeGenerator.test.ts behavior: the 4-arg
      // signature still works and emits inline PipeGeometry_*(...) when a node
      // carries an inline geometry value rather than a UUID. Critical for the
      // pre-Phase-62 fixtures used elsewhere.
      const nodes = [
        makeNode("c", "Channel", "ch_1", {
          n: 5,
          geometry: { type: "rectangular", L: 0.5, W: 0.01, H: 0.003 },
        }),
      ];
      const code = generateCode(nodes, [], NO_BCS, mockGetComponent);
      expect(code).toContain("PipeGeometry_rectangular(0.5, 0.01, 0.003)");
    });
  });
});
