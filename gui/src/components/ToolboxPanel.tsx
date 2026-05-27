import ToolboxItem from "./ToolboxItem";
import { SectionHeader } from "./ui/section-header";
import { getComponentsByCategory } from "../registry";

// Phase 62 D-02 — ToolboxPanel is now rendered inside the left-panel Tabs
// `<TabsContent value="Components">` wrapper in App.tsx. The wrapper supplies
// width, the resize handle, the right border, and the outer height; this
// component renders the inner scrollable content only.
//
// Phase 63.1 D-06 — value-sources (WallTemperature, HeatFluxSource) were
// removed from the toolbox in 63.1 because promoteToSharedSource (Plan 08)
// was the only intended spawn path. Phase 65 UAT 2026-05-15: user reverted
// that decision — direct drag works fine in practice. Sources category is
// re-surfaced as a drag-from-toolbox affordance. promoteToSharedSource
// remains the canonical seed path for the type_union → Source promotion
// flow, but is no longer the only path.
//
// Phase 68 Plan 03 D-11 — the toolbox is a stable drag palette: every
// registry-listed draggable component appears regardless of `activeLayers`
// state. The previous per-category `isComponentVisibleInLayer` filter is
// gone; the canvas (not the toolbox) is where layer toggles surface their
// effect. Category headings are preserved purely as rendering structure.

export default function ToolboxPanel() {
  const hydraulicComponents = getComponentsByCategory("Hydraulic");
  const thermalComponents = getComponentsByCategory("Thermal");
  const sourceComponents = getComponentsByCategory("Sources");

  return (
    <div className="h-full p-2 overflow-y-auto min-w-0">
      {hydraulicComponents.length > 0 && (
        <>
          <SectionHeader className="px-2 mb-1 mt-2">Hydraulic</SectionHeader>
          <div className="space-y-px">
            {hydraulicComponents.map((comp) => (
              <ToolboxItem
                key={comp.id}
                componentId={comp.id}
                label={comp.label}
              />
            ))}
          </div>
        </>
      )}

      {thermalComponents.length > 0 && (
        <>
          <SectionHeader className="px-2 mb-1 mt-3">Thermal</SectionHeader>
          <div className="space-y-px">
            {thermalComponents.map((comp) => (
              <ToolboxItem
                key={comp.id}
                componentId={comp.id}
                label={comp.label}
              />
            ))}
          </div>
        </>
      )}

      {sourceComponents.length > 0 && (
        <>
          <SectionHeader className="px-2 mb-1 mt-3">Sources</SectionHeader>
          <div className="space-y-px">
            {sourceComponents.map((comp) => (
              <ToolboxItem
                key={comp.id}
                componentId={comp.id}
                label={comp.label}
              />
            ))}
          </div>
        </>
      )}
    </div>
  );
}
