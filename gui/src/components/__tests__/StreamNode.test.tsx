// @vitest-environment happy-dom
import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { ReactFlowProvider } from "@xyflow/react";
import StreamNode from "../StreamNode";

function renderStreamNode(data: {
  componentId: string;
  instanceName: string;
  parameters: Record<string, unknown>;
}) {
  return render(
    <ReactFlowProvider>
      <StreamNode
        id="test-node"
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
    // Pump has inlet and outlet FlowPorts
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
    // 2 FlowPort (inlet, outlet) + 2 ThermalPort (thermal_left, thermal_right)
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
