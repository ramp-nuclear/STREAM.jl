/**
 * Phase 71 Plan 12 — exportCode test rewrite for D-17 synchronous gate.
 *
 * Behavior asserted here:
 *
 *  1. Empty nodes → returns false, `save` NOT called.
 *  2. runValidators returns error results → returns false, toast.error fired,
 *     store updated with bottomPanelOpen + activeBottomTab='validation',
 *     `save` NOT called.
 *  3. User cancel: `save` returns null → returns false, `writeTextFile`
 *     NOT called.
 *  4. Happy path: `save` returns a path, `writeTextFile` resolves →
 *     returns true. `writeTextFile` called with that path and a string
 *     containing the canonical D-12 `# === <Section> ===` headers.
 *  5. Write throws: `writeTextFile` rejects → `exportCode` rejects
 *     (does not silently swallow).
 *
 * Tauri plugins, the store, and the validation runner are mocked so the
 * test does not hit the filesystem nor require a Tauri runtime.
 */

import { describe, it, expect, vi, beforeEach } from "vitest";
import type { Node } from "@xyflow/react";
import type { CodeSection } from "../codeGenerator";
import type { ValidationResult } from "../validation/types";

// --- Mocks ------------------------------------------------------------------

vi.mock("@tauri-apps/plugin-dialog", () => ({
  save: vi.fn(),
}));

vi.mock("@tauri-apps/plugin-fs", () => ({
  writeTextFile: vi.fn(),
}));

// Mock sonner toast so we can assert on toast.error calls.
vi.mock("../../components/ui/sonner", () => ({
  toast: { error: vi.fn() },
}));

// Mock buildValidationSnapshot — returns a trivial snapshot object.
vi.mock("../validation/snapshot", () => ({
  buildValidationSnapshot: vi.fn(() => ({})),
}));

// Mock runValidators — default returns empty (no errors); overridden per test.
vi.mock("../validation/runner", () => ({
  runValidators: vi.fn(() => []),
}));

// Mock the store. setState is a plain vi.fn(); getState returns minimal fields.
vi.mock("../../store/useStore", () => ({
  __esModule: true,
  default: {
    getState: vi.fn(() => ({
      nodes: [
        {
          id: "pump1-uuid",
          type: "stream",
          position: { x: 0, y: 0 },
          data: {},
        },
      ],
      edges: [],
      anchors: {},
      bcMode: {},
      resources: {},
    })),
    setState: vi.fn(),
  },
}));

// Lazy imports after mocks are installed.
import { save } from "@tauri-apps/plugin-dialog";
import { writeTextFile } from "@tauri-apps/plugin-fs";
import { runValidators } from "../validation/runner";
import { toast } from "../../components/ui/sonner";
import useStore from "../../store/useStore";
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

function makeErrorResult(): ValidationResult {
  return {
    id: "test-err-1",
    validatorId: "danglingFlowPort",
    severity: "error",
    description: "pump1.port_out unconnected",
    targets: [{ kind: "node", nodeId: "pump1-uuid" }],
  };
}

// --- Tests ------------------------------------------------------------------

beforeEach(() => {
  vi.mocked(save).mockReset();
  vi.mocked(writeTextFile).mockReset();
  vi.mocked(runValidators).mockReset();
  vi.mocked(runValidators).mockReturnValue([]);
  vi.mocked(useStore.setState).mockReset();
  vi.mocked(toast.error).mockReset();
});

describe("exportCode — validation gate", () => {
  it("returns false and does NOT call save() when nodes array is empty", async () => {
    const result = await exportCode({ sections: makeSections(), nodes: [] });
    expect(result).toBe(false);
    expect(vi.mocked(save)).not.toHaveBeenCalled();
    expect(vi.mocked(writeTextFile)).not.toHaveBeenCalled();
  });

  it("returns false and does NOT call save() when runValidators returns errors", async () => {
    vi.mocked(runValidators).mockReturnValue([makeErrorResult()]);

    const result = await exportCode({
      sections: makeSections(),
      nodes: makeNodes(),
    });
    expect(result).toBe(false);
    expect(vi.mocked(save)).not.toHaveBeenCalled();
    expect(vi.mocked(writeTextFile)).not.toHaveBeenCalled();
  });

  it("fires toast.error with error count when runValidators returns errors", async () => {
    vi.mocked(runValidators).mockReturnValue([makeErrorResult()]);

    await exportCode({ sections: makeSections(), nodes: makeNodes() });

    expect(vi.mocked(toast.error)).toHaveBeenCalledTimes(1);
    const [msg] = vi.mocked(toast.error).mock.calls[0];
    expect(msg).toContain("Export blocked: 1 validation error");
  });

  it("sets bottomPanelOpen=true and activeBottomTab='validation' on error", async () => {
    vi.mocked(runValidators).mockReturnValue([makeErrorResult()]);

    await exportCode({ sections: makeSections(), nodes: makeNodes() });

    expect(vi.mocked(useStore.setState)).toHaveBeenCalledWith(
      expect.objectContaining({
        bottomPanelOpen: true,
        activeBottomTab: "validation",
      }),
    );
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
