// codeGenerator.test.ts -- Unit tests for STREAM.jl code generation from canvas state

import { describe, it, expect } from "vitest";
import { generateCode } from "./codeGenerator";
import type { CodegenAnchorsState } from "./anchors";
import { getComponent } from "../registry";
import type { ComponentDefinition, Parameter, FunctionOption } from "../registry/types";
import type { Node, Edge } from "@xyflow/react";

// Phase 63.1 Plan 04: helper to wrap an anchors Record into the third-arg
// shape expected by generateCode (no more BCEntry[] adapter).
const NO_ANCHORS: CodegenAnchorsState = { anchors: {} };
function anchors(
  ...entries: { nodeId: string; portField: "port_in.P" | "port_out.P"; value: number }[]
): CodegenAnchorsState {
  const a: Record<string, { portField: "port_in.P" | "port_out.P"; value: number }> = {};
  for (const e of entries) {
    a[e.nodeId] = { portField: e.portField, value: e.value };
  }
  return { anchors: a };
}

// ---------------------------------------------------------------------------
// Mock component definitions (matching real registry structure)
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
    {
      name: "mdot0",
      type: "Real",
      unit: "kg/s",
      description: "Fixed mass flow rate",
      required: true,
      positional: false,
    },
  ],
  constructorModes: [
    { mode: "fixed-dP", signature: "Pump(dP_pump::Real; name)", parameters: ["dP_pump"] },
    { mode: "fixed-mdot", signature: "Pump(; name, mdot0)", parameters: ["mdot0"] },
  ],
};

const elenbaasSubParams: Parameter[] = [
  { name: "b", type: "Real", unit: "m", description: "Gap", required: true, positional: false },
  { name: "L", type: "Real", unit: "m", description: "Length", required: true, positional: false },
  { name: "Dh", type: "Real", unit: "m", description: "Hydraulic diameter", required: true, positional: false },
  { name: "g", type: "Real", unit: "m/s^2", default: 9.80665, description: "Gravity", required: false, positional: false },
];

const htcOptions: FunctionOption[] = [
  { value: "dittus_boelter", label: "Dittus-Boelter", kind: "simple" },
  { value: "constant_Nusselt", label: "Constant Nusselt", kind: "simple" },
  {
    value: "regime_dependent",
    label: "Regime Dependent",
    kind: "factory",
    sub_parameters: [
      {
        name: "htc_forced",
        type: "Function",
        description: "Forced HTC",
        required: true,
        positional: false,
        options: [
          { value: "dittus_boelter", label: "Dittus-Boelter", kind: "simple" },
          { value: "constant_Nusselt", label: "Constant Nusselt", kind: "simple" },
          {
            value: "elenbaas_htc",
            label: "Elenbaas",
            kind: "factory",
            sub_parameters: elenbaasSubParams,
          },
        ],
      },
      {
        name: "htc_natural",
        type: "Function",
        description: "Natural HTC",
        required: true,
        positional: false,
        options: [
          { value: "dittus_boelter", label: "Dittus-Boelter", kind: "simple" },
          { value: "constant_Nusselt", label: "Constant Nusselt", kind: "simple" },
          {
            value: "elenbaas_htc",
            label: "Elenbaas",
            kind: "factory",
            sub_parameters: elenbaasSubParams,
          },
        ],
      },
      {
        name: "threshold",
        type: "Real",
        unit: "-",
        default: 1.0,
        description: "Gr/Re^2 threshold",
        required: false,
        positional: false,
      },
    ],
  },
  {
    value: "elenbaas_htc",
    label: "Elenbaas",
    kind: "factory",
    sub_parameters: elenbaasSubParams,
  },
];

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
    { name: "geometry", type: "PipeGeometry", description: "Geometry", required: true, positional: false },
    { name: "g", type: "Real", unit: "m/s^2", default: 0.0, description: "Gravity", required: false, positional: false },
    { name: "htc_correlation", type: "Function", default: "dittus_boelter", description: "HTC", required: false, positional: false, options: htcOptions },
    { name: "friction_correlation", type: "Function", default: "blasius_friction", description: "Friction", required: false, positional: false, options: [
      { value: "blasius_friction", label: "Blasius", kind: "simple" },
      { value: "laminar_friction", label: "Laminar", kind: "simple" },
    ]},
  ],
  constructorModes: [
    { mode: "default", signature: "Channel(; name, n, geometry, g=0.0, htc_correlation=dittus_boelter, friction_correlation=blasius_friction)", parameters: ["n", "geometry", "g", "htc_correlation", "friction_correlation"] },
  ],
};

const heatExDef: ComponentDefinition = {
  id: "HeatExchanger",
  label: "Heat Exchanger",
  category: "Hydraulic",
  description: "HeatExchanger",
  ports: [
    { name: "port_in", type: "FlowPort", side: "left" },
    { name: "port_out", type: "FlowPort", side: "right" },
  ],
  parameters: [
    { name: "T_bc", type: "Real", unit: "K", description: "BC temp", required: true, positional: true },
  ],
  constructorModes: [
    { mode: "default", signature: "HeatExchanger(T_bc; name)", parameters: ["T_bc"] },
  ],
};

const gravityDef: ComponentDefinition = {
  id: "Gravity",
  label: "Gravity",
  category: "Hydraulic",
  description: "Gravity",
  ports: [
    { name: "port_in", type: "FlowPort", side: "left" },
    { name: "port_out", type: "FlowPort", side: "right" },
  ],
  parameters: [
    { name: "H", type: "Real", unit: "m", description: "Height", required: true, positional: true },
  ],
  constructorModes: [
    { mode: "default", signature: "Gravity(H; name)", parameters: ["H"] },
  ],
};

const resistorDef: ComponentDefinition = {
  id: "Resistor",
  label: "Resistor",
  category: "Hydraulic",
  description: "Resistor",
  ports: [
    { name: "port_in", type: "FlowPort", side: "left" },
    { name: "port_out", type: "FlowPort", side: "right" },
  ],
  parameters: [
    { name: "R", type: "Real", unit: "Pa/(kg/s)", description: "Resistance", required: true, positional: true },
  ],
  constructorModes: [
    { mode: "default", signature: "Resistor(R; name)", parameters: ["R"] },
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
    { name: "geometry", type: "PipeGeometry", description: "Geometry", required: true, positional: false },
  ],
  constructorModes: [
    { mode: "default", signature: "ChannelAndContacts(; name, n, geometry)", parameters: ["n", "geometry"] },
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
    { name: "Lz", type: "Real", unit: "m", description: "Axial length", required: true, positional: false },
    { name: "Lx", type: "Real", unit: "m", description: "Radial thickness", required: true, positional: false },
    { name: "y", type: "Real", unit: "m", description: "Half-gap", required: true, positional: false },
    { name: "k", type: "Real", unit: "W/(m*K)", description: "Conductivity", required: true, positional: false },
    { name: "rho_s", type: "Real", unit: "kg/m^3", description: "Density", required: true, positional: false },
    { name: "cp_s", type: "Real", unit: "J/(kg*K)", description: "Specific heat", required: true, positional: false },
  ],
  constructorModes: [
    { mode: "default", signature: "HeatDiffusion(; name, nz, nx, Lz, Lx, y, k, rho_s, cp_s)", parameters: ["nz", "nx", "Lz", "Lx", "y", "k", "rho_s", "cp_s"] },
  ],
};

const ctDef: ComponentDefinition = {
  id: "ConstantTemperature",
  label: "Constant Temperature",
  category: "Thermal",
  description: "CT",
  ports: [
    { name: "thermal", type: "ThermalPort", side: "left" },
  ],
  parameters: [
    { name: "T", type: "Real", unit: "K", description: "Temperature", required: true, positional: true },
  ],
  constructorModes: [
    { mode: "default", signature: "ConstantTemperature(T; name)", parameters: ["T"] },
  ],
};

const componentMap: Record<string, ComponentDefinition> = {
  Pump: pumpDef,
  Channel: channelDef,
  HeatExchanger: heatExDef,
  Gravity: gravityDef,
  Resistor: resistorDef,
  ChannelAndContacts: cacDef,
  HeatDiffusion: hdDef,
  ConstantTemperature: ctDef,
};

function mockGetComponent(id: string): ComponentDefinition | undefined {
  return componentMap[id];
}

// Helper to create a node
function makeNode(id: string, componentId: string, instanceName: string, params: Record<string, unknown>, mode?: string): Node {
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

function makeEdge(id: string, source: string, sourceHandle: string, target: string, targetHandle: string): Edge {
  return { id, source, sourceHandle, target, targetHandle } as Edge;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("generateCode", () => {
  describe("empty state", () => {
    it("returns comment for empty canvas", () => {
      const result = generateCode([], [], NO_ANCHORS, mockGetComponent);
      expect(result).toBe("# Add components to the canvas to generate Julia code.");
    });
  });

  describe("component declarations", () => {
    it("emits Pump fixed-dP with positional arg", () => {
      const nodes = [makeNode("a", "Pump", "pump_1", { dP_pump: 30000 }, "fixed-dP")];
      const code = generateCode(nodes, [], NO_ANCHORS, mockGetComponent);
      expect(code).toContain("@named pump_1 = Pump(30000.0)");
    });

    it("emits Pump fixed-mdot with keyword-only (semicolon)", () => {
      const nodes = [makeNode("a", "Pump", "pump_1", { mdot0: 0.5 }, "fixed-mdot")];
      const code = generateCode(nodes, [], NO_ANCHORS, mockGetComponent);
      expect(code).toContain("@named pump_1 = Pump(; mdot0=0.5)");
    });

    it("emits Channel with defaults omitted", () => {
      const nodes = [makeNode("a", "Channel", "ch_1", {
        n: 5,
        geometry: { type: "rectangular", L: 0.5, W: 0.01, H: 0.003 },
        g: 0.0,
        htc_correlation: "dittus_boelter",
        friction_correlation: "blasius_friction",
      })];
      const code = generateCode(nodes, [], NO_ANCHORS, mockGetComponent);
      expect(code).toContain("@named ch_1 = Channel(; n=5, geometry=PipeGeometry_rectangular(0.5, 0.01, 0.003, 0.01))");
      // defaults should be omitted
      expect(code).not.toContain("g=");
      expect(code).not.toContain("htc_correlation=");
      expect(code).not.toContain("friction_correlation=");
    });

    it("emits Channel with non-default htc_correlation", () => {
      const nodes = [makeNode("a", "Channel", "ch_1", {
        n: 5,
        geometry: { type: "rectangular", L: 0.5, W: 0.01, H: 0.003 },
        g: 0.0,
        htc_correlation: "constant_Nusselt",
        friction_correlation: "blasius_friction",
      })];
      const code = generateCode(nodes, [], NO_ANCHORS, mockGetComponent);
      expect(code).toContain("htc_correlation=constant_Nusselt");
    });

    it("emits factory htc_correlation (elenbaas_htc)", () => {
      const nodes = [makeNode("a", "Channel", "ch_1", {
        n: 5,
        geometry: { type: "rectangular", L: 0.5, W: 0.01, H: 0.003 },
        htc_correlation: { kind: "factory", value: "elenbaas_htc", subParams: { b: 0.003, L: 0.6, Dh: 0.0025, g: 9.80665 } },
      })];
      const code = generateCode(nodes, [], NO_ANCHORS, mockGetComponent);
      // g=9.80665 is default for elenbaas_htc, should be omitted
      expect(code).toContain("htc_correlation=elenbaas_htc(b=0.003, L=0.6, Dh=0.0025)");
    });

    it("emits nested factory (regime_dependent with elenbaas_htc sub-param)", () => {
      const nodes = [makeNode("a", "Channel", "ch_1", {
        n: 5,
        geometry: { type: "rectangular", L: 0.5, W: 0.01, H: 0.003 },
        htc_correlation: {
          kind: "factory",
          value: "regime_dependent",
          subParams: {
            htc_forced: "dittus_boelter",
            htc_natural: { kind: "factory", value: "elenbaas_htc", subParams: { b: 0.003, L: 0.6, Dh: 0.0025 } },
            threshold: 1.0,
          },
        },
      })];
      const code = generateCode(nodes, [], NO_ANCHORS, mockGetComponent);
      // threshold=1.0 is default, should be omitted
      expect(code).toContain("htc_correlation=regime_dependent(htc_forced=dittus_boelter, htc_natural=elenbaas_htc(b=0.003, L=0.6, Dh=0.0025))");
    });

    it("emits HeatExchanger with positional arg", () => {
      const nodes = [makeNode("a", "HeatExchanger", "hx_1", { T_bc: 300 })];
      const code = generateCode(nodes, [], NO_ANCHORS, mockGetComponent);
      expect(code).toContain("@named hx_1 = HeatExchanger(300.0)");
    });

    it("emits Gravity with positional arg", () => {
      const nodes = [makeNode("a", "Gravity", "grav_1", { H: 0.5 })];
      const code = generateCode(nodes, [], NO_ANCHORS, mockGetComponent);
      expect(code).toContain("@named grav_1 = Gravity(0.5)");
    });

    it("emits Resistor with positional arg", () => {
      const nodes = [makeNode("a", "Resistor", "res_1", { R: 1000 })];
      const code = generateCode(nodes, [], NO_ANCHORS, mockGetComponent);
      expect(code).toContain("@named res_1 = Resistor(1000.0)");
    });

    it("emits PipeGeometry_circular for circular geometry", () => {
      const nodes = [makeNode("a", "Channel", "ch_1", {
        n: 5,
        geometry: { type: "circular", L: 0.5, D: 0.01 },
      })];
      const code = generateCode(nodes, [], NO_ANCHORS, mockGetComponent);
      expect(code).toContain("geometry=PipeGeometry_circular(0.5, 0.01)");
    });
  });

  describe("value formatting", () => {
    it("formats Int without decimal", () => {
      const nodes = [makeNode("a", "Channel", "ch_1", {
        n: 5,
        geometry: { type: "rectangular", L: 0.5, W: 0.01, H: 0.003 },
      })];
      const code = generateCode(nodes, [], NO_ANCHORS, mockGetComponent);
      expect(code).toContain("n=5,");
      expect(code).not.toContain("n=5.0");
    });

    it("formats integer Real with .0", () => {
      const nodes = [makeNode("a", "Pump", "pump_1", { dP_pump: 100 }, "fixed-dP")];
      const code = generateCode(nodes, [], NO_ANCHORS, mockGetComponent);
      expect(code).toContain("Pump(100.0)");
    });

    it("formats Real with existing decimal as-is", () => {
      const nodes = [makeNode("a", "Pump", "pump_1", { dP_pump: 0.5 }, "fixed-dP")];
      const code = generateCode(nodes, [], NO_ANCHORS, mockGetComponent);
      expect(code).toContain("Pump(0.5)");
    });
  });

  describe("connections", () => {
    it("emits connect() for edges", () => {
      const nodes = [
        makeNode("a", "Pump", "pump_1", { dP_pump: 30000 }, "fixed-dP"),
        makeNode("b", "Channel", "ch_1", { n: 5, geometry: { type: "rectangular", L: 0.5, W: 0.01, H: 0.003 } }),
      ];
      const edges = [makeEdge("e1", "a", "port_out", "b", "port_in")];
      const code = generateCode(nodes, edges, NO_ANCHORS, mockGetComponent);
      expect(code).toContain("connect(pump_1.port_out, ch_1.port_in)");
    });
  });

  describe("boundary conditions", () => {
    it("emits BC as equation", () => {
      const nodes = [makeNode("abc", "Pump", "pump_1", { dP_pump: 30000 }, "fixed-dP")];
      const a = anchors({ nodeId: "abc", portField: "port_in.P", value: 100000 });
      const code = generateCode(nodes, [], a, mockGetComponent);
      expect(code).toMatch(/pump_1\.port_in\.P\s*~\s*1(\.0)?e5|100000\.0/);
    });

    it("skips BC for deleted node", () => {
      const nodes = [makeNode("abc", "Pump", "pump_1", { dP_pump: 30000 }, "fixed-dP")];
      const a = anchors({ nodeId: "deleted_id", portField: "port_in.P", value: 100000 });
      const code = generateCode(nodes, [], a, mockGetComponent);
      // Should not contain a BC line for deleted_id
      expect(code).not.toContain("deleted_id");
    });
  });

  describe("identifier validation", () => {
    it("warns for invalid instanceName", () => {
      const nodes = [makeNode("a", "Pump", "my pump", { dP_pump: 30000 }, "fixed-dP")];
      const code = generateCode(nodes, [], NO_ANCHORS, mockGetComponent);
      expect(code).toContain('# WARNING: Invalid identifier "my pump" -- rename before exporting');
      expect(code).toContain("@named my pump = Pump(30000.0)");
    });
  });

  describe("complete system structure", () => {
    it("contains all sections for a Pump+Channel system", () => {
      const nodes = [
        makeNode("a", "Pump", "pump_1", { dP_pump: 30000 }, "fixed-dP"),
        makeNode("b", "Channel", "ch_1", { n: 5, geometry: { type: "rectangular", L: 0.5, W: 0.01, H: 0.003 } }),
      ];
      const edges = [makeEdge("e1", "a", "port_out", "b", "port_in")];
      const code = generateCode(nodes, edges, NO_ANCHORS, mockGetComponent);

      expect(code).toContain("using ModelingToolkit, STREAM");
      expect(code).toContain("@named");
      expect(code).toContain("eqs = [");
      expect(code).toContain("connect(");
      expect(code).toContain("ODESystem(eqs, t;");
      expect(code).toContain("mtkcompile");
    });

    it("systems list matches node insertion order", () => {
      const nodes = [
        makeNode("a", "Pump", "pump_1", { dP_pump: 30000 }, "fixed-dP"),
        makeNode("b", "Channel", "ch_1", { n: 5, geometry: { type: "rectangular", L: 0.5, W: 0.01, H: 0.003 } }),
      ];
      const code = generateCode(nodes, [], NO_ANCHORS, mockGetComponent);
      expect(code).toContain("systems=[pump_1, ch_1]");
    });
  });

  describe("function param edge cases", () => {
    it("factory sub-param Function-type emits bare identifier", () => {
      const nodes = [makeNode("a", "Channel", "ch_1", {
        n: 5,
        geometry: { type: "rectangular", L: 0.5, W: 0.01, H: 0.003 },
        htc_correlation: {
          kind: "factory",
          value: "regime_dependent",
          subParams: {
            htc_forced: "dittus_boelter",
            htc_natural: "constant_Nusselt",
          },
        },
      })];
      const code = generateCode(nodes, [], NO_ANCHORS, mockGetComponent);
      expect(code).toContain("htc_forced=dittus_boelter");
      expect(code).toContain("htc_natural=constant_Nusselt");
      // Should NOT have quotes around function names
      expect(code).not.toContain('"dittus_boelter"');
      expect(code).not.toContain('"constant_Nusselt"');
    });

    it("factory sub-param default values are omitted", () => {
      const nodes = [makeNode("a", "Channel", "ch_1", {
        n: 5,
        geometry: { type: "rectangular", L: 0.5, W: 0.01, H: 0.003 },
        htc_correlation: {
          kind: "factory",
          value: "elenbaas_htc",
          subParams: { b: 0.003, L: 0.6, Dh: 0.0025, g: 9.80665 },
        },
      })];
      const code = generateCode(nodes, [], NO_ANCHORS, mockGetComponent);
      // g=9.80665 is the default for elenbaas_htc, should be omitted
      expect(code).not.toMatch(/elenbaas_htc\([^)]*g=/);
    });
  });

  // =========================================================================
  // Thermal code generation (Phase 40 Plan 02)
  // =========================================================================

  describe("thermal code generation", () => {
    // Shared HD params
    const hdParams = { nz: 5, nx: 3, Lz: 0.6, Lx: 0.001, y: 0.0015, k: 15.0, rho_s: 6500.0, cp_s: 300.0 };
    const cacParams = { n: 5, geometry: { type: "rectangular", L: 0.6, W: 0.066, H: 0.003 } };

    it("no thermal edges -> unchanged Phase 36 ODESystem format", () => {
      // Only flow edges, no thermal edges
      const nodes = [
        makeNode("p", "Pump", "pump_1", { dP_pump: 30000 }, "fixed-dP"),
        makeNode("c", "ChannelAndContacts", "cac_1", cacParams),
      ];
      const edges = [makeEdge("e1", "p", "port_out", "c", "port_in")];
      const code = generateCode(nodes, edges, NO_ANCHORS, mockGetComponent);
      expect(code).toContain("ODESystem(eqs, t;");
      expect(code).not.toContain("compose_systems");
      expect(code).not.toContain("symmetric_plate");
    });

    it("symmetric_plate -- one CAC wired both thermal sides to one HD", () => {
      const nodes = [
        makeNode("p", "Pump", "pump_1", { dP_pump: 30000 }, "fixed-dP"),
        makeNode("c", "ChannelAndContacts", "cac_1", cacParams),
        makeNode("h", "HeatDiffusion", "fuel_1", hdParams),
      ];
      // CAC.thermal_right -> HD.thermal_left AND CAC.thermal_left -> HD.thermal_right
      const edges = [
        makeEdge("e1", "p", "port_out", "c", "port_in"),
        makeEdge("e2", "c", "port_out", "p", "port_in"),
        makeEdge("t1", "c", "thermal_right", "h", "thermal_left"),
        makeEdge("t2", "c", "thermal_left", "h", "thermal_right"),
      ];
      const code = generateCode(nodes, edges, NO_ANCHORS, mockGetComponent);
      expect(code).toContain("symmetric_plate(cac_1, fuel_1)");
      expect(code).toContain("@named assembly_1");
      expect(code).not.toContain("ODESystem(eqs, t;");
    });

    it("plate -- two CACs each wired one side of one HD", () => {
      const nodes = [
        makeNode("p", "Pump", "pump_1", { dP_pump: 30000 }, "fixed-dP"),
        makeNode("c1", "ChannelAndContacts", "cac_left", cacParams),
        makeNode("c2", "ChannelAndContacts", "cac_right", cacParams),
        makeNode("h", "HeatDiffusion", "fuel_1", hdParams),
      ];
      // cac_left.thermal_right -> HD.thermal_left, cac_right.thermal_left -> HD.thermal_right
      const edges = [
        makeEdge("e1", "p", "port_out", "c1", "port_in"),
        makeEdge("e2", "c1", "port_out", "c2", "port_in"),
        makeEdge("e3", "c2", "port_out", "p", "port_in"),
        makeEdge("t1", "c1", "thermal_right", "h", "thermal_left"),
        makeEdge("t2", "c2", "thermal_left", "h", "thermal_right"),
      ];
      const code = generateCode(nodes, edges, NO_ANCHORS, mockGetComponent);
      expect(code).toContain("plate(cac_left, cac_right, fuel_1)");
      expect(code).toContain("@named assembly_1");
    });

    it("one_sided_connection (left) -- CAC.thermal_left -> HD.thermal_right", () => {
      const nodes = [
        makeNode("p", "Pump", "pump_1", { dP_pump: 30000 }, "fixed-dP"),
        makeNode("c", "ChannelAndContacts", "cac_1", cacParams),
        makeNode("h", "HeatDiffusion", "fuel_1", hdParams),
      ];
      const edges = [
        makeEdge("e1", "p", "port_out", "c", "port_in"),
        makeEdge("e2", "c", "port_out", "p", "port_in"),
        makeEdge("t1", "c", "thermal_left", "h", "thermal_right"),
      ];
      const code = generateCode(nodes, edges, NO_ANCHORS, mockGetComponent);
      expect(code).toContain("one_sided_connection(cac_1, fuel_1; side=:left)");
      expect(code).toContain("@named assembly_1");
    });

    it("one_sided_connection (right) -- CAC.thermal_right -> HD.thermal_left", () => {
      const nodes = [
        makeNode("p", "Pump", "pump_1", { dP_pump: 30000 }, "fixed-dP"),
        makeNode("c", "ChannelAndContacts", "cac_1", cacParams),
        makeNode("h", "HeatDiffusion", "fuel_1", hdParams),
      ];
      const edges = [
        makeEdge("e1", "p", "port_out", "c", "port_in"),
        makeEdge("e2", "c", "port_out", "p", "port_in"),
        makeEdge("t1", "c", "thermal_right", "h", "thermal_left"),
      ];
      const code = generateCode(nodes, edges, NO_ANCHORS, mockGetComponent);
      expect(code).toContain("one_sided_connection(cac_1, fuel_1; side=:right)");
      expect(code).toContain("@named assembly_1");
    });

    it("unknown topology -> emits TODO comment", () => {
      // Wire only one thermal port from HD to another HD (nonsensical)
      const nodes = [
        makeNode("h1", "HeatDiffusion", "fuel_1", hdParams),
        makeNode("h2", "HeatDiffusion", "fuel_2", hdParams),
      ];
      const edges = [
        makeEdge("t1", "h1", "thermal_right", "h2", "thermal_left"),
      ];
      const code = generateCode(nodes, edges, NO_ANCHORS, mockGetComponent);
      expect(code).toContain("# TODO: verify thermal wiring");
    });

    it("hydraulic connects use dotted assembly path when CAC is inside assembly", () => {
      const nodes = [
        makeNode("p", "Pump", "pump_1", { dP_pump: 30000 }, "fixed-dP"),
        makeNode("c", "ChannelAndContacts", "cac_1", cacParams),
        makeNode("h", "HeatDiffusion", "fuel_1", hdParams),
      ];
      const edges = [
        makeEdge("e1", "p", "port_out", "c", "port_in"),
        makeEdge("e2", "c", "port_out", "p", "port_in"),
        makeEdge("t1", "c", "thermal_right", "h", "thermal_left"),
        makeEdge("t2", "c", "thermal_left", "h", "thermal_right"),
      ];
      const code = generateCode(nodes, edges, NO_ANCHORS, mockGetComponent);
      // CAC is consumed into assembly_1, so hydraulic connects must use assembly path
      expect(code).toContain("assembly_1.cac_1.port_in");
      expect(code).toContain("assembly_1.cac_1.port_out");
    });

    it("top-level system uses compose_systems() when thermal assemblies exist", () => {
      const nodes = [
        makeNode("p", "Pump", "pump_1", { dP_pump: 30000 }, "fixed-dP"),
        makeNode("c", "ChannelAndContacts", "cac_1", cacParams),
        makeNode("h", "HeatDiffusion", "fuel_1", hdParams),
      ];
      const edges = [
        makeEdge("e1", "p", "port_out", "c", "port_in"),
        makeEdge("e2", "c", "port_out", "p", "port_in"),
        makeEdge("t1", "c", "thermal_right", "h", "thermal_left"),
        makeEdge("t2", "c", "thermal_left", "h", "thermal_right"),
      ];
      const code = generateCode(nodes, edges, NO_ANCHORS, mockGetComponent);
      expect(code).toContain("compose_systems(");
      expect(code).not.toContain("ODESystem(eqs, t;");
      expect(code).toContain("mtkcompile");
    });

    it("nz != n mismatch emits NOTE comment", () => {
      const nodes = [
        makeNode("p", "Pump", "pump_1", { dP_pump: 30000 }, "fixed-dP"),
        makeNode("c", "ChannelAndContacts", "cac_1", { ...cacParams, n: 5 }),
        makeNode("h", "HeatDiffusion", "fuel_1", { ...hdParams, nz: 10 }),
      ];
      const edges = [
        makeEdge("e1", "p", "port_out", "c", "port_in"),
        makeEdge("t1", "c", "thermal_right", "h", "thermal_left"),
        makeEdge("t2", "c", "thermal_left", "h", "thermal_right"),
      ];
      const code = generateCode(nodes, edges, NO_ANCHORS, mockGetComponent);
      expect(code).toContain("# NOTE: HeatDiffusion nz");
    });

    it("ConstantTemperature wired to ThermalPort emits per-cell connect calls", () => {
      const nodes = [
        makeNode("c", "ChannelAndContacts", "cac_1", cacParams),
        makeNode("ct", "ConstantTemperature", "ct_1", { T: 400.0 }),
      ];
      const edges = [
        makeEdge("t1", "ct", "thermal", "c", "thermal_left"),
      ];
      const code = generateCode(nodes, edges, NO_ANCHORS, mockGetComponent);
      // Should emit per-cell connect with port() helper
      expect(code).toContain("port(");
    });
  });
});

// ---------------------------------------------------------------------------
// Plan 63.1-14 (GAP-RC-4) — SourceValueEntry emission for WT.T_wall / HFS.q
//
// These tests use the LIVE registry (WallTemperature / HeatFluxSource) and
// confirm that generateCode emits the right Julia for each value mode.
// They are RED until Task 4 extends formatParamValue + adds sourceEmitPlan.
// ---------------------------------------------------------------------------
describe("codeGenerator — SourceValueEntry emission (Plan 14, GAP-RC-4)", () => {
  it("WallTemperature in value mode emits T_wall=<scalar>", () => {
    const wtComp = getComponent("WallTemperature")!;
    const node = makeNode("wt1", "WallTemperature", "wt1", {
      n: 4,
      T_wall: { mode: "value", value: 300 },
    });
    const code = generateCode([node], [], NO_ANCHORS, (id) =>
      id === "WallTemperature" ? wtComp : undefined
    );
    expect(code).toContain("WallTemperature(");
    expect(code).toContain("T_wall=300.0");
    expect(code).not.toContain("[object Object]");
  });

  it("WallTemperature in profile-cosine mode emits profile-var line above @named", () => {
    const wtComp = getComponent("WallTemperature")!;
    const node = makeNode("wt1", "WallTemperature", "wt1", {
      n: 4,
      T_wall: { mode: "profile", preset: "cosine", amplitude: 1.0, peakingFactor: 1.5 },
    });
    const code = generateCode([node], [], NO_ANCHORS, (id) =>
      id === "WallTemperature" ? wtComp : undefined
    );
    expect(code).toContain("wt1_T_wall_profile = cosine_T_wall_profile(4; amplitude=1.0, peaking_factor=1.5)");
    expect(code).toContain("T_wall=wt1_T_wall_profile");
  });

  it("WallTemperature in profile-file mode emits rebin_intensive line", () => {
    const wtComp = getComponent("WallTemperature")!;
    const node = makeNode("wt1", "WallTemperature", "wt1", {
      n: 4,
      T_wall: { mode: "profile", preset: "file", path: "wall.csv" },
    });
    const code = generateCode([node], [], NO_ANCHORS, (id) =>
      id === "WallTemperature" ? wtComp : undefined
    );
    expect(code).toContain('wt1_T_wall_profile = rebin_intensive(readdlm(joinpath(@__DIR__, "wall.csv"), \',\'), 4)');
    expect(code).toContain("T_wall=wt1_T_wall_profile");
  });

  it("WallTemperature in function mode (fn(t)) emits stub above @named", () => {
    const wtComp = getComponent("WallTemperature")!;
    const node = makeNode("wt1", "WallTemperature", "wt1", {
      n: 4,
      T_wall: { mode: "function", signature: "fn(t)", functionName: "my_T_wall" },
    });
    const code = generateCode([node], [], NO_ANCHORS, (id) =>
      id === "WallTemperature" ? wtComp : undefined
    );
    expect(code).toContain("my_T_wall(t) = 0.0");
    expect(code).toContain("T_wall=my_T_wall");
  });

  it("WallTemperature in function mode (fn(t, i)) emits stub with t, i arglist", () => {
    const wtComp = getComponent("WallTemperature")!;
    const node = makeNode("wt1", "WallTemperature", "wt1", {
      n: 4,
      T_wall: { mode: "function", signature: "fn(t, i)", functionName: "my_T_wall" },
    });
    const code = generateCode([node], [], NO_ANCHORS, (id) =>
      id === "WallTemperature" ? wtComp : undefined
    );
    expect(code).toContain("my_T_wall(t, i) = 0.0");
    expect(code).toContain("T_wall=my_T_wall");
  });

  it("HeatFluxSource in value mode emits q=<scalar>", () => {
    const hfsComp = getComponent("HeatFluxSource")!;
    const node = makeNode("hfs1", "HeatFluxSource", "hfs1", {
      n: 4,
      q: { mode: "value", value: 50000 },
    });
    const code = generateCode([node], [], NO_ANCHORS, (id) =>
      id === "HeatFluxSource" ? hfsComp : undefined
    );
    expect(code).toContain("HeatFluxSource(");
    expect(code).toContain("q=50000.0");
    expect(code).not.toContain("[object Object]");
  });

  it("HeatFluxSource in profile-cosine mode reuses cosine_T_wall_profile helper", () => {
    const hfsComp = getComponent("HeatFluxSource")!;
    const node = makeNode("hfs1", "HeatFluxSource", "hfs1", {
      n: 4,
      q: { mode: "profile", preset: "cosine", amplitude: 1e6, peakingFactor: 1.2 },
    });
    const code = generateCode([node], [], NO_ANCHORS, (id) =>
      id === "HeatFluxSource" ? hfsComp : undefined
    );
    // cosine_T_wall_profile is dimension-agnostic; reused for q (Plan 14 design decision (a))
    expect(code).toContain("hfs1_q_profile = cosine_T_wall_profile(4; amplitude=1000000.0, peaking_factor=1.2)");
    expect(code).toContain("q=hfs1_q_profile");
  });

  it("bare-number legacy T_wall still emits a numeric literal (back-compat tolerance)", () => {
    const wtComp = getComponent("WallTemperature")!;
    const node = makeNode("wt_legacy", "WallTemperature", "wt_legacy", {
      n: 4,
      T_wall: 300,  // bare number (pre-Plan-14 .streamgui shape)
    });
    const code = generateCode([node], [], NO_ANCHORS, (id) =>
      id === "WallTemperature" ? wtComp : undefined
    );
    expect(code).toContain("T_wall=300.0");
    expect(code).not.toContain("[object Object]");
  });
});
