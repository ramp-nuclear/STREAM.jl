// @vitest-environment happy-dom
//
// Phase 62 Plan 62-06 Task 2 — ResourcesTreePanel vitest coverage.
//
// Implements decisions D-03 (tree shape, + buttons, fluids placeholder,
// rename, context menu), D-05 (selection mutual exclusivity), D-20
// (empty-state copy when search yields zero matches), D-26 (sentinel
// PowerShape filtered out of the visible tree).
//
// Portal-mounting note: Radix ContextMenu and AlertDialog mount their
// content via React Portals. happy-dom handles portals into document.body
// correctly, so `screen` queries find rendered content. For asynchronous
// open transitions, we use `findBy*` (async) — these resolve once the
// content is attached.

import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, cleanup, within } from "@testing-library/react";
import { TooltipProvider } from "@/components/ui/tooltip";
import ResourcesTreePanel from "../ResourcesTreePanel";
import useStore, {
  SENTINEL_UNSET_POWER_SHAPE,
  SENTINEL_LIGHT_WATER_FLUID,
} from "@/store/useStore";

// Wrap renders in TooltipProvider since the Fluids group's disabled `+`
// button uses Tooltip (Radix Tooltip requires a provider in the tree).
function renderTree() {
  return render(
    <TooltipProvider delayDuration={0}>
      <ResourcesTreePanel />
    </TooltipProvider>,
  );
}

// Reset the store to a clean Phase 62 baseline before every test. Bake in
// the unset PowerShape sentinel and the light_water fluid placeholder.
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
    activeLeftTab: "Resources",
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

describe("ResourcesTreePanel — tree shape (D-03)", () => {
  it("D-03: renders three group headers GEOMETRIES / POWER SHAPES / FLUIDS", () => {
    renderTree();
    // Tailwind uppercase => match case-insensitively.
    expect(screen.getByText(/^Geometries$/i)).toBeTruthy();
    expect(screen.getByText(/^Power Shapes$/i)).toBeTruthy();
    expect(screen.getByText(/^Fluids$/i)).toBeTruthy();
  });

  it("D-03: each group exposes a + button with aria-label", () => {
    renderTree();
    expect(screen.getByRole("button", { name: /Add geometry/i })).toBeTruthy();
    expect(screen.getByRole("button", { name: /Add power shape/i })).toBeTruthy();
    expect(screen.getByRole("button", { name: /Add fluid/i })).toBeTruthy();
  });

  it("D-03: the Fluids + button is disabled (Phase 62 multi-fluid OOS)", () => {
    renderTree();
    const fluidAdd = screen.getByRole("button", { name: /Add fluid/i });
    expect(fluidAdd).toHaveProperty("disabled", true);
  });
});

describe("ResourcesTreePanel — Fluids placeholder row", () => {
  it("renders the light_water fluid row", () => {
    renderTree();
    expect(screen.getByText("light_water")).toBeTruthy();
  });

  it("light_water row does NOT enter rename mode on double-click", () => {
    renderTree();
    const fluidRow = screen.getByText("light_water").closest('li[role="treeitem"]');
    expect(fluidRow).not.toBeNull();
    fireEvent.doubleClick(fluidRow!);
    // No <input> appears for the fluid row.
    const input = fluidRow!.querySelector("input");
    expect(input).toBeNull();
  });

  it("light_water row does NOT open a context menu on right-click", () => {
    renderTree();
    const fluidRow = screen.getByText("light_water").closest('li[role="treeitem"]');
    expect(fluidRow).not.toBeNull();
    fireEvent.contextMenu(fluidRow!);
    // No menuitem named "Delete" appears (the fluid row has no ContextMenu wrapper).
    expect(screen.queryByRole("menuitem", { name: /^Delete$/i })).toBeNull();
  });
});

describe("ResourcesTreePanel — D-26 sentinel filter", () => {
  it("D-26: the unset PowerShape sentinel is NOT rendered as a row in Power Shapes", () => {
    renderTree();
    // The sentinel's name is "(leave unset — fill in code)" — it must not
    // appear in the tree body (it only lives in the field-level picker).
    expect(screen.queryByText("(leave unset — fill in code)")).toBeNull();
    // No <li> in the tree carries the sentinel UUID.
    const sentinelLi = document.querySelector(
      `li[data-resource-uuid="${SENTINEL_UNSET_POWER_SHAPE}"]`,
    );
    expect(sentinelLi).toBeNull();
  });

  it("D-26: empty Power Shapes group (post sentinel filter) renders the (none yet — click +) placeholder", () => {
    renderTree();
    // Initial state has only the sentinel; after filtering, the group is
    // empty, so the placeholder copy appears at least once.
    const placeholders = screen.getAllByText(/\(none yet — click \+\)/);
    expect(placeholders.length).toBeGreaterThanOrEqual(1);
  });
});

describe("ResourcesTreePanel — search filter", () => {
  beforeEach(() => {
    // Seed resources for search tests.
    useStore.getState().addGeometry({
      name: "mtr_channel",
      kind: "rectangular",
      params: { L: 1.0, W: 0.1, H: 0.05 },
    });
    useStore.getState().addPowerShape({
      name: "axial_cos",
      kind: "z_cosine",
      params: { amplitude: 1.0 },
    });
  });

  it("D-03: case-insensitive substring filter hides non-matching rows", () => {
    renderTree();
    // Both seeded resources visible initially.
    expect(screen.getByText("mtr_channel")).toBeTruthy();
    expect(screen.getByText("axial_cos")).toBeTruthy();
    // Type "mtr" — power-shape `axial_cos` should disappear.
    const search = screen.getByLabelText(/Search resources/i);
    fireEvent.change(search, { target: { value: "mtr" } });
    expect(screen.queryByText("mtr_channel")).toBeTruthy();
    expect(screen.queryByText("axial_cos")).toBeNull();
    // Clear search restores both.
    fireEvent.change(search, { target: { value: "" } });
    expect(screen.getByText("mtr_channel")).toBeTruthy();
    expect(screen.getByText("axial_cos")).toBeTruthy();
  });

  it("D-20: when search matches nothing, all groups show the empty-state placeholder", () => {
    renderTree();
    const search = screen.getByLabelText(/Search resources/i);
    fireEvent.change(search, { target: { value: "zzzzzzzz_no_match" } });
    const placeholders = screen.getAllByText(/\(none yet — click \+\)/);
    // Three groups => three placeholder lines.
    expect(placeholders.length).toBe(3);
  });
});

describe("ResourcesTreePanel — selection (D-05)", () => {
  it("D-05: clicking a Geometry row selects it AND clears any canvas selection", () => {
    // Seed a Geometry and pre-populate a canvas selection.
    const gUuid = useStore.getState().addGeometry({
      name: "g_alpha",
      kind: "rectangular",
      params: { L: 1.0, W: 0.1, H: 0.05 },
    });
    useStore.setState({ selectedNodeId: "some-existing-node-id" });

    renderTree();
    const row = screen.getByText("g_alpha").closest('li[role="treeitem"]');
    expect(row).not.toBeNull();
    fireEvent.click(row!);

    const s = useStore.getState();
    expect(s.selectedResourceId).toBe(gUuid);
    expect(s.selectedResourceKind).toBe("geometry");
    expect(s.selectedNodeId).toBeNull();
  });
});

describe("ResourcesTreePanel — inline rename (D-03)", () => {
  it("F2 activates rename; Enter commits new name to the store", () => {
    const uuid = useStore.getState().addGeometry({
      name: "g_orig",
      kind: "rectangular",
      params: { L: 1.0, W: 0.1, H: 0.05 },
    });

    renderTree();
    const row = screen.getByText("g_orig").closest('li[role="treeitem"]');
    expect(row).not.toBeNull();
    fireEvent.keyDown(row!, { key: "F2" });

    // Input now visible inside the row.
    const input = within(row as HTMLElement).getByRole("textbox") as HTMLInputElement;
    expect(input).toBeTruthy();
    fireEvent.change(input, { target: { value: "g_renamed" } });
    fireEvent.keyDown(input, { key: "Enter" });

    expect(useStore.getState().resources.geometries[uuid].name).toBe("g_renamed");
  });

  it("Esc cancels rename and leaves the resource name unchanged", () => {
    const uuid = useStore.getState().addGeometry({
      name: "g_safe",
      kind: "rectangular",
      params: { L: 1.0, W: 0.1, H: 0.05 },
    });

    renderTree();
    const row = screen.getByText("g_safe").closest('li[role="treeitem"]');
    fireEvent.keyDown(row!, { key: "F2" });
    const input = within(row as HTMLElement).getByRole("textbox") as HTMLInputElement;
    fireEvent.change(input, { target: { value: "discard_me" } });
    fireEvent.keyDown(input, { key: "Escape" });

    expect(useStore.getState().resources.geometries[uuid].name).toBe("g_safe");
    // After Esc the input must be gone (rename mode exited).
    expect(within(row as HTMLElement).queryByRole("textbox")).toBeNull();
  });

  it("Rename collision blocks commit; resource name unchanged; input shows aria-invalid", () => {
    useStore.getState().addGeometry({
      name: "g1",
      kind: "rectangular",
      params: { L: 1.0, W: 0.1, H: 0.05 },
    });
    const uuidTwo = useStore.getState().addGeometry({
      name: "g2",
      kind: "rectangular",
      params: { L: 1.0, W: 0.1, H: 0.05 },
    });

    renderTree();
    const row = screen.getByText("g2").closest('li[role="treeitem"]');
    fireEvent.keyDown(row!, { key: "F2" });
    const input = within(row as HTMLElement).getByRole("textbox") as HTMLInputElement;
    fireEvent.change(input, { target: { value: "g1" } });
    fireEvent.keyDown(input, { key: "Enter" });

    // Name unchanged.
    expect(useStore.getState().resources.geometries[uuidTwo].name).toBe("g2");
    // Input shows the destructive (aria-invalid) state.
    const stillInput = within(row as HTMLElement).getByRole("textbox") as HTMLInputElement;
    expect(stillInput.getAttribute("aria-invalid")).toBe("true");
  });
});

describe("ResourcesTreePanel — context menu (D-03)", () => {
  it("Context menu Rename triggers the same inline-rename mode as F2", async () => {
    useStore.getState().addGeometry({
      name: "g_ctx",
      kind: "rectangular",
      params: { L: 1.0, W: 0.1, H: 0.05 },
    });

    renderTree();
    const row = screen.getByText("g_ctx").closest('li[role="treeitem"]');
    fireEvent.contextMenu(row!);

    // Radix portals the menu content into document.body.
    const renameItem = await screen.findByRole("menuitem", { name: /^Rename$/i });
    fireEvent.click(renameItem);

    const input = within(row as HTMLElement).getByRole("textbox") as HTMLInputElement;
    expect(input).toBeTruthy();
  });

  it("Context menu Delete with zero usages immediately removes the resource", async () => {
    const uuid = useStore.getState().addGeometry({
      name: "g_to_delete",
      kind: "rectangular",
      params: { L: 1.0, W: 0.1, H: 0.05 },
    });

    renderTree();
    const row = screen.getByText("g_to_delete").closest('li[role="treeitem"]');
    fireEvent.contextMenu(row!);

    const del = await screen.findByRole("menuitem", { name: /^Delete$/i });
    fireEvent.click(del);

    expect(useStore.getState().resources.geometries[uuid]).toBeUndefined();
  });

  it("Context menu Delete with usages opens an AlertDialog and Cancel keeps the resource", async () => {
    const uuid = useStore.getState().addGeometry({
      name: "g_used",
      kind: "rectangular",
      params: { L: 1.0, W: 0.1, H: 0.05 },
    });
    // Add a node that references this geometry via parameters.geometry_ref.
    useStore.setState({
      nodes: [
        {
          id: "node-1",
          type: "streamNode",
          position: { x: 0, y: 0 },
          data: {
            componentId: "Channel",
            instanceName: "channel_1",
            parameters: { geometry_ref: uuid },
            constructorMode: "default",
          },
        },
      ],
    });

    renderTree();
    const row = screen.getByText("g_used").closest('li[role="treeitem"]');
    fireEvent.contextMenu(row!);

    const del = await screen.findByRole("menuitem", { name: /^Delete$/i });
    fireEvent.click(del);

    // AlertDialog content rendered (portal). The description carries the
    // verbatim copy "Delete geometry g_used? It is used by 1 component(s)."
    const desc = await screen.findByText(
      /Delete geometry g_used\? It is used by 1 component\(s\)\./,
    );
    expect(desc).toBeTruthy();

    // Cancel button keeps the resource.
    const cancel = await screen.findByRole("button", { name: /^Cancel$/i });
    fireEvent.click(cancel);

    expect(useStore.getState().resources.geometries[uuid]).toBeDefined();
  });
});
