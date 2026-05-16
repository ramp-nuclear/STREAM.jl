import { useEffect, useState } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { platform } from "@tauri-apps/plugin-os";
import { Minus, Maximize2, Minimize2, X } from "lucide-react";
import { Button } from "./ui/button";
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
 * `platform()` from `@tauri-apps/plugin-os` is synchronous. The non-Tauri
 * vitest environment makes it throw — we fall back to the Windows/Linux
 * variant so the component still renders for tests.
 */
export default function WindowControls() {
  const [plat, setPlat] = useState<Platform>(null);
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
  return (
    <div className="flex items-stretch h-full">
      <Button
        variant="ghost"
        size="icon"
        aria-label="Minimize window"
        onClick={onMin}
        className="rounded-none h-full w-10 hover:bg-muted-foreground/20"
      >
        <Minus className="h-4 w-4" />
      </Button>
      <Button
        variant="ghost"
        size="icon"
        aria-label="Toggle maximize"
        onClick={onMax}
        className="rounded-none h-full w-10 hover:bg-muted-foreground/20"
      >
        {isMax ? (
          <Minimize2 className="h-4 w-4" />
        ) : (
          <Maximize2 className="h-4 w-4" />
        )}
      </Button>
      <Button
        variant="ghost"
        size="icon"
        aria-label="Close window"
        onClick={onClose}
        className="rounded-none h-full w-10 hover:bg-red-600 hover:text-white dark:hover:bg-red-600 dark:hover:text-white"
      >
        <X className="h-4 w-4" />
      </Button>
    </div>
  );
}
