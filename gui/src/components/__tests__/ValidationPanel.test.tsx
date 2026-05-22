// @vitest-environment happy-dom
//
// ValidationPanel.test.tsx — Phase 72 (column headers + filter pills + group-by).
//
// Tests for ValidationPanel after the panel-header rebuild: empty state, sort
// order, row click-to-focus, severity + node filter events, filter-pill toggle,
// inline node-filter clear, column-header presence, and group-by-rule
// expand/collapse.

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { render, screen, cleanup, fireEvent, within } from "@testing-library/react";
import ValidationPanel from "../ValidationPanel";
import { TooltipProvider } from "../ui/tooltip";
import useStore from "../../store/useStore";
import type { ValidationResult } from "../../lib/validation/types";

function makeResult(overrides: Partial<ValidationResult> = {}): ValidationResult {
  return {
    id: "r1",
    validatorId: "test_validator",
    severity: "error",
    description: "Test error",
    targets: [{ kind: "node", nodeId: "node-1" }],
    ...overrides,
  };
}

function renderPanel() {
  // Phase 72 (help-system) — ValidationPanel's Group-by sliders icon now
  // sits inside a Tooltip + Popover stack. Radix Tooltip requires a
  // TooltipProvider in scope; production mounts it once at the app root
  // (App.tsx). Tests render the panel in isolation, so we wrap here.
  return render(
    <TooltipProvider delayDuration={0}>
      <ValidationPanel />
    </TooltipProvider>,
  );
}

beforeEach(() => {
  useStore.setState({ validationResults: [] });
});

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

// Locate a row by its description text content. There are non-row buttons in
// the panel header (filter pills, settings trigger) and group parents, so a
// plain getByRole("button", { name: ... }) wouldn't disambiguate.
function findRowByDescription(description: string): HTMLElement {
  const row = screen
    .getAllByRole("button")
    .find((b) => b.textContent?.includes(description));
  if (!row) throw new Error(`Row not found: ${description}`);
  return row;
}

describe("ValidationPanel (Phase 72)", () => {
  // ---------------------------------------------------------------------
  // Empty + sort
  // ---------------------------------------------------------------------

  it("renders 'No issues.' when validationResults is empty", () => {
    renderPanel();
    expect(screen.getByText("No issues.")).toBeTruthy();
  });

  it("renders results in severity order (error → warning → info)", () => {
    const results: ValidationResult[] = [
      makeResult({ id: "r-info", severity: "info", validatorId: "info_rule", description: "Info msg" }),
      makeResult({ id: "r-err", severity: "error", validatorId: "err_rule", description: "Error msg" }),
      makeResult({ id: "r-warn", severity: "warning", validatorId: "warn_rule", description: "Warn msg" }),
    ];
    useStore.setState({ validationResults: results });
    renderPanel();

    const rows = screen.getAllByRole("button");
    const texts = rows.map((r) => r.textContent ?? "");
    const errorIdx = texts.findIndex((t) => t.includes("Error msg"));
    const warnIdx = texts.findIndex((t) => t.includes("Warn msg"));
    const infoIdx = texts.findIndex((t) => t.includes("Info msg"));
    expect(errorIdx).toBeLessThan(warnIdx);
    expect(warnIdx).toBeLessThan(infoIdx);
  });

  // ---------------------------------------------------------------------
  // Row click → focus dispatch
  // ---------------------------------------------------------------------

  it("dispatches stream:focus-validation-result on row click", () => {
    const result = makeResult({ id: "r1", description: "Test error" });
    useStore.setState({ validationResults: [result] });
    renderPanel();

    const dispatched: CustomEvent[] = [];
    const spy = (e: Event) => dispatched.push(e as CustomEvent);
    window.addEventListener("stream:focus-validation-result", spy as EventListener);

    fireEvent.click(findRowByDescription("Test error"));

    expect(dispatched.length).toBeGreaterThanOrEqual(1);
    const ev = dispatched.find((e) => e.type === "stream:focus-validation-result");
    expect(ev).toBeTruthy();
    expect((ev as CustomEvent).detail.result.id).toBe("r1");

    window.removeEventListener("stream:focus-validation-result", spy as EventListener);
  });

  it("dispatches stream:open-property-field when result has exactly one field target", () => {
    const result = makeResult({
      id: "r-field",
      description: "Field error",
      targets: [{ kind: "field", nodeId: "node-1", fieldPath: "n" }],
    });
    useStore.setState({ validationResults: [result] });
    renderPanel();

    const fieldEvents: CustomEvent[] = [];
    window.addEventListener("stream:open-property-field", ((e: Event) =>
      fieldEvents.push(e as CustomEvent)) as EventListener);

    fireEvent.click(findRowByDescription("Field error"));

    expect(fieldEvents.length).toBe(1);
    expect(fieldEvents[0].detail.nodeId).toBe("node-1");
    expect(fieldEvents[0].detail.fieldPath).toBe("n");
  });

  // ---------------------------------------------------------------------
  // Severity filter — via window event (status-bar dispatch path)
  // ---------------------------------------------------------------------

  it("filters to only error results when stream:validation-filter severity=error is dispatched", () => {
    const results: ValidationResult[] = [
      makeResult({ id: "e1", severity: "error", description: "Error one" }),
      makeResult({ id: "w1", severity: "warning", description: "Warning one" }),
    ];
    useStore.setState({ validationResults: results });
    renderPanel();

    fireEvent(
      window,
      new CustomEvent("stream:validation-filter", { detail: { severity: "error" } }),
    );

    expect(screen.queryByText("Error one")).toBeTruthy();
    expect(screen.queryByText("Warning one")).toBeFalsy();
  });

  it("replaces a prior severity filter when a new one is dispatched", () => {
    const results: ValidationResult[] = [
      makeResult({ id: "e1", severity: "error", description: "Error one" }),
      makeResult({ id: "w1", severity: "warning", description: "Warning one" }),
    ];
    useStore.setState({ validationResults: results });
    renderPanel();

    fireEvent(
      window,
      new CustomEvent("stream:validation-filter", { detail: { severity: "error" } }),
    );
    expect(screen.queryByText("Error one")).toBeTruthy();
    expect(screen.queryByText("Warning one")).toBeFalsy();

    fireEvent(
      window,
      new CustomEvent("stream:validation-filter", { detail: { severity: "warning" } }),
    );
    expect(screen.queryByText("Error one")).toBeFalsy();
    expect(screen.queryByText("Warning one")).toBeTruthy();
  });

  // ---------------------------------------------------------------------
  // Filter pills (new in Phase 72)
  // ---------------------------------------------------------------------

  it("clicking a severity filter pill activates that filter", () => {
    const results: ValidationResult[] = [
      makeResult({ id: "e1", severity: "error", description: "Error one" }),
      makeResult({ id: "w1", severity: "warning", description: "Warning one" }),
    ];
    useStore.setState({ validationResults: results });
    renderPanel();

    const errorPill = screen.getByRole("button", { name: /^Filter to error$/i });
    fireEvent.click(errorPill);

    expect(screen.queryByText("Error one")).toBeTruthy();
    expect(screen.queryByText("Warning one")).toBeFalsy();
  });

  it("clicking the active severity filter pill clears the filter", () => {
    const results: ValidationResult[] = [
      makeResult({ id: "e1", severity: "error", description: "Error one" }),
      makeResult({ id: "w1", severity: "warning", description: "Warning one" }),
    ];
    useStore.setState({ validationResults: results });
    renderPanel();

    // Activate
    fireEvent.click(screen.getByRole("button", { name: /^Filter to error$/i }));
    expect(screen.queryByText("Warning one")).toBeFalsy();

    // Active aria-label now ends with " (active)"
    const activePill = screen.getByRole("button", { name: /^Filter to error \(active\)$/i });
    fireEvent.click(activePill);

    expect(screen.queryByText("Error one")).toBeTruthy();
    expect(screen.queryByText("Warning one")).toBeTruthy();
  });

  // ---------------------------------------------------------------------
  // Node filter
  // ---------------------------------------------------------------------

  it("filters to only results matching the nodeId when stream:validation-filter-node is dispatched", () => {
    const results: ValidationResult[] = [
      makeResult({
        id: "r-a",
        description: "Node A error",
        targets: [{ kind: "node", nodeId: "node-A" }],
      }),
      makeResult({
        id: "r-b",
        description: "Node B error",
        targets: [{ kind: "node", nodeId: "node-B" }],
      }),
    ];
    useStore.setState({ validationResults: results });
    renderPanel();

    fireEvent(
      window,
      new CustomEvent("stream:validation-filter-node", { detail: { nodeId: "node-A" } }),
    );

    expect(screen.queryByText("Node A error")).toBeTruthy();
    expect(screen.queryByText("Node B error")).toBeFalsy();
  });

  it("clears the node filter when the inline 'clear' link is clicked", () => {
    const results: ValidationResult[] = [
      makeResult({
        id: "r-a",
        description: "Node A error",
        targets: [{ kind: "node", nodeId: "node-A" }],
      }),
      makeResult({
        id: "r-b",
        description: "Node B error",
        targets: [{ kind: "node", nodeId: "node-B" }],
      }),
    ];
    useStore.setState({ validationResults: results });
    renderPanel();

    fireEvent(
      window,
      new CustomEvent("stream:validation-filter-node", { detail: { nodeId: "node-A" } }),
    );
    expect(screen.queryByText("Node B error")).toBeFalsy();

    fireEvent.click(screen.getByText("clear"));

    expect(screen.queryByText("Node A error")).toBeTruthy();
    expect(screen.queryByText("Node B error")).toBeTruthy();
  });

  // ---------------------------------------------------------------------
  // Empty-with-filter + column headers
  // ---------------------------------------------------------------------

  it("shows 'No results match the active filter.' when a filter is active and no results match", () => {
    const results: ValidationResult[] = [
      makeResult({ id: "w1", severity: "warning", description: "Warning one" }),
    ];
    useStore.setState({ validationResults: results });
    renderPanel();

    fireEvent(
      window,
      new CustomEvent("stream:validation-filter", { detail: { severity: "error" } }),
    );

    expect(screen.queryByText("No issues.")).toBeFalsy();
    expect(screen.getByText(/No results match the active filter\./)).toBeTruthy();
  });

  it("renders column-label row (Sev / Rule / Message) when there is at least one result", () => {
    const result = makeResult({
      id: "r1",
      validatorId: "z_n_match",
      description: "n × L mismatch",
    });
    useStore.setState({ validationResults: [result] });
    renderPanel();

    expect(screen.getByText("Sev")).toBeTruthy();
    expect(screen.getByText("Rule")).toBeTruthy();
    expect(screen.getByText("Message")).toBeTruthy();
  });

  it("does NOT render column labels when there are zero results", () => {
    renderPanel();
    expect(screen.queryByText("Sev")).toBeNull();
    expect(screen.queryByText("Rule")).toBeNull();
    expect(screen.queryByText("Message")).toBeNull();
  });

  // ---------------------------------------------------------------------
  // Group-by — popover + parent rows + expand/collapse
  // ---------------------------------------------------------------------

  it("flat-list by default: shows every row without group parents", () => {
    const results: ValidationResult[] = [
      makeResult({ id: "r1", validatorId: "z_n_match", description: "Z-N mismatch A" }),
      makeResult({ id: "r2", validatorId: "z_n_match", description: "Z-N mismatch B" }),
      makeResult({ id: "r3", validatorId: "gravity_sum", severity: "warning", description: "ΣΔh ≠ 0" }),
    ];
    useStore.setState({ validationResults: results });
    renderPanel();

    expect(screen.queryByText("Z-N mismatch A")).toBeTruthy();
    expect(screen.queryByText("Z-N mismatch B")).toBeTruthy();
    expect(screen.queryByText("ΣΔh ≠ 0")).toBeTruthy();
    // No parent row reads "× rule" in flat mode
    expect(screen.queryByText(/× rule/)).toBeNull();
  });

  it("group-by-rule switch via the Group by popover collapses rows by validatorId", () => {
    const results: ValidationResult[] = [
      makeResult({ id: "r1", validatorId: "z_n_match", description: "Z-N mismatch A" }),
      makeResult({ id: "r2", validatorId: "z_n_match", description: "Z-N mismatch B" }),
      makeResult({ id: "r3", validatorId: "gravity_sum", severity: "warning", description: "ΣΔh ≠ 0" }),
    ];
    useStore.setState({ validationResults: results });
    renderPanel();

    // Open the Group by popover and pick "Rule".
    fireEvent.click(screen.getByRole("button", { name: /Group by settings/i }));
    // ToggleGroup items render as toggles; click "Rule".
    fireEvent.click(screen.getByRole("radio", { name: "Rule" }));

    // Both children still rendered (parent expanded by default).
    expect(screen.queryByText("Z-N mismatch A")).toBeTruthy();
    expect(screen.queryByText("Z-N mismatch B")).toBeTruthy();
    // Parent rows: "2 × rule" for z_n_match, "1 × rule" for gravity_sum.
    expect(screen.queryByText("2 × rule")).toBeTruthy();
    expect(screen.queryByText("1 × rule")).toBeTruthy();
  });

  it("collapsing a group parent hides its child rows", () => {
    const results: ValidationResult[] = [
      makeResult({ id: "r1", validatorId: "z_n_match", description: "Z-N mismatch A" }),
      makeResult({ id: "r2", validatorId: "z_n_match", description: "Z-N mismatch B" }),
    ];
    useStore.setState({ validationResults: results });
    renderPanel();

    fireEvent.click(screen.getByRole("button", { name: /Group by settings/i }));
    fireEvent.click(screen.getByRole("radio", { name: "Rule" }));

    // Click the parent ("2 × rule") to collapse.
    const parent = screen.getByText("2 × rule").closest("button");
    expect(parent).toBeTruthy();
    fireEvent.click(parent!);

    expect(screen.queryByText("Z-N mismatch A")).toBeFalsy();
    expect(screen.queryByText("Z-N mismatch B")).toBeFalsy();
    // Parent still rendered after collapse.
    expect(screen.queryByText("2 × rule")).toBeTruthy();
  });

  // ---------------------------------------------------------------------
  // Light sanity on the row body (validator-id column + severity prefix)
  // ---------------------------------------------------------------------

  it("each row renders the validator ID and severity prefix", () => {
    const result = makeResult({
      id: "r1",
      validatorId: "z_n_match",
      description: "n × L mismatch across plate",
    });
    useStore.setState({ validationResults: [result] });
    renderPanel();

    // Validator id should appear in its column (and only its column).
    expect(screen.getByText("z_n_match")).toBeTruthy();
    expect(screen.getByText("n × L mismatch across plate")).toBeTruthy();

    // "ERR" appears in BOTH the filter pill and the row body now. Assert at
    // least one occurrence inside an actual data row (role=button + truncate
    // description matches), via screen.getAllByText.
    const errMatches = screen.getAllByText("ERR");
    expect(errMatches.length).toBeGreaterThanOrEqual(1);

    // Sanity: at least one ERR token sits in a clickable row that ALSO
    // contains the description text.
    const rowWithErrAndDesc = screen
      .getAllByRole("button")
      .find(
        (b) =>
          b.textContent?.includes("ERR") &&
          b.textContent?.includes("n × L mismatch across plate"),
      );
    expect(rowWithErrAndDesc).toBeTruthy();
    expect(within(rowWithErrAndDesc!).getByText("z_n_match")).toBeTruthy();
  });
});
