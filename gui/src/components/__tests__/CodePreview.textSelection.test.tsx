// @vitest-environment happy-dom
//
// CodePreview.textSelection.test.tsx — Phase 66 Plan 01 (RED)
//
// Locks the D-14 regression contract: native browser text-selection MUST be
// preserved across sub-block wrappers. Specifically, no sub-block wrapper
// may carry the Tailwind `select-none` class (the only realistic regression
// vector — jsdom can't resolve Tailwind computed styles, so we class-lint).
//
// References:
//   .planning/phases/66-code-preview-rework/66-CONTEXT.md D-14
//   .planning/phases/66-code-preview-rework/66-RESEARCH.md Pattern 7
//
// RED state: CodePreview still renders a single <pre><code> with no
// [data-sub-block] elements at all. The querySelectorAll returns 0 elements,
// the length assertion fails. Plan 04 introduces the sub-block wrappers; this
// test then guards against any future select-none class slipping in.

import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { render, cleanup } from "@testing-library/react";
import CodePreview from "../CodePreview";
import useStore, {
  SENTINEL_UNSET_POWER_SHAPE,
  SENTINEL_LIGHT_WATER_FLUID,
} from "../../store/useStore";

function seedStore() {
  useStore.setState({
    nodes: [
      {
        id: "pump-uuid",
        type: "streamNode",
        position: { x: 0, y: 0 },
        data: {
          componentId: "Pump",
          instanceName: "pump_1",
          parameters: { dP_pump: 1.0 },
          constructorMode: "fixed-dP",
        },
      },
      {
        id: "ch-uuid",
        type: "streamNode",
        position: { x: 200, y: 0 },
        data: {
          componentId: "Channel",
          instanceName: "ch_1",
          parameters: { n: 5, geometry_ref: "geo-1" },
        },
      },
    ],
    edges: [
      {
        id: "e1",
        source: "pump-uuid",
        target: "ch-uuid",
        sourceHandle: "port_out",
        targetHandle: "port_in",
      },
    ],
    anchors: {},
    resources: {
      geometries: {
        "geo-1": {
          uuid: "geo-1",
          name: "geom_main",
          kind: "rectangular",
          params: { L: 0.6, W: 0.07, H: 0.0025 },
        },
      },
      powerShapes: {
        [SENTINEL_UNSET_POWER_SHAPE]: {
          uuid: SENTINEL_UNSET_POWER_SHAPE,
          name: "(leave unset; set in code)",
          kind: "unset",
          params: {},
        },
      },
      fluids: {
        [SENTINEL_LIGHT_WATER_FLUID]: {
          uuid: SENTINEL_LIGHT_WATER_FLUID,
          name: "light_water",
        },
      },
    },
    bcMode: {},
    bcSymmetric: {},
  });
}

beforeEach(() => {
  seedStore();
});

afterEach(() => {
  cleanup();
});

describe("CodePreview — D-14 native text-selection preserved across sub-blocks", () => {
  it("no [data-sub-block] wrapper has the Tailwind `select-none` class (Pattern 7 class-lint)", () => {
    const { container } = render(<CodePreview />);
    const subBlocks = container.querySelectorAll("[data-sub-block]");
    // Sanity: there should be sub-blocks to lint (Plan 04 creates them).
    expect(subBlocks.length).toBeGreaterThan(0);
    for (const el of Array.from(subBlocks)) {
      expect(el.className).not.toContain("select-none");
    }
  });
});
