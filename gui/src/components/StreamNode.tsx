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
import { getComponentLayers, getDisplayLayers, type ActiveLayers } from "../lib/layers";
import { LAYER_COLOR_VAR } from "../lib/layerColors";
import type { StreamNodeData } from "../store/useStore";
import useStore from "../store/useStore";
import { isSourceValueEntry } from "@/lib/sourceValueEntry";
import {
  resolveFlowPortAssignment,
  resolveThermalPairSides,
  resolveBCPortSide,
  computePortOffset,
  type Side,
} from "@/lib/autoflip";
import { usePreference } from "@/lib/preferences";

// Phase 72 — flow-port visual treatment (Lane 2, 2026-05-23). The disc
// itself is a tinted-neutral graphite pad (--color-port-disc); the chevron
// inside carries the Hydraulic accent. Inverts the prior "Hydraulic disc +
// near-white chevron" treatment, which read as a saturated sticker rather
// than an instrument port. The shape (filled circle) still says Hydraulic;
// the colour signal moves to a smaller, more precise element. AnatomyDialog
// mirrors must track these tokens.
const FLOW_FILL = "var(--color-port-disc)";
const FLOW_STROKE = "var(--color-port-disc-border)";

// Phase 73 — crafted shape language. Flow is a filled circle with a small
// directional chevron pointing in/out (so port_in vs port_out reads at a
// glance, not just "blue vs red"). Thermal is a flat-top rounded hexagon
// (replaces the rotated diamond — reads more deliberate, less "rotated
// square as afterthought"). BC is a dashed rounded square (echoes the
// dashed BCEdge stroke at the handle).
// All three: 14 px hit target, 1.5 px stroke, circular hover halo via CSS
// targeting `data-port-type`.
const THERMAL_FILL = "var(--color-layer-thermal)";
const THERMAL_STROKE = "color-mix(in oklch, var(--color-layer-thermal) 60%, black)";
const BC_STROKE = "var(--muted-foreground)";

// Rotation (deg) for the in-port chevron given the resolved side. The chevron
// glyph is drawn pointing RIGHT in its local frame (▶); we rotate it so it
// points INWARD into the node when on `port_in`, and OUTWARD when on
// `port_out`.
//   port_in  on left  → chevron points right (into node)
//   port_in  on right → chevron points left
//   port_in  on top   → chevron points down
//   port_in  on bottom→ chevron points up
//   port_out is the opposite of each of those.
function flowChevronRotation(side: string, isInPort: boolean): number {
  const inwardDeg: Record<string, number> = {
    left: 0,    // ▶ default = right = inward when on left edge
    right: 180,
    top: 90,    // ▼ pointing down
    bottom: 270,
  };
  const base = inwardDeg[side] ?? 0;
  return isInPort ? base : (base + 180) % 360;
}

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
// depth re-render loop (Pitfall 1 — return a primitive, never a fresh object).

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

// ---------------------------------------------------------------------------
// SVG mark components (Phase 73 — Lane A: crafted shapes).
// ---------------------------------------------------------------------------
//
// Rendered as children of the React Flow `Handle`. The Handle itself is a
// 14×14 transparent hit target with `border-radius: 50%` (so the hover
// box-shadow halo is circular regardless of mark shape). `pointer-events: none`
// on the SVG keeps drag events targeting the Handle div, not the SVG paint.

/**
 * Filled circle + small inner chevron pointing in flow direction.
 * `direction` controls the chevron rotation (degrees, CW from "points right").
 */
function FlowDiscMark({
  fill,
  stroke,
  direction,
}: {
  fill: string;
  stroke: string;
  direction: number;
}) {
  return (
    <svg
      width="14"
      height="14"
      viewBox="0 0 14 14"
      style={{ position: "absolute", inset: 0, pointerEvents: "none" }}
      aria-hidden="true"
    >
      <circle cx="7" cy="7" r="6" fill={fill} stroke={stroke} strokeWidth="1" />
      {/* Chevron uses --color-port-chevron (desaturated Hydraulic, chroma
          0.07 vs the layer accent's 0.18). Whispers "Hydraulic" rather
          than shouting it — small saturated marks on neutral discs read
          toyish, this drops chroma until the chevron reads as an etched
          indicator. */}
      <polygon
        points="5.5,4.5 8.5,7 5.5,9.5"
        fill="var(--color-port-chevron)"
        transform={`rotate(${direction} 7 7)`}
      />
    </svg>
  );
}

// Hexagon: flat-top, inscribed in a 14×14 viewBox with 0.6 px stroke inset on
// every side so the 1.5 px stroke doesn't get clipped at the SVG edge.
function ThermalHexMark() {
  return (
    <svg
      width="14"
      height="14"
      viewBox="0 0 14 14"
      style={{ position: "absolute", inset: 0, pointerEvents: "none" }}
      aria-hidden="true"
    >
      <polygon
        points="3.5,0.9 10.5,0.9 13.1,7 10.5,13.1 3.5,13.1 0.9,7"
        fill={THERMAL_FILL}
        stroke={THERMAL_STROKE}
        strokeWidth="1.5"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function BCDashedMark() {
  return (
    <svg
      width="14"
      height="14"
      viewBox="0 0 14 14"
      style={{ position: "absolute", inset: 0, pointerEvents: "none" }}
      aria-hidden="true"
    >
      <rect
        x="1.5"
        y="1.5"
        width="11"
        height="11"
        rx="2"
        ry="2"
        fill="transparent"
        stroke={BC_STROKE}
        strokeWidth="1.5"
        strokeDasharray="2.5 1.5"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function FlowPortHandle({
  nodeId,
  port,
  dimFlowHandles,
  hideFlowHandles,
}: {
  nodeId: string;
  port: FlowPortLike;
  dimFlowHandles: boolean;
  hideFlowHandles: boolean;
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

  // Phase 64 — live side derivation under the "one port per side" rule. Each
  // FlowPort scores its 4-side preference by neighbor projection; siblings
  // displace each other so two ports never collide. Selector returns a
  // primitive string so zustand's shallow equality stays stable (Pitfall 3).
  //
  // Phase 72 (post-Preferences) — `editor.autoFlipPortsOnConnect` gates the
  // resolver: when OFF, the port stays on its registry-declared side and
  // ignores neighbor geometry. The resolver still runs (its result is
  // discarded) — short-circuiting it would require threading the boolean
  // through every selector, which the autoflip doctrine ("zero runtime
  // imports from react/zustand") refuses. The wasted work is per-handle
  // and bounded by the canvas node count; negligible.
  const defaultSide = (port.side as Side | undefined) ?? "left";
  const [autoFlipEnabled] = usePreference("editor", "autoFlipPortsOnConnect");
  const resolvedSide = useStore(
    useCallback(
      (s: { nodes: Node[]; edges: Edge[] }) => {
        if (!autoFlipEnabled) return defaultSide;
        return (resolveFlowPortAssignment(s.nodes, s.edges, nodeId, getComponent)[
          port.name
        ] ?? defaultSide) as Side;
      },
      [nodeId, port.name, defaultSide, autoFlipEnabled],
    ),
  );

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

  // Phase 72 (post-Preferences) — showPortTypeOnHover reveals "FlowPort"
  // on hover via a native `title` attribute. Native title (vs. Radix
  // Tooltip) is the right call per the locked tooltip discipline:
  // (a) handles are 12-14 px hit targets — too small for a 400 ms
  //     Radix tooltip's positioning math to feel right;
  // (b) the dialog's per-handle TooltipProvider overhead is real on a
  //     100-node canvas (handle count = 2-4× node count);
  // (c) native title preserves the OS-native floating behavior and
  //     respects screen-reader announce paths for free.
  const [showPortType] = usePreference("editor", "showPortTypeOnHover");

  return (
    <>
      <Handle
        id={port.name}
        type={isInPort ? "target" : "source"}
        position={sideToPosition[resolvedSide]}
        data={{ portType: port.type }}
        data-port-type={isInPort ? "flow-in" : "flow-out"}
        {...(showPortType ? { title: "FlowPort" } : {})}
        style={{
          // Phase 73 — Handle is a transparent 14×14 hit target; the visible
          // disc + chevron are painted by the SVG child. `border-radius: 50%`
          // keeps the hover halo circular and aligned with the disc.
          background: "transparent",
          border: "none",
          width: 14,
          height: 14,
          borderRadius: "50%",
          // Phase 68 D-03: per-handle off-layer treatment. Hide mode takes
          // precedence over dim mode (display:none beats opacity 0.2).
          ...(hideFlowHandles
            ? { display: "none" as const }
            : dimFlowHandles
              ? { opacity: 0.2, pointerEvents: "none" as const }
              : {}),
        }}
      >
        <FlowDiscMark
          fill={FLOW_FILL}
          stroke={FLOW_STROKE}
          direction={flowChevronRotation(resolvedSide, isInPort)}
        />
      </Handle>
      {hasAnchor && !hideFlowHandles && (
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
  hideThermalHandles,
}: {
  nodeId: string;
  port: ThermalPortLike;
  dimThermalHandles: boolean;
  hideThermalHandles: boolean;
}) {
  const pairWith = port.pair_with!;
  const defaultAxis = port.default_axis ?? "horizontal";

  // Phase 72 (post-Preferences) — autoFlipPortsOnConnect gate; same model
  // as FlowPortHandle above. When OFF, the port stays on its registry-
  // declared side (`port.side` or — if absent — the natural side derived
  // from default_axis + "in"/"out" name convention).
  const [autoFlipEnabled] = usePreference("editor", "autoFlipPortsOnConnect");
  const registryDefaultSide: Side =
    (port.side as Side | undefined) ??
    (defaultAxis === "horizontal"
      ? port.name.includes("right")
        ? "right"
        : "left"
      : port.name.includes("bottom")
        ? "bottom"
        : "top");

  // Pitfall 3: pull just the primitive `thisSide` out of the selector body so
  // the returned value is a string, not a fresh object.
  //
  // Phase 73 v2 — thermal pair uses neighbor projection for axis selection
  // (legacy resolveThermalPairSides). Collision with flow on the same axis
  // is handled visually via `computePortOffset` below, not by relocating.
  const resolvedSide: Side = useStore(
    useCallback(
      (s: { nodes: Node[]; edges: Edge[] }) => {
        if (!autoFlipEnabled) return registryDefaultSide;
        return resolveThermalPairSides(
          s.nodes,
          s.edges,
          nodeId,
          port.name,
          pairWith,
          defaultAxis,
          getComponent,
        ).thisSide;
      },
      [nodeId, port.name, pairWith, defaultAxis, autoFlipEnabled, registryDefaultSide],
    ),
  );

  // Phase 73 v2 — along-edge offset when the resolved side coincides with a
  // flow port. Subscribed as a primitive (serialized JSON) so zustand's
  // shallow equality stays stable and we don't re-render per store tick.
  //
  // Thermal pair: uniform 25% offset for BOTH members. Even though
  // suffix-based offset (left→25%, right→75%) would visually separate them,
  // pair members live on OPPOSITE edges by the suffix-locked rule and never
  // share an edge — so a fixed 25% reads as a coherent "shelf" parallel to
  // the flow axis instead of a zigzag.
  const offsetJson = useStore(
    useCallback(
      (s: { nodes: Node[]; edges: Edge[] }) => {
        const flow = resolveFlowPortAssignment(
          s.nodes,
          s.edges,
          nodeId,
          getComponent,
        );
        const flowSides = new Set<Side>(Object.values(flow));
        const offset = computePortOffset(port.name, resolvedSide, flowSides, {
          uniformOffset: "25%",
        });
        return offset ? JSON.stringify(offset) : "";
      },
      [nodeId, port.name, resolvedSide],
    ),
  );
  const offsetStyle: { top?: string; left?: string } = offsetJson
    ? JSON.parse(offsetJson)
    : {};

  // Pattern 2 / Pitfall 1 — re-measure when the side flips.
  const updateNodeInternals = useUpdateNodeInternals();
  useEffect(() => {
    updateNodeInternals(nodeId);
  }, [nodeId, resolvedSide, updateNodeInternals]);

  // The source/target heuristic now reads from the resolved side rather than
  // the registry's static `port.side` — handle source/target identity flips
  // alongside autoflip so edges connect to the correct end.
  const isSourceHandle = resolvedSide === "right" || resolvedSide === "bottom";

  // Phase 72 (post-Preferences) — port-type-on-hover. See FlowPortHandle
  // for why this is native title= rather than Radix Tooltip.
  const [showPortType] = usePreference("editor", "showPortTypeOnHover");

  return (
    <Handle
      id={port.name}
      type={isSourceHandle ? "source" : "target"}
      position={sideToPosition[resolvedSide]}
      data={{ portType: port.type }}
      data-port-type="thermal"
      {...(showPortType ? { title: "ThermalPort" } : {})}
      style={{
        // Phase 73 — Handle is a transparent hit target; SVG child paints the
        // hex. `border-radius: 50%` so the CSS hover halo (box-shadow) is
        // circular regardless of the inner shape.
        background: "transparent",
        border: "none",
        width: 14,
        height: 14,
        borderRadius: "50%",
        // Phase 73 v2 — along-edge offset wins when set (collision w/ flow);
        // override default cross-edge centering only on the collision axis.
        ...offsetStyle,
        // Phase 68 D-03: per-handle off-layer treatment for the Thermal
        // layer. Hide mode beats dim mode.
        ...(hideThermalHandles
          ? { display: "none" as const }
          : dimThermalHandles
            ? { opacity: 0.2, pointerEvents: "none" as const }
            : {}),
      }}
    >
      <ThermalHexMark />
    </Handle>
  );
}

// ---------------------------------------------------------------------------
// BCPortHandle — dashed rounded square (Phase 73).
// ---------------------------------------------------------------------------
//
// BC ports now participate in the side-priority engine: flow first, thermal
// perpendicular to flow, BC takes whichever side is free and closest to its
// connected source. The registry's static `port.side` becomes a default —
// `resolveBCPortSide` overrides it when a flow port wants that side.
//
// The structural fix here: in vertical hydraulic loops, Channel's port_out
// autoflips to `bottom`, and the legacy BC rendering pinned T_wall_left to
// `bottom` too (overlap). With the new resolver, T_wall_left moves to the
// perpendicular axis (left or right) instead.
function BCPortHandle({
  nodeId,
  port,
  isBCSource,
}: {
  nodeId: string;
  port: { name: string; type: string; side?: string };
  isBCSource: boolean;
}) {
  const [autoFlipEnabled] = usePreference("editor", "autoFlipPortsOnConnect");
  const registryDefault = (port.side as Side | undefined) ?? "bottom";

  // Phase 73 v2 — neighbor projection only. Collision with flow on the
  // same side gets resolved by `computePortOffset` below.
  const resolvedSide: Side = useStore(
    useCallback(
      (s: { nodes: Node[]; edges: Edge[] }) => {
        if (!autoFlipEnabled) return registryDefault;
        return resolveBCPortSide(s.nodes, s.edges, nodeId, port, getComponent);
      },
      [nodeId, port, autoFlipEnabled, registryDefault],
    ),
  );

  const offsetJson = useStore(
    useCallback(
      (s: { nodes: Node[]; edges: Edge[] }) => {
        const flow = resolveFlowPortAssignment(
          s.nodes,
          s.edges,
          nodeId,
          getComponent,
        );
        const flowSides = new Set<Side>(Object.values(flow));
        const offset = computePortOffset(port.name, resolvedSide, flowSides);
        return offset ? JSON.stringify(offset) : "";
      },
      [nodeId, port.name, resolvedSide],
    ),
  );
  const offsetStyle: { top?: string; left?: string } = offsetJson
    ? JSON.parse(offsetJson)
    : {};

  const updateNodeInternals = useUpdateNodeInternals();
  useEffect(() => {
    updateNodeInternals(nodeId);
  }, [nodeId, resolvedSide, updateNodeInternals]);

  const [showPortType] = usePreference("editor", "showPortTypeOnHover");

  return (
    <Handle
      id={port.name}
      type={isBCSource ? "source" : "target"}
      position={sideToPosition[resolvedSide]}
      data={{ portType: port.type }}
      data-port-type="bc"
      {...(showPortType ? { title: "BCPort" } : {})}
      style={{
        background: "transparent",
        border: "none",
        width: 14,
        height: 14,
        borderRadius: "50%",
        ...offsetStyle,
      }}
    >
      <BCDashedMark />
    </Handle>
  );
}

export default function StreamNode({ id, data, selected }: NodeProps) {
  const nodeData = data as unknown as StreamNodeData;
  const hasError = useStore(useCallback((s: { errorNodeIds: Set<string> }) => s.errorNodeIds.has(id), [id]));
  // nMatch validator results flow through errorNodeIds via initValidation (Phase 71 D-20).
  // Phase 66 — code-panel ↔ canvas bidirectional traceability (D-05, D-09, D-11).
  // Per-node primitive-boolean selectors mirror the `hasAnchor` shape above.
  // Re-render fanout: toggling one ID only re-renders the affected StreamNode(s),
  // not all N nodes — zustand sees the boolean flip for `n1` only and skips
  // the other subscribers (Research Pattern 9).
  const isCodeHovered = useStore(
    useCallback((s: { hoveredSourceIds: Set<string> }) => s.hoveredSourceIds.has(id), [id]),
  );
  const isCodePinned = useStore(
    useCallback((s: { pinnedSourceIds: Set<string> }) => s.pinnedSourceIds.has(id), [id]),
  );
  // Phase 68 Plan 03 — 4-layer independent-toggle state. Per-handle dim is
  // driven by activeLayers.Hydraulic / activeLayers.Thermal directly. The
  // node-body visibility (D-02) is handled in CanvasPanel's enrichedNodes
  // pass; this component is responsible only for the per-port-handle
  // dim/lock behavior for dual-layer nodes (D-03), e.g. CAC with one of its
  // two layers off.
  const activeLayers = useStore(
    useCallback((s: { activeLayers: ActiveLayers }) => s.activeLayers, []),
  );
  const hideOffLayer = useStore(
    useCallback((s: { hideOffLayer: boolean }) => s.hideOffLayer, []),
  );
  const component = getComponent(nodeData.componentId);
  if (!component) return null;

  const Icon = getComponentIcon(nodeData.componentId);

  // Phase 72 — leading-band identity (replaces border-as-accent). One band
  // div per layer the component belongs to, side by side horizontally. For
  // single-layer components (most), one solid band. For dual-layer
  // (ChannelAndContacts has both FlowPorts and ThermalPorts), the band
  // splits half/half. Components with no layer association (e.g. Resources)
  // render no band. Visual-only — uses getDisplayLayers, not
  // getComponentLayers, so visibility/dim behavior is unaffected.
  const layers = getDisplayLayers(component);
  const bandHeightPx = selected ? 8 : 4;

  const flowPorts = component.ports.filter((p) => p.type === "FlowPort");
  const thermalPorts = component.ports.filter((p) => p.type === "ThermalPort");
  const bcPorts = component.ports.filter((p) => p.type === "BCPort");

  // Phase 68 D-03: when a node belongs to BOTH Hydraulic and Thermal layers
  // (CAC today) and one of those layers is off, the off-layer port handles
  // dim + lock (dim mode) or are display:none (hide mode); the node body
  // stays visible because the OTHER layer is on (D-02).
  const componentLayers = getComponentLayers(component);
  const isDualLayer =
    componentLayers.includes("Hydraulic") && componentLayers.includes("Thermal");
  const flowOff = isDualLayer && activeLayers.Hydraulic === false;
  const thermalOff = isDualLayer && activeLayers.Thermal === false;
  const dimFlowHandles = flowOff && !hideOffLayer;
  const hideFlowHandles = flowOff && hideOffLayer;
  const dimThermalHandles = thermalOff && !hideOffLayer;
  const hideThermalHandles = thermalOff && hideOffLayer;

  // Combined error surface — errorNodeIds is now the sole source (Phase 71 D-20).
  const hasAnyError = hasError;

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
      // Phase 72 — `data-stream-node-id` is the flash target for the
      // canvas-pan-to-validation-result animation (CanvasPanel onNodeFlash).
      // Anchored on THIS element (not on xyflow's outer wrapper carrying
      // `data-id`) so the flash outline lives on the same element as the
      // persistent error outline below — otherwise the persistent outline
      // (which is a DOM child of the xyflow wrapper) paints on top of the
      // flash and the user perceives "nothing happens" when clicking an
      // error row whose node is already errored.
      data-stream-node-id={id}
      // Phase 72 — outline + box-shadow set via inline style. The CSS
      // pipeline in the dev configuration serves stale compiled output
      // for .stream-node--* class rules; inline style ships via JS HMR
      // and wins specificity over any class rule. Outline state
      // priority: error → autoExtended → none. Ring priority:
      // selected → code-pinned → code-hovered → rest. The selected ring
      // keeps its 200 ms transition (the band thickens in sync; gentle
      // is the right feel for explicit canvas-side selection). Code-link
      // rings SNAP — no transition — because (a) a delay made the click
      // feel laggy in live verification, (b) the marching-ants edge
      // animation is the primary signal anyway, the node ring is a
      // reinforcement. Integer spreads (2 px / 3 px) instead of 2.5 to
      // avoid subpixel-rounding asymmetry where one side rendered fatter
      // than the other. The `data-code-link` attribute is the modern
      // state marker for tests + selectors; the old className-side
      // markers (.stream-node--code-{hover,pinned}) are gone.
      data-code-link={
        isCodePinned ? "pinned" : isCodeHovered ? "hover" : undefined
      }
      className={`relative rounded-md min-w-[140px] ${
        selected ? "transition-[box-shadow] duration-200" : ""
      }`}
      style={{
        boxShadow: selected
          ? "0 0 0 1px var(--canvas), 0 0 0 3px var(--ring)"
          : isCodePinned
            ? "0 0 0 1px var(--canvas), 0 0 0 3px var(--foreground)"
            : isCodeHovered
              ? "0 0 0 1px var(--canvas), 0 0 0 2px var(--foreground)"
              : "0 0 0 1px var(--canvas), 0 0 0 2px var(--node-ring-rest)",
        outline: hasAnyError
          ? "2px solid var(--destructive)"
          : nodeData.autoExtended
            ? "2px dashed var(--chart-5)"
            : "none",
        outlineOffset: nodeData.autoExtended ? "2px" : "0",
      }}
    >
      {/* Phase 72 — visual surface wrapper. overflow-hidden + rounded-md
          clip the band's top corners to match the wrapper's outline. Kept
          INSIDE the positioned outer div so xyflow's port Handles (which
          attach to the positioned ancestor and project outside its
          bounding box) are NOT clipped by this overflow. First-pass put
          overflow-hidden on the outer wrapper itself, which clipped half
          of every port handle. */}
      <div className="rounded-md overflow-hidden">
        {/* Leading-band layer identity. Replaces the prior border-left
            accent. Solid for single-layer components; split half/half
            for dual-layer (CAC on Hydraulic+Thermal); n-way split for
            >2 layers (forward-compatible — no component has this
            today). Band height thickens 4 → 8 px on selection. */}
        {layers.length > 0 && (
          <div
            className="flex w-full transition-[height]"
            style={{ height: bandHeightPx }}
            aria-hidden="true"
            data-testid="stream-node-band"
          >
            {layers.map((layer) => (
              <div
                key={layer}
                data-layer={layer}
                style={{
                  flex: 1,
                  backgroundColor: LAYER_COLOR_VAR[layer],
                }}
              />
            ))}
          </div>
        )}
        {/* Body uses bg-card (recommitted in index.css to be distinctly
            darker than --canvas) so the node reads as a cell on the work
            surface. First-pass used bg-canvas, which matched the canvas
            color exactly and rendered bodies invisible. */}
        <div className="bg-card p-2">
          <div className="flex items-center gap-1 text-label text-muted-foreground">
            <Icon className="w-3.5 h-3.5" />
            {component.label}
          </div>
          <div className="font-semibold text-body">{nodeData.instanceName}</div>
          {sourceLabel && (
            <div
              className={`text-label ${sourceLabel.muted ? "text-destructive/80" : "text-muted-foreground"}`}
              data-testid="source-block-label"
            >
              {sourceLabel.text}
            </div>
          )}
        </div>
      </div>
      {flowPorts.map((port) => (
        <FlowPortHandle
          key={port.name}
          nodeId={id}
          port={port}
          dimFlowHandles={dimFlowHandles}
          hideFlowHandles={hideFlowHandles}
        />
      ))}
      {thermalPorts.map((port) => {
        // Phase 64 Pitfall 6 fix: pair-thermal ports (CAC + HD — they carry
        // `pair_with` and have no static `side`) route through
        // `ThermalPortHandle`, which resolves a defined side via D-18
        // suffix-locked axis-flip (now with Phase 73 flow-axis hint so the
        // pair lands perpendicular to flow on dual-domain nodes).
        // Single-port thermal entries (e.g. ConstantTemperature.thermal) keep
        // the registry-default `side` — they have no pair to swing.
        if (port.pair_with) {
          return (
            <ThermalPortHandle
              key={port.name}
              nodeId={id}
              port={port as ThermalPortLike}
              dimThermalHandles={dimThermalHandles}
              hideThermalHandles={hideThermalHandles}
            />
          );
        }
        // Phase 73 — single thermal ports adopt the crafted hex mark too.
        const singleSide = (port.side ?? "left") as Side;
        return (
          <Handle
            key={port.name}
            id={port.name}
            type={singleSide === "right" || singleSide === "bottom" ? "source" : "target"}
            position={sideToPosition[singleSide]}
            data={{ portType: port.type }}
            data-port-type="thermal"
            style={{
              background: "transparent",
              border: "none",
              width: 14,
              height: 14,
              borderRadius: "50%",
              // Phase 68 D-03: per-handle off-layer treatment for the
              // Thermal layer (single-port branch — ConstantTemperature etc.).
              // Hide mode beats dim mode.
              ...(hideThermalHandles
                ? { display: "none" as const }
                : dimThermalHandles
                  ? { opacity: 0.2, pointerEvents: "none" as const }
                  : {}),
            }}
          >
            <ThermalHexMark />
          </Handle>
        );
      })}
      {bcPorts.map((port) => {
        // Plan 63.1-12 RC-2: BCPort is now used on both Sources (source-side,
        // e.g. WT.T_wall_out) AND Hydraulic consumers (target-side, e.g.
        // Channel.T_wall_left on the bottom edge). The dispatch keys off the
        // component category — see registry.test.ts "BCPort allowed on
        // Sources OR Hydraulic" invariant.
        //
        // Phase 73 — BC handles now route through BCPortHandle, which uses
        // the side-priority engine (flow > thermal > BC) to pick a side that
        // doesn't collide with flow/thermal. Fixes Channel.T_wall_left
        // (static bottom) ↔ port_out (autoflipped to bottom) overlap.
        const isBCSource = component.category === "Sources";
        return (
          <BCPortHandle
            key={port.name}
            nodeId={id}
            port={port}
            isBCSource={isBCSource}
          />
        );
      })}
    </div>
  );
}
