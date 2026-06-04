// @vitest-environment happy-dom
import { describe, it, expect, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import FunctionSelect from "../FunctionSelect";
import type { Parameter, FactoryCorrelationValue } from "../../../registry/types";

// Minimal HTC correlation parameter — mirrors components.json structure
const htcParam: Parameter = {
  name: "htc_correlation",
  type: "Function",
  default: "dittus_boelter",
  description: "HTC correlation closure (Re, Pr, T_bulk, T_wall) -> Nu",
  required: false,
  positional: false,
  options: [
    { value: "dittus_boelter", label: "Dittus-Boelter", kind: "simple" },
    { value: "constant_Nusselt", label: "Constant Nusselt", kind: "simple" },
    {
      value: "regime_dependent",
      label: "Regime Dependent",
      kind: "factory",
      sub_parameters: [
        {
          name: "htc_forced",
          type: "Function",
          description: "HTC closure for forced convection regime",
          required: true,
          positional: false,
          options: [
            { value: "dittus_boelter", label: "Dittus-Boelter", kind: "simple" },
            { value: "constant_Nusselt", label: "Constant Nusselt", kind: "simple" },
            { value: "elenbaas_htc", label: "Elenbaas", kind: "factory", sub_parameters: [
              { name: "b", type: "Real", unit: "m", description: "Channel gap width", required: true, positional: false },
              { name: "L", type: "Real", unit: "m", description: "Channel length", required: true, positional: false },
              { name: "Dh", type: "Real", unit: "m", description: "Hydraulic diameter", required: true, positional: false },
              { name: "g", type: "Real", unit: "m/s^2", default: 9.80665, description: "Gravitational acceleration", required: false, positional: false },
            ]},
          ],
        },
        {
          name: "threshold",
          type: "Real",
          unit: "—",
          default: 1.0,
          description: "Gr/Re² threshold for NC detection",
          required: false,
          positional: false,
        },
      ],
    },
  ],
};

// Simple-only param (friction correlation — no factories)
const frictionParam: Parameter = {
  name: "friction_correlation",
  type: "Function",
  default: "blasius_friction",
  description: "Friction factor correlation closure (Re) -> f",
  required: false,
  positional: false,
  options: [
    { value: "blasius_friction", label: "Blasius", kind: "simple" },
    { value: "laminar_friction_rectangular", label: "Laminar", kind: "simple" },
  ],
};

describe("FunctionSelect", () => {
  it("renders a dropdown with all options", () => {
    render(
      <FunctionSelect param={htcParam} value="dittus_boelter" onChange={vi.fn()} />
    );
    expect(screen.getByText("htc_correlation")).toBeTruthy();
    expect(screen.getByText("Dittus-Boelter")).toBeTruthy();
  });

  it("shows the info icon with tooltip when param has a description", () => {
    render(
      <FunctionSelect param={htcParam} value="dittus_boelter" onChange={vi.fn()} />
    );
    const icons = document.querySelectorAll("svg");
    expect(icons.length).toBeGreaterThan(0);
  });

  it("emits plain string for simple closure selection", async () => {
    const onChange = vi.fn();
    render(
      <FunctionSelect param={htcParam} value="dittus_boelter" onChange={onChange} />
    );
    const trigger = screen.getByRole("combobox");
    await userEvent.click(trigger);
    const option = screen.getByText("Constant Nusselt");
    await userEvent.click(option);
    expect(onChange).toHaveBeenCalledWith("constant_Nusselt");
  });

  it("emits FactoryCorrelationValue when factory option selected", async () => {
    const onChange = vi.fn();
    render(
      <FunctionSelect param={htcParam} value="dittus_boelter" onChange={onChange} />
    );
    const trigger = screen.getByRole("combobox");
    await userEvent.click(trigger);
    const option = screen.getByText("Regime Dependent");
    await userEvent.click(option);
    expect(onChange).toHaveBeenCalledWith({
      kind: "factory",
      value: "regime_dependent",
      subParams: {},
    } satisfies FactoryCorrelationValue);
  });

  it("shows sub-fields when value is a FactoryCorrelationValue", () => {
    const factoryValue: FactoryCorrelationValue = {
      kind: "factory",
      value: "regime_dependent",
      subParams: { htc_forced: "dittus_boelter", threshold: 1.0 },
    };
    render(
      <FunctionSelect param={htcParam} value={factoryValue} onChange={vi.fn()} />
    );
    expect(screen.getByText("htc_forced")).toBeTruthy();
    expect(screen.getByText("threshold")).toBeTruthy();
  });

  it("does NOT show sub-fields for simple selection", () => {
    render(
      <FunctionSelect param={htcParam} value="dittus_boelter" onChange={vi.fn()} />
    );
    expect(screen.queryByText("htc_forced")).toBeNull();
    expect(screen.queryByText("threshold")).toBeNull();
  });

  it("does NOT show sub-fields for friction param (no factories)", () => {
    render(
      <FunctionSelect param={frictionParam} value="blasius_friction" onChange={vi.fn()} />
    );
    const subContainer = document.querySelector("[data-testid='function-subparams']");
    expect(subContainer).toBeNull();
  });

  it("sub-field change merges into FactoryCorrelationValue.subParams", async () => {
    const onChange = vi.fn();
    const factoryValue: FactoryCorrelationValue = {
      kind: "factory",
      value: "regime_dependent",
      subParams: { htc_forced: "dittus_boelter" },
    };
    render(
      <FunctionSelect param={htcParam} value={factoryValue} onChange={onChange} />
    );
    // threshold input renders via NumericField with inputMode="decimal" (not type="number")
    // query by display value: default is 1.0 -> displayed as ""  (no value in subParams), falls back to param.default "1"
    const thresholdInput = screen.getByDisplayValue("1");
    fireEvent.change(thresholdInput, { target: { value: "0.5" } });
    fireEvent.blur(thresholdInput);
    const lastCall = onChange.mock.calls[onChange.mock.calls.length - 1][0] as FactoryCorrelationValue;
    expect(lastCall.kind).toBe("factory");
    expect(lastCall.value).toBe("regime_dependent");
    expect(lastCall.subParams.threshold).toBeCloseTo(0.5);
    expect(lastCall.subParams.htc_forced).toBe("dittus_boelter");
  });

  it("does NOT produce [object Object] in Select trigger for factory value", () => {
    const factoryValue: FactoryCorrelationValue = {
      kind: "factory",
      value: "regime_dependent",
      subParams: {},
    };
    render(
      <FunctionSelect param={htcParam} value={factoryValue} onChange={vi.fn()} />
    );
    // When factory selected, sub-FunctionSelect for htc_forced is also rendered,
    // so there are multiple comboboxes; the first one is the top-level trigger
    const triggers = screen.getAllByRole("combobox");
    const topTrigger = triggers[0];
    expect(topTrigger.textContent).not.toContain("[object Object]");
    expect(topTrigger.textContent).toContain("Regime Dependent");
  });
});
