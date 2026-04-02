// @vitest-environment happy-dom
import { describe, it, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import ModeToggle from "../ModeToggle";

describe("ModeToggle", () => {
  const modes = [
    {
      mode: "fixed-dP",
      signature: "Pump(dP; name)",
      parameters: ["dP_pump"],
    },
    {
      mode: "fixed-mdot",
      signature: "Pump(mdot0; name)",
      parameters: ["mdot0"],
    },
  ];

  it("renders buttons for each mode", () => {
    render(
      <ModeToggle modes={modes} activeMode="fixed-dP" onChange={vi.fn()} />
    );
    expect(screen.getByText("Fixed dP")).toBeTruthy();
    expect(screen.getByText("Fixed mdot")).toBeTruthy();
  });

  it.todo("calls onChange when inactive mode button is clicked");
  it.todo("highlights active mode button");
});
