import { BaseEdge, type EdgeProps } from "@xyflow/react";

// How far the arrowhead marker extends back from its tip (SVG units).
// Used to stop the path just before the node border so the arrowhead
// body doesn't get painted over by the node background.
const ARROW_CLEARANCE = 14;

// Fixed arc radius — how far control points bow out from the node column.
const ARC_OFFSET = 60;

/**
 * Compute a cubic bezier path that avoids overlap in loop topologies.
 *
 * All STREAM edges go from a port_out handle (right side) to a port_in
 * handle (left side).  When nodes are stacked vertically the two loop
 * edges would otherwise overlap through the center.  This function routes:
 *
 *   source above target → C-shape on the RIGHT
 *   source below target → C-shape on the LEFT
 *   source left  of target → standard S-curve bezier
 *
 * Symmetry: both control points of each C-shape share the same x value
 * (rightBound or leftBound), so the arc is a true mirror-image pair.
 *
 * Arrowhead visibility: the right-arc path approaches the target's LEFT
 * handle from the right, which would bury the arrowhead inside the node.
 * We stop the path ARROW_CLEARANCE px short so the arrowhead floats just
 * outside the node border.  The left-arc path approaches from the left and
 * terminates cleanly — no adjustment needed.
 */
function getStreamPath(
  sourceX: number,
  sourceY: number,
  targetX: number,
  targetY: number,
): string {
  const dx = targetX - sourceX;
  const dy = targetY - sourceY;

  if (dx > 50) {
    // Natural left-to-right: standard S-curve bezier, no offset needed.
    const cp = Math.abs(dx) * 0.45;
    return `M ${sourceX},${sourceY} C ${sourceX + cp},${sourceY} ${targetX - cp},${targetY} ${targetX},${targetY}`;
  }

  // Right-to-left (or same column): arc around the outside.
  const rightBound = Math.max(sourceX, targetX) + ARC_OFFSET;
  const leftBound  = Math.min(sourceX, targetX) - ARC_OFFSET;

  if (dy >= 0) {
    // Source above target → RIGHT-side C-shape.
    // Path approaches target from the right, so stop short to keep arrowhead visible.
    const endX = targetX + ARROW_CLEARANCE;
    return `M ${sourceX},${sourceY} C ${rightBound},${sourceY} ${rightBound},${targetY} ${endX},${targetY}`;
  } else {
    // Source below target → LEFT-side C-shape.
    // Path approaches from the left; arrowhead body is outside the node naturally.
    return `M ${sourceX},${sourceY} C ${leftBound},${sourceY} ${leftBound},${targetY} ${targetX},${targetY}`;
  }
}

export default function StreamEdge({
  id,
  sourceX,
  sourceY,
  targetX,
  targetY,
  markerEnd,
  style,
}: EdgeProps) {
  const path = getStreamPath(sourceX, sourceY, targetX, targetY);
  return <BaseEdge id={id} path={path} markerEnd={markerEnd} style={style} />;
}
