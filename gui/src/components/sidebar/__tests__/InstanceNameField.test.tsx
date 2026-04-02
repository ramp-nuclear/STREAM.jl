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

  it("renders a 'Name' label with info icon", () => {
    render(<InstanceNameField value="ch1" onChange={vi.fn()} />);
    expect(screen.getByText("Name")).toBeTruthy();
    const icons = document.querySelectorAll("svg");
    expect(icons.length).toBeGreaterThan(0);
  });

  it.todo("validates Julia identifier on blur");
  it.todo("shows error for invalid identifiers");
  it.todo("calls onChange only for valid values");
  it.todo("syncs localValue when value prop changes");
});
