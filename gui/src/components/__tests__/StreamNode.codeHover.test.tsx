// @vitest-environment happy-dom
// StreamNode.codeHover.test.tsx — Phase 66 Plan 05 (Wave-4 RED).
//
// Covers the canvas hover/pin ring (D-05, D-09, D-11):
//   - When `hoveredSourceIds.has(id)`, the StreamNode root element carries the
//     `stream-node--code-hover` class.
//   - When `pinnedSourceIds.has(id)`, the root element carries the
//     `stream-node--code-pinned` class.
//   - Both classes can coexist (sub-block-hovered + previously-pinned node).
//
// Wiring is via per-node primitive-boolean selectors (Research Pattern 9),
// matching the established `hasAnchor` / `hasBCError` shape so re-render
// fanout stays bounded to the affected nodes.

import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { act, render, cleanup } from "@testing-library/react";
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

function rootEl(container: HTMLElement): HTMLElement {
  // StreamNode renders a single root <div>; container.firstChild is it.
  const el = container.firstChild as HTMLElement | null;
  if (!el) throw new Error("StreamNode did not render a root element");
  return el;
}

beforeEach(() => {
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
    edges: [],
    selectedNodeId: null,
    isDirty: false,
    _undoPast: [],
    _undoFuture: [],
    bcMode: {},
    bcSymmetric: {},
    anchors: {},
    errorNodeIds: new Set<string>(),
    hoveredSourceIds: new Set<string>(),
    pinnedSourceIds: new Set<string>(),
    pendingShowCodeFor: null,
  });
});

afterEach(() => {
  cleanup();
});

describe("StreamNode code-hover / pinned ring (Phase 66)", () => {
  it("does NOT carry the hover / pinned classes initially", () => {
    const { container } = renderStreamNode("n1");
    const el = rootEl(container);
    expect(el.className).not.toContain("stream-node--code-hover");
    expect(el.className).not.toContain("stream-node--code-pinned");
  });

  it("applies stream-node--code-hover when hoveredSourceIds includes the node id", () => {
    const { container } = renderStreamNode("n1");
    act(() => {
      useStore.setState({ hoveredSourceIds: new Set(["n1"]) });
    });
    expect(rootEl(container).className).toContain("stream-node--code-hover");
  });

  it("removes stream-node--code-hover when the id leaves hoveredSourceIds", () => {
    const { container } = renderStreamNode("n1");
    act(() => {
      useStore.setState({ hoveredSourceIds: new Set(["n1"]) });
    });
    expect(rootEl(container).className).toContain("stream-node--code-hover");
    act(() => {
      useStore.setState({ hoveredSourceIds: new Set<string>() });
    });
    expect(rootEl(container).className).not.toContain("stream-node--code-hover");
  });

  it("applies stream-node--code-pinned when pinnedSourceIds includes the node id", () => {
    const { container } = renderStreamNode("n1");
    act(() => {
      useStore.setState({ pinnedSourceIds: new Set(["n1"]) });
    });
    expect(rootEl(container).className).toContain("stream-node--code-pinned");
  });

  it("applies BOTH classes when the id is in both sets simultaneously", () => {
    const { container } = renderStreamNode("n1");
    act(() => {
      useStore.setState({
        hoveredSourceIds: new Set(["n1"]),
        pinnedSourceIds: new Set(["n1"]),
      });
    });
    const cls = rootEl(container).className;
    expect(cls).toContain("stream-node--code-hover");
    expect(cls).toContain("stream-node--code-pinned");
  });
});
