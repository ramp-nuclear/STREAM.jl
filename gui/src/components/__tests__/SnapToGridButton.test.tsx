// @vitest-environment happy-dom
//
// Phase 65 Plan 06 Task 3 (TDD) — SnapToGridButton component tests
// Covers the 5 behavior cases from the plan's <behavior> spec:
//   1. Renders a button with aria-label "Snap to grid"
//   2. When store snapToGrid === false, button has data-state="off" (not pressed)
//   3. When store snapToGrid === true, button has data-state="on" (pressed)
//   4. Clicking the button calls setSnapToGrid(!currentValue)
//   5. Button uses the Grid lucide icon

import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, fireEvent, act } from "@testing-library/react";
import SnapToGridButton from "../canvasMenus/SnapToGridButton";
import useStore from "../../store/useStore";
import { initPreferencesBridge, setPreference } from "../../lib/preferences";

// Phase 72 Preferences — the canvas overlay button now writes through
// setPreference; the runtime mirror in useStore is updated by the bridge that
// App.tsx mounts on app load. In isolated component tests, we mount the
// bridge manually so the click → pref → store propagation completes.
let teardownBridge: (() => void) | null = null;

beforeEach(() => {
  act(() => {
    useStore.setState({ snapToGrid: false });
  });
  // Clear any pref value lingering from a previous test
  setPreference("editor", "snapToGrid", false);
  teardownBridge = initPreferencesBridge({
    setHideOffLayer: useStore.getState().setHideOffLayer,
    setSnapToGrid: useStore.getState().setSnapToGrid,
    setInteractiveLocked: useStore.getState().setInteractiveLocked,
  });
});

afterEach(() => {
  teardownBridge?.();
  teardownBridge = null;
  cleanup();
});

describe("SnapToGridButton (Phase 65 D-07/D-10)", () => {
  it("case 1: renders a button with aria-label containing 'snap to grid' (case-insensitive)", () => {
    render(<SnapToGridButton />);
    const btn = screen.getByRole("button");
    expect(btn).toBeTruthy();
    const label = btn.getAttribute("aria-label") ?? btn.getAttribute("title") ?? "";
    expect(label.toLowerCase()).toContain("snap to grid");
  });

  it("case 2: when snapToGrid === false, button has data-state='off'", () => {
    act(() => { useStore.setState({ snapToGrid: false }); });
    render(<SnapToGridButton />);
    const btn = screen.getByRole("button");
    expect(btn.getAttribute("data-state")).toBe("off");
  });

  it("case 3: when snapToGrid === true, button has data-state='on'", () => {
    act(() => { useStore.setState({ snapToGrid: true }); });
    render(<SnapToGridButton />);
    const btn = screen.getByRole("button");
    expect(btn.getAttribute("data-state")).toBe("on");
  });

  it("case 4: clicking the button toggles snapToGrid in the store", () => {
    act(() => { useStore.setState({ snapToGrid: false }); });
    render(<SnapToGridButton />);
    const btn = screen.getByRole("button");
    fireEvent.click(btn);
    expect(useStore.getState().snapToGrid).toBe(true);
    // Click again — back to false
    fireEvent.click(btn);
    expect(useStore.getState().snapToGrid).toBe(false);
  });

  it("case 5: button renders an SVG icon (Grid lucide icon)", () => {
    render(<SnapToGridButton />);
    const btn = screen.getByRole("button");
    // lucide-react renders an SVG inside the button
    const svg = btn.querySelector("svg");
    expect(svg).not.toBeNull();
  });
});
