// @vitest-environment happy-dom
// StreamNode.anchor.test.tsx — Phase 63.1 Plan 01 (Wave-0 RED).
//
// Covers the canvas anchor indicator (D-13):
//   - When `anchors[id]` exists and the portField matches a FlowPort handle
//     on this node, render an element with
//       data-testid="anchor-indicator" and aria-label="Pressure anchor".
//   - When no anchor entry exists for this node, the indicator must NOT
//     render (queryByTestId returns null).
//
// UI-SPEC (§"Canvas Anchor Indicator"): a small w-1.5 h-1.5 dot rendered
// adjacent to the handle. The current StreamNode does not render any
// anchor-indicator element — this stub is RED until Plan 09 lands.
// @ts-nocheck — anchor indicator renders in Wave 5 / Plan 09.

import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";
import { ReactFlowProvider } from "@xyflow/react";
import StreamNode from "../StreamNode";
import useStore from "../../store/useStore";

function renderStreamNode(id: string) {
  return render(
    <ReactFlowProvider>
      <StreamNode
        id={id}
        data={{
          componentId: "Pump",
          instanceName: "pump1",
          parameters: {},
        } as unknown as Record<string, unknown>}
        selected={false}
        type="streamNode"
        isConnectable={true}
        positionAbsoluteX={0}
        positionAbsoluteY={0}
        zIndex={0}
        dragging={false}
        draggable={true}
        deletable={true}
        selectable={true}
        parentId={undefined}
        dragHandle={undefined}
        sourcePosition={undefined}
        targetPosition={undefined}
      />
    </ReactFlowProvider>,
  );
}

beforeEach(() => {
  useStore.setState({
    nodes: [],
    edges: [],
    selectedNodeId: null,
    isDirty: false,
    _undoPast: [],
    _undoFuture: [],
    bcMode: {},
    bcSymmetric: {},
    anchors: {},
    errorNodeIds: new Set<string>(),
    // Phase 63.1 D-15: errorTagsByNodeId slice removed.
  });
});

afterEach(() => {
  cleanup();
});

describe("StreamNode anchor indicator (D-13)", () => {
  it("renders an element with data-testid='anchor-indicator' when an anchor exists for this node", () => {
    useStore.setState({
      nodes: [
        {
          id: "n1",
          type: "streamNode",
          position: { x: 0, y: 0 },
          data: {
            componentId: "Pump",
            instanceName: "pump1",
            parameters: {},
            constructorMode: "default",
          },
        },
      ],
      anchors: { n1: { portField: "port_in.P", value: 1e5 } },
    });
    renderStreamNode("n1");
    expect(screen.getByTestId("anchor-indicator")).toBeTruthy();
    expect(screen.getByLabelText("Pressure anchor")).toBeTruthy();
  });

  it("does NOT render the indicator when no anchor entry exists for this node", () => {
    useStore.setState({
      nodes: [
        {
          id: "n1",
          type: "streamNode",
          position: { x: 0, y: 0 },
          data: {
            componentId: "Pump",
            instanceName: "pump1",
            parameters: {},
            constructorMode: "default",
          },
        },
      ],
      anchors: {},
    });
    renderStreamNode("n1");
    expect(screen.queryByTestId("anchor-indicator")).toBeNull();
  });

  // GAP-COSMETIC-ANCHOR (Plan 63.1-13): the indicator is a lucide Anchor SVG,
  // not a filled-circle <div>. testID + aria-label must remain so the existing
  // accessibility hooks survive the visual swap.
  it("renders the anchor indicator as an SVG glyph (lucide Anchor icon)", () => {
    useStore.setState({
      nodes: [
        {
          id: "n1",
          type: "streamNode",
          position: { x: 0, y: 0 },
          data: {
            componentId: "Pump",
            instanceName: "pump1",
            parameters: {},
            constructorMode: "default",
          },
        },
      ],
      anchors: { n1: { portField: "port_in.P", value: 1e5 } },
    });
    renderStreamNode("n1");
    const indicator = screen.getByTestId("anchor-indicator");
    // lucide-react icons render as <svg> elements. tagName is uppercase in HTML
    // doms; lowercase in XHTML/SVG. Compare case-insensitively.
    expect(indicator.tagName.toLowerCase()).toBe("svg");
    // The SVG must NOT carry the legacy `rounded-full bg-foreground` div style.
    expect(indicator.className.toString()).not.toContain("rounded-full");
    expect(indicator.className.toString()).not.toContain("bg-foreground");
  });
});
