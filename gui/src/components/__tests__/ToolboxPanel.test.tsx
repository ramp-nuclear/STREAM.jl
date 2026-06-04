// @vitest-environment happy-dom
//
// Phase 63.1 D-06 removed the Sources category block. Phase 65 UAT 2026-05-15
// reverted that — Sources are re-surfaced as direct drag affordances because
// the workflow needed them. This file's contract has been flipped accordingly:
// the SOURCES header and the WallTemperature / HeatFluxSource drag rows are
// now expected to RENDER.
//
// Phase 68 Plan 03 — D-11 contract: ToolboxPanel does NOT filter components
// by `activeLayers` state. Whatever the per-layer toggles are, every
// registry-listed draggable component appears in its category section.
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
    activeLayers: {
      Hydraulic: true,
      Thermal: true,
      Sources: true,
      ReactorPhysics: true,
    },
    hideOffLayer: false,
    resources: {
      geometries: {},
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

describe("ToolboxPanel — layer filter (Phase 68 D-11): toolbox does NOT filter by layer", () => {
  it("renders Hydraulic components when Hydraulic layer is OFF", () => {
    useStore.setState({
      activeLayers: {
        Hydraulic: false,
        Thermal: true,
        Sources: true,
        ReactorPhysics: true,
      },
      hideOffLayer: false,
    });
    render(<ToolboxPanel />);
    // HYDRAULIC header + at least one Hydraulic component still rendered
    expect(screen.getByText(/^Hydraulic$/i)).toBeTruthy();
    // Channel (hydraulic) — the canonical hydraulic primitive
    expect(screen.getByText(/^Channel$/i)).toBeTruthy();
  });

  it("renders Thermal components when Thermal layer is OFF", () => {
    useStore.setState({
      activeLayers: {
        Hydraulic: true,
        Thermal: false,
        Sources: true,
        ReactorPhysics: true,
      },
      hideOffLayer: false,
    });
    render(<ToolboxPanel />);
    expect(screen.getByText(/^Thermal$/i)).toBeTruthy();
    // ConstantTemperature / HeatDiffusion are the thermal primitives — at
    // least one must render. (Exact label depends on registry label field.)
    expect(screen.getByText(/Constant Temperature/i)).toBeTruthy();
  });

  it("renders every category when ALL layers are OFF", () => {
    useStore.setState({
      activeLayers: {
        Hydraulic: false,
        Thermal: false,
        Sources: false,
        ReactorPhysics: false,
      },
      hideOffLayer: false,
    });
    render(<ToolboxPanel />);
    expect(screen.getByText(/^Hydraulic$/i)).toBeTruthy();
    expect(screen.getByText(/^Thermal$/i)).toBeTruthy();
    expect(screen.getByText(/^Sources$/i)).toBeTruthy();
    expect(screen.getByText(/^Channel$/i)).toBeTruthy();
    expect(screen.getByText(/Constant Temperature/i)).toBeTruthy();
    expect(screen.getByText(/Wall Temperature/i)).toBeTruthy();
  });
});
