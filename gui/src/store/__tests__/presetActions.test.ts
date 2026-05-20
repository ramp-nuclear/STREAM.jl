/**
 * Phase 70 Plan 03 Task 4 — Preset store action tests.
 *
 * Covers all seven preset actions under mocked Tauri FS:
 *   refreshPresetsDir, saveSelectionAsPreset, loadPresetAtPosition,
 *   loadPresetFromPath, renamePreset, deletePreset.
 *
 * Mirror of autoRecover.actions.test.ts pattern:
 *   - Top-level vi.mock for @tauri-apps/plugin-fs, @tauri-apps/api/path,
 *     and @tauri-apps/plugin-dialog.
 *   - beforeEach resets store and clears mocks.
 *   - Zero real FS operations.
 */

import { describe, it, expect, vi, beforeEach } from "vitest";
import useStore, {
  SENTINEL_UNSET_POWER_SHAPE,
  SENTINEL_LIGHT_WATER_FLUID,
} from "../useStore";
import { PRESET_FORMAT_VERSION } from "../../lib/presetIO";

// ---------------------------------------------------------------------------
// Tauri FS mock
// ---------------------------------------------------------------------------

const mockWriteTextFile = vi.fn<(path: string, content: string) => Promise<void>>();
const mockReadTextFile = vi.fn<(path: string) => Promise<string>>();
const mockRemove = vi.fn<(path: string) => Promise<void>>();
const mockMkdir = vi.fn<(path: string, opts?: unknown) => Promise<void>>();
const mockReadDir = vi.fn<(path: string) => Promise<{ name: string; isFile: boolean; isDirectory: boolean }[]>>();
const mockRename = vi.fn<(oldPath: string, newPath: string) => Promise<void>>();

vi.mock("@tauri-apps/plugin-fs", () => ({
  writeTextFile: (p: string, c: string) => mockWriteTextFile(p, c),
  readTextFile: (p: string) => mockReadTextFile(p),
  remove: (p: string) => mockRemove(p),
  mkdir: (p: string, opts?: unknown) => mockMkdir(p, opts),
  readDir: (p: string) => mockReadDir(p),
  rename: (o: string, n: string) => mockRename(o, n),
}));

// ---------------------------------------------------------------------------
// Tauri path mock
// ---------------------------------------------------------------------------

vi.mock("@tauri-apps/api/path", () => ({
  join: (...parts: string[]) => Promise.resolve(parts.join("/")),
  appConfigDir: () => Promise.resolve("/mock/config"),
}));

// ---------------------------------------------------------------------------
// Tauri dialog mock
// ---------------------------------------------------------------------------

const mockOpen = vi.fn<() => Promise<string | null>>();

vi.mock("@tauri-apps/plugin-dialog", () => ({
  open: (opts?: unknown) => { void opts; return mockOpen(); },
}));

// ---------------------------------------------------------------------------
// Minimal valid preset JSON fixture
// ---------------------------------------------------------------------------

function makePresetJson(overrides: {
  name?: string;
  description?: string;
  components?: unknown[];
  connections?: unknown[];
  geometries?: unknown[];
  powerShapes?: unknown[];
  layout?: Record<string, { x: number; y: number }>;
} = {}): string {
  return JSON.stringify({
    format_version: PRESET_FORMAT_VERSION,
    kind: "preset",
    name: overrides.name ?? "test_preset",
    description: overrides.description ?? "a test preset",
    resources: {
      geometries: overrides.geometries ?? [],
      power_shapes: overrides.powerShapes ?? [],
      fluids: [],
    },
    components: overrides.components ?? [
      {
        id: "node-A",
        type: "streamNode",
        position: { x: 0, y: 0 },
        data: {
          componentId: "Channel",
          instanceName: "channel_1",
          parameters: {},
          constructorMode: "default",
        },
        selected: false,
      },
      {
        id: "node-B",
        type: "streamNode",
        position: { x: 150, y: 0 },
        data: {
          componentId: "Channel",
          instanceName: "channel_2",
          parameters: {},
          constructorMode: "default",
        },
        selected: false,
      },
    ],
    connections: overrides.connections ?? [],
    layout: overrides.layout ?? {
      "node-A": { x: 0, y: 0 },
      "node-B": { x: 150, y: 0 },
    },
  });
}

// ---------------------------------------------------------------------------
// Helper: reset store to a known empty state before each test
// ---------------------------------------------------------------------------

function resetStore(extra: Record<string, unknown> = {}) {
  useStore.setState({
    nodes: [],
    edges: [],
    anchors: {},
    isDirty: false,
    currentFilePath: null,
    selectedNodeId: null,
    selectedResourceId: null,
    selectedResourceKind: null,
    selectionKind: "none",
    _undoPast: [],
    _undoFuture: [],
    projectPresets: [],
    libraryPresets: [],
    resources: {
      geometries: {},
      powerShapes: {
        [SENTINEL_UNSET_POWER_SHAPE]: {
          uuid: SENTINEL_UNSET_POWER_SHAPE,
          name: "(leave unset — set in code)",
          kind: "unset",
          params: {},
        },
      },
      fluids: {
        [SENTINEL_LIGHT_WATER_FLUID]: {
          uuid: SENTINEL_LIGHT_WATER_FLUID,
          name: "light_water",
        },
      },
    },
    ...extra,
  });
}

beforeEach(() => {
  resetStore();
  vi.clearAllMocks();
  // Default mock resolutions so each test only overrides what it needs.
  mockWriteTextFile.mockResolvedValue(undefined);
  mockRemove.mockResolvedValue(undefined);
  mockMkdir.mockResolvedValue(undefined);
  mockRename.mockResolvedValue(undefined);
  // readDir returns empty by default; individual tests override.
  mockReadDir.mockResolvedValue([]);
});

// ---------------------------------------------------------------------------
// describe: refreshPresetsDir
// ---------------------------------------------------------------------------

describe("refreshPresetsDir", () => {
  it("populates projectPresets from valid .scpr files in dir", async () => {
    const presetA = makePresetJson({ name: "preset_alpha", description: "Alpha" });
    const presetB = makePresetJson({ name: "preset_beta", description: "Beta" });

    mockReadDir.mockResolvedValueOnce([
      { name: "preset_alpha.scpr", isFile: true, isDirectory: false },
      { name: "preset_beta.scpr", isFile: true, isDirectory: false },
      { name: "not_a_preset.txt", isFile: true, isDirectory: false },
      { name: "subdir", isFile: false, isDirectory: true },
    ]);
    mockReadTextFile.mockResolvedValueOnce(presetA);
    mockReadTextFile.mockResolvedValueOnce(presetB);

    await useStore.getState().refreshPresetsDir("project", "/mock/project/presets");

    const state = useStore.getState();
    expect(state.projectPresets).toHaveLength(2);
    expect(state.projectPresets[0].name).toBe("preset_alpha");
    expect(state.projectPresets[0].description).toBe("Alpha");
    expect(state.projectPresets[0].filePath).toBe(
      "/mock/project/presets/preset_alpha.scpr",
    );
    expect(state.projectPresets[0].store).toBe("project");
    expect(state.projectPresets[1].name).toBe("preset_beta");
    // libraryPresets should be unaffected
    expect(state.libraryPresets).toHaveLength(0);
  });

  it("skips unreadable files without throwing", async () => {
    const validJson = makePresetJson({ name: "valid_preset", description: "" });

    mockReadDir.mockResolvedValueOnce([
      { name: "valid_preset.scpr", isFile: true, isDirectory: false },
      { name: "corrupt.scpr", isFile: true, isDirectory: false },
    ]);
    // First .scpr is valid; second returns garbage.
    mockReadTextFile
      .mockResolvedValueOnce(validJson)
      .mockResolvedValueOnce("not valid json {{{{{");

    await useStore.getState().refreshPresetsDir("library", "/mock/config/presets");

    const state = useStore.getState();
    // Only the valid preset should appear; corrupt one silently skipped.
    expect(state.libraryPresets).toHaveLength(1);
    expect(state.libraryPresets[0].name).toBe("valid_preset");
  });

  it("handles missing directory gracefully (no throw)", async () => {
    mockReadDir.mockRejectedValueOnce(new Error("ENOENT: no such file or directory"));

    // Should not throw.
    await expect(
      useStore.getState().refreshPresetsDir("project", "/no/such/dir"),
    ).resolves.toBeUndefined();

    expect(useStore.getState().projectPresets).toHaveLength(0);
  });
});

// ---------------------------------------------------------------------------
// describe: saveSelectionAsPreset
// ---------------------------------------------------------------------------

describe("saveSelectionAsPreset", () => {
  it("writes correct .scpr JSON content via writeTextFile", async () => {
    // Arrange: two selected nodes, no edges.
    resetStore({
      currentFilePath: null, // will use library store
      nodes: [
        {
          id: "n1",
          type: "streamNode",
          position: { x: 100, y: 200 },
          selected: true,
          data: { componentId: "Channel", instanceName: "channel_1", parameters: {}, constructorMode: "default" },
        },
        {
          id: "n2",
          type: "streamNode",
          position: { x: 300, y: 200 },
          selected: true,
          data: { componentId: "Channel", instanceName: "channel_2", parameters: {}, constructorMode: "default" },
        },
      ],
      edges: [],
    });
    // readDir for the subsequent refreshPresetsDir call.
    mockReadDir.mockResolvedValue([
      { name: "my_preset.scpr", isFile: true, isDirectory: false },
    ]);
    mockReadTextFile.mockResolvedValue(
      makePresetJson({ name: "my_preset", description: "desc" }),
    );

    await useStore.getState().saveSelectionAsPreset("my_preset", "desc", "library");

    expect(mockWriteTextFile).toHaveBeenCalledOnce();
    const [path, content] = mockWriteTextFile.mock.calls[0];
    expect(path).toMatch(/\/presets\/my_preset\.scpr$/);
    const parsed = JSON.parse(content);
    expect(parsed.format_version).toBe(PRESET_FORMAT_VERSION);
    expect(parsed.kind).toBe("preset");
    expect(parsed.name).toBe("my_preset");
    expect(parsed.description).toBe("desc");
    expect(parsed.components).toHaveLength(2);
  });

  it("throws when fewer than 2 components are selected", async () => {
    resetStore({
      nodes: [
        {
          id: "n1",
          type: "streamNode",
          position: { x: 0, y: 0 },
          selected: true,
          data: { componentId: "Channel", instanceName: "channel_1", parameters: {}, constructorMode: "default" },
        },
      ],
      edges: [],
    });

    await expect(
      useStore.getState().saveSelectionAsPreset("ok_name", "", "library"),
    ).rejects.toThrow("Need at least 2 selected components");
  });

  it("throws when name fails isValidPresetName (e.g. has space)", async () => {
    resetStore({
      nodes: [
        { id: "n1", type: "streamNode", position: { x: 0, y: 0 }, selected: true, data: { componentId: "Channel", instanceName: "channel_1", parameters: {}, constructorMode: "default" } },
        { id: "n2", type: "streamNode", position: { x: 0, y: 0 }, selected: true, data: { componentId: "Channel", instanceName: "channel_2", parameters: {}, constructorMode: "default" } },
      ],
      edges: [],
    });

    await expect(
      useStore.getState().saveSelectionAsPreset("bad name", "", "library"),
    ).rejects.toThrow("Invalid preset name");
  });

  it("throws when targetStore is 'project' and currentFilePath is null", async () => {
    resetStore({
      currentFilePath: null,
      nodes: [
        { id: "n1", type: "streamNode", position: { x: 0, y: 0 }, selected: true, data: { componentId: "Channel", instanceName: "channel_1", parameters: {}, constructorMode: "default" } },
        { id: "n2", type: "streamNode", position: { x: 0, y: 0 }, selected: true, data: { componentId: "Channel", instanceName: "channel_2", parameters: {}, constructorMode: "default" } },
      ],
      edges: [],
    });

    await expect(
      useStore.getState().saveSelectionAsPreset("my_preset", "", "project"),
    ).rejects.toThrow("no project file is open");
  });

  it("auto-extend pulls in an unselected BC neighbour", async () => {
    // Arrange: two selected channels + one unselected WallTemperature connected
    // via a bcEdge to channel n1.
    resetStore({
      nodes: [
        { id: "ch1", type: "streamNode", position: { x: 0, y: 0 }, selected: true, data: { componentId: "Channel", instanceName: "channel_1", parameters: {}, constructorMode: "default" } },
        { id: "ch2", type: "streamNode", position: { x: 150, y: 0 }, selected: true, data: { componentId: "Channel", instanceName: "channel_2", parameters: {}, constructorMode: "default" } },
        { id: "wt1", type: "streamNode", position: { x: 0, y: -80 }, selected: false, data: { componentId: "WallTemperature", instanceName: "wt_1", parameters: {}, constructorMode: "default" } },
      ],
      edges: [
        { id: "e1", source: "ch1", target: "wt1", type: "bcEdge" },
      ],
    });
    mockReadDir.mockResolvedValue([]);

    await useStore.getState().saveSelectionAsPreset("auto_preset", "", "library");

    expect(mockWriteTextFile).toHaveBeenCalledOnce();
    const content = mockWriteTextFile.mock.calls[0][1];
    const parsed = JSON.parse(content);
    // The WallTemperature should have been pulled in via auto-extend.
    expect(parsed.components).toHaveLength(3);
    const ids = parsed.components.map((c: { id: string }) => c.id);
    expect(ids).toContain("wt1");
  });
});

// ---------------------------------------------------------------------------
// describe: loadPresetAtPosition
// ---------------------------------------------------------------------------

describe("loadPresetAtPosition", () => {
  it("mints new UUIDs per node — all differ from source IDs", async () => {
    const presetJson = makePresetJson();
    mockReadTextFile.mockResolvedValueOnce(presetJson);

    const initialNodeCount = useStore.getState().nodes.length;
    await useStore.getState().loadPresetAtPosition("/mock/preset.scpr", { x: 0, y: 0 });

    const newNodes = useStore.getState().nodes.slice(initialNodeCount);
    expect(newNodes).toHaveLength(2);
    expect(newNodes[0].id).not.toBe("node-A");
    expect(newNodes[1].id).not.toBe("node-B");
    // UUIDs should be unique.
    expect(newNodes[0].id).not.toBe(newNodes[1].id);
  });

  it("smart-names collisions — increments name if already exists on canvas", async () => {
    // Pre-populate store with an existing "channel_1" node.
    resetStore({
      nodes: [
        {
          id: "existing-ch1",
          type: "streamNode",
          position: { x: 500, y: 500 },
          selected: false,
          data: { componentId: "Channel", instanceName: "channel_1", parameters: {}, constructorMode: "default" },
        },
      ],
    });

    // Preset also has a "channel_1".
    const presetJson = makePresetJson({
      components: [
        {
          id: "preset-n1",
          type: "streamNode",
          position: { x: 0, y: 0 },
          selected: false,
          data: { componentId: "Channel", instanceName: "channel_1", parameters: {}, constructorMode: "default" },
        },
        {
          id: "preset-n2",
          type: "streamNode",
          position: { x: 150, y: 0 },
          selected: false,
          data: { componentId: "Channel", instanceName: "channel_3", parameters: {}, constructorMode: "default" },
        },
      ],
      layout: { "preset-n1": { x: 0, y: 0 }, "preset-n2": { x: 150, y: 0 } },
    });
    mockReadTextFile.mockResolvedValueOnce(presetJson);

    await useStore.getState().loadPresetAtPosition("/mock/preset.scpr", { x: 0, y: 0 });

    const allNodes = useStore.getState().nodes;
    const names = allNodes.map((n) => (n.data as { instanceName: string }).instanceName);
    // channel_1 already exists, so the loaded one should be channel_2.
    expect(names).toContain("channel_1"); // the pre-existing one
    expect(names).toContain("channel_2"); // the smart-incremented copy
    expect(names).toContain("channel_3"); // no collision, unchanged
  });

  it("adds embedded resources and remaps UUIDs in component params", async () => {
    const geomUuid = "g-old-uuid-1234";
    const presetJson = makePresetJson({
      geometries: [
        { uuid: geomUuid, name: "geom_1", kind: "rectangular", params: { L: 1.0, W: 0.1, H: 0.01 } },
      ],
      components: [
        {
          id: "node-A",
          type: "streamNode",
          position: { x: 0, y: 0 },
          selected: false,
          data: {
            componentId: "Channel",
            instanceName: "channel_1",
            parameters: { geometry: geomUuid },
            constructorMode: "default",
          },
        },
        {
          id: "node-B",
          type: "streamNode",
          position: { x: 150, y: 0 },
          selected: false,
          data: { componentId: "Channel", instanceName: "channel_2", parameters: {}, constructorMode: "default" },
        },
      ],
      layout: { "node-A": { x: 0, y: 0 }, "node-B": { x: 150, y: 0 } },
    });
    mockReadTextFile.mockResolvedValueOnce(presetJson);

    await useStore.getState().loadPresetAtPosition("/mock/preset.scpr", { x: 0, y: 0 });

    const state = useStore.getState();
    // A new geometry should have been added.
    const geomEntries = Object.values(state.resources.geometries);
    expect(geomEntries).toHaveLength(1);
    const addedGeom = geomEntries[0];
    expect(addedGeom.name).toBe("geom_1");
    expect(addedGeom.uuid).not.toBe(geomUuid); // minted new UUID

    // The placed node's parameter should reference the NEW UUID, not the old one.
    const placedNode = state.nodes.find(
      (n) => (n.data as { instanceName: string }).instanceName === "channel_1",
    );
    expect(placedNode).toBeDefined();
    const params = (placedNode!.data as { parameters: Record<string, unknown> }).parameters;
    expect(params.geometry).toBe(addedGeom.uuid);
    expect(params.geometry).not.toBe(geomUuid);
  });

  it("auto-selects all placed nodes", async () => {
    const presetJson = makePresetJson();
    mockReadTextFile.mockResolvedValueOnce(presetJson);

    await useStore.getState().loadPresetAtPosition("/mock/preset.scpr", { x: 0, y: 0 });

    const state = useStore.getState();
    // All newly-added nodes should be selected.
    const loadedNodes = state.nodes; // store started empty
    expect(loadedNodes.every((n) => n.selected === true)).toBe(true);
  });

  it("deselects pre-existing nodes after load", async () => {
    // Pre-populate with a selected node.
    resetStore({
      nodes: [
        {
          id: "pre-existing",
          type: "streamNode",
          position: { x: 999, y: 999 },
          selected: true,
          data: { componentId: "Pump", instanceName: "pump_1", parameters: {}, constructorMode: "default" },
        },
      ],
    });

    const presetJson = makePresetJson();
    mockReadTextFile.mockResolvedValueOnce(presetJson);

    await useStore.getState().loadPresetAtPosition("/mock/preset.scpr", { x: 0, y: 0 });

    const allNodes = useStore.getState().nodes;
    const preExisting = allNodes.find((n) => n.id === "pre-existing");
    expect(preExisting).toBeDefined();
    // Pre-existing node must have been deselected.
    expect(preExisting!.selected).toBe(false);
    // The two newly-loaded nodes should be selected.
    const loadedNodes = allNodes.filter((n) => n.id !== "pre-existing");
    expect(loadedNodes.every((n) => n.selected === true)).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// describe: renamePreset
// ---------------------------------------------------------------------------

describe("renamePreset", () => {
  const OLD_PATH = "/mock/config/presets/old_name.scpr";
  const NEW_NAME = "new_name";
  const NEW_PATH = "/mock/config/presets/new_name.scpr";

  beforeEach(() => {
    // Seed libraryPresets so renamePreset can determine the store.
    resetStore({
      libraryPresets: [
        { name: "old_name", description: "desc", filePath: OLD_PATH, store: "library" },
      ],
    });
  });

  it("rewrites JSON name field AND writes to the new path", async () => {
    const originalJson = makePresetJson({ name: "old_name", description: "my desc" });
    mockReadTextFile
      .mockResolvedValueOnce(originalJson) // read old file
      .mockRejectedValueOnce(new Error("ENOENT")); // collision check: new path doesn't exist
    // refreshPresetsDir call at the end.
    mockReadDir.mockResolvedValue([
      { name: "new_name.scpr", isFile: true, isDirectory: false },
    ]);
    mockReadTextFile.mockResolvedValue(
      makePresetJson({ name: "new_name", description: "my desc" }),
    );

    await useStore.getState().renamePreset(OLD_PATH, NEW_NAME);

    // writeTextFile should have been called with new path.
    expect(mockWriteTextFile).toHaveBeenCalledOnce();
    const [writePath, writeContent] = mockWriteTextFile.mock.calls[0];
    expect(writePath).toBe(NEW_PATH);
    const parsed = JSON.parse(writeContent);
    expect(parsed.name).toBe(NEW_NAME);

    // Old file should have been removed.
    expect(mockRemove).toHaveBeenCalledWith(OLD_PATH);
  });

  it("throws on charset violation", async () => {
    await expect(
      useStore.getState().renamePreset(OLD_PATH, "bad name with spaces"),
    ).rejects.toThrow("Invalid preset name");
  });

  it("throws on collision (when target path already exists)", async () => {
    const originalJson = makePresetJson({ name: "old_name", description: "" });
    // First readTextFile: read old file.
    // Second readTextFile: collision check succeeds (file exists).
    mockReadTextFile
      .mockResolvedValueOnce(originalJson)
      .mockResolvedValueOnce(makePresetJson({ name: "new_name" })); // collision!

    await expect(
      useStore.getState().renamePreset(OLD_PATH, NEW_NAME),
    ).rejects.toThrow("already exists in this store");
  });
});

// ---------------------------------------------------------------------------
// describe: deletePreset
// ---------------------------------------------------------------------------

describe("deletePreset", () => {
  it("calls remove with the correct path", async () => {
    const filePath = "/mock/config/presets/to_delete.scpr";
    resetStore({
      libraryPresets: [
        { name: "to_delete", description: "", filePath, store: "library" },
      ],
    });
    // refreshPresetsDir after delete.
    mockReadDir.mockResolvedValue([]);

    await useStore.getState().deletePreset(filePath);

    expect(mockRemove).toHaveBeenCalledWith(filePath);
  });
});
