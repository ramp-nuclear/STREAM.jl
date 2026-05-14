// @vitest-environment happy-dom
//
// Phase 65 Plan 65-02 — Reset-to-empty rule tests (§3.5, D-14 "spec verbatim").
//
// Fixtures A–E cover the three-branch blank-on-blur rule implemented in Task 1
// (NumericField + ParameterForm.ScalarInput) and Task 2 (BCsTabForm ValueModeEditor).
//
// Fixture A: Real param with default=5.0, required=false
//   → clear + blur → resets to 5.0 (onChange called with 5.0)
// Fixture B: Real param with default=null, required=true
//   → clear + blur → destructive border (error); onChange NOT called with a value
// Fixture C: Real param with default=null, required=false
//   → clear + blur → onChange(undefined) called; no error
// Fixture D: TypeUnionField for WT.T_wall (Sources, default=300.0)
//   → clear + blur → resets to 300 (SourceValueEntry {mode:"value",value:300})
// Fixture E: BCsTabForm ValueModeEditor for WallTemperature entry with value=300.0
//   → clear + blur → onChange re-called with 300

import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, fireEvent } from "@testing-library/react";
import NumericField from "../NumericField";
import ParameterForm from "../ParameterForm";
import BCsTabForm from "../BCsTabForm";
import { TooltipProvider } from "../../ui/tooltip";
import useStore, { type StreamNodeData } from "../../../store/useStore";
import type { Node } from "@xyflow/react";
import type { ComponentDefinition, Parameter } from "../../../registry/types";

// ---------------------------------------------------------------------------
// Fixture A: Real param, default=5.0, required=false
// ---------------------------------------------------------------------------

const paramA: Parameter = {
  name: "L",
  type: "Real",
  unit: "m",
  default: 5.0,
  required: false,
  positional: false,
  description: "Length",
};

describe("Fixture A — Real param, default=5.0, required=false", () => {
  it("clear-then-blur resets the field to the registry default (5.0)", () => {
    const onChange = vi.fn();
    render(
      <TooltipProvider>
        <NumericField param={paramA} value={12} onChange={onChange} />
      </TooltipProvider>
    );

    // The input should show "12" initially (value prop overrides default).
    const input = document.querySelector("input") as HTMLInputElement;
    expect(input.value).toBe("12");

    // Clear the input and blur.
    fireEvent.change(input, { target: { value: "" } });
    fireEvent.blur(input);

    // onChange must have been called with the default value (5.0).
    expect(onChange).toHaveBeenCalledWith(5.0);

    // The input should visually display the default ("5").
    expect(input.value).toBe("5");

    // No error message.
    expect(document.querySelector(".text-destructive")).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// Fixture B: Real param, default=null, required=true
// ---------------------------------------------------------------------------

const paramB: Parameter = {
  name: "n",
  type: "Int",
  default: null,
  required: true,
  positional: false,
  description: "Segments",
};

describe("Fixture B — Real param, default=null, required=true", () => {
  it("clear-then-blur shows a destructive error; onChange is not called with a value", () => {
    const onChange = vi.fn();
    render(
      <TooltipProvider>
        <NumericField param={paramB} value={10} onChange={onChange} />
      </TooltipProvider>
    );

    const input = document.querySelector("input") as HTMLInputElement;

    // Baseline: type a valid number and blur to commit.
    fireEvent.change(input, { target: { value: "10" } });
    fireEvent.blur(input);
    const callsBefore = onChange.mock.calls.length;

    // Now clear and blur again.
    fireEvent.change(input, { target: { value: "" } });
    fireEvent.blur(input);

    // Verify: no additional numeric onChange call was made.
    const numericCalls = onChange.mock.calls.filter(
      (args) => typeof args[0] === "number"
    );
    expect(numericCalls.length).toBe(callsBefore);

    // A destructive error indicator should be visible.
    const errorEl = document.querySelector(".text-destructive");
    expect(errorEl).toBeTruthy();
  });
});

// ---------------------------------------------------------------------------
// Fixture C: Real param, default=null, required=false
// ---------------------------------------------------------------------------

const paramC: Parameter = {
  name: "extra",
  type: "Real",
  default: null,
  required: false,
  positional: false,
  description: "Optional extra",
};

describe("Fixture C — Real param, default=null, required=false", () => {
  it("clear-then-blur calls onChange(undefined) with no error", () => {
    // vi.fn() returns a spy whose .mock.calls we inspect. Cast to the expected
    // NumericField onChange signature so TypeScript allows the prop assignment.
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const onChangeSpy = vi.fn() as any;
    const onChange: (value: number | undefined) => void = onChangeSpy;
    render(
      <TooltipProvider>
        <NumericField
          param={paramC}
          value={42}
          onChange={onChange}
        />
      </TooltipProvider>
    );

    const input = document.querySelector("input") as HTMLInputElement;

    // Clear and blur.
    fireEvent.change(input, { target: { value: "" } });
    fireEvent.blur(input);

    // onChange must have been called with undefined (omit-from-code-gen).
    const calls = onChangeSpy.mock.calls;
    expect(calls.length).toBeGreaterThan(0);
    const lastCallArg = calls[calls.length - 1][0];
    expect(lastCallArg).toBeUndefined();

    // No error shown.
    expect(document.querySelector(".text-destructive")).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// Fixture D: TypeUnionField for a Sources param (WT.T_wall shape) with default=300.0
// ---------------------------------------------------------------------------

// Mock WallTemperature definition that explicitly has default: 300 on T_wall.
// The live registry does not set a default on T_wall; we use a mock here per
// the plan fixture spec ("with default: 300.0").
const mockWallTemperatureWithDefault: ComponentDefinition = {
  id: "WallTemperature",
  label: "Wall Temperature",
  category: "Sources",
  description: "Wall temperature source",
  ports: [],
  parameters: [
    {
      name: "n",
      type: "Int",
      required: true,
      positional: false,
    },
    {
      name: "T_wall",
      type_union: ["Real", "Vector", "Function"],
      input_modes: ["scalar", "vector", "callable"],
      unit: "K",
      description: "Per-cell wall temperature",
      required: true,
      positional: false,
      default: 300,
    },
  ],
  constructorModes: [
    { mode: "default", signature: "WallTemperature(; ...)", parameters: ["n", "T_wall"] },
  ],
};

describe("Fixture D — TypeUnionField for Sources-category param with default=300.0", () => {
  it("clear-then-blur in value mode resets to param default (SourceValueEntry {mode:'value',value:300})", () => {
    const onParamChange = vi.fn();
    render(
      <TooltipProvider>
        <ParameterForm
          component={mockWallTemperatureWithDefault}
          activeMode="default"
          values={{ n: 4, T_wall: { mode: "value", value: 250 } }}
          onParamChange={onParamChange}
        />
      </TooltipProvider>
    );

    // Find the scalar input in the value-mode editor.
    const inputs = document.querySelectorAll("input");
    const scalarInput = inputs[inputs.length - 1] as HTMLInputElement;
    expect(scalarInput.value).toBe("250");

    // Clear and blur.
    fireEvent.change(scalarInput, { target: { value: "" } });
    fireEvent.blur(scalarInput);

    // Clearing must restore it as a SourceValueEntry with the default (300).
    const calls = onParamChange.mock.calls;
    expect(calls.length).toBeGreaterThan(0);
    const lastCall = calls[calls.length - 1];
    expect(lastCall[0]).toBe("T_wall");
    expect(lastCall[1]).toEqual({ mode: "value", value: 300 });
  });
});

// ---------------------------------------------------------------------------
// Fixture E: BCsTabForm ValueModeEditor with entry value=300.0
// ---------------------------------------------------------------------------

const mockChannelForBCs: ComponentDefinition = {
  id: "Channel",
  label: "Channel",
  category: "Hydraulic",
  description: "Test channel",
  ports: [],
  parameters: [
    {
      name: "n",
      type: "Int",
      required: true,
      positional: false,
    },
  ],
  constructorModes: [
    { mode: "default", signature: "Channel(; ...)", parameters: ["n"] },
  ],
  external_inputs: [
    {
      name: "T_wall_left",
      shape: "[1:n]",
      description: "Left wall BC",
      bc_modes: ["Value", "Profile", "Function", "Mark", "Source"],
      source_component: "WallTemperature",
      source_port: "T_wall_out",
    },
  ],
};

function makeNode(id: string): Node {
  return {
    id,
    type: "streamNode",
    position: { x: 200, y: 100 },
    data: {
      componentId: "Channel",
      instanceName: id,
      parameters: { n: 4 },
      constructorMode: "default",
    } satisfies StreamNodeData,
  };
}

describe("Fixture E — BCsTabForm ValueModeEditor, value=300.0", () => {
  beforeEach(() => {
    // Seed the store with a Channel node and a pre-set value BC entry (300.0).
    useStore.setState({
      nodes: [makeNode("ch1")],
      edges: [],
      selectedNodeId: "ch1",
      anchors: {},
      isDirty: false,
      _undoPast: [],
      _undoFuture: [],
      bcMode: {
        "ch1::T_wall_left": { mode: "value", value: 300 },
      },
      bcSymmetric: {},
    });
  });

  it("clear-then-blur in BCs value-mode editor resets to the current value (300)", () => {
    render(
      <TooltipProvider>
        <BCsTabForm component={mockChannelForBCs} nodeId="ch1" />
      </TooltipProvider>
    );

    // The NumericField inside ValueModeEditor should show "300".
    const input = document.querySelector("input") as HTMLInputElement;
    expect(input.value).toBe("300");

    // Clear and blur.
    fireEvent.change(input, { target: { value: "" } });
    fireEvent.blur(input);

    // After reset, the field should display "300" again (param.default = initial value).
    expect(input.value).toBe("300");

    // No error should appear.
    expect(document.querySelector(".text-destructive")).toBeNull();
  });
});
