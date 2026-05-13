import { useCallback } from "react";
import { Handle, Position, useConnection, type NodeProps } from "@xyflow/react";
import { getComponent } from "../registry";
import { getComponentIcon } from "@/registry/icons";
import { getComponentLayers } from "../lib/layers";
import type { LayerView } from "../lib/layers";
import type { StreamNodeData } from "../store/useStore";
import useStore from "../store/useStore";
import { getPortType } from "./CanvasPanel";
import { selectNodeErrors, type NodeErrorsInput } from "@/lib/selectors/nodeErrors";

// Inline colors: immune to Tailwind JIT scanning gaps and * { border-color } cascade.
const CATEGORY_LEFT_BORDER_COLOR: Record<string, string> = {
  Hydraulic: "#3b82f6", // blue-500
  Thermal: "#f59e0b", // amber-500
};

const FLOW_IN_BG = "#60a5fa";       // blue-400 (port_in — incoming flow)
const FLOW_IN_BORDER = "#1d4ed8";   // blue-700
const FLOW_OUT_BG = "#f87171";      // red-400 (port_out — outgoing flow)
const FLOW_OUT_BORDER = "#b91c1c";  // red-700

const THERMAL_HANDLE_COLOR = "#f59e0b"; // amber-500
const THERMAL_HANDLE_BORDER = "#d97706"; // amber-600

const sideToPosition: Record<string, Position> = {
  left: Position.Left,
  right: Position.Right,
  top: Position.Top,
  bottom: Position.Bottom,
};

// ---------------------------------------------------------------------------
// Source-block label rendering (D-19)
// ---------------------------------------------------------------------------
//
// For value-source blocks (WallTemperature, HeatFluxSource) we render a
// two-line label:
//   Line 1: instance name (existing — unchanged).
//   Line 2: mode-aware value summary derived from the relevant constructor
//           parameter (`T_wall` for WT, `q` for HFS).
//
// The encoding contract (matches what ParameterForm writes into
// `node.data.parameters`):
//   - scalar value      → number
//   - vector value      → JS array
//   - callable / fn(t)  → string (function signature/name)
//   - unset / absent    → undefined | null | empty string
function sourceLabelLine(
  parameters: Record<string, unknown> | undefined,
  fieldName: string,
  unit: string | undefined,
): { text: string; muted: boolean } {
  const value = parameters?.[fieldName];
  const n = parameters?.["n"];
  if (value === undefined || value === null || value === "") {
    return { text: `${fieldName} = (unset)`, muted: true };
  }
  if (Array.isArray(value)) {
    const count = typeof n === "number" ? n : value.length;
    return { text: `${fieldName} = vector (n=${count})`, muted: false };
  }
  if (typeof value === "number") {
    const unitSuffix = unit ? ` ${unit}` : "";
    return { text: `${fieldName} = ${value}${unitSuffix}`, muted: false };
  }
  // String value — function/callable encoding (e.g. "fn(t)" / "fn(t, i)" /
  // user-named function). Render as `fn(t)` per D-19 (Phase 63 unit-tests the
  // class of string-encoded callables; the precise string is a UI detail).
  return { text: `${fieldName} = fn(t)`, muted: false };
}

const SOURCE_LABEL_FIELD: Record<string, string> = {
  WallTemperature: "T_wall",
  HeatFluxSource: "q",
};

export default function StreamNode({ id, data, selected }: NodeProps) {
  const nodeData = data as unknown as StreamNodeData;
  const hasError = useStore(useCallback((s: { errorNodeIds: Set<string> }) => s.errorNodeIds.has(id), [id]));
  // Phase 63 D-22 / 63.1 D-15 — BC-specific error tag surface (sibling to the
  // legacy Phase-39 `errorNodeIds: Set<string>`; both contribute to the red-ring).
  // Select a primitive (boolean) — not a fresh array — to keep zustand's
  // shallow equality stable and avoid the maximum-update-depth re-render loop.
  // Phase 63.1 D-15: ring state now derives from selectNodeErrors (pure
  // function of nodes + edges + bcMode + bcSymmetric + anchors); there is no
  // stored errorTagsByNodeId slice anymore.
  const hasBCError = useStore(
    useCallback(
      (s) => selectNodeErrors(s as unknown as NodeErrorsInput, id).length > 0,
      [id],
    ),
  );
  const activeLayer = useStore(useCallback((s: { activeLayer: LayerView }) => s.activeLayer, []));
  const connection = useConnection();
  const component = getComponent(nodeData.componentId);
  if (!component) return null;

  const Icon = getComponentIcon(nodeData.componentId);
  const accentColor = CATEGORY_LEFT_BORDER_COLOR[component.category];

  const flowPorts = component.ports.filter((p) => p.type === "FlowPort");
  const thermalPorts = component.ports.filter((p) => p.type === "ThermalPort");
  const bcPorts = component.ports.filter((p) => p.type === "BCPort");

  // Handle dimming for dual-layer nodes (e.g. ChannelAndContacts)
  const { hasFlow, hasThermal } = getComponentLayers(component);
  const isDualLayer = hasFlow && hasThermal;
  const dimFlowHandles = isDualLayer && activeLayer === "Thermal";
  const dimThermalHandles = isDualLayer && activeLayer === "Hydraulic";

  // Combined error surface — legacy Phase-39 + BC tag list. The red-ring
  // outline lights up when EITHER source has a flag for this node.
  const hasAnyError = hasError || hasBCError;

  // -------------------------------------------------------------------------
  // Whole-body BC drop overlay (D-10, CD-03)
  // -------------------------------------------------------------------------
  // Activate the dashed-outline overlay ONLY when:
  //   (a) a connection is in-flight,
  //   (b) the in-flight drag's source port is a BCPort, and
  //   (c) the target node has external_inputs (i.e. is a consumer).
  // The overlay is purely visual (`pointer-events-none`) — ReactFlow's own
  // handle hit-testing performs the actual drop. Per CD-03 we use the
  // built-in `useConnection` hook rather than hand-rolled mouse listeners.
  const isConsumerNode = (component.external_inputs?.length ?? 0) > 0;
  const dropActive =
    !!connection &&
    connection.inProgress === true &&
    !!connection.fromNode &&
    !!connection.fromHandle?.id &&
    getPortType(connection.fromNode.id, connection.fromHandle.id) === "BCPort" &&
    isConsumerNode &&
    connection.fromNode.id !== id; // don't self-drop

  // -------------------------------------------------------------------------
  // Source-block label (D-19)
  // -------------------------------------------------------------------------
  const sourceFieldName = SOURCE_LABEL_FIELD[component.id];
  let sourceLabel: { text: string; muted: boolean } | null = null;
  if (sourceFieldName) {
    const paramDef = component.parameters.find((p) => p.name === sourceFieldName);
    sourceLabel = sourceLabelLine(
      nodeData.parameters as Record<string, unknown> | undefined,
      sourceFieldName,
      paramDef?.unit,
    );
  }

  return (
    <div
      className={`relative border rounded-[var(--radius)] bg-card p-2 min-w-[140px] ${
        selected ? "ring-2 ring-[var(--ring)]" : ""
      } ${hasAnyError ? "outline outline-2 outline-offset-1 ring-2 ring-destructive" : ""}`}
      style={{
        ...(accentColor ? { borderLeftWidth: "3px", borderLeftColor: accentColor } : {}),
        ...(hasAnyError ? { outlineColor: "var(--destructive)" } : {}),
      }}
    >
      {dropActive && (
        <div
          className="absolute inset-0 rounded border-2 border-dashed pointer-events-none"
          style={{ borderColor: "var(--muted-foreground)" }}
        >
          <div className="absolute -top-[20px] left-1/2 -translate-x-1/2 rounded bg-background px-[6px] py-[2px] text-xs text-muted-foreground border">
            Connect BC
          </div>
        </div>
      )}
      <div className="flex items-center gap-1 text-[11px] text-muted-foreground">
        <Icon className="w-3.5 h-3.5" />
        {component.label}
      </div>
      <div className="font-semibold text-sm">{nodeData.instanceName}</div>
      {sourceLabel && (
        <div
          className={`text-[11px] ${sourceLabel.muted ? "text-destructive/80" : "text-muted-foreground"}`}
          data-testid="source-block-label"
        >
          {sourceLabel.text}
        </div>
      )}
      {flowPorts.map((port) => {
        const isInPort = port.name.includes("in");
        return (
          <Handle
            key={port.name}
            id={port.name}
            type={isInPort ? "target" : "source"}
            position={sideToPosition[port.side!]}
            data={{ portType: port.type }}
            style={{
              background: isInPort ? FLOW_IN_BG : FLOW_OUT_BG,
              border: `1.5px solid ${isInPort ? FLOW_IN_BORDER : FLOW_OUT_BORDER}`,
              ...(dimFlowHandles ? { opacity: 0.2, pointerEvents: "none" as const } : {}),
            }}
          />
        );
      })}
      {thermalPorts.map((port) => (
        <Handle
          key={port.name}
          id={port.name}
          type={port.side === "right" || port.side === "bottom" ? "source" : "target"}
          position={sideToPosition[port.side!]}
          data={{ portType: port.type }}
          style={{
            background: THERMAL_HANDLE_COLOR,
            border: `1.5px solid ${THERMAL_HANDLE_BORDER}`,
            width: 12,
            height: 12,
            borderRadius: 0,
            transform: "rotate(45deg)",
            ...(dimThermalHandles ? { opacity: 0.2, pointerEvents: "none" as const } : {}),
          }}
        />
      ))}
      {bcPorts.map((port) => (
        <Handle
          key={port.name}
          id={port.name}
          type="source"
          position={sideToPosition[port.side ?? "right"]}
          data={{ portType: port.type }}
          style={{
            background: "transparent",
            border: `1.5px solid var(--muted-foreground)`,
            width: 10,
            height: 10,
            borderRadius: 0,
          }}
        />
      ))}
    </div>
  );
}
