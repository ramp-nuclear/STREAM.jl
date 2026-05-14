// @vitest-environment happy-dom
import { describe, it, expect, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import ParameterForm from "../ParameterForm";
import type { ComponentDefinition } from "../../../registry/types";
import { getComponent } from "../../../registry";
import { TooltipProvider } from "../../ui/tooltip";
import { isSourceValueEntry } from "../../../lib/sourceValueEntry";

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
// Per project-feedback (heavy-dev, 2026-05-14), the GUI exposes ONLY a scalar
// editor for type_union params. Vector and callable values belong in the
// generated Julia script — per-cell editors in a sidebar are unusable at
// realistic n. These tests anchor against the LIVE registry so the contract
// under test is the same Parameter shape ParameterForm consumes in production
// (D-10 type_union + input_modes).
// ---------------------------------------------------------------------------
describe("ParameterForm — type_union parameters (RC-1, scalar-only)", () => {
  it("renders T_wall as a scalar input when WallTemperature is selected", () => {
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
    expect(screen.getByText("T_wall")).toBeTruthy();
    // No mode picker — scalar / vector / callable buttons must NOT exist.
    expect(screen.queryByRole("button", { name: /^scalar$/i })).toBeNull();
    expect(screen.queryByRole("button", { name: /^vector$/i })).toBeNull();
    expect(screen.queryByRole("button", { name: /^callable$/i })).toBeNull();
    // Script-only hint is present.
    expect(
      screen.getByText(/edit in the generated julia/i)
    ).toBeTruthy();
    // Typing 300 + blur writes through onParamChange("T_wall", 300).
    const inputs = document.querySelectorAll("input");
    const scalarInput = inputs[inputs.length - 1] as HTMLInputElement;
    fireEvent.change(scalarInput, { target: { value: "300" } });
    fireEvent.blur(scalarInput);
    expect(onParamChange).toHaveBeenCalledWith("T_wall", 300);
  });

  it("renders q as a scalar input when HeatFluxSource is selected", () => {
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
    expect(screen.queryByRole("button", { name: /^scalar$/i })).toBeNull();
    expect(screen.queryByRole("button", { name: /^vector$/i })).toBeNull();
  });

  it("renders h_left and h_right scalar inputs when Channel is selected", () => {
    const ch = getComponent("Channel");
    expect(ch).toBeTruthy();
    // Channel.geometry uses ResourceReferencePicker which renders <Tooltip>
    // without its own TooltipProvider — production wraps the whole App in one
    // (App.tsx:217). Mirror that here so the picker mounts cleanly.
    render(
      <TooltipProvider>
        <ParameterForm
          component={ch!}
          activeMode="default"
          values={{ n: 1, geometry: "uuid-stub" }}
          onParamChange={vi.fn()}
        />
      </TooltipProvider>
    );
    expect(screen.getByText("h_left")).toBeTruthy();
    expect(screen.getByText("h_right")).toBeTruthy();
    // No vector / callable controls anywhere.
    expect(screen.queryByRole("button", { name: /^vector$/i })).toBeNull();
    expect(screen.queryByRole("button", { name: /^callable$/i })).toBeNull();
  });

  it("displays an existing scalar value in the input", () => {
    const wt = getComponent("WallTemperature")!;
    render(
      <ParameterForm
        component={wt}
        activeMode="default"
        values={{ n: 4, T_wall: 350 }}
        onParamChange={vi.fn()}
      />
    );
    const filled = Array.from(
      document.querySelectorAll("input")
    ).find((el) => (el as HTMLInputElement).value === "350");
    expect(filled).toBeTruthy();
  });

  it("overwrites a stored non-scalar value with the typed scalar on edit", () => {
    const wt = getComponent("WallTemperature")!;
    const onParamChange = vi.fn();
    // Stored value is an array — heavy-dev project file with a pre-existing
    // vector value. UI must show an empty scalar input (per "always overwrite"
    // contract) and the first edit must write a scalar number, not an array.
    render(
      <ParameterForm
        component={wt}
        activeMode="default"
        values={{ n: 3, T_wall: [300, 310, 320] }}
        onParamChange={onParamChange}
      />
    );
    // No per-cell editor exists — no input should carry "310".
    const arrayCell = Array.from(
      document.querySelectorAll("input")
    ).find((el) => (el as HTMLInputElement).value === "310");
    expect(arrayCell).toBeFalsy();
    // Edit + blur the scalar input → emits a number.
    const inputs = document.querySelectorAll("input");
    const scalarInput = inputs[inputs.length - 1] as HTMLInputElement;
    fireEvent.change(scalarInput, { target: { value: "295" } });
    fireEvent.blur(scalarInput);
    expect(onParamChange).toHaveBeenCalledWith("T_wall", 295);
  });
});

// ---------------------------------------------------------------------------
// Plan 14, GAP-RC-4: Mode dropdown for Sources-category type_union params.
//
// These tests anchor against the LIVE registry for WallTemperature / HFS /
// Channel. They are RED until Task 3 (GREEN) extends TypeUnionField with the
// 3-option Mode dropdown gated on component.category === "Sources".
// ---------------------------------------------------------------------------
describe("ParameterForm — type_union mode dropdown (Plan 14, GAP-RC-4)", () => {
  it("WallTemperature renders the Mode dropdown with exactly Value/Profile/Function options", () => {
    const wt = getComponent("WallTemperature")!;
    render(
      <TooltipProvider>
        <ParameterForm
          component={wt}
          activeMode="default"
          values={{ n: 4, T_wall: { mode: "value", value: 300 } }}
          onParamChange={vi.fn()}
        />
      </TooltipProvider>
    );
    // The shadcn SelectTrigger renders as role="combobox".
    const combobox = screen.getByRole("combobox");
    expect(combobox).toBeTruthy();
    // Open the dropdown.
    fireEvent.click(combobox);
    expect(screen.getByRole("option", { name: "Value" })).toBeTruthy();
    expect(screen.getByRole("option", { name: "Profile" })).toBeTruthy();
    expect(screen.getByRole("option", { name: "Function" })).toBeTruthy();
    // Mark and Source must NOT be present.
    expect(screen.queryByRole("option", { name: "Mark" })).toBeNull();
    expect(screen.queryByRole("option", { name: "Source" })).toBeNull();
  });

  it("HeatFluxSource renders the Mode dropdown above the q editor", () => {
    const hfs = getComponent("HeatFluxSource")!;
    render(
      <TooltipProvider>
        <ParameterForm
          component={hfs}
          activeMode="default"
          values={{ n: 4, q: { mode: "value", value: 0 } }}
          onParamChange={vi.fn()}
        />
      </TooltipProvider>
    );
    const combobox = screen.getByRole("combobox");
    expect(combobox).toBeTruthy();
    fireEvent.click(combobox);
    expect(screen.getByRole("option", { name: "Value" })).toBeTruthy();
    expect(screen.getByRole("option", { name: "Profile" })).toBeTruthy();
    expect(screen.getByRole("option", { name: "Function" })).toBeTruthy();
    expect(screen.queryByRole("option", { name: "Mark" })).toBeNull();
    expect(screen.queryByRole("option", { name: "Source" })).toBeNull();
  });

  it("Channel does NOT render a Mode dropdown for h_left/h_right (regression guard)", () => {
    const ch = getComponent("Channel")!;
    render(
      <TooltipProvider>
        <ParameterForm
          component={ch}
          activeMode="default"
          values={{ n: 1, geometry: "uuid-stub" }}
          onParamChange={vi.fn()}
        />
      </TooltipProvider>
    );
    // No combobox (Mode dropdown) should appear for Channel.h_left/h_right.
    expect(screen.queryByRole("combobox")).toBeNull();
    // Plan 11 scalar-only hint preserved.
    expect(
      screen.getByText(/edit in the generated julia/i)
    ).toBeTruthy();
  });

  it("switching Mode from Value to Profile dispatches a profile-cosine SourceValueEntry", () => {
    const wt = getComponent("WallTemperature")!;
    const onParamChange = vi.fn();
    const { rerender } = render(
      <TooltipProvider>
        <ParameterForm
          component={wt}
          activeMode="default"
          values={{ n: 4, T_wall: { mode: "value", value: 300 } }}
          onParamChange={onParamChange}
        />
      </TooltipProvider>
    );
    // Open the Mode dropdown and pick Profile.
    const combobox = screen.getByRole("combobox");
    fireEvent.click(combobox);
    fireEvent.click(screen.getByRole("option", { name: "Profile" }));
    // Verify the dispatched value is a profile-cosine SourceValueEntry.
    expect(onParamChange).toHaveBeenCalledWith(
      "T_wall",
      { mode: "profile", preset: "cosine", amplitude: 1.0, peakingFactor: 1.0 }
    );
    // Re-render with the new value; the ProfileModeEditor (Cosine/File seg control) should appear.
    rerender(
      <TooltipProvider>
        <ParameterForm
          component={wt}
          activeMode="default"
          values={{ n: 4, T_wall: { mode: "profile", preset: "cosine", amplitude: 1.0, peakingFactor: 1.0 } }}
          onParamChange={onParamChange}
        />
      </TooltipProvider>
    );
    expect(screen.getByText("Cosine")).toBeTruthy();
  });

  it("switching Mode from Value to Function dispatches a function SourceValueEntry", () => {
    const wt = getComponent("WallTemperature")!;
    const onParamChange = vi.fn();
    const { rerender } = render(
      <TooltipProvider>
        <ParameterForm
          component={wt}
          activeMode="default"
          values={{ n: 4, T_wall: { mode: "value", value: 300 } }}
          onParamChange={onParamChange}
        />
      </TooltipProvider>
    );
    const combobox = screen.getByRole("combobox");
    fireEvent.click(combobox);
    fireEvent.click(screen.getByRole("option", { name: "Function" }));
    expect(onParamChange).toHaveBeenCalledWith(
      "T_wall",
      { mode: "function", signature: "fn(t)", functionName: "" }
    );
    rerender(
      <TooltipProvider>
        <ParameterForm
          component={wt}
          activeMode="default"
          values={{ n: 4, T_wall: { mode: "function", signature: "fn(t)", functionName: "" } }}
          onParamChange={onParamChange}
        />
      </TooltipProvider>
    );
    // FunctionModeEditor body shows fn(t) / fn(t, i) segmented control.
    expect(screen.getByText("fn(t)")).toBeTruthy();
  });

  it("bare-number legacy T_wall renders as Value mode with the numeric value", () => {
    const wt = getComponent("WallTemperature")!;
    render(
      <TooltipProvider>
        <ParameterForm
          component={wt}
          activeMode="default"
          values={{ n: 4, T_wall: 300 }}
          onParamChange={vi.fn()}
        />
      </TooltipProvider>
    );
    // Mode dropdown should show "Value" (or its default).
    const combobox = screen.getByRole("combobox");
    expect(combobox).toBeTruthy();
    // The scalar input should display "300".
    const input = Array.from(document.querySelectorAll("input")).find(
      (el) => el.value === "300"
    );
    expect(input).toBeTruthy();
  });

  it("editing scalar value in Value mode dispatches SourceValueEntry (not bare number)", () => {
    const wt = getComponent("WallTemperature")!;
    const onParamChange = vi.fn();
    render(
      <TooltipProvider>
        <ParameterForm
          component={wt}
          activeMode="default"
          values={{ n: 4, T_wall: { mode: "value", value: 300 } }}
          onParamChange={onParamChange}
        />
      </TooltipProvider>
    );
    const inputs = document.querySelectorAll("input");
    const scalarInput = inputs[inputs.length - 1] as HTMLInputElement;
    fireEvent.change(scalarInput, { target: { value: "350" } });
    fireEvent.blur(scalarInput);
    const lastCall = onParamChange.mock.calls[onParamChange.mock.calls.length - 1];
    expect(lastCall[0]).toBe("T_wall");
    expect(isSourceValueEntry(lastCall[1])).toBe(true);
    expect(lastCall[1]).toEqual({ mode: "value", value: 350 });
  });
});
