import { describe, it, expect, beforeEach } from "vitest";
import useStore, {
  SENTINEL_UNSET_POWER_SHAPE,
  SENTINEL_LIGHT_WATER_FLUID,
} from "../useStore";

beforeEach(() => {
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
    modelOptions: {
      name: "",
      description: "",
      default_fluid: "water",
      g_default: 9.80665,
      solver: { abstol: 1e-8, reltol: 1e-6, dtmax: null },
    },
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

describe("modelOptions slice (D-04 + CD-04)", () => {
  describe("D-04: initial state", () => {
    it("D-04: name defaults to empty string", () => {
      expect(useStore.getState().modelOptions.name).toBe("");
    });

    it("D-04: description defaults to empty string", () => {
      expect(useStore.getState().modelOptions.description).toBe("");
    });

    it("D-04: default_fluid defaults to 'water'", () => {
      expect(useStore.getState().modelOptions.default_fluid).toBe("water");
    });

    it("D-04: g_default defaults to 9.80665 m/s^2", () => {
      expect(useStore.getState().modelOptions.g_default).toBe(9.80665);
    });

    it("CD-04: solver.abstol defaults to 1e-8", () => {
      expect(useStore.getState().modelOptions.solver.abstol).toBe(1e-8);
    });

    it("CD-04: solver.reltol defaults to 1e-6", () => {
      expect(useStore.getState().modelOptions.solver.reltol).toBe(1e-6);
    });

    it("CD-04: solver.dtmax defaults to null (open-ended)", () => {
      expect(useStore.getState().modelOptions.solver.dtmax).toBeNull();
    });
  });

  describe("setModelOptions: shallow merge", () => {
    it("setModelOptions({name}) only changes name; other fields preserved", () => {
      useStore.getState().setModelOptions({ name: "demo" });
      const mo = useStore.getState().modelOptions;
      expect(mo.name).toBe("demo");
      expect(mo.description).toBe("");
      expect(mo.default_fluid).toBe("water");
      expect(mo.g_default).toBe(9.80665);
      expect(mo.solver.abstol).toBe(1e-8);
    });

    it("setModelOptions with full solver subobject replaces it", () => {
      useStore.getState().setModelOptions({
        solver: { abstol: 1e-10, reltol: 1e-6, dtmax: 0.1 },
      });
      const s = useStore.getState().modelOptions.solver;
      expect(s.abstol).toBe(1e-10);
      expect(s.reltol).toBe(1e-6);
      expect(s.dtmax).toBe(0.1);
    });

    it("setModelOptions with description preserves name", () => {
      useStore.getState().setModelOptions({ name: "demo" });
      useStore.getState().setModelOptions({ description: "a description" });
      const mo = useStore.getState().modelOptions;
      expect(mo.name).toBe("demo");
      expect(mo.description).toBe("a description");
    });
  });

  describe("setModelOptions: snapshot + isDirty", () => {
    it("setModelOptions calls _pushSnapshot BEFORE mutation (_undoPast.length += 1)", () => {
      const before = useStore.getState()._undoPast.length;
      useStore.getState().setModelOptions({ name: "snap_check" });
      expect(useStore.getState()._undoPast.length).toBe(before + 1);
    });

    it("setModelOptions sets isDirty: true", () => {
      useStore.setState({ isDirty: false });
      useStore.getState().setModelOptions({ name: "dirty_check" });
      expect(useStore.getState().isDirty).toBe(true);
    });

    it("undo after setModelOptions reverts the change", () => {
      useStore.getState().setModelOptions({ name: "before_undo" });
      expect(useStore.getState().modelOptions.name).toBe("before_undo");
      useStore.getState().undo();
      expect(useStore.getState().modelOptions.name).toBe("");
    });

    it("undo then redo restores the change", () => {
      useStore.getState().setModelOptions({ name: "round_trip" });
      useStore.getState().undo();
      expect(useStore.getState().modelOptions.name).toBe("");
      useStore.getState().redo();
      expect(useStore.getState().modelOptions.name).toBe("round_trip");
    });
  });

  describe("CD-04: solver fields are exactly { abstol, reltol, dtmax }", () => {
    it("CD-04: unknown solver fields are merged in permissively (TS catches at compile time)", () => {
      // Runtime is permissive — TypeScript prevents the bad shape at compile
      // time, but a runtime patch with extra fields should not throw.
      useStore.getState().setModelOptions({
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        solver: { abstol: 1e-9, reltol: 1e-7, dtmax: null, unknown_field: 42 } as any,
      });
      const s = useStore.getState().modelOptions.solver;
      expect(s.abstol).toBe(1e-9);
      expect(s.reltol).toBe(1e-7);
      expect(s.dtmax).toBeNull();
    });
  });
});
