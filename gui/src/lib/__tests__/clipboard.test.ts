import { describe, it, expect } from "vitest";
import {
  smartParseAndIncrement,
  isClipboardPayload,
  CLIPBOARD_FORMAT_TAG,
  CLIPBOARD_VERSION,
} from "../clipboard";

describe("smartParseAndIncrement — smart-parse-and-increment naming (§3.5)", () => {
  // --- No collision: return original unchanged ---
  it("returns original name when no collision (empty set, digits suffix)", () => {
    expect(smartParseAndIncrement("pump_1", new Set())).toBe("pump_1");
  });

  it("returns original name when no collision (empty set, no digits suffix)", () => {
    expect(smartParseAndIncrement("pump", new Set())).toBe("pump");
  });

  // --- Name ends in _<digits>: base is stripped prefix ---
  it("pump_1 + {pump_1} → pump_2", () => {
    expect(smartParseAndIncrement("pump_1", new Set(["pump_1"]))).toBe("pump_2");
  });

  it("pump_1 + {pump_1, pump_2} → pump_3", () => {
    expect(
      smartParseAndIncrement("pump_1", new Set(["pump_1", "pump_2"])),
    ).toBe("pump_3");
  });

  it("pump_1 + {pump_1, pump_3} → pump_2 (lowest-free with base pump)", () => {
    expect(
      smartParseAndIncrement("pump_1", new Set(["pump_1", "pump_3"])),
    ).toBe("pump_2");
  });

  it("top_pump_1 + {top_pump_1} → top_pump_2", () => {
    expect(
      smartParseAndIncrement("top_pump_1", new Set(["top_pump_1"])),
    ).toBe("top_pump_2");
  });

  it("top_pump_1 + {top_pump_1, top_pump_2} → top_pump_3", () => {
    expect(
      smartParseAndIncrement(
        "top_pump_1",
        new Set(["top_pump_1", "top_pump_2"]),
      ),
    ).toBe("top_pump_3");
  });

  // --- Name does NOT end in _<digits>: base is the whole name, scan from 2 ---
  it("pump + {pump} → pump_2", () => {
    expect(smartParseAndIncrement("pump", new Set(["pump"]))).toBe("pump_2");
  });

  it("heated_channel + {heated_channel} → heated_channel_2", () => {
    expect(
      smartParseAndIncrement("heated_channel", new Set(["heated_channel"])),
    ).toBe("heated_channel_2");
  });

  // --- Acceptable noise: pump_v2 ends in digits, so treated as base=pump_v, digit=2 ---
  it("pump_v2 + {pump_v2} → pump_v3 (acceptable noise per §3.5)", () => {
    expect(smartParseAndIncrement("pump_v2", new Set(["pump_v2"]))).toBe(
      "pump_v3",
    );
  });

  // --- Lowest-free semantics: always scan from 2 regardless of original digit ---
  it("pump_5 + {pump_5} → pump_2 (lowest free, not pump_6)", () => {
    expect(smartParseAndIncrement("pump_5", new Set(["pump_5"]))).toBe("pump_2");
  });
});

describe("isClipboardPayload — type guard", () => {
  it("accepts a valid payload", () => {
    expect(
      isClipboardPayload({
        __format: CLIPBOARD_FORMAT_TAG,
        version: CLIPBOARD_VERSION,
        nodes: [],
        edges: [],
      }),
    ).toBe(true);
  });

  it("rejects empty object", () => {
    expect(isClipboardPayload({})).toBe(false);
  });

  it("rejects a plain string", () => {
    expect(isClipboardPayload("not json")).toBe(false);
  });

  it("rejects wrong __format tag", () => {
    expect(
      isClipboardPayload({
        __format: "wrong",
        version: CLIPBOARD_VERSION,
        nodes: [],
        edges: [],
      }),
    ).toBe(false);
  });

  it("rejects null", () => {
    expect(isClipboardPayload(null)).toBe(false);
  });

  it("rejects wrong version", () => {
    expect(
      isClipboardPayload({
        __format: CLIPBOARD_FORMAT_TAG,
        version: 2,
        nodes: [],
        edges: [],
      }),
    ).toBe(false);
  });

  it("rejects when nodes is not an array", () => {
    expect(
      isClipboardPayload({
        __format: CLIPBOARD_FORMAT_TAG,
        version: CLIPBOARD_VERSION,
        nodes: "not-an-array",
        edges: [],
      }),
    ).toBe(false);
  });

  it("rejects when edges is not an array", () => {
    expect(
      isClipboardPayload({
        __format: CLIPBOARD_FORMAT_TAG,
        version: CLIPBOARD_VERSION,
        nodes: [],
        edges: "not-an-array",
      }),
    ).toBe(false);
  });
});
