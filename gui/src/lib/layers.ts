// layers.ts -- Pure layer detection utilities for the layered canvas feature.
//
// All functions are pure (no DOM, no React, no store) and fully testable.
// Plan 02 wires these into UI components.

import type { ComponentDefinition } from "../registry/types";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type LayerView = "Hydraulic" | "Both" | "Thermal";

// ---------------------------------------------------------------------------
// getComponentLayers
// ---------------------------------------------------------------------------

/**
 * Determine which layers a component belongs to based on its port types.
 *
 * A component with at least one FlowPort is on the hydraulic layer.
 * A component with at least one ThermalPort is on the thermal layer.
 * Components like ChannelAndContacts have both.
 */
export function getComponentLayers(comp: ComponentDefinition): {
  hasFlow: boolean;
  hasThermal: boolean;
} {
  return {
    hasFlow: comp.ports.some((p) => p.type === "FlowPort"),
    hasThermal: comp.ports.some((p) => p.type === "ThermalPort"),
  };
}

// ---------------------------------------------------------------------------
// isComponentVisibleInLayer
// ---------------------------------------------------------------------------

/**
 * Whether a component should be visible (not hidden) in the given layer view.
 *
 * - "Both" view: everything is visible.
 * - "Hydraulic" view: only components with FlowPorts.
 * - "Thermal" view: only components with ThermalPorts.
 */
export function isComponentVisibleInLayer(
  comp: ComponentDefinition,
  activeLayer: LayerView,
): boolean {
  if (activeLayer === "Both") return true;
  const layers = getComponentLayers(comp);
  if (activeLayer === "Hydraulic") return layers.hasFlow;
  return layers.hasThermal;
}

// ---------------------------------------------------------------------------
// isNodeDimmed
// ---------------------------------------------------------------------------

/**
 * Whether a canvas node should be visually dimmed in the current layer view.
 *
 * Rules (per D-01/D-02/D-06):
 * - "Both" view: nothing is dimmed.
 * - Dual-layer nodes (both FlowPort and ThermalPort) are never fully dimmed.
 * - Single-layer nodes are dimmed when viewing the opposite layer.
 */
export function isNodeDimmed(
  componentId: string,
  activeLayer: LayerView,
  getComp: (id: string) => ComponentDefinition | undefined,
): boolean {
  if (activeLayer === "Both") return false;
  const comp = getComp(componentId);
  if (!comp) return false;
  const layers = getComponentLayers(comp);
  // Dual-layer components are never fully dimmed
  if (layers.hasFlow && layers.hasThermal) return false;
  if (activeLayer === "Hydraulic") return !layers.hasFlow;
  return !layers.hasThermal;
}

// ---------------------------------------------------------------------------
// isEdgeDimmed
// ---------------------------------------------------------------------------

/**
 * Whether a canvas edge should be visually dimmed in the current layer view.
 *
 * The caller determines `edgeIsThermal` (e.g. by checking amber stroke style).
 * This keeps the utility pure -- no ReactFlow edge type knowledge here.
 *
 * - "Both" view: nothing is dimmed.
 * - "Hydraulic" view: thermal edges are dimmed.
 * - "Thermal" view: flow edges are dimmed.
 */
export function isEdgeDimmed(
  edgeIsThermal: boolean,
  activeLayer: LayerView,
): boolean {
  if (activeLayer === "Both") return false;
  if (activeLayer === "Hydraulic") return edgeIsThermal;
  return !edgeIsThermal;
}
