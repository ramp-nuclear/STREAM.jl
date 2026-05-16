import { useCallback, useEffect, useRef, useState } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";

/**
 * Reactive boolean reflecting whether the Tauri main window is currently
 * maximized. Used by WindowControls to swap the Maximize2 ↔ Minimize2 icon
 * on the Windows/Linux platform branch.
 *
 * Implementation notes:
 * - Mirrors the App.tsx `onCloseRequested` listener-cleanup pattern (S5):
 *   `active` flag + `unlistenRef` to survive React Strict Mode's
 *   double-effect-invocation without leaking listeners.
 * - Wraps every Tauri call in try/catch so vitest (no real IPC bridge)
 *   renders the hook as a stable `false` instead of throwing.
 * - Uses event-driven `onResized` (NOT setInterval polling) per Pitfall 3
 *   in 67-RESEARCH.md — `setInterval` + `isMaximized()` leaks memory on
 *   macOS per Tauri issue #13199.
 */
export function useWindowMaximized(): boolean {
  const [isMax, setIsMax] = useState<boolean>(false);
  const unlistenRef = useRef<(() => void) | null>(null);

  const refresh = useCallback(async () => {
    try {
      const v = await getCurrentWindow().isMaximized();
      setIsMax(v);
    } catch {
      // Non-Tauri env (vitest) — leave default false
    }
  }, []);

  useEffect(() => {
    let active = true;

    // Seed initial state (Promise — fire-and-forget)
    void refresh();

    // Subscribe to resize events; idempotent setState debounces the
    // isMaximized() reads through React's equality check.
    getCurrentWindow()
      .onResized(() => {
        void refresh();
      })
      .then((fn) => {
        if (!active) {
          fn(); // effect already cleaned up — unlisten immediately
        } else {
          unlistenRef.current = fn;
        }
      })
      .catch(() => {
        // Non-Tauri env (vitest) — no listener to attach
      });

    return () => {
      active = false;
      unlistenRef.current?.();
      unlistenRef.current = null;
    };
  }, [refresh]);

  return isMax;
}
