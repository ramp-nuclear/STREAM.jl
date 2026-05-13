// nodeErrors.test.ts — Phase 63.1 Plan 01 (Wave-0 RED).
//
// Covers the new selector-derived validator `selectNodeErrors` (D-15 / D-23):
//   - For a source-mode BC consumer, return ['bc-n-mismatch'] iff the
//     consumer's `n` parameter differs from the bound source node's `n`.
//   - Return [] when n matches or when the consumer mode is "value"
//     (not "source").
//   - Auto-clear: the selector is a pure function of state, so flipping `n`
//     to match the source automatically produces [] on the next read
//     (no manual clear-error step — D-23 bidirectional sync).
//
// The module `@/lib/selectors/nodeErrors` does not exist yet — this stub is
// RED until Plan 04 lands.
// @ts-nocheck — selector module lands in Wave 2 / Plan 04.

import { describe, it, expect } from "vitest";
import type { Node } from "@xyflow/react";
import { selectNodeErrors } from "../nodeErrors";
import { bcModeKey } from "../../bcMode";

function chan(id: string, n: number): Node {
  return {
    id,
    type: "streamNode",
    position: { x: 0, y: 0 },
    data: {
      componentId: "Channel",
      instanceName: id,
      parameters: { n },
      constructorMode: "default",
    },
  };
}

function wt(id: string, n: number): Node {
  return {
    id,
    type: "streamNode",
    position: { x: 0, y: 0 },
    data: {
      componentId: "WallTemperature",
      instanceName: id,
      parameters: { n, T_wall: 320 },
      constructorMode: "default",
    },
  };
}

describe("selectNodeErrors (D-15)", () => {
  it("returns ['bc-n-mismatch'] when consumer's n differs from source's n", () => {
    const state = {
      nodes: [chan("ch1", 5), wt("wt1", 3)],
      edges: [],
      bcMode: {
        [bcModeKey("ch1", "T_wall_left")]: {
          mode: "source" as const,
          sourceNodeId: "wt1",
        },
      },
      bcSymmetric: {},
      anchors: {},
    };
    const errors = selectNodeErrors(state, "ch1");
    expect(errors).toContain("bc-n-mismatch");
  });

  it("returns [] when n matches between consumer and source", () => {
    const state = {
      nodes: [chan("ch1", 4), wt("wt1", 4)],
      edges: [],
      bcMode: {
        [bcModeKey("ch1", "T_wall_left")]: {
          mode: "source" as const,
          sourceNodeId: "wt1",
        },
      },
      bcSymmetric: {},
      anchors: {},
    };
    expect(selectNodeErrors(state, "ch1")).toEqual([]);
  });

  it("returns [] when consumer mode is 'value' (no source binding)", () => {
    const state = {
      nodes: [chan("ch1", 4), wt("wt1", 7)],
      edges: [],
      bcMode: {
        [bcModeKey("ch1", "T_wall_left")]: {
          mode: "value" as const,
          value: 320,
        },
      },
      bcSymmetric: {},
      anchors: {},
    };
    expect(selectNodeErrors(state, "ch1")).toEqual([]);
  });

  it("auto-clears when underlying n is corrected (D-23 bidirectional sync)", () => {
    // Same bcMode wiring, but the consumer's n now matches — selector must
    // return [] without any manual clear-error call.
    const state = {
      nodes: [chan("ch1", 3), wt("wt1", 3)],
      edges: [],
      bcMode: {
        [bcModeKey("ch1", "T_wall_left")]: {
          mode: "source" as const,
          sourceNodeId: "wt1",
        },
      },
      bcSymmetric: {},
      anchors: {},
    };
    expect(selectNodeErrors(state, "ch1")).toEqual([]);
  });
});
