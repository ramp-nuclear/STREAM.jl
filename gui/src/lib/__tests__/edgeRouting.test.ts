// edgeRouting.test.ts — pure orthogonal router tests.

import { describe, it, expect } from "vitest";
import { Position } from "@xyflow/react";
import {
  computeRoutePoints,
  pointsToSvgPath,
  type Bbox,
} from "../edgeRouting";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function bboxesCrossedBy(points: { x: number; y: number }[], obstacles: Bbox[]): Bbox[] {
  const epsilon = 0.5;
  const hits: Bbox[] = [];
  for (let i = 0; i < points.length - 1; i++) {
    const a = points[i];
    const b = points[i + 1];
    for (const bbox of obstacles) {
      const bxMin = bbox.x + epsilon;
      const bxMax = bbox.x + bbox.width - epsilon;
      const byMin = bbox.y + epsilon;
      const byMax = bbox.y + bbox.height - epsilon;
      if (a.x === b.x) {
        if (a.x <= bxMin || a.x >= bxMax) continue;
        const yLo = Math.min(a.y, b.y);
        const yHi = Math.max(a.y, b.y);
        if (yHi > byMin && yLo < byMax) {
          hits.push(bbox);
        }
      } else if (a.y === b.y) {
        if (a.y <= byMin || a.y >= byMax) continue;
        const xLo = Math.min(a.x, b.x);
        const xHi = Math.max(a.x, b.x);
        if (xHi > bxMin && xLo < bxMax) {
          hits.push(bbox);
        }
      }
    }
  }
  return hits;
}

function turnCount(points: { x: number; y: number }[]): number {
  if (points.length < 3) return 0;
  let turns = 0;
  for (let i = 1; i < points.length - 1; i++) {
    const prev = points[i - 1];
    const cur = points[i];
    const next = points[i + 1];
    if ((prev.y === cur.y) !== (cur.y === next.y)) turns++;
  }
  return turns;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("computeRoutePoints", () => {
  it("clear path: short edge between two side-by-side nodes uses the naive Z-path", () => {
    const obstacles: Bbox[] = [
      { x: 0, y: 0, width: 100, height: 50 },     // source
      { x: 200, y: 0, width: 100, height: 50 },   // target
    ];
    const points = computeRoutePoints({
      sourceX: 100, sourceY: 25, sourcePosition: Position.Right,
      targetX: 200, targetY: 25, targetPosition: Position.Left,
      obstacles,
    });
    expect(bboxesCrossedBy(points, obstacles)).toEqual([]);
    expect(turnCount(points)).toBeLessThanOrEqual(2);
  });

  it("user scenario: vertical loop return edge wraps around the network without crossing any body", () => {
    // pump_1 (top), gravity_1 (middle-left), gravity_2 (middle-right),
    // gravity_3 (bottom). The return edge gravity_3.port_out (bottom of
    // gravity_3) → pump_1.port_in (top of pump_1) cannot route straight
    // up because pump_1 sits on the same x. It must wrap around the
    // cluster — left or right lane is acceptable, as long as it doesn't
    // cross any node body.
    const obstacles: Bbox[] = [
      { x: 450, y: 200, width: 180, height: 80 },   // pump_1
      { x: 320, y: 380, width: 180, height: 80 },   // gravity_1
      { x: 600, y: 380, width: 180, height: 80 },   // gravity_2
      { x: 450, y: 580, width: 180, height: 80 },   // gravity_3
    ];
    const points = computeRoutePoints({
      sourceX: 540, sourceY: 660, sourcePosition: Position.Bottom, // gravity_3 bottom-center
      targetX: 540, targetY: 200, targetPosition: Position.Top,    // pump_1 top-center
      obstacles,
    });
    expect(bboxesCrossedBy(points, obstacles)).toEqual([]);
    // Wraps via a side lane — 4 turns in the general case.
    expect(turnCount(points)).toBeLessThanOrEqual(4);
  });

  it("T-shape topology: return edge wraps cleanly past every node, no crossings (imp_bad_edges regression)", () => {
    // Cluster matches imp_bad_edges.png: 4 wide nodes in a T-shape. The
    // return edge from gravity_2 (bottom) → pump_1 (top) must wrap around
    // without crossing pump_1, gravity_1, gravity_2, or gravity_3 — the
    // wrap pivots must be OUTSIDE the cluster, not at the port's own Y.
    const obstacles: Bbox[] = [
      { x: 900, y: 380, width: 300, height: 80 },   // pump_1 (top)
      { x: 700, y: 600, width: 300, height: 80 },   // gravity_1 (middle-left)
      { x: 1100, y: 600, width: 300, height: 80 },  // gravity_3 (middle-right)
      { x: 900, y: 820, width: 300, height: 80 },   // gravity_2 (bottom)
    ];
    const points = computeRoutePoints({
      sourceX: 1050, sourceY: 900, sourcePosition: Position.Bottom, // gravity_2 bottom
      targetX: 1050, targetY: 380, targetPosition: Position.Top,    // pump_1 top
      obstacles,
    });
    expect(bboxesCrossedBy(points, obstacles)).toEqual([]);
  });

  it("source/target included as obstacles: a path with the same x on opposite-facing ports detours instead of going straight through", () => {
    // gravity_3.port_out (bottom) at (100, 100), pump_1.port_in (top) at (100, 0).
    // Default naive path is a vertical line that crosses both source and target
    // bbox interiors. Must detour.
    const obstacles: Bbox[] = [
      { x: 50, y: -50, width: 100, height: 50 },  // pump_1 — target above
      { x: 50, y: 100, width: 100, height: 50 },  // gravity_3 — source below
    ];
    const points = computeRoutePoints({
      sourceX: 100, sourceY: 100, sourcePosition: Position.Bottom,
      targetX: 100, targetY: 0, targetPosition: Position.Top,
      obstacles,
    });
    expect(bboxesCrossedBy(points, obstacles)).toEqual([]);
  });

  it("naive path is preferred when it's clean (fewer turns)", () => {
    // Two horizontally-adjacent nodes, source-right → target-left.
    // Naive 2-turn Z-path is clean; should win on tiebreak over the 4-turn wraps.
    const obstacles: Bbox[] = [
      { x: 0, y: 0, width: 100, height: 50 },
      { x: 300, y: 0, width: 100, height: 50 },
    ];
    const points = computeRoutePoints({
      sourceX: 100, sourceY: 25, sourcePosition: Position.Right,
      targetX: 300, targetY: 25, targetPosition: Position.Left,
      obstacles,
    });
    expect(turnCount(points)).toBeLessThanOrEqual(2);
  });

  it("path starts at source port and ends at target port (boundary preservation)", () => {
    const obstacles: Bbox[] = [
      { x: 0, y: 0, width: 100, height: 50 },
      { x: 200, y: 200, width: 100, height: 50 },
    ];
    const points = computeRoutePoints({
      sourceX: 100, sourceY: 25, sourcePosition: Position.Right,
      targetX: 200, targetY: 225, targetPosition: Position.Left,
      obstacles,
    });
    expect(points[0]).toEqual({ x: 100, y: 25 });
    expect(points[points.length - 1]).toEqual({ x: 200, y: 225 });
  });
});

describe("pointsToSvgPath", () => {
  it("produces a valid SVG path for a 2-segment L", () => {
    const path = pointsToSvgPath([
      { x: 0, y: 0 },
      { x: 100, y: 0 },
      { x: 100, y: 100 },
    ]);
    // Starts with M, contains a Q for the rounded corner.
    expect(path.startsWith("M 0 0")).toBe(true);
    expect(path).toContain("Q ");
    expect(path.trim().split(" L ").length).toBeGreaterThanOrEqual(2);
  });

  it("returns an empty string for zero points", () => {
    expect(pointsToSvgPath([])).toBe("");
  });

  it("uses straight L commands when cornerRadius is 0", () => {
    const path = pointsToSvgPath(
      [
        { x: 0, y: 0 },
        { x: 100, y: 0 },
        { x: 100, y: 100 },
      ],
      0,
    );
    expect(path).toBe("M 0 0 L 100 0 L 100 100");
  });
});
