import { BaseEdge, type EdgeProps } from "@xyflow/react";

/**
 * Compute a cubic bezier path that avoids overlap in loop topologies.
 *
 * Rules:
 * - Source left of target (dx > 50): standard left-to-right bezier
 * - Source above target (dy >= 0): arc around the RIGHT side
 * - Source below target (dy < 0):  arc around the LEFT side
 *
 * This ensures two edges forming a vertical loop route on opposite sides
 * of the nodes instead of overlapping through the center.
 */
function getStreamPath(
  sourceX: number,
  sourceY: number,
  targetX: number,
  targetY: number,
): [path: string, labelX: number, labelY: number] {
  const dx = targetX - sourceX;
  const dy = targetY - sourceY;

  if (dx > 50) {
    // Natural left-to-right: standard S-curve bezier
    const cp = Math.abs(dx) * 0.45;
    return [
      `M ${sourceX},${sourceY} C ${sourceX + cp},${sourceY} ${targetX - cp},${targetY} ${targetX},${targetY}`,
      (sourceX + targetX) / 2,
      (sourceY + targetY) / 2,
    ];
  }

  // Source is to the right of (or same column as) target — need to arc around.
  // Use a C-shape whose width scales with horizontal overlap plus a minimum.
  const offset = Math.max(90, Math.abs(dx) + 90);

  if (dy >= 0) {
    // Source above: arc around the RIGHT side
    const cx = sourceX + offset;
    return [
      `M ${sourceX},${sourceY} C ${cx},${sourceY} ${targetX + offset},${targetY} ${targetX},${targetY}`,
      cx,
      (sourceY + targetY) / 2,
    ];
  } else {
    // Source below: arc around the LEFT side
    const cx = sourceX - offset;
    return [
      `M ${sourceX},${sourceY} C ${cx},${sourceY} ${targetX - offset},${targetY} ${targetX},${targetY}`,
      cx,
      (sourceY + targetY) / 2,
    ];
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
  const [edgePath] = getStreamPath(sourceX, sourceY, targetX, targetY);
  return <BaseEdge id={id} path={edgePath} markerEnd={markerEnd} style={style} />;
}
