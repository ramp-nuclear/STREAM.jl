// @vitest-environment happy-dom
//
// Phase 68 — LayersPanel interaction tests (replaces the deleted
// LayersChip.test.tsx after the UAT 2026-05-17 redesign).
//
// Covers: section header, 4 click-rows in LAYER_KEYS order with dot color +
// opacity tied to per-layer state, Eye/EyeOff icon swap, row click toggles
// the correct layer, footer cycle-toggle for hideOffLayer (Dim ↔ Hide),
// and a11y contract (role=switch, aria-checked, aria-label).

import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import LayersPanel from "../LayersPanel";
import useStore, {
  SENTINEL_UNSET_POWER_SHAPE,
  SENTINEL_LIGHT_WATER_FLUID,
} from "../../store/useStore";
import { ALL_LAYERS_ON, LAYER_KEYS } from "../../lib/layers";
import { LAYER_COLOR_VAR } from "../../lib/layerColors";

// Phase 72 — color contract is now tokenized via CSS custom properties
// (see lib/layerColors.ts). Tests assert the var() expression rather than
// resolved hex/rgb values (happy-dom does not compute CSS custom properties).

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
    activeLayers: { ...ALL_LAYERS_ON },
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

function getRow(key: string): HTMLElement {
  return screen.getByTestId(`layer-row-${key}`);
}

function getDot(key: string): HTMLElement {
  return screen.getByTestId(`layer-dot-${key}`);
}

function dotColorMatches(el: HTMLElement, key: string): boolean {
  // The inline style holds the var() expression verbatim; the browser
  // resolves it at paint time. happy-dom does not compute custom-property
  // resolution, so we assert against the raw token reference.
  return el.style.backgroundColor === LAYER_COLOR_VAR[key as keyof typeof LAYER_COLOR_VAR];
}

describe("LayersPanel — render + header", () => {
  it("renders the 'Layers' section header above the rows", () => {
    render(<LayersPanel />);
    const header = screen.getByText(/^Layers$/);
    expect(header).toBeTruthy();
    expect(header.className).toMatch(/uppercase/);
  });

  it("renders 4 rows in LAYER_KEYS order (top-to-bottom)", () => {
    render(<LayersPanel />);
    const rows = LAYER_KEYS.map((k) => getRow(k));
    const FOLLOWING = Node.DOCUMENT_POSITION_FOLLOWING;
    for (let i = 0; i < rows.length - 1; i++) {
      expect(
        rows[i].compareDocumentPosition(rows[i + 1]) & FOLLOWING,
      ).toBeTruthy();
    }
  });

  it("each row shows the full layer name (no abbreviations)", () => {
    render(<LayersPanel />);
    expect(screen.getByText("Hydraulic")).toBeTruthy();
    expect(screen.getByText("Thermal")).toBeTruthy();
    expect(screen.getByText("Sources")).toBeTruthy();
    expect(screen.getByText("Reactor Physics")).toBeTruthy();
  });
});

describe("LayersPanel — color dots", () => {
  it("each dot uses its D-01 color at full opacity when layer is on", () => {
    render(<LayersPanel />);
    for (const key of LAYER_KEYS) {
      const dot = getDot(key);
      expect(dotColorMatches(dot, key)).toBe(true);
      expect(dot.style.opacity).toBe("1");
    }
  });

  it("dot dims to opacity 0.25 when its layer is off; siblings stay at 1", () => {
    useStore.setState({
      activeLayers: { ...ALL_LAYERS_ON, Sources: false },
    });
    render(<LayersPanel />);
    expect(getDot("Hydraulic").style.opacity).toBe("1");
    expect(getDot("Thermal").style.opacity).toBe("1");
    expect(getDot("Sources").style.opacity).toBe("0.25");
    expect(getDot("ReactorPhysics").style.opacity).toBe("1");
  });
});

describe("LayersPanel — Eye / EyeOff icon swap (colorblind-safe state cue)", () => {
  it("layer ON → Eye icon present, EyeOff absent", () => {
    render(<LayersPanel />);
    for (const key of LAYER_KEYS) {
      expect(screen.queryByTestId(`layer-eye-${key}`)).toBeTruthy();
      expect(screen.queryByTestId(`layer-eye-off-${key}`)).toBeNull();
    }
  });

  it("layer OFF → EyeOff icon present, Eye absent", () => {
    useStore.setState({
      activeLayers: { ...ALL_LAYERS_ON, Thermal: false, ReactorPhysics: false },
    });
    render(<LayersPanel />);
    expect(screen.queryByTestId("layer-eye-Thermal")).toBeNull();
    expect(screen.queryByTestId("layer-eye-off-Thermal")).toBeTruthy();
    expect(screen.queryByTestId("layer-eye-Hydraulic")).toBeTruthy();
    expect(screen.queryByTestId("layer-eye-off-Hydraulic")).toBeNull();
    expect(screen.queryByTestId("layer-eye-ReactorPhysics")).toBeNull();
    expect(screen.queryByTestId("layer-eye-off-ReactorPhysics")).toBeTruthy();
  });
});

describe("LayersPanel — row click toggles", () => {
  it("clicking a row flips its layer; aria-checked reflects new state", async () => {
    const user = userEvent.setup();
    render(<LayersPanel />);
    const row = getRow("Hydraulic");
    expect(row.getAttribute("aria-checked")).toBe("true");
    await user.click(row);
    expect(useStore.getState().activeLayers.Hydraulic).toBe(false);
    expect(getRow("Hydraulic").getAttribute("aria-checked")).toBe("false");
  });

  it("clicking a row twice returns to the original state", async () => {
    const user = userEvent.setup();
    render(<LayersPanel />);
    const row = getRow("Sources");
    await user.click(row);
    expect(useStore.getState().activeLayers.Sources).toBe(false);
    await user.click(row);
    expect(useStore.getState().activeLayers.Sources).toBe(true);
  });

  it("each row toggles only its own LayerKey (no leak)", async () => {
    for (const key of LAYER_KEYS) {
      useStore.setState({
        activeLayers: { ...ALL_LAYERS_ON },
        hideOffLayer: false,
      });
      const user = userEvent.setup();
      const { unmount } = render(<LayersPanel />);
      await user.click(getRow(key));

      const state = useStore.getState().activeLayers;
      for (const k of LAYER_KEYS) {
        expect(state[k]).toBe(k === key ? false : true);
      }
      unmount();
    }
  });
});

// Phase 72 Preferences — the Off-layer Dim/Hide footer toggle was removed
// from LayersPanel and rehomed to `Edit > Preferences > Editor > Off-layer
// behavior`. The store action `setHideOffLayer` is still tested via the
// PreferencesDialog + the preferences bridge; the panel no longer owns the
// surface.

describe("LayersPanel — accessibility", () => {
  it("each row carries role='switch' + aria-checked + descriptive aria-label", () => {
    render(<LayersPanel />);
    for (const key of LAYER_KEYS) {
      const row = getRow(key);
      expect(row.getAttribute("role")).toBe("switch");
      expect(["true", "false"]).toContain(row.getAttribute("aria-checked"));
      expect(row.getAttribute("aria-label")).toMatch(/layer/);
    }
  });
});
