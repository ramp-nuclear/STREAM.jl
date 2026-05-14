// @vitest-environment happy-dom
// StreamNode.autoflip.test.tsx — Phase 64 Plan 03 (Wave 2, Task 1 RED).
//
// Rendered-handle assertions for the autoflip wiring in StreamNode.tsx.
// Each `it(...)` block notes its driving D-ID from
// `.planning/phases/64-connection-routing/64-CONTEXT.md`.
//
// These tests are RED on Wave-1 base: StreamNode.tsx still resolves handle
// `position` from `port.side!` from the registry. Task 2 (GREEN) wires
// `resolveFlowPortSide` / `resolveThermalPairSides` from `@/lib/autoflip` into
// the render path, at which point every assertion below turns green.

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, cleanup } from "@testing-library/react";
import { ReactFlowProvider } from "@xyflow/react";
import type { Edge, Node } from "@xyflow/react";
import StreamNode from "../StreamNode";
import useStore from "../../store/useStore";

// ---------------------------------------------------------------------------
// useUpdateNodeInternals mock — captures every call into a shared spy. We use
// the partial-mock pattern from BCEdge.test.tsx (importActual + spread).
// ---------------------------------------------------------------------------

const updateNodeInternalsSpy = vi.fn();

vi.mock("@xyflow/react", async () => {
  const actual =
    await vi.importActual<typeof import("@xyflow/react")>("@xyflow/react");
  return {
    ...actual,
    useUpdateNodeInternals: () => updateNodeInternalsSpy,
  };
});

// ---------------------------------------------------------------------------
// Test helper — render StreamNode wrapped in a ReactFlowProvider (matches
// StreamNode.anchor.test.tsx). The `id` arg lets each test pick a node id that
// matches the entry it primed into `useStore` via `setState`.
// ---------------------------------------------------------------------------

function renderStreamNode(
  id: string,
  componentId: string,
  instanceName: string,
  parameters: Record<string, unknown> = {},
) {
  return render(
    <ReactFlowProvider>
      <StreamNode
        id={id}
        data={{
          componentId,
          instanceName,
          parameters,
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

// Fixture builders — keep test bodies short and let the geometric setup
// dominate the visible test code.
function pumpNode(
  id: string,
  position: { x: number; y: number },
  instanceName = id,
): Node {
  return {
    id,
    type: "streamNode",
    position,
    measured: { width: 140, height: 70 },
    data: {
      componentId: "Pump",
      instanceName,
      parameters: {},
    },
  } as unknown as Node;
}

function cacNode(
  id: string,
  position: { x: number; y: number },
  instanceName = id,
): Node {
  return {
    id,
    type: "streamNode",
    position,
    measured: { width: 140, height: 70 },
    data: {
      componentId: "ChannelAndContacts",
      instanceName,
      parameters: { n: 4 },
    },
  } as unknown as Node;
}

function hdNode(
  id: string,
  position: { x: number; y: number },
  instanceName = id,
): Node {
  return {
    id,
    type: "streamNode",
    position,
    measured: { width: 140, height: 70 },
    data: {
      componentId: "HeatDiffusion",
      instanceName,
      parameters: { nz: 4, nx: 4 },
    },
  } as unknown as Node;
}

function flowEdge(
  id: string,
  source: string,
  sourceHandle: string,
  target: string,
  targetHandle: string,
): Edge {
  return {
    id,
    source,
    sourceHandle,
    target,
    targetHandle,
    type: "hydraulicEdge",
  } as Edge;
}

function thermalEdge(
  id: string,
  source: string,
  sourceHandle: string,
  target: string,
  targetHandle: string,
): Edge {
  return {
    id,
    source,
    sourceHandle,
    target,
    targetHandle,
    type: "default",
  } as Edge;
}

function primeStore(nodes: Node[], edges: Edge[]) {
  useStore.setState({
    nodes,
    edges,
    bcMode: {},
    bcSymmetric: {},
    anchors: {},
    errorNodeIds: new Set<string>(),
  });
}

function getHandle(
  container: HTMLElement,
  handleId: string,
): HTMLElement | undefined {
  return Array.from(
    container.querySelectorAll(".react-flow__handle"),
  ).find(
    (h) => (h as HTMLElement).getAttribute("data-handleid") === handleId,
  ) as HTMLElement | undefined;
}

beforeEach(() => {
  updateNodeInternalsSpy.mockClear();
  useStore.setState({
    nodes: [],
    edges: [],
    bcMode: {},
    bcSymmetric: {},
    anchors: {},
    errorNodeIds: new Set<string>(),
  });
});

afterEach(() => {
  cleanup();
});

// ---------------------------------------------------------------------------
// §3.3 Example 1 — bidirectional X-cross between two pumps placed left/right.
// Both pumps' ports should flip to the side facing the neighbor. With both
// FlowPorts of pump1 on the right side, D-09/D-10 places port_in at top:25%
// and port_out at top:75%.
// ---------------------------------------------------------------------------

describe("StreamNode autoflip — FlowPort §3.3 Example 1 X-cross", () => {
  function primeXCross() {
    primeStore(
      [pumpNode("p1", { x: 0, y: 0 }), pumpNode("p2", { x: 300, y: 0 })],
      [
        flowEdge("e1", "p1", "port_out", "p2", "port_in"),
        flowEdge("e2", "p2", "port_out", "p1", "port_in"),
      ],
    );
  }

  it("D-13/D-16: pump1.port_out flips to spatial right (neighbor to the right)", () => {
    primeXCross();
    const { container } = renderStreamNode("p1", "Pump", "pump1");
    const handle = getHandle(container, "port_out");
    expect(handle).toBeTruthy();
    expect(handle!.className).toContain("react-flow__handle-right");
  });

  it("D-13/D-16: pump1.port_in flips to spatial right (its connection comes from pump2 on the right)", () => {
    primeXCross();
    const { container } = renderStreamNode("p1", "Pump", "pump1");
    const handle = getHandle(container, "port_in");
    expect(handle).toBeTruthy();
    expect(handle!.className).toContain("react-flow__handle-right");
  });

  it("D-09/D-10: same-side collision places port_in at top:25%, port_out at top:75% (reading direction)", () => {
    primeXCross();
    const { container } = renderStreamNode("p1", "Pump", "pump1");
    const portIn = getHandle(container, "port_in")!;
    const portOut = getHandle(container, "port_out")!;
    // Pitfall 8: for left/right side, percentage axis is `top` (D-10).
    expect(portIn.style.top).toBe("25%");
    expect(portOut.style.top).toBe("75%");
  });

  it("D-04 anchor co-location: anchor follows the autoflipped side (right → style.right === -16)", () => {
    primeXCross();
    // Add anchor on pump1.port_in.P so the indicator renders.
    useStore.setState({
      anchors: { p1: { portField: "port_in.P", value: 1e5 } },
    });
    const { container } = renderStreamNode("p1", "Pump", "pump1");
    const indicator = container.querySelector(
      '[data-testid="anchor-indicator"]',
    ) as HTMLElement | null;
    expect(indicator).toBeTruthy();
    // anchorIndicatorStyleFor("right") returns { right: -16, top: -6 }.
    // Inline `right: -16` serializes to `-16px` in CSSOM.
    expect(indicator!.style.right).toBe("-16px");
  });
});

// ---------------------------------------------------------------------------
// §3.3 Examples 3-4 — vertical stack. Pump above a channel-like component:
// pump.port_out should flip to bottom (|dy| > |dx|), channel.port_in flips
// to top.
// ---------------------------------------------------------------------------

describe("StreamNode autoflip — §3.3 Examples 3-4 vertical stack", () => {
  function primeVerticalStack() {
    primeStore(
      [
        pumpNode("p1", { x: 0, y: 0 }, "pump_top"),
        cacNode("c1", { x: 0, y: 300 }, "cac_below"),
      ],
      [flowEdge("e1", "p1", "port_out", "c1", "port_in")],
    );
  }

  it("D-13/D-16: pump.port_out resolves to bottom when channel sits directly below", () => {
    primeVerticalStack();
    const { container } = renderStreamNode("p1", "Pump", "pump_top");
    const handle = getHandle(container, "port_out");
    expect(handle).toBeTruthy();
    expect(handle!.className).toContain("react-flow__handle-bottom");
  });

  it("D-13/D-16: channel.port_in resolves to top when pump sits directly above", () => {
    primeVerticalStack();
    const { container } = renderStreamNode("c1", "ChannelAndContacts", "cac_below", { n: 4 });
    const handle = getHandle(container, "port_in");
    expect(handle).toBeTruthy();
    expect(handle!.className).toContain("react-flow__handle-top");
  });
});

// ---------------------------------------------------------------------------
// D-11 — zero-connection default. An isolated component renders handles at
// the registry-default sides.
// ---------------------------------------------------------------------------

describe("StreamNode autoflip — D-11 zero-connection default", () => {
  it("D-11: isolated Pump.port_in renders on registry-default left", () => {
    primeStore([pumpNode("p1", { x: 0, y: 0 })], []);
    const { container } = renderStreamNode("p1", "Pump", "pump1");
    const handle = getHandle(container, "port_in");
    expect(handle).toBeTruthy();
    expect(handle!.className).toContain("react-flow__handle-left");
  });

  it("D-11: isolated Pump.port_out renders on registry-default right", () => {
    primeStore([pumpNode("p1", { x: 0, y: 0 })], []);
    const { container } = renderStreamNode("p1", "Pump", "pump1");
    const handle = getHandle(container, "port_out");
    expect(handle).toBeTruthy();
    expect(handle!.className).toContain("react-flow__handle-right");
  });
});

// ---------------------------------------------------------------------------
// Pitfall 6 — CAC thermal latent bug. The CAC registry entry omits `side` on
// thermal ports (only `default_axis: "vertical"` + `pair_with`). Pre-Plan-03
// `port.side!` was `undefined`, and `sideToPosition[undefined]` was
// `undefined`, so the handle rendered at ReactFlow's default position with no
// `react-flow__handle-*` class set. Plan 03 resolves a defined side from the
// suffix + axis (D-18) — thermal_left → top, thermal_right → bottom for
// `default_axis = vertical`.
// ---------------------------------------------------------------------------

describe("StreamNode autoflip — Pitfall 6 CAC thermal latent bug", () => {
  it("D-18: isolated CAC.thermal_left renders on top (suffix=left, axis=vertical)", () => {
    primeStore([cacNode("c1", { x: 0, y: 0 })], []);
    const { container } = renderStreamNode("c1", "ChannelAndContacts", "cac_1", { n: 4 });
    const handle = getHandle(container, "thermal_left");
    expect(handle).toBeTruthy();
    expect(handle!.className).toContain("react-flow__handle-top");
  });

  it("D-18: isolated CAC.thermal_right renders on bottom (suffix=right, axis=vertical)", () => {
    primeStore([cacNode("c1", { x: 0, y: 0 })], []);
    const { container } = renderStreamNode("c1", "ChannelAndContacts", "cac_1", { n: 4 });
    const handle = getHandle(container, "thermal_right");
    expect(handle).toBeTruthy();
    expect(handle!.className).toContain("react-flow__handle-bottom");
  });

  it("Pitfall 6 regression guard: every rendered handle has one of the four position classes", () => {
    primeStore([cacNode("c1", { x: 0, y: 0 })], []);
    const { container } = renderStreamNode("c1", "ChannelAndContacts", "cac_1", { n: 4 });
    const handles = Array.from(
      container.querySelectorAll(".react-flow__handle"),
    ) as HTMLElement[];
    expect(handles.length).toBeGreaterThan(0);
    for (const h of handles) {
      expect(h.className).toMatch(
        /react-flow__handle-(left|right|top|bottom)/,
      );
    }
  });
});

// ---------------------------------------------------------------------------
// D-18 — thermal axis flip on neighbor. CAC default_axis="vertical" means
// (top, bottom). With a horizontal neighbor, the axis flips to horizontal so
// suffix `_left` maps to spatial left and `_right` to spatial right.
// ---------------------------------------------------------------------------

describe("StreamNode autoflip — D-18 thermal axis flip on neighbor", () => {
  function primeHorizontalCacHd() {
    primeStore(
      [
        cacNode("c1", { x: 0, y: 0 }),
        hdNode("h1", { x: 300, y: 0 }),
      ],
      [
        thermalEdge("te1", "c1", "thermal_right", "h1", "thermal_left"),
      ],
    );
  }

  it("D-18: CAC.thermal_left flips to spatial left when neighbor is horizontal (|dx| > |dy|)", () => {
    primeHorizontalCacHd();
    const { container } = renderStreamNode("c1", "ChannelAndContacts", "cac_1", { n: 4 });
    const handle = getHandle(container, "thermal_left");
    expect(handle).toBeTruthy();
    expect(handle!.className).toContain("react-flow__handle-left");
  });

  it("D-18: CAC.thermal_right flips to spatial right (suffix-locked pair opposite)", () => {
    primeHorizontalCacHd();
    const { container } = renderStreamNode("c1", "ChannelAndContacts", "cac_1", { n: 4 });
    const handle = getHandle(container, "thermal_right");
    expect(handle).toBeTruthy();
    expect(handle!.className).toContain("react-flow__handle-right");
  });
});

// ---------------------------------------------------------------------------
// useUpdateNodeInternals — fires on every per-port side flip. Per the plan,
// each FlowPortHandle / ThermalPortHandle sub-component registers its own
// `useEffect` keyed on its resolved side; the spy must receive the node id
// at least once when the side changes between renders.
// ---------------------------------------------------------------------------

describe("StreamNode autoflip — useUpdateNodeInternals fires on side change", () => {
  it("Pattern 2 / Pitfall 1: updateNodeInternals(nodeId) is called when the resolved side flips", () => {
    // Render once with no edges (registry defaults).
    primeStore([pumpNode("p1", { x: 0, y: 0 })], []);
    const { rerender, container } = render(
      <ReactFlowProvider>
        <StreamNode
          id="p1"
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
    // Confirm initial render produced handles.
    expect(container.querySelectorAll(".react-flow__handle").length).toBe(2);

    updateNodeInternalsSpy.mockClear();

    // Now mutate the store so port_in flips from its default (left) to right
    // — the connected neighbor is now on the right side.
    primeStore(
      [pumpNode("p1", { x: 0, y: 0 }), pumpNode("p2", { x: 300, y: 0 })],
      [flowEdge("e1", "p2", "port_out", "p1", "port_in")],
    );

    rerender(
      <ReactFlowProvider>
        <StreamNode
          id="p1"
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

    // The spy must have been called with the node id at least once after the
    // flip — useUpdateNodeInternals is the mechanism that tells ReactFlow to
    // re-measure handle DOM (Pattern 2, Pitfall 1).
    expect(updateNodeInternalsSpy).toHaveBeenCalled();
    expect(updateNodeInternalsSpy.mock.calls.some((c) => c[0] === "p1")).toBe(
      true,
    );
  });
});
