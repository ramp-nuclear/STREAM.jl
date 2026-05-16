import { memo, useCallback } from "react";
import {
  getSmoothStepPath,
  BaseEdge,
  type EdgeProps,
} from "@xyflow/react";
import useStore from "../store/useStore";

/**
 * Custom hydraulic edge — smoothstep routing with closed arrowhead.
 *
 * The anti-parallel ±8px bow from Phase 64 Plan 02 was removed once the
 * one-port-per-side FlowPort rule landed: under that rule, bidirectional
 * pairs between two components leave from different sides of each component
 * (e.g. pump_1.port_in on right + pump_1.port_out on bottom), so the two
 * edges no longer share a midline and the bow's only job evaporated. The bow
 * also detached path endpoints from handle DOM positions, leaving a visible
 * 8px gap between each port dot and its arrowhead — actively harmful once
 * the underlying overlap was already solved.
 *
 * Phase 66 — code-panel <-> edge bidirectional traceability.
 * Per-edge primitive-boolean selectors (matches StreamNode pattern,
 * see gui/PERFORMANCE.md rule 1) light the edge up when BOTH endpoint
 * UUIDs appear in `hoveredSourceIds` / `pinnedSourceIds` — which happens
 * exactly when a `connect(<src>.port_*, <tgt>.port_*)` sub-block is
 * hovered/pinned in the code panel. Single-endpoint matches (e.g. just
 * hovering `@named pump_1 = Pump()`) deliberately do NOT light edges:
 * only the pump node ring would, and the edge is incidental.
 */
function HydraulicEdge({
  sourceX,
  sourceY,
  targetX,
  targetY,
  sourcePosition,
  targetPosition,
  id,
  source,
  target,
  style,
  markerEnd,
}: EdgeProps) {
  const [path] = getSmoothStepPath({
    sourceX,
    sourceY,
    targetX,
    targetY,
    sourcePosition,
    targetPosition,
  });

  const isCodeHovered = useStore(
    useCallback(
      (s: { hoveredSourceIds: Set<string> }) =>
        s.hoveredSourceIds.has(source) && s.hoveredSourceIds.has(target),
      [source, target],
    ),
  );
  const isCodePinned = useStore(
    useCallback(
      (s: { pinnedSourceIds: Set<string> }) =>
        s.pinnedSourceIds.has(source) && s.pinnedSourceIds.has(target),
      [source, target],
    ),
  );

  // Pinned wins over hover (same cascade rule the canvas node ring uses).
  // Caller-provided `style` is the base; we override stroke + strokeWidth
  // only when an interaction is active. Colors mirror the canvas-node ring
  // tokens for visual consistency: sky-400 (#38bdf8) hover, sky-300 (#7dd3fc)
  // pinned, both ~30-50% thicker than the default edge.
  const mergedStyle = isCodePinned
    ? { ...style, stroke: "#7dd3fc", strokeWidth: 3 }
    : isCodeHovered
      ? { ...style, stroke: "#38bdf8", strokeWidth: 2.25 }
      : style;

  return (
    <BaseEdge id={id} path={path} style={mergedStyle} markerEnd={markerEnd} />
  );
}

export default memo(HydraulicEdge);
