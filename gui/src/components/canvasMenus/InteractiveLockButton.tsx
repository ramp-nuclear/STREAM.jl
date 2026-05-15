// InteractiveLockButton.tsx — Canvas-overlay toggle for interactive lock (Phase 65 Plan 13)
//
// Renders a small icon button in the top-right canvas overlay stack.
// Reads/sets `interactiveLocked` from the store via stable primitive selectors.
// Active state: colored background (bg-primary text-primary-foreground).
// Mirrors SnapToGridButton.tsx pattern — single Lock icon, bg swap conveys state.

import { Lock } from "lucide-react";
import useStore from "../../store/useStore";

export default function InteractiveLockButton() {
  const interactiveLocked = useStore((s) => s.interactiveLocked);
  const setInteractiveLocked = useStore((s) => s.setInteractiveLocked);

  return (
    <button
      aria-label="Lock canvas interactions"
      aria-pressed={interactiveLocked}
      data-state={interactiveLocked ? "on" : "off"}
      title={interactiveLocked ? "Unlock canvas interactions" : "Lock canvas interactions"}
      onClick={() => setInteractiveLocked(!interactiveLocked)}
      className={
        "flex items-center justify-center w-8 h-8 rounded border shadow-sm transition-colors " +
        (interactiveLocked
          ? "bg-primary text-primary-foreground border-primary"
          : "bg-background text-foreground border-border hover:bg-accent hover:text-accent-foreground")
      }
    >
      <Lock className="h-4 w-4" />
    </button>
  );
}
