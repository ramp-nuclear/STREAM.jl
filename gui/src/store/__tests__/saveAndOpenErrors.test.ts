// saveAndOpenErrors.test.ts
// -----------------------------------------------------------------------------
// Phase 62-15 (VERIFICATION.md Critical Gap #4 — engineering-tool voice).
//
// Pins the rewritten error-dialog copy emitted by:
//   - saveProject     (catch branch — writeTextFile rejects)
//   - saveProjectAs   (catch branch — writeTextFile rejects)
//   - loadProject     (catch branch — open() rejects)
//   - loadProjectFromPath (catch branch — readTextFile rejects)
//   - loadProjectFromPath (missing-file path — single + plural variants
//     and the dialog title)
//
// The substitutions are intentionally exact-literal so a future LLM-driven
// re-flow can't silently revert them. See 62-15-COPY-AUDIT.md rows 16, 17,
// 18, 19.

import { vi, describe, it, expect, beforeEach } from "vitest";

// ---------------------------------------------------------------------------
// Tauri plugin mocks — must be declared BEFORE importing useStore so that
// the dynamic `await import("@tauri-apps/plugin-dialog")` inside the
// actions sees the mock.
// ---------------------------------------------------------------------------

const saveMock = vi.fn();
const openMock = vi.fn();
const messageMock = vi.fn();
const writeTextFileMock = vi.fn();
const readTextFileMock = vi.fn();
const mkdirMock = vi.fn();
const dirnameMock = vi.fn();
const joinMock = vi.fn();
const appDataDirMock = vi.fn();
const existsMock = vi.fn();

vi.mock("@tauri-apps/plugin-dialog", () => ({
  save: saveMock,
  open: openMock,
  message: messageMock,
}));

vi.mock("@tauri-apps/plugin-fs", () => ({
  writeTextFile: writeTextFileMock,
  readTextFile: readTextFileMock,
  mkdir: mkdirMock,
  exists: existsMock,
}));

vi.mock("@tauri-apps/api/path", () => ({
  dirname: dirnameMock,
  join: joinMock,
  appDataDir: appDataDirMock,
}));

import useStore, {
  SENTINEL_UNSET_POWER_SHAPE,
  SENTINEL_LIGHT_WATER_FLUID,
} from "../useStore";

function resetStore() {
  useStore.setState({
    nodes: [],
    edges: [],
    anchors: {},
    selectedNodeId: null,
    selectedResourceId: null,
    selectedResourceKind: null,
    selectionKind: "none",
    isDirty: false,
    currentFilePath: null,
    recentFiles: [],
    missingFilePowerShapes: [],
    activeLeftTab: "Components",
    // Phase 68: 4-layer fixture (replaces v0.8 `activeLayer: "Both"`).
    activeLayers: { Hydraulic: true, Thermal: true, Sources: true, ReactorPhysics: true },
    hideOffLayer: false,
    errorNodeIds: new Set<string>(),
    validationResult: null,
    // Stub the validation gate so saveProject / saveProjectAs reach the
    // write step regardless of canvas content.
    validateAndGate: () => ({ valid: true, nodeErrors: [], systemErrors: [] }),
    modelOptions: {
      name: "demo",
      description: "",
      default_fluid: "water",
      g_default: 9.80665,
      solver: { abstol: 1e-8, reltol: 1e-6, dtmax: null },
    },
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
  });
}

beforeEach(() => {
  resetStore();
  saveMock.mockReset();
  openMock.mockReset();
  messageMock.mockReset();
  messageMock.mockResolvedValue(undefined);
  writeTextFileMock.mockReset();
  readTextFileMock.mockReset();
  mkdirMock.mockReset();
  mkdirMock.mockResolvedValue(undefined);
  dirnameMock.mockReset();
  dirnameMock.mockResolvedValue("/tmp");
  joinMock.mockReset();
  joinMock.mockImplementation(async (...parts: string[]) => parts.join("/"));
  appDataDirMock.mockReset();
  appDataDirMock.mockResolvedValue("/tmp");
  existsMock.mockReset();
  existsMock.mockResolvedValue(true);
});

describe("Save error dialog copy (62-15 — VERIFICATION Gap #4)", () => {
  it("saveProjectAs: shows 'Save failed. Check the file is writable and there is disk space.' when writeTextFile rejects", async () => {
    saveMock.mockResolvedValueOnce("/tmp/myproj.scp");
    writeTextFileMock.mockRejectedValueOnce(new Error("EACCES"));

    await useStore.getState().saveProjectAs();

    // The catch branch dispatches a message dialog with the new copy.
    expect(messageMock).toHaveBeenCalled();
    const arg0 = messageMock.mock.calls[0][0];
    expect(arg0).toBe(
      "Save failed. Check the file is writable and there is disk space.",
    );
  });

  it("saveProject (existing path): shows the same 'Save failed.' copy when writeTextFile rejects", async () => {
    // Pre-seed currentFilePath so saveProject takes the direct-write branch
    // rather than delegating to saveProjectAs.
    useStore.setState({ currentFilePath: "/tmp/existing.scp" });
    writeTextFileMock.mockRejectedValueOnce(new Error("ENOSPC"));

    await useStore.getState().saveProject();

    expect(messageMock).toHaveBeenCalled();
    const arg0 = messageMock.mock.calls[0][0];
    expect(arg0).toBe(
      "Save failed. Check the file is writable and there is disk space.",
    );
  });
});

describe("Open error dialog copy (62-15 — VERIFICATION Gap #4)", () => {
  it("loadProject: shows 'Open failed. The file may be missing, corrupted, or not a valid .scp file.' when open() rejects", async () => {
    openMock.mockRejectedValueOnce(new Error("dialog cancelled with error"));

    await useStore.getState().loadProject();

    expect(messageMock).toHaveBeenCalled();
    const arg0 = messageMock.mock.calls[0][0];
    expect(arg0).toBe(
      "Open failed. The file may be missing, corrupted, or not a valid .scp file.",
    );
  });

  it("loadProjectFromPath: shows the same 'Open failed.' copy when readTextFile rejects", async () => {
    readTextFileMock.mockRejectedValueOnce(new Error("ENOENT"));

    await useStore.getState().loadProjectFromPath("/tmp/bogus.scp");

    expect(messageMock).toHaveBeenCalled();
    const arg0 = messageMock.mock.calls[0][0];
    expect(arg0).toBe(
      "Open failed. The file may be missing, corrupted, or not a valid .scp file.",
    );
  });
});

describe("Missing power-shape dialog copy (62-15 — VERIFICATION Gap #4)", () => {
  // The missing-file dialog branch lives inside loadProjectFromPath after
  // the file existence check. We force `exists` to return false to trip
  // the branch, then assert title + body copy.
  it("singular: '1 power-shape file not found: ... Open the Resources tab to relocate.'", async () => {
    // Seed a single file_loaded power shape so the existence check fires.
    useStore.setState({
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
    });
    // Provide a serialized project body with one file_loaded power shape.
    const fakeProject = JSON.stringify({
      format_version: "2.0",
      components: [],
      connections: [],
      anchors: {},
      resources: {
        geometries: [],
        power_shapes: [
          {
            uuid: "ps-missing-1",
            name: "psA",
            kind: "file_loaded",
            params: { path: "missing.csv" },
          },
        ],
        fluids: [],
      },
      model_options: {
        name: "demo",
        description: "",
        default_fluid: "water",
        g_default: 9.80665,
        solver: { abstol: 1e-8, reltol: 1e-6, dtmax: null },
      },
      layout: { active_left_tab: "Components", active_layer: "Both" },
    });
    readTextFileMock.mockResolvedValueOnce(fakeProject);
    existsMock.mockResolvedValueOnce(false); // file does NOT exist on disk

    await useStore.getState().loadProjectFromPath("/tmp/demo.scp");

    // The first message call is the missing-file warning.
    const calls = messageMock.mock.calls;
    expect(calls.length).toBeGreaterThanOrEqual(1);
    const body = calls[0][0] as string;
    const opts = calls[0][1] as { title: string; kind: string };

    // Body shape: "1 power-shape file not found: <path>. Open the
    // Resources tab to relocate."
    expect(body).toMatch(/^1 power-shape file not found:/);
    expect(body).toContain("Open the Resources tab to relocate.");
    expect(opts.title).toBe("Missing power-shape file");
    expect(opts.kind).toBe("warning");
  });

  it("plural: 'N power-shape file(s) not found. Open the Resources tab to relocate.'", async () => {
    const fakeProject = JSON.stringify({
      format_version: "2.0",
      components: [],
      connections: [],
      anchors: {},
      resources: {
        geometries: [],
        power_shapes: [
          {
            uuid: "ps-missing-1",
            name: "psA",
            kind: "file_loaded",
            params: { path: "missingA.csv" },
          },
          {
            uuid: "ps-missing-2",
            name: "psB",
            kind: "file_loaded",
            params: { path: "missingB.csv" },
          },
        ],
        fluids: [],
      },
      model_options: {
        name: "demo",
        description: "",
        default_fluid: "water",
        g_default: 9.80665,
        solver: { abstol: 1e-8, reltol: 1e-6, dtmax: null },
      },
      layout: { active_left_tab: "Components", active_layer: "Both" },
    });
    readTextFileMock.mockResolvedValueOnce(fakeProject);
    existsMock.mockResolvedValue(false); // both files missing

    await useStore.getState().loadProjectFromPath("/tmp/demo.scp");

    const calls = messageMock.mock.calls;
    expect(calls.length).toBeGreaterThanOrEqual(1);
    const body = calls[0][0] as string;
    const opts = calls[0][1] as { title: string; kind: string };

    expect(body).toBe(
      "2 power-shape file(s) not found. Open the Resources tab to relocate.",
    );
    expect(opts.title).toBe("Missing power-shape file");
  });
});
