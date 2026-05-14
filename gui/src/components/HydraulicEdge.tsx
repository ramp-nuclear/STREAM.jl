import { memo } from "react";
import {
  getSmoothStepPath,
  BaseEdge,
  Position,
  type EdgeProps,
} from "@xyflow/react";
import useStore from "../store/useStore";

/**
 * Custom hydraulic edge — smoothstep routing with closed arrowhead.
 *
 * Bidirectional hydraulic pairs (Phase 64 — D-06, D-07, D-08, D-17):
 *   When two `type === "hydraulicEdge"` edges exist between the same node pair
 *   in opposite directions, each draws a ±8px perpendicular bow so the two
 *   paths render as parallel offsets instead of overlapping on a single midline
 *   (Example-1 X-cross fix). Direction is stable: the smaller-id edge bows
 *   `+BOW_PX`, the larger-id edge bows `-BOW_PX`.
 *
 *   The same-type filter (D-17) — only `type === "hydraulicEdge"` counts as a
 *   sibling. A BCEdge / thermal edge between the same two nodes does NOT
 *   pair with a hydraulic edge.
 *
 *   The sibling lookup uses `useStore.getState().edges` synchronously inside
 *   render (RESEARCH.md Pattern 3). Subscribing via the `useStore` hook would
 *   cause a re-render storm — ReactFlow already re-runs the edge render on every
 *   drag tick (because `sourceX/Y/targetX/Y` props change), which is also when
 *   the sibling set might shift, so the synchronous read is consistency-safe.
 *
 *   Bow application strategy (RESEARCH.md §"Anti-parallel bow inside
 *   HydraulicEdge", option (a)): pre-offset the endpoint coordinates
 *   perpendicular to the dominant axis BEFORE calling `getSmoothStepPath`.
 *   Simpler than hand-building a path string with a midpoint kink, and the
 *   visual result is a parallel-shifted smoothstep — equivalent at the
 *   midpoint where the two siblings would otherwise overlap.
 */
const BOW_PX = 8; // D-07 — constant perpendicular bow, not user-tunable in v1.2

function HydraulicEdge({
  id,
  source,
  target,
  sourceX,
  sourceY,
  targetX,
  targetY,
  sourcePosition,
  targetPosition,
  style,
  markerEnd,
}: EdgeProps) {
  // D-08 swap + D-17 same-type filter. Synchronous read — NO hook subscription.
  const allEdges = useStore.getState().edges;
  const sibling = allEdges.find(
    (e) =>
      e.id !== id &&
      e.type === "hydraulicEdge" &&
      e.source === target &&
      e.target === source,
  );

  // Deterministic direction: smaller-id bows +BOW_PX, larger-id bows -BOW_PX.
  // Lexicographic id comparison makes the choice stable across re-renders, so
  // the two siblings always bow in OPPOSITE directions and never flicker.
  const bow = sibling ? (id < sibling.id ? BOW_PX : -BOW_PX) : 0;

  // Apply bow perpendicular to the dominant axis. For a horizontal edge
  // (Left/Right source position), shift both Y endpoints by `bow`. Otherwise
  // (Top/Bottom), shift both X endpoints. The "perpendicular axis" is keyed
  // off the source position — for an anti-parallel pair both endpoints share
  // the same orientation, so this also covers the target side.
  const horizontal =
    sourcePosition === Position.Left || sourcePosition === Position.Right;

  const adjSourceX = horizontal ? sourceX : sourceX + bow;
  const adjSourceY = horizontal ? sourceY + bow : sourceY;
  const adjTargetX = horizontal ? targetX : targetX + bow;
  const adjTargetY = horizontal ? targetY + bow : targetY;

  const [path] = getSmoothStepPath({
    sourceX: adjSourceX,
    sourceY: adjSourceY,
    targetX: adjTargetX,
    targetY: adjTargetY,
    sourcePosition,
    targetPosition,
  });

  return <BaseEdge id={id} path={path} style={style} markerEnd={markerEnd} />;
}

export default memo(HydraulicEdge);
