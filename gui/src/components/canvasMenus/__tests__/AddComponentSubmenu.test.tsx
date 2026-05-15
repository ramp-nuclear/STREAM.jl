// @vitest-environment happy-dom
//
// Phase 65 Plan 11 — AddComponentSubmenu Radix DropdownMenu.Sub wiring test
//
// Regression guard for the Plan 11 primitive swap. Verifies:
//   1. Each registry category gets a <DropdownMenuSubTrigger> with text == category name.
//   2. Hovering a category SubTrigger opens its SubContent and clicking a leaf item
//      invokes useStore.getState().addNode(componentId, flowPosition) and onClose().
//
// Functional placement (viewport flip) is Radix's responsibility and is verified by
// the manual UAT Test 13 re-run, not here.

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, fireEvent } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

import AddComponentSubmenu from "../AddComponentSubmenu";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuPortal,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import useStore from "@/store/useStore";
import { getAllComponents } from "@/registry";

// Wrap the submenu in a parent DropdownMenu (defaultOpen={true}) so the
// DropdownMenuSub primitives have the required Radix Root + Content context.
function renderInDropdown(ui: React.ReactElement) {
  return render(
    <DropdownMenu defaultOpen={true}>
      <DropdownMenuTrigger>open</DropdownMenuTrigger>
      <DropdownMenuPortal>
        <DropdownMenuContent>{ui}</DropdownMenuContent>
      </DropdownMenuPortal>
    </DropdownMenu>,
  );
}

beforeEach(() => {
  // Reset store between tests
  useStore.setState({
    nodes: [],
    edges: [],
    selectedNodeId: null,
    bcMode: {},
    bcSymmetric: {},
    errorNodeIds: new Set(),
  });
});

afterEach(() => {
  cleanup();
});

describe("AddComponentSubmenu (Phase 65 Plan 11 — Radix DropdownMenu.Sub)", () => {
  it("renders a DropdownMenuSubTrigger for each registry category", () => {
    renderInDropdown(
      <AddComponentSubmenu
        flowPosition={{ x: 0, y: 0 }}
        onClose={vi.fn()}
      />,
    );

    // Distinct category names from registry.components.json:
    // Hydraulic, Reactor Physics, Resources, Sources, Thermal
    const allCategories = Array.from(
      new Set(getAllComponents().map((c) => c.category)),
    );
    expect(allCategories.length).toBeGreaterThan(0);

    for (const cat of allCategories) {
      // The DropdownMenuSubTrigger renders with text == category. We assert by
      // role+name AND by data-slot to be robust to any Tailwind/markup churn.
      const triggers = screen.getAllByText(cat);
      expect(triggers.length).toBeGreaterThan(0);
      const subTrigger = triggers.find((el) =>
        el.closest('[data-slot="dropdown-menu-sub-trigger"]') !== null,
      );
      expect(
        subTrigger,
        `category "${cat}" should be a DropdownMenuSubTrigger`,
      ).toBeTruthy();
    }
  });

  it("clicking a leaf item invokes addNode(componentId, flowPosition) and onClose", async () => {
    const addNodeSpy = vi.fn();
    useStore.setState({ addNode: addNodeSpy });

    const onClose = vi.fn();
    const flowPosition = { x: 42, y: 99 };

    renderInDropdown(
      <AddComponentSubmenu flowPosition={flowPosition} onClose={onClose} />,
    );

    // Pick the first component to exercise (don't hard-code "Pump" — it
    // makes the test resilient to label renames in components.json).
    const components = getAllComponents();
    expect(components.length).toBeGreaterThan(0);
    const target = components[0];

    // Open the target category SubContent by hovering its trigger.
    // Use pointerEnter (what Radix listens to for sub-open) — userEvent.hover
    // dispatches the right event sequence.
    const user = userEvent.setup();
    const categoryEls = screen.getAllByText(target.category);
    const categoryTrigger = categoryEls.find(
      (el) =>
        el.closest('[data-slot="dropdown-menu-sub-trigger"]') !== null,
    );
    expect(categoryTrigger).toBeTruthy();

    // Open via pointer-down + hover — Radix opens sub on pointer-enter when
    // the trigger receives focus, but the most reliable cross-impl approach
    // in tests is to click the trigger.
    await user.click(categoryTrigger as HTMLElement);

    // SubContent should now be in the document. Find the leaf item by label.
    const leaf = await screen.findByText(target.label);
    expect(leaf).toBeTruthy();

    // Click the leaf
    fireEvent.click(leaf);

    expect(addNodeSpy).toHaveBeenCalledTimes(1);
    expect(addNodeSpy).toHaveBeenCalledWith(target.id, flowPosition);
    expect(onClose).toHaveBeenCalledTimes(1);
  });
});
