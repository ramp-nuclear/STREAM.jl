// @vitest-environment happy-dom
//
// ValidationStatusBar.test.tsx — Phase 72 (unified bottom-chrome footer +
// status-bar tabs).
//
// Covers:
//   1. Three severity segments render with correct counts.
//   2. Click on a severity segment → opens panel + Validation tab + dispatches filter.
//   3. 0 → N error transition flags the error segment for `pulse-once`.
//   4. Code + Validation tab buttons always render (left-of-chevron right cluster).
//   5. Click an inactive tab while closed → opens panel on that tab.
//   6. Click the active tab while open → closes panel.
//   7. Click an inactive tab while open → switches active tab, panel stays open.
//   8. Close chevron renders only when the panel is open.

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { render, screen, cleanup, fireEvent, act } from "@testing-library/react";
import ValidationStatusBar from "../ValidationStatusBar";
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

function renderBar() {
  return render(<ValidationStatusBar />);
}

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

describe("ValidationStatusBar (Phase 72 with tabs)", () => {
  it("renders three severity segments with counts derived from validationResults", () => {
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

    expect(screen.getByRole("button", { name: /2 errors/i })).toBeTruthy();
    expect(screen.getByRole("button", { name: /1 warning/i })).toBeTruthy();
    expect(screen.getByRole("button", { name: /1 info/i })).toBeTruthy();
  });

  it("renders segments with count 0 when validationResults is empty", () => {
    renderBar();
    expect(screen.getByRole("button", { name: /0 errors/i })).toBeTruthy();
    expect(screen.getByRole("button", { name: /0 warnings/i })).toBeTruthy();
    expect(screen.getByRole("button", { name: /0 info/i })).toBeTruthy();
  });

  it("clicking the error segment opens the panel and switches to the Validation tab", () => {
    renderBar();
    fireEvent.click(screen.getByRole("button", { name: /errors/i }));
    const state = useStore.getState();
    expect(state.bottomPanelOpen).toBe(true);
    expect(state.activeBottomTab).toBe("validation");
  });

  it("clicking the error segment dispatches stream:validation-filter with severity='error'", () => {
    renderBar();
    const received: CustomEvent[] = [];
    const listener = (e: Event) => received.push(e as CustomEvent);
    window.addEventListener("stream:validation-filter", listener);
    try {
      fireEvent.click(screen.getByRole("button", { name: /errors/i }));
      expect(received).toHaveLength(1);
      expect((received[0] as CustomEvent).detail.severity).toBe("error");
    } finally {
      window.removeEventListener("stream:validation-filter", listener);
    }
  });

  it("clicking the warning segment dispatches stream:validation-filter with severity='warning'", () => {
    renderBar();
    const received: CustomEvent[] = [];
    const listener = (e: Event) => received.push(e as CustomEvent);
    window.addEventListener("stream:validation-filter", listener);
    try {
      fireEvent.click(screen.getByRole("button", { name: /warnings/i }));
      expect(received).toHaveLength(1);
      expect((received[0] as CustomEvent).detail.severity).toBe("warning");
    } finally {
      window.removeEventListener("stream:validation-filter", listener);
    }
  });

  it("clicking the info segment dispatches stream:validation-filter with severity='info'", () => {
    renderBar();
    const received: CustomEvent[] = [];
    const listener = (e: Event) => received.push(e as CustomEvent);
    window.addEventListener("stream:validation-filter", listener);
    try {
      fireEvent.click(screen.getByRole("button", { name: /0 info/i }));
      expect(received).toHaveLength(1);
      expect((received[0] as CustomEvent).detail.severity).toBe("info");
    } finally {
      window.removeEventListener("stream:validation-filter", listener);
    }
  });

  it("adds pulse-once class to error segment when error count rises from 0 to N", () => {
    renderBar();

    act(() => {
      useStore.setState({
        validationResults: [makeResult({ id: "e1", severity: "error" })],
      });
    });

    const updatedBtn = screen.getByRole("button", { name: /1 error/i });
    expect(updatedBtn.className).toContain("pulse-once");
  });

  // -----------------------------------------------------------------------
  // Phase 72 tab control — Code | Validation in the right cluster.
  // -----------------------------------------------------------------------

  it("renders both Code and Validation tabs when the panel is closed", () => {
    renderBar();
    expect(screen.getByRole("tab", { name: /Open code panel/i })).toBeTruthy();
    expect(screen.getByRole("tab", { name: /Open validation panel/i })).toBeTruthy();
  });

  it("clicking the Code tab while closed opens the panel on the Code tab", () => {
    renderBar();
    fireEvent.click(screen.getByRole("tab", { name: /Open code panel/i }));
    const state = useStore.getState();
    expect(state.bottomPanelOpen).toBe(true);
    expect(state.activeBottomTab).toBe("code");
  });

  it("clicking the Validation tab while closed opens the panel on the Validation tab", () => {
    renderBar();
    fireEvent.click(screen.getByRole("tab", { name: /Open validation panel/i }));
    const state = useStore.getState();
    expect(state.bottomPanelOpen).toBe(true);
    expect(state.activeBottomTab).toBe("validation");
  });

  it("clicking the active tab while open closes the panel", () => {
    act(() => {
      useStore.setState({ bottomPanelOpen: true, activeBottomTab: "code" });
    });
    renderBar();
    fireEvent.click(screen.getByRole("tab", { name: /Close code panel/i }));
    expect(useStore.getState().bottomPanelOpen).toBe(false);
  });

  it("clicking the inactive tab while open switches active tab without closing", () => {
    act(() => {
      useStore.setState({ bottomPanelOpen: true, activeBottomTab: "code" });
    });
    renderBar();
    fireEvent.click(screen.getByRole("tab", { name: /Switch to validation panel/i }));
    const state = useStore.getState();
    expect(state.bottomPanelOpen).toBe(true);
    expect(state.activeBottomTab).toBe("validation");
  });

  it("renders an explicit Close bottom panel chevron only when the panel is open", () => {
    renderBar();
    expect(screen.queryByRole("button", { name: /Close bottom panel/i })).toBeNull();

    act(() => {
      useStore.setState({ bottomPanelOpen: true });
    });

    expect(screen.getByRole("button", { name: /Close bottom panel/i })).toBeTruthy();
  });

  it("clicking the close chevron closes the panel", () => {
    act(() => {
      useStore.setState({ bottomPanelOpen: true, activeBottomTab: "code" });
    });
    renderBar();
    fireEvent.click(screen.getByRole("button", { name: /Close bottom panel/i }));
    expect(useStore.getState().bottomPanelOpen).toBe(false);
  });
});
