// @vitest-environment happy-dom
import { describe, it, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import PipeGeometryPicker from "../PipeGeometryPicker";

describe("PipeGeometryPicker", () => {
  it("renders circular and rectangular buttons", () => {
    render(<PipeGeometryPicker value={undefined} onChange={vi.fn()} />);
    expect(screen.getByText("Circular")).toBeTruthy();
    expect(screen.getByText("Rectangular")).toBeTruthy();
  });

  it.todo("shows L and D fields in circular mode");
  it.todo("shows L, W, H fields in rectangular mode");
  it.todo("clears dimension fields on geometry type switch (per D-02)");
  it.todo("validates dimensions with validatePositiveReal on blur");
});
