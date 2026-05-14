// @vitest-environment happy-dom
// StreamNode.topologyHint.test.tsx — Phase 64 Plan 04 (Wave 3, Task 2 RED).
//
// Rendered-chip assertions for the D-15 topology-hint surface in
// StreamNode.tsx. Each `it(...)` notes the driving D-ID from
// `.planning/phases/64-connection-routing/64-CONTEXT.md`.
//
// RED on the Wave-2 base: StreamNode.tsx still resolves handle positions via
// autoflip but does not yet render the topology-hint chip. Task 3 (GREEN)
// wires `selectTopologyHints` from `@/lib/selectors/topologyHints` and adds
// the `<div data-testid="topology-hint-chip">` element, at which point every
// assertion below turns green.
//
// Severity invariant: the chip is NON-BLOCKING (D-15). It renders
// independently of the red-ring `ring-destructive` class. When only the
// topology hint fires (no other errors), the rendered node MUST NOT carry
// `ring-destructive`. This guards against accidentally mixing the hint into
// `hasAnyError`.

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";
import { ReactFlowProvider } from "@xyflow/react";
import type { Edge, Node } from "@xyflow/react";
import StreamNode from "../StreamNode";
import useStore from "../../store/useStore";

// ---------------------------------------------------------------------------
// useUpdateNodeInternals mock (matches StreamNode.autoflip.test.tsx).
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
// Test helpers
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
// D-15 positive — both axes resolve to horizontal on a CAC.
// Layout: pump (-300, 0) --flow--> cac (0, 0) --thermal--> hd (300, 0).
// Flow axis: horizontal (pump on left). Thermal axis: horizontal (hd on
// right; CAC default_axis=vertical flips to horizontal). Collision → chip.
// ---------------------------------------------------------------------------

describe("StreamNode topology-hint chip — D-15 positive", () => {
  function primeCrowdedCAC() {
    primeStore(
      [
        pumpNode("pump1", { x: -300, y: 0 }),
        cacNode("cac1", { x: 0, y: 0 }),
        hdNode("hd1", { x: 300, y: 0 }),
      ],
      [
        flowEdge("e_flow", "pump1", "port_out", "cac1", "port_in"),
        thermalEdge("e_th", "cac1", "thermal_right", "hd1", "thermal_left"),
      ],
    );
  }

  it("D-15: renders the yellow chip when both axes resolve to horizontal on a CAC", () => {
    primeCrowdedCAC();
    renderStreamNode("cac1", "ChannelAndContacts", "cac_1", { n: 4 });
    const chip = screen.getByTestId("topology-hint-chip");
    expect(chip).toBeTruthy();
    expect(chip.textContent || "").toContain("same axis");
  });

  it("D-15 severity (non-blocking): chip presence does NOT toggle ring-destructive on the node root", () => {
    primeCrowdedCAC();
    const { container } = renderStreamNode(
      "cac1",
      "ChannelAndContacts",
      "cac_1",
      { n: 4 },
    );
    // Chip must be present.
    expect(screen.getByTestId("topology-hint-chip")).toBeTruthy();
    // But the red-ring class MUST NOT be on the node root — D-15 is a warning,
    // not an error. The chip and the red ring are independent surfaces.
    const destructive = container.querySelector(
      '[class*="ring-destructive"]',
    );
    expect(destructive).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// D-15 negative — orthogonal axes (flow horizontal, thermal vertical).
// Layout: pump (-300, 0) --flow--> cac (0, 0); hd above cac for vertical
// thermal axis. Orthogonal → no chip.
// ---------------------------------------------------------------------------

describe("StreamNode topology-hint chip — D-15 negative (orthogonal axes)", () => {
  it("D-15: chip does NOT render when flow axis and thermal axis are orthogonal", () => {
    primeStore(
      [
        pumpNode("pump1", { x: -300, y: 0 }),
        cacNode("cac1", { x: 0, y: 0 }),
        hdNode("hd1", { x: 0, y: -300 }),
      ],
      [
        flowEdge("e_flow", "pump1", "port_out", "cac1", "port_in"),
        thermalEdge("e_th", "cac1", "thermal_left", "hd1", "thermal_right"),
      ],
    );
    renderStreamNode("cac1", "ChannelAndContacts", "cac_1", { n: 4 });
    expect(screen.queryByTestId("topology-hint-chip")).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// D-15 negative — components without both layers.
// ---------------------------------------------------------------------------

describe("StreamNode topology-hint chip — D-15 negative (single-layer)", () => {
  it("D-15: isolated Pump (no thermal pair) does NOT render the chip", () => {
    primeStore([pumpNode("p1", { x: 0, y: 0 })], []);
    renderStreamNode("p1", "Pump", "pump1");
    expect(screen.queryByTestId("topology-hint-chip")).toBeNull();
  });
});
