import { useCallback } from "react";
import { Handle, Position, type NodeProps } from "@xyflow/react";
import { getComponent } from "../registry";
import { getComponentIcon } from "@/registry/icons";
import type { StreamNodeData } from "../store/useStore";
import useStore from "../store/useStore";

// Inline colors: immune to Tailwind JIT scanning gaps and * { border-color } cascade.
const CATEGORY_LEFT_BORDER_COLOR: Record<string, string> = {
  Hydraulic: "#3b82f6", // blue-500
  Thermal: "#f59e0b", // amber-500
};

const THERMAL_HANDLE_COLOR = "#f59e0b"; // amber-500
const THERMAL_HANDLE_BORDER = "#d97706"; // amber-600

const sideToPosition: Record<string, Position> = {
  left: Position.Left,
  right: Position.Right,
  top: Position.Top,
  bottom: Position.Bottom,
};

export default function StreamNode({ id, data, selected }: NodeProps) {
  const nodeData = data as unknown as StreamNodeData;
  const hasError = useStore(useCallback((s: { errorNodeIds: Set<string> }) => s.errorNodeIds.has(id), [id]));
  const component = getComponent(nodeData.componentId);
  if (!component) return null;

  const Icon = getComponentIcon(nodeData.componentId);
  const accentColor = CATEGORY_LEFT_BORDER_COLOR[component.category];

  const flowPorts = component.ports.filter((p) => p.type === "FlowPort");
  const thermalPorts = component.ports.filter((p) => p.type === "ThermalPort");

  return (
    <div
      className={`border rounded-[var(--radius)] bg-card p-2 min-w-[140px] ${
        selected ? "ring-2 ring-[var(--ring)]" : ""
      } ${hasError ? "outline outline-2 outline-offset-1" : ""}`}
      style={{
        ...(accentColor ? { borderLeftWidth: "3px", borderLeftColor: accentColor } : {}),
        ...(hasError ? { outlineColor: "var(--destructive)" } : {}),
      }}
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
          data={{ portType: port.type }}
        />
      ))}
      {thermalPorts.map((port) => (
        <Handle
          key={port.name}
          id={port.name}
          type={port.side === "right" || port.side === "bottom" ? "source" : "target"}
          position={sideToPosition[port.side]}
          data={{ portType: port.type }}
          style={{
            background: THERMAL_HANDLE_COLOR,
            border: `1px solid ${THERMAL_HANDLE_BORDER}`,
            width: 10,
            height: 10,
            borderRadius: 0,
            transform: "rotate(45deg)",
          }}
        />
      ))}
    </div>
  );
}
