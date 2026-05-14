// @vitest-environment happy-dom
import { describe, it, expect, beforeEach } from "vitest";
import { render } from "@testing-library/react";
import { Position, ReactFlowProvider, getSmoothStepPath, type Edge } from "@xyflow/react";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import HydraulicEdge from "../HydraulicEdge";
import useStore from "../../store/useStore";

/**
 * Phase 64 Plan 02 — anti-parallel ±8px perpendicular bow tests (D-06/D-07/D-08/D-17).
 *
 * Coordinate setup: source at (0,0) on Right face, target at (200,0) on Left face.
 * SmoothStep midline is at y=0 in the no-bow baseline. The bow strategy is
 * "pre-offset endpoint coords perpendicular to the dominant axis BEFORE
 * calling getSmoothStepPath" (RESEARCH.md option (a) — Pattern 3).
 *
 * Render-storm guard (Pitfall — RESEARCH.md Pattern 3): the edge component
 * MUST NOT subscribe to the store via the `useStore(...)` hook — edges re-render
 * every drag frame and a subscription would trigger a render storm. The only
 * permitted read is `useStore.getState().edges` synchronously inside render.
 */

const HORIZ_PROPS = {
  sourceX: 0,
  sourceY: 0,
  targetX: 200,
  targetY: 0,
  sourcePosition: Position.Right,
  targetPosition: Position.Left,
  style: undefined,
  markerEnd: undefined,
  selected: false,
  animated: false,
} as const;

function makeHydraulicEdge(
  id: string,
  source: string,
  target: string,
  overrides: Partial<Edge> = {},
): Edge {
  return {
    id,
    source,
    target,
    type: "hydraulicEdge",
    ...overrides,
  };
}

function renderEdge(
  edgeId: string,
  source: string,
  target: string,
) {
  return render(
    <ReactFlowProvider>
      <svg>
        <HydraulicEdge
          id={edgeId}
          source={source}
          target={target}
          {...HORIZ_PROPS}
        />
      </svg>
    </ReactFlowProvider>,
  );
}

/**
 * Parse the SVG `d` attribute emitted by `getSmoothStepPath` for the standard
 * horizontal (Right→Left) layout. The path has the form
 * `M{x0} {y0}L{x1} {y1}L{x2} {y2}…` and every y coordinate is the midline y
 * (because we pre-offset the endpoint coords). Returns the FIRST y-coord we
 * encounter — that IS the midline y for a horizontal smoothstep.
 */
function extractMidlineY(d: string): number {
  const match = d.match(/^M\s*-?\d+(?:\.\d+)?\s+(-?\d+(?:\.\d+)?)/);
  expect(match, `path "${d}" did not match expected smoothstep format`).toBeTruthy();
  return Number(match![1]);
}

beforeEach(() => {
  useStore.setState({ edges: [] });
});

describe("HydraulicEdge anti-parallel bow", () => {
  it("renders a baseline (no-bow) path when there is no sibling edge", () => {
    useStore.setState({
      edges: [makeHydraulicEdge("e1", "A", "B")],
    });
    const { container } = renderEdge("e1", "A", "B");
    const path = container.querySelector("path");
    expect(path).toBeTruthy();
    const d = path!.getAttribute("d")!;

    const [expected] = getSmoothStepPath({
      sourceX: 0,
      sourceY: 0,
      targetX: 200,
      targetY: 0,
      sourcePosition: Position.Right,
      targetPosition: Position.Left,
    });
    expect(d).toBe(expected);
    expect(extractMidlineY(d)).toBe(0);
  });

  it("D-08 — smaller-id sibling of a bidirectional pair bows +8 px (midline y=+8)", () => {
    // Two hydraulic edges between (A, B) in opposite directions.
    // "e1" (smaller id) is rendered → should bow +8.
    useStore.setState({
      edges: [
        makeHydraulicEdge("e1", "A", "B"),
        makeHydraulicEdge("e2", "B", "A"),
      ],
    });
    const { container } = renderEdge("e1", "A", "B");
    const d = container.querySelector("path")!.getAttribute("d")!;
    expect(extractMidlineY(d)).toBe(8);
  });

  it("D-08 — larger-id sibling of a bidirectional pair bows −8 px (midline y=−8)", () => {
    useStore.setState({
      edges: [
        makeHydraulicEdge("e1", "A", "B"),
        makeHydraulicEdge("e2", "B", "A"),
      ],
    });
    const { container } = renderEdge("e2", "B", "A");
    const d = container.querySelector("path")!.getAttribute("d")!;
    // Direction stability: smaller-id bows +8, larger-id bows −8.
    expect(extractMidlineY(d)).toBe(-8);
  });

  it("D-08 — siblings bow in OPPOSITE directions", () => {
    useStore.setState({
      edges: [
        makeHydraulicEdge("e1", "A", "B"),
        makeHydraulicEdge("e2", "B", "A"),
      ],
    });
    const e1 = renderEdge("e1", "A", "B");
    const yE1 = extractMidlineY(e1.container.querySelector("path")!.getAttribute("d")!);
    e1.unmount();
    const e2 = renderEdge("e2", "B", "A");
    const yE2 = extractMidlineY(e2.container.querySelector("path")!.getAttribute("d")!);
    expect(yE1).toBe(-yE2);
    expect(Math.abs(yE1)).toBe(8);
  });

  it("D-17 — a B→A bcEdge does NOT count as a sibling (no bow on the hydraulic edge)", () => {
    useStore.setState({
      edges: [
        makeHydraulicEdge("e1", "A", "B"),
        { id: "e2", source: "B", target: "A", type: "bcEdge" } as Edge,
      ],
    });
    const { container } = renderEdge("e1", "A", "B");
    const d = container.querySelector("path")!.getAttribute("d")!;
    expect(extractMidlineY(d)).toBe(0);
  });

  it("D-17 — a B→A thermal-typed edge does NOT count as a sibling (no bow on the hydraulic edge)", () => {
    useStore.setState({
      edges: [
        makeHydraulicEdge("e1", "A", "B"),
        // Thermal edges have type set elsewhere (currently undefined / default,
        // but the contract is "type !== 'hydraulicEdge'"). Use an explicit
        // non-hydraulicEdge type to assert the filter is type-based.
        { id: "e2", source: "B", target: "A", type: "thermalEdge" } as Edge,
      ],
    });
    const { container } = renderEdge("e1", "A", "B");
    const d = container.querySelector("path")!.getAttribute("d")!;
    expect(extractMidlineY(d)).toBe(0);
  });

  it("render-storm guard — HydraulicEdge.tsx source contains zero `useStore(` hook subscriptions", () => {
    // RESEARCH.md Pattern 3 / Pitfall 3: edges re-render on every drag tick;
    // subscribing to the edges array via `useStore(...)` would cause a render
    // storm. The only permitted read is `useStore.getState().edges`.
    const sourcePath = resolve(__dirname, "../HydraulicEdge.tsx");
    const source = readFileSync(sourcePath, "utf8");
    // The literal `useStore(` (with paren) is the hook subscription. The
    // synchronous `useStore.getState()` form has a `.` between `useStore` and
    // `getState`, so the regex below will not match it.
    expect(source).not.toMatch(/\buseStore\(/);
  });
});
