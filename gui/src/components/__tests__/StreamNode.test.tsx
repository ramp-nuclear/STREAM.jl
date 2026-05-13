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
  useStore.setState({
    errorNodeIds: new Set<string>(),
    errorTagsByNodeId: {},
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

  it("renders with category border stripe for Hydraulic component", () => {
    const { container } = renderStreamNode({
      componentId: "Pump",
      instanceName: "pump_1",
      parameters: {},
    });
    const nodeEl = container.firstElementChild as HTMLElement;
    expect(nodeEl?.style.borderLeftColor).toBe("#3b82f6");
  });

  it("renders with category border stripe for Thermal component", () => {
    const { container } = renderStreamNode({
      componentId: "ConstantTemperature",
      instanceName: "ct_1",
      parameters: {},
    });
    const nodeEl = container.firstElementChild as HTMLElement;
    expect(nodeEl?.style.borderLeftColor).toBe("#f59e0b");
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

  it("ThermalPort handles have amber background", () => {
    const { container } = renderStreamNode({
      componentId: "ConstantTemperature",
      instanceName: "ct_1",
      parameters: {},
    });
    const handle = container.querySelector(".react-flow__handle") as HTMLElement;
    expect(handle).toBeTruthy();
    expect(handle.style.background).toContain("#f59e0b");
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

  it("does NOT render BCPort handle on a Channel (Channel has no BCPort port)", () => {
    const { container } = renderStreamNode({
      componentId: "Channel",
      instanceName: "ch_1",
      parameters: {},
    });
    // Channel has FlowPort port_in/port_out only; no BCPort handles allowed.
    const handles = container.querySelectorAll(".react-flow__handle");
    handles.forEach((h) => {
      const el = h as HTMLElement;
      // BCPort would have transparent background — verify none do.
      expect(el.style.background).not.toBe("transparent");
    });
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
// Phase 63 D-22: errorTagsByNodeId-driven red-ring outline
// ---------------------------------------------------------------------------

describe("StreamNode — Phase 63 BC error red-ring (D-22)", () => {
  it("applies red-ring outline when errorTagsByNodeId contains a tag (D-22)", () => {
    useStore.setState({
      errorTagsByNodeId: { "wt_red": ["bc-n-mismatch"] },
    });
    const { container } = renderStreamNode(
      { componentId: "WallTemperature", instanceName: "wt_1", parameters: { n: 10, T_wall: 320 } },
      { id: "wt_red" },
    );
    const nodeEl = container.firstElementChild as HTMLElement;
    expect(nodeEl.className).toMatch(/ring-destructive/);
  });

  it("does NOT apply red-ring when errorTagsByNodeId is empty for that node", () => {
    useStore.setState({
      errorTagsByNodeId: {},
      errorNodeIds: new Set<string>(),
    });
    const { container } = renderStreamNode(
      { componentId: "WallTemperature", instanceName: "wt_1", parameters: { n: 10, T_wall: 320 } },
      { id: "wt_clean" },
    );
    const nodeEl = container.firstElementChild as HTMLElement;
    expect(nodeEl.className).not.toMatch(/ring-destructive/);
  });
});
