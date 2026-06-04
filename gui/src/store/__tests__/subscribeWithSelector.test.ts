/**
 * Phase 65 Plan 14 Task 1 (TDD RED) — subscribeWithSelector middleware regression
 *
 * Asserts that `useStore` is wrapped with the `subscribeWithSelector` middleware so
 * consumers can opt into selector-gated edge-only notifications. Backward compatibility
 * is also asserted — the legacy single-arg `subscribe(listener)` overload must still
 * fire on every `set()`.
 *
 * Without the middleware, the 2-arg overload either throws or treats the selector as a
 * listener — both make the "fires only on selected-value change" assertion fail.
 */

import { describe, it, expect, beforeEach, vi } from "vitest";
import useStore from "../useStore";

beforeEach(() => {
  // Clean slate per test
  useStore.setState({ snapToGrid: false, bottomPanelHeight: 240, isDirty: false });
});

describe("subscribeWithSelector middleware", () => {
  it("selector-gated subscribe fires only on selected value change", () => {
    const listener = vi.fn();
    const unsub = useStore.subscribe((s) => s.snapToGrid, listener);

    // Unrelated state change — listener must NOT fire
    useStore.getState().setBottomPanelHeight(300);
    expect(listener).toHaveBeenCalledTimes(0);

    // Selected value changes — listener fires once
    useStore.getState().setSnapToGrid(true);
    expect(listener).toHaveBeenCalledTimes(1);

    // Same value re-set — listener must NOT fire (default === equality)
    useStore.setState({ snapToGrid: true });
    expect(listener).toHaveBeenCalledTimes(1);

    unsub();
  });

  it("backward-compat: single-arg subscribe still fires on every set()", () => {
    const listener = vi.fn();
    const unsub = useStore.subscribe(listener);

    useStore.getState().setBottomPanelHeight(310);
    expect(listener).toHaveBeenCalled();
    const callsAfterFirst = listener.mock.calls.length;

    useStore.getState().setBottomPanelHeight(320);
    expect(listener.mock.calls.length).toBeGreaterThan(callsAfterFirst);

    unsub();
  });

  it("middleware composition preserves existing action behavior", () => {
    // Smoke check: a couple of existing actions still mutate state correctly.
    expect(useStore.getState().snapToGrid).toBe(false);
    useStore.getState().setSnapToGrid(true);
    expect(useStore.getState().snapToGrid).toBe(true);

    expect(useStore.getState().bottomPanelHeight).toBe(240);
    useStore.getState().setBottomPanelHeight(280);
    expect(useStore.getState().bottomPanelHeight).toBe(280);
  });
});
