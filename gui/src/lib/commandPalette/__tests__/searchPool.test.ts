import { describe, it, expect } from "vitest";
import type { Node } from "@xyflow/react";

import { buildSearchPool, type SearchItem } from "../searchPool";
import {
  SENTINEL_UNSET_POWER_SHAPE,
  SENTINEL_LIGHT_WATER_FLUID,
  type ResourcesSliceState,
  type GeometryResource,
  type PowerShapeResource,
  type FluidResource,
  type StreamNodeData,
} from "@/store/useStore";

// Phase 69 Plan 01 Task 3 — unit tests for buildSearchPool.
//
// Pure helper; no React, no zustand, no DOM. Test cases mirror the
// <behavior> block of the plan one-for-one.

function emptyResources(): ResourcesSliceState {
  return {
    geometries: {},
    powerShapes: {},
    fluids: {},
  };
}

function geom(uuid: string, name: string): GeometryResource {
  return {
    uuid,
    name,
    kind: "rectangular",
    params: { L: 1.0, W: 0.01, H: 0.001 },
  };
}

function powerShape(uuid: string, name: string): PowerShapeResource {
  return {
    uuid,
    name,
    kind: "uniform",
    params: { amplitude: 1.0 },
  };
}

function fluid(uuid: string, name: string): FluidResource {
  return { uuid, name };
}

function streamNode(id: string, componentId: string, instanceName: string): Node {
  return {
    id,
    type: "stream",
    position: { x: 0, y: 0 },
    data: {
      componentId,
      instanceName,
      parameters: {},
    } satisfies StreamNodeData as unknown as Record<string, unknown>,
  };
}

describe("buildSearchPool", () => {
  it("returns exactly one modelOptions row for empty nodes + empty resources", () => {
    const items = buildSearchPool([], emptyResources());

    expect(items).toHaveLength(1);
    expect(items[0]).toEqual({
      kind: "modelOptions",
      id: "modelOptions",
      name: "Project Options",
    });
  });

  it("emits one component row per node with valid componentId", () => {
    const node = streamNode("n1", "Pump", "top_pump");
    const items = buildSearchPool([node], emptyResources());

    // 1 component + 1 modelOptions row
    expect(items).toHaveLength(2);

    const comp = items.find((i) => i.kind === "component") as Extract<
      SearchItem,
      { kind: "component" }
    >;
    expect(comp).toBeDefined();
    expect(comp.id).toBe("n1");
    expect(comp.name).toBe("top_pump");
    expect(comp.typeLabel).toBe("Pump");
    expect(comp.node).toBe(node);
    expect(comp.comp.id).toBe("Pump");
  });

  it("skips nodes whose componentId does not resolve in the registry", () => {
    const ghost = streamNode("ghost", "NotARealComponent_xyz", "spooky");
    const items = buildSearchPool([ghost], emptyResources());

    // Just the modelOptions row — the unknown component is silently dropped.
    expect(items).toHaveLength(1);
    expect(items[0].kind).toBe("modelOptions");
  });

  it("emits one geometry row per geometry resource", () => {
    const resources = emptyResources();
    resources.geometries["g1"] = geom("g1", "rect1");
    resources.geometries["g2"] = geom("g2", "rect2");

    const items = buildSearchPool([], resources);

    // 2 geometries + 1 modelOptions row
    expect(items).toHaveLength(3);

    const geos = items.filter((i) => i.kind === "geometry") as Extract<
      SearchItem,
      { kind: "geometry" }
    >[];
    expect(geos).toHaveLength(2);
    expect(geos.map((g) => g.id).sort()).toEqual(["geo:g1", "geo:g2"]);
    const g1 = geos.find((g) => g.uuid === "g1");
    expect(g1).toBeDefined();
    expect(g1!.name).toBe("rect1");
    expect(g1!.id).toBe("geo:g1");
  });

  it("emits one powerShape row per power shape — and skips SENTINEL_UNSET_POWER_SHAPE", () => {
    const resources = emptyResources();
    // The sentinel is always present in the live store; it must not appear in the pool.
    resources.powerShapes[SENTINEL_UNSET_POWER_SHAPE] = {
      uuid: SENTINEL_UNSET_POWER_SHAPE,
      name: "(leave unset — set in code)",
      kind: "unset",
      params: {},
    };
    resources.powerShapes["ps1"] = powerShape("ps1", "uniform-shape");

    const items = buildSearchPool([], resources);

    const shapes = items.filter((i) => i.kind === "powerShape") as Extract<
      SearchItem,
      { kind: "powerShape" }
    >[];
    expect(shapes).toHaveLength(1);
    expect(shapes[0].id).toBe("ps:ps1");
    expect(shapes[0].name).toBe("uniform-shape");
    expect(shapes[0].uuid).toBe("ps1");

    // Sentinel filtered out.
    expect(items.find((i) => i.kind === "powerShape" && i.id === `ps:${SENTINEL_UNSET_POWER_SHAPE}`)).toBeUndefined();
  });

  it("emits one fluid row per fluid resource — light_water sentinel is NOT filtered", () => {
    const resources = emptyResources();
    // light_water sentinel IS a real selectable fluid per plan <behavior>.
    resources.fluids[SENTINEL_LIGHT_WATER_FLUID] = fluid(
      SENTINEL_LIGHT_WATER_FLUID,
      "light_water",
    );

    const items = buildSearchPool([], resources);

    const fluids = items.filter((i) => i.kind === "fluid") as Extract<
      SearchItem,
      { kind: "fluid" }
    >[];
    expect(fluids).toHaveLength(1);
    expect(fluids[0].id).toBe(`fl:${SENTINEL_LIGHT_WATER_FLUID}`);
    expect(fluids[0].name).toBe("light_water");
  });

  it("emits modelOptions row last, after all other categories (D-05: always present)", () => {
    const resources = emptyResources();
    resources.geometries["g1"] = geom("g1", "rect1");
    resources.powerShapes["ps1"] = powerShape("ps1", "shape1");
    resources.fluids["f1"] = fluid("f1", "heavy_water");
    const node = streamNode("n1", "Channel", "ch1");

    const items = buildSearchPool([node], resources);

    // component + geometry + powerShape + fluid + modelOptions = 5
    expect(items).toHaveLength(5);

    // Last item is always the modelOptions sentinel.
    const last = items[items.length - 1];
    expect(last).toEqual({
      kind: "modelOptions",
      id: "modelOptions",
      name: "Project Options",
    });

    // Exactly one modelOptions row.
    const modelOpts = items.filter((i) => i.kind === "modelOptions");
    expect(modelOpts).toHaveLength(1);
  });
});
