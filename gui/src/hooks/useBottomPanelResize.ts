import { useCallback, useRef } from "react";
import useStore from "@/store/useStore";

/**
 * Custom hook for bottom panel vertical drag-to-resize.
 *
 * Reads and writes `bottomPanelHeight` in the Zustand store directly via
 * `useStore.getState()` (not a selector) since updates happen inside event
 * handlers, not the React render cycle.
 *
 * Height is clamped between 120px (minimum usable) and 60% of viewport height
 * (D-03). The max is recalculated on each mousemove to handle viewport resize.
 */
export function useBottomPanelResize() {
  const startYRef = useRef(0);
  const startHeightRef = useRef(0);

  const onMouseDown = useCallback((e: React.MouseEvent) => {
    e.preventDefault();
    const height = useStore.getState().bottomPanelHeight;
    startYRef.current = e.clientY;
    startHeightRef.current = height;

    const onMouseMove = (moveEvent: MouseEvent) => {
      const deltaY = startYRef.current - moveEvent.clientY; // drag up = taller
      const maxHeight = Math.floor(window.innerHeight * 0.6);
      const newHeight = Math.min(maxHeight, Math.max(120, startHeightRef.current + deltaY));
      useStore.getState().setBottomPanelHeight(newHeight);
    };

    const onMouseUp = () => {
      document.removeEventListener("mousemove", onMouseMove);
      document.removeEventListener("mouseup", onMouseUp);
    };

    document.addEventListener("mousemove", onMouseMove);
    document.addEventListener("mouseup", onMouseUp);
  }, []);

  return { onMouseDown };
}
