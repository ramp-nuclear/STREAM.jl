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
});
