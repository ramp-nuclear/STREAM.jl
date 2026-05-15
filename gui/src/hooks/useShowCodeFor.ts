/**
 * useShowCodeFor — Phase 66 Plan 03
 *
 * Window-level listener for the `stream:show-code-for` CustomEvent. The
 * dispatcher already exists at `gui/src/components/canvasMenus/NodeContextMenu.tsx:39-41`
 * (Phase 65 D-14): right-clicking a canvas StreamNode → "Show generated
 * Julia code" opens the bottom panel and fires this event with the node's id.
 *
 * Phase 66 is the CONSUMER. This hook MUST be mounted at app root (App.tsx)
 * so the listener is installed regardless of whether `CodePreview` is
 * currently mounted (BottomPanel.tsx short-circuits `CodePreview` when the
 * bottom panel is closed — see Pitfall 2 in 66-RESEARCH.md). On event:
 *
 *   1. Normalize detail.nodeId / detail.nodeIds into a single string[] (xor).
 *   2. If empty, ignore.
 *   3. If bottom panel is closed, open it (matches NodeContextMenu's
 *      synchronous open-then-dispatch pattern at line 36-37).
 *   4. Write the ids to `useStore.pendingShowCodeFor`. Plan 04's
 *      CodePreview consumer reads this on mount/update, scrolls to the
 *      matching sub-block, and flashes it for 1.5s.
 *
 * Cleanup uses the same handler reference cast to `EventListener` so
 * `removeEventListener` succeeds (Pattern 5 in 66-RESEARCH.md — without
 * the cast, TypeScript can synthesize a different reference and cleanup
 * silently fails on HMR re-mount).
 */

import { useEffect } from "react";
import useStore from "../store/useStore";

interface ShowCodeForDetail {
  nodeId?: string;
  nodeIds?: string[];
}

declare global {
  interface WindowEventMap {
    "stream:show-code-for": CustomEvent<ShowCodeForDetail>;
  }
}

export function useShowCodeFor(): void {
  useEffect(() => {
    const handler = (e: Event) => {
      const ce = e as CustomEvent<ShowCodeForDetail>;
      const ids =
        ce.detail?.nodeIds ?? (ce.detail?.nodeId ? [ce.detail.nodeId] : []);
      if (ids.length === 0) return;

      // Mirror NodeContextMenu.tsx:36-37: open-if-closed via toggleBottomPanel.
      // No setBottomPanelOpen setter exists; the toggle is the established
      // convention.
      if (useStore.getState().bottomPanelOpen === false) {
        useStore.getState().toggleBottomPanel();
      }

      useStore.getState().setPendingShowCodeFor(ids);
    };
    window.addEventListener(
      "stream:show-code-for",
      handler as EventListener,
    );
    return () =>
      window.removeEventListener(
        "stream:show-code-for",
        handler as EventListener,
      );
  }, []);
}
