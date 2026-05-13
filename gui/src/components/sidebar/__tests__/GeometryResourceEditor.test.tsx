// @vitest-environment happy-dom
//
// Phase 62 Plan 62-08 Task 3 — GeometryResourceEditor unit tests.
// Covers D-19 (smart-name-increment per kind), D-22 (kind toggle behavior),
// and the verbatim UI-SPEC validation copy.

import { describe, it, expect, beforeEach, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import GeometryResourceEditor from "../GeometryResourceEditor";
import useStore, {
  SENTINEL_UNSET_POWER_SHAPE,
  SENTINEL_LIGHT_WATER_FLUID,
} from "../../../store/useStore";
import { TooltipProvider } from "../../ui/tooltip";

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
  props: Partial<React.ComponentProps<typeof GeometryResourceEditor>> = {},
) {
  return render(
    <TooltipProvider>
      <GeometryResourceEditor
        mode={props.mode ?? "create"}
        onSubmit={props.onSubmit ?? vi.fn()}
        onCancel={props.onCancel ?? vi.fn()}
        {...props}
      />
    </TooltipProvider>,
  );
}

describe("GeometryResourceEditor", () => {
  beforeEach(() => {
    resetStore();
  });

  describe("D-19 smart-name-increment (lowest-free integer per kind)", () => {
    it("D-19: pre-fills geometry_1 when no geometries exist", () => {
      renderEditor({ mode: "create" });
      const nameInput = screen.getByDisplayValue("geometry_1");
      expect(nameInput).toBeTruthy();
    });

    it("D-19: pre-fills geometry_2 when geometry_1 already exists", () => {
      useStore.getState().addGeometry({
        name: "geometry_1",
        kind: "rectangular",
        params: { L: 1, W: 0.1, H: 0.01 },
      });
      renderEditor({ mode: "create" });
      expect(screen.getByDisplayValue("geometry_2")).toBeTruthy();
    });

    it("D-19: lowest-free wins — gap at geometry_2 with 1 and 3 present", () => {
      useStore.getState().addGeometry({
        name: "geometry_1",
        kind: "rectangular",
        params: { L: 1, W: 0.1, H: 0.01 },
      });
      useStore.getState().addGeometry({
        name: "geometry_3",
        kind: "rectangular",
        params: { L: 2, W: 0.2, H: 0.02 },
      });
      renderEditor({ mode: "create" });
      // Lowest-free positive integer is 2, not 4.
      expect(screen.getByDisplayValue("geometry_2")).toBeTruthy();
    });
  });

  describe("D-22 kind toggle (circular ↔ rectangular)", () => {
    it("renders circular by default with L and D fields", () => {
      renderEditor({ mode: "create" });
      // L label and D label both visible
      expect(screen.getAllByText("L").length).toBeGreaterThan(0);
      expect(screen.getAllByText("D").length).toBeGreaterThan(0);
    });

    it("switches to L+W+H when rectangular is selected", () => {
      renderEditor({ mode: "create" });
      const rectButton = screen.getByText("rectangular");
      fireEvent.click(rectButton);
      // After flipping kind, W and H should appear
      expect(screen.getAllByText("W").length).toBeGreaterThan(0);
      expect(screen.getAllByText("H").length).toBeGreaterThan(0);
    });
  });

  describe("Name collision validation (verbatim UI-SPEC copy)", () => {
    it("shows 'A geometry named X already exists.' on collision", () => {
      // Seed the store with an existing geometry.
      useStore.getState().addGeometry({
        name: "mtr_channel",
        kind: "rectangular",
        params: { L: 1, W: 0.1, H: 0.01 },
      });
      const onSubmit = vi.fn();
      renderEditor({ mode: "create", onSubmit });

      // Type the colliding name.
      const nameInput = screen.getByDisplayValue("geometry_1");
      fireEvent.change(nameInput, { target: { value: "mtr_channel" } });

      // Click Create.
      fireEvent.click(screen.getByText("Create"));

      // Verbatim error copy.
      expect(
        screen.getByText("A geometry named mtr_channel already exists."),
      ).toBeTruthy();
      // The resource was NOT created.
      expect(onSubmit).not.toHaveBeenCalled();
    });
  });

  describe("Julia identifier validation (verbatim UI-SPEC copy)", () => {
    it("shows 'Letters, digits, underscores. Cannot start with a digit.' for 3channel", () => {
      const onSubmit = vi.fn();
      renderEditor({ mode: "create", onSubmit });

      const nameInput = screen.getByDisplayValue("geometry_1");
      fireEvent.change(nameInput, { target: { value: "3channel" } });
      fireEvent.click(screen.getByText("Create"));

      // 62-15 rewrite per VERIFICATION Gap #4 — engineering-voice copy.
      expect(
        screen.getByText(
          "Letters, digits, underscores. Cannot start with a digit.",
        ),
      ).toBeTruthy();
      expect(onSubmit).not.toHaveBeenCalled();
    });

    it("rejects names with hyphens", () => {
      const onSubmit = vi.fn();
      renderEditor({ mode: "create", onSubmit });

      const nameInput = screen.getByDisplayValue("geometry_1");
      fireEvent.change(nameInput, { target: { value: "mtr-channel" } });
      fireEvent.click(screen.getByText("Create"));

      expect(
        screen.getByText(
          "Letters, digits, underscores. Cannot start with a digit.",
        ),
      ).toBeTruthy();
      expect(onSubmit).not.toHaveBeenCalled();
    });
  });

  describe("Successful Create flow", () => {
    it("calls onSubmit with the parsed payload on valid input", () => {
      const onSubmit = vi.fn();
      renderEditor({ mode: "create", onSubmit });

      // Fill L and D for circular.
      const inputs = screen.getAllByRole("textbox");
      // The first input is the name; we want the L + D inputs after.
      // Easier: query by their parent <Label>; here we just find by index.
      // The "circular" mode renders Name input (index 0) + L input (index 1)
      // + D input (index 2). We use inputMode="decimal" but Testing Library
      // still treats them as `textbox` because the underlying element is
      // <input> without type="number".
      fireEvent.change(inputs[1], { target: { value: "0.6" } });
      fireEvent.change(inputs[2], { target: { value: "0.025" } });

      fireEvent.click(screen.getByText("Create"));

      expect(onSubmit).toHaveBeenCalledTimes(1);
      const payload = onSubmit.mock.calls[0][0];
      expect(payload.name).toBe("geometry_1");
      expect(payload.kind).toBe("circular");
      expect(payload.params.L).toBe(0.6);
      expect(payload.params.D).toBe(0.025);
    });
  });

  describe("Header copy switches by mode", () => {
    it("renders 'New Geometry' in create mode", () => {
      renderEditor({ mode: "create" });
      expect(screen.getByText("New Geometry")).toBeTruthy();
    });

    it("renders 'Edit Geometry' in edit mode", () => {
      renderEditor({
        mode: "edit",
        initialName: "mtr_channel",
        initialKind: "rectangular",
        initialParams: { L: 0.6, W: 0.07, H: 0.0025 },
      });
      expect(screen.getByText("Edit Geometry")).toBeTruthy();
    });
  });
});
