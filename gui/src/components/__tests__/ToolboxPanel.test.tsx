// @vitest-environment happy-dom
//
// Phase 63.1 D-06 — the Sources category block has been removed from the
// default toolbox. Registry entries for WallTemperature / HeatFluxSource
// remain in components.json so `promoteToSharedSource` (Plan 08) can spawn
// them programmatically, but the user no longer drags them from the toolbox.
//
// This file's previous Phase 62 / 63 contract (the SOURCES header and the
// WallTemperature / HeatFluxSource drag rows) is superseded by D-06; the
// tests below now lock in the *absence* of those affordances.
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
    anchors: {},
    selectedNodeId: null,
    selectedResourceId: null,
    selectedResourceKind: null,
    selectionKind: "none",
    isDirty: false,
    _undoPast: [],
    _undoFuture: [],
    activeLeftTab: "Components",
    activeLayer: "Both",
    resources: {
      geometries: {},
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
  });
});

afterEach(() => {
  cleanup();
});

describe("ToolboxPanel — Sources category hidden by default (D-06)", () => {
  it("D-06: does NOT render the SOURCES group header in the Components tab body", () => {
    render(<ToolboxPanel />);
    expect(screen.queryByText(/^Sources$/i)).toBeNull();
  });

  it("D-06: does NOT render a WallTemperature drag row in the toolbox", () => {
    render(<ToolboxPanel />);
    expect(screen.queryByText(/Wall Temperature/i)).toBeNull();
  });

  it("D-06: does NOT render a HeatFluxSource drag row in the toolbox", () => {
    render(<ToolboxPanel />);
    expect(screen.queryByText(/Heat Flux Source/i)).toBeNull();
  });

  it("D-06: continues to render the HYDRAULIC and THERMAL category headers", () => {
    render(<ToolboxPanel />);
    expect(screen.getByText(/^Hydraulic$/i)).toBeTruthy();
    expect(screen.getByText(/^Thermal$/i)).toBeTruthy();
  });
});
