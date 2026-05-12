// @vitest-environment happy-dom
//
// Tests the Phase 62 plan 62-05 Task 2 contract: SOURCES category header
// added to the Components-tab toolbox (D-30). Header-only — no rows, no
// drag handlers, no tooltip (UI-SPEC §"Sources toolbox category header").
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";
import ToolboxPanel from "../ToolboxPanel";
import useStore, {
  SENTINEL_UNSET_POWER_SHAPE,
  SENTINEL_LIGHT_WATER_FLUID,
} from "../../store/useStore";

beforeEach(() => {
  // Cold-start store state per 62-02 (activeLayer affects which Hydraulic /
  // Thermal items appear; default layer keeps both visible).
  useStore.setState({
    nodes: [],
    edges: [],
    bcs: [],
    selectedNodeId: null,
    selectedResourceId: null,
    selectedResourceKind: null,
    selectionKind: "none",
    isDirty: false,
    _undoPast: [],
    _undoFuture: [],
    activeLeftTab: "Components",
    activeLayer: "all",
    resources: {
      geometries: {},
      powerShapes: {
        [SENTINEL_UNSET_POWER_SHAPE]: {
          uuid: SENTINEL_UNSET_POWER_SHAPE,
          name: "(leave unset — fill in code)",
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
  });
});

afterEach(() => {
  cleanup();
});

describe("ToolboxPanel — SOURCES header (D-30)", () => {
  it("D-30: renders a SOURCES group header in the Components tab body", () => {
    render(<ToolboxPanel />);
    // The visual uppercase comes from Tailwind `uppercase` class, so the
    // literal in JSX may be Mixed-case ("Sources"). Match case-insensitively.
    const header = screen.getByText(/^Sources$/i);
    expect(header).toBeTruthy();
  });

  it("D-30: SOURCES header uses the same Tailwind treatment as Hydraulic/Thermal", () => {
    render(<ToolboxPanel />);
    const sourcesHeader = screen.getByText(/^Sources$/i);
    // Reference treatment per ToolboxPanel.tsx HYDRAULIC / THERMAL headers.
    const expectedClassFragments = [
      "text-xs",
      "font-semibold",
      "uppercase",
      "tracking-wide",
      "text-muted-foreground",
    ];
    for (const frag of expectedClassFragments) {
      expect(sourcesHeader.className).toContain(frag);
    }
  });

  it("D-30: SOURCES header renders AFTER the THERMAL header in DOM order", () => {
    render(<ToolboxPanel />);
    const thermal = screen.getByText(/^Thermal$/i);
    const sources = screen.getByText(/^Sources$/i);
    const pos = thermal.compareDocumentPosition(sources);
    // Node.DOCUMENT_POSITION_FOLLOWING = 4
    // eslint-disable-next-line no-bitwise
    expect(pos & 4).toBeTruthy();
  });

  it("D-30: no WallTemperature or HeatFluxSource rows are rendered in Phase 62", () => {
    render(<ToolboxPanel />);
    // Phase 63 lands the drag entries; Phase 62 ships the header only.
    expect(screen.queryByText(/WallTemperature/i)).toBeNull();
    expect(screen.queryByText(/HeatFluxSource/i)).toBeNull();
  });

  it("D-30: SOURCES header is not interactive (no aria-describedby / tooltip)", () => {
    render(<ToolboxPanel />);
    const sources = screen.getByText(/^Sources$/i);
    // "No inert affordances" — header is plain text, not a tooltip trigger.
    expect(sources.getAttribute("aria-describedby")).toBeNull();
    expect(sources.getAttribute("role")).toBeNull();
    // It is a <div>, not a <button> / <a> / <[role=tab|button]>.
    expect(sources.tagName.toLowerCase()).toBe("div");
  });
});
