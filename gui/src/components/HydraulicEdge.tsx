import { memo } from "react";
import { getSmoothStepPath, BaseEdge, type EdgeProps } from "@xyflow/react";

// Clearance (px) from the outermost handle to the arc peak.
// Should exceed nodeHeight/2 (~40px) plus a visual gap.
const MARGIN = 60;

/**
 * Custom hydraulic edge with three routing modes:
 *
 * - parallelOffset === 0  → standard smoothstep (single, non-bidirectional edge)
 * - parallelOffset  >  0  → cubic bezier arcing ABOVE both nodes
 * - parallelOffset  <  0  → cubic bezier arcing BELOW both nodes
 *
 * For bidirectional pairs the two edges form a racetrack oval that completely
 * avoids crossing, regardless of how the nodes are positioned. This matches
 * the visual convention used in hydraulic circuit diagrams.
 *
 * The ReactFlow official BiDirectionalEdge example uses a quadratic bezier
 * with direction determined by sourceX < targetX. That works for side-by-side
 * nodes but fails for STREAM's layout: both edges always go right→left (port_out
 * to port_in), so they get the same offset direction and still overlap. The
 * over/under racetrack routing solves all orientations.
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
  const parallelOffset = (data?.parallelOffset as number) ?? 0;

  let path: string;

  if (parallelOffset === 0) {
    [path] = getSmoothStepPath({
      sourceX,
      sourceY,
      targetX,
      targetY,
      sourcePosition,
      targetPosition,
    });
  } else if (parallelOffset > 0) {
    // Route ABOVE both nodes: arc peaks MARGIN px above the topmost handle
    const peakY = Math.min(sourceY, targetY) - MARGIN;
    path = `M ${sourceX} ${sourceY} C ${sourceX} ${peakY} ${targetX} ${peakY} ${targetX} ${targetY}`;
  } else {
    // Route BELOW both nodes: arc peaks MARGIN px below the bottommost handle
    const peakY = Math.max(sourceY, targetY) + MARGIN;
    path = `M ${sourceX} ${sourceY} C ${sourceX} ${peakY} ${targetX} ${peakY} ${targetX} ${targetY}`;
  }

  return <BaseEdge id={id} path={path} style={style} markerEnd={markerEnd} />;
}

export default memo(HydraulicEdge);
