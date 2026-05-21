// @vitest-environment happy-dom
//
// ValidationStatusBar.test.tsx — Phase 71 Plan 10
//
// Covers:
//   1. Three chips render with correct counts from the store.
//   2. Click on error chip → sets bottomPanelOpen=true, activeBottomTab='validation'.
//   3. Click on error chip dispatches 'stream:validation-filter' with severity='error'.
//   4. Click on warning chip dispatches 'stream:validation-filter' with severity='warning'.
//   5. Click on info chip dispatches 'stream:validation-filter' with severity='info'.
//   6. 0→N error transition adds 'pulse-once' class to the error chip.

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { render, screen, cleanup, fireEvent, act } from "@testing-library/react";
import ValidationStatusBar from "../ValidationStatusBar";
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

function renderBar() {
  return render(<ValidationStatusBar />);
}

// ---------------------------------------------------------------------------
// Setup / teardown
// ---------------------------------------------------------------------------

beforeEach(() => {
  act(() => {
    useStore.setState({
      validationResults: [],
      bottomPanelOpen: false,
      activeBottomTab: "code",
    });
  });
});

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("ValidationStatusBar (Phase 71 D-02 / D-03 / D-05)", () => {
  // -----------------------------------------------------------------------
  // 1. Three chips render with correct counts
  // -----------------------------------------------------------------------
  it("renders three chips with counts derived from validationResults", () => {
    act(() => {
      useStore.setState({
        validationResults: [
          makeResult({ id: "e1", severity: "error" }),
          makeResult({ id: "e2", severity: "error" }),
          makeResult({ id: "w1", severity: "warning" }),
          makeResult({ id: "i1", severity: "info" }),
        ],
      });
    });
    renderBar();

    const errorBtn = screen.getByRole("button", { name: /2 errors/i });
    const warnBtn = screen.getByRole("button", { name: /1 warning/i });
    const infoBtn = screen.getByRole("button", { name: /1 info/i });

    expect(errorBtn).toBeTruthy();
    expect(warnBtn).toBeTruthy();
    expect(infoBtn).toBeTruthy();
  });

  it("renders chips with count 0 when validationResults is empty", () => {
    renderBar();
    const errorBtn = screen.getByRole("button", { name: /0 errors/i });
    const warnBtn = screen.getByRole("button", { name: /0 warnings/i });
    const infoBtn = screen.getByRole("button", { name: /0 info/i });
    expect(errorBtn).toBeTruthy();
    expect(warnBtn).toBeTruthy();
    expect(infoBtn).toBeTruthy();
  });

  // -----------------------------------------------------------------------
  // 2. Click on error chip → store side effect
  // -----------------------------------------------------------------------
  it("clicking the error chip opens the panel and switches to the Validation tab", () => {
    renderBar();
    const errorBtn = screen.getByRole("button", { name: /errors/i });
    fireEvent.click(errorBtn);

    const state = useStore.getState();
    expect(state.bottomPanelOpen).toBe(true);
    expect(state.activeBottomTab).toBe("validation");
  });

  // -----------------------------------------------------------------------
  // 3. Error chip dispatch
  // -----------------------------------------------------------------------
  it("clicking the error chip dispatches stream:validation-filter with severity='error'", () => {
    renderBar();
    const received: CustomEvent[] = [];
    const listener = (e: Event) => received.push(e as CustomEvent);
    window.addEventListener("stream:validation-filter", listener);

    try {
      const errorBtn = screen.getByRole("button", { name: /errors/i });
      fireEvent.click(errorBtn);
      expect(received).toHaveLength(1);
      expect((received[0] as CustomEvent).detail.severity).toBe("error");
    } finally {
      window.removeEventListener("stream:validation-filter", listener);
    }
  });

  // -----------------------------------------------------------------------
  // 4. Warning chip dispatch
  // -----------------------------------------------------------------------
  it("clicking the warning chip dispatches stream:validation-filter with severity='warning'", () => {
    renderBar();
    const received: CustomEvent[] = [];
    const listener = (e: Event) => received.push(e as CustomEvent);
    window.addEventListener("stream:validation-filter", listener);

    try {
      const warnBtn = screen.getByRole("button", { name: /warnings/i });
      fireEvent.click(warnBtn);
      expect(received).toHaveLength(1);
      expect((received[0] as CustomEvent).detail.severity).toBe("warning");
    } finally {
      window.removeEventListener("stream:validation-filter", listener);
    }
  });

  // -----------------------------------------------------------------------
  // 5. Info chip dispatch
  // -----------------------------------------------------------------------
  it("clicking the info chip dispatches stream:validation-filter with severity='info'", () => {
    renderBar();
    const received: CustomEvent[] = [];
    const listener = (e: Event) => received.push(e as CustomEvent);
    window.addEventListener("stream:validation-filter", listener);

    try {
      const infoBtn = screen.getByRole("button", { name: /0 info/i });
      fireEvent.click(infoBtn);
      expect(received).toHaveLength(1);
      expect((received[0] as CustomEvent).detail.severity).toBe("info");
    } finally {
      window.removeEventListener("stream:validation-filter", listener);
    }
  });

  // -----------------------------------------------------------------------
  // 6. 0→N pulse: error chip gets 'pulse-once' class on 0→N transition
  // -----------------------------------------------------------------------
  it("adds pulse-once class to error chip when error count rises from 0 to N", async () => {
    renderBar();

    // Start with no errors — confirmed already in beforeEach
    const buttons = screen.getAllByRole("button");
    // The error chip is the first chip button (leftmost)
    const errorBtn = buttons.find((b) => (b.getAttribute("aria-label") ?? "").includes("error"));
    expect(errorBtn).toBeTruthy();

    // Transition from 0 → 1 error
    act(() => {
      useStore.setState({
        validationResults: [makeResult({ id: "e1", severity: "error" })],
      });
    });

    // After re-render, the error chip should carry the pulse-once class.
    // Note: the class is removed after 700ms via setTimeout; we only check
    // that it was applied (the clearTimeout in the component handles teardown).
    const updatedBtn = screen.getByRole("button", { name: /1 error/i });
    expect(updatedBtn.className).toContain("pulse-once");
  });
});
