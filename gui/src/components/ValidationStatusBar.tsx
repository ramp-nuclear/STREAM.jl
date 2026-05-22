/**
 * ValidationStatusBar — unified bottom-chrome footer (Phase 72 redesign).
 *
 * Always-visible 22 px strip pinned to the absolute bottom of the window.
 * The single source of truth for the bottom-panel's open / closed state AND
 * its active tab. The BottomPanel header no longer carries tabs.
 *
 * Layout:
 *   left   — severity count segments: `ERR 12   WRN 4   INF 2`, mono,
 *            color-tokenized. Click → opens BottomPanel on Validation tab
 *            with that severity filter pre-applied.
 *   center — divider hairline (visual separation between status and control).
 *   right  — `Code | Validation` tab buttons + close chevron. Click an
 *            inactive tab → opens panel on that tab. Click active tab →
 *            closes panel. The `⌄` chevron is a redundant close affordance
 *            shown only when the panel is open.
 *
 * Severity vocabulary (ERR/WRN/INF) intentionally matches ValidationPanel row
 * prefixes — one severity language across the system, not two.
 *
 * 0 → N error pulse retained: when error count rises from 0 the ERR segment
 * plays `pulse-once` once. Panel does NOT auto-open on count change.
 */

import { useEffect, useMemo, useRef, useState } from "react";
import { ChevronDown } from "lucide-react";
import useStore from "../store/useStore";

type Severity = "error" | "warning" | "info";
type BottomTab = "code" | "validation";

const SEVERITY_LABEL: Record<Severity, string> = {
  error: "ERR",
  warning: "WRN",
  info: "INF",
};

const SEVERITY_COLOR_VAR: Record<Severity, string> = {
  error: "var(--destructive)",
  warning: "var(--color-warning)",
  info: "var(--color-info)",
};

// ---------------------------------------------------------------------------
// Severity segment — left cluster
// ---------------------------------------------------------------------------

interface SeveritySegmentProps {
  severity: Severity;
  count: number;
  pulse?: boolean;
}

function SeveritySegment({ severity, count, pulse }: SeveritySegmentProps) {
  const active = count > 0;

  function handleClick() {
    useStore.setState({ bottomPanelOpen: true, activeBottomTab: "validation" });
    window.dispatchEvent(
      new CustomEvent("stream:validation-filter", { detail: { severity } }),
    );
  }

  return (
    <button
      type="button"
      onClick={handleClick}
      aria-label={`${count} ${severity}${count === 1 ? "" : "s"}`}
      title={
        severity === "error" && count > 0
          ? `${count} ${count === 1 ? "error" : "errors"} block export`
          : `${count} ${severity}${count === 1 ? "" : "s"}`
      }
      className={
        "h-full px-3 inline-flex items-center gap-2 font-mono text-body " +
        "leading-none cursor-pointer select-none " +
        "transition-colors duration-[80ms] " +
        "hover:bg-popover/60 focus-visible:outline-none focus-visible:bg-popover " +
        (active ? "" : "opacity-55 ") +
        (pulse ? "pulse-once" : "")
      }
    >
      <span
        style={{ color: active ? SEVERITY_COLOR_VAR[severity] : undefined }}
        className="tracking-tight"
      >
        {SEVERITY_LABEL[severity]}
      </span>
      <span className="text-foreground/85 tabular-nums">{count}</span>
    </button>
  );
}

// ---------------------------------------------------------------------------
// Tab button — right cluster
// ---------------------------------------------------------------------------

interface TabButtonProps {
  tab: BottomTab;
  label: string;
  panelOpen: boolean;
  activeTab: BottomTab;
}

function TabButton({ tab, label, panelOpen, activeTab }: TabButtonProps) {
  const isActive = panelOpen && activeTab === tab;

  function handleClick() {
    if (!panelOpen) {
      // Closed → open on this tab.
      useStore.setState({ bottomPanelOpen: true, activeBottomTab: tab });
      return;
    }
    if (activeTab === tab) {
      // Active tab clicked while open → close.
      useStore.setState({ bottomPanelOpen: false });
      return;
    }
    // Inactive tab clicked while open → switch tab.
    useStore.setState({ activeBottomTab: tab });
  }

  // Active-tab indicator: a 1 px top accent rule using --ring (Hydraulic
  // hue, locked focus color), plus brighter text. Rest state is foreground/65
  // mono. Hover lifts background to --popover/60 like the severity segments.
  return (
    <button
      type="button"
      onClick={handleClick}
      role="tab"
      aria-selected={isActive}
      aria-label={
        !panelOpen
          ? `Open ${label.toLowerCase()} panel`
          : isActive
            ? `Close ${label.toLowerCase()} panel`
            : `Switch to ${label.toLowerCase()} panel`
      }
      className={
        "relative h-full px-4 inline-flex items-center font-mono text-body " +
        "leading-none cursor-pointer select-none " +
        "transition-colors duration-[80ms] " +
        "hover:bg-popover/60 focus-visible:outline-none focus-visible:bg-popover " +
        (isActive ? "text-foreground" : "text-foreground/65 hover:text-foreground")
      }
    >
      {/* Active-tab top accent — 1 px line at the top edge using --ring. */}
      {isActive && (
        <span
          aria-hidden
          className="absolute left-2 right-2 top-0 h-px"
          style={{ background: "var(--ring)" }}
        />
      )}
      <span>{label}</span>
    </button>
  );
}

// ---------------------------------------------------------------------------
// Status bar
// ---------------------------------------------------------------------------

export default function ValidationStatusBar() {
  const validationResults = useStore((s) => s.validationResults);
  const bottomPanelOpen = useStore((s) => s.bottomPanelOpen);
  const activeBottomTab = useStore((s) => s.activeBottomTab);

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

  // 0 → N error pulse.
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

  useEffect(() => {
    prevErrorCountRef.current = errorCount;
  });

  return (
    <div
      className="flex flex-row items-stretch justify-between border-t bg-chrome shrink-0 select-none"
      style={{ height: 28 }}
      aria-label="Status bar"
    >
      {/* Left cluster — severity segments */}
      <div className="flex flex-row items-stretch" role="group" aria-label="Validation counts">
        <SeveritySegment severity="error" count={errorCount} pulse={pulseActive} />
        <SeveritySegment severity="warning" count={warningCount} />
        <SeveritySegment severity="info" count={infoCount} />
      </div>

      {/* Right cluster — bottom-panel tabs + close chevron */}
      <div className="flex flex-row items-stretch" role="tablist" aria-label="Bottom panel">
        <TabButton
          tab="code"
          label="Code"
          panelOpen={bottomPanelOpen}
          activeTab={activeBottomTab}
        />
        <TabButton
          tab="validation"
          label="Validation"
          panelOpen={bottomPanelOpen}
          activeTab={activeBottomTab}
        />
        {bottomPanelOpen && (
          <button
            type="button"
            onClick={() => useStore.setState({ bottomPanelOpen: false })}
            aria-label="Close bottom panel"
            title="Close panel (Ctrl+`)"
            className={
              "h-full px-3 inline-flex items-center cursor-pointer text-foreground/65 " +
              "hover:text-foreground transition-colors duration-[80ms] " +
              "hover:bg-popover/60 focus-visible:outline-none focus-visible:bg-popover"
            }
          >
            <ChevronDown className="h-3.5 w-3.5" strokeWidth={1.5} />
          </button>
        )}
      </div>
    </div>
  );
}
