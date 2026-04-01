import { Handle, Position, type NodeProps } from "@xyflow/react";
import { getComponent } from "../registry";
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

  // D-03: Only FlowPort handles in Phase 34 (ThermalPort deferred to Phase 40)
  const flowPorts = component.ports.filter((p) => p.type === "FlowPort");

  return (
    <div
      className={`border rounded-[var(--radius)] bg-card p-2 min-w-[140px] ${
        selected ? "ring-2 ring-[var(--ring)]" : ""
      }`}
    >
      <div className="text-xs text-muted-foreground">{component.label}</div>
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
