/**
 * Phase 65 Plan 08 Task 1 (TDD RED) — AutoRecover store actions tests
 *
 * Tests recoverFromSidecar and discardAllSidecars store actions.
 */

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import useStore from "../useStore";

// ---------------------------------------------------------------------------
// Mock @/lib/autoRecover for store action tests
// ---------------------------------------------------------------------------

const mockReadSidecar = vi.fn<(basename: string) => Promise<string | null>>();
const mockClearSidecar = vi.fn<(basename: string) => Promise<void>>();
const mockClearLockfile = vi.fn<() => Promise<void>>();
const mockEnumerateSidecars = vi.fn<() => Promise<string[]>>();

vi.mock("@/lib/autoRecover", () => ({
  readSidecar: (basename: string) => mockReadSidecar(basename),
  clearSidecar: (basename: string) => mockClearSidecar(basename),
  clearLockfile: () => mockClearLockfile(),
  enumerateSidecars: () => mockEnumerateSidecars(),
  // Re-export any other needed exports with pass-through behavior
  getSidecarBasename: vi.fn().mockReturnValue("mock.scp.autosave"),
  writeSidecar: vi.fn().mockResolvedValue(undefined),
  writeLockfile: vi.fn().mockResolvedValue(undefined),
  createDebouncedSidecarWriter: vi.fn().mockReturnValue({
    schedule: vi.fn(),
    cancel: vi.fn(),
    flush: vi.fn().mockResolvedValue(undefined),
  }),
}));

// ---------------------------------------------------------------------------
// Mock @tauri-apps/api/core (for get_pid invoke in initAutoRecover)
// ---------------------------------------------------------------------------

vi.mock("@tauri-apps/api/core", () => ({
  invoke: vi.fn().mockResolvedValue(12345),
}));

// ---------------------------------------------------------------------------
// Valid .scp project fixture
// ---------------------------------------------------------------------------

const VALID_PROJECT_JSON = JSON.stringify({
  format_version: "2.0",
  model_options: {
    name: "TestProject",
    description: "",
    default_fluid: "water",
    g_default: 9.80665,
    solver: { abstol: 1e-8, reltol: 1e-6, dtmax: null },
  },
  resources: {
    geometries: [],
    power_shapes: [],
    fluids: [],
  },
  components: [
    {
      id: "pump_1",
      type: "streamNode",
      position: { x: 100, y: 200 },
      data: {
        componentId: "Pump",
        instanceName: "pump_1",
        parameters: {},
        constructorMode: "default",
      },
    },
  ],
  connections: [],
  anchors: {},
  layout: {
    active_left_tab: "Components",
    active_layer: "Both",
    snap_to_grid: false,
  },
});

// ---------------------------------------------------------------------------
// Reset store state before each test
// ---------------------------------------------------------------------------

beforeEach(() => {
  mockReadSidecar.mockReset();
  mockClearSidecar.mockReset().mockResolvedValue(undefined);
  mockClearLockfile.mockReset().mockResolvedValue(undefined);
  mockEnumerateSidecars.mockReset();

  useStore.setState({
    nodes: [],
    edges: [],
    anchors: {},
    isDirty: false,
    currentFilePath: "some/existing/path.scp",
  });
});

afterEach(() => {
  vi.clearAllMocks();
});

describe("recoverFromSidecar (Phase 65 Plan 08)", () => {
  it("populates nodes from a valid sidecar + sets isDirty=true + currentFilePath=null", async () => {
    mockReadSidecar.mockResolvedValue(VALID_PROJECT_JSON);

    await useStore.getState().recoverFromSidecar("foo.scp.autosave");

    const state = useStore.getState();
    // Nodes should be hydrated from the sidecar
    expect(state.nodes.length).toBe(1);
    expect(state.nodes[0].id).toBe("pump_1");
    // Must be dirty after recovery (D-04 in-memory-unsaved)
    expect(state.isDirty).toBe(true);
    // currentFilePath must be null (D-04 Save-As gate)
    expect(state.currentFilePath).toBeNull();
    // Sidecar and lockfile cleared on success
    expect(mockClearSidecar).toHaveBeenCalledWith("foo.scp.autosave");
    expect(mockClearLockfile).toHaveBeenCalledOnce();
  });

  it("silent failure: readSidecar returns null — store stays unchanged + sidecar cleared", async () => {
    const initialNodes = useStore.getState().nodes;
    mockReadSidecar.mockResolvedValue(null);

    await useStore.getState().recoverFromSidecar("corrupt.scp.autosave");

    const state = useStore.getState();
    // Store should remain in its current state (not reset to new project)
    expect(state.nodes).toEqual(initialNodes);
    // Corrupted sidecar should still be cleared (no boot loop)
    expect(mockClearSidecar).toHaveBeenCalledWith("corrupt.scp.autosave");
    expect(mockClearLockfile).toHaveBeenCalledOnce();
  });

  it("silent failure: malformed sidecar JSON — store unchanged + sidecar cleared", async () => {
    const initialNodes = useStore.getState().nodes;
    mockReadSidecar.mockResolvedValue("not valid json at all {{{{");

    await useStore.getState().recoverFromSidecar("malformed.scp.autosave");

    const state = useStore.getState();
    expect(state.nodes).toEqual(initialNodes);
    // Corrupted sidecar must be removed (prevent repeated boot-loop failure)
    expect(mockClearSidecar).toHaveBeenCalledWith("malformed.scp.autosave");
    expect(mockClearLockfile).toHaveBeenCalledOnce();
  });
});

describe("discardAllSidecars (Phase 65 Plan 08)", () => {
  it("enumerates, clears each sidecar, and clears the lockfile", async () => {
    mockEnumerateSidecars.mockResolvedValue([
      "a.scp.autosave",
      "b.scp.autosave",
    ]);

    await useStore.getState().discardAllSidecars();

    expect(mockClearSidecar).toHaveBeenCalledWith("a.scp.autosave");
    expect(mockClearSidecar).toHaveBeenCalledWith("b.scp.autosave");
    expect(mockClearSidecar).toHaveBeenCalledTimes(2);
    expect(mockClearLockfile).toHaveBeenCalledOnce();
  });

  it("works with empty sidecar list", async () => {
    mockEnumerateSidecars.mockResolvedValue([]);

    await useStore.getState().discardAllSidecars();

    expect(mockClearSidecar).not.toHaveBeenCalled();
    expect(mockClearLockfile).toHaveBeenCalledOnce();
  });
});
