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
  const sourceComponents = getComponentsByCategory("Sources");

  const visibleHydraulic = hydraulicComponents.filter(comp =>
    isComponentVisibleInLayer(comp, activeLayer)
  );
  const visibleThermal = thermalComponents.filter(comp =>
    isComponentVisibleInLayer(comp, activeLayer)
  );
  // Phase 63 D-24 — value-source blocks (WallTemperature, HeatFluxSource).
  // They drive external BC inputs on Channel/ChannelHeatFlux via the dashed
  // BCPort edge. We show them in every layer view (they're not gated on
  // FlowPort/ThermalPort presence) — they only carry BCPorts.
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

      {/* Phase 62 D-30 — SOURCES category header. Always rendered (no
          conditional `length > 0` gate); Phase 63 D-24 populates the
          value-source drag entries (WallTemperature, HeatFluxSource).
          Both entries always show — value-sources are not gated on the
          active layer view because they carry only BCPorts, which do
          not participate in the Hydraulic/Thermal layer split. */}
      <div className="text-xs font-semibold uppercase tracking-wide text-muted-foreground px-2 mb-1 mt-3">
        Sources
      </div>
      {visibleSources.length > 0 && (
        <div className="space-y-px">
          {visibleSources.map((comp) => (
            <ToolboxItem
              key={comp.id}
              componentId={comp.id}
              label={comp.label}
            />
          ))}
        </div>
      )}
    </div>
  );
}
