// @vitest-environment happy-dom
import { describe, it, expect, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import ParameterForm from "../ParameterForm";
import type { ComponentDefinition } from "../../../registry/types";
import { getComponent } from "../../../registry";

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

  it.todo(
    "renders ResourceReferencePicker (resourceKind=geometry) for PipeGeometry-type params (62-08)",
  );
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

// ---------------------------------------------------------------------------
// Plan 63.1-11 — RC-1: type_union parameters must render in Properties.
//
// These tests anchor against the LIVE registry (getComponent) so the contract
// under test is the same Parameter shape ParameterForm consumes in production
// (D-10 type_union + input_modes). They are deliberately RED on the current
// renderField (no `case` for `type_union`).
// ---------------------------------------------------------------------------
describe("ParameterForm — type_union parameters (RC-1)", () => {
  it("renders T_wall mode picker and scalar input when WallTemperature is selected", () => {
    const wt = getComponent("WallTemperature");
    expect(wt).toBeTruthy();
    const onParamChange = vi.fn();
    render(
      <ParameterForm
        component={wt!}
        activeMode="default"
        values={{ n: 4 }}
        onParamChange={onParamChange}
      />
    );
    // Field label
    expect(screen.getByText("T_wall")).toBeTruthy();
    // Mode picker — scalar / vector / callable segmented control
    expect(screen.getByRole("button", { name: /^scalar$/i })).toBeTruthy();
    expect(screen.getByRole("button", { name: /^vector$/i })).toBeTruthy();
    expect(screen.getByRole("button", { name: /^callable$/i })).toBeTruthy();
    // Scalar editor — NumericField textbox is reachable via the visible unit
    // suffix "K"; assert at least one numeric Input rendered in the form.
    const inputs = document.querySelectorAll("input");
    expect(inputs.length).toBeGreaterThan(0);
    // Typing a value and blurring writes through onParamChange("T_wall", 300).
    const scalarInput = inputs[inputs.length - 1] as HTMLInputElement;
    fireEvent.change(scalarInput, { target: { value: "300" } });
    fireEvent.blur(scalarInput);
    expect(onParamChange).toHaveBeenCalledWith("T_wall", 300);
  });

  it("renders q editor when HeatFluxSource is selected (parity with T_wall)", () => {
    const hfs = getComponent("HeatFluxSource");
    expect(hfs).toBeTruthy();
    render(
      <ParameterForm
        component={hfs!}
        activeMode="default"
        values={{ n: 4 }}
        onParamChange={vi.fn()}
      />
    );
    expect(screen.getByText("q")).toBeTruthy();
    expect(screen.getByRole("button", { name: /^scalar$/i })).toBeTruthy();
  });

  it("renders h_left and h_right editors when Channel is selected", () => {
    const ch = getComponent("Channel");
    expect(ch).toBeTruthy();
    render(
      <ParameterForm
        component={ch!}
        activeMode="default"
        values={{ n: 1, geometry: "uuid-stub" }}
        onParamChange={vi.fn()}
      />
    );
    expect(screen.getByText("h_left")).toBeTruthy();
    expect(screen.getByText("h_right")).toBeTruthy();
    // Each type_union param renders its own mode picker → at least 2 scalar buttons.
    const scalarButtons = screen.getAllByRole("button", { name: /^scalar$/i });
    expect(scalarButtons.length).toBeGreaterThanOrEqual(2);
  });

  it("switches to vector mode and emits an array on edit", () => {
    const wt = getComponent("WallTemperature");
    const onParamChange = vi.fn();
    render(
      <ParameterForm
        component={wt!}
        activeMode="default"
        values={{ n: 3 }}
        onParamChange={onParamChange}
      />
    );
    // Click the "vector" mode segment.
    fireEvent.click(screen.getByRole("button", { name: /^vector$/i }));
    // Three numeric cells render in the vector editor.
    const inputs = Array.from(
      document.querySelectorAll("input")
    ) as HTMLInputElement[];
    // The vector editor exposes exactly n cells (n=3 here). Other inputs in the
    // form (n itself) are also present, so we filter by the cell-row pattern:
    // assert at least 3 numeric inputs are present.
    expect(inputs.length).toBeGreaterThanOrEqual(3);
    // Edit cell index 1 to 350 and blur — onChange should fire with an
    // array whose index 1 === 350.
    // Vector cells are the last 3 inputs in document order.
    const cell1 = inputs[inputs.length - 2];
    fireEvent.change(cell1, { target: { value: "350" } });
    fireEvent.blur(cell1);
    expect(onParamChange).toHaveBeenCalled();
    const lastCall = onParamChange.mock.calls.find(
      (c) => c[0] === "T_wall" && Array.isArray(c[1])
    );
    expect(lastCall).toBeTruthy();
    expect((lastCall![1] as number[]).length).toBe(3);
    expect((lastCall![1] as number[])[1]).toBe(350);
  });

  it("switches to callable mode and emits a string signature", () => {
    const wt = getComponent("WallTemperature");
    const onParamChange = vi.fn();
    render(
      <ParameterForm
        component={wt!}
        activeMode="default"
        values={{ n: 4 }}
        onParamChange={onParamChange}
      />
    );
    fireEvent.click(screen.getByRole("button", { name: /^callable$/i }));
    // Signature picker exposes fn(t) and fn(t, i) segmented options.
    const fnT = screen.getByRole("button", { name: /^fn\(t\)$/i });
    const fnTi = screen.getByRole("button", { name: /^fn\(t, i\)$/i });
    expect(fnT).toBeTruthy();
    expect(fnTi).toBeTruthy();
    fireEvent.click(fnTi);
    expect(onParamChange).toHaveBeenCalledWith("T_wall", "fn(t, i)");
  });

  it("infers the active mode from an existing value", () => {
    const wt = getComponent("WallTemperature")!;
    const { rerender, unmount } = render(
      <ParameterForm
        component={wt}
        activeMode="default"
        values={{ n: 4, T_wall: 350 }}
        onParamChange={vi.fn()}
      />
    );
    // scalar mode active when value is a number — the scalar button carries the
    // shadcn "default" variant, but a more robust selector is to assert that
    // the scalar NumericField input currently holds "350".
    const scalarInput = Array.from(
      document.querySelectorAll("input")
    ).find((el) => (el as HTMLInputElement).value === "350");
    expect(scalarInput).toBeTruthy();

    // Re-mount with vector value → vector mode active, 4 cells render.
    unmount();
    rerender(
      <ParameterForm
        component={wt}
        activeMode="default"
        values={{ n: 4, T_wall: [300, 310, 320, 330] }}
        onParamChange={vi.fn()}
      />
    );
    // Look for "310" as a value in some input — proves vector cells rendered
    // with the stored array.
    const cell = Array.from(
      document.querySelectorAll("input")
    ).find((el) => (el as HTMLInputElement).value === "310");
    expect(cell).toBeTruthy();

    // Re-mount with callable value → callable picker showing the chosen sig.
    unmount();
    rerender(
      <ParameterForm
        component={wt}
        activeMode="default"
        values={{ n: 4, T_wall: "fn(t)" }}
        onParamChange={vi.fn()}
      />
    );
    expect(screen.getByRole("button", { name: /^fn\(t\)$/i })).toBeTruthy();
  });
});
