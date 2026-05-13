// @vitest-environment happy-dom
import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { Position } from "@xyflow/react";
import BCEdge from "../BCEdge";
import useStore from "../../store/useStore";
import type { BCEdgeData } from "../../lib/bcMode";

// EdgeLabelRenderer requires a ReactFlow renderer host in DOM. Stub it to a
// passthrough div so we can render the edge in isolation (test focuses on
// the edge's own JSX + click behavior, not on ReactFlow's portal mechanism).
vi.mock("@xyflow/react", async () => {
  const actual =
    await vi.importActual<typeof import("@xyflow/react")>("@xyflow/react");
  return {
    ...actual,
    EdgeLabelRenderer: ({ children }: { children: React.ReactNode }) => (
      <div data-testid="edge-label-renderer-stub">{children}</div>
    ),
  };
});

interface EdgeRenderProps {
  data?: BCEdgeData;
}

function renderBCEdge({ data }: EdgeRenderProps = {}) {
  const props = {
    id: "bc-edge-1",
    source: "wt_1",
    target: "ch_1",
    sourceX: 0,
    sourceY: 0,
    targetX: 100,
    targetY: 0,
    sourcePosition: Position.Right,
    targetPosition: Position.Left,
    data,
    selected: false,
    animated: false,
  } as unknown as React.ComponentProps<typeof BCEdge>;

  // BCEdge needs to be rendered inside an <svg> for the SVG <path> child.
  return render(
    <svg>
      <BCEdge {...props} />
    </svg>,
  );
}

describe("BCEdge", () => {
  beforeEach(() => {
    // Reset any prior cycle invocations
    useStore.setState({ edges: [] });
  });

  it("renders a path with dashed muted-foreground style (D-12)", () => {
    const { container } = renderBCEdge({
      data: {
        componentId: "ch_1",
        externalInputName: "T_wall_left",
        targetSide: "both",
      },
    });
    const path = container.querySelector("path");
    expect(path).toBeTruthy();
    const style = (path as SVGPathElement).style;
    expect(style.strokeDasharray).toBe("6 3");
    // strokeWidth is a string in CSSOM — "1.5"
    expect(style.strokeWidth).toBe("1.5");
    expect(style.stroke).toContain("--muted-foreground");
  });

  it("renders the chip label 'L+R' by default when targetSide is 'both' (D-11)", () => {
    renderBCEdge({
      data: {
        componentId: "ch_1",
        externalInputName: "T_wall_left",
        targetSide: "both",
      },
    });
    expect(screen.getByText("L+R")).toBeTruthy();
  });

  it("renders the chip label 'L' when targetSide is 'left' (D-11)", () => {
    renderBCEdge({
      data: {
        componentId: "ch_1",
        externalInputName: "T_wall_left",
        targetSide: "left",
      },
    });
    expect(screen.getByText("L")).toBeTruthy();
  });

  it("renders the chip label 'R' when targetSide is 'right' (D-11)", () => {
    renderBCEdge({
      data: {
        componentId: "ch_1",
        externalInputName: "T_wall_left",
        targetSide: "right",
      },
    });
    expect(screen.getByText("R")).toBeTruthy();
  });

  it("clicking the chip calls cycleBCEdgeTargetSide with the edge id (D-11)", () => {
    const spy = vi.fn();
    // Replace the store action with a spy.
    useStore.setState({
      cycleBCEdgeTargetSide: spy as unknown as typeof useStore.getState extends () => infer S
        ? S extends { cycleBCEdgeTargetSide: infer F }
          ? F
          : never
        : never,
    });
    renderBCEdge({
      data: {
        componentId: "ch_1",
        externalInputName: "T_wall_left",
        targetSide: "both",
      },
    });
    fireEvent.click(screen.getByText("L+R"));
    expect(spy).toHaveBeenCalledTimes(1);
    expect(spy).toHaveBeenCalledWith("bc-edge-1");
  });

  it("defaults the chip label to 'L+R' when data is undefined (defensive)", () => {
    renderBCEdge({});
    expect(screen.getByText("L+R")).toBeTruthy();
  });

  it("does NOT render any markerEnd arrowhead (D-12 — BC edges have no arrow)", () => {
    const { container } = renderBCEdge({
      data: {
        componentId: "ch_1",
        externalInputName: "T_wall_left",
        targetSide: "both",
      },
    });
    const path = container.querySelector("path");
    expect(path).toBeTruthy();
    // No marker-end attribute (BaseEdge omits it when prop is undefined).
    expect(path?.getAttribute("marker-end")).toBeFalsy();
  });
});
