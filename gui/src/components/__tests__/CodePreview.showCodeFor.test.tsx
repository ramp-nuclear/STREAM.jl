// @vitest-environment happy-dom
//
// CodePreview.showCodeFor.test.tsx — Phase 66 Plan 01 (RED)
//
// Locks the `stream:show-code-for` CustomEvent consumer contract:
//   - panel opens (bottomPanelOpen = true)
//   - target sub-block's scrollIntoView is called with smooth+center
//   - flash class/attribute applied for ~1.5s
//   - nodeIds: string[] payload shape is accepted (D-08 multi-node future)
//
// References:
//   .planning/phases/66-code-preview-rework/66-CONTEXT.md D-07, D-08
//   .planning/phases/66-code-preview-rework/66-RESEARCH.md Pattern 3, Pattern 5, Pattern 10
//   gui/src/components/canvasMenus/NodeContextMenu.tsx:40 (Phase 65 dispatcher)
//
// RED state: no `stream:show-code-for` listener exists yet anywhere in the
// component tree; scrollIntoView is never called; no `[data-flash="true"]`
// attribute is ever set. Plan 04 wires the listener (via useShowCodeFor hook
// installed in App.tsx per Pattern 5).

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { render, cleanup, waitFor, act } from "@testing-library/react";
import CodePreview from "../CodePreview";
import useStore, {
  SENTINEL_UNSET_POWER_SHAPE,
  SENTINEL_LIGHT_WATER_FLUID,
} from "../../store/useStore";

function seedStore(opts: { bottomPanelOpen: boolean } = { bottomPanelOpen: false }) {
  useStore.setState({
    nodes: [
      {
        id: "pump-uuid",
        type: "streamNode",
        position: { x: 0, y: 0 },
        data: {
          componentId: "Pump",
          instanceName: "pump_1",
          parameters: { dP_pump: 1.0 },
          constructorMode: "fixed-dP",
        },
      },
      {
        id: "ch-uuid",
        type: "streamNode",
        position: { x: 200, y: 0 },
        data: {
          componentId: "Channel",
          instanceName: "ch_1",
          parameters: { n: 5, geometry_ref: "geo-1" },
        },
      },
    ],
    edges: [],
    anchors: {},
    bottomPanelOpen: opts.bottomPanelOpen,
    resources: {
      geometries: {
        "geo-1": {
          uuid: "geo-1",
          name: "geom_main",
          kind: "rectangular",
          params: { L: 0.6, W: 0.07, H: 0.0025 },
        },
      },
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
    bcMode: {},
    bcSymmetric: {},
  });
}

beforeEach(() => {
  seedStore();
  // Plan 04 must use scrollIntoView with {behavior:'smooth', block:'center'}.
  // jsdom/happy-dom doesn't implement it; spy/mock per Pattern 3 pitfall.
  vi.spyOn(Element.prototype, "scrollIntoView").mockImplementation(() => {});
});

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

describe("CodePreview — stream:show-code-for listener (Phase 66 D-07, D-08)", () => {
  it("opens the bottom panel and scrolls the target sub-block into view on stream:show-code-for", async () => {
    // Panel starts closed. Per Pattern 5 the listener is installed at a level
    // that's mounted regardless of bottomPanelOpen (e.g., useShowCodeFor hook
    // in App.tsx). For this Plan 04-driven test, we mount CodePreview alone —
    // Plan 04 may need to restructure if it goes with the hook-in-App path.
    // For the RED state, CodePreview is mounted to keep the test focused; the
    // expected outcome (scrollIntoView called) is the contract that matters.
    render(<CodePreview />);

    act(() => {
      window.dispatchEvent(
        new CustomEvent("stream:show-code-for", {
          detail: { nodeId: "pump-uuid" },
        }),
      );
    });

    await waitFor(() => {
      expect(useStore.getState().bottomPanelOpen).toBe(true);
    });

    await waitFor(() => {
      expect(Element.prototype.scrollIntoView).toHaveBeenCalledWith(
        expect.objectContaining({ behavior: "smooth", block: "center" }),
      );
    });
  });

  it("applies a flash attribute/class to the target sub-block for ~1.5s (D-07)", async () => {
    const { container } = render(<CodePreview />);

    act(() => {
      window.dispatchEvent(
        new CustomEvent("stream:show-code-for", {
          detail: { nodeId: "pump-uuid" },
        }),
      );
    });

    // After the event fires, the targeted sub-block has a flash marker.
    // Per Pattern 3 the marker is `data-flash="true"` (an attribute, easy to
    // assert from jsdom — class-based assertion is also acceptable).
    await waitFor(() => {
      const flashed = container.querySelector('[data-flash="true"]');
      expect(flashed).toBeTruthy();
    });
  });

  it("accepts the future multi-node payload (nodeIds: string[]) per D-08", async () => {
    const { container } = render(<CodePreview />);

    act(() => {
      window.dispatchEvent(
        new CustomEvent("stream:show-code-for", {
          detail: { nodeIds: ["pump-uuid", "ch-uuid"] },
        }),
      );
    });

    // When multiple node ids are provided, every matching sub-block should
    // get the flash marker; scrollIntoView is still called (target = first
    // match in document order, per Pattern 3).
    await waitFor(() => {
      expect(Element.prototype.scrollIntoView).toHaveBeenCalled();
    });

    await waitFor(() => {
      const flashed = container.querySelectorAll('[data-flash="true"]');
      // ≥ 1 — at least one sub-block flashed. Multi-node fan-out specifics
      // are decided by Plan 04 (whether each matching sub-block flashes
      // simultaneously or only the first).
      expect(flashed.length).toBeGreaterThanOrEqual(1);
    });
  });
});
