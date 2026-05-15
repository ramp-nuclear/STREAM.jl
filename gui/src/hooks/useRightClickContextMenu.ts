import { useState, useEffect, useCallback, useRef } from "react";
import type { Node, Edge } from "@xyflow/react";

// D-12: 5px Manhattan-distance + 250ms time threshold for pan-vs-menu disambiguation
const MANHATTAN_THRESHOLD_PX = 5;
const TIME_THRESHOLD_MS = 250;

export interface ContextMenuState {
  kind: "pane" | "node" | "edge" | null;
  targetId: string | null; // node id or edge id; null for pane
  screenX: number;
  screenY: number;
}

const INITIAL_STATE: ContextMenuState = {
  kind: null,
  targetId: null,
  screenX: 0,
  screenY: 0,
};

interface GestureRef {
  downX: number;
  downY: number;
  downT: number;
  upX: number;
  upY: number;
  upT: number;
}

export function useRightClickContextMenu(): {
  state: ContextMenuState;
  close: () => void;
  onPaneContextMenu: (event: MouseEvent | React.MouseEvent) => void;
  onNodeContextMenu: (event: React.MouseEvent, node: Node) => void;
  onEdgeContextMenu: (event: React.MouseEvent, edge: Edge) => void;
} {
  const [state, setState] = useState<ContextMenuState>(INITIAL_STATE);

  // Track the right-button gesture (mousedown → mouseup) for disambiguation
  const gestureRef = useRef<GestureRef | null>(null);

  // Helper: returns true iff the last gesture qualifies as a quick-short right-click
  // (not a pan). Reads gestureRef directly so it always sees the latest value.
  //
  // First-interaction fallback (UAT 2026-05-15): return TRUE when gestureRef is
  // null. The previous "null → false" rule caused the very first right-click on
  // the canvas to silently no-op when ReactFlow's pane mousedown handler swallowed
  // the bubble phase. A right-click with no prior mousedown is, by definition,
  // not a pan gesture — so treating it as quick-short is safe.
  const isQuickShortGesture = useCallback((): boolean => {
    const g = gestureRef.current;
    if (!g) return true;
    const manhattan = Math.abs(g.upX - g.downX) + Math.abs(g.upY - g.downY);
    const elapsed = g.upT - g.downT;
    return manhattan <= MANHATTAN_THRESHOLD_PX && elapsed <= TIME_THRESHOLD_MS;
  }, []);

  useEffect(() => {
    // Listener 1: mousedown (bubble phase) — record right-button press coords.
    // Seed upX/Y/T to the down values so a contextmenu-without-mouseup (e.g.,
    // mousedown→contextmenu with no mouseup) computes zero distance and zero
    // duration → qualifies as quick-short.
    const handleMouseDown = (event: MouseEvent) => {
      if (event.button !== 2) return;
      gestureRef.current = {
        downX: event.clientX,
        downY: event.clientY,
        downT: event.timeStamp,
        upX: event.clientX,
        upY: event.clientY,
        upT: event.timeStamp,
      };
    };

    // Listener 2: mouseup (bubble phase) — update up coords when the right button
    // is released. A new mousedown overwrites the ref (handles orphan mousedowns).
    const handleMouseUp = (event: MouseEvent) => {
      if (event.button !== 2) return;
      if (!gestureRef.current) return;
      gestureRef.current.upX = event.clientX;
      gestureRef.current.upY = event.clientY;
      gestureRef.current.upT = event.timeStamp;
    };

    // Listener 3: contextmenu (CAPTURE phase — runs BEFORE React's delegated
    // handlers). If the preceding gesture was a drag (exceeded threshold), call
    // preventDefault() to suppress the OS-native context menu. This resolves
    // checker B2: ReactFlow forwards onPaneContextMenu regardless of pan state,
    // and the browser may also fire a native contextmenu after a right-drag on
    // Linux/X11/Windows.
    const handleContextMenu = (event: MouseEvent) => {
      if (gestureRef.current === null) return;
      if (!isQuickShortGesture()) {
        event.preventDefault();
      }
    };

    // Capture phase for ALL three. ReactFlow's pane handler can stopPropagation
    // on right-button mousedown during pan handling; using bubble phase meant the
    // very first right-click after page load could miss the listener (gestureRef
    // stayed null). Capture phase runs before any descendant can stop the event.
    window.addEventListener("mousedown", handleMouseDown, true);
    window.addEventListener("mouseup", handleMouseUp, true);
    window.addEventListener("contextmenu", handleContextMenu, true);

    return () => {
      window.removeEventListener("mousedown", handleMouseDown, true);
      window.removeEventListener("mouseup", handleMouseUp, true);
      window.removeEventListener("contextmenu", handleContextMenu, true);
    };
  }, [isQuickShortGesture]);

  // ReactFlow handler: pane (empty canvas) right-click
  const onPaneContextMenu = useCallback(
    (event: MouseEvent | React.MouseEvent) => {
      // Belt-and-suspenders: also call preventDefault on the React synthetic event.
      // The window capture listener already handled the native contextmenu event,
      // but the React synthetic event is separate.
      if (typeof (event as React.MouseEvent).preventDefault === "function") {
        (event as React.MouseEvent).preventDefault();
      }
      if (!isQuickShortGesture()) return;
      setState({
        kind: "pane",
        targetId: null,
        screenX: (event as MouseEvent).clientX,
        screenY: (event as MouseEvent).clientY,
      });
    },
    [isQuickShortGesture],
  );

  // ReactFlow handler: node right-click
  const onNodeContextMenu = useCallback(
    (event: React.MouseEvent, node: Node) => {
      event.preventDefault();
      if (!isQuickShortGesture()) return;
      setState({
        kind: "node",
        targetId: node.id,
        screenX: event.clientX,
        screenY: event.clientY,
      });
    },
    [isQuickShortGesture],
  );

  // ReactFlow handler: edge right-click
  const onEdgeContextMenu = useCallback(
    (event: React.MouseEvent, edge: Edge) => {
      event.preventDefault();
      if (!isQuickShortGesture()) return;
      setState({
        kind: "edge",
        targetId: edge.id,
        screenX: event.clientX,
        screenY: event.clientY,
      });
    },
    [isQuickShortGesture],
  );

  // Close the menu — Plan 05 will also attach outside-click and Esc handlers,
  // but close() is exposed here for manual dismissal.
  const close = useCallback(() => {
    setState(INITIAL_STATE);
  }, []);

  return { state, close, onPaneContextMenu, onNodeContextMenu, onEdgeContextMenu };
}
