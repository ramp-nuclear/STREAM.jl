// fields.test.ts — Unit tests for field validation helpers (Phase 71)
//
// Copied from gui/src/lib/validation.test.ts assertions for
// validateInt/validateReal/validatePositiveReal/validateJuliaIdentifier.
// Import path updated to '../fields' (new location per D-16).
// Topology tests NOT included — they move to per-rule tests in Plans 04-08.

import { describe, it, expect } from "vitest";
import {
  validateInt,
  validateReal,
  validatePositiveReal,
  validateJuliaIdentifier,
} from "../fields";

// ---------------------------------------------------------------------------
// validateInt
// ---------------------------------------------------------------------------

describe("validateInt", () => {
  it("returns valid=false for empty string", () => {
    const result = validateInt("");
    expect(result.valid).toBe(false);
  });

  it("returns valid=false for whitespace-only string", () => {
    const result = validateInt("   ");
    expect(result.valid).toBe(false);
  });

  it("returns valid=false for non-integer float", () => {
    const result = validateInt("1.5");
    expect(result.valid).toBe(false);
    if (!result.valid) {
      expect(result.message).toContain("positive integer");
    }
  });

  it("returns valid=false for zero", () => {
    const result = validateInt("0");
    expect(result.valid).toBe(false);
  });

  it("returns valid=false for negative integer", () => {
    const result = validateInt("-3");
    expect(result.valid).toBe(false);
  });

  it("returns valid=true for positive integer", () => {
    const result = validateInt("5");
    expect(result.valid).toBe(true);
    if (result.valid) {
      expect(result.value).toBe(5);
    }
  });

  it("returns valid=true for large positive integer", () => {
    const result = validateInt("100");
    expect(result.valid).toBe(true);
    if (result.valid) {
      expect(result.value).toBe(100);
    }
  });
});

// ---------------------------------------------------------------------------
// validateReal
// ---------------------------------------------------------------------------

describe("validateReal", () => {
  it("returns valid=false for empty string", () => {
    const result = validateReal("");
    expect(result.valid).toBe(false);
  });

  it("returns valid=false for non-numeric string", () => {
    const result = validateReal("abc");
    expect(result.valid).toBe(false);
    if (!result.valid) {
      expect(result.message).toContain("finite number");
    }
  });

  it("returns valid=false for Infinity", () => {
    const result = validateReal("Infinity");
    expect(result.valid).toBe(false);
  });

  it("returns valid=true for zero", () => {
    const result = validateReal("0");
    expect(result.valid).toBe(true);
    if (result.valid) {
      expect(result.value).toBe(0);
    }
  });

  it("returns valid=true for negative real", () => {
    const result = validateReal("-3.14");
    expect(result.valid).toBe(true);
    if (result.valid) {
      expect(result.value).toBeCloseTo(-3.14);
    }
  });

  it("returns valid=true for positive real", () => {
    const result = validateReal("2.718");
    expect(result.valid).toBe(true);
    if (result.valid) {
      expect(result.value).toBeCloseTo(2.718);
    }
  });
});

// ---------------------------------------------------------------------------
// validatePositiveReal
// ---------------------------------------------------------------------------

describe("validatePositiveReal", () => {
  it("returns valid=false for empty string", () => {
    const result = validatePositiveReal("");
    expect(result.valid).toBe(false);
  });

  it("returns valid=false for zero", () => {
    const result = validatePositiveReal("0");
    expect(result.valid).toBe(false);
    if (!result.valid) {
      expect(result.message).toContain("positive");
    }
  });

  it("returns valid=false for negative number", () => {
    const result = validatePositiveReal("-1.5");
    expect(result.valid).toBe(false);
  });

  it("returns valid=true for positive real", () => {
    const result = validatePositiveReal("3.14");
    expect(result.valid).toBe(true);
    if (result.valid) {
      expect(result.value).toBeCloseTo(3.14);
    }
  });

  it("returns valid=true for small positive real", () => {
    const result = validatePositiveReal("0.001");
    expect(result.valid).toBe(true);
    if (result.valid) {
      expect(result.value).toBeCloseTo(0.001);
    }
  });
});

// ---------------------------------------------------------------------------
// validateJuliaIdentifier
// ---------------------------------------------------------------------------

describe("validateJuliaIdentifier", () => {
  it("returns valid=false for empty string", () => {
    const result = validateJuliaIdentifier("");
    expect(result.valid).toBe(false);
  });

  it("returns valid=false for string starting with digit", () => {
    const result = validateJuliaIdentifier("1abc");
    expect(result.valid).toBe(false);
    if (!result.valid) {
      expect(result.message).toContain("Julia identifier");
    }
  });

  it("returns valid=false for string with spaces", () => {
    const result = validateJuliaIdentifier("my var");
    expect(result.valid).toBe(false);
  });

  it("returns valid=false for string with hyphens", () => {
    const result = validateJuliaIdentifier("my-var");
    expect(result.valid).toBe(false);
  });

  it("returns valid=true for simple lowercase identifier", () => {
    const result = validateJuliaIdentifier("channel1");
    expect(result.valid).toBe(true);
    if (result.valid) {
      expect(result.value).toBe("channel1");
    }
  });

  it("returns valid=true for identifier starting with underscore", () => {
    const result = validateJuliaIdentifier("_helper");
    expect(result.valid).toBe(true);
    if (result.valid) {
      expect(result.value).toBe("_helper");
    }
  });

  it("returns valid=true for mixed-case identifier with underscores", () => {
    const result = validateJuliaIdentifier("myChannel_1");
    expect(result.valid).toBe(true);
    if (result.valid) {
      expect(result.value).toBe("myChannel_1");
    }
  });

  it("returns valid=true for single letter identifier", () => {
    const result = validateJuliaIdentifier("x");
    expect(result.valid).toBe(true);
  });
});
