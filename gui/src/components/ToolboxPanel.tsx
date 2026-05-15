import ToolboxItem from "./ToolboxItem";
import { getComponentsByCategory } from "../registry";
import useStore from "../store/useStore";
import { isComponentVisibleInLayer } from "../lib/layers";

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

export default function ToolboxPanel() {
  const activeLayer = useStore((s) => s.activeLayer);
  const hydraulicComponents = getComponentsByCategory("Hydraulic");
  const thermalComponents = getComponentsByCategory("Thermal");
  const sourceComponents = getComponentsByCategory("Sources");

  const visibleHydraulic = hydraulicComponents.filter(comp =>
    isComponentVisibleInLayer(comp, activeLayer)
  );
  const visibleThermal = thermalComponents.filter(comp =>
    isComponentVisibleInLayer(comp, activeLayer)
  );
  // Value-sources carry only BCPorts and are not gated on the active layer.
  const visibleSources = sourceComponents;

  return (
    <div className="h-full p-2 overflow-y-auto min-w-0">
      {visibleHydraulic.length > 0 && (
        <>
          <div className="text-xs font-semibold uppercase tracking-wide text-muted-foreground px-2 mb-1 mt-2">
            Hydraulic
          </div>
          <div className="space-y-px">
            {visibleHydraulic.map((comp) => (
              <ToolboxItem
                key={comp.id}
                componentId={comp.id}
                label={comp.label}
              />
            ))}
          </div>
        </>
      )}

      {visibleThermal.length > 0 && (
        <>
          <div className="text-xs font-semibold uppercase tracking-wide text-muted-foreground px-2 mb-1 mt-3">
            Thermal
          </div>
          <div className="space-y-px">
            {visibleThermal.map((comp) => (
              <ToolboxItem
                key={comp.id}
                componentId={comp.id}
                label={comp.label}
              />
            ))}
          </div>
        </>
      )}

      {visibleSources.length > 0 && (
        <>
          <div className="text-xs font-semibold uppercase tracking-wide text-muted-foreground px-2 mb-1 mt-3">
            Sources
          </div>
          <div className="space-y-px">
            {visibleSources.map((comp) => (
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
