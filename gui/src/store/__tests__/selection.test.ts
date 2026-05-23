import { describe, it, expect, beforeEach } from "vitest";
import useStore, {
  SENTINEL_UNSET_POWER_SHAPE,
  SENTINEL_LIGHT_WATER_FLUID,
} from "../useStore";

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

describe("selection router (D-05, INV-09, INV-17)", () => {
  describe("initial state", () => {
    it("selectedNodeId, selectedResourceId are null; selectionKind is 'none'", () => {
      const s = useStore.getState();
      expect(s.selectedNodeId).toBeNull();
      expect(s.selectedResourceId).toBeNull();
      expect(s.selectedResourceKind).toBeNull();
      expect(s.selectionKind).toBe("none");
    });
  });

  describe("INV-09: selection-kind mutual exclusivity (D-05)", () => {
    it("INV-09: selectNode sets selectionKind='component' and clears resource selection", () => {
      useStore.getState().selectNode("node-1");
      const s = useStore.getState();
      expect(s.selectedNodeId).toBe("node-1");
      expect(s.selectedResourceId).toBeNull();
      expect(s.selectedResourceKind).toBeNull();
      expect(s.selectionKind).toBe("component");
    });

    it("INV-09: selectResource clears the canvas selection (mutual exclusivity)", () => {
      useStore.getState().selectNode("node-1");
      expect(useStore.getState().selectedNodeId).toBe("node-1");
      const gUuid = useStore.getState().addGeometry({
        name: "g_sel",
        kind: "rectangular",
        params: { L: 1.0 },
      });
      useStore.getState().selectResource(gUuid, "geometry");
      const s = useStore.getState();
      expect(s.selectedResourceId).toBe(gUuid);
      expect(s.selectedResourceKind).toBe("geometry");
      expect(s.selectedNodeId).toBeNull();
      expect(s.selectionKind).toBe("resource");
    });

    it("INV-09: re-selecting a canvas node after a resource clears selectedResourceId", () => {
      const gUuid = useStore.getState().addGeometry({
        name: "g_sel_swap",
        kind: "rectangular",
        params: { L: 1.0 },
      });
      useStore.getState().selectResource(gUuid, "geometry");
      expect(useStore.getState().selectedResourceId).toBe(gUuid);
      useStore.getState().selectNode("node-2");
      const s = useStore.getState();
      expect(s.selectedNodeId).toBe("node-2");
      expect(s.selectedResourceId).toBeNull();
      expect(s.selectionKind).toBe("component");
    });

    it("INV-09: selectNode(null) clears the canvas selection without touching resource selection", () => {
      // selectNode(null) is the standard canvas-deselect path. It also clears
      // resource selection by the D-05 invariant (single source of truth on
      // selection — both ids null = selectionKind 'none').
      useStore.getState().selectNode("node-1");
      useStore.getState().selectNode(null);
      const s = useStore.getState();
      expect(s.selectedNodeId).toBeNull();
      expect(s.selectedResourceId).toBeNull();
      expect(s.selectionKind).toBe("none");
    });
  });

  describe("INV-17: Edit… jump shape (state composition)", () => {
    it("INV-17: selectResource + setActiveLeftTab compose — tab switches AND resource is selected AND canvas selection cleared", () => {
      // Sequence is exactly what the 62-08 Edit… handler will dispatch:
      // selectResource(uuid, kind) then setActiveLeftTab('Resources').
      useStore.getState().selectNode("node-A");
      const gUuid = useStore.getState().addGeometry({
        name: "g_edit_jump",
        kind: "rectangular",
        params: { L: 1.0 },
      });
      useStore.getState().selectResource(gUuid, "geometry");
      useStore.getState().setActiveLeftTab("Resources");
      const s = useStore.getState();
      expect(s.activeLeftTab).toBe("Resources");
      expect(s.selectedResourceId).toBe(gUuid);
      expect(s.selectedResourceKind).toBe("geometry");
      expect(s.selectedNodeId).toBeNull();
      expect(s.selectionKind).toBe("resource");
    });
  });

  describe("clearSelection", () => {
    it("clearSelection after selectNode resets both ids and sets selectionKind='none'", () => {
      useStore.getState().selectNode("node-1");
      useStore.getState().clearSelection();
      const s = useStore.getState();
      expect(s.selectedNodeId).toBeNull();
      expect(s.selectedResourceId).toBeNull();
      expect(s.selectedResourceKind).toBeNull();
      expect(s.selectionKind).toBe("none");
    });

    it("clearSelection after selectResource resets both ids and sets selectionKind='none'", () => {
      const gUuid = useStore.getState().addGeometry({
        name: "g_clear",
        kind: "rectangular",
        params: { L: 1.0 },
      });
      useStore.getState().selectResource(gUuid, "geometry");
      useStore.getState().clearSelection();
      const s = useStore.getState();
      expect(s.selectedNodeId).toBeNull();
      expect(s.selectedResourceId).toBeNull();
      expect(s.selectedResourceKind).toBeNull();
      expect(s.selectionKind).toBe("none");
    });
  });

  describe("selectResource accepts fluid kind", () => {
    it("selectResource(uuid, 'fluid') sets selectedResourceKind='fluid'", () => {
      useStore.getState().selectResource(SENTINEL_LIGHT_WATER_FLUID, "fluid");
      const s = useStore.getState();
      expect(s.selectedResourceId).toBe(SENTINEL_LIGHT_WATER_FLUID);
      expect(s.selectedResourceKind).toBe("fluid");
      expect(s.selectionKind).toBe("resource");
    });
  });
});
