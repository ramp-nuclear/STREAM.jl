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
  type Side,
} from "@/lib/autoflip";

// Phase 72 — flow-port colors stay as inline hex (documented JIT-bypass);
// per Phase 72 brief their tokenization is deferred to the edges-and-code-
// preview shape session. THERMAL_HANDLE values consume the new layer-thermal
// token (handle is per definition the Thermal layer's signal).
const FLOW_IN_BG = "#60a5fa";       // blue-400 (port_in — incoming flow)
const FLOW_IN_BORDER = "#1d4ed8";   // blue-700
const FLOW_OUT_BG = "#f87171";      // red-400 (port_out — outgoing flow)
const FLOW_OUT_BORDER = "#b91c1c";  // red-700

const THERMAL_HANDLE_COLOR = "var(--color-layer-thermal)";
const THERMAL_HANDLE_BORDER =
  "color-mix(in oklch, var(--color-layer-thermal) 75%, black)";

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
  const defaultSide = (port.side as Side | undefined) ?? "left";
  const resolvedSide = useStore(
    useCallback(
      (s: { nodes: Node[]; edges: Edge[] }) =>
        (resolveFlowPortAssignment(s.nodes, s.edges, nodeId, getComponent)[
          port.name
        ] ?? defaultSide) as Side,
      [nodeId, port.name, defaultSide],
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
          // Phase 68 D-03: per-handle off-layer treatment. Hide mode takes
          // precedence over dim mode (display:none beats opacity 0.2).
          ...(hideFlowHandles
            ? { display: "none" as const }
            : dimFlowHandles
              ? { opacity: 0.2, pointerEvents: "none" as const }
              : {}),
        }}
      />
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
        // Phase 68 D-03: per-handle off-layer treatment for the Thermal
        // layer. Hide mode beats dim mode.
        ...(hideThermalHandles
          ? { display: "none" as const }
          : dimThermalHandles
            ? { opacity: 0.2, pointerEvents: "none" as const }
            : {}),
      }}
    />
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
      // Phase 72 P10 (2026-05-22) — box-shadow moved from CSS class to
      // inline style after seven CSS-side passes failed to land. The
      // dev-server CSS pipeline (Vite + Tailwind v4 @theme inline + the
      // .vite/deps optimizer cache) was serving stale compiled output
      // for class rules even though body-level CSS updated fine via
      // HMR (verified with a magenta-probe diagnostic). Inline style
      // bypasses the entire CSS pipeline — Tailwind, class cascade,
      // file caching — and ships with the JS bundle that HMR DOES
      // refresh reliably. transition-[box-shadow] duration-200 in the
      // className still applies; transitions work on inline-styled
      // properties identically to class-styled ones.
      //
      // Color choices:
      //   - rest: #6e6e6e dark / #c3c3c3 light, plain hex, no OKLCH,
      //     no alpha. Resolved per theme via the ternary on a body
      //     class check (htmlElement.classList.contains('dark') style,
      //     but here we go simpler — both light and dark themes use
      //     the same mid-tone grey via the `theme-aware-ring-rest`
      //     CSS var defined inline below).
      //   - selected: var(--ring) — Hydraulic light blue, 2 px.
      //
      // Geometry: two-stop box-shadow. First stop fills a 1 px gap
      // around the body with the canvas color (the "offset"); second
      // stop draws the actual ring 2 px outside that.
      className={`relative rounded-md min-w-[140px] transition-[box-shadow] duration-200 ${
        hasAnyError ? "outline outline-2 outline-[var(--destructive)]" : ""
      } ${
        // Classes preserved (the code-preview ↔ canvas linking layer expects
        // them on the DOM for state tracking + tests). CSS rules are no-ops
        // in index.css — they no longer paint anything, so they can't add
        // back the blue ring the user has been chasing.
        isCodeHovered ? "stream-node--code-hover" : ""
      } ${isCodePinned ? "stream-node--code-pinned" : ""} ${
        nodeData.autoExtended
          ? "outline outline-2 outline-dashed outline-[var(--chart-5)] outline-offset-2"
          : ""
      }`}
      style={{
        boxShadow: selected
          ? "0 0 0 1px var(--canvas), 0 0 0 3px var(--ring)"
          : "0 0 0 1px var(--canvas), 0 0 0 2px var(--node-ring-rest, #6e6e6e)",
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
              hideThermalHandles={hideThermalHandles}
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
              // Phase 68 D-03: per-handle off-layer treatment for the
              // Thermal layer (single-port branch — ConstantTemperature etc.).
              // Hide mode beats dim mode.
              ...(hideThermalHandles
                ? { display: "none" as const }
                : dimThermalHandles
                  ? { opacity: 0.2, pointerEvents: "none" as const }
                  : {}),
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
