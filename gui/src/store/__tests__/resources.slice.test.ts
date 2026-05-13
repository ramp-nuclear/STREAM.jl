import { describe, it, expect, beforeEach } from "vitest";
import useStore, {
  SENTINEL_UNSET_POWER_SHAPE,
  SENTINEL_LIGHT_WATER_FLUID,
} from "../useStore";

// Reset the store between tests. We preserve the sentinel PowerShape + the
// placeholder fluid in the resources bucket (those are baked-in invariants
// per D-26 + UI-SPEC, not test fixtures).
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

describe("resources slice", () => {
  describe("INV-01: UUID uniqueness", () => {
    it("INV-01: adding 100 geometries mints 100 unique UUIDs", () => {
      const uuids: string[] = [];
      for (let i = 0; i < 100; i++) {
        const uuid = useStore.getState().addGeometry({
          name: `geometry_${i + 1}`,
          kind: "rectangular",
          params: { L: 1.0, W: 0.1, H: 0.01 },
        });
        uuids.push(uuid);
      }
      expect(new Set(uuids).size).toBe(100);
      expect(uuids.every((u) => typeof u === "string" && u.length > 0)).toBe(true);
    });
  });

  describe("INV-04: per-kind name uniqueness (D-10)", () => {
    it("INV-04: adding two geometries with the same name throws the UI-SPEC string", () => {
      useStore.getState().addGeometry({
        name: "mtr_ch",
        kind: "rectangular",
        params: { L: 1.0 },
      });
      expect(() =>
        useStore.getState().addGeometry({
          name: "mtr_ch",
          kind: "rectangular",
          params: { L: 1.0 },
        }),
      ).toThrowError("A geometry named mtr_ch already exists.");
    });

    it("INV-04: a Geometry and a PowerShape may share a name (kinds are independent namespaces)", () => {
      const gUuid = useStore.getState().addGeometry({
        name: "mtr_ch",
        kind: "rectangular",
        params: { L: 1.0 },
      });
      const psUuid = useStore.getState().addPowerShape({
        name: "mtr_ch",
        kind: "uniform",
        params: { amplitude: 1.0 },
      });
      const { resources } = useStore.getState();
      expect(resources.geometries[gUuid].name).toBe("mtr_ch");
      expect(resources.powerShapes[psUuid].name).toBe("mtr_ch");
    });

    it("INV-04: two power shapes with the same name throws with 'power shape' label", () => {
      useStore.getState().addPowerShape({
        name: "shape_a",
        kind: "uniform",
        params: { amplitude: 1.0 },
      });
      expect(() =>
        useStore.getState().addPowerShape({
          name: "shape_a",
          kind: "z_cosine",
          params: {},
        }),
      ).toThrowError("A power shape named shape_a already exists.");
    });
  });

  describe("Julia-identifier validation on add (UI-SPEC popover copy)", () => {
    it("rejects name starting with a digit", () => {
      expect(() =>
        useStore.getState().addGeometry({
          name: "3channel",
          kind: "rectangular",
          params: { L: 1.0 },
        }),
      ).toThrowError(
        "Use ASCII letters, digits, and underscores; must not start with a digit.",
      );
    });

    it("rejects name with a dash", () => {
      expect(() =>
        useStore.getState().addGeometry({
          name: "my-channel",
          kind: "rectangular",
          params: { L: 1.0 },
        }),
      ).toThrowError(
        "Use ASCII letters, digits, and underscores; must not start with a digit.",
      );
    });

    it("accepts valid Julia identifier names", () => {
      expect(() =>
        useStore.getState().addGeometry({
          name: "my_channel",
          kind: "rectangular",
          params: { L: 1.0 },
        }),
      ).not.toThrow();
      expect(() =>
        useStore.getState().addGeometry({
          name: "my_channel_2",
          kind: "rectangular",
          params: { L: 1.0 },
        }),
      ).not.toThrow();
      expect(() =>
        useStore.getState().addGeometry({
          name: "_underscore_first",
          kind: "rectangular",
          params: { L: 1.0 },
        }),
      ).not.toThrow();
    });
  });

  describe("INV-02: rename propagation (D-12)", () => {
    it("INV-02: rename updates name in place; UUID is unchanged", () => {
      const uuid = useStore.getState().addGeometry({
        name: "old_name",
        kind: "rectangular",
        params: { L: 1.0 },
      });
      useStore.getState().renameResource("geometry", uuid, "renamed");
      const { resources } = useStore.getState();
      expect(resources.geometries[uuid].name).toBe("renamed");
      expect(resources.geometries[uuid].uuid).toBe(uuid);
    });
  });

  describe("INV-04: rename uniqueness", () => {
    it("INV-04: renaming to a name already used by another geometry throws", () => {
      useStore.getState().addGeometry({
        name: "g_a",
        kind: "rectangular",
        params: { L: 1.0 },
      });
      const uuid = useStore.getState().addGeometry({
        name: "g_b",
        kind: "rectangular",
        params: { L: 1.0 },
      });
      expect(() =>
        useStore.getState().renameResource("geometry", uuid, "g_a"),
      ).toThrowError("A geometry named g_a already exists.");
    });

    it("INV-04: renaming a geometry to a name used by a power shape succeeds (kinds independent)", () => {
      useStore.getState().addPowerShape({
        name: "shared_name",
        kind: "uniform",
        params: { amplitude: 1.0 },
      });
      const uuid = useStore.getState().addGeometry({
        name: "g_orig",
        kind: "rectangular",
        params: { L: 1.0 },
      });
      expect(() =>
        useStore.getState().renameResource("geometry", uuid, "shared_name"),
      ).not.toThrow();
      expect(useStore.getState().resources.geometries[uuid].name).toBe(
        "shared_name",
      );
    });

    it("INV-04: renaming a resource to its own current name is a no-op (does not throw)", () => {
      const uuid = useStore.getState().addGeometry({
        name: "stable",
        kind: "rectangular",
        params: { L: 1.0 },
      });
      // Renaming to the same name must NOT trip the uniqueness check (the
      // record being renamed is excluded via ignoreUuid).
      expect(() =>
        useStore.getState().renameResource("geometry", uuid, "stable"),
      ).not.toThrow();
    });
  });

  describe("INV-05: UUIDs never reused on delete (D-11)", () => {
    it("INV-05: add A, remove A, add B — B.uuid !== A.uuid", () => {
      const a = useStore.getState().addGeometry({
        name: "g_a",
        kind: "rectangular",
        params: { L: 1.0 },
      });
      useStore.getState().removeResource("geometry", a);
      const b = useStore.getState().addGeometry({
        name: "g_b",
        kind: "rectangular",
        params: { L: 1.0 },
      });
      expect(b).not.toBe(a);
      expect(useStore.getState().resources.geometries[a]).toBeUndefined();
      expect(useStore.getState().resources.geometries[b]).toBeDefined();
    });
  });

  describe("INV-08: undo/redo over Resources", () => {
    it("INV-08: undo addGeometry removes the resource", () => {
      const uuid = useStore.getState().addGeometry({
        name: "g_u",
        kind: "rectangular",
        params: { L: 1.0 },
      });
      expect(useStore.getState().resources.geometries[uuid]).toBeDefined();
      useStore.getState().undo();
      expect(useStore.getState().resources.geometries[uuid]).toBeUndefined();
    });

    it("INV-08: redo addGeometry re-adds the resource", () => {
      const uuid = useStore.getState().addGeometry({
        name: "g_r",
        kind: "rectangular",
        params: { L: 1.0 },
      });
      useStore.getState().undo();
      expect(useStore.getState().resources.geometries[uuid]).toBeUndefined();
      useStore.getState().redo();
      expect(useStore.getState().resources.geometries[uuid]).toBeDefined();
    });

    it("INV-08: undo rename reverts to original name; redo reapplies the rename", () => {
      const uuid = useStore.getState().addGeometry({
        name: "g_orig",
        kind: "rectangular",
        params: { L: 1.0 },
      });
      useStore.getState().renameResource("geometry", uuid, "g_new");
      expect(useStore.getState().resources.geometries[uuid].name).toBe("g_new");
      useStore.getState().undo();
      expect(useStore.getState().resources.geometries[uuid].name).toBe("g_orig");
      useStore.getState().redo();
      expect(useStore.getState().resources.geometries[uuid].name).toBe("g_new");
    });

    it("INV-08: undo removeResource restores the record", () => {
      const uuid = useStore.getState().addGeometry({
        name: "g_del",
        kind: "rectangular",
        params: { L: 1.0 },
      });
      useStore.getState().removeResource("geometry", uuid);
      expect(useStore.getState().resources.geometries[uuid]).toBeUndefined();
      useStore.getState().undo();
      expect(useStore.getState().resources.geometries[uuid]).toBeDefined();
      expect(useStore.getState().resources.geometries[uuid].name).toBe("g_del");
    });
  });

  describe("D-26: sentinel Power Shape", () => {
    it("D-26: sentinel exists in initial state with kind 'unset' and verbatim UI-SPEC name", () => {
      const { resources } = useStore.getState();
      const sentinel = resources.powerShapes[SENTINEL_UNSET_POWER_SHAPE];
      expect(sentinel).toBeDefined();
      expect(sentinel.kind).toBe("unset");
      expect(sentinel.name).toBe("(leave unset — set in code)");
      expect(sentinel.uuid).toBe(SENTINEL_UNSET_POWER_SHAPE);
    });

    it("D-26: SENTINEL_UNSET_POWER_SHAPE is the canonical all-zeros UUID", () => {
      expect(SENTINEL_UNSET_POWER_SHAPE).toBe(
        "00000000-0000-0000-0000-000000000000",
      );
    });

    it("D-26: removeResource on the sentinel is a no-op (sentinel still present after the call)", () => {
      useStore.getState().removeResource("powerShape", SENTINEL_UNSET_POWER_SHAPE);
      expect(
        useStore.getState().resources.powerShapes[SENTINEL_UNSET_POWER_SHAPE],
      ).toBeDefined();
    });

    it("D-26: renameResource on the sentinel is a no-op (kept original name)", () => {
      // Implementer choice documented: no-op rather than throw. The UI never
      // surfaces a rename affordance on the sentinel row, so reaching this
      // branch is defensive only.
      useStore
        .getState()
        .renameResource("powerShape", SENTINEL_UNSET_POWER_SHAPE, "anything");
      expect(
        useStore.getState().resources.powerShapes[SENTINEL_UNSET_POWER_SHAPE]
          .name,
      ).toBe("(leave unset — set in code)");
    });

    it("D-26: user cannot create another 'unset' Power Shape — addPowerShape throws", () => {
      expect(() =>
        useStore.getState().addPowerShape({
          name: "my_unset",
          kind: "unset",
          params: {},
        }),
      ).toThrowError(/unset/i);
    });

    it("D-26: duplicateResource on the sentinel throws (not a real duplicable resource)", () => {
      expect(() =>
        useStore
          .getState()
          .duplicateResource("powerShape", SENTINEL_UNSET_POWER_SHAPE),
      ).toThrowError(/sentinel|unset/i);
    });
  });

  describe("D-13 / INV-03: FK lookup behavior", () => {
    it("D-13 cross-check: given a geometry uuid, the lookup returns the record", () => {
      const uuid = useStore.getState().addGeometry({
        name: "g_lookup",
        kind: "rectangular",
        params: { L: 1.0, W: 0.05, H: 0.005 },
      });
      const record = useStore.getState().resources.geometries[uuid];
      expect(record).toBeDefined();
      expect(record.name).toBe("g_lookup");
      expect(record.params.L).toBe(1.0);
    });

    it("D-13 dangling-ref UX is Phase 71: deletion leaves geometries[uuid] === undefined", () => {
      const uuid = useStore.getState().addGeometry({
        name: "g_to_del",
        kind: "rectangular",
        params: { L: 1.0 },
      });
      useStore.getState().removeResource("geometry", uuid);
      expect(useStore.getState().resources.geometries[uuid]).toBeUndefined();
    });
  });

  describe("snapshot discipline (RESEARCH Pitfall 2)", () => {
    it("addGeometry pushes a snapshot BEFORE mutation (length increases by 1)", () => {
      const before = useStore.getState()._undoPast.length;
      useStore.getState().addGeometry({
        name: "g_snap",
        kind: "rectangular",
        params: { L: 1.0 },
      });
      expect(useStore.getState()._undoPast.length).toBe(before + 1);
    });

    it("renameResource pushes a snapshot BEFORE mutation", () => {
      const uuid = useStore.getState().addGeometry({
        name: "g_snap_r",
        kind: "rectangular",
        params: { L: 1.0 },
      });
      const before = useStore.getState()._undoPast.length;
      useStore.getState().renameResource("geometry", uuid, "g_snap_r_new");
      expect(useStore.getState()._undoPast.length).toBe(before + 1);
    });

    it("updateResource pushes a snapshot BEFORE mutation", () => {
      const uuid = useStore.getState().addGeometry({
        name: "g_snap_u",
        kind: "rectangular",
        params: { L: 1.0 },
      });
      const before = useStore.getState()._undoPast.length;
      useStore.getState().updateResource("geometry", uuid, {
        params: { L: 2.0 },
      });
      expect(useStore.getState()._undoPast.length).toBe(before + 1);
    });

    it("removeResource pushes a snapshot BEFORE mutation", () => {
      const uuid = useStore.getState().addGeometry({
        name: "g_snap_d",
        kind: "rectangular",
        params: { L: 1.0 },
      });
      const before = useStore.getState()._undoPast.length;
      useStore.getState().removeResource("geometry", uuid);
      expect(useStore.getState()._undoPast.length).toBe(before + 1);
    });

    it("duplicateResource pushes a snapshot BEFORE mutation", () => {
      const uuid = useStore.getState().addGeometry({
        name: "g_snap_dup",
        kind: "rectangular",
        params: { L: 1.0 },
      });
      const before = useStore.getState()._undoPast.length;
      useStore.getState().duplicateResource("geometry", uuid);
      expect(useStore.getState()._undoPast.length).toBe(before + 1);
    });
  });

  describe("D-19: duplicateResource smart-name-increment", () => {
    it("D-19: duplicating geometry_1 produces a name with the lowest-free integer", () => {
      const uuid = useStore.getState().addGeometry({
        name: "geometry_1",
        kind: "rectangular",
        params: { L: 1.0 },
      });
      const newUuid = useStore.getState().duplicateResource("geometry", uuid);
      const newRecord = useStore.getState().resources.geometries[newUuid];
      // Existing names after dup: { geometry_1, geometry_2 } — lowest free is 2.
      expect(newRecord.name).toBe("geometry_2");
    });

    it("D-19: duplicates do not share UUIDs but copy params", () => {
      const uuid = useStore.getState().addGeometry({
        name: "src",
        kind: "rectangular",
        params: { L: 1.5, W: 0.08, H: 0.012 },
      });
      const newUuid = useStore.getState().duplicateResource("geometry", uuid);
      const src = useStore.getState().resources.geometries[uuid];
      const dup = useStore.getState().resources.geometries[newUuid];
      expect(dup.uuid).not.toBe(src.uuid);
      expect(dup.params).toEqual(src.params);
      // Defensive: params object is a copy, not a shared reference
      expect(dup.params).not.toBe(src.params);
    });
  });

  describe("isDirty tracking on Resource actions", () => {
    it("addGeometry sets isDirty true", () => {
      useStore.setState({ isDirty: false });
      useStore.getState().addGeometry({
        name: "g_dirty",
        kind: "rectangular",
        params: { L: 1.0 },
      });
      expect(useStore.getState().isDirty).toBe(true);
    });

    it("renameResource sets isDirty true", () => {
      const uuid = useStore.getState().addGeometry({
        name: "g_d_r",
        kind: "rectangular",
        params: { L: 1.0 },
      });
      useStore.setState({ isDirty: false });
      useStore.getState().renameResource("geometry", uuid, "g_d_r_new");
      expect(useStore.getState().isDirty).toBe(true);
    });

    it("removeResource sets isDirty true", () => {
      const uuid = useStore.getState().addGeometry({
        name: "g_d_d",
        kind: "rectangular",
        params: { L: 1.0 },
      });
      useStore.setState({ isDirty: false });
      useStore.getState().removeResource("geometry", uuid);
      expect(useStore.getState().isDirty).toBe(true);
    });
  });
});
