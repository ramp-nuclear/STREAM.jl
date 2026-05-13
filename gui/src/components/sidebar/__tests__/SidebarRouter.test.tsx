// @vitest-environment happy-dom
//
// Phase 62 Plan 62-09 Task 2 — SidebarPanel selection-kind router tests.
// Covers D-05 (router exclusivity), D-06 (header text per kind), CD-05
// (single-file router pattern), and INV-17 (selection-kind discriminator
// drives the panel).
//
// What is NOT tested here (covered elsewhere):
//   • Full ResourceEditor form behavior — 62-08 GeometryResourceEditor.test.tsx
//     / PowerShapeResourceEditor.test.tsx. We only assert the right editor
//     *mounts* by querying for "Edit Geometry" / "Edit Power Shape".
//   • Esc cascade-stop at the popover layer — 62-08
//     ResourceReferencePicker.test.tsx. We only test the cascade tail
//     (item 4 — selection-clear).

import { describe, it, expect, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import SidebarPanel from "../SidebarPanel";
import useStore, {
  SENTINEL_UNSET_POWER_SHAPE,
  SENTINEL_LIGHT_WATER_FLUID,
} from "../../../store/useStore";
import { TooltipProvider } from "../../ui/tooltip";

function resetStore() {
  useStore.setState({
    nodes: [],
    edges: [],
    bcs: [],
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
          name: "(leave unset — fill in code)",
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

function renderPanel() {
  // TooltipProvider is required by ParameterForm (Component editor branch)
  // and by ResourceReferencePicker mounted inside ParameterForm — every
  // top-level mount of SidebarPanel in tests must wrap in one.
  return render(
    <TooltipProvider>
      <SidebarPanel width={320} />
    </TooltipProvider>,
  );
}

beforeEach(() => {
  resetStore();
});

describe("SidebarPanel — D-06 header text per selection kind", () => {
  it("D-06: component selection → header 'Properties'", () => {
    useStore.getState().addNode("Channel", { x: 0, y: 0 });
    const nodeId = useStore.getState().nodes[0].id;
    useStore.getState().selectNode(nodeId);
    renderPanel();
    expect(screen.getByRole("heading", { level: 2 }).textContent).toBe(
      "Properties",
    );
  });

  it("D-06: geometry selection → header 'Geometry: <name>'", () => {
    const uuid = useStore.getState().addGeometry({
      name: "mtr_channel",
      kind: "rectangular",
      params: { L: 1.0, W: 0.025, H: 0.0025 },
    });
    useStore.getState().selectResource(uuid, "geometry");
    renderPanel();
    expect(screen.getByRole("heading", { level: 2 }).textContent).toBe(
      "Geometry: mtr_channel",
    );
  });

  it("D-06: power-shape selection → header 'Power Shape: <name>'", () => {
    const uuid = useStore.getState().addPowerShape({
      name: "axial_cos",
      kind: "z_cosine",
      params: { peaking: 1.4 },
    });
    useStore.getState().selectResource(uuid, "powerShape");
    renderPanel();
    expect(screen.getByRole("heading", { level: 2 }).textContent).toBe(
      "Power Shape: axial_cos",
    );
  });

  it("D-06: fluid selection → header 'Fluid: light_water'", () => {
    useStore.getState().selectResource(SENTINEL_LIGHT_WATER_FLUID, "fluid");
    renderPanel();
    expect(screen.getByRole("heading", { level: 2 }).textContent).toBe(
      "Fluid: light_water",
    );
  });

  it("D-06: no selection → header 'Properties'", () => {
    renderPanel();
    expect(screen.getByRole("heading", { level: 2 }).textContent).toBe(
      "Properties",
    );
  });
});

describe("SidebarPanel — D-05 body branching by selection kind", () => {
  it("D-05 / CD-05: geometry selection mounts GeometryResourceEditor in edit mode", () => {
    const uuid = useStore.getState().addGeometry({
      name: "mtr_channel",
      kind: "rectangular",
      params: { L: 1.0, W: 0.025, H: 0.0025 },
    });
    useStore.getState().selectResource(uuid, "geometry");
    renderPanel();
    // The 62-08 GeometryResourceEditor renders the literal "Edit Geometry"
    // header in edit mode.
    expect(screen.getByText("Edit Geometry")).toBeTruthy();
  });

  it("D-05 / CD-05: non-sentinel power-shape selection mounts PowerShapeResourceEditor in edit mode", () => {
    const uuid = useStore.getState().addPowerShape({
      name: "axial_cos",
      kind: "z_cosine",
      params: { peaking: 1.4 },
    });
    useStore.getState().selectResource(uuid, "powerShape");
    renderPanel();
    expect(screen.getByText("Edit Power Shape")).toBeTruthy();
  });

  it("D-26: sentinel power-shape selection shows read-only placeholder, NOT the editor", () => {
    useStore
      .getState()
      .selectResource(SENTINEL_UNSET_POWER_SHAPE, "powerShape");
    renderPanel();
    // Sentinel placeholder body — read-only message.
    expect(
      screen.getByText(/unset.*placeholder|Cannot be edited/i),
    ).toBeTruthy();
    // The editor form does NOT mount for the sentinel.
    expect(screen.queryByText("Edit Power Shape")).toBeNull();
  });

  it("D-05: fluid selection shows read-only placeholder body (RESEARCH Q3)", () => {
    useStore.getState().selectResource(SENTINEL_LIGHT_WATER_FLUID, "fluid");
    renderPanel();
    expect(screen.getByText(/Multi-fluid abstraction is v0\.6\+/i)).toBeTruthy();
  });

  it("D-05: no-selection body — Resources tab active shows variant copy", () => {
    useStore.getState().setActiveLeftTab("Resources");
    renderPanel();
    expect(
      screen.getByText("Select a resource on the left to edit it."),
    ).toBeTruthy();
  });

  it("D-05: no-selection body — Components tab active shows standard copy", () => {
    useStore.getState().setActiveLeftTab("Components");
    renderPanel();
    expect(
      screen.getByText(
        "Select a component on the canvas to view its properties.",
      ),
    ).toBeTruthy();
  });

  it("D-05 / INV-17: mutual exclusivity — switching from component to resource swaps the body cleanly", () => {
    // Start: component selected.
    useStore.getState().addNode("Channel", { x: 0, y: 0 });
    const nodeId = useStore.getState().nodes[0].id;
    useStore.getState().selectNode(nodeId);
    const { rerender } = renderPanel();
    expect(screen.getByRole("heading", { level: 2 }).textContent).toBe(
      "Properties",
    );

    // Switch to resource selection — store's selectResource clears node
    // selection (62-02 mutual-exclusivity contract).
    const uuid = useStore.getState().addGeometry({
      name: "mtr_channel",
      kind: "rectangular",
      params: { L: 1.0, W: 0.025, H: 0.0025 },
    });
    useStore.getState().selectResource(uuid, "geometry");
    rerender(
      <TooltipProvider>
        <SidebarPanel width={320} />
      </TooltipProvider>,
    );

    // Header now reflects the resource — Component editor no longer mounted.
    expect(screen.getByRole("heading", { level: 2 }).textContent).toBe(
      "Geometry: mtr_channel",
    );
    expect(screen.getByText("Edit Geometry")).toBeTruthy();
    // Mutual exclusivity surfaced: there is only ONE h2 heading and it
    // belongs to the resource branch (the Component branch's ParameterForm
    // does not produce a competing h2).
    expect(screen.queryAllByRole("heading", { level: 2 }).length).toBe(1);
  });
});

describe("SidebarPanel — UI-SPEC §Esc cascade tail (item 4 — selection-clear)", () => {
  it("D-05 / cascade tail: Esc with no higher-precedence consumer clears selection", () => {
    useStore.getState().addNode("Channel", { x: 0, y: 0 });
    const nodeId = useStore.getState().nodes[0].id;
    useStore.getState().selectNode(nodeId);
    expect(useStore.getState().selectionKind).toBe("component");

    renderPanel();
    // Dispatch a plain Esc on document — no higher-precedence handler ran,
    // so the cascade tail fires.
    fireEvent.keyDown(document, { key: "Escape", code: "Escape" });

    expect(useStore.getState().selectionKind).toBe("none");
    expect(useStore.getState().selectedNodeId).toBeNull();
  });

  it("cascade tail: Esc with defaultPrevented=true does NOT clear selection (gate honored)", () => {
    useStore.getState().addNode("Channel", { x: 0, y: 0 });
    const nodeId = useStore.getState().nodes[0].id;
    useStore.getState().selectNode(nodeId);
    expect(useStore.getState().selectionKind).toBe("component");

    renderPanel();
    // Simulate a higher-precedence consumer (popover / context-menu / rename)
    // that called preventDefault before this listener saw the event. The
    // cascade tail's `e.defaultPrevented` guard must skip.
    const event = new KeyboardEvent("keydown", {
      key: "Escape",
      code: "Escape",
      bubbles: true,
      cancelable: true,
    });
    event.preventDefault();
    document.dispatchEvent(event);

    // Selection is unchanged.
    expect(useStore.getState().selectionKind).toBe("component");
    expect(useStore.getState().selectedNodeId).toBe(nodeId);
  });

  it("cascade tail: Esc with selectionKind === 'none' is a no-op", () => {
    expect(useStore.getState().selectionKind).toBe("none");
    renderPanel();
    fireEvent.keyDown(document, { key: "Escape", code: "Escape" });
    // Still none — no error, no state churn.
    expect(useStore.getState().selectionKind).toBe("none");
  });
});
