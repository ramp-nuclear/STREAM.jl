// @vitest-environment happy-dom
import { describe, it, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import ParameterForm from "../ParameterForm";
import type { ComponentDefinition } from "../../../registry/types";

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
    {
      name: "g",
      type: "Real",
      unit: "m/s^2",
      default: 0.0,
      description: "Gravity",
      required: false,
      positional: false,
    },
  ],
  constructorModes: [
    { mode: "default", signature: "Channel(; ...)", parameters: ["n", "g"] },
  ],
};

describe("ParameterForm", () => {
  it("renders field renderers for a mock Channel component", () => {
    render(
      <ParameterForm
        component={mockChannel}
        activeMode="default"
        values={{ g: 0.0 }}
        onParamChange={vi.fn()}
      />
    );
    expect(screen.getByText("n")).toBeTruthy();
    expect(screen.getByText("g")).toBeTruthy();
  });

  it.todo("renders PipeGeometryPicker for PipeGeometry-type params");
  it.todo("renders FunctionSelect for Function-type params");
  it.todo("renders MatrixBadge for Matrix-type params");
  it.todo("filters visible params by activeMode");
  it.todo(
    "calls onParamChange when a numeric field value is committed on blur"
  );
});
