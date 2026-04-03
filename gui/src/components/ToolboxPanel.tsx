import ToolboxItem from "./ToolboxItem";
import { getComponentsByCategory } from "../registry";
import useStore from "../store/useStore";
import { isComponentVisibleInLayer } from "../lib/layers";

interface ToolboxPanelProps {
  width: number;
  onResizeMouseDown?: (e: React.MouseEvent) => void;
}

export default function ToolboxPanel({ width, onResizeMouseDown }: ToolboxPanelProps) {
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
    <div className="relative h-full border-r shrink-0" style={{ width }}>
      {/* Resize handle — thin overlay on right edge, does not add visual thickness */}
      {onResizeMouseDown && (
        <div
          className="absolute right-0 top-0 w-1 h-full cursor-col-resize z-10 hover:bg-border/50"
          onMouseDown={onResizeMouseDown}
        />
      )}
      <div className="h-full p-4 overflow-y-auto">
        <h2 className="text-lg font-semibold mb-4">Components</h2>

        {visibleHydraulic.length > 0 && (
          <>
            <div className="text-xs font-semibold uppercase tracking-wide text-muted-foreground mb-2 mt-4">
              Hydraulic
            </div>
            <div className="space-y-0.5">
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
            <div className="text-xs font-semibold uppercase tracking-wide text-muted-foreground mb-2 mt-4">
              Thermal
            </div>
            <div className="space-y-0.5">
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
    </div>
  );
}
