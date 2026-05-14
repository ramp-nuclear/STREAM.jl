// SnapToGridButton.tsx — Canvas-overlay toggle for snap-to-grid (Phase 65 D-07/D-10)
//
// Renders a small icon button in the top-right canvas overlay stack.
// Reads/sets `snapToGrid` from the store via stable primitive selectors.
// Active state: colored background (bg-primary text-primary-foreground).
// Inactive state: ghost / neutral background.
//
// Render host: absolutely-positioned div (NOT Panel from @xyflow/react) per W9 lock.

import { Grid } from "lucide-react";
import useStore from "../../store/useStore";

export default function SnapToGridButton() {
  const snapToGrid = useStore((s) => s.snapToGrid);
  const setSnapToGrid = useStore((s) => s.setSnapToGrid);

  return (
    <button
      aria-label="Snap to grid"
      aria-pressed={snapToGrid}
      data-state={snapToGrid ? "on" : "off"}
      title="Snap to grid (16px)"
      onClick={() => setSnapToGrid(!snapToGrid)}
      className={
        "flex items-center justify-center w-8 h-8 rounded border shadow-sm transition-colors " +
        (snapToGrid
          ? "bg-primary text-primary-foreground border-primary"
          : "bg-background text-foreground border-border hover:bg-accent hover:text-accent-foreground")
      }
    >
      <Grid className="h-4 w-4" />
    </button>
  );
}
