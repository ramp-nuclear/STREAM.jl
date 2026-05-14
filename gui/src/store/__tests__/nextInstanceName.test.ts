import { describe, it, expect } from "vitest";
import { nextInstanceName } from "../useStore";

describe("nextInstanceName — lowest-free positive-integer suffix", () => {
  it("returns <componentId>_1 when no existing names", () => {
    expect(nextInstanceName("pump", new Set())).toBe("pump_1");
  });

  it("lowercases componentId (preserves legacy convention)", () => {
    expect(nextInstanceName("Pump", new Set())).toBe("pump_1");
  });

  it("returns next sequential slot when names are contiguous from 1", () => {
    expect(nextInstanceName("pump", new Set(["pump_1", "pump_2"]))).toBe(
      "pump_3",
    );
  });

  it("returns lowest-free slot, not next-after-highest (gap case)", () => {
    // pump_2 is free even though pump_3 exists
    expect(nextInstanceName("pump", new Set(["pump_1", "pump_3"]))).toBe(
      "pump_2",
    );
  });

  it("returns pump_1 when only pump_2 exists (lowest free is 1)", () => {
    expect(nextInstanceName("pump", new Set(["pump_2"]))).toBe("pump_1");
  });

  it("other component types do not pollute the search space", () => {
    expect(
      nextInstanceName(
        "pump",
        new Set(["channel_1", "channel_2", "pump_1"]),
      ),
    ).toBe("pump_2");
  });

  it("non-digit-suffix existing names do not occupy an integer slot", () => {
    // pump_a and pump_ do not count as pump_1
    expect(nextInstanceName("pump", new Set(["pump_a", "pump_"]))).toBe(
      "pump_1",
    );
  });

  it("prefix isolation: top_pump_1 does not count as pump_1", () => {
    // only names matching ^pump_(\d+)$ count
    expect(nextInstanceName("pump", new Set(["top_pump_1"]))).toBe("pump_1");
  });

  it("produces names that match valid Julia identifier shape /^[a-z][a-z0-9_]*$/", () => {
    // Spot-check several component IDs that appear in the registry
    const componentIds = [
      "pump",
      "channel",
      "channelandcontacts",
      "channelheatflux",
      "heatdiffusion",
      "resistor",
      "inertia",
      "gravity",
      "heatexchanger",
      "constanttemperature",
      "walltemperature",
      "heatfluxsource",
    ];
    const juliaSafe = /^[a-z][a-z0-9_]*$/;
    for (const id of componentIds) {
      const name = nextInstanceName(id, new Set());
      expect(name).toMatch(juliaSafe);
    }
  });

  it("throws when all slots are exhausted (defensive — not reachable in practice)", () => {
    const full = new Set<string>();
    for (let i = 1; i < 10_000; i++) full.add(`pump_${i}`);
    expect(() => nextInstanceName("pump", full)).toThrow(
      /nextInstanceName: exhausted candidates for pump/,
    );
  });
});
