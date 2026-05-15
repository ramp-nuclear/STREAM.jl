// @vitest-environment happy-dom
//
// Phase 63.1 D-06 removed the Sources category block. Phase 65 UAT 2026-05-15
// reverted that — Sources are re-surfaced as direct drag affordances because
// the workflow needed them. This file's contract has been flipped accordingly:
// the SOURCES header and the WallTemperature / HeatFluxSource drag rows are
// now expected to RENDER.
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";
import ToolboxPanel from "../ToolboxPanel";
import useStore, {
  SENTINEL_UNSET_POWER_SHAPE,
  SENTINEL_LIGHT_WATER_FLUID,
} from "../../store/useStore";

beforeEach(() => {
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

describe("ToolboxPanel — Sources category re-surfaced (Phase 65 UAT revert of 63.1 D-06)", () => {
  it("renders the SOURCES group header in the Components tab body", () => {
    render(<ToolboxPanel />);
    expect(screen.getByText(/^Sources$/i)).toBeTruthy();
  });

  it("renders a WallTemperature drag row in the toolbox", () => {
    render(<ToolboxPanel />);
    expect(screen.getByText(/Wall Temperature/i)).toBeTruthy();
  });

  it("renders a HeatFluxSource drag row in the toolbox", () => {
    render(<ToolboxPanel />);
    expect(screen.getByText(/Heat Flux Source/i)).toBeTruthy();
  });

  it("continues to render the HYDRAULIC and THERMAL category headers", () => {
    render(<ToolboxPanel />);
    expect(screen.getByText(/^Hydraulic$/i)).toBeTruthy();
    expect(screen.getByText(/^Thermal$/i)).toBeTruthy();
  });
});
