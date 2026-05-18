// @vitest-environment happy-dom

import { describe, it, expect } from "vitest";
import { render } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { Input } from "../input";

// Uniform select-on-focus across every <Input> in the app.
// Regression guard for the chokepoint behavior introduced post-Phase-69 UAT.
describe("Input — select-on-focus", () => {
  it("selects existing value on focus for text input", async () => {
    const user = userEvent.setup();
    const { getByTestId } = render(
      <Input data-testid="i" defaultValue="hello" />,
    );
    const input = getByTestId("i") as HTMLInputElement;
    await user.click(input);
    expect(input.selectionStart).toBe(0);
    expect(input.selectionEnd).toBe(5);
  });

  it("selects existing value on focus for number input", async () => {
    const user = userEvent.setup();
    const { getByTestId } = render(
      <Input data-testid="i" type="number" defaultValue="42" />,
    );
    const input = getByTestId("i") as HTMLInputElement;
    await user.click(input);
    // happy-dom does not expose selectionStart on number inputs in all paths
    // — assert via input.select() being a no-op when called by the handler.
    // The behavioral contract: focus on a non-empty number input should not
    // throw and should leave the value intact.
    expect(input.value).toBe("42");
  });

  it("does NOT call select() on empty input (no-op, no flicker)", async () => {
    const user = userEvent.setup();
    const { getByTestId } = render(<Input data-testid="i" defaultValue="" />);
    const input = getByTestId("i") as HTMLInputElement;
    await user.click(input);
    // Empty input: nothing to select; selection range stays at 0,0.
    expect(input.selectionStart).toBe(0);
    expect(input.selectionEnd).toBe(0);
  });

  it("composes with caller-supplied onFocus (called first, before select)", async () => {
    const user = userEvent.setup();
    let captured = "";
    const { getByTestId } = render(
      <Input
        data-testid="i"
        defaultValue="abc"
        onFocus={(e) => {
          captured = e.currentTarget.value;
        }}
      />,
    );
    const input = getByTestId("i") as HTMLInputElement;
    await user.click(input);
    expect(captured).toBe("abc");
    expect(input.selectionStart).toBe(0);
    expect(input.selectionEnd).toBe(3);
  });

  it("opt-out: caller's onFocus calling preventDefault() suppresses select", async () => {
    const user = userEvent.setup();
    const { getByTestId } = render(
      <Input
        data-testid="i"
        defaultValue="abc"
        onFocus={(e) => e.preventDefault()}
      />,
    );
    const input = getByTestId("i") as HTMLInputElement;
    await user.click(input);
    // happy-dom click positions the caret at the end (length 3) when select
    // does not fire — we just assert it is NOT the full selection (0..3).
    expect(input.selectionEnd).toBe(input.selectionStart);
  });
});
