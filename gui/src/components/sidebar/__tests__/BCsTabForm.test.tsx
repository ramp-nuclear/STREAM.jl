// @vitest-environment happy-dom
//
// Phase 63 Plan 63-C Task 03 — BCsTabForm tests.
// Covers D-04 (mode picker), D-05 (symmetric toggle + expansion), D-08
// (Function-mode editor minimal), D-09 (required-unset), D-20 (`+ New
// WallTemperature` flow + n-default-from-consumer), and CD-05 (symmetric
// default ON, per-instance).

import { describe, it, expect, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import type { Node } from "@xyflow/react";
import BCsTabForm from "../BCsTabForm";
import useStore, { type StreamNodeData } from "../../../store/useStore";
import { bcModeKey } from "../../../lib/bcMode";
import type { ComponentDefinition } from "../../../registry/types";

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const mockChannel: ComponentDefinition = {
  id: "Channel",
  label: "Channel",
  category: "Hydraulic",
  description: "Test channel",
  ports: [],
  parameters: [
    {
      name: "n",
      type: "Int",
      description: "Segments",
      required: true,
      positional: false,
    },
  ],
  constructorModes: [
    { mode: "default", signature: "Channel(; ...)", parameters: ["n"] },
  ],
  external_inputs: [
    {
      name: "T_wall_left",
      shape: "[1:n]",
      description: "left BC",
      bc_modes: ["Value", "Profile", "Function", "Mark", "Source"],
      source_component: "WallTemperature",
      source_port: "T_wall_out",
    },
    {
      name: "T_wall_right",
      shape: "[1:n]",
      description: "right BC",
      bc_modes: ["Value", "Profile", "Function", "Mark", "Source"],
      source_component: "WallTemperature",
      source_port: "T_wall_out",
    },
  ],
};

function makeChannelNode(id: string, n: number): Node {
  return {
    id,
    type: "streamNode",
    position: { x: 200, y: 100 },
    data: {
      componentId: "Channel",
      instanceName: id,
      parameters: { n },
      constructorMode: "default",
    } satisfies StreamNodeData,
  };
}

function makeWTNode(id: string, n: number): Node {
  return {
    id,
    type: "streamNode",
    position: { x: 80, y: 100 },
    data: {
      componentId: "WallTemperature",
      instanceName: id,
      parameters: { n, T_wall: 320 },
      constructorMode: "default",
    } satisfies StreamNodeData,
  };
}

beforeEach(() => {
  useStore.setState({
    nodes: [makeChannelNode("ch1", 10)],
    edges: [],
    selectedNodeId: "ch1",
    anchors: {},
    isDirty: false,
    _undoPast: [],
    _undoFuture: [],
    bcMode: {},
    bcSymmetric: {},
    // Phase 63.1 D-15: errorTagsByNodeId slice removed.
  });
});

function renderForm() {
  return render(<BCsTabForm component={mockChannel} nodeId="ch1" />);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("BCsTabForm", () => {
  it("renders one symmetric toggle + one BC mode dropdown for a paired field set (default symmetric ON) (D-05, D-11)", () => {
    renderForm();
    // Phase 63.1 D-12: SegmentedButtonGroup with explicit Symmetric/Asymmetric labels.
    expect(screen.getByRole("button", { name: "Symmetric" })).toBeTruthy();
    expect(screen.getByRole("button", { name: "Asymmetric" })).toBeTruthy();
    // Phase 63.1 D-11: single inline Select dropdown (combobox role) for the pair.
    const combos = screen.getAllByRole("combobox");
    expect(combos.length).toBe(1);
    // The required-unset placeholder is shown on the trigger.
    expect(screen.getByText("Select BC mode...")).toBeTruthy();
    // The required-unset destructive hint is rendered (D-09 carry-over).
    expect(screen.getByText("BC required; select a mode")).toBeTruthy();
    // The section heading (base field name) appears.
    expect(screen.getAllByText("T_wall").length).toBeGreaterThanOrEqual(1);
  });

  it("expands to two stacked BC mode dropdowns when symmetric toggle is OFF (D-05, D-11, D-12)", () => {
    renderForm();
    // Phase 63.1 D-12: click the "Asymmetric" segmented button to break symmetric mirroring.
    fireEvent.click(screen.getByRole("button", { name: "Asymmetric" }));
    // Now both sides should render their own Select trigger — two combobox roles.
    const combos = screen.getAllByRole("combobox");
    expect(combos.length).toBe(2);
    // Both sibling labels appear as section headings.
    expect(screen.getByText("T_wall_left[1:n]")).toBeTruthy();
    expect(screen.getByText("T_wall_right[1:n]")).toBeTruthy();
  });

  it("renders the entry's current mode label on the Select trigger when entry is set (D-11)", () => {
    useStore.setState({
      bcMode: {
        [bcModeKey("ch1", "T_wall_left")]: { mode: "value", value: 0 },
        [bcModeKey("ch1", "T_wall_right")]: { mode: "value", value: 0 },
      },
    });
    renderForm();
    // The combobox trigger displays the selected mode label.
    const combo = screen.getByRole("combobox");
    expect(combo.textContent).toContain("Value");
    // Required-unset hint is no longer shown.
    expect(screen.queryByText("BC required; select a mode")).toBeNull();
  });

  it("renders NumericField below the picker when mode is Value", () => {
    useStore.setState({
      bcMode: {
        [bcModeKey("ch1", "T_wall_left")]: { mode: "value", value: 320 },
        [bcModeKey("ch1", "T_wall_right")]: { mode: "value", value: 320 },
      },
    });
    renderForm();
    // The Value pill is the active one (button), and the NumericField label
    // is also "Value" — assert at least one matching element exists.
    expect(screen.getAllByText("Value").length).toBeGreaterThanOrEqual(1);
    // The Input element carries the entry's numeric value.
    const inputs = screen.getAllByRole("textbox");
    const valueInput = inputs.find(
      (i) => (i as HTMLInputElement).value === "320",
    );
    expect(valueInput).toBeTruthy();
  });

  it("renders cosine NumericFields when mode is Profile + preset=cosine (D-06)", () => {
    useStore.setState({
      bcMode: {
        [bcModeKey("ch1", "T_wall_left")]: {
          mode: "profile",
          preset: "cosine",
          amplitude: 50,
          peakingFactor: 1.5,
        },
        [bcModeKey("ch1", "T_wall_right")]: {
          mode: "profile",
          preset: "cosine",
          amplitude: 50,
          peakingFactor: 1.5,
        },
      },
    });
    renderForm();
    expect(screen.getByText("amplitude")).toBeTruthy();
    expect(screen.getByText("peakingFactor")).toBeTruthy();
  });

  it("renders signature picker + function name input when mode is Function (D-08)", () => {
    useStore.setState({
      bcMode: {
        [bcModeKey("ch1", "T_wall_left")]: {
          mode: "function",
          signature: "fn(t)",
          functionName: "T_wall_fn",
        },
        [bcModeKey("ch1", "T_wall_right")]: {
          mode: "function",
          signature: "fn(t)",
          functionName: "T_wall_fn",
        },
      },
    });
    renderForm();
    expect(screen.getByRole("button", { name: "fn(t)" })).toBeTruthy();
    expect(screen.getByRole("button", { name: "fn(t, i)" })).toBeTruthy();
    expect(screen.getByText("Function name")).toBeTruthy();
  });

  it("renders 'Marked in code' hint and NO editor body when mode is Mark (D-08)", () => {
    useStore.setState({
      bcMode: {
        [bcModeKey("ch1", "T_wall_left")]: { mode: "mark" },
        [bcModeKey("ch1", "T_wall_right")]: { mode: "mark" },
      },
    });
    renderForm();
    expect(screen.getByText(/Marked in code/i)).toBeTruthy();
    // No numeric input for "Value" should be present.
    expect(screen.queryByText("amplitude")).toBeNull();
  });

  it("Promote-to-shared-source button renders next to the Mode Select when entry.mode !== 'source' and source_component is defined (Phase 63.1 D-07)", () => {
    // Default beforeEach leaves bcMode empty → entry === undefined →
    // entry?.mode !== "source", so the Promote button must render.
    renderForm();
    expect(
      screen.getByRole("button", { name: /Promote to shared source/ }),
    ).toBeTruthy();
  });

  it("Promote-to-shared-source button is HIDDEN when entry.mode === 'source' (Phase 63.1 D-07 visibility rule)", () => {
    useStore.setState({
      bcMode: {
        [bcModeKey("ch1", "T_wall_left")]: {
          mode: "source",
          sourceNodeId: "",
        },
        [bcModeKey("ch1", "T_wall_right")]: {
          mode: "source",
          sourceNodeId: "",
        },
      },
    });
    renderForm();
    expect(
      screen.queryByRole("button", { name: /Promote to shared source/ }),
    ).toBeNull();
  });

  it("Source mode with existing source nodes shows a Select dropdown listing them (D-20)", () => {
    const wt = makeWTNode("wt1", 10);
    useStore.setState({
      nodes: [makeChannelNode("ch1", 10), wt],
      bcMode: {
        [bcModeKey("ch1", "T_wall_left")]: {
          mode: "source",
          sourceNodeId: "wt1",
        },
        [bcModeKey("ch1", "T_wall_right")]: {
          mode: "source",
          sourceNodeId: "wt1",
        },
      },
    });
    renderForm();
    // Radix Select renders a combobox role on its trigger. In Phase 63.1 D-11
    // the BC mode picker is also a combobox, so we expect at least 2:
    // (1) the BC mode dropdown, (2) the source-node picker.
    const combos = screen.getAllByRole("combobox");
    expect(combos.length).toBeGreaterThanOrEqual(2);
  });

  it("clicking the Promote button spawns a WallTemperature node and flips the entry to source mode (Phase 63.1 D-07 / D-08)", () => {
    // bcMode left undefined → Promote button visible. Click it.
    renderForm();
    fireEvent.click(
      screen.getByRole("button", { name: /Promote to shared source/ }),
    );
    const state = useStore.getState();
    // Two nodes: original Channel + newly-spawned WallTemperature.
    expect(state.nodes.length).toBe(2);
    const wtNode = state.nodes.find(
      (n) => (n.data as StreamNodeData).componentId === "WallTemperature",
    );
    expect(wtNode).toBeDefined();
    // bcMode entry is now source mode pointing at the new WT id.
    const leftEntry = state.bcMode[bcModeKey("ch1", "T_wall_left")];
    expect(leftEntry?.mode).toBe("source");
    if (leftEntry?.mode === "source") {
      expect(leftEntry.sourceNodeId).toBe(wtNode!.id);
    }
  });

  it("clicking Promote seeds the new WallTemperature's n from the consumer Channel (Phase 63.1 D-07 / D-08 — n defaults to consumer's n)", () => {
    // Channel n = 12 fixture.
    useStore.setState({
      nodes: [makeChannelNode("ch1", 12)],
    });
    renderForm();
    fireEvent.click(
      screen.getByRole("button", { name: /Promote to shared source/ }),
    );
    const state = useStore.getState();
    const wtNode = state.nodes.find(
      (n) => (n.data as StreamNodeData).componentId === "WallTemperature",
    );
    expect(wtNode).toBeDefined();
    const wtN = (wtNode!.data as StreamNodeData).parameters?.n;
    expect(wtN).toBe(12);
  });

  // Plan 63.1-13 (GAP-MINOR-SOURCE-GATE): the Source SelectItem must be
  // disabled when no Sources-category nodes exist on the canvas.
  it("Source SelectItem is disabled when no nodes with category='Sources' exist (GAP-MINOR-SOURCE-GATE)", () => {
    // beforeEach seeds only a Channel — no WT/HFS on the canvas.
    renderForm();
    // Open the BC mode Select (the first combobox is the BC mode picker).
    const combos = screen.getAllByRole("combobox");
    fireEvent.click(combos[0]);
    // Radix Select renders SelectItems with role="option". Source must be
    // present but aria-disabled.
    const sourceOption = screen.getByRole("option", { name: /^source$/i });
    expect(sourceOption.getAttribute("aria-disabled")).toBe("true");
  });

  it("Source SelectItem is ENABLED when at least one Sources-category node exists (GAP-MINOR-SOURCE-GATE)", () => {
    const wt = makeWTNode("wt1", 10);
    useStore.setState({
      nodes: [makeChannelNode("ch1", 10), wt],
    });
    renderForm();
    const combos = screen.getAllByRole("combobox");
    fireEvent.click(combos[0]);
    const sourceOption = screen.getByRole("option", { name: /^source$/i });
    expect(sourceOption.getAttribute("aria-disabled")).not.toBe("true");
  });

  // Plan 63.1-13 (GAP-COSMETIC-PROMOTE): Promote button is icon-only with
  // aria-label="Promote to shared source" + a hover tooltip carrying the
  // same string. No visible text content.
  it("Promote button is icon-only with accessible label and no visible text (GAP-COSMETIC-PROMOTE)", () => {
    renderForm();
    const button = screen.getByRole("button", {
      name: "Promote to shared source",
    });
    // Icon-only: visible text inside the button is empty (the SVG glyph is
    // not text). Whitespace tolerated.
    expect(button.textContent?.trim() ?? "").toBe("");
    // The legacy "↗" character must be gone from the button content.
    expect(button.textContent ?? "").not.toContain("↗");
    // Button contains an SVG child (the lucide MoveUpRight glyph).
    expect(button.querySelector("svg")).toBeTruthy();
    // aria-label carries the accessible name.
    expect(button.getAttribute("aria-label")).toBe("Promote to shared source");
  });
});
