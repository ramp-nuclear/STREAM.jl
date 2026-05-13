import ToolboxItem from "./ToolboxItem";
import { getComponentsByCategory } from "../registry";
import useStore from "../store/useStore";
import { isComponentVisibleInLayer } from "../lib/layers";

// Phase 62 D-02 — ToolboxPanel is now rendered inside the left-panel Tabs
// `<TabsContent value="Components">` wrapper in App.tsx. The wrapper supplies
// width, the resize handle, the right border, and the outer height; this
// component renders the inner scrollable content only.

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

      {/* Phase 62 D-30 — SOURCES category header. Always rendered (no
          conditional `length > 0` gate); Phase 63 lands the value-source
          drag entries with the BCs wiring. Phase 62 ships the header
          alone — no rows, no tooltip, no drag handlers. */}
      <div className="text-xs font-semibold uppercase tracking-wide text-muted-foreground px-2 mb-1 mt-3">
        Sources
      </div>
    </div>
  );
}
