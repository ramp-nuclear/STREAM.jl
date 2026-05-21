/**
 * ValidationStatusBar — Phase 71 Plan 10
 *
 * Always-visible 22px statusbar strip mounted under BottomPanel (D-02).
 * Shows three count chips: errors / warnings / info.
 *
 * UX contract (D-02, D-03, D-05):
 *   - Always rendered; never collapsible.
 *   - Each chip: icon + count. When count === 0 the chip dims to opacity-60.
 *   - Click a chip → opens BottomPanel, switches to Validation tab, dispatches
 *     'stream:validation-filter' CustomEvent so ValidationPanel pre-filters by
 *     that severity (D-05 locked decision — dispatch is REQUIRED).
 *   - 0→N pulse: when error count rises from 0 to N, the error chip plays
 *     'pulse-once' CSS animation (~600ms, single shot). D-03: panel does NOT
 *     auto-open on count change — only the chip pulses.
 */

import { useEffect, useMemo, useRef, useState } from "react";
import { AlertCircle, AlertTriangle, Info } from "lucide-react";
import { Button } from "./ui/button";
import useStore from "../store/useStore";

export default function ValidationStatusBar() {
  const validationResults = useStore((s) => s.validationResults);

  // Derive counts inline via useMemo — avoids derived-state race on every render.
  const errorCount = useMemo(
    () => validationResults.filter((r) => r.severity === "error").length,
    [validationResults],
  );
  const warningCount = useMemo(
    () => validationResults.filter((r) => r.severity === "warning").length,
    [validationResults],
  );
  const infoCount = useMemo(
    () => validationResults.filter((r) => r.severity === "info").length,
    [validationResults],
  );

  // 0→N pulse logic (D-03): track previous error count via ref; on a 0→N
  // transition add the CSS class for 700ms then clear it.
  const prevErrorCountRef = useRef<number>(errorCount);
  const [pulseActive, setPulseActive] = useState(false);

  useEffect(() => {
    const prev = prevErrorCountRef.current;
    if (prev === 0 && errorCount > 0) {
      setPulseActive(true);
      const id = window.setTimeout(() => setPulseActive(false), 700);
      return () => window.clearTimeout(id);
    }
  }, [errorCount]);

  // Update previous ref AFTER the effect runs (mirrors each render).
  useEffect(() => {
    prevErrorCountRef.current = errorCount;
  });

  // Chip click handler factory — open panel + dispatch severity filter (D-05).
  function handleChipClick(severity: "error" | "warning" | "info") {
    useStore.setState({ bottomPanelOpen: true, activeBottomTab: "validation" });
    window.dispatchEvent(
      new CustomEvent("stream:validation-filter", {
        detail: { severity },
      }),
    );
  }

  return (
    <div
      className="flex flex-row items-center justify-between px-2 border-t bg-chrome shrink-0"
      style={{ height: 22, fontSize: 11 }}
      aria-label="Validation status"
    >
      {/* Left side: three chips */}
      <div className="flex flex-row items-center gap-0.5">
        {/* Error chip */}
        <Button
          variant="ghost"
          size="sm"
          className={
            "h-5 w-auto px-1.5 gap-1 text-[11px] rounded-sm " +
            (errorCount === 0 ? "opacity-60" : "") +
            (pulseActive ? " pulse-once" : "")
          }
          onClick={() => handleChipClick("error")}
          aria-label={`${errorCount} errors`}
          title={`${errorCount} error${errorCount === 1 ? "" : "s"} — click to filter`}
        >
          <AlertCircle className="h-3 w-3 shrink-0" />
          <span>{errorCount}</span>
        </Button>

        {/* Warning chip */}
        <Button
          variant="ghost"
          size="sm"
          className={
            "h-5 w-auto px-1.5 gap-1 text-[11px] rounded-sm " +
            (warningCount === 0 ? "opacity-60" : "")
          }
          onClick={() => handleChipClick("warning")}
          aria-label={`${warningCount} warnings`}
          title={`${warningCount} warning${warningCount === 1 ? "" : "s"} — click to filter`}
        >
          <AlertTriangle className="h-3 w-3 shrink-0" />
          <span>{warningCount}</span>
        </Button>

        {/* Info chip */}
        <Button
          variant="ghost"
          size="sm"
          className={
            "h-5 w-auto px-1.5 gap-1 text-[11px] rounded-sm " +
            (infoCount === 0 ? "opacity-60" : "")
          }
          onClick={() => handleChipClick("info")}
          aria-label={`${infoCount} info`}
          title={`${infoCount} info — click to filter`}
        >
          <Info className="h-3 w-3 shrink-0" />
          <span>{infoCount}</span>
        </Button>
      </div>

      {/* Right side: reserved for Phase 72 positional indicators */}
      <div />
    </div>
  );
}
