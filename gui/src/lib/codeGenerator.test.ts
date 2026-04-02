// codeGenerator.test.ts -- Unit tests for STREAM.jl code generation from canvas state

import { describe, it, expect } from "vitest";
import { generateCode, BCEntry } from "./codeGenerator";
import type { ComponentDefinition, Parameter, FunctionOption } from "../registry/types";
import type { Node, Edge } from "@xyflow/react";

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

const componentMap: Record<string, ComponentDefinition> = {
  Pump: pumpDef,
  Channel: channelDef,
  HeatExchanger: heatExDef,
  Gravity: gravityDef,
  Resistor: resistorDef,
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
      const result = generateCode([], [], [], mockGetComponent);
      expect(result).toBe("# Add components to the canvas to generate Julia code.");
    });
  });

  describe("component declarations", () => {
    it("emits Pump fixed-dP with positional arg", () => {
      const nodes = [makeNode("a", "Pump", "pump_1", { dP_pump: 30000 }, "fixed-dP")];
      const code = generateCode(nodes, [], [], mockGetComponent);
      expect(code).toContain("@named pump_1 = Pump(30000.0)");
    });

    it("emits Pump fixed-mdot with keyword-only (semicolon)", () => {
      const nodes = [makeNode("a", "Pump", "pump_1", { mdot0: 0.5 }, "fixed-mdot")];
      const code = generateCode(nodes, [], [], mockGetComponent);
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
      const code = generateCode(nodes, [], [], mockGetComponent);
      expect(code).toContain("@named ch_1 = Channel(; n=5, geometry=PipeGeometry_rectangular(0.5, 0.01, 0.003))");
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
      const code = generateCode(nodes, [], [], mockGetComponent);
      expect(code).toContain("htc_correlation=constant_Nusselt");
    });

    it("emits factory htc_correlation (elenbaas_htc)", () => {
      const nodes = [makeNode("a", "Channel", "ch_1", {
        n: 5,
        geometry: { type: "rectangular", L: 0.5, W: 0.01, H: 0.003 },
        htc_correlation: { kind: "factory", value: "elenbaas_htc", subParams: { b: 0.003, L: 0.6, Dh: 0.0025, g: 9.80665 } },
      })];
      const code = generateCode(nodes, [], [], mockGetComponent);
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
      const code = generateCode(nodes, [], [], mockGetComponent);
      // threshold=1.0 is default, should be omitted
      expect(code).toContain("htc_correlation=regime_dependent(htc_forced=dittus_boelter, htc_natural=elenbaas_htc(b=0.003, L=0.6, Dh=0.0025))");
    });

    it("emits HeatExchanger with positional arg", () => {
      const nodes = [makeNode("a", "HeatExchanger", "hx_1", { T_bc: 300 })];
      const code = generateCode(nodes, [], [], mockGetComponent);
      expect(code).toContain("@named hx_1 = HeatExchanger(300.0)");
    });

    it("emits Gravity with positional arg", () => {
      const nodes = [makeNode("a", "Gravity", "grav_1", { H: 0.5 })];
      const code = generateCode(nodes, [], [], mockGetComponent);
      expect(code).toContain("@named grav_1 = Gravity(0.5)");
    });

    it("emits Resistor with positional arg", () => {
      const nodes = [makeNode("a", "Resistor", "res_1", { R: 1000 })];
      const code = generateCode(nodes, [], [], mockGetComponent);
      expect(code).toContain("@named res_1 = Resistor(1000.0)");
    });

    it("emits PipeGeometry_circular for circular geometry", () => {
      const nodes = [makeNode("a", "Channel", "ch_1", {
        n: 5,
        geometry: { type: "circular", L: 0.5, D: 0.01 },
      })];
      const code = generateCode(nodes, [], [], mockGetComponent);
      expect(code).toContain("geometry=PipeGeometry_circular(0.5, 0.01)");
    });
  });

  describe("value formatting", () => {
    it("formats Int without decimal", () => {
      const nodes = [makeNode("a", "Channel", "ch_1", {
        n: 5,
        geometry: { type: "rectangular", L: 0.5, W: 0.01, H: 0.003 },
      })];
      const code = generateCode(nodes, [], [], mockGetComponent);
      expect(code).toContain("n=5,");
      expect(code).not.toContain("n=5.0");
    });

    it("formats integer Real with .0", () => {
      const nodes = [makeNode("a", "Pump", "pump_1", { dP_pump: 100 }, "fixed-dP")];
      const code = generateCode(nodes, [], [], mockGetComponent);
      expect(code).toContain("Pump(100.0)");
    });

    it("formats Real with existing decimal as-is", () => {
      const nodes = [makeNode("a", "Pump", "pump_1", { dP_pump: 0.5 }, "fixed-dP")];
      const code = generateCode(nodes, [], [], mockGetComponent);
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
      const code = generateCode(nodes, edges, [], mockGetComponent);
      expect(code).toContain("connect(pump_1.port_out, ch_1.port_in)");
    });
  });

  describe("boundary conditions", () => {
    it("emits BC as equation", () => {
      const nodes = [makeNode("abc", "Pump", "pump_1", { dP_pump: 30000 }, "fixed-dP")];
      const bcs: BCEntry[] = [{ nodeId: "abc", portField: "port_in.P", value: 100000 }];
      const code = generateCode(nodes, [], bcs, mockGetComponent);
      expect(code).toMatch(/pump_1\.port_in\.P\s*~\s*1(\.0)?e5|100000\.0/);
    });

    it("skips BC for deleted node", () => {
      const nodes = [makeNode("abc", "Pump", "pump_1", { dP_pump: 30000 }, "fixed-dP")];
      const bcs: BCEntry[] = [{ nodeId: "deleted_id", portField: "port_in.P", value: 100000 }];
      const code = generateCode(nodes, [], bcs, mockGetComponent);
      // Should not contain a BC line for deleted_id
      expect(code).not.toContain("deleted_id");
    });
  });

  describe("identifier validation", () => {
    it("warns for invalid instanceName", () => {
      const nodes = [makeNode("a", "Pump", "my pump", { dP_pump: 30000 }, "fixed-dP")];
      const code = generateCode(nodes, [], [], mockGetComponent);
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
      const code = generateCode(nodes, edges, [], mockGetComponent);

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
      const code = generateCode(nodes, [], [], mockGetComponent);
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
      const code = generateCode(nodes, [], [], mockGetComponent);
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
      const code = generateCode(nodes, [], [], mockGetComponent);
      // g=9.80665 is the default for elenbaas_htc, should be omitted
      expect(code).not.toMatch(/elenbaas_htc\([^)]*g=/);
    });
  });
});
