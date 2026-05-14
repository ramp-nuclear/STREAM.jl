// projectIO.snapToGrid.test.ts — Phase 65 Plan 06 Task 1 (TDD)
//
// Covers: snap_to_grid field in .scp layout block (D-10)
//   1. serializeProject({snapToGrid: true, ...}) produces layout.snap_to_grid === true
//   2. serializeProject({snapToGrid: false, ...}) produces layout.snap_to_grid === false (explicit, not absent)
//   3. deserializeProject of JSON with layout.snap_to_grid: true returns snap_to_grid === true
//   4. deserializeProject of JSON WITHOUT layout.snap_to_grid (legacy v2.0 file) defaults to false
//   5. Round-trip: serialize → deserialize → snap_to_grid preserved

import { describe, it, expect } from "vitest";
import type { Node, Edge } from "@xyflow/react";
import {
  serializeProject,
  deserializeProject,
  PROJECT_FORMAT_VERSION,
} from "../projectIO";
import { SENTINEL_UNSET_POWER_SHAPE, SENTINEL_LIGHT_WATER_FLUID } from "../../store/useStore";
import type {
  GeometryResource,
  PowerShapeResource,
  FluidResource,
  ModelOptionsSliceState,
  ActiveLeftTab,
} from "../../store/useStore";
import type { AnchorEntry } from "../anchors";
import type { LayerView } from "../layers";

// ---------------------------------------------------------------------------
// Minimal fixtures
// ---------------------------------------------------------------------------

function makeMinimalSerializeArgs(snapToGrid: boolean) {
  const nodes: Node[] = [];
  const edges: Edge[] = [];
  const anchors: Record<string, AnchorEntry> = {};
  const resources = {
    geometries: {} as Record<string, GeometryResource>,
    powerShapes: {
      [SENTINEL_UNSET_POWER_SHAPE]: {
        uuid: SENTINEL_UNSET_POWER_SHAPE,
        name: "(leave unset — set in code)",
        kind: "unset" as const,
        params: {},
      },
    } as Record<string, PowerShapeResource>,
    fluids: {
      [SENTINEL_LIGHT_WATER_FLUID]: {
        uuid: SENTINEL_LIGHT_WATER_FLUID,
        name: "light_water",
      },
    } as Record<string, FluidResource>,
  };
  const modelOptions: ModelOptionsSliceState = {
    name: "",
    description: "",
    default_fluid: "water",
    g_default: 9.80665,
    solver: { abstol: 1e-8, reltol: 1e-6, dtmax: null },
  };
  const activeLeftTab: ActiveLeftTab = "Components";
  const activeLayer: LayerView = "Both";

  return {
    nodes,
    edges,
    anchors,
    resources,
    modelOptions,
    activeLeftTab,
    activeLayer,
    snapToGrid,
  };
}

// ---------------------------------------------------------------------------
// Test cases
// ---------------------------------------------------------------------------

describe("serializeProject — snap_to_grid field (D-10)", () => {
  it("case 1: snapToGrid=true produces layout.snap_to_grid === true", () => {
    const json = serializeProject(makeMinimalSerializeArgs(true));
    const parsed = JSON.parse(json) as { layout: { snap_to_grid: unknown } };
    expect(parsed.layout.snap_to_grid).toBe(true);
  });

  it("case 2: snapToGrid=false produces layout.snap_to_grid === false (explicit, not absent)", () => {
    const json = serializeProject(makeMinimalSerializeArgs(false));
    const parsed = JSON.parse(json) as { layout: { snap_to_grid: unknown } };
    expect(parsed.layout).toHaveProperty("snap_to_grid");
    expect(parsed.layout.snap_to_grid).toBe(false);
  });
});

describe("deserializeProject — snap_to_grid field (D-10, RESEARCH Pitfall 3)", () => {
  it("case 3: v2.0 JSON with layout.snap_to_grid:true deserializes to snap_to_grid === true", () => {
    const raw = JSON.stringify({
      format_version: PROJECT_FORMAT_VERSION,
      layout: { active_left_tab: "Components", active_layer: "Both", snap_to_grid: true },
    });
    const project = deserializeProject(raw);
    expect(project.layout.snap_to_grid).toBe(true);
  });

  it("case 4: v2.0 JSON without layout.snap_to_grid defaults to false (legacy tolerance)", () => {
    const raw = JSON.stringify({
      format_version: PROJECT_FORMAT_VERSION,
      layout: { active_left_tab: "Components", active_layer: "Both" },
    });
    const project = deserializeProject(raw);
    expect(project.layout.snap_to_grid).toBe(false);
  });
});

describe("snap_to_grid round-trip (D-10)", () => {
  it("case 5: serialize(snapToGrid=true) → deserialize → snap_to_grid === true", () => {
    const json = serializeProject(makeMinimalSerializeArgs(true));
    const project = deserializeProject(json);
    expect(project.layout.snap_to_grid).toBe(true);
  });
});
