// Single source of truth for layer-accent colors. Each LayerKey maps to a
// CSS custom property declared in index.css (--color-layer-*). Consumed by
// LayersPanel (dot indicators), StreamNode (leading band), and any future
// surface that signals layer membership visually.
//
// The values are CSS var() expressions, not raw hex — this lets dark/light
// mode swap automatically and keeps the palette tokenized. Resolves audit
// finding P0-4 (layer accent hex previously duplicated across 3 files).
//
// Phase 72 canvas shape, commit 2/5.

import type { LayerKey } from "./layers";

export const LAYER_COLOR_VAR: Record<LayerKey, string> = {
  Hydraulic: "var(--color-layer-hydraulic)",
  Thermal: "var(--color-layer-thermal)",
  Sources: "var(--color-layer-sources)",
  ReactorPhysics: "var(--color-layer-reactor-physics)",
};
