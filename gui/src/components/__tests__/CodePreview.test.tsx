// @vitest-environment happy-dom
//
// CodePreview.test.tsx — Phase 66 Plan 01 (RED)
//
// Locks the CodePreview rendering + hover/click contract before Plan 04's
// rewrite of the 34-line CodePreview.tsx. Tests render the current 34-line
// `<pre><code>{string}</code></pre>` shape, find no [data-sub-block] elements,
// and fail at runtime. Plan 04 turns these green.
//
// References:
//   .planning/phases/66-code-preview-rework/66-CONTEXT.md D-04, D-09, D-10
//   .planning/phases/66-code-preview-rework/66-RESEARCH.md Pattern 10
//
// RED state: CodePreview still renders a single <pre><code>; querying for
// `[data-sub-block]` returns 0 elements; the store does NOT yet have
// hoveredSourceIds / pinnedSourceIds slices, so writes via fireEvent are no-ops.

import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { render, fireEvent, cleanup } from "@testing-library/react";
import CodePreview from "../CodePreview";
import useStore, {
  SENTINEL_UNSET_POWER_SHAPE,
  SENTINEL_LIGHT_WATER_FLUID,
} from "../../store/useStore";

// Seed the store with a deterministic node graph that, after Plan 04, will
// render multiple sub-blocks (Imports, Components ×2, Composition ×1, Main).
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
          name: "(leave unset — set in code)",
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

describe("CodePreview — section render + hover + click (Phase 66 Plan 04 contract)", () => {
  it("renders multiple [data-sub-block] elements (one per emitted sub-block)", () => {
    const { container } = render(<CodePreview />);
    const subBlocks = container.querySelectorAll("[data-sub-block]");
    // The seeded graph produces (at minimum) Imports + pump_1 component +
    // ch_1 component + pump→ch connect + Main → ≥ 5 sub-blocks.
    expect(subBlocks.length).toBeGreaterThanOrEqual(5);
  });

  it("renders a recognizable header for each populated section (Imports, Components, Composition, Main)", () => {
    const { container } = render(<CodePreview />);
    const text = container.textContent ?? "";
    // Header texts emitted by serializeSections (D-12) appear in the DOM
    // because CodePreview renders the same source content (no syntax stripping).
    expect(text).toContain("Imports");
    expect(text).toContain("Components");
    expect(text).toContain("Composition");
    expect(text).toContain("Main");
  });

  it("hovering a sub-block writes its sourceIds into useStore.hoveredSourceIds (mouseEnter)", () => {
    const { container } = render(<CodePreview />);
    const subBlocks = container.querySelectorAll("[data-sub-block]");
    expect(subBlocks.length).toBeGreaterThan(0);

    // Find a sub-block that has a non-empty sourceIds list — the pump_1
    // component sub-block is the canonical example. The DOM should encode
    // the sourceIds via a data-source-ids attribute (Plan 04 spec).
    const componentSub = Array.from(subBlocks).find((el) =>
      (el.getAttribute("data-source-ids") ?? "").includes("pump-uuid"),
    );
    expect(componentSub).toBeDefined();

    fireEvent.mouseEnter(componentSub!);
    const hovered = useStore.getState().hoveredSourceIds;
    expect(hovered.has("pump-uuid")).toBe(true);
  });

  it("mouseLeave clears hoveredSourceIds for the sub-block", () => {
    const { container } = render(<CodePreview />);
    const subBlocks = container.querySelectorAll("[data-sub-block]");
    const componentSub = Array.from(subBlocks).find((el) =>
      (el.getAttribute("data-source-ids") ?? "").includes("pump-uuid"),
    );
    expect(componentSub).toBeDefined();

    fireEvent.mouseEnter(componentSub!);
    expect(useStore.getState().hoveredSourceIds.has("pump-uuid")).toBe(true);

    fireEvent.mouseLeave(componentSub!);
    expect(useStore.getState().hoveredSourceIds.has("pump-uuid")).toBe(false);
  });

  it("clicking a sub-block adds its sourceIds to pinnedSourceIds (D-09)", () => {
    const { container } = render(<CodePreview />);
    const subBlocks = container.querySelectorAll("[data-sub-block]");
    const componentSub = Array.from(subBlocks).find((el) =>
      (el.getAttribute("data-source-ids") ?? "").includes("pump-uuid"),
    );
    expect(componentSub).toBeDefined();

    fireEvent.click(componentSub!);
    expect(useStore.getState().pinnedSourceIds.has("pump-uuid")).toBe(true);
  });

  it("clicking two different sub-blocks pins both (D-10 multi-pin is additive)", () => {
    const { container } = render(<CodePreview />);
    const subBlocks = container.querySelectorAll("[data-sub-block]");
    const pumpSub = Array.from(subBlocks).find((el) =>
      (el.getAttribute("data-source-ids") ?? "").includes("pump-uuid"),
    );
    const chSub = Array.from(subBlocks).find((el) =>
      (el.getAttribute("data-source-ids") ?? "").includes("ch-uuid"),
    );
    expect(pumpSub).toBeDefined();
    expect(chSub).toBeDefined();

    fireEvent.click(pumpSub!);
    fireEvent.click(chSub!);

    const pinned = useStore.getState().pinnedSourceIds;
    expect(pinned.has("pump-uuid")).toBe(true);
    expect(pinned.has("ch-uuid")).toBe(true);
  });

  it("clicking the same sub-block twice toggles its sourceIds off (D-09)", () => {
    const { container } = render(<CodePreview />);
    const subBlocks = container.querySelectorAll("[data-sub-block]");
    const pumpSub = Array.from(subBlocks).find((el) =>
      (el.getAttribute("data-source-ids") ?? "").includes("pump-uuid"),
    );
    expect(pumpSub).toBeDefined();

    fireEvent.click(pumpSub!);
    expect(useStore.getState().pinnedSourceIds.has("pump-uuid")).toBe(true);

    fireEvent.click(pumpSub!);
    expect(useStore.getState().pinnedSourceIds.has("pump-uuid")).toBe(false);
  });

  // Esc clears pins. Per Plan 01 acceptance criteria this MAY live in an
  // AppShell test instead — if Plan 04 wires the Esc handler at App level,
  // this becomes a todo. For now, we encode the expectation at the
  // CodePreview level (the cheaper test to write); Plan 04 can move it.
  it.todo(
    "Esc clears pinnedSourceIds (Plan 04 may wire this at App.tsx level — if so, move to AppShell test set)",
  );
});
