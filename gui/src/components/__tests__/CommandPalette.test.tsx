// @vitest-environment happy-dom
//
// Phase 69 Plan 02 Task 2 — behavior coverage for CommandPalette.tsx.
//
// Maps 1:1 to the 11 <behavior> cases in 69-02-PLAN.md:
//   1. renders nothing when open=false
//   2. renders top-anchored dialog when open=true (top-[80px] + translate-y-0)
//   3. empty query shows group headings
//   4. typed query shows flat list (no group headings)
//   5. off-layer component renders hint chip with per-layer accent color (D-08)
//   6. selecting an off-layer component dispatches setLayerVisible → setCenter
//      → selectNode → onOpenChange in order (D-03 / D-04)
//   7. setCenter zoom respects ZOOM_MIN_LEGIBLE = 0.75 floor (D-04)
//   8. selecting a resource calls setActiveLeftTab("Resources") + selectResource
//      + onOpenChange (D-06)
//   9. selecting Project Options calls setActiveLeftTab("Project") +
//      clearSelection + onOpenChange (D-05)
//  10. no matched-character highlighting (D-07)
//  11. Esc closes palette (Section 3.8 / radix default)
//
// useReactFlow is mocked via vi.mock("@xyflow/react") — the test owns the
// setCenter/getZoom spies. ReactFlowProvider is the same module's export and
// is re-exported as a no-op fragment by the mock factory.

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { render, screen, cleanup, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

// --- vi.mock for @xyflow/react -------------------------------------------
// Hoisted spies so each test can read/reset them.
const setCenterSpy = vi.fn();
let currentZoom = 1.0;

vi.mock("@xyflow/react", async () => {
  const React = await import("react");
  return {
    useReactFlow: () => ({
      setCenter: setCenterSpy,
      getZoom: () => currentZoom,
      // pass-throughs in case the component ever calls them — not exercised
      // by these tests:
      fitView: vi.fn(),
    }),
    ReactFlowProvider: ({ children }: { children: React.ReactNode }) =>
      React.createElement(React.Fragment, null, children),
  };
});
// --------------------------------------------------------------------------

import CommandPalette from "../CommandPalette";
import useStore, {
  SENTINEL_UNSET_POWER_SHAPE,
  SENTINEL_LIGHT_WATER_FLUID,
} from "../../store/useStore";
import { ALL_LAYERS_ON } from "../../lib/layers";
import { ReactFlowProvider } from "@xyflow/react";

// ---------------------------------------------------------------------------
// Test fixtures + helpers
// ---------------------------------------------------------------------------

/**
 * Build a minimal canvas node for the search pool. `componentId: "Channel"`
 * is a real registry entry whose category is "Hydraulic", so
 * `getComponentLayers` returns `["Hydraulic"]` — that's how we drive the
 * off-layer-chip and on-select-layer-enable tests.
 */
function makeChannelNode(opts: {
  id?: string;
  instanceName?: string;
  x?: number;
  y?: number;
} = {}) {
  return {
    id: opts.id ?? "node-1",
    type: "streamNode",
    position: { x: opts.x ?? 100, y: opts.y ?? 200 },
    data: {
      componentId: "Channel",
      instanceName: opts.instanceName ?? "channel",
      parameters: {},
    },
  };
}

function seedStore(overrides: Record<string, unknown> = {}): void {
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
    activeLayers: { ...ALL_LAYERS_ON },
    hideOffLayer: false,
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
    ...overrides,
  });
}

/** Render CommandPalette wrapped in the mocked ReactFlowProvider. */
function renderPalette(props: {
  open: boolean;
  onOpenChange?: (open: boolean) => void;
}) {
  const onOpenChange = props.onOpenChange ?? vi.fn();
  const utils = render(
    <ReactFlowProvider>
      <CommandPalette open={props.open} onOpenChange={onOpenChange} />
    </ReactFlowProvider>,
  );
  return { ...utils, onOpenChange };
}

beforeEach(() => {
  setCenterSpy.mockReset();
  currentZoom = 1.0;
  seedStore();
});

afterEach(() => {
  cleanup();
});

// ---------------------------------------------------------------------------
// Case 1 — renders nothing when open=false
// ---------------------------------------------------------------------------

describe("CommandPalette — mount gate", () => {
  it("renders nothing when open=false", () => {
    renderPalette({ open: false });
    expect(
      screen.queryByPlaceholderText(/Type to search/i),
    ).toBeNull();
  });

  // Case 2 — top-anchored dialog when open=true
  it("renders a top-anchored dialog when open=true (top-[80px] + translate-y-0)", () => {
    renderPalette({ open: true });
    const content = screen.getByTestId("command-palette-content");
    expect(content.className).toContain("top-[80px]");
    expect(content.className).toContain("translate-y-0");
  });
});

// ---------------------------------------------------------------------------
// Case 3 + 4 — browse vs flat
// ---------------------------------------------------------------------------

describe("CommandPalette — browse vs flat", () => {
  it("empty query shows group headings (Components + Geometries)", () => {
    seedStore({
      nodes: [makeChannelNode()],
      resources: {
        geometries: { g1: { uuid: "g1", name: "rect1" } },
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
    renderPalette({ open: true });
    expect(screen.getByText("Components")).toBeTruthy();
    expect(screen.getByText("Geometries")).toBeTruthy();
    // Project Options is always present per D-05.
    expect(screen.getByText("Project")).toBeTruthy();
  });

  it("typed query hides group headings (flat list)", async () => {
    seedStore({
      nodes: [makeChannelNode()],
      resources: {
        geometries: { g1: { uuid: "g1", name: "rect1" } },
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
    const user = userEvent.setup();
    renderPalette({ open: true });
    const input = screen.getByPlaceholderText(/Type to search/i);
    await user.type(input, "channel");
    expect(screen.queryByText("Components")).toBeNull();
    expect(screen.queryByText("Geometries")).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// Case 5 — off-layer hint chip uses per-layer accent (D-08)
// ---------------------------------------------------------------------------

describe("CommandPalette — off-layer hint chip (D-08)", () => {
  it("renders a layer-color dot with tooltip when a layer is off (D-08 dim+dot)", () => {
    seedStore({
      nodes: [makeChannelNode()],
      activeLayers: { ...ALL_LAYERS_ON, Hydraulic: false },
    });
    renderPalette({ open: true });
    const dot = screen.getByTestId("off-layer-chip-Hydraulic");
    // happy-dom serializes hex to rgb(...).
    const expectedHex = "#3b82f6";
    const expectedRgb = "rgb(59, 130, 246)";
    const bg = dot.style.backgroundColor || "";
    expect([expectedHex, expectedRgb]).toContain(bg);
    // Detail moved from inline text to title/aria-label for hover-on-demand.
    expect(dot.getAttribute("title")).toMatch(/Hydraulic/);
    expect(dot.getAttribute("title")).toMatch(/off/);
    expect(dot.getAttribute("title")).toMatch(/will enable/);
    // Parent CommandItem is dimmed so the off-layer state is also legible
    // at-a-glance even without hovering the dot.
    const row = dot.closest('[data-testid^="cmdk-row-component-"]');
    expect(row?.getAttribute("data-off-layer")).toBe("true");
  });
});

// ---------------------------------------------------------------------------
// Case 6 + 7 — component on-select dispatch (D-03 / D-04) + zoom floor
// ---------------------------------------------------------------------------

describe("CommandPalette — component on-select dispatch", () => {
  it("dispatches setLayerVisible → setCenter → selectNode → onOpenChange in order", async () => {
    const node = makeChannelNode({ x: 100, y: 200, id: "node-1" });
    const setLayerVisibleSpy = vi.fn();
    const selectNodeSpy = vi.fn();
    const onOpenChange = vi.fn();

    seedStore({
      nodes: [node],
      activeLayers: { ...ALL_LAYERS_ON, Hydraulic: false },
      setLayerVisible: setLayerVisibleSpy,
      selectNode: selectNodeSpy,
    });
    currentZoom = 1.0;

    const user = userEvent.setup();
    render(
      <ReactFlowProvider>
        <CommandPalette open={true} onOpenChange={onOpenChange} />
      </ReactFlowProvider>,
    );

    const row = screen.getByTestId("cmdk-row-component-node-1");
    await user.click(row);

    // D-03 — layer enable happens BEFORE pan/select.
    expect(setLayerVisibleSpy).toHaveBeenCalledWith("Hydraulic", true);
    // D-04 — setCenter with current zoom (1.0, above the floor).
    expect(setCenterSpy).toHaveBeenCalledWith(100, 200, {
      zoom: 1.0,
      duration: 250,
    });
    expect(selectNodeSpy).toHaveBeenCalledWith("node-1");
    expect(onOpenChange).toHaveBeenCalledWith(false);

    // Order check: setLayerVisible invocation happened before setCenter,
    // setCenter before selectNode, selectNode before onOpenChange.
    const layerCallOrder = setLayerVisibleSpy.mock.invocationCallOrder[0];
    const centerCallOrder = setCenterSpy.mock.invocationCallOrder[0];
    const selectNodeCallOrder = selectNodeSpy.mock.invocationCallOrder[0];
    const openCallOrder = onOpenChange.mock.invocationCallOrder[0];
    expect(layerCallOrder).toBeLessThan(centerCallOrder);
    expect(centerCallOrder).toBeLessThan(selectNodeCallOrder);
    expect(selectNodeCallOrder).toBeLessThan(openCallOrder);
  });

  it("setCenter zoom respects ZOOM_MIN_LEGIBLE (0.75) when currentZoom < 0.75", async () => {
    const node = makeChannelNode({ x: 50, y: 50, id: "node-z" });
    seedStore({
      nodes: [node],
      activeLayers: { ...ALL_LAYERS_ON },
    });
    currentZoom = 0.5;

    const user = userEvent.setup();
    renderPalette({ open: true });
    const row = screen.getByTestId("cmdk-row-component-node-z");
    await user.click(row);

    expect(setCenterSpy).toHaveBeenCalledWith(50, 50, {
      zoom: 0.75,
      duration: 250,
    });
  });
});

// ---------------------------------------------------------------------------
// Case 8 — resource on-select dispatch (D-06)
// ---------------------------------------------------------------------------

describe("CommandPalette — resource on-select dispatch (D-06)", () => {
  it("selecting a geometry calls setActiveLeftTab('Resources') + selectResource + onOpenChange", async () => {
    const setActiveLeftTabSpy = vi.fn();
    const selectResourceSpy = vi.fn();
    const onOpenChange = vi.fn();

    seedStore({
      resources: {
        geometries: { g1: { uuid: "g1", name: "rect1" } },
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
      setActiveLeftTab: setActiveLeftTabSpy,
      selectResource: selectResourceSpy,
    });

    const user = userEvent.setup();
    render(
      <ReactFlowProvider>
        <CommandPalette open={true} onOpenChange={onOpenChange} />
      </ReactFlowProvider>,
    );

    const row = screen.getByTestId("cmdk-row-geometry-g1");
    await user.click(row);

    expect(setActiveLeftTabSpy).toHaveBeenCalledWith("Resources");
    expect(selectResourceSpy).toHaveBeenCalledWith("g1", "geometry");
    expect(onOpenChange).toHaveBeenCalledWith(false);
    // No setCenter for resource jumps.
    expect(setCenterSpy).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// Case 9 — Project Options on-select dispatch (D-05)
// ---------------------------------------------------------------------------

describe("CommandPalette — Project Options on-select dispatch (D-05)", () => {
  it("calls setActiveLeftTab('Project') + clearSelection + onOpenChange", async () => {
    const setActiveLeftTabSpy = vi.fn();
    const clearSelectionSpy = vi.fn();
    const onOpenChange = vi.fn();

    seedStore({
      setActiveLeftTab: setActiveLeftTabSpy,
      clearSelection: clearSelectionSpy,
    });

    const user = userEvent.setup();
    render(
      <ReactFlowProvider>
        <CommandPalette open={true} onOpenChange={onOpenChange} />
      </ReactFlowProvider>,
    );

    const row = screen.getByTestId("cmdk-row-modelOptions");
    await user.click(row);

    expect(setActiveLeftTabSpy).toHaveBeenCalledWith("Project");
    expect(clearSelectionSpy).toHaveBeenCalled();
    expect(onOpenChange).toHaveBeenCalledWith(false);
  });
});

// ---------------------------------------------------------------------------
// Case 10 — no matched-character highlighting (D-07)
// ---------------------------------------------------------------------------

describe("CommandPalette — no matched-character highlighting (D-07)", () => {
  it("typing a substring does NOT wrap matched chars in <mark> or accent spans", async () => {
    seedStore({
      nodes: [makeChannelNode({ instanceName: "channel" })],
    });

    const user = userEvent.setup();
    const { container } = renderPalette({ open: true });
    const input = screen.getByPlaceholderText(/Type to search/i);
    await user.type(input, "ch");

    // No <mark> elements anywhere in the palette.
    expect(container.querySelector("mark")).toBeNull();

    // The row's name slot should still read "channel" as a single text run.
    const row = screen.getByTestId("cmdk-row-component-node-1");
    const nameSpan = within(row).getByText("channel");
    // The name lives in a single <span> with no children that wrap a
    // substring like "ch" in its own colored span.
    expect(nameSpan.children.length).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// Case 11 — Esc closes palette
// ---------------------------------------------------------------------------

describe("CommandPalette — Esc dismissal (Section 3.8)", () => {
  it("pressing Esc fires onOpenChange(false)", async () => {
    const onOpenChange = vi.fn();
    const user = userEvent.setup();
    render(
      <ReactFlowProvider>
        <CommandPalette open={true} onOpenChange={onOpenChange} />
      </ReactFlowProvider>,
    );

    await user.keyboard("{Escape}");

    expect(onOpenChange).toHaveBeenCalledWith(false);
  });

  // Pitfall 6 / CONTEXT.md D-08 regression guard:
  // Esc must close the palette without bubbling to the window-level Esc
  // handler in App.tsx that clears pinned code-preview blocks. We assert
  // this at the source by capturing the keydown on `window` and confirming
  // propagation was stopped by the time it reaches there.
  it("Esc does NOT bubble past the dialog (no double-fire to window)", async () => {
    const onOpenChange = vi.fn();
    const user = userEvent.setup();
    render(
      <ReactFlowProvider>
        <CommandPalette open={true} onOpenChange={onOpenChange} />
      </ReactFlowProvider>,
    );

    const windowEsc = vi.fn();
    const listener = (e: KeyboardEvent) => {
      if (e.key === "Escape") windowEsc();
    };
    window.addEventListener("keydown", listener);
    try {
      await user.keyboard("{Escape}");
    } finally {
      window.removeEventListener("keydown", listener);
    }

    expect(onOpenChange).toHaveBeenCalledWith(false);
    expect(windowEsc).not.toHaveBeenCalled();
  });
});
