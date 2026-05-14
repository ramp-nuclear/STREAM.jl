// @vitest-environment happy-dom
// sourceValueEntry.test.ts — Plan 63.1-14 (GAP-RC-4) RED tests for the
// SourceValueEntry discriminated union, isSourceValueEntry guard, and
// defaultSourceValueEntry factory.

import { describe, it, expect } from "vitest";
import { isSourceValueEntry, defaultSourceValueEntry } from "./sourceValueEntry";

describe("isSourceValueEntry", () => {
  it("returns true for value-mode entry", () => {
    expect(isSourceValueEntry({ mode: "value", value: 300 })).toBe(true);
  });

  it("returns true for profile-cosine entry", () => {
    expect(
      isSourceValueEntry({
        mode: "profile",
        preset: "cosine",
        amplitude: 1,
        peakingFactor: 1,
      })
    ).toBe(true);
  });

  it("returns true for profile-file entry", () => {
    expect(
      isSourceValueEntry({ mode: "profile", preset: "file", path: "p.csv" })
    ).toBe(true);
  });

  it("returns true for function entry with fn(t)", () => {
    expect(
      isSourceValueEntry({
        mode: "function",
        signature: "fn(t)",
        functionName: "f",
      })
    ).toBe(true);
  });

  it("returns true for function entry with fn(t, i)", () => {
    expect(
      isSourceValueEntry({
        mode: "function",
        signature: "fn(t, i)",
        functionName: "f",
      })
    ).toBe(true);
  });

  it("returns false for bare number 300", () => {
    expect(isSourceValueEntry(300)).toBe(false);
  });

  it("returns false for undefined", () => {
    expect(isSourceValueEntry(undefined)).toBe(false);
  });

  it("returns false for null", () => {
    expect(isSourceValueEntry(null)).toBe(false);
  });

  it("returns false for mark-mode entry (dropped BCModeEntry arm)", () => {
    expect(isSourceValueEntry({ mode: "mark" })).toBe(false);
  });

  it("returns false for source-mode entry (dropped BCModeEntry arm)", () => {
    expect(isSourceValueEntry({ mode: "source", sourceNodeId: "x" })).toBe(false);
  });
});

describe("defaultSourceValueEntry", () => {
  it("returns { mode: 'value', value: 300 } for 300", () => {
    expect(defaultSourceValueEntry(300)).toEqual({ mode: "value", value: 300 });
  });

  it("returns { mode: 'value', value: 0 } for 0", () => {
    expect(defaultSourceValueEntry(0)).toEqual({ mode: "value", value: 0 });
  });
});
