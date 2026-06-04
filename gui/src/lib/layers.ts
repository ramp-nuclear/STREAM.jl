// layers.ts -- Pure 4-layer independent-toggle API (Phase 68).
//
// Replaces the v0.8 three-mode API (`LayerView = "Hydraulic" | "Both" | "Thermal"`)
// per CONTEXT.md D-05. Layer membership is derived from
// `ComponentDefinition.category` (the registry value), not port-type sniffing —
// this handles Sources (BCPort) and Reactor Physics (no canvas ports) correctly.
//
// All functions are pure (no React, no Zustand, no DOM, no ReactFlow) and fully
// testable. Plan 02 wires these into `useStore`; Plans 03/04 wire them into
// CanvasPanel / LayersPanel.

import type { ComponentDefinition } from "../registry/types";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/**
 * The four canonical layer keys, in canonical UI ordering. Spaces in registry
 * category strings ("Reactor Physics") are dropped here so the key is a valid
 * TypeScript identifier — see `CATEGORY_TO_LAYER_KEY` for the registry-string
 * mapping.
 */
export type LayerKey = "Hydraulic" | "Thermal" | "Sources" | "ReactorPhysics";

/**
 * The active-layers state shape — one boolean per layer. Replaces the v0.8
 * `LayerView` union type per D-05. Persisted in `.scp` `layout.active_layers`
 * (see Plan 02 for the projectIO migration).
 */
export type ActiveLayers = Record<LayerKey, boolean>;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/**
 * Default active-layers state: all four layers on. Used as the seed for new
 * projects and as the fallback when migrating old `.scp` files that lack the
 * `active_layers` block.
 */
export const ALL_LAYERS_ON: ActiveLayers = {
  Hydraulic: true,
  Thermal: true,
  Sources: true,
  ReactorPhysics: true,
};

/**
 * Canonical ordering of layer keys for UI rows (LayersPanel rows). Frozen
 * `as const` tuple so consumers get a precise type.
 */
export const LAYER_KEYS: readonly LayerKey[] = [
  "Hydraulic",
  "Thermal",
  "Sources",
  "ReactorPhysics",
] as const;

/**
 * Registry `category` string → `LayerKey`. Internal — not exported. Note the
 * space in `"Reactor Physics"` (matches `gui/src/registry/components.json`
 * exactly). `"Resources"` is intentionally omitted — Resources (e.g.
 * ReactivityController) have no canvas presence, so they don't belong to any
 * layer.
 */
const CATEGORY_TO_LAYER_KEY: Partial<Record<string, LayerKey>> = {
  Hydraulic: "Hydraulic",
  Thermal: "Thermal",
  Sources: "Sources",
  "Reactor Physics": "ReactorPhysics",
};

// ---------------------------------------------------------------------------
// getComponentLayers
// ---------------------------------------------------------------------------

/**
 * The layer keys a component belongs to, derived from its registry `category`.
 *
 * - "Hydraulic"        → ["Hydraulic"]
 * - "Thermal"          → ["Thermal"]
 * - "Sources"          → ["Sources"]
 * - "Reactor Physics"  → ["ReactorPhysics"]
 * - "Resources"        → []  (no canvas presence — never participates in layers)
 * - unknown category   → []
 *
 * The return is an array (not a single key) to keep room for future
 * multi-layer components without breaking the signature; today every category
 * maps to exactly 0 or 1 layers.
 */
export function getComponentLayers(comp: ComponentDefinition): LayerKey[] {
  const key = CATEGORY_TO_LAYER_KEY[comp.category];
  return key !== undefined ? [key] : [];
}

// ---------------------------------------------------------------------------
// getDisplayLayers (Phase 72 — visual-only)
// ---------------------------------------------------------------------------

/**
 * Visual-only extension of `getComponentLayers` for surfaces that paint per-
 * layer identity (StreamNode leading band today). Returns all layers a
 * component visually participates in, including those derivable from port
 * composition but not from `category` alone.
 *
 * The canonical case: `ChannelAndContacts` has `category: "Hydraulic"` but
 * carries `ThermalPort` handles — visually it belongs to both layers, even
 * though for visibility/dim purposes it follows its category (Hydraulic).
 *
 * Behavioral functions (`isNodeVisible`, `isEdgeDimmed`, layer-aware connect,
 * the per-layer dim logic in StreamNode for dual-layer nodes) keep using
 * `getComponentLayers` to preserve current behavior. This function is *only*
 * for rendering layer-accent identity.
 *
 * Detection rule: a component has both `FlowPort` and `ThermalPort` → it's
 * visually on Hydraulic AND Thermal, in that left-to-right order for the
 * leading band's split rendering.
 */
export function getDisplayLayers(comp: ComponentDefinition): LayerKey[] {
  const base = getComponentLayers(comp);
  const hasFlow = comp.ports.some((p) => p.type === "FlowPort");
  const hasThermal = comp.ports.some((p) => p.type === "ThermalPort");
  if (hasFlow && hasThermal) {
    const result = [...base];
    if (!result.includes("Hydraulic")) result.unshift("Hydraulic");
    if (!result.includes("Thermal")) result.push("Thermal");
    return result;
  }
  return base;
}

// ---------------------------------------------------------------------------
// isNodeVisible
// ---------------------------------------------------------------------------

/**
 * Whether a canvas node should be visible given the current per-layer toggles.
 *
 * D-02 rule: a component is visible if **any** of its layers is active. A
 * component with no layer association (e.g. Resources — `getComponentLayers`
 * returns `[]`) is always visible; the layer system simply doesn't apply to it.
 *
 * Used by `CanvasPanel`'s per-node enrichment pass (Plan 03) to set the
 * `hidden` ReactFlow prop in hide mode, or as the input to the dim/lock pass
 * in dim mode.
 */
export function isNodeVisible(
  comp: ComponentDefinition,
  activeLayers: ActiveLayers,
): boolean {
  const layers = getComponentLayers(comp);
  if (layers.length === 0) return true;
  return layers.some((k) => activeLayers[k]);
}

// ---------------------------------------------------------------------------
// isEdgeDimmed
// ---------------------------------------------------------------------------

/**
 * Whether an edge should be dimmed given its layer association and the current
 * per-layer toggles.
 *
 * Edges follow **their own layer**, not their endpoints' layers (D-04). The
 * caller is responsible for resolving each edge's `LayerKey` (e.g. by checking
 * the port type of the source/target handle) — pass `null` for edges that have
 * no layer association (e.g. virtual reactivity-controller links), which are
 * never dimmed.
 */
export function isEdgeDimmed(
  edgeLayerKey: LayerKey | null,
  activeLayers: ActiveLayers,
): boolean {
  if (!edgeLayerKey) return false;
  return !activeLayers[edgeLayerKey];
}
