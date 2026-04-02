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
  it("renders FunctionSelect for Function-type params", () => {
    const channelWithCorrelation: ComponentDefinition = {
      ...mockChannel,
      parameters: [
        ...mockChannel.parameters,
        {
          name: "htc_correlation",
          type: "Function",
          default: "dittus_boelter",
          description: "HTC correlation",
          required: false,
          positional: false,
          options: [
            { value: "dittus_boelter", label: "Dittus-Boelter", kind: "simple" },
            { value: "constant_Nusselt", label: "Constant Nusselt", kind: "simple" },
          ],
        },
      ],
      constructorModes: [
        {
          mode: "default",
          signature: "Channel(; ...)",
          parameters: ["n", "g", "htc_correlation"],
        },
      ],
    };
    render(
      <ParameterForm
        component={channelWithCorrelation}
        activeMode="default"
        values={{ g: 0.0, htc_correlation: "dittus_boelter" }}
        onParamChange={vi.fn()}
      />
    );
    expect(screen.getByText("htc_correlation")).toBeTruthy();
    expect(screen.getByText("Correlations")).toBeTruthy();
  });
  it.todo("renders MatrixBadge for Matrix-type params");
  it("filters visible params by activeMode", () => {
    const pumpComponent: ComponentDefinition = {
      ...mockChannel,
      id: "Pump",
      constructorModes: [
        { mode: "fixed_dp", signature: "Pump(dP; ...)", parameters: ["n"] },
        { mode: "fixed_mdot", signature: "Pump(mdot0; ...)", parameters: ["g"] },
      ],
    };
    const { rerender } = render(
      <ParameterForm
        component={pumpComponent}
        activeMode="fixed_dp"
        values={{}}
        onParamChange={vi.fn()}
      />
    );
    expect(screen.getByText("n")).toBeTruthy();
    expect(screen.queryByText("g")).toBeNull();

    rerender(
      <ParameterForm
        component={pumpComponent}
        activeMode="fixed_mdot"
        values={{}}
        onParamChange={vi.fn()}
      />
    );
    expect(screen.queryByText("n")).toBeNull();
    expect(screen.getByText("g")).toBeTruthy();
  });
  it.todo(
    "calls onParamChange when a numeric field value is committed on blur"
  );
});
