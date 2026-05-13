// @vitest-environment happy-dom
//
// Phase 63 Plan 63-C Task 04 — SidebarPanel BCs-tab integration tests.
// Covers D-01 (tab strip BELOW header), D-02 (visibility rule based on
// external_inputs.length > 0), and D-03 (active tab resets to Properties on
// selection change).
//
// Pre-existing SidebarRouter coverage lives in SidebarRouter.test.tsx and is
// not duplicated here.

import { describe, it, expect, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import SidebarPanel from "../SidebarPanel";
import useStore, {
  SENTINEL_UNSET_POWER_SHAPE,
  SENTINEL_LIGHT_WATER_FLUID,
} from "../../../store/useStore";
import { TooltipProvider } from "../../ui/tooltip";

// ---------------------------------------------------------------------------
// Fixtures — use production registry entries (Channel has external_inputs;
// Pump does not), so the visibility rule is exercised end-to-end.
// ---------------------------------------------------------------------------

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
    // Phase 63.1 D-15: errorTagsByNodeId slice removed.
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

describe("SidebarPanel — BCs tab strip (Phase 63)", () => {
  it("renders the Properties/BCs tab strip when selected component has external_inputs (D-01, D-02)", () => {
    useStore.getState().addNode("Channel", { x: 0, y: 0 });
    const nodeId = useStore.getState().nodes[0].id;
    useStore.getState().selectNode(nodeId);
    renderPanel();
    expect(screen.getByRole("tab", { name: /Properties/i })).toBeTruthy();
    expect(screen.getByRole("tab", { name: /BCs/i })).toBeTruthy();
  });

  it("does NOT render the tab strip when selected component has neither FlowPort nor external_inputs (Phase 63.1 D-04 — broadened gate)", () => {
    // Phase 63.1 Plan 06 broadened hasBCs from `external_inputs.length > 0`
    // to `hasFlowPort || hasExternalInputs`. To still cover the negative
    // case we need a component that has NEITHER. WallTemperature is a
    // value-source: only a BCPort, no FlowPort, no external_inputs.
    useStore.getState().addNode("WallTemperature", { x: 0, y: 0 });
    const nodeId = useStore.getState().nodes[0].id;
    useStore.getState().selectNode(nodeId);
    renderPanel();
    expect(screen.queryByRole("tab", { name: /BCs/i })).toBeNull();
  });

  it("active tab resets to Properties on selection change (D-03)", () => {
    // Two Channel nodes — switch selection between them.
    useStore.getState().addNode("Channel", { x: 0, y: 0 });
    useStore.getState().addNode("Channel", { x: 0, y: 0 });
    const [n1, n2] = useStore.getState().nodes;
    useStore.getState().selectNode(n1.id);
    const { rerender } = renderPanel();

    // Switch to BCs. Radix Tabs activates on pointerDown / mouseDown, not
    // click (see AppShell.test.tsx idiom).
    const bcsTrigger = screen.getByRole("tab", { name: /BCs/i });
    fireEvent.mouseDown(bcsTrigger);
    fireEvent.click(bcsTrigger);
    // BCs panel content visible — assert a BCsTabForm artefact ("Symmetric (L = R)").
    expect(screen.getByText("Symmetric (L = R)")).toBeTruthy();

    // Change selection — outer `<div key={selectedNodeId}>` remounts the
    // subtree, resetting local tab state.
    useStore.getState().selectNode(n2.id);
    rerender(
      <TooltipProvider>
        <SidebarPanel width={320} />
      </TooltipProvider>,
    );

    // Properties tab should be active by default (D-03 reset).
    const propsTab = screen.getByRole("tab", { name: /Properties/i });
    expect(propsTab.getAttribute("data-state")).toBe("active");
    const bcsTab = screen.getByRole("tab", { name: /BCs/i });
    expect(bcsTab.getAttribute("data-state")).toBe("inactive");
  });

  it("renders the InstanceNameField + Badge header ABOVE the tab strip (D-01)", () => {
    useStore.getState().addNode("Channel", { x: 0, y: 0 });
    const nodeId = useStore.getState().nodes[0].id;
    useStore.getState().selectNode(nodeId);
    const { container } = renderPanel();
    // Locate the instance-name input (header element) and the BCs tab.
    const instanceInput = container.querySelector("input");
    const bcsTab = screen.getByRole("tab", { name: /BCs/i });
    expect(instanceInput).toBeTruthy();
    expect(bcsTab).toBeTruthy();
    // The instance-name input must precede the BCs tab in document order.
    // Node.DOCUMENT_POSITION_FOLLOWING === 4
    const order = instanceInput!.compareDocumentPosition(bcsTab);
    expect(order & 4).toBeTruthy();
  });

  it("clicking the BCs tab renders the BCsTabForm body", () => {
    useStore.getState().addNode("Channel", { x: 0, y: 0 });
    const nodeId = useStore.getState().nodes[0].id;
    useStore.getState().selectNode(nodeId);
    renderPanel();
    // Radix Tabs activates on mouseDown (AppShell.test.tsx idiom).
    const bcsTrigger = screen.getByRole("tab", { name: /BCs/i });
    fireEvent.mouseDown(bcsTrigger);
    fireEvent.click(bcsTrigger);
    expect(screen.getByText("Symmetric (L = R)")).toBeTruthy();
  });
});
