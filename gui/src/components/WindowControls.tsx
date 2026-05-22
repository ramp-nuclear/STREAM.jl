import { useEffect, useRef, useState } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { listen } from "@tauri-apps/api/event";
import { platform } from "@tauri-apps/plugin-os";
import { Minus, Maximize2, Minimize2, X } from "lucide-react";
import { Button } from "./ui/button";
import { Tooltip, TooltipContent, TooltipTrigger } from "./ui/tooltip";
import { useWindowMaximized } from "../hooks/useWindowMaximized";

type Platform = "macos" | "windows" | "linux" | null;

/**
 * Platform-branched window controls (D-14, D-15).
 *
 * - macOS: 3 traffic-light circles in Apple HIG L→R order — Close (red
 *   `#ff5f57`), Minimize (yellow `#ffbd2e`), Maximize (green `#28c840`).
 * - Windows/Linux: 3 shadcn ghost buttons with Lucide icons in
 *   L→R order — Minimize, Maximize/Restore, Close (destructive hover).
 *
 * Snap-layout hover bridge (Phase 67 round 2, Windows-only):
 * The transparent overlay HWND installed by `src-tauri/src/snap_layout.rs`
 * sits on top of the React Maximize button, so the browser's `:hover` never
 * fires while the cursor is over the icon. The overlay's WndProc emits
 * `snap-layout://hover-enter` and `snap-layout://hover-leave` Tauri events
 * on its own WM_MOUSEMOVE / WM_MOUSELEAVE; we subscribe here and mirror
 * the state into a `snapHover` boolean that applies the same hover bg as
 * if it were CSS-hovered.
 *
 * `platform()` from `@tauri-apps/plugin-os` is synchronous. The non-Tauri
 * vitest environment makes it throw — we fall back to the Windows/Linux
 * variant so the component still renders for tests.
 */
export default function WindowControls() {
  const [plat, setPlat] = useState<Platform>(null);
  const [snapHover, setSnapHover] = useState(false);
  const isMax = useWindowMaximized();

  useEffect(() => {
    try {
      const p = platform();
      setPlat(p === "macos" ? "macos" : p === "windows" ? "windows" : "linux");
    } catch {
      // Non-Tauri env (vitest) — render Windows/Linux variant
      setPlat("linux");
    }
  }, []);

  // Fire-and-forget Tauri IPC (Pattern S4 — `void` prefix matches App.tsx style).
  const w = getCurrentWindow();
  const onMin = () => void w.minimize();
  const onMax = () => void w.toggleMaximize();
  const onClose = () => void w.close();

  // Snap-layout overlay bridge — Windows only. Three Tauri events from the
  // native overlay HWND (src-tauri/src/snap_layout.rs):
  //   hover-enter / hover-leave → toggle visual hover-state on the React
  //     Maximize button so it looks responsive even though the OS overlay
  //     ate the browser :hover.
  //   click → call onMax(). Clicks on the overlay are routed by Windows as
  //     non-client clicks to the OVERLAY HWND (because HTMAXBUTTON), not
  //     the parent webview — so the React onClick handler on the Maximize
  //     button never fires from a real click. The overlay emits this event
  //     and we treat it as the click.
  // Mirrors the App.tsx listener-cleanup pattern (S5): `active` flag + ref
  // to survive Strict Mode double-invocation without leaking listeners.
  const unlistenEnterRef = useRef<(() => void) | null>(null);
  const unlistenLeaveRef = useRef<(() => void) | null>(null);
  const unlistenClickRef = useRef<(() => void) | null>(null);
  useEffect(() => {
    if (plat !== "windows") return;
    let active = true;
    listen("snap-layout://hover-enter", () => setSnapHover(true))
      .then((fn) => {
        if (!active) fn();
        else unlistenEnterRef.current = fn;
      })
      .catch(() => {
        // Non-Tauri env — no listener to attach
      });
    listen("snap-layout://hover-leave", () => setSnapHover(false))
      .then((fn) => {
        if (!active) fn();
        else unlistenLeaveRef.current = fn;
      })
      .catch(() => {});
    listen("snap-layout://click", () => onMax())
      .then((fn) => {
        if (!active) fn();
        else unlistenClickRef.current = fn;
      })
      .catch(() => {});
    return () => {
      active = false;
      unlistenEnterRef.current?.();
      unlistenLeaveRef.current?.();
      unlistenClickRef.current?.();
      unlistenEnterRef.current = null;
      unlistenLeaveRef.current = null;
      unlistenClickRef.current = null;
    };
    // onMax is a stable inline closure capturing the singleton window — safe
    // to omit from deps; including it would re-subscribe every render.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [plat]);

  if (plat === "macos") {
    return (
      <div className="flex items-center gap-2 px-3 group">
        <button
          aria-label="Close window"
          onClick={onClose}
          className="w-3 h-3 rounded-full bg-[#ff5f57]/40 group-hover:bg-[#ff5f57] transition-colors"
        />
        <button
          aria-label="Minimize window"
          onClick={onMin}
          className="w-3 h-3 rounded-full bg-[#ffbd2e]/40 group-hover:bg-[#ffbd2e] transition-colors"
        />
        <button
          aria-label="Toggle maximize"
          onClick={onMax}
          className="w-3 h-3 rounded-full bg-[#28c840]/40 group-hover:bg-[#28c840] transition-colors"
        />
      </div>
    );
  }

  // Windows / Linux (also the vitest fallback when platform() throws or plat
  // is still null pre-mount — render Windows/Linux variant pre-emptively).
  //
  // Phase 72 (help-system tooltip discipline) — each button is icon-only, so
  // a Tooltip with the action label is required. Triggers use `asChild` so
  // the existing <Button> is the trigger surface (no extra wrapper).
  return (
    <div className="flex items-stretch h-full">
      <Tooltip>
        <TooltipTrigger asChild>
          <Button
            variant="ghost"
            size="icon"
            aria-label="Minimize window"
            onClick={onMin}
            className="rounded-none h-full w-10 hover:bg-muted-foreground/20"
          >
            <Minus className="h-4 w-4" />
          </Button>
        </TooltipTrigger>
        <TooltipContent side="bottom">Minimize</TooltipContent>
      </Tooltip>
      <Tooltip>
        <TooltipTrigger asChild>
          <Button
            variant="ghost"
            size="icon"
            aria-label="Toggle maximize"
            onClick={onMax}
            className={
              "rounded-none h-full w-10 hover:bg-muted-foreground/20" +
              (snapHover ? " bg-muted-foreground/20" : "")
            }
          >
            {isMax ? (
              <Minimize2 className="h-4 w-4" />
            ) : (
              <Maximize2 className="h-4 w-4" />
            )}
          </Button>
        </TooltipTrigger>
        <TooltipContent side="bottom">
          {isMax ? "Restore" : "Maximize"}
        </TooltipContent>
      </Tooltip>
      <Tooltip>
        <TooltipTrigger asChild>
          <Button
            variant="ghost"
            size="icon"
            aria-label="Close window"
            onClick={onClose}
            className="rounded-none h-full w-10 hover:bg-red-600 hover:text-white dark:hover:bg-red-600 dark:hover:text-white"
          >
            <X className="h-4 w-4" />
          </Button>
        </TooltipTrigger>
        <TooltipContent side="bottom">Close</TooltipContent>
      </Tooltip>
    </div>
  );
}
