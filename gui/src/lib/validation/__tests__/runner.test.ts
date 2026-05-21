// runner.test.ts — Unit tests for the validator runner (Phase 71)
//
// Environment: node (vitest.config.ts default — no JSDOM needed for pure functions).
// Tests pin:
//   1. Empty registry → runValidators returns []
//   2. Stub validator → runValidators returns its results
//   3. FixAction lossless-sync apply closure invocation (contract pin)

import { describe, it, expect, vi, beforeEach } from "vitest";
import type { ValidationSnapshot } from "../snapshot";
import type { ValidationResult, Validator } from "../types";

// ---------------------------------------------------------------------------
// vi.mock declarations must be at the top level (vitest hoisting requirement).
// We use a mutable module-level variable that each test can write before import.
// ---------------------------------------------------------------------------

// Mutable validators array — tests override this before importing runner.
const _validators: Validator[] = [];

vi.mock("../index", () => ({
  get validators() {
    return _validators;
  },
}));

// ---------------------------------------------------------------------------
// Synthetic snapshot factory (empty canvas)
// ---------------------------------------------------------------------------

function makeEmptySnapshot(): ValidationSnapshot {
  return {
    nodes: [],
    edges: [],
    anchors: {},
    bcMode: {},
    resources: {
      geometries: {},
      powerShapes: {},
      fluids: {},
    },
    getComponentDef: (_id: string) => undefined,
  };
}

// Import runner AFTER the mock is declared.
import { runValidators } from "../runner";

// ---------------------------------------------------------------------------
// Test 1: empty registry → empty results
// ---------------------------------------------------------------------------

describe("runValidators", () => {
  beforeEach(() => {
    // Clear validators before each test
    _validators.length = 0;
  });

  it("returns [] when no validators are registered", () => {
    const snapshot = makeEmptySnapshot();
    const results = runValidators(snapshot);
    expect(results).toEqual([]);
  });

  // ---------------------------------------------------------------------------
  // Test 2: stub validator → results forwarded
  // ---------------------------------------------------------------------------

  it("returns results from a stub validator", () => {
    const stubResult: ValidationResult = {
      id: "stub::test",
      validatorId: "stub",
      severity: "warning",
      description: "Stub warning",
      targets: [],
    };

    const stubValidator: Validator = {
      id: "stub",
      severity: "warning",
      description: "Stub validator",
      scope: ["nodes"],
      run: (_snapshot) => [stubResult],
    };

    _validators.push(stubValidator);

    const snapshot = makeEmptySnapshot();
    const results = runValidators(snapshot);
    expect(results).toHaveLength(1);
    expect(results[0]).toEqual(stubResult);
  });

  // ---------------------------------------------------------------------------
  // Test 3: FixAction lossless-sync apply closure — contract pin
  //
  // This test verifies the FixAction shape at both the type level and runtime
  // level: a ValidationResult with a 'lossless-sync' fixAction can be
  // constructed, and its apply() can be invoked with (mockSet, mockGet).
  // ---------------------------------------------------------------------------

  it("invokes lossless-sync apply with set and get handles", () => {
    const mockSet = vi.fn();
    const mockGet = vi.fn(() => ({}));

    const result: ValidationResult = {
      id: "test::lossless",
      validatorId: "test",
      severity: "warning",
      description: "Test lossless-sync fix action",
      targets: [{ kind: "node", nodeId: "n1" }],
      fixAction: {
        kind: "lossless-sync",
        label: "Sync n to 10",
        apply: (set, get) => {
          // Closure uses get() to read fresh state and set() to apply fix.
          // In real rules the closure would call set({ someField: value }).
          void get();
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          (set as any)({ nodes: [] });
        },
      },
    };

    // Verify the FixAction discriminant is correct
    expect(result.fixAction).toBeDefined();
    expect(result.fixAction!.kind).toBe("lossless-sync");

    // Invoke the apply closure with mock handles (as ValidationPanel will at click time)
    if (result.fixAction?.kind === "lossless-sync") {
      const fa = result.fixAction;
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      fa.apply(mockSet as any, mockGet as any);
    }

    // Both handles should have been called exactly once
    expect(mockGet).toHaveBeenCalledOnce();
    expect(mockSet).toHaveBeenCalledOnce();
  });
});
