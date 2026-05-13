// @vitest-environment happy-dom
//
// Phase 63.1 Plan 06 Task 1 — AnchorsSection tests.
// Covers D-04 (FlowPort gate), D-02 anchors-slice integration, UI-SPEC
// Anchors Section — Row Anatomy (empty + populated states), and the
// Copywriting Contract (verbatim strings).

import { describe, it, expect, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import AnchorsSection from "../AnchorsSection";
import useStore from "../../../store/useStore";
import type { ComponentDefinition } from "../../../registry/types";
import { TooltipProvider } from "../../ui/tooltip";

// ---------------------------------------------------------------------------
// Fixtures — components with / without a FlowPort.
// ---------------------------------------------------------------------------

const pumpDef: ComponentDefinition = {
  id: "Pump",
  label: "Pump",
  category: "Hydraulic",
  description: "Test pump",
  ports: [
    { name: "port_in", type: "FlowPort", side: "left" },
    { name: "port_out", type: "FlowPort", side: "right" },
  ],
  parameters: [],
  constructorModes: [{ mode: "default", signature: "Pump(...)", parameters: [] }],
};

const wallTempDef: ComponentDefinition = {
  id: "WallTemperature",
  label: "Wall Temperature",
  category: "Sources",
  description: "Test WallTemperature",
  ports: [
    { name: "T_wall_out", type: "BCPort", array_size: "n", side: "right" },
  ],
  parameters: [],
  constructorModes: [
    { mode: "default", signature: "WallTemperature(...)", parameters: [] },
  ],
};

function resetStore() {
  useStore.setState({
    nodes: [],
    edges: [],
    anchors: {},
    selectedNodeId: null,
    isDirty: false,
    _undoPast: [],
    _undoFuture: [],
    bcMode: {},
    bcSymmetric: {},
  });
}

function renderSection(component: ComponentDefinition, nodeId: string) {
  return render(
    <TooltipProvider>
      <AnchorsSection nodeId={nodeId} component={component} />
    </TooltipProvider>,
  );
}

beforeEach(() => {
  resetStore();
});

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("AnchorsSection — FlowPort gate (D-04)", () => {
  it("renders nothing when the component has no FlowPort", () => {
    const { container } = renderSection(wallTempDef, "n1");
    expect(container.firstChild).toBeNull();
  });

  it("renders the section container when the component has a FlowPort", () => {
    const { container } = renderSection(pumpDef, "n1");
    expect(container.firstChild).not.toBeNull();
    expect(screen.getByTestId("anchors-section")).toBeTruthy();
  });
});

describe("AnchorsSection — empty state (UI-SPEC State A)", () => {
  it("shows the 'No anchor set' empty message when anchors[nodeId] is undefined", () => {
    renderSection(pumpDef, "n1");
    expect(screen.getByText("No anchor set")).toBeTruthy();
  });

  it("shows the '+ Add anchor' affordance in the empty state", () => {
    renderSection(pumpDef, "n1");
    expect(screen.getByTestId("anchor-add")).toBeTruthy();
    expect(screen.getByText("+ Add anchor")).toBeTruthy();
  });

  it("clicking '+ Add anchor' calls setAnchor with the default { port_in.P, 0 }", () => {
    renderSection(pumpDef, "n1");
    fireEvent.click(screen.getByTestId("anchor-add"));
    expect(useStore.getState().anchors["n1"]).toEqual({
      portField: "port_in.P",
      value: 0,
    });
  });
});

describe("AnchorsSection — populated state (UI-SPEC State B)", () => {
  beforeEach(() => {
    useStore.getState().setAnchor("n1", { portField: "port_in.P", value: 101325 });
  });

  it("renders the Port label and Pressure label", () => {
    renderSection(pumpDef, "n1");
    expect(screen.getByText("Port")).toBeTruthy();
    expect(screen.getByText("Pressure")).toBeTruthy();
  });

  it("renders a Clear anchor button (testid + verbatim copy)", () => {
    renderSection(pumpDef, "n1");
    expect(screen.getByTestId("anchor-clear")).toBeTruthy();
    expect(screen.getByText("Clear anchor")).toBeTruthy();
  });

  it("clicking 'Clear anchor' dispatches clearAnchor(nodeId)", () => {
    renderSection(pumpDef, "n1");
    fireEvent.click(screen.getByTestId("anchor-clear"));
    expect(useStore.getState().anchors["n1"]).toBeUndefined();
  });
});
