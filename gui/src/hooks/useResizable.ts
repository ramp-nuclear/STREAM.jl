import { useState, useCallback, useRef } from "react";

interface UseResizableOptions {
  direction: "left" | "right";
  minWidth: number;
  maxWidth: number;
  defaultWidth: number;
}

interface UseResizableReturn {
  width: number;
  onMouseDown: (e: React.MouseEvent) => void;
}

/**
 * Custom hook for panel drag-to-resize.
 *
 * @param direction - "left" means panel is on the left (drag handle on right edge),
 *                    "right" means panel is on the right (drag handle on left edge).
 */
export function useResizable({
  direction,
  minWidth,
  maxWidth,
  defaultWidth,
}: UseResizableOptions): UseResizableReturn {
  const [width, setWidth] = useState(defaultWidth);
  const startXRef = useRef(0);
  const startWidthRef = useRef(0);

  const onMouseDown = useCallback(
    (e: React.MouseEvent) => {
      e.preventDefault();
      startXRef.current = e.clientX;
      startWidthRef.current = width;

      const onMouseMove = (moveEvent: MouseEvent) => {
        const deltaX = moveEvent.clientX - startXRef.current;
        const newWidth =
          direction === "left"
            ? startWidthRef.current + deltaX
            : startWidthRef.current - deltaX;
        setWidth(Math.min(maxWidth, Math.max(minWidth, newWidth)));
      };

      const onMouseUp = () => {
        document.removeEventListener("mousemove", onMouseMove);
        document.removeEventListener("mouseup", onMouseUp);
      };

      // Attach to document to avoid mouse-escape leak
      document.addEventListener("mousemove", onMouseMove);
      document.addEventListener("mouseup", onMouseUp);
    },
    [direction, minWidth, maxWidth, width],
  );

  return { width, onMouseDown };
}
