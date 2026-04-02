import ToolboxItem from "./ToolboxItem";
import { getComponentsByCategory } from "../registry";

interface ToolboxPanelProps {
  width: number;
}

export default function ToolboxPanel({ width }: ToolboxPanelProps) {
  const hydraulicComponents = getComponentsByCategory("Hydraulic");
  const thermalComponents = getComponentsByCategory("Thermal");

  return (
    <div className="h-full border-r p-4 overflow-y-auto shrink-0" style={{ width }}>
      <h2 className="text-lg font-semibold mb-4">Components</h2>

      <div className="text-xs font-semibold uppercase tracking-wide text-muted-foreground mb-2 mt-4">
        Hydraulic
      </div>
      <div className="space-y-0.5">
        {hydraulicComponents.map((comp) => (
          <ToolboxItem
            key={comp.id}
            componentId={comp.id}
            label={comp.label}
          />
        ))}
      </div>

      <div className="text-xs font-semibold uppercase tracking-wide text-muted-foreground mb-2 mt-4">
        Thermal
      </div>
      <div className="space-y-0.5">
        {thermalComponents.map((comp) => (
          <ToolboxItem
            key={comp.id}
            componentId={comp.id}
            label={comp.label}
          />
        ))}
      </div>
    </div>
  );
}
