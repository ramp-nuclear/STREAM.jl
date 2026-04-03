import { memo } from "react";
import { getSmoothStepPath, BaseEdge, type EdgeProps } from "@xyflow/react";

/**
 * Custom hydraulic edge that supports true parallel offset for bidirectional pairs.
 *
 * ReactFlow's smoothstep `pathOptions.offset` controls the step distance from the
 * node boundary, not lateral path separation. To get two visually distinct parallel
 * lines, we shift the source and target Y coordinates by `data.parallelOffset` pixels
 * before computing the path. A positive offset shifts the edge down, negative shifts up.
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
  data,
}: EdgeProps) {
  const offset = (data?.parallelOffset as number) ?? 0;

  const [edgePath] = getSmoothStepPath({
    sourceX,
    sourceY: sourceY + offset,
    targetX,
    targetY: targetY + offset,
    sourcePosition,
    targetPosition,
  });

  return <BaseEdge id={id} path={edgePath} style={style} markerEnd={markerEnd} />;
}

export default memo(HydraulicEdge);
