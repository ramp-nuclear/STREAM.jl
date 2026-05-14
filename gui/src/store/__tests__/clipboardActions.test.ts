/**
 * Phase 65 Plan 04 — Clipboard actions tests (D-15, D-16, D-19).
 *
 * Tests the four store actions: copySelection, cutSelection,
 * pasteFromClipboard, duplicateSelection.
 */

import { describe, it, expect, beforeEach, vi } from "vitest";
import type { Node, Edge } from "@xyflow/react";
import useStore, { _resetPasteOffsetIndexForTesting } from "../useStore";
import type { StreamNodeData } from "../useStore";
import {
  CLIPBOARD_FORMAT_TAG,
  CLIPBOARD_VERSION,
  type ClipboardPayload,
} from "@/lib/clipboard";

// ---------------------------------------------------------------------------
// navigator.clipboard mock
// ---------------------------------------------------------------------------

let clipboardText = "";
const writeTextMock = vi.fn(async (text: string) => {
  clipboardText = text;
});
const readTextMock = vi.fn(async () => clipboardText);

Object.defineProperty(globalThis, "navigator", {
  value: {
    clipboard: {
      writeText: writeTextMock,
      readText: readTextMock,
    },
  },
  configurable: true,
  writable: true,
});

// ---------------------------------------------------------------------------
// Helper: build a test node
// ---------------------------------------------------------------------------

function makeNode(
  id: string,
  instanceName: string,
  componentId = "Pump",
  x = 100,
  y = 200,
  selected = false,
): Node {
  return {
    id,
    type: "streamNode",
    position: { x, y },
    selected,
    data: {
      componentId,
      instanceName,
      parameters: {},
      constructorMode: "default",
    } satisfies StreamNodeData as unknown as Record<string, unknown>,
  };
}

function makeEdge(id: string, source: string, target: string): Edge {
  return {
    id,
    source,
    target,
    sourceHandle: "port_out",
    targetHandle: "port_in",
  };
}

// ---------------------------------------------------------------------------
// Reset store before each test
// ---------------------------------------------------------------------------

beforeEach(() => {
  useStore.setState({
    nodes: [],
    edges: [],
    selectedNodeId: null,
    anchors: {},
    isDirty: false,
    _undoPast: [],
    _undoFuture: [],
  });
  // Reset the module-level paste-offset counter between tests so offset
  // assertions don't leak across test cases.
  _resetPasteOffsetIndexForTesting();
  clipboardText = "";
  writeTextMock.mockClear();
  readTextMock.mockClear();
});

// ---------------------------------------------------------------------------
// copySelection
// ---------------------------------------------------------------------------

describe("copySelection", () => {
  it("writes a ClipboardPayload to navigator.clipboard when a node is selected", async () => {
    const node = makeNode("n1", "pump_1", "Pump", 100, 200, true);
    useStore.setState({ nodes: [node] });

    await useStore.getState().copySelection();

    expect(writeTextMock).toHaveBeenCalledTimes(1);
    const payload: ClipboardPayload = JSON.parse(writeTextMock.mock.calls[0][0] as string);
    expect(payload.__format).toBe(CLIPBOARD_FORMAT_TAG);
    expect(payload.version).toBe(CLIPBOARD_VERSION);
    expect(payload.nodes).toHaveLength(1);
    expect(payload.nodes[0].id).toBe("n1");
  });

  it("is a no-op when nothing is selected", async () => {
    const node = makeNode("n1", "pump_1", "Pump", 100, 200, false);
    useStore.setState({ nodes: [node] });

    await useStore.getState().copySelection();

    expect(writeTextMock).not.toHaveBeenCalled();
  });

  it("includes internal edges (both endpoints selected) in payload", async () => {
    const n1 = makeNode("n1", "pump_1", "Pump", 100, 200, true);
    const n2 = makeNode("n2", "channel_1", "Channel", 200, 200, true);
    const edge = makeEdge("e1", "n1", "n2");
    useStore.setState({ nodes: [n1, n2], edges: [edge] });

    await useStore.getState().copySelection();

    const payload: ClipboardPayload = JSON.parse(writeTextMock.mock.calls[0][0] as string);
    expect(payload.edges).toHaveLength(1);
    expect(payload.edges[0].id).toBe("e1");
  });

  it("excludes external edges (one endpoint not selected) from payload", async () => {
    const n1 = makeNode("n1", "pump_1", "Pump", 100, 200, true);
    const n2 = makeNode("n2", "channel_1", "Channel", 200, 200, false); // not selected
    const edge = makeEdge("e1", "n1", "n2");
    useStore.setState({ nodes: [n1, n2], edges: [edge] });

    await useStore.getState().copySelection();

    const payload: ClipboardPayload = JSON.parse(writeTextMock.mock.calls[0][0] as string);
    expect(payload.edges).toHaveLength(0);
  });

  it("resets pasteOffsetIndex to 0 on copy so next paste lands at +20 from copied pos", async () => {
    // Advance the index by doing two pastes, then verify that a fresh copy+paste
    // resets the sequence: the paste after re-copy lands at +20 from the newly
    // copied position (not at +60 from some accumulated state).
    const node = makeNode("n1", "pump_1", "Pump", 100, 200, true);
    useStore.setState({ nodes: [node] });

    await useStore.getState().copySelection(); // clipboard = n1 @ (100,200); index reset to 0
    await useStore.getState().pasteFromClipboard(); // index=1 → pastes @ (120,220); pasted node now selected
    await useStore.getState().pasteFromClipboard(); // index=2 → pastes @ (140,240); pasted node now selected

    // Copy the currently-selected node (at 140,240) → index resets to 0.
    await useStore.getState().copySelection();
    // Paste once → index=1 → should land at (140+20, 240+20) = (160,260), NOT (140+60=200).
    await useStore.getState().pasteFromClipboard();

    const allNodes = useStore.getState().nodes;
    const lastPasted = allNodes[allNodes.length - 1];
    // Key assertion: offset is exactly +20 (index=1 after reset), not +60 (index=3 without reset).
    expect(lastPasted.position.x).toBe(140 + 20); // 160, not 200
  });
});

// ---------------------------------------------------------------------------
// pasteFromClipboard
// ---------------------------------------------------------------------------

describe("pasteFromClipboard", () => {
  it("mints new instance name when colliding (pump_1 exists → pump_2)", async () => {
    const existing = makeNode("n1", "pump_1", "Pump", 100, 200, false);
    useStore.setState({ nodes: [existing] });

    const payload: ClipboardPayload = {
      __format: CLIPBOARD_FORMAT_TAG,
      version: CLIPBOARD_VERSION,
      nodes: [makeNode("old-id", "pump_1", "Pump", 100, 200, false)],
      edges: [],
    };
    clipboardText = JSON.stringify(payload);

    await useStore.getState().pasteFromClipboard();

    const { nodes } = useStore.getState();
    expect(nodes).toHaveLength(2);
    expect(nodes[1].data.instanceName).toBe("pump_2");
  });

  it("mints lowest-free name: pump_1 + pump_3 exist → pump_2", async () => {
    const n1 = makeNode("n1", "pump_1", "Pump", 100, 200, false);
    const n3 = makeNode("n3", "pump_3", "Pump", 300, 200, false);
    useStore.setState({ nodes: [n1, n3] });

    const payload: ClipboardPayload = {
      __format: CLIPBOARD_FORMAT_TAG,
      version: CLIPBOARD_VERSION,
      nodes: [makeNode("old-id", "pump_1", "Pump", 100, 200, false)],
      edges: [],
    };
    clipboardText = JSON.stringify(payload);

    await useStore.getState().pasteFromClipboard();

    const { nodes } = useStore.getState();
    const pastedName = nodes[nodes.length - 1].data.instanceName as string;
    expect(pastedName).toBe("pump_2");
  });

  it("increments pasteOffsetIndex on successive calls (B4 lock)", async () => {
    const node = makeNode("orig", "pump_1", "Pump", 100, 200, false);
    useStore.setState({ nodes: [node] });

    const payload: ClipboardPayload = {
      __format: CLIPBOARD_FORMAT_TAG,
      version: CLIPBOARD_VERSION,
      nodes: [makeNode("old-id", "pump_2", "Pump", 100, 200, false)],
      edges: [],
    };
    clipboardText = JSON.stringify(payload);

    // paste 1 → offset = 1*20 = 20
    await useStore.getState().pasteFromClipboard();
    // paste 2 → offset = 2*20 = 40
    await useStore.getState().pasteFromClipboard();

    const { nodes } = useStore.getState();
    // node[1] is first paste: 100 + 20 = 120
    expect(nodes[1].position.x).toBe(100 + 20);
    // node[2] is second paste: 100 + 40 = 140
    expect(nodes[2].position.x).toBe(100 + 40);
  });

  it("preserves resource UUIDs verbatim", async () => {
    const payload: ClipboardPayload = {
      __format: CLIPBOARD_FORMAT_TAG,
      version: CLIPBOARD_VERSION,
      nodes: [
        {
          id: "old-id",
          type: "streamNode",
          position: { x: 50, y: 50 },
          data: {
            componentId: "Channel",
            instanceName: "channel_1",
            parameters: { geometry: "uuid-A" },
            constructorMode: "default",
          } satisfies StreamNodeData as unknown as Record<string, unknown>,
        },
      ],
      edges: [],
    };
    clipboardText = JSON.stringify(payload);

    await useStore.getState().pasteFromClipboard();

    const { nodes } = useStore.getState();
    expect(nodes).toHaveLength(1);
    const pastedParams = nodes[0].data.parameters as Record<string, unknown>;
    expect(pastedParams.geometry).toBe("uuid-A");
  });

  it("is a silent no-op for malformed clipboard text", async () => {
    clipboardText = "not json";
    useStore.setState({ nodes: [], _undoPast: [] });

    await useStore.getState().pasteFromClipboard();

    expect(useStore.getState().nodes).toHaveLength(0);
    expect(useStore.getState()._undoPast).toHaveLength(0);
  });

  it("drops edges whose source/target is not in payload.nodes (defensive)", async () => {
    const payload: ClipboardPayload = {
      __format: CLIPBOARD_FORMAT_TAG,
      version: CLIPBOARD_VERSION,
      nodes: [makeNode("n1", "pump_2", "Pump", 100, 200, false)],
      edges: [makeEdge("e1", "n1", "EXTERNAL-ID")], // target not in payload
    };
    clipboardText = JSON.stringify(payload);

    await useStore.getState().pasteFromClipboard();

    const { edges } = useStore.getState();
    expect(edges).toHaveLength(0);
  });

  it("rewires internal edges to new node IDs after paste", async () => {
    const payload: ClipboardPayload = {
      __format: CLIPBOARD_FORMAT_TAG,
      version: CLIPBOARD_VERSION,
      nodes: [
        makeNode("n1", "pump_2", "Pump", 100, 200, false),
        makeNode("n2", "channel_1", "Channel", 200, 200, false),
      ],
      edges: [makeEdge("e1", "n1", "n2")],
    };
    clipboardText = JSON.stringify(payload);

    await useStore.getState().pasteFromClipboard();

    const { nodes, edges } = useStore.getState();
    expect(nodes).toHaveLength(2);
    expect(edges).toHaveLength(1);
    // Edge should reference new node IDs, not the original "n1"/"n2"
    expect(edges[0].source).not.toBe("n1");
    expect(edges[0].target).not.toBe("n2");
    expect(nodes.map((n) => n.id)).toContain(edges[0].source);
    expect(nodes.map((n) => n.id)).toContain(edges[0].target);
  });
});

// ---------------------------------------------------------------------------
// cutSelection
// ---------------------------------------------------------------------------

describe("cutSelection", () => {
  it("removes selected nodes and their incident edges in a single snapshot", async () => {
    const n1 = makeNode("n1", "pump_1", "Pump", 100, 200, true); // selected
    const n2 = makeNode("n2", "channel_1", "Channel", 200, 200, false);
    const edge = makeEdge("e1", "n1", "n2");
    useStore.setState({
      nodes: [n1, n2],
      edges: [edge],
      _undoPast: [],
      isDirty: false,
    });

    // Spy on _pushSnapshot to assert single call
    const pushSnapshotSpy = vi.spyOn(useStore.getState(), "_pushSnapshot");

    await useStore.getState().cutSelection();

    const { nodes, edges } = useStore.getState();
    expect(nodes).toHaveLength(1);
    expect(nodes[0].id).toBe("n2");
    expect(edges).toHaveLength(0);
    expect(useStore.getState().isDirty).toBe(true);

    // Single snapshot (not two separate pushes)
    expect(useStore.getState()._undoPast).toHaveLength(1);
    pushSnapshotSpy.mockRestore();
  });

  it("also writes clipboard so pasted after cut works", async () => {
    const n1 = makeNode("n1", "pump_1", "Pump", 100, 200, true);
    useStore.setState({ nodes: [n1], edges: [] });

    await useStore.getState().cutSelection();

    expect(writeTextMock).toHaveBeenCalledTimes(1);
    const payload: ClipboardPayload = JSON.parse(writeTextMock.mock.calls[0][0] as string);
    expect(payload.nodes).toHaveLength(1);
    expect(payload.nodes[0].data.instanceName).toBe("pump_1");
  });
});

// ---------------------------------------------------------------------------
// duplicateSelection
// ---------------------------------------------------------------------------

describe("duplicateSelection", () => {
  it("produces new nodes at fixed +20px/+20px offset on every call (no accumulation)", () => {
    const n1 = makeNode("n1", "pump_1", "Pump", 100, 200, true);
    useStore.setState({ nodes: [n1] });

    useStore.getState().duplicateSelection();

    const afterFirst = useStore.getState().nodes;
    // New node is now selected (the old one is deselected)
    const firstDupe = afterFirst.find((n) => n.selected);
    expect(firstDupe).toBeDefined();
    expect(firstDupe!.position.x).toBe(120); // 100 + 20
    expect(firstDupe!.position.y).toBe(220); // 200 + 20

    // Duplicate again — second duplicate should also land at +20 from ITS source
    // (firstDupe is now selected, position {120, 220})
    useStore.getState().duplicateSelection();

    const afterSecond = useStore.getState().nodes;
    const secondDupe = afterSecond.find((n) => n.selected);
    expect(secondDupe).toBeDefined();
    expect(secondDupe!.position.x).toBe(140); // 120 + 20
    expect(secondDupe!.position.y).toBe(240); // 220 + 20
  });

  it("does NOT touch navigator.clipboard (D-16)", () => {
    const n1 = makeNode("n1", "pump_1", "Pump", 100, 200, true);
    useStore.setState({ nodes: [n1] });

    useStore.getState().duplicateSelection();
    useStore.getState().duplicateSelection();

    expect(writeTextMock).not.toHaveBeenCalled();
  });

  it("assigns new UUIDs (not the same ID as source)", () => {
    const n1 = makeNode("n1", "pump_1", "Pump", 100, 200, true);
    useStore.setState({ nodes: [n1] });

    useStore.getState().duplicateSelection();

    const { nodes } = useStore.getState();
    expect(nodes).toHaveLength(2);
    const ids = nodes.map((n) => n.id);
    expect(new Set(ids).size).toBe(2); // all unique
  });

  it("uses lowest-free naming per smartParseAndIncrement", () => {
    const n1 = makeNode("n1", "pump_1", "Pump", 100, 200, true);
    const n2 = makeNode("n2", "pump_2", "Pump", 200, 200, false);
    useStore.setState({ nodes: [n1, n2] });

    useStore.getState().duplicateSelection();

    const { nodes } = useStore.getState();
    const names = nodes.map((n) => n.data.instanceName as string);
    expect(names).toContain("pump_3"); // lowest free after pump_1, pump_2
  });
});
