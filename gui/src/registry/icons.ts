// icons.ts — Single source of truth for component icons and category colors
//
// Used by StreamNode (canvas) and ToolboxItem (toolbox panel) to render
// consistent visual identity per component type.

import type { LucideIcon } from "lucide-react";
import {
  RectangleHorizontal,
  Layers,
  Flame,
  Gauge,
  ToggleRight,
  Slash,
  ArrowDown,
  Minus,
  Weight,
  Thermometer,
  ThermometerSun,
  Grid3x3,
  Box,
} from "lucide-react";

/**
 * Maps each STREAM component ID to its Lucide icon.
 *
 * Keep in sync with gui/src/registry/components.json.
 */
export const COMPONENT_ICONS: Record<string, LucideIcon> = {
  Channel: RectangleHorizontal,
  ChannelAndContacts: Layers,
  ChannelHeatFlux: Flame,
  Pump: Gauge,
  Flapper: ToggleRight,
  Friction: Slash,
  Gravity: ArrowDown,
  Resistor: Minus,
  Inertia: Weight,
  HeatExchanger: Thermometer,
  ConstantTemperature: ThermometerSun,
  HeatDiffusion: Grid3x3,
};

/** Fallback icon for unknown component types. */
export const FALLBACK_ICON: LucideIcon = Box;

/**
 * Returns the Lucide icon for a given component ID.
 * Falls back to Box if the component ID is not in the map.
 */
export function getComponentIcon(componentId: string): LucideIcon {
  return COMPONENT_ICONS[componentId] ?? FALLBACK_ICON;
}

/**
 * Maps component categories to Tailwind border-left classes.
 *
 * IMPORTANT: These must be full literal strings, never dynamically
 * constructed, because Tailwind JIT scans source for complete class names.
 */
export const CATEGORY_BORDER_CLASSES: Record<string, string> = {
  Hydraulic: "border-l-blue-500",
  Thermal: "border-l-amber-500",
};

/**
 * Returns the Tailwind border-left class for a component category.
 * Returns empty string for unknown categories.
 */
export function getCategoryBorderClass(category: string): string {
  return CATEGORY_BORDER_CLASSES[category] ?? "";
}
