// @vitest-environment happy-dom
//
// Phase 62 Plan 62-08 Task 3 — PowerShapeResourceEditor unit tests.
// Covers D-19 (smart-name-increment), D-22 (kind selector excludes unset),
// D-23 (CSV-only Tauri filter), and the kind-conditional fields.

import { describe, it, expect, beforeEach, vi } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import PowerShapeResourceEditor from "../PowerShapeResourceEditor";
import useStore, {
  SENTINEL_UNSET_POWER_SHAPE,
  SENTINEL_LIGHT_WATER_FLUID,
} from "../../../store/useStore";
import { TooltipProvider } from "../../ui/tooltip";

// Mock the Tauri dialog + fs modules so the Browse button can be exercised
// in happy-dom. The dialog mock records its filter argument so we can
// assert the CSV-only D-23 contract.
const openMock = vi.fn();
const existsMock = vi.fn();

vi.mock("@tauri-apps/plugin-dialog", () => ({
  open: (...args: unknown[]) => openMock(...args),
}));

vi.mock("@tauri-apps/plugin-fs", () => ({
  exists: (...args: unknown[]) => existsMock(...args),
}));

vi.mock("@tauri-apps/api/path", () => ({
  dirname: async (p: string) => p.replace(/\/[^/]*$/, ""),
}));

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
    _undoPast: [],
    _undoFuture: [],
    activeLeftTab: "Components",
    currentFilePath: null,
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

function renderEditor(
  props: Partial<React.ComponentProps<typeof PowerShapeResourceEditor>> = {},
) {
  return render(
    <TooltipProvider>
      <PowerShapeResourceEditor
        mode={props.mode ?? "create"}
        onSubmit={props.onSubmit ?? vi.fn()}
        onCancel={props.onCancel ?? vi.fn()}
        {...props}
      />
    </TooltipProvider>,
  );
}

describe("PowerShapeResourceEditor", () => {
  beforeEach(() => {
    resetStore();
    openMock.mockReset();
    existsMock.mockReset();
  });

  describe("D-22 kind selector excludes `unset`", () => {
    it("D-22: only uniform / z_cosine / file_loaded are user-creatable kinds", () => {
      renderEditor({ mode: "create" });
      // The Select trigger displays the currently selected kind ("uniform" by default).
      // Open the menu and inspect the items.
      const trigger = screen.getByRole("combobox");
      fireEvent.click(trigger);

      expect(screen.getByRole("option", { name: "uniform" })).toBeTruthy();
      expect(screen.getByRole("option", { name: "z_cosine" })).toBeTruthy();
      expect(screen.getByRole("option", { name: "file_loaded" })).toBeTruthy();

      // The `unset` kind MUST NOT appear (D-22 + D-26: sentinel-only).
      expect(screen.queryByRole("option", { name: "unset" })).toBeNull();
    });
  });

  describe("D-19 smart-name-increment for power shapes", () => {
    it("D-19: pre-fills power_shape_1 on a fresh store", () => {
      renderEditor({ mode: "create" });
      expect(screen.getByDisplayValue("power_shape_1")).toBeTruthy();
    });
  });

  describe("uniform — no extra fields", () => {
    it("renders only Name + Kind when kind is uniform", () => {
      renderEditor({ mode: "create" });
      expect(screen.queryByText("Amplitude")).toBeNull();
      expect(screen.queryByText("Path")).toBeNull();
      expect(screen.queryByText("Browse…")).toBeNull();
    });
  });

  describe("z_cosine — Amplitude field (default 1.0)", () => {
    it("shows the Amplitude NumericField when kind is z_cosine", () => {
      renderEditor({ mode: "create", initialKind: "z_cosine" });
      expect(screen.getByText("Amplitude")).toBeTruthy();
      expect(screen.getByDisplayValue("1.0")).toBeTruthy();
    });
  });

  describe("file_loaded — Path + Browse… button (D-23 CSV-only filter)", () => {
    it("renders the Browse… button and a Path display when kind is file_loaded", () => {
      renderEditor({ mode: "create", initialKind: "file_loaded" });
      expect(screen.getByText("Browse…")).toBeTruthy();
      expect(screen.getByText("Path")).toBeTruthy();
    });

    it("D-23: Browse… invokes the Tauri open() with a CSV-only filter", async () => {
      openMock.mockResolvedValue(null); // user cancels — that's fine, we only care about the filter
      existsMock.mockResolvedValue(true);

      renderEditor({ mode: "create", initialKind: "file_loaded" });
      fireEvent.click(screen.getByText("Browse…"));

      await waitFor(() => expect(openMock).toHaveBeenCalledTimes(1));
      const arg = openMock.mock.calls[0][0] as {
        filters: { name: string; extensions: string[] }[];
      };
      expect(arg.filters).toBeTruthy();
      expect(arg.filters[0].extensions).toEqual(["csv"]);
    });
  });

  describe("Name collision validation (verbatim UI-SPEC copy)", () => {
    it("'A power shape named X already exists.' on collision", () => {
      // Seed with an existing power shape.
      useStore.getState().addPowerShape({
        name: "mtr_cosine",
        kind: "z_cosine",
        params: { amplitude: 1.0 },
      });
      const onSubmit = vi.fn();
      renderEditor({ mode: "create", onSubmit });
      const nameInput = screen.getByDisplayValue("power_shape_1");
      fireEvent.change(nameInput, { target: { value: "mtr_cosine" } });
      fireEvent.click(screen.getByText("Create"));
      expect(
        screen.getByText("A power shape named mtr_cosine already exists."),
      ).toBeTruthy();
      expect(onSubmit).not.toHaveBeenCalled();
    });
  });

  describe("Header copy switches by mode", () => {
    it("renders 'New Power Shape' in create mode", () => {
      renderEditor({ mode: "create" });
      expect(screen.getByText("New Power Shape")).toBeTruthy();
    });

    it("renders 'Edit Power Shape' in edit mode", () => {
      renderEditor({
        mode: "edit",
        initialName: "mtr_cosine",
        initialKind: "z_cosine",
        initialParams: { amplitude: 1.5 },
      });
      expect(screen.getByText("Edit Power Shape")).toBeTruthy();
    });
  });

  // 62-15 (VERIFICATION Gap #4): pin the rewritten engineering-voice copy
  // for identifier validation, amplitude error, and missing-CSV error.
  describe("62-15 engineering-voice validation copy", () => {
    it("shows 'Letters, digits, underscores. Cannot start with a digit.' for an invalid name", () => {
      const onSubmit = vi.fn();
      renderEditor({ mode: "create", onSubmit });
      const nameInput = screen.getByDisplayValue("power_shape_1");
      fireEvent.change(nameInput, { target: { value: "3bad" } });
      fireEvent.click(screen.getByText("Create"));
      expect(
        screen.getByText(
          "Letters, digits, underscores. Cannot start with a digit.",
        ),
      ).toBeTruthy();
      expect(onSubmit).not.toHaveBeenCalled();
    });

    it("shows 'Amplitude must be finite.' on a NaN amplitude", () => {
      const onSubmit = vi.fn();
      renderEditor({ mode: "create", initialKind: "z_cosine", onSubmit });
      // Replace the 1.0 default with garbage.
      const ampInput = screen.getByDisplayValue("1.0");
      fireEvent.change(ampInput, { target: { value: "not-a-number" } });
      fireEvent.click(screen.getByText("Create"));
      expect(screen.getByText("Amplitude must be finite.")).toBeTruthy();
      expect(onSubmit).not.toHaveBeenCalled();
    });

    it("shows 'Pick a CSV file via Browse.' when file_loaded path is empty on submit", () => {
      const onSubmit = vi.fn();
      renderEditor({ mode: "create", initialKind: "file_loaded", onSubmit });
      // Do NOT click Browse; click Create directly with empty path.
      fireEvent.click(screen.getByText("Create"));
      expect(screen.getByText("Pick a CSV file via Browse.")).toBeTruthy();
      expect(onSubmit).not.toHaveBeenCalled();
    });
  });
});
