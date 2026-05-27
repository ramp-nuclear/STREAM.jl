/**
 * ValidationPanel — Phase 72 redesign (notes 3a + 3b + 3c iteration).
 *
 * Engineering-inspection table for the canonical ValidationResults list.
 * Lives as the body of the "Validation" tab in BottomPanel.
 *
 * Header is two sub-rows:
 *   1. Controls row:
 *        left  — `12 issues` (sans 11 px, foreground/65)
 *        right — severity filter pills (ERR 12 / WRN 4 / INF 2), then a
 *                settings icon that opens a Group-by popover
 *        + when a node filter is active, an inline `· in <name> · clear`
 *          chip joins the count side.
 *   2. Column labels row (10 px mono uppercase, foreground/55, hairline
 *      under it): SEV / RULE / MESSAGE aligned to the row grid.
 *
 * Filter pills replace the prior `12 issues · ERR only · clear` inline
 * header — one click toggles a severity filter active/inactive instead of
 * forcing the user to go through the status bar for filtering and "clear"
 * for unfiltering.
 *
 * Group-by settings (per-session local state, no persistence):
 *   - None (default) — flat list, sorted by severity then validatorId.
 *   - Rule — group by validatorId. Parent row reads `▸ 5 × z_n_match`.
 *   - Component — group by first node target's instanceName. Parent reads
 *     `▸ 5 × Channel \`riser\``. Results without a node target fall into
 *     a `(unscoped)` group.
 *
 * Interactions preserved from Phase 71:
 *   - Row click → 'stream:focus-validation-result' (+ 'stream:open-property-field'
 *     for single-field-target results).
 *   - 'stream:validation-filter' (StatusBar) → severity filter.
 *   - 'stream:validation-filter-node' (NodeContextMenu) → node filter +
 *     scrollIntoView on first match.
 *   - Severity + node filters mutually exclusive.
 */

import { useEffect, useMemo, useRef, useState } from "react";
import { SlidersHorizontal, ChevronRight, ChevronDown } from "lucide-react";
import useStore from "../store/useStore";
import { Popover, PopoverContent, PopoverTrigger } from "./ui/popover";
import { ToggleGroup, ToggleGroupItem } from "./ui/toggle-group";
import { Tooltip, TooltipContent, TooltipTrigger } from "./ui/tooltip";
import type { ValidationResult } from "../lib/validation/types";
import { type StreamNodeData } from "../store/useStore";
import { scrollIntoViewSafe } from "../lib/scrollIntoViewSafe";
import { getPreference } from "../lib/preferences";
import {
  type Severity,
  SEVERITY_COLOR_VAR,
  SEVERITY_LABEL,
} from "../lib/severity";

// ---------------------------------------------------------------------------
// Custom-event type declarations
// ---------------------------------------------------------------------------

interface ValidationFilterDetail {
  severity: "error" | "warning" | "info";
}

interface ValidationFilterNodeDetail {
  nodeId: string;
}

declare global {
  interface WindowEventMap {
    "stream:validation-filter": CustomEvent<ValidationFilterDetail>;
    "stream:validation-filter-node": CustomEvent<ValidationFilterNodeDetail>;
    "stream:focus-validation-result": CustomEvent<{
      result: ValidationResult;
    }>;
    "stream:open-property-field": CustomEvent<{
      nodeId: string;
      fieldPath: string;
    }>;
  }
}

// ---------------------------------------------------------------------------
// Severity vocabulary
// ---------------------------------------------------------------------------

type GroupBy = "none" | "rule" | "component";

const SEVERITY_RANK: Record<Severity, number> = {
  error: 0,
  warning: 1,
  info: 2,
};

// Phase 72 — severity labels are full lowercase words ("error" / "warning"
// / "info"), not the 3-letter mono ERR/WRN/INF prefixes. The compact prefix
// has its place in the bottom-chrome status bar where space is tight and
// icons carry the recognition load — see ValidationStatusBar's icon-based
// severity glyphs. In the panel itself, vertical space is ample and the
// full word reads better: clearer at a glance, no abbreviation parsing,
// and consistent with the rest of the panel's full-word vocabulary
// (Group by None / Rule / Component, etc.).
//
// SEVERITY_LABEL + SEVERITY_COLOR_VAR live in `lib/severity.ts` (Phase 72
// extract — shared with ValidationStatusBar, PreferencesDialog, CanvasPanel).

// Default column widths in pixels. The user can drag the SEV↔RULE and
// RULE↔MESSAGE dividers to resize; min/max enforced below. MESSAGE is the
// fluid remainder (`minmax(0, 1fr)`), so only the first two are tunable.
// SEV bumped from 32 → 80 to fit the longest full-word label ("warning")
// at the panel's 13 px mono font with breathing room.
const DEFAULT_SEV_WIDTH = 80;
const DEFAULT_RULE_WIDTH = 200;
const MIN_SEV_WIDTH = 60;
const MAX_SEV_WIDTH = 120;
const MIN_RULE_WIDTH = 80;
const MAX_RULE_WIDTH = 480;

function gridTemplate(sevWidth: number, ruleWidth: number): string {
  return `${sevWidth}px ${ruleWidth}px minmax(0, 1fr)`;
}

function sortResults(results: ValidationResult[]): ValidationResult[] {
  return [...results].sort((a, b) => {
    const rankDiff =
      (SEVERITY_RANK[a.severity] ?? 99) - (SEVERITY_RANK[b.severity] ?? 99);
    if (rankDiff !== 0) return rankDiff;
    return a.validatorId.localeCompare(b.validatorId);
  });
}

function resultMatchesNode(result: ValidationResult, nodeId: string): boolean {
  return result.targets.some(
    (t) =>
      (t.kind === "node" && t.nodeId === nodeId) ||
      (t.kind === "port" && t.nodeId === nodeId) ||
      (t.kind === "field" && t.nodeId === nodeId),
  );
}

/** Component key for group-by-component. Uses the first node-target; if
 *  there is none, returns null (caller bucket as "(unscoped)"). */
function primaryNodeId(result: ValidationResult): string | null {
  const t = result.targets.find(
    (t) => t.kind === "node" || t.kind === "port" || t.kind === "field",
  );
  if (!t) return null;
  if (t.kind === "node" || t.kind === "port" || t.kind === "field") {
    return t.nodeId;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export default function ValidationPanel() {
  const validationResults = useStore((s) => s.validationResults);
  const nodes = useStore((s) => s.nodes);

  // Phase 72 Preferences — seed severity filter + group-by from user prefs.
  // Reading via lazy initializer so localStorage hits exactly once on mount.
  // Subsequent pref edits in the dialog don't reach back through this state
  // — the user already has the panel open and will see their explicit
  // selection win until the next mount (matches Linear/Figma "defaults apply
  // on open" model).
  const [severityFilter, setSeverityFilter] = useState<Severity | null>(() => {
    const pref = getPreference("validation", "defaultSeverityFilter");
    if (pref === "errors") return "error";
    // "warnings+" / "info+" / "all" all start with a null filter and the
    // user's filter pills do the rest. (warnings+/info+ would require a
    // multi-tier filter which the current pill UI doesn't support.)
    return null;
  });
  const [nodeFilter, setNodeFilter] = useState<string | null>(null);
  const [groupBy, setGroupBy] = useState<GroupBy>(() =>
    getPreference("validation", "defaultGroupBy"),
  );
  const [collapsedGroups, setCollapsedGroups] = useState<Set<string>>(new Set());
  // Selected-row state: tracks the most-recently clicked validation result so
  // the panel can render a visible left-edge accent on it. Matches the
  // persistent canvas trace lifetime (CanvasPanel auto-clears on canvas click;
  // we clear here on filter changes and on canvas-side trace clears too —
  // listen for an explicit 'stream:validation-trace-cleared' if we add one).
  const [selectedResultId, setSelectedResultId] = useState<string | null>(null);
  // Per-session column widths. Dragging the dividers updates these.
  const [sevWidth, setSevWidth] = useState<number>(DEFAULT_SEV_WIDTH);
  const [ruleWidth, setRuleWidth] = useState<number>(DEFAULT_RULE_WIDTH);
  const currentGrid = gridTemplate(sevWidth, ruleWidth);

  const nodeFilterLabel =
    nodeFilter === null
      ? null
      : (nodes.find((n) => n.id === nodeFilter)?.data as
          | StreamNodeData
          | undefined)?.instanceName ?? nodeFilter;

  // First row ref for scrollIntoView on node-filter activation.
  const firstRowRef = useRef<HTMLButtonElement | null>(null);

  // Window event listeners.
  useEffect(() => {
    const onSeverityFilter = (e: Event) => {
      const ce = e as CustomEvent<ValidationFilterDetail>;
      const sev = ce.detail?.severity;
      if (sev) {
        setSeverityFilter(sev);
        setNodeFilter(null);
      }
    };

    const onNodeFilter = (e: Event) => {
      const ce = e as CustomEvent<ValidationFilterNodeDetail>;
      const nodeId = ce.detail?.nodeId;
      if (nodeId) {
        setNodeFilter(nodeId);
        setSeverityFilter(null);
        requestAnimationFrame(() => {
          if (firstRowRef.current) {
            scrollIntoViewSafe(firstRowRef.current, {
              block: "nearest",
              behavior: "smooth",
            });
          }
        });
      }
    };

    window.addEventListener(
      "stream:validation-filter",
      onSeverityFilter as EventListener,
    );
    window.addEventListener(
      "stream:validation-filter-node",
      onNodeFilter as EventListener,
    );

    return () => {
      window.removeEventListener(
        "stream:validation-filter",
        onSeverityFilter as EventListener,
      );
      window.removeEventListener(
        "stream:validation-filter-node",
        onNodeFilter as EventListener,
      );
    };
  }, []);

  // Total counts (per-severity over ALL results, not just filtered) —
  // these feed the filter pills so they show stable totals regardless of
  // which filter is active.
  const totals = useMemo(() => {
    let e = 0, w = 0, i = 0;
    for (const r of validationResults) {
      if (r.severity === "error") e++;
      else if (r.severity === "warning") w++;
      else if (r.severity === "info") i++;
    }
    return { error: e, warning: w, info: i };
  }, [validationResults]);

  // Filter pipeline.
  let filtered = validationResults;
  if (severityFilter !== null) {
    filtered = filtered.filter((r) => r.severity === severityFilter);
  } else if (nodeFilter !== null) {
    filtered = filtered.filter((r) => resultMatchesNode(r, nodeFilter));
  }

  const sorted = sortResults(filtered);
  const count = sorted.length;
  const filterActive = severityFilter !== null || nodeFilter !== null;

  // Group projection. Keyed by validatorId (rule) or instanceName (component).
  type Group = {
    key: string;
    displayLabel: string;
    results: ValidationResult[];
  };
  const groups: Group[] = useMemo(() => {
    if (groupBy === "none") return [];

    const buckets = new Map<string, ValidationResult[]>();
    const labelByKey = new Map<string, string>();

    for (const r of sorted) {
      let key: string;
      let label: string;
      if (groupBy === "rule") {
        key = r.validatorId;
        label = r.validatorId;
      } else {
        const nid = primaryNodeId(r);
        if (nid === null) {
          key = "__unscoped__";
          label = "(unscoped)";
        } else {
          key = nid;
          const inst = (nodes.find((n) => n.id === nid)?.data as
            | StreamNodeData
            | undefined)?.instanceName;
          label = inst ?? nid;
        }
      }
      labelByKey.set(key, label);
      const bucket = buckets.get(key);
      if (bucket) bucket.push(r);
      else buckets.set(key, [r]);
    }

    return Array.from(buckets.entries()).map(([key, results]) => ({
      key,
      displayLabel: labelByKey.get(key) ?? key,
      results,
    }));
  }, [sorted, groupBy, nodes]);

  function handleResultClick(result: ValidationResult) {
    setSelectedResultId(result.id);
    window.dispatchEvent(
      new CustomEvent("stream:focus-validation-result", { detail: { result } }),
    );

    const fieldTargets = result.targets.filter((t) => t.kind === "field");
    if (fieldTargets.length === 1) {
      const ft = fieldTargets[0];
      if (ft.kind === "field") {
        window.dispatchEvent(
          new CustomEvent("stream:open-property-field", {
            detail: { nodeId: ft.nodeId, fieldPath: ft.fieldPath },
          }),
        );
      }
    }
  }

  function togglePill(severity: Severity) {
    if (severityFilter === severity) {
      setSeverityFilter(null);
    } else {
      setSeverityFilter(severity);
      setNodeFilter(null);
    }
    setSelectedResultId(null);
  }

  function clearNodeFilter() {
    setNodeFilter(null);
    setSelectedResultId(null);
  }

  // Column resize: tracks a drag-in-progress and a `which` flag identifying
  // which boundary is being dragged. Mouse events are bound to the document
  // so the user can drag the pointer outside the visible handle area.
  const dragStateRef = useRef<{
    which: "sev" | "rule";
    startX: number;
    startWidth: number;
  } | null>(null);

  useEffect(() => {
    function onMove(ev: MouseEvent) {
      const drag = dragStateRef.current;
      if (!drag) return;
      const dx = ev.clientX - drag.startX;
      if (drag.which === "sev") {
        const next = Math.min(
          MAX_SEV_WIDTH,
          Math.max(MIN_SEV_WIDTH, drag.startWidth + dx),
        );
        setSevWidth(next);
      } else {
        const next = Math.min(
          MAX_RULE_WIDTH,
          Math.max(MIN_RULE_WIDTH, drag.startWidth + dx),
        );
        setRuleWidth(next);
      }
    }
    function onUp() {
      if (!dragStateRef.current) return;
      dragStateRef.current = null;
      document.body.style.cursor = "";
      document.body.style.userSelect = "";
    }
    document.addEventListener("mousemove", onMove);
    document.addEventListener("mouseup", onUp);
    return () => {
      document.removeEventListener("mousemove", onMove);
      document.removeEventListener("mouseup", onUp);
    };
  }, []);

  function startResize(which: "sev" | "rule", ev: React.MouseEvent) {
    ev.preventDefault();
    ev.stopPropagation();
    dragStateRef.current = {
      which,
      startX: ev.clientX,
      startWidth: which === "sev" ? sevWidth : ruleWidth,
    };
    document.body.style.cursor = "col-resize";
    document.body.style.userSelect = "none";
  }

  function toggleGroup(key: string) {
    setCollapsedGroups((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  }

  const hasAnyResults = validationResults.length > 0;

  return (
    <div className="flex flex-col h-full overflow-y-auto">
      {/* Header: controls row + node-filter chip + column labels.
          Only rendered when there's something to control over (any results
          exist OR a filter is active). */}
      {(hasAnyResults || filterActive) && (
        <div className="border-b border-border shrink-0">
          {/* Controls row */}
          <div className="flex items-center justify-between px-3 py-1.5 gap-3">
            <div className="flex items-center gap-2 text-label text-foreground/65 min-w-0">
              <span className="tabular-nums">
                {count} {count === 1 ? "issue" : "issues"}
              </span>
              {nodeFilter !== null && (
                <>
                  <span aria-hidden className="text-foreground/40">·</span>
                  <span className="truncate">
                    in <span className="text-foreground/85">{nodeFilterLabel}</span>
                  </span>
                  <button
                    type="button"
                    onClick={clearNodeFilter}
                    className="text-foreground/75 hover:text-foreground underline-offset-2 hover:underline cursor-pointer"
                  >
                    clear
                  </button>
                </>
              )}
            </div>
            <div className="flex items-center gap-0.5 shrink-0">
              <FilterPill
                severity="error"
                count={totals.error}
                active={severityFilter === "error"}
                onClick={() => togglePill("error")}
              />
              <FilterPill
                severity="warning"
                count={totals.warning}
                active={severityFilter === "warning"}
                onClick={() => togglePill("warning")}
              />
              <FilterPill
                severity="info"
                count={totals.info}
                active={severityFilter === "info"}
                onClick={() => togglePill("info")}
              />
              <GroupBySettings groupBy={groupBy} onChange={setGroupBy} />
            </div>
          </div>

          {/* Column labels — only when there is content to label.
              The two `<ColumnResizeHandle>`s sit at the right edge of the
              SEV and RULE columns. They're 4 px wide invisible drag zones
              that show a 1 px ring hairline on hover and switch the cursor
              to col-resize. Drag adjusts the corresponding column width;
              both this row AND every data row + group header consume the
              same `currentGrid`, so widths stay in sync. */}
          {count > 0 && (
            <div className="relative">
              <div
                className="grid items-baseline gap-3 px-3 pb-1 text-micro uppercase tracking-wide text-foreground/45 font-mono"
                style={{ gridTemplateColumns: currentGrid }}
                aria-hidden
              >
                <span>Sev</span>
                <span>Rule</span>
                <span>Message</span>
              </div>
              <ColumnResizeHandle
                left={12 + sevWidth}
                onMouseDown={(e) => startResize("sev", e)}
              />
              <ColumnResizeHandle
                left={12 + sevWidth + 12 + ruleWidth}
                onMouseDown={(e) => startResize("rule", e)}
              />
            </div>
          )}
        </div>
      )}

      {/* Empty state */}
      {count === 0 && (
        <div className="flex-1 px-3 py-3 text-body text-foreground/65 font-mono">
          {filterActive ? (
            <>
              No results match the active filter.{" "}
              <button
                type="button"
                onClick={() => {
                  setSeverityFilter(null);
                  setNodeFilter(null);
                }}
                className="underline-offset-2 hover:underline text-foreground/85 hover:text-foreground transition-colors duration-[80ms] cursor-pointer"
              >
                clear
              </button>
            </>
          ) : (
            "No issues."
          )}
        </div>
      )}

      {/* Body — flat list or grouped */}
      {count > 0 && groupBy === "none" && (
        <div className="flex flex-col">
          {sorted.map((result, index) => (
            <Row
              key={result.id}
              ref={index === 0 ? firstRowRef : undefined}
              result={result}
              gridTemplate={currentGrid}
              selected={selectedResultId === result.id}
              onClick={() => handleResultClick(result)}
            />
          ))}
        </div>
      )}

      {count > 0 && groupBy !== "none" && (
        <div className="flex flex-col">
          {groups.map((group, gIdx) => {
            const collapsed = collapsedGroups.has(group.key);
            const groupSeverity: Severity =
              group.results.reduce<Severity>((acc, r) => {
                return SEVERITY_RANK[r.severity] < SEVERITY_RANK[acc] ? r.severity : acc;
              }, "info");
            return (
              <div key={group.key}>
                <GroupHeader
                  collapsed={collapsed}
                  severity={groupSeverity}
                  count={group.results.length}
                  label={group.displayLabel}
                  groupBy={groupBy}
                  gridTemplate={currentGrid}
                  onClick={() => toggleGroup(group.key)}
                />
                {!collapsed &&
                  group.results.map((result, rIdx) => (
                    <Row
                      key={result.id}
                      ref={gIdx === 0 && rIdx === 0 ? firstRowRef : undefined}
                      result={result}
                      gridTemplate={currentGrid}
                      selected={selectedResultId === result.id}
                      onClick={() => handleResultClick(result)}
                      indented
                    />
                  ))}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// FilterPill — toggle a severity filter from inside the panel header.
// Inactive: foreground/55, no background. Active: color-tokenized text, faint
// background tint. No chip silhouette — flat type with a hover bg lift.
// ---------------------------------------------------------------------------

interface FilterPillProps {
  severity: Severity;
  count: number;
  active: boolean;
  onClick: () => void;
}

function FilterPill({ severity, count, active, onClick }: FilterPillProps) {
  const dim = count === 0 && !active;
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={active}
      aria-label={`Filter to ${severity}${active ? " (active)" : ""}`}
      // Phase 72 — bumped from text-[11px] px-1.5 py-1 (cramped) to
      // text-[13px] px-2.5 py-1.5 to match the panel's body text scale
      // (RULE / MESSAGE cells are 13 px) and give the controls more
      // tap-target / hit-area. gap-1.5 (was gap-1) keeps the label and
      // count visually balanced at the larger text size.
      className={
        "inline-flex items-center gap-1.5 font-mono text-body leading-none " +
        "px-2.5 py-1.5 rounded-sm cursor-pointer select-none " +
        "transition-colors duration-[80ms] " +
        "hover:bg-popover focus-visible:outline-none focus-visible:bg-popover " +
        (active ? "bg-popover " : "") +
        (dim ? "opacity-55 " : "")
      }
    >
      <span
        style={{ color: active || count > 0 ? SEVERITY_COLOR_VAR[severity] : undefined }}
      >
        {SEVERITY_LABEL[severity]}
      </span>
      <span className={active ? "text-foreground tabular-nums" : "text-foreground/75 tabular-nums"}>
        {count}
      </span>
    </button>
  );
}

// ---------------------------------------------------------------------------
// GroupBySettings — sliders icon → popover with a single-select toggle group.
// ---------------------------------------------------------------------------

interface GroupBySettingsProps {
  groupBy: GroupBy;
  onChange: (v: GroupBy) => void;
}

function GroupBySettings({ groupBy, onChange }: GroupBySettingsProps) {
  return (
    <Popover>
      {/* Phase 72 (help-system) — icon-only chrome button. Tooltip
          discipline applies. Nested asChild: TooltipTrigger and
          PopoverTrigger both forward refs/props to the button. */}
      <Tooltip>
        <TooltipTrigger asChild>
          <PopoverTrigger asChild>
            <button
              type="button"
              aria-label="Group by settings"
              // Phase 72 — padded to match the new bigger FilterPill
              // (px-2.5 py-1.5 vs prior px-1.5 py-1). Icon size 3.5 → 4
              // (16 px) so the glyph keeps proportional presence in the
              // larger button.
              className={
                "inline-flex items-center justify-center px-2 py-1.5 ml-1 rounded-sm cursor-pointer " +
                "text-foreground/65 hover:text-foreground " +
                "transition-colors duration-[80ms] " +
                "hover:bg-popover focus-visible:outline-none focus-visible:bg-popover " +
                (groupBy !== "none" ? "text-foreground" : "")
              }
            >
              <SlidersHorizontal className="h-4 w-4" strokeWidth={1.5} />
            </button>
          </PopoverTrigger>
        </TooltipTrigger>
        <TooltipContent side="top">Group by</TooltipContent>
      </Tooltip>
      <PopoverContent align="end" className="w-auto p-3">
        <div className="flex flex-col gap-2">
          <span className="text-micro uppercase tracking-wide text-foreground/55 font-mono">
            Group by
          </span>
          <ToggleGroup
            type="single"
            value={groupBy}
            onValueChange={(v) => {
              // ToggleGroup emits "" when the user clicks the active item;
              // coerce to "none" so the control always has a definite state.
              if (v === "" || v === undefined) {
                onChange("none");
                return;
              }
              onChange(v as GroupBy);
            }}
            size="sm"
          >
            <ToggleGroupItem value="none">None</ToggleGroupItem>
            <ToggleGroupItem value="rule">Rule</ToggleGroupItem>
            <ToggleGroupItem value="component">Component</ToggleGroupItem>
          </ToggleGroup>
        </div>
      </PopoverContent>
    </Popover>
  );
}

// ---------------------------------------------------------------------------
// GroupHeader — parent row for a collapsed/expanded group bucket.
// Layout matches the row grid so the message column lines up between groups
// and leaves. Chevron + count chip live in the SEV/RULE cells; the label fills
// the MESSAGE cell.
// ---------------------------------------------------------------------------

interface GroupHeaderProps {
  collapsed: boolean;
  severity: Severity;
  count: number;
  label: string;
  groupBy: GroupBy;
  gridTemplate: string;
  onClick: () => void;
}

function GroupHeader({
  collapsed,
  severity,
  count,
  label,
  groupBy,
  gridTemplate,
  onClick,
}: GroupHeaderProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-expanded={!collapsed}
      className={
        "grid items-baseline gap-3 px-3 py-1.5 cursor-pointer text-left w-full " +
        "hover:bg-popover/60 focus-visible:outline-none focus-visible:bg-popover/80 " +
        "transition-colors duration-[80ms] border-t border-border/60 first:border-t-0"
      }
      style={{ gridTemplateColumns: gridTemplate }}
    >
      <span className="font-mono text-label leading-snug inline-flex items-center text-foreground/65">
        {collapsed ? (
          <ChevronRight className="h-3 w-3" strokeWidth={1.5} />
        ) : (
          <ChevronDown className="h-3 w-3" strokeWidth={1.5} />
        )}
      </span>
      <span
        className="font-mono text-label leading-snug tabular-nums"
        style={{ color: SEVERITY_COLOR_VAR[severity] }}
        title={`${count} ${count === 1 ? "issue" : "issues"} (highest: ${severity})`}
      >
        {count} × {groupBy === "rule" ? "rule" : "node"}
      </span>
      <span
        className="text-body leading-snug text-foreground truncate font-mono"
        title={label}
      >
        {label}
      </span>
    </button>
  );
}

// ---------------------------------------------------------------------------
// Row — three-column compiler-output silhouette.
// ---------------------------------------------------------------------------

interface RowProps {
  result: ValidationResult;
  onClick: () => void;
  ref?: React.Ref<HTMLButtonElement>;
  indented?: boolean;
  gridTemplate: string;
  selected: boolean;
}

function Row({ result, onClick, ref, indented, gridTemplate, selected }: RowProps) {
  // Phase 72 harden — converted from `<div role="button" tabIndex={0}
  // onKeyDown>` to a native `<button>`. The prior shim was correct for
  // axe-core, but the native element wins on screen-reader announcement
  // (announces "button" with state, no role coercion), supports Enter/Space
  // activation for free, participates in form-tab order without an explicit
  // tabIndex, and `type="button"` guarantees no accidental submit if this
  // panel ever lands inside a <form>.
  //
  // Selected rows render a 2 px left-edge accent in --ring (Hydraulic-hue
  // focus color, locked Phase 72) so the user can tell which row is producing
  // the persistent canvas trace at a glance. Clears when the user clicks
  // anywhere on the canvas (CanvasPanel clears the trace, panel re-renders
  // and selected state is dropped via filter-change paths).
  return (
    <button
      ref={ref}
      type="button"
      onClick={onClick}
      data-selected={selected || undefined}
      className={
        // `text-left font-normal` reset native <button> centering + bold
        // defaults (the row reads as a list item, not a chrome button).
        "relative grid items-baseline gap-3 py-1.5 text-left font-normal cursor-pointer w-full " +
        "hover:bg-popover focus-visible:outline-none focus-visible:bg-popover " +
        "transition-colors duration-[80ms] motion-reduce:transition-none " +
        (indented ? "pl-6 pr-3" : "px-3") +
        (selected ? " bg-popover" : "")
      }
      style={{ gridTemplateColumns: gridTemplate }}
    >
      {selected && (
        <span
          aria-hidden
          className="absolute left-0 top-0 bottom-0 w-[2px]"
          style={{ background: "var(--ring)" }}
        />
      )}
      <span
        // Phase 72 — bumped from text-[11px] tracking-tight (sized for
        // the prior 3-letter prefix) to text-[13px] matching the RULE +
        // MESSAGE cells. Drops the tight tracking — full-word "warning"
        // doesn't need the abbreviation-style condensation.
        className="font-mono text-body leading-snug"
        style={{ color: SEVERITY_COLOR_VAR[result.severity] }}
      >
        {SEVERITY_LABEL[result.severity]}
      </span>
      <span
        className="font-mono text-body leading-snug text-foreground/85 truncate"
        title={result.validatorId}
      >
        {result.validatorId}
      </span>
      <span
        className="text-body leading-snug text-foreground truncate"
        title={result.description}
      >
        {result.description}
      </span>
    </button>
  );
}

// ---------------------------------------------------------------------------
// ColumnResizeHandle — invisible 6 px drag zone overlaying the column boundary.
// Renders absolutely-positioned over the column-label row's `relative` parent.
// Shows a 1 px --ring hairline + col-resize cursor on hover.
// ---------------------------------------------------------------------------

interface ColumnResizeHandleProps {
  left: number;
  onMouseDown: (ev: React.MouseEvent) => void;
}

function ColumnResizeHandle({ left, onMouseDown }: ColumnResizeHandleProps) {
  return (
    <span
      role="separator"
      aria-orientation="vertical"
      onMouseDown={onMouseDown}
      style={{ left: `${left}px` }}
      className={
        "absolute top-0 bottom-0 w-1.5 -ml-[3px] cursor-col-resize z-10 group/handle " +
        "before:absolute before:left-1/2 before:-translate-x-1/2 before:top-0 before:bottom-0 " +
        "before:w-px before:bg-transparent before:transition-colors before:duration-[80ms] " +
        "hover:before:bg-[var(--ring)] active:before:bg-[var(--ring)]"
      }
    />
  );
}
