import type * as React from "react";
import { useCallback, useEffect } from "react";
import { Anchor } from "lucide-react";
import {
  Handle,
  Position,
  useUpdateNodeInternals,
  type Edge,
  type Node,
  type NodeProps,
} from "@xyflow/react";
import { getComponent } from "../registry";
import { getComponentIcon } from "@/registry/icons";
import { getComponentLayers } from "../lib/layers";
import type { LayerView } from "../lib/layers";
import type { StreamNodeData } from "../store/useStore";
import useStore from "../store/useStore";
import { selectNodeErrors, type NodeErrorsInput } from "@/lib/selectors/nodeErrors";
import {
  selectTopologyHints,
  type TopologyHintsInput,
} from "@/lib/selectors/topologyHints";
import { isSourceValueEntry } from "@/lib/sourceValueEntry";
import {
  resolveFlowPortSide,
  resolveAsymmetricOffset,
  resolveThermalPairSides,
  type Side,
  type OffsetStyle,
} from "@/lib/autoflip";

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

  // Plan 63.1-14 (GAP-RC-4): SourceValueEntry-shaped values dispatch first.
  if (isSourceValueEntry(value)) {
    if (value.mode === "value") {
      const unitSuffix = unit ? ` ${unit}` : "";
      return { text: `${fieldName} = ${value.value}${unitSuffix}`, muted: false };
    }
    if (value.mode === "profile") {
      const presetLabel = value.preset === "file" ? "file" : "cosine";
      return { text: `${fieldName} = profile (${presetLabel})`, muted: false };
    }
    if (value.mode === "function") {
      return { text: `${fieldName} = fn(t)`, muted: false };
    }
  }

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

type ThermalPortLike = {
  name: string;
  type: string;
  side?: string;
  default_axis?: "horizontal" | "vertical";
  pair_with?: string;
};

// ---------------------------------------------------------------------------
// Offset-string parsing (Pitfall 3 guard)
// ---------------------------------------------------------------------------
//
// `resolveAsymmetricOffset` returns a fresh `OffsetStyle` object — returning
// that directly from a `useStore` selector would cause an infinite re-render
// loop because each call produces a new reference (Pitfall 3 / RESEARCH.md).
// We encode the offset as a primitive string ("left:25%", "top:75%", or "")
// from inside the selector and parse it back to an `OffsetStyle` in the
// component body. The selector cache stays stable across renders.
function offsetToString(offset: OffsetStyle | undefined): string {
  if (!offset) return "";
  if (offset.left !== undefined) return `left:${offset.left}`;
  if (offset.top !== undefined) return `top:${offset.top}`;
  return "";
}

function parseOffsetString(s: string): OffsetStyle | undefined {
  if (!s) return undefined;
  const [axis, value] = s.split(":");
  if (axis === "left") return { left: value };
  if (axis === "top") return { top: value };
  return undefined;
}

function anchorIndicatorStyleFor(side: string | undefined): React.CSSProperties {
  // The FlowPort `<Handle>` is a 12-px circle that ReactFlow centers on the
  // node edge at the requested `Position`. We place the 12-px lucide Anchor
  // icon just outside the handle, tangent to its edge. Plan 63.1-13 widened
  // the indicator from a 6-px dot to a 12-px SVG glyph; offsets bumped from
  // (-10, -3) to (-16, -6) accordingly.
  switch (side) {
    case "left":
      return { position: "absolute", left: -16, top: -6 };
    case "right":
      return { position: "absolute", right: -16, top: -6 };
    case "top":
      return { position: "absolute", left: -6, top: -16 };
    case "bottom":
      return { position: "absolute", left: -6, bottom: -16 };
    default:
      return { position: "absolute", left: -16, top: -6 };
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

  // Phase 64 D-01/D-02 — live side derivation from (nodes, edges). Returns a
  // primitive string so zustand's shallow equality stays stable (Pitfall 3).
  const defaultSide = (port.side as Side | undefined) ?? "left";
  const resolvedSide = useStore(
    useCallback(
      (s: { nodes: Node[]; edges: Edge[] }) =>
        resolveFlowPortSide(
          s.nodes,
          s.edges,
          nodeId,
          port.name,
          defaultSide,
          getComponent,
        ),
      [nodeId, port.name, defaultSide],
    ),
  );

  // D-09/D-10 asymmetric same-side placement — encoded as a primitive string
  // ("left:25%" / "top:75%" / "") inside the selector, parsed to OffsetStyle
  // in the component body (Pitfall 3: never return a fresh object/array from
  // a selector).
  const offsetString = useStore(
    useCallback(
      (s: { nodes: Node[]; edges: Edge[] }) =>
        offsetToString(
          resolveAsymmetricOffset(
            s.nodes,
            s.edges,
            nodeId,
            resolvedSide,
            port.name,
            defaultSide,
            getComponent,
          ),
        ),
      [nodeId, port.name, resolvedSide, defaultSide],
    ),
  );
  const offsetStyle = parseOffsetString(offsetString);

  // Pattern 2 / Pitfall 1 — re-measure handle DOM whenever the resolved side
  // flips. Multiple sibling sub-components may each fire updateNodeInternals
  // on the same node id; ReactFlow handles redundant calls idempotently.
  // Pitfall 2 note: if rapid drag exposes a sticky-edge race, switch to the
  // deferred form `setTimeout(() => updateNodeInternals(nodeId), 0)`; not
  // applied initially per the plan.
  const updateNodeInternals = useUpdateNodeInternals();
  useEffect(() => {
    updateNodeInternals(nodeId);
  }, [nodeId, resolvedSide, updateNodeInternals]);

  return (
    <>
      <Handle
        id={port.name}
        type={isInPort ? "target" : "source"}
        position={sideToPosition[resolvedSide]}
        data={{ portType: port.type }}
        style={{
          background: isInPort ? FLOW_IN_BG : FLOW_OUT_BG,
          border: `1.5px solid ${isInPort ? FLOW_IN_BORDER : FLOW_OUT_BORDER}`,
          ...(offsetStyle ?? {}),
          ...(dimFlowHandles ? { opacity: 0.2, pointerEvents: "none" as const } : {}),
        }}
      />
      {hasAnchor && (
        <Anchor
          data-testid="anchor-indicator"
          aria-label="Pressure anchor"
          className={`w-3 h-3 text-foreground ${
            dimFlowHandles ? "opacity-20" : ""
          }`}
          // D-04 anchor co-location — anchor follows the resolved side, not
          // the registry default, so handle + anchor never visually decouple.
          style={anchorIndicatorStyleFor(resolvedSide)}
        />
      )}
    </>
  );
}

// ---------------------------------------------------------------------------
// ThermalPortHandle — pair-thermal sub-component (Phase 64 D-12 / D-18).
// ---------------------------------------------------------------------------
//
// Used for thermal ports carrying `pair_with` (CAC + HD today). The pair stays
// on opposing faces; the suffix is definitive (`_left` → spatial left or top,
// `_right` → spatial right or bottom); only the axis flips based on neighbor
// placement. Single-port thermal handles (e.g. ConstantTemperature.thermal)
// stay in the inline `.map(...)` path with the registry-default `side` —
// they have no `pair_with` to swing.
function ThermalPortHandle({
  nodeId,
  port,
  dimThermalHandles,
}: {
  nodeId: string;
  port: ThermalPortLike;
  dimThermalHandles: boolean;
}) {
  const pairWith = port.pair_with!;
  const defaultAxis = port.default_axis ?? "horizontal";

  // Pitfall 3: pull just the primitive `thisSide` out of the selector body so
  // the returned value is a string, not a fresh object.
  const resolvedSide: Side = useStore(
    useCallback(
      (s: { nodes: Node[]; edges: Edge[] }) =>
        resolveThermalPairSides(
          s.nodes,
          s.edges,
          nodeId,
          port.name,
          pairWith,
          defaultAxis,
          getComponent,
        ).thisSide,
      [nodeId, port.name, pairWith, defaultAxis],
    ),
  );

  // Pattern 2 / Pitfall 1 — re-measure when the side flips.
  const updateNodeInternals = useUpdateNodeInternals();
  useEffect(() => {
    updateNodeInternals(nodeId);
  }, [nodeId, resolvedSide, updateNodeInternals]);

  // The source/target heuristic now reads from the resolved side rather than
  // the registry's static `port.side` — handle source/target identity flips
  // alongside autoflip so edges connect to the correct end.
  const isSourceHandle = resolvedSide === "right" || resolvedSide === "bottom";

  return (
    <Handle
      id={port.name}
      type={isSourceHandle ? "source" : "target"}
      position={sideToPosition[resolvedSide]}
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
  // Phase 64 Plan 04 D-15 — non-blocking topology-hint surface. Returns a
  // primitive boolean (Pitfall 3: never return a fresh array from a Zustand
  // selector). NOT mixed into `hasAnyError` — the chip and the red-ring
  // outline are independent surfaces. The hint is a warning, not an error.
  const hasTopologyHint = useStore(
    useCallback(
      (s) =>
        selectTopologyHints(
          s as unknown as TopologyHintsInput,
          id,
          getComponent,
        ).length > 0,
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
      {hasTopologyHint && (
        <div
          data-testid="topology-hint-chip"
          role="status"
          aria-label="Topology hint"
          className="absolute right-1 bottom-1 text-[10px] rounded border bg-amber-100 text-amber-900 px-1 py-0.5"
        >
          Hydraulic and thermal neighbors on same axis — consider repositioning.
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
      {thermalPorts.map((port) => {
        // Phase 64 Pitfall 6 fix: pair-thermal ports (CAC + HD — they carry
        // `pair_with` and have no static `side`) route through
        // `ThermalPortHandle`, which resolves a defined side via D-18
        // suffix-locked axis-flip. Single-port thermal entries (e.g.
        // ConstantTemperature.thermal) keep the registry-default `side` —
        // they have no pair to swing.
        if (port.pair_with) {
          return (
            <ThermalPortHandle
              key={port.name}
              nodeId={id}
              port={port as ThermalPortLike}
              dimThermalHandles={dimThermalHandles}
            />
          );
        }
        const singleSide = (port.side ?? "left") as Side;
        return (
          <Handle
            key={port.name}
            id={port.name}
            type={singleSide === "right" || singleSide === "bottom" ? "source" : "target"}
            position={sideToPosition[singleSide]}
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
        );
      })}
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
