// @vitest-environment happy-dom
import { describe, it, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import InstanceNameField from "../InstanceNameField";

describe("InstanceNameField", () => {
  it("renders input with initial value", () => {
    render(<InstanceNameField value="pump_1" onChange={vi.fn()} />);
    const input = screen.getByDisplayValue("pump_1");
    expect(input).toBeTruthy();
  });

  it.todo("validates Julia identifier on blur");
  it.todo("shows error for invalid identifiers");
  it.todo("calls onChange only for valid values");
  it.todo("syncs localValue when value prop changes");
});
