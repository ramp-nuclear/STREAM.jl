import { memo, useCallback } from "react";
import { BaseEdge, type EdgeProps } from "@xyflow/react";
import useStore from "../store/useStore";
import {
  computeRoutePoints,
  pointsToSvgPath,
  type Bbox,
} from "../lib/edgeRouting";

/**
 * Custom hydraulic edge — obstacle-avoiding orthogonal router.
 *
 * Phase 72 Phase B — the previous smoothstep router treated edges as
 * point-to-point and was happy to cut through any node bbox in its way (the
 * canonical bug: a vertical loop's return edge passing straight through every
 * node between source and target). The new router pulls every node bbox from
 * the store, computes 5 candidate orthogonal paths (naive Z, plus wrap via
 * left / right / top / bottom lane), and picks the candidate that crosses no
 * bboxes — tiebreaking on fewer turns, then shorter total length.
 *
 * Source and target nodes are included as obstacles: the path must approach
 * their port from outside the body, not through it.
 *
 * The rendered path uses rounded corners (~6 px radius) to match the visual
 * style of the previous smoothstep edges.
 *
 * Phase 66 — code-panel <-> edge bidirectional traceability. Per-edge
 * primitive-boolean selectors (matches StreamNode pattern, see PERFORMANCE.md
 * rule 1) light the edge up when BOTH endpoint UUIDs appear in
 * `hoveredSourceIds` / `pinnedSourceIds`.
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
  // Subscribe to the nodes array directly. xyflow replaces this reference
  // whenever any node mutates (position drag, resize, etc.) — exactly when
  // we need to re-route. Other store changes don't replace this reference,
  // so the edge doesn't re-render on unrelated state changes.
  const nodes = useStore((s) => s.nodes);
  const obstacles: Bbox[] = [];
  for (const n of nodes) {
    const measured = n.measured as
      | { width?: number; height?: number }
      | undefined;
    const w = measured?.width ?? 140;
    const h = measured?.height ?? 70;
    obstacles.push({ x: n.position.x, y: n.position.y, width: w, height: h });
  }

  const points = computeRoutePoints({
    sourceX,
    sourceY,
    sourcePosition,
    targetX,
    targetY,
    targetPosition,
    obstacles,
  });
  const path = pointsToSvgPath(points);

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
