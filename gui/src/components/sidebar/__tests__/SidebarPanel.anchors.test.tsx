// @vitest-environment happy-dom
//
// Phase 63.1 Plan 06 Task 2 — SidebarPanel BCs-tab integration with the
// Anchors section.
//
// Covers:
//   - D-04: broadened hasBCs = hasFlowPort || hasExternalInputs. The BCs
//     tab now appears for components with a FlowPort even when they have
//     no external_inputs (e.g. Pump).
//   - D-09: BCs tab body renders Anchors section ABOVE External Inputs
//     when the component has both (e.g. Channel).
//   - D-10: BCs tab remains in the right sidebar — no relocation.

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
    anchors: {},
    selectedNodeId: null,
    selectedResourceId: null,
    selectedResourceKind: null,
    selectionKind: "none",
    isDirty: false,
    _undoPast: [],
    _undoFuture: [],
    activeLeftTab: "Components",
    bcMode: {},
    bcSymmetric: {},
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

function renderPanel() {
  return render(
    <TooltipProvider>
      <SidebarPanel width={320} />
    </TooltipProvider>,
  );
}

beforeEach(() => {
  resetStore();
});

describe("SidebarPanel — BCs tab Anchors integration (Phase 63.1 Plan 06)", () => {
  it("Pump (FlowPort, no external_inputs): BCs tab now renders (D-04 broadened gate)", () => {
    useStore.getState().addNode("Pump", { x: 0, y: 0 });
    const nodeId = useStore.getState().nodes[0].id;
    useStore.getState().selectNode(nodeId);
    renderPanel();
    expect(screen.getByRole("tab", { name: /BCs/i })).toBeTruthy();
  });

  it("Pump BCs tab body shows Anchors section but NOT External Inputs header", () => {
    useStore.getState().addNode("Pump", { x: 0, y: 0 });
    const nodeId = useStore.getState().nodes[0].id;
    useStore.getState().selectNode(nodeId);
    renderPanel();
    const bcsTrigger = screen.getByRole("tab", { name: /BCs/i });
    fireEvent.mouseDown(bcsTrigger);
    fireEvent.click(bcsTrigger);
    // Anchors section header + empty-state copy visible
    expect(screen.getByText("Anchors")).toBeTruthy();
    expect(screen.getByText("No anchor set")).toBeTruthy();
    // External Inputs section header NOT shown (Pump has no external_inputs)
    expect(screen.queryByText("External Inputs")).toBeNull();
  });

  it("Channel (FlowPort + external_inputs): BCs tab body shows Anchors ABOVE External Inputs (D-09)", () => {
    useStore.getState().addNode("Channel", { x: 0, y: 0 });
    const nodeId = useStore.getState().nodes[0].id;
    useStore.getState().selectNode(nodeId);
    renderPanel();
    const bcsTrigger = screen.getByRole("tab", { name: /BCs/i });
    fireEvent.mouseDown(bcsTrigger);
    fireEvent.click(bcsTrigger);

    const anchorsHeader = screen.getByText("Anchors");
    const extInputsHeader = screen.getByText("External Inputs");
    expect(anchorsHeader).toBeTruthy();
    expect(extInputsHeader).toBeTruthy();

    // Anchors header must precede External Inputs header in document order.
    // Node.DOCUMENT_POSITION_FOLLOWING === 4
    const order = anchorsHeader.compareDocumentPosition(extInputsHeader);
    expect(order & 4).toBeTruthy();
  });

  it("Channel BCs tab body still renders BCsTabForm content below Anchors", () => {
    useStore.getState().addNode("Channel", { x: 0, y: 0 });
    const nodeId = useStore.getState().nodes[0].id;
    useStore.getState().selectNode(nodeId);
    renderPanel();
    const bcsTrigger = screen.getByRole("tab", { name: /BCs/i });
    fireEvent.mouseDown(bcsTrigger);
    fireEvent.click(bcsTrigger);
    // Phase 63.1 D-12 replaced the legacy "Symmetric (L = R)" custom switch
    // with a SegmentedButtonGroup ("Symmetric" / "Asymmetric"). The original
    // test targeted the deleted literal; assert against the current copy so
    // we still verify that BCsTabForm renders below the Anchors section.
    expect(screen.getByText("Symmetric")).toBeTruthy();
    expect(screen.getByText("Asymmetric")).toBeTruthy();
  });
});
