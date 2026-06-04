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

describe("activeLeftTab (D-01, D-08, INV-11)", () => {
  it("D-01 + D-08: defaults to 'Components'", () => {
    expect(useStore.getState().activeLeftTab).toBe("Components");
  });

  it("setActiveLeftTab('Resources') updates the value", () => {
    useStore.getState().setActiveLeftTab("Resources");
    expect(useStore.getState().activeLeftTab).toBe("Resources");
  });

  it("setActiveLeftTab('Project') updates the value", () => {
    useStore.getState().setActiveLeftTab("Project");
    expect(useStore.getState().activeLeftTab).toBe("Project");
  });

  it("setActiveLeftTab does NOT push to _undoPast (UI state, not content state)", () => {
    const before = useStore.getState()._undoPast.length;
    useStore.getState().setActiveLeftTab("Resources");
    useStore.getState().setActiveLeftTab("Project");
    useStore.getState().setActiveLeftTab("Components");
    expect(useStore.getState()._undoPast.length).toBe(before);
  });

  it("setActiveLeftTab DOES set isDirty: true (persisted in .scp layout block per D-29)", () => {
    // Resolution per plan: the change IS part of layout state that gets
    // serialized into .scp, so the document is dirty even though the tab
    // change does not push an undo entry.
    useStore.setState({ isDirty: false });
    useStore.getState().setActiveLeftTab("Resources");
    expect(useStore.getState().isDirty).toBe(true);
  });

  it("activeLeftTab is preserved across undo (NOT in CanvasSnapshot)", () => {
    useStore.getState().setActiveLeftTab("Resources");
    // Mutate canvas (which DOES push a snapshot), then undo. The activeLeftTab
    // should be unchanged because it's intentionally not part of the snapshot.
    useStore.getState().addNode("Pump", { x: 0, y: 0 });
    expect(useStore.getState().nodes).toHaveLength(1);
    useStore.getState().undo();
    expect(useStore.getState().nodes).toHaveLength(0);
    expect(useStore.getState().activeLeftTab).toBe("Resources");
  });
});
