/**
 * edgeRouting.ts — obstacle-avoiding orthogonal edge router (Phase 72 Phase B).
 *
 * xyflow's built-in edge routers (default, smoothstep, step, bezier) treat
 * edges as point-to-point and have zero awareness of other nodes' bboxes.
 * That produces edges that cut through node bodies whenever the source and
 * target ports' outward directions force the path to traverse the space the
 * nodes occupy — the canonical example is a vertical hydraulic loop where
 * the return edge needs to wrap around the network.
 *
 * This module computes an orthogonal path from a source port to a target port
 * that does NOT cross the interior of any node bbox (source and target nodes
 * included). It tries several candidate paths and picks the one with zero
 * crossings, fewest turns, and shortest length, in that priority.
 *
 * Pure function. Zero React / xyflow runtime imports — only `Position` enum
 * for input typing.
 */

import { Position } from "@xyflow/react";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface Bbox {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface Point {
  x: number;
  y: number;
}

export interface RouteInput {
  sourceX: number;
  sourceY: number;
  sourcePosition: Position;
  targetX: number;
  targetY: number;
  targetPosition: Position;
  /** Every node bbox the path must NOT cross. Includes source + target nodes:
   *  the path naturally touches their perimeter at the port, but must stay
   *  outside the interior. */
  obstacles: Bbox[];
  /** Distance the path extends from each port before turning. Default 20. */
  portMargin?: number;
  /** Distance between the wrap lane and the closest obstacle. Default 32. */
  laneMargin?: number;
}

// ---------------------------------------------------------------------------
// Geometric helpers
// ---------------------------------------------------------------------------

/** Outward unit vector for a port position (away from the node body). */
function outwardVec(pos: Position): { dx: number; dy: number } {
  switch (pos) {
    case Position.Top:
      return { dx: 0, dy: -1 };
    case Position.Bottom:
      return { dx: 0, dy: 1 };
    case Position.Left:
      return { dx: -1, dy: 0 };
    case Position.Right:
      return { dx: 1, dy: 0 };
  }
}

/** Tests whether an orthogonal segment crosses a bbox interior.
 *  The segment must be axis-aligned (one of x1===x2 or y1===y2). An epsilon
 *  margin avoids false positives when the segment runs ON the bbox perimeter
 *  (e.g. exits a port on the bbox edge). */
function segmentCrossesBbox(
  x1: number,
  y1: number,
  x2: number,
  y2: number,
  bbox: Bbox,
  epsilon = 0.5,
): boolean {
  const bxMin = bbox.x + epsilon;
  const bxMax = bbox.x + bbox.width - epsilon;
  const byMin = bbox.y + epsilon;
  const byMax = bbox.y + bbox.height - epsilon;

  if (x1 === x2) {
    if (x1 <= bxMin || x1 >= bxMax) return false;
    const yLo = Math.min(y1, y2);
    const yHi = Math.max(y1, y2);
    return yHi > byMin && yLo < byMax;
  }
  if (y1 === y2) {
    if (y1 <= byMin || y1 >= byMax) return false;
    const xLo = Math.min(x1, x2);
    const xHi = Math.max(x1, x2);
    return xHi > bxMin && xLo < bxMax;
  }
  return false; // Non-axis-aligned — not expected for our orthogonal paths.
}

function pathCrossings(points: Point[], obstacles: Bbox[]): number {
  let count = 0;
  for (let i = 0; i < points.length - 1; i++) {
    const a = points[i];
    const b = points[i + 1];
    for (const bbox of obstacles) {
      if (segmentCrossesBbox(a.x, a.y, b.x, b.y, bbox)) count++;
    }
  }
  return count;
}

function pathLength(points: Point[]): number {
  let total = 0;
  for (let i = 0; i < points.length - 1; i++) {
    total += Math.abs(points[i + 1].x - points[i].x) + Math.abs(points[i + 1].y - points[i].y);
  }
  return total;
}

/** A "turn" is a corner between two consecutive segments. Path with N points
 *  has at most N-2 turns; consecutive points on the same axis don't count. */
function pathTurns(points: Point[]): number {
  if (points.length < 3) return 0;
  let turns = 0;
  for (let i = 1; i < points.length - 1; i++) {
    const prev = points[i - 1];
    const cur = points[i];
    const next = points[i + 1];
    const inHoriz = prev.y === cur.y;
    const outHoriz = cur.y === next.y;
    if (inHoriz !== outHoriz) turns++;
  }
  return turns;
}

/** Collapse colinear consecutive points so length / turn counts are accurate.
 *  Three points in a straight line collapse to two. */
function simplify(points: Point[]): Point[] {
  if (points.length < 3) return points.slice();
  const out: Point[] = [points[0]];
  for (let i = 1; i < points.length - 1; i++) {
    const prev = out[out.length - 1];
    const cur = points[i];
    const next = points[i + 1];
    const colinearH = prev.y === cur.y && cur.y === next.y;
    const colinearV = prev.x === cur.x && cur.x === next.x;
    if (!(colinearH || colinearV)) out.push(cur);
  }
  out.push(points[points.length - 1]);
  return out;
}

// ---------------------------------------------------------------------------
// Candidate-path constructors
// ---------------------------------------------------------------------------

/** Naive smoothstep-style Z-path: extend from source by portMargin, extend to
 *  target by portMargin, connect via one intermediate segment. */
function naivePath(
  sx: number,
  sy: number,
  sPos: Position,
  tx: number,
  ty: number,
  tPos: Position,
  portMargin: number,
): Point[] {
  const sOut = outwardVec(sPos);
  const tOut = outwardVec(tPos);

  // Source exits the port outward by portMargin. Target is approached from
  // outward direction (the path comes from outside, going INTO the port).
  const sExit: Point = { x: sx + sOut.dx * portMargin, y: sy + sOut.dy * portMargin };
  const tApproach: Point = { x: tx + tOut.dx * portMargin, y: ty + tOut.dy * portMargin };

  // Connect sExit → tApproach orthogonally. If source axis matches target axis,
  // produce an L (one turn); otherwise a Z (two turns). Pick the leg-axis from
  // the source's outward direction so the first segment continues in the
  // expected direction (the user reads "exits port_out going down").
  const sourceHoriz = sOut.dx !== 0;

  let mid: Point[];
  if (sourceHoriz) {
    // Source extends horizontally → mid uses target.y for the horizontal leg.
    mid = [{ x: tApproach.x, y: sExit.y }];
  } else {
    // Source extends vertically → mid uses source.y for the vertical leg.
    mid = [{ x: sExit.x, y: tApproach.y }];
  }

  return simplify([{ x: sx, y: sy }, sExit, ...mid, tApproach, { x: tx, y: ty }]);
}

/** Wrap-via-lane path: extend from source outward, travel to a lane axis
 *  (laneX for vertical lanes left/right, laneY for horizontal lanes top/
 *  bottom), travel along the lane past the target's level, then approach
 *  target. Produces 4 turns in the general case. */
function wrapVerticalLane(
  sx: number,
  sy: number,
  sPos: Position,
  tx: number,
  ty: number,
  tPos: Position,
  portMargin: number,
  laneX: number,
  clusterTopLaneY: number,
  clusterBottomLaneY: number,
): Point[] {
  const sOut = outwardVec(sPos);
  const tOut = outwardVec(tPos);
  const sExit: Point = { x: sx + sOut.dx * portMargin, y: sy + sOut.dy * portMargin };
  const tApproach: Point = { x: tx + tOut.dx * portMargin, y: ty + tOut.dy * portMargin };

  // Pivot Y must be OUTSIDE the cluster — not at the port's own Y (which is
  // typically INSIDE the cluster and would cause the horizontal segment to
  // cross other node bodies). Pick the cluster-edge lane closer to each port.
  // For a source on the bottom of the cluster, route via the bottom lane;
  // for a source near the top, the top lane.
  const clusterMidY = (clusterTopLaneY + clusterBottomLaneY) / 2;
  const sourcePivotY =
    sExit.y >= clusterMidY ? clusterBottomLaneY : clusterTopLaneY;
  const targetPivotY =
    tApproach.y >= clusterMidY ? clusterBottomLaneY : clusterTopLaneY;

  return simplify([
    { x: sx, y: sy },
    sExit,
    { x: sExit.x, y: sourcePivotY }, // extend in source's outward direction past the cluster
    { x: laneX, y: sourcePivotY },   // travel horizontally to the side lane (outside cluster)
    { x: laneX, y: targetPivotY },   // travel along the side lane to target's row
    { x: tApproach.x, y: targetPivotY }, // travel horizontally back toward target.x
    tApproach,
    { x: tx, y: ty },
  ]);
}

function wrapHorizontalLane(
  sx: number,
  sy: number,
  sPos: Position,
  tx: number,
  ty: number,
  tPos: Position,
  portMargin: number,
  laneY: number,
  clusterLeftLaneX: number,
  clusterRightLaneX: number,
): Point[] {
  const sOut = outwardVec(sPos);
  const tOut = outwardVec(tPos);
  const sExit: Point = { x: sx + sOut.dx * portMargin, y: sy + sOut.dy * portMargin };
  const tApproach: Point = { x: tx + tOut.dx * portMargin, y: ty + tOut.dy * portMargin };

  const clusterMidX = (clusterLeftLaneX + clusterRightLaneX) / 2;
  const sourcePivotX =
    sExit.x >= clusterMidX ? clusterRightLaneX : clusterLeftLaneX;
  const targetPivotX =
    tApproach.x >= clusterMidX ? clusterRightLaneX : clusterLeftLaneX;

  return simplify([
    { x: sx, y: sy },
    sExit,
    { x: sourcePivotX, y: sExit.y },
    { x: sourcePivotX, y: laneY },
    { x: targetPivotX, y: laneY },
    { x: targetPivotX, y: tApproach.y },
    tApproach,
    { x: tx, y: ty },
  ]);
}

// ---------------------------------------------------------------------------
// Main entry
// ---------------------------------------------------------------------------

/** Compute an orthogonal path from source port to target port that minimizes
 *  obstacle crossings. Returns the best candidate as an array of points. */
export function computeRoutePoints(input: RouteInput): Point[] {
  const {
    sourceX: sx,
    sourceY: sy,
    sourcePosition: sPos,
    targetX: tx,
    targetY: ty,
    targetPosition: tPos,
    obstacles,
    portMargin = 20,
    laneMargin = 32,
  } = input;

  // Compute lane positions from the obstacles' bbox bounds.
  let minX = Infinity;
  let maxX = -Infinity;
  let minY = Infinity;
  let maxY = -Infinity;
  for (const o of obstacles) {
    if (o.x < minX) minX = o.x;
    if (o.x + o.width > maxX) maxX = o.x + o.width;
    if (o.y < minY) minY = o.y;
    if (o.y + o.height > maxY) maxY = o.y + o.height;
  }
  // Also fold source & target endpoints in case the cluster is empty
  // (degenerate; shouldn't happen but defensive).
  if (!Number.isFinite(minX)) {
    minX = Math.min(sx, tx);
    maxX = Math.max(sx, tx);
    minY = Math.min(sy, ty);
    maxY = Math.max(sy, ty);
  }
  const leftLaneX = minX - laneMargin;
  const rightLaneX = maxX + laneMargin;
  const topLaneY = minY - laneMargin;
  const bottomLaneY = maxY + laneMargin;

  const candidates: { name: string; path: Point[] }[] = [
    { name: "naive", path: naivePath(sx, sy, sPos, tx, ty, tPos, portMargin) },
    {
      name: "right",
      path: wrapVerticalLane(sx, sy, sPos, tx, ty, tPos, portMargin, rightLaneX, topLaneY, bottomLaneY),
    },
    {
      name: "left",
      path: wrapVerticalLane(sx, sy, sPos, tx, ty, tPos, portMargin, leftLaneX, topLaneY, bottomLaneY),
    },
    {
      name: "bottom",
      path: wrapHorizontalLane(sx, sy, sPos, tx, ty, tPos, portMargin, bottomLaneY, leftLaneX, rightLaneX),
    },
    {
      name: "top",
      path: wrapHorizontalLane(sx, sy, sPos, tx, ty, tPos, portMargin, topLaneY, leftLaneX, rightLaneX),
    },
  ];

  // Rank by (crossings, turns, length). Pick the best.
  const scored = candidates.map((c) => ({
    ...c,
    crossings: pathCrossings(c.path, obstacles),
    turns: pathTurns(c.path),
    length: pathLength(c.path),
  }));
  scored.sort((a, b) => {
    if (a.crossings !== b.crossings) return a.crossings - b.crossings;
    if (a.turns !== b.turns) return a.turns - b.turns;
    return a.length - b.length;
  });

  return scored[0].path;
}

// ---------------------------------------------------------------------------
// SVG path serialization
// ---------------------------------------------------------------------------

/** Convert a list of orthogonal points to an SVG path string with optionally
 *  rounded corners at turns. Rounded corners use small quadratic Bezier curves
 *  matching the visual style of xyflow's smoothstep edges (default radius 6). */
export function pointsToSvgPath(points: Point[], cornerRadius = 6): string {
  if (points.length === 0) return "";
  if (points.length === 1) return `M ${points[0].x} ${points[0].y}`;

  if (cornerRadius <= 0) {
    // Sharp corners — straight M/L commands.
    let d = `M ${points[0].x} ${points[0].y}`;
    for (let i = 1; i < points.length; i++) {
      d += ` L ${points[i].x} ${points[i].y}`;
    }
    return d;
  }

  // Rounded corners. For each interior point, the segment incoming and outgoing
  // are shortened by min(cornerRadius, segHalfLen) and joined by a quadratic
  // Bezier curve through the corner point.
  let d = `M ${points[0].x} ${points[0].y}`;
  for (let i = 1; i < points.length - 1; i++) {
    const prev = points[i - 1];
    const cur = points[i];
    const next = points[i + 1];

    const inDx = cur.x - prev.x;
    const inDy = cur.y - prev.y;
    const outDx = next.x - cur.x;
    const outDy = next.y - cur.y;

    const inLen = Math.abs(inDx) + Math.abs(inDy);
    const outLen = Math.abs(outDx) + Math.abs(outDy);
    const r = Math.min(cornerRadius, inLen / 2, outLen / 2);

    // Point r before the corner (along incoming direction).
    const ix = cur.x - Math.sign(inDx) * r;
    const iy = cur.y - Math.sign(inDy) * r;
    // Point r after the corner (along outgoing direction).
    const ox = cur.x + Math.sign(outDx) * r;
    const oy = cur.y + Math.sign(outDy) * r;

    d += ` L ${ix} ${iy} Q ${cur.x} ${cur.y} ${ox} ${oy}`;
  }
  d += ` L ${points[points.length - 1].x} ${points[points.length - 1].y}`;
  return d;
}
