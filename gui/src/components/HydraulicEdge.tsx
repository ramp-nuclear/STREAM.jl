import { memo } from "react";
import {
  getSmoothStepPath,
  BaseEdge,
  type EdgeProps,
} from "@xyflow/react";

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
 */
function HydraulicEdge({
  sourceX,
  sourceY,
  targetX,
  targetY,
  sourcePosition,
  targetPosition,
  id,
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

  return <BaseEdge id={id} path={path} style={style} markerEnd={markerEnd} />;
}

export default memo(HydraulicEdge);
