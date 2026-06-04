// presetIO.test.ts — Unit tests for presetIO.ts exports.
//
// Coverage: serializePreset/deserializePreset round-trip, rejection branches,
// autoExtendSelection (BC-hop + non-BC + single-hop invariant + edge
// partitioning + empty-selection), normalizeLayout (positive + negative
// positions + empty), isValidPresetName (accept/reject charset), and the
// PRESET_FORMAT_VERSION literal contract.
//
// Per CLAUDE.md no-back-compat: no "loads old v0.9 .scpr" test.
// No vi.mock, no filesystem reads — all inputs are inline literals.

import { describe, it, expect } from "vitest";
import type { Node, Edge } from "@xyflow/react";
import {
  serializePreset,
  deserializePreset,
  autoExtendSelection,
  normalizeLayout,
  isValidPresetName,
  PRESET_FORMAT_VERSION,
} from "../presetIO";

// ---------------------------------------------------------------------------
// describe("serializePreset / deserializePreset round-trip")
// ---------------------------------------------------------------------------

describe("serializePreset / deserializePreset round-trip", () => {
  it("round-trips a minimal preset (one node, no edges, one geometry resource)", () => {
    const node: Node = {
      id: "node-1",
      type: "streamNode",
      position: { x: 10, y: 20 },
      data: { instanceName: "Channel_1", componentType: "Channel", parameters: {} },
    };
    const geometry = {
      uuid: "geo-uuid-1",
      name: "rect1",
      kind: "rectangular" as const,
      params: { L: 1.0, W: 0.02, H: 0.01 },
    };

    const json = serializePreset({
      name: "test-preset",
      description: "A minimal preset for testing",
      components: [node],
      connections: [],
      geometries: [geometry],
      powerShapes: [],
      layout: { "node-1": { x: 0, y: 0 } },
    });

    const result = deserializePreset(json);

    expect(result.format_version).toBe("1.0");
    expect(result.kind).toBe("preset");
    expect(result.name).toBe("test-preset");
    expect(result.description).toBe("A minimal preset for testing");
    expect(result.resources.geometries).toHaveLength(1);
    expect(result.resources.geometries[0].uuid).toBe("geo-uuid-1");
    expect(result.resources.power_shapes).toHaveLength(0);
    expect(result.resources.fluids).toHaveLength(0);
    expect(result.components).toHaveLength(1);
    expect(result.components[0].id).toBe("node-1");
    expect(result.connections).toHaveLength(0);
    expect(result.layout["node-1"]).toEqual({ x: 0, y: 0 });
  });

  it("strips data.autoExtended from serialized output", () => {
    const nodeWithAutoExtended: Node = {
      id: "node-2",
      type: "streamNode",
      position: { x: 0, y: 0 },
      data: {
        instanceName: "WT_1",
        componentType: "WallTemperature",
        parameters: {},
        autoExtended: true,
      },
    };

    const json = serializePreset({
      name: "strip-test",
      description: "",
      components: [nodeWithAutoExtended],
      connections: [],
      geometries: [],
      powerShapes: [],
      layout: {},
    });

    const raw = JSON.parse(json) as {
      components: Array<{ data: Record<string, unknown> }>;
    };
    expect(raw.components[0].data.autoExtended).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// describe("deserializePreset rejection")
// ---------------------------------------------------------------------------

describe("deserializePreset rejection", () => {
  it("rejects missing format_version — throw message contains 'missing format_version'", () => {
    const badJson = JSON.stringify({ kind: "preset", name: "x" });
    expect(() => deserializePreset(badJson)).toThrow("missing format_version");
  });

  it("rejects wrong format_version (e.g. '2.0') — throw message contains \"got '2.0'\"", () => {
    const badJson = JSON.stringify({
      format_version: "2.0",
      kind: "preset",
      name: "x",
    });
    expect(() => deserializePreset(badJson)).toThrow("got '2.0'");
  });

  it("rejects wrong kind (e.g. 'project') — throw message contains 'kind'", () => {
    const badJson = JSON.stringify({
      format_version: "1.0",
      kind: "project",
      name: "x",
    });
    expect(() => deserializePreset(badJson)).toThrow("kind");
  });
});

// ---------------------------------------------------------------------------
// describe("autoExtendSelection")
// ---------------------------------------------------------------------------

function makeNode(id: string): Node {
  return {
    id,
    type: "streamNode",
    position: { x: 0, y: 0 },
    data: {},
  };
}

function makeBcEdge(id: string, source: string, target: string): Edge {
  return { id, source, target, type: "bcEdge" };
}

function makeHydraulicEdge(id: string, source: string, target: string): Edge {
  return { id, source, target, type: "hydraulicEdge" };
}

describe("autoExtendSelection", () => {
  it("BC edge with one endpoint in selection adds the other endpoint to extendedIds", () => {
    const nodes = [makeNode("A"), makeNode("B")];
    const edges = [makeBcEdge("e1", "A", "B")];
    const selected = new Set(["A"]);

    const { extendedIds } = autoExtendSelection(selected, nodes, edges);

    expect(extendedIds.has("A")).toBe(true);
    expect(extendedIds.has("B")).toBe(true);
  });

  it("non-BC edge (type: 'hydraulicEdge') does NOT add neighbour to extendedIds", () => {
    const nodes = [makeNode("A"), makeNode("B")];
    const edges = [makeHydraulicEdge("e1", "A", "B")];
    const selected = new Set(["A"]);

    const { extendedIds } = autoExtendSelection(selected, nodes, edges);

    expect(extendedIds.has("A")).toBe(true);
    expect(extendedIds.has("B")).toBe(false);
  });

  it("single-hop only (D-13): given S={A}, A--bcEdge--B--bcEdge--C, extended set is {A,B} not {A,B,C}", () => {
    const nodes = [makeNode("A"), makeNode("B"), makeNode("C")];
    const edges = [
      makeBcEdge("e1", "A", "B"),
      makeBcEdge("e2", "B", "C"),
    ];
    const selected = new Set(["A"]);

    const { extendedIds } = autoExtendSelection(selected, nodes, edges);

    expect(extendedIds.has("A")).toBe(true);
    expect(extendedIds.has("B")).toBe(true);
    // C must NOT be added: the extension is one hop only, not recursive
    expect(extendedIds.has("C")).toBe(false);
  });

  it("edges fully inside extendedIds are returned in keptEdges", () => {
    const nodes = [makeNode("A"), makeNode("B")];
    const edges = [makeBcEdge("e1", "A", "B")];
    const selected = new Set(["A"]);

    const { keptEdges } = autoExtendSelection(selected, nodes, edges);

    expect(keptEdges).toHaveLength(1);
    expect(keptEdges[0].id).toBe("e1");
  });

  it("edges with exactly one endpoint outside extendedIds (after extension) are returned in droppedEdges", () => {
    // A is selected; B is connected via bcEdge (gets extended in); C is outside
    const nodes = [makeNode("A"), makeNode("B"), makeNode("C")];
    const bcEdge = makeBcEdge("e1", "A", "B");
    const hydraulicEdge = makeHydraulicEdge("e2", "B", "C"); // crosses boundary
    const edges = [bcEdge, hydraulicEdge];
    const selected = new Set(["A"]);

    const { keptEdges, droppedEdges } = autoExtendSelection(
      selected,
      nodes,
      edges,
    );

    // e1 (A--bc--B): both A and B in extendedIds → kept
    expect(keptEdges.map((e) => e.id)).toContain("e1");
    // e2 (B--hydraulic--C): C is outside extendedIds → dropped
    expect(droppedEdges.map((e) => e.id)).toContain("e2");
  });

  it("returns identical extendedIds shape when called with empty selectedNodeIds", () => {
    const nodes = [makeNode("A"), makeNode("B")];
    const edges = [makeBcEdge("e1", "A", "B")];
    const selected = new Set<string>();

    const { extendedIds, keptEdges, droppedEdges } = autoExtendSelection(
      selected,
      nodes,
      edges,
    );

    // No node is selected so no BC hop can trigger (XOR is false for both)
    expect(extendedIds.size).toBe(0);
    expect(keptEdges).toHaveLength(0);
    expect(droppedEdges).toHaveLength(1); // e1 has both endpoints outside
  });
});

// ---------------------------------------------------------------------------
// describe("normalizeLayout")
// ---------------------------------------------------------------------------

describe("normalizeLayout", () => {
  it("shifts all positions so bbox-top-left is at (0, 0)", () => {
    const nodes: Node[] = [
      { id: "n1", position: { x: 50, y: 30 }, data: {}, type: "streamNode" },
      { id: "n2", position: { x: 150, y: 80 }, data: {}, type: "streamNode" },
    ];

    const layout = normalizeLayout(nodes);

    const xs = Object.values(layout).map((p) => p.x);
    const ys = Object.values(layout).map((p) => p.y);
    expect(Math.min(...xs)).toBe(0);
    expect(Math.min(...ys)).toBe(0);
  });

  it("tolerates negative source positions: (-100,-50) and (50,100) → (0,0) and (150,150)", () => {
    const nodes: Node[] = [
      { id: "n1", position: { x: -100, y: -50 }, data: {}, type: "streamNode" },
      { id: "n2", position: { x: 50, y: 100 }, data: {}, type: "streamNode" },
    ];

    const layout = normalizeLayout(nodes);

    expect(layout["n1"]).toEqual({ x: 0, y: 0 });
    expect(layout["n2"]).toEqual({ x: 150, y: 150 });
  });

  it("returns {} for empty nodes array (no crash on Math.min(...))", () => {
    const layout = normalizeLayout([]);
    expect(layout).toEqual({});
  });
});

// ---------------------------------------------------------------------------
// describe("isValidPresetName")
// ---------------------------------------------------------------------------

describe("isValidPresetName", () => {
  it("accepts 'mtr-fuel-assembly', 'abc', 'abc_123', '_-_'", () => {
    expect(isValidPresetName("mtr-fuel-assembly")).toBe(true);
    expect(isValidPresetName("abc")).toBe(true);
    expect(isValidPresetName("abc_123")).toBe(true);
    expect(isValidPresetName("_-_")).toBe(true);
  });

  it("rejects empty string, names with spaces, dots, slashes, Unicode, parens, semicolons", () => {
    expect(isValidPresetName("")).toBe(false);
    expect(isValidPresetName("hello world")).toBe(false);
    expect(isValidPresetName("a.b")).toBe(false);
    expect(isValidPresetName("a/b")).toBe(false);
    expect(isValidPresetName("βeta")).toBe(false);
    expect(isValidPresetName("foo(bar)")).toBe(false);
    expect(isValidPresetName("foo;bar")).toBe(false);
  });

  it("rejects names exceeding the regex: 'a.b', 'a/b', 'a b'", () => {
    expect(isValidPresetName("a.b")).toBe(false);
    expect(isValidPresetName("a/b")).toBe(false);
    expect(isValidPresetName("a b")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// describe("PRESET_FORMAT_VERSION")
// ---------------------------------------------------------------------------

describe("PRESET_FORMAT_VERSION", () => {
  it("is the literal string '1.0' (locks the contract from drifting)", () => {
    expect(PRESET_FORMAT_VERSION).toBe("1.0");
  });
});
