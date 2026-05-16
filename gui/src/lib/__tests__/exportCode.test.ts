/**
 * Phase 66 Plan 03 Task 3 — exportCode shared util.
 *
 * Encapsulates the validation gate + Tauri save dialog + writeTextFile path
 * that Toolbar.tsx (this plan) and BottomPanel.tsx (Plan 04) both drive.
 *
 * Behavior asserted here:
 *
 *  1. Validation gate: empty nodes → returns false, `save` NOT called.
 *  2. User cancel: `save` returns null → returns false, `writeTextFile`
 *     NOT called.
 *  3. Happy path: `save` returns a path, `writeTextFile` resolves →
 *     returns true. `writeTextFile` called with that path and a string
 *     containing the canonical D-12 `# === <Section> ===` headers.
 *  4. Write throws: `writeTextFile` rejects → `exportCode` rejects
 *     (does not silently swallow — the caller's existing .catch path
 *     keeps surfacing the error, matching Toolbar's current behavior).
 *
 * Tauri plugins are mocked so the test does not hit the filesystem nor
 * require a Tauri runtime.
 */

import { describe, it, expect, vi, beforeEach } from "vitest";
import type { Node } from "@xyflow/react";
import type { CodeSection } from "../codeGenerator";
import type { TopologyResult } from "../validation";

// --- Mocks ------------------------------------------------------------------

vi.mock("@tauri-apps/plugin-dialog", () => ({
  save: vi.fn(),
}));

vi.mock("@tauri-apps/plugin-fs", () => ({
  writeTextFile: vi.fn(),
}));

// Mock the validation gate by hooking useStore.getState().validateAndGate.
// We mutate the module-shared `vi.fn()` per test so each case controls the
// gate's response without re-importing the store.
const validateAndGateMock = vi.fn<() => TopologyResult>(() => ({
  valid: true,
  nodeErrors: [],
  systemErrors: [],
}));

vi.mock("../../store/useStore", () => ({
  __esModule: true,
  default: {
    getState: () => ({
      validateAndGate: validateAndGateMock,
    }),
  },
}));

// Lazy imports after mocks are installed.
import { save } from "@tauri-apps/plugin-dialog";
import { writeTextFile } from "@tauri-apps/plugin-fs";
import { exportCode } from "../exportCode";

// --- Fixtures ---------------------------------------------------------------

function makeSections(): CodeSection[] {
  return [
    {
      name: "Imports",
      subBlocks: [
        { kind: "import", lines: ["using STREAM"], sourceIds: [] },
      ],
    },
    {
      name: "Components",
      subBlocks: [
        {
          kind: "component",
          lines: ["@named pump1 = Pump(dP=1.0)"],
          sourceIds: ["pump1-uuid"],
        },
      ],
    },
  ];
}

function makeNodes(): Node[] {
  return [
    {
      id: "pump1-uuid",
      type: "stream",
      position: { x: 0, y: 0 },
      data: {},
    } as Node,
  ];
}

// --- Tests ------------------------------------------------------------------

beforeEach(() => {
  vi.mocked(save).mockReset();
  vi.mocked(writeTextFile).mockReset();
  validateAndGateMock.mockReset();
  validateAndGateMock.mockReturnValue({
    valid: true,
    nodeErrors: [],
    systemErrors: [],
  });
});

describe("exportCode — validation gate", () => {
  it("returns false and does NOT call save() when nodes array is empty", async () => {
    const result = await exportCode({ sections: makeSections(), nodes: [] });
    expect(result).toBe(false);
    expect(vi.mocked(save)).not.toHaveBeenCalled();
    expect(vi.mocked(writeTextFile)).not.toHaveBeenCalled();
  });

  it("returns false and does NOT call save() when validateAndGate reports invalid", async () => {
    validateAndGateMock.mockReturnValue({
      valid: false,
      nodeErrors: [
        { nodeId: "n1", instanceName: "pump1", portName: "port_in" },
      ],
      systemErrors: [],
    });

    const result = await exportCode({
      sections: makeSections(),
      nodes: makeNodes(),
    });
    expect(result).toBe(false);
    expect(vi.mocked(save)).not.toHaveBeenCalled();
    expect(vi.mocked(writeTextFile)).not.toHaveBeenCalled();
  });
});

describe("exportCode — user cancellation", () => {
  it("returns false when save() returns null (user dismissed dialog)", async () => {
    vi.mocked(save).mockResolvedValue(null);
    const result = await exportCode({
      sections: makeSections(),
      nodes: makeNodes(),
    });
    expect(result).toBe(false);
    expect(vi.mocked(save)).toHaveBeenCalledTimes(1);
    expect(vi.mocked(writeTextFile)).not.toHaveBeenCalled();
  });
});

describe("exportCode — happy path", () => {
  it("returns true and writes the serialized sections to the chosen path", async () => {
    vi.mocked(save).mockResolvedValue("/tmp/out.jl");
    vi.mocked(writeTextFile).mockResolvedValue(undefined);

    const result = await exportCode({
      sections: makeSections(),
      nodes: makeNodes(),
    });

    expect(result).toBe(true);
    expect(vi.mocked(save)).toHaveBeenCalledWith({
      defaultPath: "system.jl",
      filters: [{ name: "Julia files", extensions: ["jl"] }],
    });
    expect(vi.mocked(writeTextFile)).toHaveBeenCalledTimes(1);
    const [path, body] = vi.mocked(writeTextFile).mock.calls[0];
    expect(path).toBe("/tmp/out.jl");
    expect(body).toContain("# === Imports ===");
    expect(body).toContain("# === Components ===");
    expect(body).toContain("using STREAM");
    expect(body).toContain("@named pump1 = Pump(dP=1.0)");
  });
});

describe("exportCode — write failure surfaces", () => {
  it("propagates the writeTextFile error (does not swallow)", async () => {
    vi.mocked(save).mockResolvedValue("/tmp/out.jl");
    vi.mocked(writeTextFile).mockRejectedValue(new Error("disk full"));

    await expect(
      exportCode({ sections: makeSections(), nodes: makeNodes() }),
    ).rejects.toThrow("disk full");
  });
});
