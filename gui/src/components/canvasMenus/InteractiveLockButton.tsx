// InteractiveLockButton.tsx — Canvas-overlay toggle for interactive lock (Phase 65 Plan 13)
//
// Renders a small icon button in the top-right canvas overlay stack.
// Reads/sets `interactiveLocked` from the store via stable primitive selectors.
// Active state: colored background (bg-primary text-primary-foreground).
// Mirrors SnapToGridButton.tsx pattern — single Lock icon, bg swap conveys state.

import { Lock } from "lucide-react";
import useStore from "../../store/useStore";
import { setPreference } from "../../lib/preferences";

export default function InteractiveLockButton() {
  // Phase 72 Preferences — lock state is canonical in user-global prefs
  // (`editor.interactiveLock`). Read the runtime mirror from useStore; WRITE
  // through setPreference so the Preferences dialog stays consistent.
  const interactiveLocked = useStore((s) => s.interactiveLocked);

  return (
    <button
      aria-label="Lock canvas interactions"
      aria-pressed={interactiveLocked}
      data-state={interactiveLocked ? "on" : "off"}
      title={interactiveLocked ? "Unlock canvas interactions" : "Lock canvas interactions"}
      onClick={() => setPreference("editor", "interactiveLock", !interactiveLocked)}
      className={
        "flex items-center justify-center w-8 h-8 rounded border transition-colors " +
        (interactiveLocked
          ? "bg-primary text-primary-foreground border-primary"
          : "bg-background text-foreground border-border hover:bg-accent hover:text-accent-foreground")
      }
    >
      <Lock className="h-4 w-4" />
    </button>
  );
}
