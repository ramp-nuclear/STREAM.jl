// @vitest-environment happy-dom
//
// Phase 63 Plan 63-C Task 02 — BCModePicker tests.
// Covers D-04 (5-pill order: Value Profile Function Mark Source) and D-09
// (required-unset visual + muted-destructive hint).

import { describe, it, expect, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import BCModePicker from "../BCModePicker";

describe("BCModePicker", () => {
  it("renders all 5 mode pills in D-04 order (Value Profile Function Mark Source)", () => {
    render(
      <BCModePicker
        label="T_wall_left[1:n]"
        active={undefined}
        onChange={vi.fn()}
      />,
    );
    const buttons = screen.getAllByRole("button");
    const labels = buttons.map((b) => b.textContent);
    expect(labels).toEqual(["Value", "Profile", "Function", "Mark", "Source"]);
  });

  it("renders no active pill when active === undefined (D-09 required-unset)", () => {
    render(
      <BCModePicker
        label="T_wall_left[1:n]"
        active={undefined}
        onChange={vi.fn()}
      />,
    );
    // shadcn Button's default variant carries `bg-primary`; outline does not.
    // When active === undefined, no button should have the default-variant class.
    const buttons = screen.getAllByRole("button");
    for (const b of buttons) {
      expect(b.className).not.toMatch(/\bbg-primary\b/);
    }
  });

  it("renders the required-unset hint when active === undefined (D-09)", () => {
    render(
      <BCModePicker
        label="T_wall_left[1:n]"
        active={undefined}
        onChange={vi.fn()}
      />,
    );
    expect(screen.getByText(/BC required/i)).toBeTruthy();
  });

  it("does NOT render the hint when active is set", () => {
    render(
      <BCModePicker
        label="T_wall_left[1:n]"
        active="value"
        onChange={vi.fn()}
      />,
    );
    expect(screen.queryByText(/BC required/i)).toBeNull();
  });

  it("highlights the active pill when active is set", () => {
    render(
      <BCModePicker
        label="T_wall_left[1:n]"
        active="profile"
        onChange={vi.fn()}
      />,
    );
    const profileBtn = screen.getByRole("button", { name: "Profile" });
    expect(profileBtn.className).toMatch(/\bbg-primary\b/);
    // Sanity: a different pill should NOT be highlighted.
    const valueBtn = screen.getByRole("button", { name: "Value" });
    expect(valueBtn.className).not.toMatch(/\bbg-primary\b/);
  });

  it("calls onChange with the new mode when an inactive pill is clicked", () => {
    const onChange = vi.fn();
    render(
      <BCModePicker
        label="T_wall_left[1:n]"
        active={undefined}
        onChange={onChange}
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: "Mark" }));
    expect(onChange).toHaveBeenCalledTimes(1);
    expect(onChange).toHaveBeenCalledWith("mark");
  });

  it("renders the label prop", () => {
    render(
      <BCModePicker
        label="T_wall_left[1:n]"
        active={undefined}
        onChange={vi.fn()}
      />,
    );
    expect(screen.getByText("T_wall_left[1:n]")).toBeTruthy();
  });
});
