import { describe, it, expect } from "vitest";
import {
  serializeProject,
  deserializeProject,
  addToRecent,
  reconstructInstanceCounters,
} from "../projectIO";
import type { Node, Edge } from "@xyflow/react";
import type { BCEntry } from "../codeGenerator";

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

const sampleNodes: Node[] = [
  {
    id: "node-1",
    type: "streamNode",
    position: { x: 100, y: 200 },
    data: { componentId: "Pump", instanceName: "pump_1", parameters: {} },
  },
  {
    id: "node-2",
    type: "streamNode",
    position: { x: 300, y: 200 },
    data: {
      componentId: "Channel",
      instanceName: "channel_1",
      parameters: { n: 10 },
    },
  },
];

const sampleEdges: Edge[] = [
  {
    id: "edge-1",
    source: "node-1",
    target: "node-2",
    sourceHandle: "outlet",
    targetHandle: "inlet",
  },
];

const sampleBcs: BCEntry[] = [
  { nodeId: "node-1", portField: "inlet.P", value: 1e5 },
];

// ---------------------------------------------------------------------------
// serializeProject
// ---------------------------------------------------------------------------

describe("serializeProject", () => {
  it("returns a JSON string", () => {
    const result = serializeProject(sampleNodes, sampleEdges, sampleBcs);
    expect(typeof result).toBe("string");
    expect(() => JSON.parse(result)).not.toThrow();
  });

  it("includes version 2", () => {
    const result = serializeProject(sampleNodes, sampleEdges, sampleBcs);
    const parsed = JSON.parse(result);
    expect(parsed.version).toBe(2);
  });

  it("includes nodes array", () => {
    const result = serializeProject(sampleNodes, sampleEdges, sampleBcs);
    const parsed = JSON.parse(result);
    expect(Array.isArray(parsed.nodes)).toBe(true);
    expect(parsed.nodes).toHaveLength(2);
  });

  it("includes edges array", () => {
    const result = serializeProject(sampleNodes, sampleEdges, sampleBcs);
    const parsed = JSON.parse(result);
    expect(Array.isArray(parsed.edges)).toBe(true);
    expect(parsed.edges).toHaveLength(1);
  });

  it("includes bcs array", () => {
    const result = serializeProject(sampleNodes, sampleEdges, sampleBcs);
    const parsed = JSON.parse(result);
    expect(Array.isArray(parsed.bcs)).toBe(true);
    expect(parsed.bcs).toHaveLength(1);
  });

  it("serializes empty arrays correctly", () => {
    const result = serializeProject([], [], []);
    const parsed = JSON.parse(result);
    expect(parsed.nodes).toEqual([]);
    expect(parsed.edges).toEqual([]);
    expect(parsed.bcs).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// deserializeProject
// ---------------------------------------------------------------------------

describe("deserializeProject", () => {
  it("parses valid JSON and returns a StreamProject", () => {
    const json = serializeProject(sampleNodes, sampleEdges, sampleBcs);
    const project = deserializeProject(json);
    expect(project.version).toBe(2);
    expect(project.nodes).toHaveLength(2);
    expect(project.edges).toHaveLength(1);
    expect(project.bcs).toHaveLength(1);
  });

  it("throws Error('Invalid .streamgui file') when version is missing", () => {
    const json = JSON.stringify({ nodes: [], edges: [], bcs: [] });
    expect(() => deserializeProject(json)).toThrow("Invalid .streamgui file");
  });

  it("throws Error('Invalid .streamgui file') when nodes is missing", () => {
    const json = JSON.stringify({ version: 1, edges: [], bcs: [] });
    expect(() => deserializeProject(json)).toThrow("Invalid .streamgui file");
  });

  it("throws Error('Invalid .streamgui file') when edges is missing", () => {
    const json = JSON.stringify({ version: 1, nodes: [], bcs: [] });
    expect(() => deserializeProject(json)).toThrow("Invalid .streamgui file");
  });

  it("throws Error('Invalid .streamgui file') when bcs is missing", () => {
    const json = JSON.stringify({ version: 1, nodes: [], edges: [] });
    expect(() => deserializeProject(json)).toThrow("Invalid .streamgui file");
  });

  it("throws on malformed JSON", () => {
    expect(() => deserializeProject("{invalid json")).toThrow();
  });

  it("throws Error('Invalid .streamgui file') when nodes is not an array", () => {
    const json = JSON.stringify({ version: 1, nodes: "bad", edges: [], bcs: [] });
    expect(() => deserializeProject(json)).toThrow("Invalid .streamgui file");
  });

  it("throws Error('Invalid .streamgui file') when edges is not an array", () => {
    const json = JSON.stringify({ version: 1, nodes: [], edges: null, bcs: [] });
    expect(() => deserializeProject(json)).toThrow("Invalid .streamgui file");
  });

  it("throws Error('Invalid .streamgui file') when bcs is not an array", () => {
    const json = JSON.stringify({ version: 1, nodes: [], edges: [], bcs: 42 });
    expect(() => deserializeProject(json)).toThrow("Invalid .streamgui file");
  });

  it("throws Error('Invalid .streamgui file') when version is not a number", () => {
    const json = JSON.stringify({ version: "1", nodes: [], edges: [], bcs: [] });
    expect(() => deserializeProject(json)).toThrow("Invalid .streamgui file");
  });
});

// ---------------------------------------------------------------------------
// addToRecent
// ---------------------------------------------------------------------------

describe("addToRecent", () => {
  it("adds to an empty list", () => {
    const result = addToRecent([], "/path/a.streamgui");
    expect(result).toEqual(["/path/a.streamgui"]);
  });

  it("prepends to existing list", () => {
    const result = addToRecent(["/a", "/b"], "/c");
    expect(result[0]).toBe("/c");
  });

  it("deduplicates and moves existing path to top", () => {
    const result = addToRecent(["/a", "/b", "/c"], "/b");
    expect(result).toEqual(["/b", "/a", "/c"]);
  });

  it("does not duplicate the path in the list", () => {
    const result = addToRecent(["/a", "/b"], "/b");
    const count = result.filter((f) => f === "/b").length;
    expect(count).toBe(1);
  });

  it("truncates to 5 entries", () => {
    const files = ["/a", "/b", "/c", "/d", "/e"];
    const result = addToRecent(files, "/f");
    expect(result).toHaveLength(5);
    expect(result[0]).toBe("/f");
  });

  it("keeps most recent at index 0", () => {
    const result = addToRecent(["/old1", "/old2"], "/new");
    expect(result[0]).toBe("/new");
  });

  it("with exactly 5 items, adding a new item keeps the list at 5", () => {
    const files = ["/a", "/b", "/c", "/d", "/e"];
    const result = addToRecent(files, "/f");
    expect(result).toHaveLength(5);
    // /e should have been dropped
    expect(result.includes("/e")).toBe(false);
  });

  it("with 6 items already, truncates to 5", () => {
    const files = ["/a", "/b", "/c", "/d", "/e", "/f"];
    const result = addToRecent(files, "/g");
    expect(result).toHaveLength(5);
  });
});

// ---------------------------------------------------------------------------
// reconstructInstanceCounters
// ---------------------------------------------------------------------------

describe("reconstructInstanceCounters", () => {
  it("returns empty object for empty nodes array", () => {
    const result = reconstructInstanceCounters([]);
    expect(result).toEqual({});
  });

  it("reconstructs counter for a single node", () => {
    const nodes: Node[] = [
      {
        id: "n1",
        type: "streamNode",
        position: { x: 0, y: 0 },
        data: { componentId: "Pump", instanceName: "pump_3", parameters: {} },
      },
    ];
    const result = reconstructInstanceCounters(nodes);
    expect(result["pump"]).toBe(3);
  });

  it("tracks max counter for multiple nodes of the same type", () => {
    const nodes: Node[] = [
      {
        id: "n1",
        type: "streamNode",
        position: { x: 0, y: 0 },
        data: { componentId: "Pump", instanceName: "pump_1", parameters: {} },
      },
      {
        id: "n2",
        type: "streamNode",
        position: { x: 0, y: 0 },
        data: { componentId: "Pump", instanceName: "pump_5", parameters: {} },
      },
      {
        id: "n3",
        type: "streamNode",
        position: { x: 0, y: 0 },
        data: { componentId: "Pump", instanceName: "pump_2", parameters: {} },
      },
    ];
    const result = reconstructInstanceCounters(nodes);
    expect(result["pump"]).toBe(5);
  });

  it("tracks separate counters for different component types", () => {
    const nodes: Node[] = [
      {
        id: "n1",
        type: "streamNode",
        position: { x: 0, y: 0 },
        data: { componentId: "Pump", instanceName: "pump_2", parameters: {} },
      },
      {
        id: "n2",
        type: "streamNode",
        position: { x: 0, y: 0 },
        data: {
          componentId: "Channel",
          instanceName: "channel_4",
          parameters: {},
        },
      },
    ];
    const result = reconstructInstanceCounters(nodes);
    expect(result["pump"]).toBe(2);
    expect(result["channel"]).toBe(4);
  });

  it("ignores custom-renamed nodes that do not match componentId pattern", () => {
    const nodes: Node[] = [
      {
        id: "n1",
        type: "streamNode",
        position: { x: 0, y: 0 },
        data: {
          componentId: "Pump",
          instanceName: "my_custom_pump",
          parameters: {},
        },
      },
    ];
    const result = reconstructInstanceCounters(nodes);
    // "my_custom_pump" does not match ^pump_(\d+)$, so no counter for "pump"
    expect(result["pump"]).toBeUndefined();
  });

  it("does not create spurious counter for custom names with trailing number", () => {
    const nodes: Node[] = [
      {
        id: "n1",
        type: "streamNode",
        position: { x: 0, y: 0 },
        data: {
          componentId: "Pump",
          instanceName: "my_custom_3",
          parameters: {},
        },
      },
    ];
    const result = reconstructInstanceCounters(nodes);
    // "my_custom_3" does not match ^pump_(\d+)$
    expect(result["pump"]).toBeUndefined();
    // Should not create a "my_custom" key either
    expect(result["my_custom"]).toBeUndefined();
  });

  it("handles mix of default-named and custom-renamed nodes", () => {
    const nodes: Node[] = [
      {
        id: "n1",
        type: "streamNode",
        position: { x: 0, y: 0 },
        data: { componentId: "Pump", instanceName: "pump_2", parameters: {} },
      },
      {
        id: "n2",
        type: "streamNode",
        position: { x: 0, y: 0 },
        data: { componentId: "Pump", instanceName: "main_pump", parameters: {} },
      },
      {
        id: "n3",
        type: "streamNode",
        position: { x: 0, y: 0 },
        data: { componentId: "Channel", instanceName: "channel_5", parameters: {} },
      },
    ];
    const result = reconstructInstanceCounters(nodes);
    expect(result["pump"]).toBe(2);       // Only pump_2 counts, not main_pump
    expect(result["channel"]).toBe(5);
  });
});

// ---------------------------------------------------------------------------
// StreamProject v2
// ---------------------------------------------------------------------------

describe("StreamProject v2", () => {
  it("serializeProject writes version 2 with activeLayer", () => {
    const result = serializeProject(sampleNodes, sampleEdges, sampleBcs, "Thermal");
    const parsed = JSON.parse(result);
    expect(parsed.version).toBe(2);
    expect(parsed.activeLayer).toBe("Thermal");
  });

  it("serializeProject defaults activeLayer to Both", () => {
    const result = serializeProject(sampleNodes, sampleEdges, sampleBcs);
    const parsed = JSON.parse(result);
    expect(parsed.version).toBe(2);
    expect(parsed.activeLayer).toBe("Both");
  });

  it("deserializeProject handles v1 files (no activeLayer)", () => {
    const v1Json = JSON.stringify({
      version: 1,
      nodes: [],
      edges: [],
      bcs: [],
    });
    const project = deserializeProject(v1Json);
    expect(project.activeLayer).toBe("Both");
    expect(project.version).toBe(2);
  });

  it("deserializeProject preserves v2 activeLayer", () => {
    const v2Json = JSON.stringify({
      version: 2,
      nodes: [],
      edges: [],
      bcs: [],
      activeLayer: "Thermal",
    });
    const project = deserializeProject(v2Json);
    expect(project.activeLayer).toBe("Thermal");
  });

  it("round-trip preserves activeLayer", () => {
    const json = serializeProject(sampleNodes, sampleEdges, sampleBcs, "Hydraulic");
    const project = deserializeProject(json);
    expect(project.activeLayer).toBe("Hydraulic");
  });
});
