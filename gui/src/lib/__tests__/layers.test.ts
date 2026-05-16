import { describe, it, expect } from "vitest";
import {
  ALL_LAYERS_ON,
  LAYER_KEYS,
  getComponentLayers,
  isNodeVisible,
  isEdgeDimmed,
} from "../layers";
import type { ActiveLayers, LayerKey } from "../layers";
import type { ComponentDefinition } from "../../registry/types";

// ---------------------------------------------------------------------------
// Fixture helpers
// ---------------------------------------------------------------------------
//
// The new 4-layer API derives layer membership from `ComponentDefinition.category`
// only — port types, parameters, and constructor modes are irrelevant. Fixtures
// are minimal `as ComponentDefinition` casts that set only the fields the API
// reads (`category`).
//
// Category strings are the registry values verbatim — see
// gui/src/registry/components.json (D-05 / CONTEXT decision: category is the
// source of truth).

function compWithCategory(category: string): ComponentDefinition {
  return {
    id: "fixture",
    label: "Fixture",
    category: category as ComponentDefinition["category"],
    description: "",
    ports: [],
    parameters: [],
    constructorModes: [],
  };
}

// Note: "Reactor Physics" has a space (registry value). The LayerKey form drops
// the space ("ReactorPhysics") so it can be used as a TypeScript identifier.
const hydraulicComp = compWithCategory("Hydraulic");
const thermalComp = compWithCategory("Thermal");
const sourcesComp = compWithCategory("Sources");
const reactorPhysicsComp = compWithCategory("Reactor Physics");
const resourcesComp = compWithCategory("Resources");
const unknownComp = compWithCategory("Unknown");

const ALL_OFF: ActiveLayers = {
  Hydraulic: false,
  Thermal: false,
  Sources: false,
  ReactorPhysics: false,
};

// ---------------------------------------------------------------------------
// ALL_LAYERS_ON
// ---------------------------------------------------------------------------

describe("ALL_LAYERS_ON", () => {
  it("Test 1: equals { Hydraulic: true, Thermal: true, Sources: true, ReactorPhysics: true }", () => {
    expect(ALL_LAYERS_ON).toEqual({
      Hydraulic: true,
      Thermal: true,
      Sources: true,
      ReactorPhysics: true,
    });
  });
});

// ---------------------------------------------------------------------------
// LAYER_KEYS (ordering contract for the LayersChip popover row order)
// ---------------------------------------------------------------------------

describe("LAYER_KEYS", () => {
  it("preserves the canonical ordering Hydraulic, Thermal, Sources, ReactorPhysics", () => {
    expect(LAYER_KEYS).toEqual([
      "Hydraulic",
      "Thermal",
      "Sources",
      "ReactorPhysics",
    ] as readonly LayerKey[]);
  });
});

// ---------------------------------------------------------------------------
// getComponentLayers
// ---------------------------------------------------------------------------

describe("getComponentLayers", () => {
  it("Test 2: category 'Hydraulic' → ['Hydraulic']", () => {
    expect(getComponentLayers(hydraulicComp)).toEqual(["Hydraulic"]);
  });

  it("Test 3: category 'Thermal' → ['Thermal']", () => {
    expect(getComponentLayers(thermalComp)).toEqual(["Thermal"]);
  });

  it("Test 4: category 'Sources' → ['Sources']", () => {
    expect(getComponentLayers(sourcesComp)).toEqual(["Sources"]);
  });

  it("Test 5: category 'Reactor Physics' (with space) → ['ReactorPhysics'] (no space)", () => {
    expect(getComponentLayers(reactorPhysicsComp)).toEqual(["ReactorPhysics"]);
  });

  it("Test 6: category 'Resources' → [] (excluded from layer system)", () => {
    expect(getComponentLayers(resourcesComp)).toEqual([]);
  });

  it("Test 7: unknown category → []", () => {
    expect(getComponentLayers(unknownComp)).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// isNodeVisible
// ---------------------------------------------------------------------------

describe("isNodeVisible", () => {
  it("Test 8: Hydraulic comp with { Hydraulic: true, ... } → true", () => {
    const active: ActiveLayers = { ...ALL_LAYERS_ON };
    expect(isNodeVisible(hydraulicComp, active)).toBe(true);
  });

  it("Test 9: Hydraulic comp with { Hydraulic: false, Thermal: true, Sources: true, ReactorPhysics: true } → false", () => {
    const active: ActiveLayers = {
      Hydraulic: false,
      Thermal: true,
      Sources: true,
      ReactorPhysics: true,
    };
    expect(isNodeVisible(hydraulicComp, active)).toBe(false);
  });

  it("Test 10: Thermal comp with { Thermal: false, ...rest true } → false", () => {
    const active: ActiveLayers = {
      Hydraulic: true,
      Thermal: false,
      Sources: true,
      ReactorPhysics: true,
    };
    expect(isNodeVisible(thermalComp, active)).toBe(false);
  });

  it("Test 11: Sources comp with { Sources: false, ...rest true } → false", () => {
    const active: ActiveLayers = {
      Hydraulic: true,
      Thermal: true,
      Sources: false,
      ReactorPhysics: true,
    };
    expect(isNodeVisible(sourcesComp, active)).toBe(false);
  });

  it("Test 12: Reactor Physics comp with { ReactorPhysics: false, ...rest true } → false", () => {
    const active: ActiveLayers = {
      Hydraulic: true,
      Thermal: true,
      Sources: true,
      ReactorPhysics: false,
    };
    expect(isNodeVisible(reactorPhysicsComp, active)).toBe(false);
  });

  it("Test 13: Resources comp (no layer) with all-off activeLayers → true (always visible)", () => {
    expect(isNodeVisible(resourcesComp, ALL_OFF)).toBe(true);
  });

  it("Test 14: Hydraulic comp with all layers off → false", () => {
    expect(isNodeVisible(hydraulicComp, ALL_OFF)).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// isEdgeDimmed
// ---------------------------------------------------------------------------

describe("isEdgeDimmed", () => {
  it("Test 15: isEdgeDimmed('Hydraulic', { Hydraulic: true, ... }) → false", () => {
    expect(isEdgeDimmed("Hydraulic", { ...ALL_LAYERS_ON })).toBe(false);
  });

  it("Test 16: isEdgeDimmed('Hydraulic', { Hydraulic: false, ... }) → true", () => {
    const active: ActiveLayers = { ...ALL_LAYERS_ON, Hydraulic: false };
    expect(isEdgeDimmed("Hydraulic", active)).toBe(true);
  });

  it("Test 17: isEdgeDimmed('Thermal', { Thermal: false, ...rest true }) → true", () => {
    const active: ActiveLayers = { ...ALL_LAYERS_ON, Thermal: false };
    expect(isEdgeDimmed("Thermal", active)).toBe(true);
  });

  it("Test 18: isEdgeDimmed(null, activeLayers) → false (edges with no layer association are never dimmed)", () => {
    expect(isEdgeDimmed(null, { ...ALL_LAYERS_ON })).toBe(false);
    expect(isEdgeDimmed(null, ALL_OFF)).toBe(false);
  });
});
