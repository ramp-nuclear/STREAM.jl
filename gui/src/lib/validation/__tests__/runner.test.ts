// runner.test.ts — Unit tests for the validator runner.
//
// Environment: node (vitest.config.ts default — no JSDOM needed for pure functions).
// Tests pin:
//   1. Empty registry → runValidators returns []
//   2. Stub validator → runValidators returns its results
//
// Phase 72: the third test (FixAction lossless-sync apply closure contract)
// was removed when the FixAction type was deleted from ValidationResult.

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

    // Phase 72 — runner short-circuits to [] when the canvas is fully empty
    // (no nodes AND no edges). Use a snapshot with at least one node so the
    // forwarding path is exercised.
    const snapshot: ValidationSnapshot = {
      ...makeEmptySnapshot(),
      nodes: [
        // Minimal node shape — runner doesn't inspect data; the stub
        // validator ignores its argument.
        { id: "n1", type: "stream", position: { x: 0, y: 0 }, data: {} } as never,
      ],
    };
    const results = runValidators(snapshot);
    expect(results).toHaveLength(1);
    expect(results[0]).toEqual(stubResult);
  });

  // Phase 72 — empty-canvas suppression.
  it("returns [] when the canvas is fully empty, regardless of registered validators", () => {
    const stubValidator: Validator = {
      id: "stub",
      severity: "warning",
      description: "Stub validator",
      scope: ["nodes"],
      run: () => [
        {
          id: "stub::would-fire",
          validatorId: "stub",
          severity: "warning",
          description: "Would fire if not for the empty-canvas short-circuit",
          targets: [],
        },
      ],
    };

    _validators.push(stubValidator);

    const snapshot = makeEmptySnapshot();
    expect(runValidators(snapshot)).toEqual([]);
  });

});
