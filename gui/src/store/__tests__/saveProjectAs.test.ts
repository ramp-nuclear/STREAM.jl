// saveProjectAs.test.ts
// -----------------------------------------------------------------------------
// Phase 62-14 — Closes VERIFICATION.md Critical Gap #3.
//
// Covers two things:
//   1. The pure module-level helper `computeSaveAsDefaultFilename(name)`
//      (sanitization rules: trim → strip illegal chars → collapse internal
//      whitespace → trim → empty-fallback → no-double-extension).
//   2. The store action `saveProjectAs` plumbs that helper's output through
//      the Tauri `save()` dialog's `defaultPath` argument, instead of the
//      pre-62-14 literal `project.scp` hardcode.
//
// Reference mock shape: gui/src/lib/__tests__/projectIO.scp.test.ts.

import { vi, describe, it, expect, beforeEach } from "vitest";

// ---------------------------------------------------------------------------
// Tauri plugin mocks — must be declared BEFORE importing useStore so that the
// dynamic `await import("@tauri-apps/plugin-dialog")` inside the action sees
// the mock.
// ---------------------------------------------------------------------------

const saveMock = vi.fn();
const messageMock = vi.fn();
const writeTextFileMock = vi.fn();
const readTextFileMock = vi.fn();
const mkdirMock = vi.fn();
const dirnameMock = vi.fn();
const joinMock = vi.fn();
const appDataDirMock = vi.fn();

vi.mock("@tauri-apps/plugin-dialog", () => ({
  save: saveMock,
  message: messageMock,
  open: vi.fn(),
}));

vi.mock("@tauri-apps/plugin-fs", () => ({
  writeTextFile: writeTextFileMock,
  readTextFile: readTextFileMock,
  mkdir: mkdirMock,
  exists: vi.fn().mockResolvedValue(true),
}));

vi.mock("@tauri-apps/api/path", () => ({
  dirname: dirnameMock,
  join: joinMock,
  appDataDir: appDataDirMock,
}));

import useStore, {
  computeSaveAsDefaultFilename,
  SENTINEL_UNSET_POWER_SHAPE,
  SENTINEL_LIGHT_WATER_FLUID,
} from "../useStore";

// ---------------------------------------------------------------------------
// Pure helper unit tests — no store, no Tauri mocks needed.
// ---------------------------------------------------------------------------

describe("computeSaveAsDefaultFilename", () => {
  it("returns 'project.scp' for an empty string", () => {
    expect(computeSaveAsDefaultFilename("")).toBe("project.scp");
  });

  it("returns 'project.scp' for an all-whitespace string", () => {
    expect(computeSaveAsDefaultFilename("   ")).toBe("project.scp");
  });

  it("appends '.scp' to a plain alphanumeric name", () => {
    expect(computeSaveAsDefaultFilename("phase62-smoke")).toBe(
      "phase62-smoke.scp",
    );
  });

  it("does NOT double-append '.scp' (lowercase)", () => {
    expect(computeSaveAsDefaultFilename("phase62-smoke.scp")).toBe(
      "phase62-smoke.scp",
    );
  });

  it("does NOT double-append '.scp' (case-insensitive, preserves original case)", () => {
    expect(computeSaveAsDefaultFilename("PHASE62.SCP")).toBe("PHASE62.SCP");
  });

  it("strips OS-illegal characters", () => {
    expect(computeSaveAsDefaultFilename("my/bad:name?")).toBe("mybadname.scp");
  });

  it("falls back to 'project.scp' when sanitization leaves an empty string", () => {
    expect(computeSaveAsDefaultFilename('/:*?"<>|')).toBe("project.scp");
  });

  it("trims surrounding whitespace before extension append", () => {
    expect(computeSaveAsDefaultFilename("  trim me  ")).toBe("trim me.scp");
  });

  it("strips control characters", () => {
    expect(computeSaveAsDefaultFilename("a\x00b\x1fc")).toBe("abc.scp");
  });

  it("collapses runs of internal whitespace to a single space", () => {
    expect(computeSaveAsDefaultFilename("multi   space")).toBe(
      "multi space.scp",
    );
  });

  it("passes filename-legal unicode characters through unchanged", () => {
    expect(computeSaveAsDefaultFilename("unicode-café")).toBe(
      "unicode-café.scp",
    );
  });
});

// ---------------------------------------------------------------------------
// Integration tests — saveProjectAs dialog defaultPath plumbing
// ---------------------------------------------------------------------------

function resetStore(name: string = "") {
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
    activeLayer: "Both",
    errorNodeIds: new Set<string>(),
    // Phase 71 D-16: validateAndGate removed; saveProjectAs no longer has a validation gate.
    modelOptions: {
      name,
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
          name: "(leave unset; set in code)",
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

describe("saveProjectAs Tauri dialog defaultPath", () => {
  beforeEach(() => {
    saveMock.mockReset();
    saveMock.mockResolvedValue(null); // default: user cancels the picker
    writeTextFileMock.mockReset();
    writeTextFileMock.mockResolvedValue(undefined);
    messageMock.mockReset();
    readTextFileMock.mockReset();
    mkdirMock.mockReset();
    mkdirMock.mockResolvedValue(undefined);
    dirnameMock.mockReset();
    dirnameMock.mockResolvedValue("/tmp");
    joinMock.mockReset();
    joinMock.mockImplementation(async (...parts: string[]) => parts.join("/"));
    appDataDirMock.mockReset();
    appDataDirMock.mockResolvedValue("/tmp");
  });

  it("derives defaultPath from modelOptions.name (happy path)", async () => {
    resetStore("phase62-smoke");
    await useStore.getState().saveProjectAs();

    expect(saveMock).toHaveBeenCalledTimes(1);
    const arg = saveMock.mock.calls[0][0];
    expect(arg.defaultPath).toBe("phase62-smoke.scp");
    expect(arg.filters[0].extensions[0]).toBe("scp");
  });

  it("falls back to 'project.scp' when modelOptions.name is empty", async () => {
    resetStore("");
    await useStore.getState().saveProjectAs();

    expect(saveMock).toHaveBeenCalledTimes(1);
    expect(saveMock.mock.calls[0][0].defaultPath).toBe("project.scp");
  });

  it("leaves currentFilePath unchanged when the user cancels", async () => {
    resetStore("anything");
    // saveMock already resolves to null in beforeEach.
    await useStore.getState().saveProjectAs();

    expect(useStore.getState().currentFilePath).toBeNull();
    expect(writeTextFileMock).not.toHaveBeenCalled();
  });

  it("successful save writes the file with derived name and updates store state", async () => {
    resetStore("myproj");
    saveMock.mockResolvedValueOnce("/tmp/myproj.scp");

    await useStore.getState().saveProjectAs();

    // Dialog was called with the derived defaultPath.
    expect(saveMock.mock.calls[0][0].defaultPath).toBe("myproj.scp");

    // writeTextFile was called with the path the user picked + valid JSON.
    // (saveRecentFiles also writes a recent.json — accept either ordering;
    // find the call whose first arg is the .scp path we picked.)
    const scpCall = writeTextFileMock.mock.calls.find(
      (call) => call[0] === "/tmp/myproj.scp",
    );
    expect(scpCall).toBeDefined();
    const parsed = JSON.parse(scpCall![1] as string);
    expect(parsed.format_version).toBe("2.0");

    // Existing post-save semantics preserved.
    const state = useStore.getState();
    expect(state.currentFilePath).toBe("/tmp/myproj.scp");
    expect(state.isDirty).toBe(false);
  });
});
