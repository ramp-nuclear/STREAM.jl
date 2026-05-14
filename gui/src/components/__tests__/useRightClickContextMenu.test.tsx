// @vitest-environment happy-dom
//
// Phase 65 Plan 03 — useRightClickContextMenu hook unit tests
// Covers the 8 behavior cases from the plan's <behavior> spec:
//   1. Initial state is null
//   2. Quick-short right-click on pane → state.kind === 'pane'
//   3. Slow right-click (over time threshold) → state stays null
//   4. Right-drag pan (over distance threshold) → contextmenu suppressed
//   5. Right-click on node → state.kind === 'node'
//   6. Right-click on edge → state.kind === 'edge'
//   7. close() resets state to null
//   8. Defensive orphan mousedown — second gesture works correctly
//   9. Listener cleanup — no preventDefault after unmount

import {
  describe,
  it,
  expect,
  afterEach,
  vi,
  type Mock,
} from "vitest";
import { renderHook, act } from "@testing-library/react";
import type { Node, Edge } from "@xyflow/react";
import { useRightClickContextMenu } from "../../hooks/useRightClickContextMenu";

// Helpers to dispatch synthetic mouse events on the window
function dispatchMouseDown(x: number, y: number, t: number) {
  const event = new MouseEvent("mousedown", {
    bubbles: true,
    cancelable: true,
    button: 2,
    clientX: x,
    clientY: y,
  });
  // Override timeStamp via Object.defineProperty (MouseEventInit ignores it in jsdom)
  Object.defineProperty(event, "timeStamp", { value: t });
  window.dispatchEvent(event);
}

function dispatchMouseUp(x: number, y: number, t: number) {
  const event = new MouseEvent("mouseup", {
    bubbles: true,
    cancelable: true,
    button: 2,
    clientX: x,
    clientY: y,
  });
  Object.defineProperty(event, "timeStamp", { value: t });
  window.dispatchEvent(event);
}

function dispatchContextMenu(x: number, y: number): MouseEvent {
  const event = new MouseEvent("contextmenu", {
    bubbles: true,
    cancelable: true,
    clientX: x,
    clientY: y,
  });
  window.dispatchEvent(event);
  return event;
}

// A minimal fake React.MouseEvent for invoking the ReactFlow callbacks
function makeReactMouseEvent(
  x: number,
  y: number,
  t: number,
  preventDefaultFn = vi.fn(),
) {
  return {
    clientX: x,
    clientY: y,
    timeStamp: t,
    preventDefault: preventDefaultFn,
  } as unknown as React.MouseEvent;
}

function makeNode(id: string): Node {
  return {
    id,
    type: "streamNode",
    position: { x: 0, y: 0 },
    data: {},
  } as Node;
}

function makeEdge(id: string): Edge {
  return {
    id,
    source: "n1",
    target: "n2",
  } as Edge;
}

describe("useRightClickContextMenu", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  // Case 1: Initial state
  it("initial state.kind is null", () => {
    const { result, unmount } = renderHook(() => useRightClickContextMenu());
    expect(result.current.state.kind).toBeNull();
    unmount();
  });

  // Case 2: Quick-short right-click on pane
  it("quick-short right-click on pane sets state.kind to 'pane'", () => {
    const { result, unmount } = renderHook(() => useRightClickContextMenu());

    const preventDefaultSpy = vi.fn();

    act(() => {
      dispatchMouseDown(100, 200, 0);
      dispatchMouseUp(102, 201, 120);
      result.current.onPaneContextMenu(makeReactMouseEvent(102, 201, 120, preventDefaultSpy));
    });

    expect(result.current.state.kind).toBe("pane");
    expect(result.current.state.screenX).toBe(102);
    expect(result.current.state.screenY).toBe(201);
    expect(preventDefaultSpy).toHaveBeenCalled();

    unmount();
  });

  // Case 3: Slow right-click (over time threshold) → state stays null
  it("slow right-click (over 250ms time threshold) keeps state null", () => {
    const { result, unmount } = renderHook(() => useRightClickContextMenu());

    const preventDefaultSpy = vi.fn();

    act(() => {
      dispatchMouseDown(100, 200, 0);
      dispatchMouseUp(102, 201, 400); // 400ms > 250ms threshold
      result.current.onPaneContextMenu(makeReactMouseEvent(102, 201, 400, preventDefaultSpy));
    });

    expect(result.current.state.kind).toBeNull();
    // preventDefault still called on the React event (belt-and-suspenders)
    expect(preventDefaultSpy).toHaveBeenCalled();

    unmount();
  });

  // Case 4: Right-drag pan (over distance threshold) → window contextmenu suppressed
  it("right-drag over 5px suppresses the window contextmenu event", () => {
    // Attach a spy BEFORE mounting the hook so it runs AFTER the hook's capture listener
    const controlSpy: Mock = vi.fn();
    const controlListener = (e: MouseEvent) => controlSpy(e.defaultPrevented);
    window.addEventListener("contextmenu", controlListener, false);

    const { result, unmount } = renderHook(() => useRightClickContextMenu());

    act(() => {
      // Manhattan distance = |200-100| + |300-200| = 200 > 5 → drag
      dispatchMouseDown(100, 200, 0);
      dispatchMouseUp(200, 300, 100);
      // Simulate the browser firing contextmenu after right-mouseup
      dispatchContextMenu(200, 300);
    });

    // The hook's capture-phase listener should have called preventDefault BEFORE
    // the control bubble listener fires, so controlSpy should see defaultPrevented = true
    expect(controlSpy).toHaveBeenCalledWith(true);

    // If ReactFlow's onPaneContextMenu was also called, state should stay null
    const preventDefaultSpy = vi.fn();
    act(() => {
      result.current.onPaneContextMenu(makeReactMouseEvent(200, 300, 100, preventDefaultSpy));
    });
    expect(result.current.state.kind).toBeNull();

    window.removeEventListener("contextmenu", controlListener, false);
    unmount();
  });

  // Case 5: Right-click on node
  it("quick right-click on node sets state.kind to 'node' with targetId", () => {
    const { result, unmount } = renderHook(() => useRightClickContextMenu());

    act(() => {
      dispatchMouseDown(50, 60, 0);
      dispatchMouseUp(51, 61, 50);
      result.current.onNodeContextMenu(
        makeReactMouseEvent(51, 61, 50),
        makeNode("n1"),
      );
    });

    expect(result.current.state.kind).toBe("node");
    expect(result.current.state.targetId).toBe("n1");

    unmount();
  });

  // Case 6: Right-click on edge
  it("quick right-click on edge sets state.kind to 'edge' with targetId", () => {
    const { result, unmount } = renderHook(() => useRightClickContextMenu());

    act(() => {
      dispatchMouseDown(50, 60, 0);
      dispatchMouseUp(51, 61, 50);
      result.current.onEdgeContextMenu(
        makeReactMouseEvent(51, 61, 50),
        makeEdge("e1"),
      );
    });

    expect(result.current.state.kind).toBe("edge");
    expect(result.current.state.targetId).toBe("e1");

    unmount();
  });

  // Case 7: close() resets state to null
  it("close() resets state.kind to null", () => {
    const { result, unmount } = renderHook(() => useRightClickContextMenu());

    // First open a menu
    act(() => {
      dispatchMouseDown(50, 60, 0);
      dispatchMouseUp(51, 61, 50);
      result.current.onPaneContextMenu(makeReactMouseEvent(51, 61, 50));
    });
    expect(result.current.state.kind).toBe("pane");

    // Then close it
    act(() => {
      result.current.close();
    });
    expect(result.current.state.kind).toBeNull();

    unmount();
  });

  // Case 8: Defensive — orphan mousedown (no matching mouseup)
  it("orphan mousedown followed by fresh gesture succeeds correctly", () => {
    const { result, unmount } = renderHook(() => useRightClickContextMenu());

    act(() => {
      // First mousedown — no mouseup follows (orphan)
      dispatchMouseDown(0, 0, 0);
      // Second gesture: mousedown at 500,500; mouseup at 501,501 (quick short)
      dispatchMouseDown(500, 500, 200);
      dispatchMouseUp(501, 501, 210);
      result.current.onPaneContextMenu(makeReactMouseEvent(501, 501, 210));
    });

    // Second gesture is quick-short → menu should open
    expect(result.current.state.kind).toBe("pane");

    unmount();
  });

  // Case 9: Listener cleanup after unmount
  it("after unmount, window contextmenu event is not suppressed", () => {
    const { unmount } = renderHook(() => useRightClickContextMenu());

    // Do a drag so the hook would suppress a contextmenu event
    dispatchMouseDown(100, 200, 0);
    dispatchMouseUp(200, 300, 100);

    // Now unmount
    unmount();

    // Attach a spy AFTER unmount
    const controlSpy: Mock = vi.fn();
    const controlListener = (e: MouseEvent) => controlSpy(e.defaultPrevented);
    window.addEventListener("contextmenu", controlListener, false);

    // Dispatch a contextmenu event — the hook's listener should have been removed
    dispatchContextMenu(200, 300);

    // Since the hook's capture listener was removed, defaultPrevented should be false
    expect(controlSpy).toHaveBeenCalledWith(false);

    window.removeEventListener("contextmenu", controlListener, false);
  });

  // Quick-click on pane context menu also suppresses native contextmenu (defaultPrevented=false for quick click)
  it("quick right-click does NOT suppress the window contextmenu event (defaultPrevented=false)", () => {
    const controlSpy: Mock = vi.fn();
    const controlListener = (e: MouseEvent) => controlSpy(e.defaultPrevented);
    window.addEventListener("contextmenu", controlListener, false);

    const { unmount } = renderHook(() => useRightClickContextMenu());

    act(() => {
      dispatchMouseDown(100, 200, 0);
      dispatchMouseUp(102, 201, 120); // Quick-short
      dispatchContextMenu(102, 201);
    });

    // For quick-short gesture, hook should NOT call preventDefault on the window event
    expect(controlSpy).toHaveBeenCalledWith(false);

    window.removeEventListener("contextmenu", controlListener, false);
    unmount();
  });
});
