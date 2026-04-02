import { describe, it, expect } from "vitest";
import {
  COMPONENT_ICONS,
  FALLBACK_ICON,
  getComponentIcon,
  CATEGORY_BORDER_CLASSES,
  getCategoryBorderClass,
} from "../icons";

const EXPECTED_COMPONENT_IDS = [
  "Channel",
  "ChannelAndContacts",
  "ChannelHeatFlux",
  "Pump",
  "Flapper",
  "Friction",
  "Gravity",
  "Resistor",
  "Inertia",
  "HeatExchanger",
  "ConstantTemperature",
  "HeatDiffusion",
];

describe("COMPONENT_ICONS", () => {
  it("has entries for all 12 component IDs", () => {
    const keys = Object.keys(COMPONENT_ICONS);
    expect(keys.sort()).toEqual([...EXPECTED_COMPONENT_IDS].sort());
  });

  it("has exactly 12 entries", () => {
    expect(Object.keys(COMPONENT_ICONS)).toHaveLength(12);
  });
});

describe("getComponentIcon", () => {
  it("returns the mapped icon for a known component", () => {
    const icon = getComponentIcon("Channel");
    expect(icon).toBeDefined();
    expect(icon).not.toBe(FALLBACK_ICON);
  });

  it("returns FALLBACK_ICON for an unknown component", () => {
    expect(getComponentIcon("unknown")).toBe(FALLBACK_ICON);
  });
});

describe("CATEGORY_BORDER_CLASSES", () => {
  it("maps Hydraulic to border-l-blue-500", () => {
    expect(CATEGORY_BORDER_CLASSES["Hydraulic"]).toBe("border-l-blue-500");
  });

  it("maps Thermal to border-l-amber-500", () => {
    expect(CATEGORY_BORDER_CLASSES["Thermal"]).toBe("border-l-amber-500");
  });
});

describe("getCategoryBorderClass", () => {
  it("returns border class for Hydraulic", () => {
    expect(getCategoryBorderClass("Hydraulic")).toBe("border-l-blue-500");
  });

  it("returns border class for Thermal", () => {
    expect(getCategoryBorderClass("Thermal")).toBe("border-l-amber-500");
  });

  it("returns empty string for unknown category", () => {
    expect(getCategoryBorderClass("unknown")).toBe("");
  });
});
