// @vitest-environment happy-dom
//
// ValidationPanel.test.tsx — Phase 71 Plan 09
//
// Tests for ValidationPanel: empty state, sort order, click-to-focus
// CustomEvent dispatch, severity + node filter CustomEvents, clear-filter,
// and all three fix-action button kinds (lossless-sync, value-transfer-picker,
// navigation-only). Covers D-04, D-05, D-14.

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { render, screen, cleanup, fireEvent } from "@testing-library/react";
import ValidationPanel from "../ValidationPanel";
import useStore from "../../store/useStore";
import type { ValidationResult } from "../../lib/validation/types";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

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
  return render(<ValidationPanel />);
}

// ---------------------------------------------------------------------------
// Setup / teardown
// ---------------------------------------------------------------------------

beforeEach(() => {
  useStore.setState({ validationResults: [] });
});

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("ValidationPanel", () => {
  // -----------------------------------------------------------------------
  // 1. Empty state
  // -----------------------------------------------------------------------
  it("renders 'No issues.' when validationResults is empty and no filter is active", () => {
    renderPanel();
    expect(screen.getByText("No issues.")).toBeTruthy();
  });

  // -----------------------------------------------------------------------
  // 2. Sort order: error → warning → info, then validatorId within each bucket
  // -----------------------------------------------------------------------
  it("renders three results in severity order (error → warning → info)", () => {
    const results: ValidationResult[] = [
      makeResult({ id: "r-info", severity: "info", validatorId: "info_rule", description: "Info msg" }),
      makeResult({ id: "r-err", severity: "error", validatorId: "err_rule", description: "Error msg" }),
      makeResult({ id: "r-warn", severity: "warning", validatorId: "warn_rule", description: "Warn msg" }),
    ];
    useStore.setState({ validationResults: results });
    renderPanel();

    const rows = screen.getAllByRole("button");
    // Row order is based on which text appears first in the DOM.
    const texts = rows.map((r) => r.textContent ?? "");
    const errorIdx = texts.findIndex((t) => t.includes("Error msg"));
    const warnIdx = texts.findIndex((t) => t.includes("Warn msg"));
    const infoIdx = texts.findIndex((t) => t.includes("Info msg"));
    expect(errorIdx).toBeLessThan(warnIdx);
    expect(warnIdx).toBeLessThan(infoIdx);
  });

  // -----------------------------------------------------------------------
  // 3. Row click dispatches 'stream:focus-validation-result'
  // -----------------------------------------------------------------------
  it("dispatches stream:focus-validation-result on row click", () => {
    const result = makeResult({ id: "r1", description: "Test error" });
    useStore.setState({ validationResults: [result] });
    renderPanel();

    const dispatched: CustomEvent[] = [];
    const spy = (e: Event) => dispatched.push(e as CustomEvent);
    window.addEventListener("stream:focus-validation-result", spy as EventListener);

    // Find the row by its text content (the row div has role=button).
    const allButtons = screen.getAllByRole("button");
    const rowBtn = allButtons.find((b) => b.textContent?.includes("Test error"));
    expect(rowBtn).toBeTruthy();
    fireEvent.click(rowBtn!);

    expect(dispatched.length).toBeGreaterThanOrEqual(1);
    const ev = dispatched.find((e) => e.type === "stream:focus-validation-result");
    expect(ev).toBeTruthy();
    expect((ev as CustomEvent).detail.result.id).toBe("r1");

    window.removeEventListener("stream:focus-validation-result", spy as EventListener);
  });

  // -----------------------------------------------------------------------
  // 4. Row click with single field target also dispatches stream:open-property-field
  // -----------------------------------------------------------------------
  it("dispatches stream:open-property-field when result has exactly one field target", () => {
    const result = makeResult({
      id: "r-field",
      description: "Field error",
      targets: [{ kind: "field", nodeId: "node-1", fieldPath: "n" }],
    });
    useStore.setState({ validationResults: [result] });
    renderPanel();

    const focusEvents: CustomEvent[] = [];
    const fieldEvents: CustomEvent[] = [];
    const spyFocus = (e: Event) => focusEvents.push(e as CustomEvent);
    const spyField = (e: Event) => fieldEvents.push(e as CustomEvent);
    window.addEventListener("stream:focus-validation-result", spyFocus as EventListener);
    window.addEventListener("stream:open-property-field", spyField as EventListener);

    const allButtons = screen.getAllByRole("button");
    const rowBtn = allButtons.find((b) => b.textContent?.includes("Field error"));
    fireEvent.click(rowBtn!);

    expect(focusEvents.length).toBeGreaterThanOrEqual(1);
    expect(fieldEvents.length).toBe(1);
    expect(fieldEvents[0].detail.nodeId).toBe("node-1");
    expect(fieldEvents[0].detail.fieldPath).toBe("n");

    window.removeEventListener("stream:focus-validation-result", spyFocus as EventListener);
    window.removeEventListener("stream:open-property-field", spyField as EventListener);
  });

  // -----------------------------------------------------------------------
  // 5. stream:validation-filter event filters list to that severity
  // -----------------------------------------------------------------------
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

  // -----------------------------------------------------------------------
  // 6. stream:validation-filter REPLACES the prior filter (no stacking)
  // -----------------------------------------------------------------------
  it("replaces a prior severity filter when a new one is dispatched", () => {
    const results: ValidationResult[] = [
      makeResult({ id: "e1", severity: "error", description: "Error one" }),
      makeResult({ id: "w1", severity: "warning", description: "Warning one" }),
    ];
    useStore.setState({ validationResults: results });
    renderPanel();

    // First: filter to error
    fireEvent(
      window,
      new CustomEvent("stream:validation-filter", { detail: { severity: "error" } }),
    );
    expect(screen.queryByText("Error one")).toBeTruthy();
    expect(screen.queryByText("Warning one")).toBeFalsy();

    // Then: switch to warning — error row must disappear
    fireEvent(
      window,
      new CustomEvent("stream:validation-filter", { detail: { severity: "warning" } }),
    );
    expect(screen.queryByText("Error one")).toBeFalsy();
    expect(screen.queryByText("Warning one")).toBeTruthy();
  });

  // -----------------------------------------------------------------------
  // 7. stream:validation-filter-node filters to results matching that nodeId
  // -----------------------------------------------------------------------
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

  // -----------------------------------------------------------------------
  // 8. Clear filter button restores full list
  // -----------------------------------------------------------------------
  it("removes the filter and shows all results when Clear filter is clicked", () => {
    const results: ValidationResult[] = [
      makeResult({ id: "e1", severity: "error", description: "Error one" }),
      makeResult({ id: "w1", severity: "warning", description: "Warning one" }),
    ];
    useStore.setState({ validationResults: results });
    renderPanel();

    // Activate filter
    fireEvent(
      window,
      new CustomEvent("stream:validation-filter", { detail: { severity: "error" } }),
    );
    expect(screen.queryByText("Warning one")).toBeFalsy();

    // Clear it
    const clearBtn = screen.getByText("Clear filter");
    fireEvent.click(clearBtn);

    expect(screen.queryByText("Error one")).toBeTruthy();
    expect(screen.queryByText("Warning one")).toBeTruthy();
  });

  // -----------------------------------------------------------------------
  // 9. Filtered empty state shows "No results match the active filter."
  // -----------------------------------------------------------------------
  it("shows 'No results match the active filter.' when a filter is active and no results match", () => {
    const results: ValidationResult[] = [
      makeResult({ id: "w1", severity: "warning", description: "Warning one" }),
    ];
    useStore.setState({ validationResults: results });
    renderPanel();

    // Filter to error — no error results exist
    fireEvent(
      window,
      new CustomEvent("stream:validation-filter", { detail: { severity: "error" } }),
    );

    expect(screen.queryByText("No issues.")).toBeFalsy();
    expect(screen.getByText("No results match the active filter.")).toBeTruthy();
  });

  // -----------------------------------------------------------------------
  // 10. No fix-action buttons when result has no fixAction
  // -----------------------------------------------------------------------
  it("renders no fix-action buttons when result.fixAction is undefined", () => {
    const result = makeResult({ id: "r1", description: "Plain error", fixAction: undefined });
    useStore.setState({ validationResults: [result] });
    renderPanel();

    // Only the row itself is a button (role=button on the row div)
    const buttons = screen.getAllByRole("button");
    // The row itself counts as a button. There should be no Button components
    // rendered — just the row. The Button component renders a <button> element.
    // We confirm there is no <button> with text that would come from a fix label.
    const buttonTexts = buttons.map((b) => b.tagName.toLowerCase() + ":" + (b.textContent ?? "").trim());
    const hasSyncButton = buttonTexts.some((t) => t.startsWith("button:") && t.length > "button:".length && !t.includes("Plain error") && !t.includes("test_validator"));
    expect(hasSyncButton).toBe(false);
  });

  // -----------------------------------------------------------------------
  // 11. lossless-sync: renders one button, clicking calls apply, no row dispatch
  // -----------------------------------------------------------------------
  it("renders a single button for lossless-sync and calls apply on click without row focus event", () => {
    const applySpy = vi.fn();
    const result = makeResult({
      id: "r-sync",
      description: "Sync error",
      fixAction: { kind: "lossless-sync", label: "Sync n to 5", apply: applySpy },
    });
    useStore.setState({ validationResults: [result] });
    renderPanel();

    // Find the fix button by its label text
    const syncBtn = screen.getByText("Sync n to 5");
    expect(syncBtn).toBeTruthy();

    // Set up spy on window.dispatchEvent to assert row event NOT fired
    const dispatchedEvents: string[] = [];
    const dispatchSpy = vi.spyOn(window, "dispatchEvent").mockImplementation((e) => {
      dispatchedEvents.push((e as Event).type);
      return true;
    });

    fireEvent.click(syncBtn);

    // apply called exactly once with two function args
    expect(applySpy).toHaveBeenCalledTimes(1);
    expect(typeof applySpy.mock.calls[0][0]).toBe("function");
    expect(typeof applySpy.mock.calls[0][1]).toBe("function");

    // Row focus event must NOT have been dispatched
    expect(dispatchedEvents).not.toContain("stream:focus-validation-result");

    dispatchSpy.mockRestore();
  });

  // -----------------------------------------------------------------------
  // 12. value-transfer-picker: two buttons, each calls the correct closure
  // -----------------------------------------------------------------------
  it("renders two buttons for value-transfer-picker and routes clicks to the correct closure", () => {
    const leftSpy = vi.fn();
    const rightSpy = vi.fn();
    const result = makeResult({
      id: "r-picker",
      description: "Picker error",
      fixAction: {
        kind: "value-transfer-picker",
        leftLabel: "Use 0.5",
        rightLabel: "Use 0.6",
        applyLeft: leftSpy,
        applyRight: rightSpy,
      },
    });
    useStore.setState({ validationResults: [result] });
    renderPanel();

    const leftBtn = screen.getByText("Use 0.5");
    const rightBtn = screen.getByText("Use 0.6");
    expect(leftBtn).toBeTruthy();
    expect(rightBtn).toBeTruthy();

    // Click left — only leftSpy called
    fireEvent.click(leftBtn);
    expect(leftSpy).toHaveBeenCalledTimes(1);
    expect(rightSpy).not.toHaveBeenCalled();

    // Click right — only rightSpy called (leftSpy still 1)
    fireEvent.click(rightBtn);
    expect(rightSpy).toHaveBeenCalledTimes(1);
    expect(leftSpy).toHaveBeenCalledTimes(1);
  });

  // -----------------------------------------------------------------------
  // 13. navigation-only: ghost button triggers the focus event like a row click
  // -----------------------------------------------------------------------
  it("renders a ghost button for navigation-only that triggers focus-validation-result", () => {
    const result = makeResult({
      id: "r-nav",
      description: "Nav error",
      fixAction: { kind: "navigation-only", label: "Go to component" },
    });
    useStore.setState({ validationResults: [result] });
    renderPanel();

    const navBtn = screen.getByText("Go to component");
    expect(navBtn).toBeTruthy();

    const dispatchedEvents: string[] = [];
    const dispatchSpy = vi.spyOn(window, "dispatchEvent").mockImplementation((e) => {
      dispatchedEvents.push((e as Event).type);
      return true;
    });

    fireEvent.click(navBtn);

    expect(dispatchedEvents).toContain("stream:focus-validation-result");

    dispatchSpy.mockRestore();
  });
});
