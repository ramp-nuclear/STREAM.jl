import { describe, it, expect } from "vitest";
import {
  validateInt,
  validateReal,
  validatePositiveReal,
  validateJuliaIdentifier,
} from "../validation/fields";

describe("validateInt", () => {
  it("accepts positive integers", () => {
    expect(validateInt("5")).toEqual({ valid: true, value: 5 });
    expect(validateInt("100")).toEqual({ valid: true, value: 100 });
  });
  it("rejects empty string", () => {
    expect(validateInt("").valid).toBe(false);
  });
  it("rejects zero", () => {
    expect(validateInt("0").valid).toBe(false);
  });
  it("rejects negative", () => {
    expect(validateInt("-3").valid).toBe(false);
  });
  it("rejects float", () => {
    expect(validateInt("3.5").valid).toBe(false);
  });
  it("rejects non-numeric", () => {
    expect(validateInt("abc").valid).toBe(false);
  });
  it("rejects NaN", () => {
    expect(validateInt("NaN").valid).toBe(false);
  });
});

describe("validateReal", () => {
  it("accepts positive numbers", () => {
    expect(validateReal("3.14")).toEqual({ valid: true, value: 3.14 });
  });
  it("accepts negative numbers", () => {
    expect(validateReal("-2.5")).toEqual({ valid: true, value: -2.5 });
  });
  it("accepts zero", () => {
    expect(validateReal("0")).toEqual({ valid: true, value: 0 });
  });
  it("accepts scientific notation", () => {
    expect(validateReal("1e6")).toEqual({ valid: true, value: 1e6 });
  });
  it("rejects empty", () => {
    expect(validateReal("").valid).toBe(false);
  });
  it("rejects NaN", () => {
    expect(validateReal("NaN").valid).toBe(false);
  });
  it("rejects Infinity", () => {
    expect(validateReal("Infinity").valid).toBe(false);
  });
  it("rejects non-numeric", () => {
    expect(validateReal("abc").valid).toBe(false);
  });
});

describe("validatePositiveReal", () => {
  it("accepts positive numbers", () => {
    expect(validatePositiveReal("0.01")).toEqual({ valid: true, value: 0.01 });
  });
  it("rejects zero", () => {
    expect(validatePositiveReal("0").valid).toBe(false);
  });
  it("rejects negative", () => {
    expect(validatePositiveReal("-1").valid).toBe(false);
  });
});

describe("validateJuliaIdentifier", () => {
  it("accepts valid identifiers", () => {
    expect(validateJuliaIdentifier("pump_1")).toEqual({ valid: true, value: "pump_1" });
    expect(validateJuliaIdentifier("_foo")).toEqual({ valid: true, value: "_foo" });
    expect(validateJuliaIdentifier("Channel")).toEqual({ valid: true, value: "Channel" });
  });
  it("rejects empty", () => {
    expect(validateJuliaIdentifier("").valid).toBe(false);
  });
  it("rejects starting with digit", () => {
    expect(validateJuliaIdentifier("1pump").valid).toBe(false);
  });
  it("rejects spaces", () => {
    expect(validateJuliaIdentifier("my pump").valid).toBe(false);
  });
  it("rejects special characters", () => {
    expect(validateJuliaIdentifier("pump-1").valid).toBe(false);
  });
});
