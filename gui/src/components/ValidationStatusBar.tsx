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
 * Severity vocabulary in the STATUS BAR uses icons (circle-x / triangle-
 * alert / info) — the IDE-status-bar lineage (VSCode/IntelliJ/Sublime/
 * Eclipse all use these exact glyphs at this exact size). This is a
 * deliberate departure from the ValidationPanel row vocabulary which uses
 * mono `ERR/WRN/INF` text prefixes — Lucide alert icons were explicitly
 * banned IN THE PANEL because they pattern-matched the canonical
 * shadcn-admin "AlertCircle + muted-foreground chip" silhouette (the very
 * pattern PRODUCT.md anti-references). In the compact status bar, the
 * same icons read as tool-grade (the IDE convention they actually come
 * from), not as SaaS-admin. Different surface, different convention. See
 * DESIGN.md §5 unified bottom-chrome footer doctrine for the carve-out.
 *
 * 0 → N error pulse retained: when error count rises from 0 the error
 * segment plays `pulse-once` once. Panel does NOT auto-open on count change.
 */

import { useEffect, useMemo, useRef, useState } from "react";
import { ChevronDown } from "lucide-react";
import useStore from "../store/useStore";
import { Tooltip, TooltipContent, TooltipTrigger } from "./ui/tooltip";
import {
  type Severity,
  SEVERITY_COLOR_VAR,
  SEVERITY_ICON,
} from "../lib/severity";

type BottomTab = "code" | "validation";

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
  const Icon = SEVERITY_ICON[severity];

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
        "h-full px-3.5 inline-flex items-center gap-2 font-mono " +
        "cursor-pointer select-none " +
        "transition-colors duration-[80ms] " +
        "hover:bg-popover/60 focus-visible:outline-none focus-visible:bg-popover " +
        (active ? "" : "opacity-55 ") +
        (pulse ? "pulse-once" : "")
      }
    >
      {/* Icon + number share an explicit 18 px line-box (icon h/w = 18,
          number leading-[18px]) so their top + bottom Y edges align
          exactly regardless of font cap-height differences. items-center
          on the parent flex row centers the matched-height boxes
          together. strokeWidth bumped 1.5 → 1.75 for visual weight at
          the larger icon size (the primitive-layer's 1.5 stroke is
          tuned for size-3.5 / 14 px controls — at 18 px the same
          stroke reads thin). Number text-[15px] reads visually
          balanced with the 18 px icon (mono digit cap height ≈ 0.72
          of font-size, so 15 px font ≈ 11 px cap, vs ~14 px icon glyph
          inside the 18 px bbox — close enough to read as harmonized).
          Color: severity token when count > 0, currentColor inherits
          from the parent's opacity-55 dim when count is 0. */}
      <Icon
        className="h-[18px] w-[18px] shrink-0"
        strokeWidth={1.75}
        aria-hidden
        style={{ color: active ? SEVERITY_COLOR_VAR[severity] : undefined }}
      />
      {/* Phase 72 — the count span is an explicit inline-flex container
          (h-[18px] matching the icon) with items-center forcing the
          digit's visual center to the box center. Prior pass used only
          `leading-[18px]` which set the line-box but left the digit
          baseline-anchored to the box bottom — at mono font with no
          descenders, that put the visible digit visibly low relative
          to the icon's center-aligned glyph. inline-flex items-center
          on the span itself overrides the baseline behavior. */}
      <span className="inline-flex items-center h-[18px] text-[15px] text-foreground/85 tabular-nums">
        {count}
      </span>
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
        "relative h-full px-4 inline-flex items-center font-mono text-[15px] " +
        "leading-[18px] cursor-pointer select-none " +
        "transition-colors duration-[80ms] " +
        "hover:bg-popover/60 focus-visible:outline-none focus-visible:bg-popover " +
        (isActive ? "text-foreground" : "text-foreground/85 hover:text-foreground")
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
      // Phase 72 — bar height bumped 28 → 32 px to accommodate the larger
      // 18 px severity icons + 15 px count text without crowding. Still
      // squarely in IDE-status-bar territory (VSCode 22, JetBrains 27,
      // Sublime 28-30, Eclipse 32). No external consumers of the 28 px
      // value (verified via grep).
      style={{ height: 32 }}
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
          // Phase 72 (help-system) — icon-only chrome button + has a
          // keyboard shortcut whose binding isn't visibly displayed.
          // Tooltip discipline applies: tooltip shows the binding.
          <Tooltip>
            <TooltipTrigger asChild>
              <button
                type="button"
                onClick={() => useStore.setState({ bottomPanelOpen: false })}
                aria-label="Close bottom panel"
                className={
                  "h-full px-3 inline-flex items-center cursor-pointer text-foreground/85 " +
                  "hover:text-foreground transition-colors duration-[80ms] " +
                  "hover:bg-popover/60 focus-visible:outline-none focus-visible:bg-popover"
                }
              >
                <ChevronDown className="h-[18px] w-[18px]" strokeWidth={1.75} />
              </button>
            </TooltipTrigger>
            <TooltipContent side="top">Close panel · Ctrl+`</TooltipContent>
          </Tooltip>
        )}
      </div>
    </div>
  );
}
