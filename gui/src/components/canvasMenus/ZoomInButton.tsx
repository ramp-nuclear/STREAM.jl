// ZoomInButton.tsx — Canvas-overlay action for zoom-in (Phase 65 Plan 13)
//
// Renders a small icon button in the top-right canvas overlay stack.
// Calls useReactFlow().zoomIn() on click. Always rendered in the inactive style
// (it's an action button, not a toggle).

import { ZoomIn } from "lucide-react";
import { useReactFlow } from "@xyflow/react";

export default function ZoomInButton() {
  const { zoomIn } = useReactFlow();

  return (
    <button
      aria-label="Zoom in"
      title="Zoom in"
      onClick={() => zoomIn()}
      className={
        "flex items-center justify-center w-8 h-8 rounded border transition-colors " +
        "bg-background text-foreground border-border hover:bg-accent hover:text-accent-foreground"
      }
    >
      <ZoomIn className="h-4 w-4" />
    </button>
  );
}
