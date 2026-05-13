import ToolboxItem from "./ToolboxItem";
import { getComponentsByCategory } from "../registry";
import useStore from "../store/useStore";
import { isComponentVisibleInLayer } from "../lib/layers";

// Phase 62 D-02 — ToolboxPanel is now rendered inside the left-panel Tabs
// `<TabsContent value="Components">` wrapper in App.tsx. The wrapper supplies
// width, the resize handle, the right border, and the outer height; this
// component renders the inner scrollable content only.
//
// Phase 63.1 D-06 — the value-source category (WallTemperature,
// HeatFluxSource) is no longer surfaced in the default toolbox. The registry
// entries remain in components.json so that `promoteToSharedSource` (Plan 08)
// can spawn those nodes programmatically — but the user no longer drags them
// from the toolbox. Value-source spawn is an opt-in derived flow, not a
// default authoring surface.

export default function ToolboxPanel() {
  const activeLayer = useStore((s) => s.activeLayer);
  const hydraulicComponents = getComponentsByCategory("Hydraulic");
  const thermalComponents = getComponentsByCategory("Thermal");

  const visibleHydraulic = hydraulicComponents.filter(comp =>
    isComponentVisibleInLayer(comp, activeLayer)
  );
  const visibleThermal = thermalComponents.filter(comp =>
    isComponentVisibleInLayer(comp, activeLayer)
  );

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
    </div>
  );
}
