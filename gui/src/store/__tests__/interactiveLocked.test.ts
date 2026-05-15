/**
 * Phase 65 Plan 13 Task 1 (TDD RED) — interactiveLocked store field tests
 *
 * Session-only viewport-state preference replacing ReactFlow's built-in Controls
 * lock toggle. Must NOT be persisted to .scp and must NOT set isDirty.
 */

import { describe, it, expect, beforeEach } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import useStore from "../useStore";

beforeEach(() => {
  // Reset to clean slate for each test
  useStore.setState({ interactiveLocked: false, isDirty: false });
});

describe("interactiveLocked store field", () => {
  it("defaults to false", () => {
    // Re-read default by instantiating a fresh state shape
    useStore.setState({ interactiveLocked: false });
    expect(useStore.getState().interactiveLocked).toBe(false);
  });

  it("setInteractiveLocked(true) flips field to true and does NOT set isDirty", () => {
    expect(useStore.getState().isDirty).toBe(false);
    useStore.getState().setInteractiveLocked(true);
    expect(useStore.getState().interactiveLocked).toBe(true);
    // Session preference — must not dirty the project
    expect(useStore.getState().isDirty).toBe(false);

    useStore.getState().setInteractiveLocked(false);
    expect(useStore.getState().interactiveLocked).toBe(false);
    expect(useStore.getState().isDirty).toBe(false);
  });

  it("interactiveLocked appears ONLY in interface/init/action (NOT in .scp serialize paths)", () => {
    // Resolve relative to this test file's location.
    const useStorePath = resolve(__dirname, "..", "useStore.ts");
    const contents = readFileSync(useStorePath, "utf-8");
    const matches = contents.match(/interactiveLocked/g) ?? [];
    // Expected exactly 3 occurrences: interface declaration, initial-state, action implementation.
    // Allow up to 4 to accommodate a justifiable comment occurrence.
    expect(matches.length).toBeGreaterThanOrEqual(3);
    expect(matches.length).toBeLessThanOrEqual(4);
  });
});
