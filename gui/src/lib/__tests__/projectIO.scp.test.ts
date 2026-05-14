// projectIO.scp.test.ts
// -----------------------------------------------------------------------------
// Vitest coverage for the Phase-62 .scp v2.0 serialize / deserialize path.
//
// Covers invariants:
//   INV-06 — round-trip preserves resources / components / connections / model_options
//   INV-07 — `unset` Power Shape persists across save/load via the sentinel
//   INV-08 — strict format_version: "2.0"; legacy numeric-version form rejected, no migration
//   INV-09 — file_loaded Power Shape stores a path string verbatim across round-trip
//   INV-11 — layout.active_left_tab round-trips; defaults to "Components" if missing
//   INV-13 — round-trip on a richly-populated project is structurally stable
//
// NB: per the plan (D-24), the absolute->relative path conversion lives in
// useStore.ts.saveProjectAs — projectIO.ts preserves whatever string it is handed.
// Tauri dialog filter strings are validated by source-grep gates in Task 2.

import { describe, it, expect } from "vitest";
import type { Node, Edge } from "@xyflow/react";
import {
  serializeProject,
  deserializeProject,
  PROJECT_FORMAT_VERSION,
} from "../projectIO";
import { SENTINEL_UNSET_POWER_SHAPE, SENTINEL_LIGHT_WATER_FLUID } from "../../store/useStore";
import type {
  GeometryResource,
  PowerShapeResource,
  FluidResource,
  ModelOptionsSliceState,
} from "../../store/useStore";
import type { AnchorEntry } from "../anchors";

// ---------------------------------------------------------------------------
// Fixture
// ---------------------------------------------------------------------------

function makeGeometries(): Record<string, GeometryResource> {
  return {
    "geo-uuid-1": {
      uuid: "geo-uuid-1",
      name: "mtr_channel",
      kind: "rectangular",
      params: { L: 0.6, W: 0.07, H: 0.0025 },
    },
    "geo-uuid-2": {
      uuid: "geo-uuid-2",
      name: "round_pipe",
      kind: "circular",
      params: { L: 1.2, D: 0.025 },
    },
  };
}

function makePowerShapes(): Record<string, PowerShapeResource> {
  return {
    // Sentinel — MUST NOT appear in serialized output.
    [SENTINEL_UNSET_POWER_SHAPE]: {
      uuid: SENTINEL_UNSET_POWER_SHAPE,
      name: "(leave unset — set in code)",
      kind: "unset",
      params: {},
    },
    "ps-uuid-uniform": {
      uuid: "ps-uuid-uniform",
      name: "flat_one",
      kind: "uniform",
      params: {},
    },
    "ps-uuid-cos": {
      uuid: "ps-uuid-cos",
      name: "axial_cos",
      kind: "z_cosine",
      params: { amplitude: 1.3 },
    },
    "ps-uuid-file": {
      uuid: "ps-uuid-file",
      name: "imported_csv",
      kind: "file_loaded",
      params: { path: "shapes/mtr.csv" },
    },
  };
}

function makeFluids(): Record<string, FluidResource> {
  return {
    [SENTINEL_LIGHT_WATER_FLUID]: {
      uuid: SENTINEL_LIGHT_WATER_FLUID,
      name: "light_water",
    },
  };
}

function makeModelOptions(): ModelOptionsSliceState {
  return {
    name: "demo project",
    description: "MTR loop with cosine axial shape",
    default_fluid: "water",
    g_default: 9.80665,
    solver: { abstol: 1e-8, reltol: 1e-6, dtmax: null },
  };
}

function makeNodes(): Node[] {
  return [
    {
      id: "node-1",
      type: "streamNode",
      position: { x: 100, y: 200 },
      data: {
        componentId: "ChannelAndContacts",
        instanceName: "cac_1",
        parameters: { geometry_ref: "geo-uuid-1" },
      },
    },
    {
      id: "node-2",
      type: "streamNode",
      position: { x: 320, y: 200 },
      data: {
        componentId: "HeatDiffusion",
        instanceName: "hd_1",
        parameters: { power_shape_ref: "ps-uuid-cos", nz: 10, nx: 5 },
      },
    },
    {
      id: "node-3",
      type: "streamNode",
      position: { x: 500, y: 200 },
      data: {
        componentId: "Pump",
        instanceName: "pump_1",
        parameters: { dP: 1e5 },
      },
    },
    {
      id: "node-4",
      type: "streamNode",
      position: { x: 700, y: 200 },
      data: {
        componentId: "Channel",
        instanceName: "channel_1",
        parameters: { geometry_ref: "geo-uuid-2", n: 8 },
      },
    },
  ];
}

function makeEdges(): Edge[] {
  return [
    {
      id: "edge-1",
      source: "node-1",
      target: "node-2",
      sourceHandle: "wall_out",
      targetHandle: "wall_in",
    },
    {
      id: "edge-2",
      source: "node-3",
      target: "node-4",
      sourceHandle: "port_out",
      targetHandle: "port_in",
    },
  ];
}

// Phase 63.1 D-02: anchors Record keyed by nodeId replaces the legacy
// boundary-conditions Array.
function makeAnchors(): Record<string, AnchorEntry> {
  return { "node-3": { portField: "port_in.P", value: 1e5 } };
}

function makeSerializeArgs() {
  return {
    nodes: makeNodes(),
    edges: makeEdges(),
    anchors: makeAnchors(),
    resources: {
      geometries: makeGeometries(),
      powerShapes: makePowerShapes(),
      fluids: makeFluids(),
    },
    modelOptions: makeModelOptions(),
    activeLeftTab: "Resources" as const,
    activeLayer: "Both" as const,
    snapToGrid: false, // Phase 65 D-10
  };
}

// ---------------------------------------------------------------------------
// PROJECT_FORMAT_VERSION
// ---------------------------------------------------------------------------

describe("PROJECT_FORMAT_VERSION", () => {
  it("is the literal string \"2.0\" (D-27)", () => {
    expect(PROJECT_FORMAT_VERSION).toBe("2.0");
  });
});

// ---------------------------------------------------------------------------
// serializeProject
// ---------------------------------------------------------------------------

describe("serializeProject (INV-06, INV-08)", () => {
  it("emits format_version: \"2.0\" at the top level", () => {
    const json = serializeProject(makeSerializeArgs());
    const parsed = JSON.parse(json);
    expect(parsed.format_version).toBe("2.0");
  });

  it("emits resources.geometries as an array (not a Record)", () => {
    const json = serializeProject(makeSerializeArgs());
    const parsed = JSON.parse(json);
    expect(Array.isArray(parsed.resources.geometries)).toBe(true);
    expect(parsed.resources.geometries).toHaveLength(2);
  });

  it("filters out the unset Power Shape sentinel on save (sentinel-skip)", () => {
    const json = serializeProject(makeSerializeArgs());
    const parsed = JSON.parse(json);
    const sentinel = parsed.resources.power_shapes.find(
      (p: { uuid: string }) => p.uuid === SENTINEL_UNSET_POWER_SHAPE,
    );
    expect(sentinel).toBeUndefined();
    // The three real user PowerShapes survive.
    expect(parsed.resources.power_shapes).toHaveLength(3);
  });

  it("filters out the light_water Fluid placeholder on save", () => {
    const json = serializeProject(makeSerializeArgs());
    const parsed = JSON.parse(json);
    const lw = parsed.resources.fluids.find(
      (f: { name: string }) => f.name === "light_water",
    );
    expect(lw).toBeUndefined();
  });

  it("emits layout.active_left_tab from the input activeLeftTab (INV-11)", () => {
    const json = serializeProject(makeSerializeArgs());
    const parsed = JSON.parse(json);
    expect(parsed.layout).toBeDefined();
    expect(parsed.layout.active_left_tab).toBe("Resources");
    expect(parsed.layout.active_layer).toBe("Both");
  });

  it("emits components / connections arrays (renamed from nodes / edges)", () => {
    const json = serializeProject(makeSerializeArgs());
    const parsed = JSON.parse(json);
    expect(Array.isArray(parsed.components)).toBe(true);
    expect(Array.isArray(parsed.connections)).toBe(true);
    expect(parsed.components).toHaveLength(4);
    expect(parsed.connections).toHaveLength(2);
  });

  it("preserves file_loaded Power Shape path verbatim (INV-09)", () => {
    const json = serializeProject(makeSerializeArgs());
    const parsed = JSON.parse(json);
    const fileLoaded = parsed.resources.power_shapes.find(
      (p: { kind: string }) => p.kind === "file_loaded",
    );
    expect(fileLoaded.params.path).toBe("shapes/mtr.csv");
  });

  it("emits model_options block", () => {
    const json = serializeProject(makeSerializeArgs());
    const parsed = JSON.parse(json);
    expect(parsed.model_options).toBeDefined();
    expect(parsed.model_options.g_default).toBe(9.80665);
    expect(parsed.model_options.name).toBe("demo project");
  });

  it("does not emit a legacy `version: 1 | 2` numeric field", () => {
    const json = serializeProject(makeSerializeArgs());
    const parsed = JSON.parse(json);
    expect(parsed.version).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// deserializeProject — happy path + round-trip
// ---------------------------------------------------------------------------

describe("deserializeProject — round-trip (INV-06, INV-13)", () => {
  it("returns a project structurally equal to the input on round-trip", () => {
    const args = makeSerializeArgs();
    const json = serializeProject(args);
    const project = deserializeProject(json);

    expect(project.format_version).toBe("2.0");

    // resources arrays restored, sentinel excluded
    expect(project.resources.geometries).toHaveLength(2);
    expect(project.resources.power_shapes).toHaveLength(3);
    expect(
      project.resources.power_shapes.find(
        (p) => p.uuid === SENTINEL_UNSET_POWER_SHAPE,
      ),
    ).toBeUndefined();

    // components / connections / anchors (D-02 round-trip)
    expect(project.components).toHaveLength(4);
    expect(project.connections).toHaveLength(2);
    expect(Object.keys(project.anchors)).toHaveLength(1);
    expect(project.anchors["node-3"]).toEqual({
      portField: "port_in.P",
      value: 1e5,
    });

    // model_options
    expect(project.model_options.g_default).toBe(9.80665);
    expect(project.model_options.solver.abstol).toBe(1e-8);

    // layout (INV-11)
    expect(project.layout.active_left_tab).toBe("Resources");
    expect(project.layout.active_layer).toBe("Both");
  });

  it("preserves file_loaded path as a plain relative string (INV-09)", () => {
    const json = serializeProject(makeSerializeArgs());
    const project = deserializeProject(json);
    const fileLoaded = project.resources.power_shapes.find(
      (p) => p.kind === "file_loaded",
    );
    expect(fileLoaded?.params.path).toBe("shapes/mtr.csv");
    // function MUST NOT resolve to absolute
    expect(fileLoaded?.params.path?.startsWith("/")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// deserializeProject — strict format_version (INV-08, D-28)
// ---------------------------------------------------------------------------

describe("deserializeProject — strict format_version (INV-07, INV-08, D-28)", () => {
  it("throws when format_version is missing entirely", () => {
    const bad = JSON.stringify({ resources: {}, components: [] });
    expect(() => deserializeProject(bad)).toThrow(/format_version/i);
  });

  it("throws when format_version is the wrong string (\"1.5\")", () => {
    const bad = JSON.stringify({ format_version: "1.5" });
    expect(() => deserializeProject(bad)).toThrow(/format_version/i);
  });

  it("throws when format_version is the wrong string (\"3.0\")", () => {
    const bad = JSON.stringify({ format_version: "3.0" });
    expect(() => deserializeProject(bad)).toThrow(/format_version/i);
  });

  it("rejects legacy v2 numeric form { version: 2, nodes: [...] } (INV-08, D-28)", () => {
    // Phase 63.1 acceptance: legacy boundary-conditions field omitted here —
    // the format_version check throws before any payload field is parsed,
    // so the historical legacy fields are not load-bearing.
    const legacy = JSON.stringify({
      version: 2,
      activeLayer: "Both",
    });
    expect(() => deserializeProject(legacy)).toThrow(/format_version/i);
  });

  it("rejects legacy v1 numeric form (INV-08, D-28)", () => {
    const legacy = JSON.stringify({
      version: 1,
    });
    expect(() => deserializeProject(legacy)).toThrow(/format_version/i);
  });

  it("rejects format_version: 2 (numeric, not string)", () => {
    const bad = JSON.stringify({ format_version: 2 });
    expect(() => deserializeProject(bad)).toThrow(/format_version/i);
  });

  it("throws on malformed JSON (inherited from JSON.parse)", () => {
    expect(() => deserializeProject("{not json")).toThrow();
  });
});

// ---------------------------------------------------------------------------
// deserializeProject — empty-state tolerance (RESEARCH Pitfall 3)
// ---------------------------------------------------------------------------

describe("deserializeProject — empty-state tolerance", () => {
  it("returns a populated default object when only format_version is present", () => {
    const minimal = JSON.stringify({ format_version: "2.0" });
    const project = deserializeProject(minimal);

    expect(project.format_version).toBe("2.0");
    expect(project.resources.geometries).toEqual([]);
    expect(project.resources.power_shapes).toEqual([]);
    expect(project.resources.fluids).toEqual([]);
    expect(project.components).toEqual([]);
    expect(project.connections).toEqual([]);
    // Phase 63.1 D-02: anchors defaults to empty Record (not Array).
    expect(project.anchors).toEqual({});
    expect(project.layout.active_left_tab).toBe("Components");
    expect(project.layout.active_layer).toBe("Both");
    expect(project.model_options).toBeDefined();
    expect(project.model_options.g_default).toBe(9.80665);
  });

  it("defaults layout.active_left_tab to \"Components\" when missing (INV-11)", () => {
    const json = JSON.stringify({
      format_version: "2.0",
      layout: { active_layer: "Hydraulic" },
    });
    const project = deserializeProject(json);
    expect(project.layout.active_left_tab).toBe("Components");
    expect(project.layout.active_layer).toBe("Hydraulic");
  });

  it("defaults missing resources sub-arrays to empty []", () => {
    const json = JSON.stringify({
      format_version: "2.0",
      resources: { geometries: [{ uuid: "g1", name: "g", kind: "rectangular", params: { L: 1 } }] },
    });
    const project = deserializeProject(json);
    expect(project.resources.geometries).toHaveLength(1);
    expect(project.resources.power_shapes).toEqual([]);
    expect(project.resources.fluids).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// active_left_tab round-trip variants (INV-11)
// ---------------------------------------------------------------------------

describe("active_left_tab round-trip (INV-11)", () => {
  it.each(["Components", "Resources", "Project"] as const)(
    "round-trips active_left_tab = %s",
    (tab) => {
      const args = { ...makeSerializeArgs(), activeLeftTab: tab };
      const project = deserializeProject(serializeProject(args));
      expect(project.layout.active_left_tab).toBe(tab);
    },
  );
});
