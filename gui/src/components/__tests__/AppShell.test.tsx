// @vitest-environment happy-dom
//
// Tests the Phase 62 plan 62-05 Task 1 contract: left-panel Tabs wrapper
// + Ctrl+1/2/3 keyboard accelerators. Covers INV-12 (Ctrl-accelerator
// preventDefault contract) and D-07 (Ctrl+1/2/3 mapping + Ctrl+Tab
// non-interception).
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

// Mock Tauri's window API BEFORE importing App — App's mount-time effects
// call getCurrentWindow().setTitle(...) and .onCloseRequested(...), both of
// which throw under happy-dom because the underlying IPC bridge is absent.
// Phase 70 fix: the `useWindowMaximized` hook (added post-Phase-65) also calls
// getCurrentWindow().onResized(...) at mount. Missing this mock entry caused
// App to throw during render and the tab tests to time out on findByRole.
vi.mock("@tauri-apps/api/window", () => ({
  getCurrentWindow: () => ({
    setTitle: vi.fn().mockResolvedValue(undefined),
    onCloseRequested: vi.fn().mockResolvedValue(() => {}),
    onResized: vi.fn().mockResolvedValue(() => {}),
    destroy: vi.fn().mockResolvedValue(undefined),
  }),
}));

// Phase 65 Plan 08: App now has an AutoRecover render-gate that shows a boot
// splash until detectCrashOnLaunch resolves. Mock the autoRecover module to
// resolve synchronously to a clean launch so the workspace renders.
vi.mock("../../lib/autoRecover", () => ({
  detectCrashOnLaunch: vi
    .fn()
    .mockResolvedValue({ crashed: false, sidecars: [], staleLockfile: null }),
  createDebouncedSidecarWriter: vi.fn().mockReturnValue({
    schedule: vi.fn(),
    cancel: vi.fn(),
    flush: vi.fn(),
  }),
  getSidecarBasename: vi.fn().mockReturnValue("test.scp.autosave"),
  writeLockfile: vi.fn().mockResolvedValue(undefined),
  clearLockfile: vi.fn().mockResolvedValue(undefined),
}));

import { render, screen, fireEvent, cleanup } from "@testing-library/react";
import App from "../../App";
import useStore, {
  SENTINEL_UNSET_POWER_SHAPE,
  SENTINEL_LIGHT_WATER_FLUID,
} from "../../store/useStore";
beforeEach(() => {
  // Reset store to plan-62-02 cold-start state so activeLeftTab === "Components"
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
    toolboxCollapsed: false,
    sidebarCollapsed: false,
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
});

afterEach(() => {
  cleanup();
});

describe("App shell — left-panel Tabs (D-01) + Ctrl+1/2/3 (D-07, INV-12)", () => {
  it("D-01: renders three tab triggers labeled Components / Resources / Project", async () => {
    render(<App />);
    // Phase 65 Plan 08: App now waits on detectCrashOnLaunch before rendering
    // the workspace, so query asynchronously.
    expect(
      await screen.findByRole("tab", { name: /^Components$/ }),
    ).toBeTruthy();
    expect(screen.getByRole("tab", { name: /^Resources$/ })).toBeTruthy();
    expect(screen.getByRole("tab", { name: /^Project$/ })).toBeTruthy();
  });

  it("D-01: Components is the default active tab on cold start", async () => {
    render(<App />);
    const componentsTab = await screen.findByRole("tab", { name: /^Components$/ });
    expect(componentsTab.getAttribute("aria-selected")).toBe("true");
    const resourcesTab = screen.getByRole("tab", { name: /^Resources$/ });
    expect(resourcesTab.getAttribute("aria-selected")).toBe("false");
    const projectTab = screen.getByRole("tab", { name: /^Project$/ });
    expect(projectTab.getAttribute("aria-selected")).toBe("false");
  });

  it("D-01: activating Resources trigger flips aria-selected and updates store", async () => {
    // Radix Tabs activates on pointer down (not click). fireEvent.mouseDown
    // matches Radix's listener; we also fire click for full event-pair fidelity.
    render(<App />);
    const resourcesTab = await screen.findByRole("tab", { name: /^Resources$/ });
    fireEvent.mouseDown(resourcesTab);
    fireEvent.click(resourcesTab);
    expect(useStore.getState().activeLeftTab).toBe("Resources");
    expect(
      screen.getByRole("tab", { name: /^Resources$/ }).getAttribute("aria-selected"),
    ).toBe("true");
  });

  it("INV-12 / D-07: Ctrl+2 keydown switches to Resources AND calls preventDefault", () => {
    render(<App />);
    const event = new KeyboardEvent("keydown", {
      key: "2",
      ctrlKey: true,
      bubbles: true,
      cancelable: true,
    });
    const dispatched = window.dispatchEvent(event);
    // dispatchEvent returns false if preventDefault was called on a cancelable event.
    expect(dispatched).toBe(false);
    expect(useStore.getState().activeLeftTab).toBe("Resources");
  });

  it("INV-12 / D-07: Ctrl+1 keydown switches to Components", () => {
    // Start from Resources to verify the change.
    useStore.getState().setActiveLeftTab("Resources");
    render(<App />);
    const event = new KeyboardEvent("keydown", {
      key: "1",
      ctrlKey: true,
      bubbles: true,
      cancelable: true,
    });
    const dispatched = window.dispatchEvent(event);
    expect(dispatched).toBe(false);
    expect(useStore.getState().activeLeftTab).toBe("Components");
  });

  it("INV-12 / D-07: Ctrl+3 keydown switches to Project", () => {
    render(<App />);
    const event = new KeyboardEvent("keydown", {
      key: "3",
      ctrlKey: true,
      bubbles: true,
      cancelable: true,
    });
    const dispatched = window.dispatchEvent(event);
    expect(dispatched).toBe(false);
    expect(useStore.getState().activeLeftTab).toBe("Project");
  });

  it("D-07: Ctrl+Tab does NOT switch left tabs (browser-collision avoidance)", () => {
    // CanvasPanel's pre-existing Tab handler intercepts plain Tab to cycle
    // layers (so defaultPrevented may be true from that handler). The Phase 62
    // contract is narrower: our Ctrl+1/2/3 handler must NOT switch the left
    // tab on Ctrl+Tab — exactly what D-07 forbids.
    render(<App />);
    const before = useStore.getState().activeLeftTab;
    const event = new KeyboardEvent("keydown", {
      key: "Tab",
      ctrlKey: true,
      bubbles: true,
      cancelable: true,
    });
    window.dispatchEvent(event);
    expect(useStore.getState().activeLeftTab).toBe(before);
  });

  it("INV-12: bare '1' keydown (no modifier) does NOT switch tabs", () => {
    render(<App />);
    const before = useStore.getState().activeLeftTab;
    const event = new KeyboardEvent("keydown", {
      key: "1",
      ctrlKey: false,
      bubbles: true,
      cancelable: true,
    });
    window.dispatchEvent(event);
    expect(useStore.getState().activeLeftTab).toBe(before);
    expect(event.defaultPrevented).toBe(false);
  });

  it("INV-12: Ctrl+Shift+1 does NOT switch tabs (only bare Ctrl+1/2/3 are bound)", () => {
    render(<App />);
    const before = useStore.getState().activeLeftTab;
    const event = new KeyboardEvent("keydown", {
      key: "1",
      ctrlKey: true,
      shiftKey: true,
      bubbles: true,
      cancelable: true,
    });
    window.dispatchEvent(event);
    expect(useStore.getState().activeLeftTab).toBe(before);
  });
});
