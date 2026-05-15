// ZoomOutButton.tsx — Canvas-overlay action for zoom-out (Phase 65 Plan 13)
//
// Renders a small icon button in the top-right canvas overlay stack.
// Calls useReactFlow().zoomOut() on click. Always rendered in the inactive style.

import { ZoomOut } from "lucide-react";
import { useReactFlow } from "@xyflow/react";

export default function ZoomOutButton() {
  const { zoomOut } = useReactFlow();

  return (
    <button
      aria-label="Zoom out"
      title="Zoom out"
      onClick={() => zoomOut()}
      className={
        "flex items-center justify-center w-8 h-8 rounded border shadow-sm transition-colors " +
        "bg-background text-foreground border-border hover:bg-accent hover:text-accent-foreground"
      }
    >
      <ZoomOut className="h-4 w-4" />
    </button>
  );
}
