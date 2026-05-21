// @vitest-environment happy-dom
//
// Phase 65 Plan 05 — context menu component tests
// Covers the 4 behavior cases from the plan's <behavior> spec:
//   1. NodeContextMenu items: Rename, Duplicate, Show generated Julia code, Delete — no Show errors
//   2. NodeContextMenu Delete click → onClose called AND node removed from store
//   3. EdgeContextMenu items: Delete only
//   4. CanvasContextMenu items: Paste, Auto-Layout (future) (disabled), Add Component submenu trigger

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, fireEvent } from "@testing-library/react";
import type { ReactNode } from "react";
import type { Node } from "@xyflow/react";
import NodeContextMenu from "../NodeContextMenu";
import EdgeContextMenu from "../EdgeContextMenu";
import CanvasContextMenu from "../CanvasContextMenu";
import {
  DropdownMenu,
  DropdownMenuContent,
} from "@/components/ui/dropdown-menu";
import useStore from "@/store/useStore";
import type { StreamNodeData } from "@/store/useStore";

// Phase 65 Plan 11 migrated *ContextMenu components from PopoverMenuItem (a
// hand-rolled div) to DropdownMenuItem (Radix MenuItem), which requires a
// `<DropdownMenu>` provider ancestor. CanvasPanel.tsx supplies that ancestor
// at the callsite; tests must do the same or `MenuItem must be used within
// Menu` is thrown via Radix's `useContext2`. This helper mirrors the
// CanvasPanel wrapper (open DropdownMenu + DropdownMenuContent) so each
// menu component renders in the context it's actually used in.
function renderInDropdown(child: ReactNode) {
  return render(
    <DropdownMenu open onOpenChange={() => {}}>
      <DropdownMenuContent
        // Match CanvasPanel.tsx props that are relevant for assertions.
        onCloseAutoFocus={(e) => e.preventDefault()}
      >
        {child}
      </DropdownMenuContent>
    </DropdownMenu>,
  );
}

// ---------------------------------------------------------------------------
// navigator.clipboard stub (needed by pasteFromClipboard if called)
// ---------------------------------------------------------------------------
Object.defineProperty(globalThis, "navigator", {
  value: {
    clipboard: {
      writeText: vi.fn(async () => {}),
      readText: vi.fn(async () => ""),
    },
  },
  configurable: true,
  writable: true,
});

// ---------------------------------------------------------------------------
// Helper: build a test node
// ---------------------------------------------------------------------------
function makeNode(id: string, instanceName = "pump_1"): Node {
  return {
    id,
    type: "streamNode",
    position: { x: 100, y: 200 },
    selected: false,
    data: {
      componentId: "Pump",
      instanceName,
      parameters: {},
      constructorMode: "default",
    } satisfies StreamNodeData as unknown as Record<string, unknown>,
  };
}

// ---------------------------------------------------------------------------
// Reset store and cleanup DOM between tests
// ---------------------------------------------------------------------------
beforeEach(() => {
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

// ---------------------------------------------------------------------------
// Test 1: NodeContextMenu item set + Show errors absent
// ---------------------------------------------------------------------------
describe("NodeContextMenu", () => {
  it("renders Rename, Duplicate, Show generated Julia code, Delete — and NOT Show errors", () => {
    const onClose = vi.fn();
    renderInDropdown(<NodeContextMenu nodeId="n1" onClose={onClose} />);

    expect(screen.getByText("Rename")).toBeTruthy();
    expect(screen.getByText("Duplicate")).toBeTruthy();
    expect(screen.getByText("Show generated Julia code")).toBeTruthy();
    expect(screen.getByText("Delete")).toBeTruthy();
    // Show errors must NOT appear (D-14: hidden until Phase 71)
    expect(screen.queryByText(/Show errors/i)).toBeNull();
  });

  // ---------------------------------------------------------------------------
  // Test 2: Delete click → onClose called AND node removed from store
  // ---------------------------------------------------------------------------
  it("Delete item removes the node from store and calls onClose", () => {
    const node = makeNode("n1");
    useStore.setState({ nodes: [node] });

    const onClose = vi.fn();
    renderInDropdown(<NodeContextMenu nodeId="n1" onClose={onClose} />);

    const deleteBtn = screen.getByText("Delete");
    fireEvent.click(deleteBtn);

    // onClose called
    expect(onClose).toHaveBeenCalledTimes(1);
    // Node removed from store
    const remaining = useStore.getState().nodes;
    expect(remaining.find((n) => n.id === "n1")).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// Test 3: EdgeContextMenu — Delete only
// ---------------------------------------------------------------------------
describe("EdgeContextMenu", () => {
  it("renders only a Delete item", () => {
    const onClose = vi.fn();
    renderInDropdown(<EdgeContextMenu edgeId="e1" onClose={onClose} />);

    expect(screen.getByText("Delete")).toBeTruthy();
    // No other named menu items (Rename, Duplicate, Paste, etc.)
    expect(screen.queryByText("Rename")).toBeNull();
    expect(screen.queryByText("Duplicate")).toBeNull();
    expect(screen.queryByText("Paste")).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// Test 4: CanvasContextMenu — Paste, Auto-Layout (future) disabled, Add Component
// ---------------------------------------------------------------------------
describe("CanvasContextMenu", () => {
  it("renders Paste, Auto-Layout (future) as disabled, and Add Component submenu trigger", () => {
    const onClose = vi.fn();
    renderInDropdown(
      <CanvasContextMenu
        flowPosition={{ x: 0, y: 0 }}
        onClose={onClose}
      />,
    );

    expect(screen.getByText("Paste")).toBeTruthy();

    // Auto-Layout (future) is present
    const autoLayout = screen.getByText("Auto-Layout (future)");
    expect(autoLayout).toBeTruthy();
    // Phase 65 Plan 11 migrated to DropdownMenuItem — the slot attribute was
    // renamed from "popover-menu-item" to "dropdown-menu-item".
    const menuItemEl = autoLayout.closest("[data-slot='dropdown-menu-item']") as HTMLElement | null;
    expect(menuItemEl).not.toBeNull();
    expect(
      menuItemEl?.getAttribute("data-disabled") !== null ||
      menuItemEl?.getAttribute("aria-disabled") === "true"
    ).toBe(true);

    // Add Component submenu trigger is present
    expect(screen.getByText("Add Component")).toBeTruthy();
  });
});
