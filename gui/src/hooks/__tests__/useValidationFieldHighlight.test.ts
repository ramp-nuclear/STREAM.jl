// @vitest-environment jsdom
/**
 * useValidationFieldHighlight.test.ts — Phase 71 Plan 11
 *
 * Tests the core highlight logic extracted from useValidationFieldHighlight.
 * We test the observable DOM mutations directly (no React renderer needed)
 * since the hook body is a pure DOM side-effect function.
 *
 * Test plan:
 *   1. Matching error target: applies .validation-field-error to the matching element
 *   2. Warning severity: applies .validation-field-warning instead
 *   3. Clear-on-change: prior highlights cleared before new ones applied
 *   4. No-op body when selectedNodeId is null (clear still runs)
 *   5. CSS.escape: fieldPath 'geom.L' (contains dot) matches attribute correctly
 *   6. Wrong nodeId: result for a different node does not paint this container
 */

import { describe, it, expect, beforeEach } from "vitest";
import type { ValidationResult } from "../../lib/validation/types";

// ---------------------------------------------------------------------------
// CSS.escape polyfill — jsdom does not always expose the CSS global.
// Must run before any code that calls CSS.escape.
// ---------------------------------------------------------------------------
if (typeof globalThis.CSS === "undefined") {
  (globalThis as unknown as Record<string, unknown>).CSS = {};
}
if (typeof (globalThis.CSS as unknown as Record<string, unknown>).escape !== "function") {
  (globalThis.CSS as unknown as Record<string, unknown>).escape = (value: string): string =>
    String(value).replace(/([^\w-￿-])/g, "\\$1");
}

// ---------------------------------------------------------------------------
// Highlight logic (extracted from the hook's useEffect body for direct testing).
// This is the exact algorithm used in useValidationFieldHighlight.ts.
// ---------------------------------------------------------------------------

function runHighlightEffect(
  container: HTMLElement,
  selectedNodeId: string | null,
  results: ValidationResult[],
): void {
  container.querySelectorAll("[data-field-path]").forEach((el) => {
    el.classList.remove("validation-field-error", "validation-field-warning");
  });

  if (!selectedNodeId) return;

  for (const result of results) {
    for (const target of result.targets) {
      if (target.kind !== "field" || target.nodeId !== selectedNodeId) continue;
      const el = container.querySelector(
        `[data-field-path="${CSS.escape(target.fieldPath)}"]`,
      );
      if (!el) continue;
      const cls =
        result.severity === "error"
          ? "validation-field-error"
          : result.severity === "warning"
            ? "validation-field-warning"
            : null;
      if (cls) el.classList.add(cls);
    }
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeContainer(): HTMLElement {
  const container = document.createElement("div");
  container.innerHTML = `
    <div data-field-path="n"></div>
    <div data-field-path="geom.L"></div>
    <div data-field-path="T_wall_left"></div>
  `;
  return container;
}

function makeFieldResult(
  nodeId: string,
  fieldPath: string,
  severity: "error" | "warning" | "info" = "error",
): ValidationResult {
  return {
    id: `${nodeId}:${fieldPath}`,
    validatorId: "test_validator",
    severity,
    description: `Test result for ${fieldPath}`,
    targets: [{ kind: "field", nodeId, fieldPath }],
  };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("useValidationFieldHighlight DOM logic", () => {
  let container: HTMLElement;

  beforeEach(() => {
    container = makeContainer();
  });

  it("applies .validation-field-error to matching data-field-path element", () => {
    runHighlightEffect(container, "node-1", [makeFieldResult("node-1", "n", "error")]);

    const nField = container.querySelector('[data-field-path="n"]');
    expect(nField?.classList.contains("validation-field-error")).toBe(true);
    // Other fields remain clean
    const geomField = container.querySelector('[data-field-path="geom.L"]');
    expect(geomField?.classList.contains("validation-field-error")).toBe(false);
  });

  it("applies .validation-field-warning for warning severity", () => {
    runHighlightEffect(container, "node-1", [makeFieldResult("node-1", "T_wall_left", "warning")]);

    const field = container.querySelector('[data-field-path="T_wall_left"]');
    expect(field?.classList.contains("validation-field-warning")).toBe(true);
    expect(field?.classList.contains("validation-field-error")).toBe(false);
  });

  it("clears prior highlights before applying new ones on re-run", () => {
    // First run: error on 'n'
    runHighlightEffect(container, "node-1", [makeFieldResult("node-1", "n", "error")]);
    expect(
      container.querySelector('[data-field-path="n"]')?.classList.contains("validation-field-error"),
    ).toBe(true);

    // Second run: different result — 'n' error cleared, warning on 'T_wall_left' applied
    runHighlightEffect(container, "node-1", [makeFieldResult("node-1", "T_wall_left", "warning")]);

    expect(container.querySelector('[data-field-path="n"]')?.classList.contains("validation-field-error")).toBe(false);
    expect(container.querySelector('[data-field-path="T_wall_left"]')?.classList.contains("validation-field-warning")).toBe(true);
  });

  it("clears all highlights and skips re-apply when selectedNodeId is null", () => {
    // Pre-paint manually
    container.querySelector('[data-field-path="n"]')!.classList.add("validation-field-error");

    runHighlightEffect(container, null, [makeFieldResult("node-1", "n", "error")]);

    // Clear step removes the class; null selectedNodeId skips re-apply
    expect(container.querySelector('[data-field-path="n"]')?.classList.contains("validation-field-error")).toBe(false);
  });

  it("handles fieldPath with dot notation via CSS.escape", () => {
    runHighlightEffect(container, "node-1", [makeFieldResult("node-1", "geom.L", "error")]);

    const field = container.querySelector('[data-field-path="geom.L"]');
    expect(field).not.toBeNull();
    expect(field?.classList.contains("validation-field-error")).toBe(true);
  });

  it("does not paint when result targets a different nodeId", () => {
    runHighlightEffect(container, "node-1", [makeFieldResult("node-2", "n", "error")]);

    expect(container.querySelector('[data-field-path="n"]')?.classList.contains("validation-field-error")).toBe(false);
  });
});
