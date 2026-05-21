// @vitest-environment happy-dom
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";
import { ReactFlowProvider } from "@xyflow/react";
import StreamNode from "../StreamNode";
import useStore from "../../store/useStore";

function renderStreamNode(data: {
  componentId: string;
  instanceName: string;
  parameters: Record<string, unknown>;
}, opts: { id?: string } = {}) {
  const id = opts.id ?? "test-node";
  return render(
    <ReactFlowProvider>
      <StreamNode
        id={id}
        data={data as unknown as Record<string, unknown>}
        selected={false}
        type="streamNode"
        isConnectable={true}
        positionAbsoluteX={0}
        positionAbsoluteY={0}
        zIndex={0}
        dragging={false}
        draggable={true}
        deletable={true}
        selectable={true}
        parentId={undefined}
        dragHandle={undefined}
        sourcePosition={undefined}
        targetPosition={undefined}
      />
    </ReactFlowProvider>,
  );
}

beforeEach(() => {
  // Reset the BC-relevant slices so error-ring tests start clean.
  // Phase 63.1 D-15: errorTagsByNodeId removed; ring state now derives from
  // selectNodeErrors over nodes + bcMode.
  useStore.setState({
    errorNodeIds: new Set<string>(),
    nodes: [],
    bcMode: {},
    bcSymmetric: {},
  });
});

afterEach(() => {
  cleanup();
});

describe("StreamNode", () => {
  it("renders component type label", () => {
    renderStreamNode({
      componentId: "Pump",
      instanceName: "pump_1",
      parameters: {},
    });
    expect(screen.getByText("Pump")).toBeTruthy();
  });

  it("renders instance name", () => {
    renderStreamNode({
      componentId: "Pump",
      instanceName: "pump_1",
      parameters: {},
    });
    expect(screen.getByText("pump_1")).toBeTruthy();
  });

  it("renders FlowPort handles", () => {
    const { container } = renderStreamNode({
      componentId: "Pump",
      instanceName: "pump_1",
      parameters: {},
    });
    // Pump has port_in and port_out FlowPorts
    const handles = container.querySelectorAll(".react-flow__handle");
    expect(handles.length).toBe(2);
  });

  it("renders leading-band for Hydraulic component (Phase 72 D-canvas — replaces border-left stripe)", () => {
    const { container } = renderStreamNode({
      componentId: "Pump",
      instanceName: "pump_1",
      parameters: {},
    });
    const band = container.querySelector('[data-testid="stream-node-band"]');
    expect(band).toBeTruthy();
    // Solid single-layer band: one child div with the Hydraulic layer var.
    const segments = band!.querySelectorAll("[data-layer]");
    expect(segments.length).toBe(1);
    expect(segments[0].getAttribute("data-layer")).toBe("Hydraulic");
    expect((segments[0] as HTMLElement).style.backgroundColor).toBe(
      "var(--color-layer-hydraulic)",
    );
  });

  it("renders leading-band for Thermal component (Phase 72 D-canvas)", () => {
    const { container } = renderStreamNode({
      componentId: "ConstantTemperature",
      instanceName: "ct_1",
      parameters: {},
    });
    const band = container.querySelector('[data-testid="stream-node-band"]');
    expect(band).toBeTruthy();
    const segments = band!.querySelectorAll("[data-layer]");
    expect(segments.length).toBe(1);
    expect(segments[0].getAttribute("data-layer")).toBe("Thermal");
    expect((segments[0] as HTMLElement).style.backgroundColor).toBe(
      "var(--color-layer-thermal)",
    );
  });

  it("renders split leading-band for dual-layer ChannelAndContacts (Phase 72 D-canvas)", () => {
    const { container } = renderStreamNode({
      componentId: "ChannelAndContacts",
      instanceName: "cac_1",
      parameters: {},
    });
    const band = container.querySelector('[data-testid="stream-node-band"]');
    expect(band).toBeTruthy();
    const segments = band!.querySelectorAll("[data-layer]");
    expect(segments.length).toBe(2);
    const layerKeys = Array.from(segments).map((s) => s.getAttribute("data-layer"));
    expect(layerKeys).toContain("Hydraulic");
    expect(layerKeys).toContain("Thermal");
  });

  it("renders an SVG icon element", () => {
    const { container } = renderStreamNode({
      componentId: "Pump",
      instanceName: "pump_1",
      parameters: {},
    });
    const svg = container.querySelector("svg");
    expect(svg).toBeTruthy();
  });

  it("ChannelAndContacts renders ThermalPort handles", () => {
    const { container } = renderStreamNode({
      componentId: "ChannelAndContacts",
      instanceName: "cac_1",
      parameters: {},
    });
    const handles = container.querySelectorAll(".react-flow__handle");
    // 2 FlowPort (port_in, port_out) + 2 ThermalPort (thermal_left, thermal_right)
    expect(handles.length).toBe(4);
  });

  it("HeatDiffusion renders ThermalPort handles only", () => {
    const { container } = renderStreamNode({
      componentId: "HeatDiffusion",
      instanceName: "hd_1",
      parameters: {},
    });
    const handles = container.querySelectorAll(".react-flow__handle");
    // 2 ThermalPort handles (thermal_left, thermal_right), no FlowPorts
    expect(handles.length).toBe(2);
  });

  it("ConstantTemperature renders single ThermalPort handle", () => {
    const { container } = renderStreamNode({
      componentId: "ConstantTemperature",
      instanceName: "ct_1",
      parameters: {},
    });
    const handles = container.querySelectorAll(".react-flow__handle");
    expect(handles.length).toBe(1);
  });

  it("ThermalPort handles consume the Thermal layer var (Phase 72 — tokenized from #f59e0b)", () => {
    const { container } = renderStreamNode({
      componentId: "ConstantTemperature",
      instanceName: "ct_1",
      parameters: {},
    });
    const handle = container.querySelector(".react-flow__handle") as HTMLElement;
    expect(handle).toBeTruthy();
    // CSSOM may discard var() values from the `background` shorthand depending
    // on environment; verify both the property (best-effort) AND the raw
    // style-attribute string (definitive).
    const raw = handle.getAttribute("style") ?? "";
    expect(raw).toContain("--color-layer-thermal");
  });

  it("ThermalPort handles have diamond rotation", () => {
    const { container } = renderStreamNode({
      componentId: "ConstantTemperature",
      instanceName: "ct_1",
      parameters: {},
    });
    const handle = container.querySelector(".react-flow__handle") as HTMLElement;
    expect(handle).toBeTruthy();
    expect(handle.style.transform).toContain("rotate(45deg)");
  });
});

// ---------------------------------------------------------------------------
// Phase 63 D-18: BCPort hollow-square handle
// ---------------------------------------------------------------------------

describe("StreamNode — Phase 63 BCPort handle (D-18)", () => {
  it("renders BCPort hollow-square handle on WallTemperature (D-18)", () => {
    const { container } = renderStreamNode({
      componentId: "WallTemperature",
      instanceName: "wt_1",
      parameters: { n: 10, T_wall: 320 },
    });
    const handles = container.querySelectorAll(".react-flow__handle");
    // Exactly one handle — the T_wall_out BCPort.
    expect(handles.length).toBe(1);
    const handle = handles[0] as HTMLElement;
    expect(handle.style.background).toBe("transparent");
    // CSSOM may discard the `var()` color from the `border` shorthand, so we
    // check the width/style portion here and verify the var() reference made
    // it into the inline `style` attribute string.
    expect(handle.style.border).toContain("1.5px");
    expect(handle.getAttribute("style") ?? "").toContain("--muted-foreground");
    expect(handle.style.borderRadius).toBe("0px");
  });

  it("renders BCPort hollow-square handle on HeatFluxSource (D-18)", () => {
    const { container } = renderStreamNode({
      componentId: "HeatFluxSource",
      instanceName: "hfs_1",
      parameters: { n: 10, q: 100000 },
    });
    const handles = container.querySelectorAll(".react-flow__handle");
    expect(handles.length).toBe(1);
    const handle = handles[0] as HTMLElement;
    expect(handle.style.background).toBe("transparent");
    expect(handle.style.borderRadius).toBe("0px");
  });

  // Plan 63.1-12 RC-2: Channel + ChannelHeatFlux now declare a BCPort TARGET
  // handle on the bottom edge (T_wall_left / q_left). The pre-Plan-12 negative
  // test ("Channel has no BCPort port") is intentionally retired here under
  // Rule 3 auto-fix; the new contract is enforced by registry.test.ts (BCPort
  // allowed on Sources OR Hydraulic) and the positive tests below.
  it("renders BCPort target handle on a Channel (RC-2, bottom edge)", () => {
    const { container } = renderStreamNode({
      componentId: "Channel",
      instanceName: "ch_1",
      parameters: { n: 4 },
    });
    const handles = Array.from(
      container.querySelectorAll(".react-flow__handle"),
    ) as HTMLElement[];
    // The T_wall_left BCPort handle has data-handleid="T_wall_left".
    const tWallTarget = handles.find(
      (h) => h.getAttribute("data-handleid") === "T_wall_left",
    );
    expect(tWallTarget).toBeDefined();
    expect(tWallTarget!.getAttribute("data-handlepos")).toBe("bottom");
    // type='target' on a consumer; ReactFlow encodes type on the className.
    expect(tWallTarget!.className).toContain("target");
    // Same hollow-square visual as the source-side BCPort.
    expect(tWallTarget!.style.background).toBe("transparent");
    expect(tWallTarget!.style.borderRadius).toBe("0px");
  });

  it("renders BCPort target handle on a ChannelHeatFlux (RC-2, bottom edge)", () => {
    const { container } = renderStreamNode({
      componentId: "ChannelHeatFlux",
      instanceName: "chf_1",
      parameters: { n: 4 },
    });
    const handles = Array.from(
      container.querySelectorAll(".react-flow__handle"),
    ) as HTMLElement[];
    const qTarget = handles.find(
      (h) => h.getAttribute("data-handleid") === "q_left",
    );
    expect(qTarget).toBeDefined();
    expect(qTarget!.getAttribute("data-handlepos")).toBe("bottom");
    expect(qTarget!.className).toContain("target");
  });

  it("renders BCPort handle as source on WallTemperature (category=Sources)", () => {
    const { container } = renderStreamNode({
      componentId: "WallTemperature",
      instanceName: "wt_1",
      parameters: { n: 10, T_wall: 320 },
    });
    const handles = Array.from(
      container.querySelectorAll(".react-flow__handle"),
    ) as HTMLElement[];
    const tOut = handles.find(
      (h) => h.getAttribute("data-handleid") === "T_wall_out",
    );
    expect(tOut).toBeDefined();
    expect(tOut!.className).toContain("source");
  });

  it("does NOT render the legacy 'Connect BC' decoy overlay (Plan 12 cleanup)", () => {
    const { container } = renderStreamNode({
      componentId: "Channel",
      instanceName: "ch_1",
      parameters: { n: 4 },
    });
    expect(container.textContent ?? "").not.toContain("Connect BC");
  });
});

// ---------------------------------------------------------------------------
// Phase 63 D-19: Source-block two-line label
// ---------------------------------------------------------------------------

describe("StreamNode — Phase 63 source-block label (D-19)", () => {
  it("renders source-block label 'T_wall = 320 K' when T_wall is a scalar (D-19)", () => {
    renderStreamNode({
      componentId: "WallTemperature",
      instanceName: "wt_1",
      parameters: { n: 10, T_wall: 320 },
    });
    const label = screen.getByTestId("source-block-label");
    expect(label.textContent).toMatch(/T_wall\s*=\s*320/);
    expect(label.textContent).toContain("K");
  });

  it("renders source-block label 'T_wall = vector (n=10)' when T_wall is an array (D-19)", () => {
    renderStreamNode({
      componentId: "WallTemperature",
      instanceName: "wt_1",
      parameters: { n: 10, T_wall: [320, 325, 330, 335, 340, 345, 350, 355, 360, 365] },
    });
    const label = screen.getByTestId("source-block-label");
    expect(label.textContent).toBe("T_wall = vector (n=10)");
  });

  it("renders source-block label 'T_wall = fn(t)' when T_wall is a function-typed value (D-19)", () => {
    renderStreamNode({
      componentId: "WallTemperature",
      instanceName: "wt_1",
      parameters: { n: 10, T_wall: "my_T_wall_fn" },
    });
    const label = screen.getByTestId("source-block-label");
    expect(label.textContent).toBe("T_wall = fn(t)");
  });

  it("renders source-block label 'T_wall = (unset)' in muted-destructive when T_wall is unset (D-19)", () => {
    renderStreamNode({
      componentId: "WallTemperature",
      instanceName: "wt_1",
      parameters: { n: 10 }, // T_wall absent
    });
    const label = screen.getByTestId("source-block-label");
    expect(label.textContent).toBe("T_wall = (unset)");
    expect(label.className).toContain("text-destructive");
  });

  it("renders source-block label 'q = ...' for HeatFluxSource (D-19)", () => {
    renderStreamNode({
      componentId: "HeatFluxSource",
      instanceName: "hfs_1",
      parameters: { n: 10, q: 100000 },
    });
    const label = screen.getByTestId("source-block-label");
    expect(label.textContent).toMatch(/q\s*=\s*100000/);
    expect(label.textContent).toContain("W/m^2");
  });

  it("does NOT render source-block label on non-source components (e.g., Pump)", () => {
    renderStreamNode({
      componentId: "Pump",
      instanceName: "pump_1",
      parameters: {},
    });
    expect(screen.queryByTestId("source-block-label")).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// Plan 63.1-14 GAP-RC-4: sourceLabelLine reads SourceValueEntry shapes
// ---------------------------------------------------------------------------

describe("StreamNode — Plan 14 sourceLabelLine SourceValueEntry (GAP-RC-4)", () => {
  it("renders 'T_wall = 300 K' for value-mode SourceValueEntry", () => {
    renderStreamNode({
      componentId: "WallTemperature",
      instanceName: "wt_1",
      parameters: { n: 4, T_wall: { mode: "value", value: 300 } },
    });
    const label = screen.getByTestId("source-block-label");
    expect(label.textContent).toMatch(/T_wall\s*=\s*300/);
    expect(label.textContent).toContain("K");
  });

  it("renders 'T_wall = profile (cosine)' for profile-cosine SourceValueEntry", () => {
    renderStreamNode({
      componentId: "WallTemperature",
      instanceName: "wt_1",
      parameters: {
        n: 4,
        T_wall: { mode: "profile", preset: "cosine", amplitude: 1.0, peakingFactor: 1.0 },
      },
    });
    const label = screen.getByTestId("source-block-label");
    expect(label.textContent).toMatch(/T_wall\s*=\s*profile.*cosine/i);
  });

  it("renders 'T_wall = profile (file)' for profile-file SourceValueEntry", () => {
    renderStreamNode({
      componentId: "WallTemperature",
      instanceName: "wt_1",
      parameters: {
        n: 4,
        T_wall: { mode: "profile", preset: "file", path: "/data/twall.csv" },
      },
    });
    const label = screen.getByTestId("source-block-label");
    expect(label.textContent).toMatch(/T_wall\s*=\s*profile.*file/i);
  });

  it("renders 'T_wall = fn(t)' for function SourceValueEntry", () => {
    renderStreamNode({
      componentId: "WallTemperature",
      instanceName: "wt_1",
      parameters: {
        n: 4,
        T_wall: { mode: "function", signature: "fn(t)", functionName: "my_fn" },
      },
    });
    const label = screen.getByTestId("source-block-label");
    expect(label.textContent).toBe("T_wall = fn(t)");
  });

  it("renders 'q = 1e5 W/m^2' for value-mode HFS SourceValueEntry", () => {
    renderStreamNode({
      componentId: "HeatFluxSource",
      instanceName: "hfs_1",
      parameters: { n: 4, q: { mode: "value", value: 100000 } },
    });
    const label = screen.getByTestId("source-block-label");
    expect(label.textContent).toMatch(/q\s*=\s*100000/);
    expect(label.textContent).toContain("W/m^2");
  });
});

// ---------------------------------------------------------------------------
// Phase 63 D-22: errorTagsByNodeId-driven red-ring outline
// ---------------------------------------------------------------------------

describe("StreamNode — BC error persistent outline (D-22 via errorNodeIds, Phase 71 D-20, Phase 72 simplification)", () => {
  it("applies persistent destructive outline when errorNodeIds contains the node id (D-22)", () => {
    // Phase 71 D-20: hasBCError removed; red-ring now derives solely from
    // errorNodeIds which is populated by nMatch via initValidation.
    // Phase 72: simplified from `outline-2 outline-offset-1 ring-2 ring-destructive`
    // (double-outline-plus-ring) to a single outline-2 destructive.
    // Phase 72 P11: outline moved from Tailwind className to inline style
    // (CSS-pipeline workaround); assertion now reads element.style.outline
    // instead of className.
    useStore.setState({
      errorNodeIds: new Set<string>(["wt_red"]),
    });
    const { container } = renderStreamNode(
      { componentId: "WallTemperature", instanceName: "wt_1", parameters: { n: 10, T_wall: 320 } },
      { id: "wt_red" },
    );
    const nodeEl = container.firstElementChild as HTMLElement;
    expect(nodeEl.style.outline).toMatch(/var\(--destructive\)/);
  });

  it("does NOT apply the destructive outline when errorNodeIds does not contain the node id", () => {
    useStore.setState({
      nodes: [],
      bcMode: {},
      errorNodeIds: new Set<string>(),
    });
    const { container } = renderStreamNode(
      { componentId: "WallTemperature", instanceName: "wt_1", parameters: { n: 10, T_wall: 320 } },
      { id: "wt_clean" },
    );
    const nodeEl = container.firstElementChild as HTMLElement;
    expect(nodeEl.style.outline).not.toMatch(/var\(--destructive\)/);
  });
});
