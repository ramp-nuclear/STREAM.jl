import { Handle, Position, type NodeProps } from "@xyflow/react";
import { getComponent } from "../registry";
import { getComponentIcon, getCategoryBorderClass } from "@/registry/icons";
import type { StreamNodeData } from "../store/useStore";

const sideToPosition: Record<string, Position> = {
  left: Position.Left,
  right: Position.Right,
  top: Position.Top,
  bottom: Position.Bottom,
};

export default function StreamNode({ data, selected }: NodeProps) {
  const nodeData = data as unknown as StreamNodeData;
  const component = getComponent(nodeData.componentId);
  if (!component) return null;

  const Icon = getComponentIcon(nodeData.componentId);
  const borderClass = getCategoryBorderClass(component.category);

  // D-03: Only FlowPort handles in Phase 34 (ThermalPort deferred to Phase 40)
  const flowPorts = component.ports.filter((p) => p.type === "FlowPort");

  return (
    <div
      className={`border border-l-[3px] ${borderClass} rounded-[var(--radius)] bg-card p-2 min-w-[140px] ${
        selected ? "ring-2 ring-[var(--ring)]" : ""
      }`}
    >
      <div className="flex items-center gap-1 text-[11px] text-muted-foreground">
        <Icon className="w-3.5 h-3.5" />
        {component.label}
      </div>
      <div className="font-semibold text-sm">{nodeData.instanceName}</div>
      {flowPorts.map((port) => (
        <Handle
          key={port.name}
          id={port.name}
          type={port.name.includes("out") ? "source" : "target"}
          position={sideToPosition[port.side]}
        />
      ))}
    </div>
  );
}
