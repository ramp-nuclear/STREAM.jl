import { memo } from "react";
import { getSmoothStepPath, BaseEdge, type EdgeProps } from "@xyflow/react";

/**
 * Custom hydraulic edge — smoothstep routing with closed arrowhead.
 * Bidirectional pairs overlap slightly but arrowheads distinguish direction.
 */
function HydraulicEdge({
  id,
  sourceX,
  sourceY,
  targetX,
  targetY,
  sourcePosition,
  targetPosition,
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
