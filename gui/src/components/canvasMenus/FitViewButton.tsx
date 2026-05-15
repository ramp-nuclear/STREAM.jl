// FitViewButton.tsx — Canvas-overlay action for fit-to-view (Phase 65 Plan 13)
//
// Renders a small icon button in the top-right canvas overlay stack.
// Calls useReactFlow().fitView() on click. Always rendered in the inactive style.

import { Maximize } from "lucide-react";
import { useReactFlow } from "@xyflow/react";

export default function FitViewButton() {
  const { fitView } = useReactFlow();

  return (
    <button
      aria-label="Fit view"
      title="Fit canvas to view"
      onClick={() => fitView()}
      className={
        "flex items-center justify-center w-8 h-8 rounded border shadow-sm transition-colors " +
        "bg-background text-foreground border-border hover:bg-accent hover:text-accent-foreground"
      }
    >
      <Maximize className="h-4 w-4" />
    </button>
  );
}
