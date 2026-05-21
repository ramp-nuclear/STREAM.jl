/**
 * ValidationPanel — Phase 71 Plan 09
 *
 * The canonical surface for every ValidationResult emitted by the validator
 * registry (Plan 01). Lives as the body of the "Validation" tab in
 * BottomPanel (D-01, D-04).
 *
 * UX contract (D-05, D-14, §3.9):
 *   - Lists all results sorted: severity (error → warning → info), then
 *     validatorId (stable ASCII sort within each bucket).
 *   - Empty-state copy: "No issues." (D-04, engineering voice).
 *   - Click a row → dispatches 'stream:focus-validation-result' (canvas
 *     pan + flash ring). If the result has exactly one 'field' target,
 *     also dispatches 'stream:open-property-field' (property panel focus).
 *   - Listens for 'stream:validation-filter' (dispatched by Plan 10
 *     ValidationStatusBar chip) → filters the list to a single severity.
 *   - Listens for 'stream:validation-filter-node' (dispatched by Plan 11
 *     NodeContextMenu) → filters the list to results whose targets reference
 *     a specific nodeId, then scrolls the first matching row into view.
 *   - Fix-action buttons per §3.9: lossless-sync (secondary), value-transfer-
 *     picker (two secondary), navigation-only (ghost). Apply closures receive
 *     (useStore.setState, useStore.getState) at click time — Pitfall 7
 *     mitigation (closures read fresh state via get(); no stale snapshot).
 *   - Severity + node filters are mutually exclusive — activating one clears
 *     the other.
 */

import { useEffect, useRef, useState } from "react";
import { AlertCircle, AlertTriangle, Info } from "lucide-react";
import { Button } from "./ui/button";
import useStore from "../store/useStore";
import type { ValidationResult, FixAction } from "../lib/validation/types";
import { type StreamNodeData } from "../store/useStore";

// ---------------------------------------------------------------------------
// Custom-event type declarations (consumed here; dispatched by Plan 10 + 11).
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
// Helpers
// ---------------------------------------------------------------------------

const SEVERITY_RANK: Record<string, number> = { error: 0, warning: 1, info: 2 };

function sortResults(results: ValidationResult[]): ValidationResult[] {
  return [...results].sort((a, b) => {
    const rankDiff =
      (SEVERITY_RANK[a.severity] ?? 99) - (SEVERITY_RANK[b.severity] ?? 99);
    if (rankDiff !== 0) return rankDiff;
    return a.validatorId.localeCompare(b.validatorId);
  });
}

/** Returns true when at least one target in the result references nodeId
 *  (by node / port / field). Edge-only targets are not matched here —
 *  Plan 11's NodeContextMenu does not dispatch for edge-only results. */
function resultMatchesNode(result: ValidationResult, nodeId: string): boolean {
  return result.targets.some(
    (t) =>
      (t.kind === "node" && t.nodeId === nodeId) ||
      (t.kind === "port" && t.nodeId === nodeId) ||
      (t.kind === "field" && t.nodeId === nodeId),
  );
}

// ---------------------------------------------------------------------------
// Severity icon — color baseline; Phase 72 sweeps visual tokens.
// ---------------------------------------------------------------------------

function SeverityIcon({ severity }: { severity: "error" | "warning" | "info" }) {
  if (severity === "error")
    return <AlertCircle className="w-4 h-4 shrink-0 text-destructive" />;
  if (severity === "warning")
    return (
      <AlertTriangle
        className="w-4 h-4 shrink-0"
        style={{ color: "var(--color-warning)" }}
      />
    );
  return (
    <Info
      className="w-4 h-4 shrink-0"
      style={{ color: "var(--color-info)" }}
    />
  );
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export default function ValidationPanel() {
  const validationResults = useStore((s) => s.validationResults);
  const nodes = useStore((s) => s.nodes);

  // D-05 filter state — mutually exclusive.
  const [severityFilter, setSeverityFilter] = useState<
    "error" | "warning" | "info" | null
  >(null);
  const [nodeFilter, setNodeFilter] = useState<string | null>(null);

  // Display label for the node filter banner: prefer the user-facing
  // instance name; fall back to the raw nodeId if the node has been
  // deleted (filter persists until Clear filter is clicked).
  const nodeFilterLabel =
    nodeFilter === null
      ? null
      : (nodes.find((n) => n.id === nodeFilter)?.data as
          | StreamNodeData
          | undefined)?.instanceName ?? nodeFilter;

  // Ref for the first rendered row so we can scrollIntoView on node-filter
  // activation (D-05 "scrolls the first matching row into view").
  const firstRowRef = useRef<HTMLDivElement | null>(null);

  // Window event listeners — single useEffect, proper teardown.
  useEffect(() => {
    const onSeverityFilter = (e: Event) => {
      const ce = e as CustomEvent<ValidationFilterDetail>;
      const sev = ce.detail?.severity;
      if (sev) {
        setSeverityFilter(sev);
        setNodeFilter(null); // mutual exclusion
      }
    };

    const onNodeFilter = (e: Event) => {
      const ce = e as CustomEvent<ValidationFilterNodeDetail>;
      const nodeId = ce.detail?.nodeId;
      if (nodeId) {
        setNodeFilter(nodeId);
        setSeverityFilter(null); // mutual exclusion
        // Scroll first matching row into view after DOM paint.
        requestAnimationFrame(() => {
          firstRowRef.current?.scrollIntoView({
            block: "nearest",
            behavior: "smooth",
          });
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

  // Filter pipeline (D-05 locked behavior).
  let filtered = validationResults;
  if (severityFilter !== null) {
    filtered = filtered.filter((r) => r.severity === severityFilter);
  } else if (nodeFilter !== null) {
    filtered = filtered.filter((r) => resultMatchesNode(r, nodeFilter));
  }

  const sorted = sortResults(filtered);
  const count = sorted.length;
  const filterActive = severityFilter !== null || nodeFilter !== null;

  // Row click-to-focus handler — dispatches cross-component CustomEvents.
  function handleResultClick(result: ValidationResult) {
    window.dispatchEvent(
      new CustomEvent("stream:focus-validation-result", { detail: { result } }),
    );

    // If there is exactly one 'field' target, also open the property panel
    // field focus.
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

  function clearFilters() {
    setSeverityFilter(null);
    setNodeFilter(null);
  }

  return (
    <div className="flex flex-col h-full overflow-y-auto">
      {/* Filter banner */}
      {filterActive && (
        <div className="flex items-center gap-2 px-3 py-1 text-xs text-muted-foreground border-b bg-muted/30 shrink-0">
          {severityFilter !== null ? (
            <span>
              Showing only <span className="font-medium">{severityFilter}</span>{" "}
              results &middot; {count}
            </span>
          ) : (
            <span>
              Filtered to <span className="font-medium">{nodeFilterLabel}</span>{" "}
              &middot; {count}
            </span>
          )}
          <Button
            variant="ghost"
            size="sm"
            className="h-5 px-1.5 text-xs"
            onClick={clearFilters}
          >
            Clear filter
          </Button>
        </div>
      )}

      {/* Header — only when there are results */}
      {count > 0 && (
        <div className="px-3 py-1 text-[11px] text-muted-foreground shrink-0">
          {count} {count === 1 ? "issue" : "issues"}
          {filterActive ? " (filtered)" : ""}
        </div>
      )}

      {/* Empty state */}
      {count === 0 && (
        <div className="flex flex-col items-center justify-center gap-2 flex-1 p-4 text-center">
          {filterActive ? (
            <>
              <p className="text-muted-foreground text-sm">
                No results match the active filter.
              </p>
              <Button variant="ghost" size="sm" onClick={clearFilters}>
                Clear filter
              </Button>
            </>
          ) : (
            <p className="text-muted-foreground text-sm">No issues.</p>
          )}
        </div>
      )}

      {/* Result list */}
      {count > 0 && (
        <div className="flex flex-col divide-y">
          {sorted.map((result, index) => (
            <div
              key={result.id}
              ref={index === 0 ? firstRowRef : undefined}
              className="flex items-center gap-2 px-3 py-2 hover:bg-accent/30 cursor-pointer transition-colors"
              onClick={() => handleResultClick(result)}
              role="button"
              tabIndex={0}
              onKeyDown={(e) => {
                if (e.key === "Enter" || e.key === " ") handleResultClick(result);
              }}
            >
              {/* 1. Severity icon */}
              <SeverityIcon severity={result.severity} />

              {/* 2. Description */}
              <span className="flex-1 text-sm truncate" title={result.description}>
                {result.description}
              </span>

              {/* 3. Fix-action buttons (conditionally rendered) */}
              {result.fixAction && (
                <FixActionButtons
                  fixAction={result.fixAction}
                  result={result}
                  onNavigate={handleResultClick}
                />
              )}

              {/* 4. Validator ID chip */}
              <span className="text-[10px] text-muted-foreground font-mono shrink-0">
                {result.validatorId}
              </span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// FixActionButtons — renders the 3 FixAction kinds per §3.9.
// Extracted to a named component to keep the row JSX readable.
// ---------------------------------------------------------------------------

interface FixActionButtonsProps {
  fixAction: FixAction;
  result: ValidationResult;
  onNavigate: (result: ValidationResult) => void;
}

function FixActionButtons({ fixAction: fa, result, onNavigate }: FixActionButtonsProps) {
  const stop = (e: React.MouseEvent) => e.stopPropagation();

  if (fa.kind === "lossless-sync") {
    return (
      <Button
        variant="secondary"
        size="sm"
        onClick={(e) => {
          stop(e);
          fa.apply(useStore.setState, useStore.getState);
        }}
      >
        {fa.label}
      </Button>
    );
  }

  if (fa.kind === "value-transfer-picker") {
    return (
      <div className="flex gap-1" onClick={stop}>
        <Button
          variant="secondary"
          size="sm"
          onClick={(e) => {
            stop(e);
            fa.applyLeft(useStore.setState, useStore.getState);
          }}
        >
          {fa.leftLabel}
        </Button>
        <Button
          variant="secondary"
          size="sm"
          onClick={(e) => {
            stop(e);
            fa.applyRight(useStore.setState, useStore.getState);
          }}
        >
          {fa.rightLabel}
        </Button>
      </div>
    );
  }

  if (fa.kind === "navigation-only") {
    return (
      <Button
        variant="ghost"
        size="sm"
        onClick={(e) => {
          stop(e);
          // Reuse the row click-to-focus path — one focus implementation.
          onNavigate(result);
        }}
      >
        {fa.label}
      </Button>
    );
  }

  // TypeScript exhaustiveness check — error here if a new kind is added.
  void (fa as never);
  return null;
}
