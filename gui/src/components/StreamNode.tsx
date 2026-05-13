import type * as React from "react";
import { useCallback } from "react";
import { Handle, Position, type NodeProps } from "@xyflow/react";
import { getComponent } from "../registry";
import { getComponentIcon } from "@/registry/icons";
import { getComponentLayers } from "../lib/layers";
import type { LayerView } from "../lib/layers";
import type { StreamNodeData } from "../store/useStore";
import useStore from "../store/useStore";
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

// ---------------------------------------------------------------------------
// FlowPort handle + anchor indicator (Phase 63.1 D-13)
// ---------------------------------------------------------------------------
//
// The anchor indicator is a small filled circle next to whichever FlowPort
// handle is the anchored one for this node (i.e. `anchors[id].portField`
// matches the handle's expected portField — `port_in.P` for an input handle,
// `port_out.P` for an output handle). UI-SPEC §"Canvas Anchor Indicator"
// fixes shape / size / color / positioning.
//
// The render is extracted into a sub-component so each handle can call
// `useStore` directly. Calling `useStore` inside `flowPorts.map(...)` would
// violate React's rules-of-hooks (hooks-in-loops). The same pattern is used
// elsewhere in the project (per-row sub-components in ResourceRow.tsx, etc.).
//
// The hasAnchor selector returns a *primitive boolean*, not a fresh object —
// this keeps zustand's shallow equality stable and avoids the max-update-
// depth re-render loop (Pitfall 1, same rationale as `hasBCError` above).

type FlowPortLike = {
  name: string;
  type: string;
  side?: string;
};

function anchorIndicatorStyleFor(side: string | undefined): React.CSSProperties {
  // The FlowPort `<Handle>` is a 12-px circle that ReactFlow centers on the
  // node edge at the requested `Position`. We place a 6-px dot just outside
  // the handle, tangent to its edge. The exact offsets below mirror the
  // UI-SPEC §"Canvas Anchor Indicator — Position" recommendation.
  switch (side) {
    case "left":
      return { position: "absolute", left: -10, top: -3 };
    case "right":
      return { position: "absolute", right: -10, top: -3 };
    case "top":
      return { position: "absolute", left: -3, top: -10 };
    case "bottom":
      return { position: "absolute", left: -3, bottom: -10 };
    default:
      return { position: "absolute", left: -10, top: -3 };
  }
}

function FlowPortHandle({
  nodeId,
  port,
  dimFlowHandles,
}: {
  nodeId: string;
  port: FlowPortLike;
  dimFlowHandles: boolean;
}) {
  const isInPort = port.name.includes("in");
  const portFieldKey = isInPort ? "port_in.P" : "port_out.P";
  // Pitfall 1 — return a primitive boolean, never a fresh object/array, so
  // zustand's shallow equality keeps re-renders bounded.
  const hasAnchor = useStore(
    useCallback(
      (s: { anchors: Record<string, { portField: string } | undefined> }) =>
        s.anchors[nodeId]?.portField === portFieldKey,
      [nodeId, portFieldKey],
    ),
  );

  return (
    <>
      <Handle
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
      {hasAnchor && (
        <div
          data-testid="anchor-indicator"
          aria-label="Pressure anchor"
          className={`w-1.5 h-1.5 rounded-full bg-foreground ${
            dimFlowHandles ? "opacity-20" : ""
          }`}
          style={anchorIndicatorStyleFor(port.side)}
        />
      )}
    </>
  );
}

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
      {flowPorts.map((port) => (
        <FlowPortHandle
          key={port.name}
          nodeId={id}
          port={port}
          dimFlowHandles={dimFlowHandles}
        />
      ))}
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
      {bcPorts.map((port) => {
        // Plan 63.1-12 RC-2: BCPort is now used on both Sources (source-side,
        // e.g. WT.T_wall_out) AND Hydraulic consumers (target-side, e.g.
        // Channel.T_wall_left on the bottom edge). The dispatch keys off the
        // component category — see registry.test.ts "BCPort allowed on
        // Sources OR Hydraulic" invariant.
        const isBCSource = component.category === "Sources";
        return (
          <Handle
            key={port.name}
            id={port.name}
            type={isBCSource ? "source" : "target"}
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
        );
      })}
    </div>
  );
}
