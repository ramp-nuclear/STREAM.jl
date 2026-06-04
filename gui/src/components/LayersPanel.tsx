// LayersPanel.tsx — Phase 68 (final, replaces LayersChip after UAT 2026-05-17)
//
// Always-visible docked layer panel mounted at the bottom of the left sidebar,
// below the Components / Resources / Project tabs. Stays visible regardless
// of which tab is active. Mirrors the docked-layer-panel pattern used by
// real engineering tools (Blender collection panel, QGIS layers panel,
// AutoCAD layer manager).
//
// Surface contract:
//   - Section header "LAYERS" (matches the existing HYDRAULIC / THERMAL /
//     SOURCES group headers in the Components tab — uppercase muted label).
//   - 4 click-rows in LAYER_KEYS canonical order. Each row: color dot + full
//     layer name + Eye/EyeOff icon (visibility metaphor universal across
//     Figma/Photoshop/Blender). Click anywhere on the row to toggle.
//
// Phase 72 Preferences — the Off-layer Dim/Hide toggle that previously lived
// here as a footer row has moved to `Edit > Preferences > Editor > Off-layer
// behavior` (it was always meant to be a user preference, not a per-project
// layout setting). The pref also moved from per-project to user-global; the
// .scp `layout.hide_off_layer` field is now ignored on load.
//
// Replaces the canvas-overlay LayersChip from Plan 04. UAT feedback:
//   - icon-only trigger in the overlay column was illegible
//   - color-only state encoding failed colorblind users
//   - users couldn't remember which color was which layer
//
// Three candidates were prototyped in parallel; this docked-sidebar pattern
// won on full-name legibility + Eye/EyeOff icon as a colorblind-safe
// secondary signal + zero canvas-overlay chrome.

import { Eye, EyeOff } from "lucide-react";
import { LAYER_KEYS, type LayerKey } from "../lib/layers";
import { LAYER_COLOR_VAR } from "../lib/layerColors";
import { SectionHeader } from "./ui/section-header";
import useStore from "../store/useStore";
import { cn } from "../lib/utils";

// Layer accents are CSS var() expressions; values live in index.css under
// --color-layer-*. See lib/layerColors.ts for the single-source-of-truth
// mapping (Phase 72 — resolves the audit's P0-4 duplicated-hex finding).

const LAYER_LABELS: Record<LayerKey, string> = {
  Hydraulic: "Hydraulic",
  Thermal: "Thermal",
  Sources: "Sources",
  ReactorPhysics: "Reactor Physics",
};

export default function LayersPanel() {
  const activeLayers = useStore((s) => s.activeLayers);
  const toggleLayer = useStore((s) => s.toggleLayer);
  // Phase 72 — disable layer toggles when no project is open. Layer
  // visibility only affects canvas rendering; with no nodes there's
  // nothing to toggle. Boolean primitive selector, value-equality.
  const noProjectVisible = useStore(
    (s) =>
      s.nodes.length === 0 && s.edges.length === 0 && !s.welcomeDismissed,
  );

  return (
    <div data-testid="layers-panel" className="border-t bg-panel shrink-0">
      <SectionHeader className="px-3 pt-2 pb-1">Layers</SectionHeader>
      <div className="flex flex-col px-1 pb-1">
        {LAYER_KEYS.map((key) => {
          const on = activeLayers[key];
          return (
            <button
              key={key}
              type="button"
              role="switch"
              aria-checked={on}
              aria-label={`${LAYER_LABELS[key]} layer`}
              data-testid={`layer-row-${key}`}
              onClick={() => toggleLayer(key)}
              disabled={noProjectVisible}
              className={cn(
                "flex items-center gap-2 px-2 py-1.5 rounded-sm text-left text-[13px] transition-colors",
                "hover:bg-accent hover:text-accent-foreground",
                "focus:outline-none focus-visible:bg-accent focus-visible:text-accent-foreground",
                "disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:bg-transparent disabled:hover:text-current",
              )}
            >
              <span
                aria-hidden="true"
                data-testid={`layer-dot-${key}`}
                className="w-2.5 h-2.5 rounded-full inline-block shrink-0 transition-opacity"
                style={{
                  backgroundColor: LAYER_COLOR_VAR[key],
                  opacity: on ? 1 : 0.25,
                }}
              />
              <span
                className={cn(
                  "flex-1 select-none transition-opacity",
                  on ? "opacity-100" : "opacity-50",
                )}
              >
                {LAYER_LABELS[key]}
              </span>
              {on ? (
                <Eye
                  data-testid={`layer-eye-${key}`}
                  className="h-3.5 w-3.5 text-muted-foreground shrink-0"
                  aria-hidden="true"
                />
              ) : (
                <EyeOff
                  data-testid={`layer-eye-off-${key}`}
                  className="h-3.5 w-3.5 text-muted-foreground shrink-0 opacity-50"
                  aria-hidden="true"
                />
              )}
            </button>
          );
        })}
      </div>
    </div>
  );
}
