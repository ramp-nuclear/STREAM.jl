// @vitest-environment happy-dom
import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";
import { Position } from "@xyflow/react";
import BCEdge from "../BCEdge";
import useStore from "../../store/useStore";
import { bcModeKey, type BCEdgeData } from "../../lib/bcMode";

// EdgeLabelRenderer requires a ReactFlow renderer host in DOM. Stub it to a
// passthrough div so we can render the edge in isolation.
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
  source?: string;
}

function renderBCEdge({ data, source = "wt_1" }: EdgeRenderProps = {}) {
  const props = {
    id: "bc-edge-1",
    source,
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
  return render(
    <svg>
      <BCEdge {...props} />
    </svg>,
  );
}

beforeEach(() => {
  useStore.setState({ edges: [], bcMode: {}, bcSymmetric: {} });
});

describe("BCEdge — dashed-style baseline (D-12)", () => {
  it("renders a path with dashed muted-foreground style", () => {
    const { container } = renderBCEdge({
      data: { componentId: "ch_1", externalInputName: "T_wall_left", targetSide: "both" },
    });
    const path = container.querySelector("path");
    expect(path).toBeTruthy();
    const style = (path as SVGPathElement).style;
    expect(style.strokeDasharray).toBe("6 3");
    expect(style.strokeWidth).toBe("1.5");
    expect(style.stroke).toContain("--muted-foreground");
  });

  it("does NOT render any markerEnd arrowhead", () => {
    const { container } = renderBCEdge({
      data: { componentId: "ch_1", externalInputName: "T_wall_left", targetSide: "both" },
    });
    const path = container.querySelector("path");
    expect(path?.getAttribute("marker-end")).toBeFalsy();
  });
});

describe("BCEdge — side tag derived from bcMode (Plan 63.1-12 amend)", () => {
  it("renders 'L+R' when both sibling bcMode entries point to this edge's source", () => {
    useStore.setState({
      bcMode: {
        [bcModeKey("ch_1", "T_wall_left")]: { mode: "source", sourceNodeId: "wt_1" },
        [bcModeKey("ch_1", "T_wall_right")]: { mode: "source", sourceNodeId: "wt_1" },
      },
    });
    renderBCEdge({
      data: { componentId: "ch_1", externalInputName: "T_wall_left", targetSide: "both" },
      source: "wt_1",
    });
    expect(screen.getByText("L+R")).toBeTruthy();
  });

  it("renders 'L' when only the left sibling bcMode points to this edge's source", () => {
    useStore.setState({
      bcMode: {
        [bcModeKey("ch_1", "T_wall_left")]: { mode: "source", sourceNodeId: "wt_1" },
        // right is unset
      },
    });
    renderBCEdge({
      data: { componentId: "ch_1", externalInputName: "T_wall_left", targetSide: "both" },
      source: "wt_1",
    });
    expect(screen.getByText("L")).toBeTruthy();
  });

  it("renders 'R' when only the right sibling bcMode points to this edge's source", () => {
    useStore.setState({
      bcMode: {
        [bcModeKey("ch_1", "T_wall_right")]: { mode: "source", sourceNodeId: "wt_1" },
      },
    });
    renderBCEdge({
      data: { componentId: "ch_1", externalInputName: "T_wall_left", targetSide: "both" },
      source: "wt_1",
    });
    expect(screen.getByText("R")).toBeTruthy();
  });

  it("renders NO side tag when bcMode is empty (orphan edge)", () => {
    renderBCEdge({
      data: { componentId: "ch_1", externalInputName: "T_wall_left", targetSide: "both" },
      source: "wt_1",
    });
    expect(screen.queryByText("L+R")).toBeNull();
    expect(screen.queryByText("L")).toBeNull();
    expect(screen.queryByText("R")).toBeNull();
  });

  it("renders NO interactive control — the side tag is a static <span>, not a <button>", () => {
    useStore.setState({
      bcMode: {
        [bcModeKey("ch_1", "T_wall_left")]: { mode: "source", sourceNodeId: "wt_1" },
        [bcModeKey("ch_1", "T_wall_right")]: { mode: "source", sourceNodeId: "wt_1" },
      },
    });
    const { container } = renderBCEdge({
      data: { componentId: "ch_1", externalInputName: "T_wall_left", targetSide: "both" },
      source: "wt_1",
    });
    // L/R/L+R should NOT live inside a <button> anymore.
    expect(container.querySelector("button")).toBeNull();
  });
});
