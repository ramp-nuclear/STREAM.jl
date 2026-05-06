import { describe, it, expect } from "vitest";
import {
  getComponentLayers,
  isComponentVisibleInLayer,
  isNodeDimmed,
  isEdgeDimmed,
} from "../layers";
import type { ComponentDefinition } from "../../registry/types";
import type { LayerView } from "../layers";

// ---------------------------------------------------------------------------
// Mock component helpers
// ---------------------------------------------------------------------------

function makeComp(
  ports: Array<{ name: string; type: "FlowPort" | "ThermalPort"; side: "left" | "right" }>,
): ComponentDefinition {
  return {
    id: "test",
    label: "Test",
    category: "Hydraulic",
    description: "",
    ports: ports.map((p) => ({ ...p })),
    parameters: [],
    constructorModes: [],
  };
}

const hydraulicOnly = makeComp([
  { name: "inlet", type: "FlowPort", side: "left" },
  { name: "outlet", type: "FlowPort", side: "right" },
]);

const thermalOnly = makeComp([
  { name: "thermal_left", type: "ThermalPort", side: "left" },
  { name: "thermal_right", type: "ThermalPort", side: "right" },
]);

const dualLayer = makeComp([
  { name: "inlet", type: "FlowPort", side: "left" },
  { name: "outlet", type: "FlowPort", side: "right" },
  { name: "thermal_left", type: "ThermalPort", side: "left" },
  { name: "thermal_right", type: "ThermalPort", side: "right" },
]);

// ---------------------------------------------------------------------------
// getComponentLayers
// ---------------------------------------------------------------------------

describe("getComponentLayers", () => {
  it("returns hasFlow=true, hasThermal=false for hydraulic-only component", () => {
    const layers = getComponentLayers(hydraulicOnly);
    expect(layers).toEqual({ hasFlow: true, hasThermal: false });
  });

  it("returns hasFlow=false, hasThermal=true for thermal-only component", () => {
    const layers = getComponentLayers(thermalOnly);
    expect(layers).toEqual({ hasFlow: false, hasThermal: true });
  });

  it("returns hasFlow=true, hasThermal=true for dual-layer component", () => {
    const layers = getComponentLayers(dualLayer);
    expect(layers).toEqual({ hasFlow: true, hasThermal: true });
  });

  it("returns hasFlow=false, hasThermal=false for component with no ports", () => {
    const noPortComp = makeComp([]);
    const layers = getComponentLayers(noPortComp);
    expect(layers).toEqual({ hasFlow: false, hasThermal: false });
  });
});

// ---------------------------------------------------------------------------
// isComponentVisibleInLayer
// ---------------------------------------------------------------------------

describe("isComponentVisibleInLayer", () => {
  const cases: Array<{ comp: ComponentDefinition; label: string; layer: LayerView; expected: boolean }> = [
    // Both view: all visible
    { comp: hydraulicOnly, label: "hydraulic-only", layer: "Both", expected: true },
    { comp: thermalOnly, label: "thermal-only", layer: "Both", expected: true },
    { comp: dualLayer, label: "dual-layer", layer: "Both", expected: true },
    // Hydraulic view
    { comp: hydraulicOnly, label: "hydraulic-only", layer: "Hydraulic", expected: true },
    { comp: thermalOnly, label: "thermal-only", layer: "Hydraulic", expected: false },
    { comp: dualLayer, label: "dual-layer", layer: "Hydraulic", expected: true },
    // Thermal view
    { comp: hydraulicOnly, label: "hydraulic-only", layer: "Thermal", expected: false },
    { comp: thermalOnly, label: "thermal-only", layer: "Thermal", expected: true },
    { comp: dualLayer, label: "dual-layer", layer: "Thermal", expected: true },
  ];

  for (const { comp, label, layer, expected } of cases) {
    it(`${label} in ${layer} view returns ${expected}`, () => {
      expect(isComponentVisibleInLayer(comp, layer)).toBe(expected);
    });
  }
});

// ---------------------------------------------------------------------------
// isNodeDimmed
// ---------------------------------------------------------------------------

describe("isNodeDimmed", () => {
  const compMap: Record<string, ComponentDefinition> = {
    Pump: hydraulicOnly,
    HeatDiffusion: thermalOnly,
    ChannelAndContacts: dualLayer,
  };
  const getComp = (id: string) => compMap[id];

  it("dual-layer node is never dimmed in Both view", () => {
    expect(isNodeDimmed("ChannelAndContacts", "Both", getComp)).toBe(false);
  });

  it("dual-layer node is never dimmed in Hydraulic view", () => {
    expect(isNodeDimmed("ChannelAndContacts", "Hydraulic", getComp)).toBe(false);
  });

  it("dual-layer node is never dimmed in Thermal view", () => {
    expect(isNodeDimmed("ChannelAndContacts", "Thermal", getComp)).toBe(false);
  });

  it("hydraulic-only node is not dimmed in Hydraulic view", () => {
    expect(isNodeDimmed("Pump", "Hydraulic", getComp)).toBe(false);
  });

  it("hydraulic-only node is not dimmed in Both view", () => {
    expect(isNodeDimmed("Pump", "Both", getComp)).toBe(false);
  });

  it("hydraulic-only node is dimmed in Thermal view", () => {
    expect(isNodeDimmed("Pump", "Thermal", getComp)).toBe(true);
  });

  it("thermal-only node is not dimmed in Thermal view", () => {
    expect(isNodeDimmed("HeatDiffusion", "Thermal", getComp)).toBe(false);
  });

  it("thermal-only node is not dimmed in Both view", () => {
    expect(isNodeDimmed("HeatDiffusion", "Both", getComp)).toBe(false);
  });

  it("thermal-only node is dimmed in Hydraulic view", () => {
    expect(isNodeDimmed("HeatDiffusion", "Hydraulic", getComp)).toBe(true);
  });

  it("returns false for unknown component", () => {
    expect(isNodeDimmed("NonExistent", "Hydraulic", getComp)).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// isEdgeDimmed
// ---------------------------------------------------------------------------

describe("isEdgeDimmed", () => {
  it("thermal edge is not dimmed in Both view", () => {
    expect(isEdgeDimmed(true, "Both")).toBe(false);
  });

  it("flow edge is not dimmed in Both view", () => {
    expect(isEdgeDimmed(false, "Both")).toBe(false);
  });

  it("thermal edge is dimmed in Hydraulic view", () => {
    expect(isEdgeDimmed(true, "Hydraulic")).toBe(true);
  });

  it("flow edge is not dimmed in Hydraulic view", () => {
    expect(isEdgeDimmed(false, "Hydraulic")).toBe(false);
  });

  it("thermal edge is not dimmed in Thermal view", () => {
    expect(isEdgeDimmed(true, "Thermal")).toBe(false);
  });

  it("flow edge is dimmed in Thermal view", () => {
    expect(isEdgeDimmed(false, "Thermal")).toBe(true);
  });
});
