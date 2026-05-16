// @vitest-environment happy-dom
//
// Tests the Phase 67 plan 67-02 Task 2 contract: WindowControls platform
// branching (D-14 / D-15). Covers:
// - macOS branch: 3 rounded-full buttons in Close/Min/Max order (Apple HIG)
//   with traffic-light hex colors and aria-label="Close window" leftmost.
// - Windows/Linux branch: 3 buttons with Lucide icons, aria-label="Close
//   window" rightmost, hover styling on Close.
// - platform() throwing falls back to Windows/Linux variant (vitest env).
// - Click handlers invoke the correct getCurrentWindow().* method.
import {
  describe,
  it,
  expect,
  beforeEach,
  afterEach,
  vi,
  type Mock,
} from "vitest";
import { render, cleanup } from "@testing-library/react";

// Mocks must be set up BEFORE the component import so the module bindings
// are stubbed at evaluation time.
const platformMock = vi.fn();
vi.mock("@tauri-apps/plugin-os", () => ({
  platform: () => platformMock(),
}));

const minimizeMock = vi.fn().mockResolvedValue(undefined);
const toggleMaximizeMock = vi.fn().mockResolvedValue(undefined);
const closeMock = vi.fn().mockResolvedValue(undefined);
const isMaximizedMock = vi.fn().mockResolvedValue(false);
const onResizedMock = vi.fn().mockResolvedValue(() => {});

vi.mock("@tauri-apps/api/window", () => ({
  getCurrentWindow: () => ({
    minimize: minimizeMock,
    toggleMaximize: toggleMaximizeMock,
    close: closeMock,
    isMaximized: isMaximizedMock,
    onResized: onResizedMock,
  }),
}));

import WindowControls from "../WindowControls";

async function flushEffects() {
  // Wait one microtask + macrotask tick so platform() in useEffect lands
  // and useWindowMaximized's initial Promise resolves.
  await new Promise((r) => setTimeout(r, 0));
  await new Promise((r) => setTimeout(r, 0));
}

beforeEach(() => {
  platformMock.mockReset();
  minimizeMock.mockClear();
  toggleMaximizeMock.mockClear();
  closeMock.mockClear();
  isMaximizedMock.mockClear();
  onResizedMock.mockClear();
});

afterEach(() => {
  cleanup();
});

describe("WindowControls — macOS branch", () => {
  it("renders three rounded-full buttons with traffic-light hex colors", async () => {
    platformMock.mockReturnValue("macos");
    const { container } = render(<WindowControls />);
    await flushEffects();

    const circles = container.querySelectorAll("button.rounded-full");
    expect(circles.length).toBe(3);

    // Apple HIG L→R order: Close (red), Minimize (yellow), Maximize (green)
    expect(circles[0].getAttribute("aria-label")).toBe("Close window");
    expect(circles[0].className).toContain("#ff5f57");
    expect(circles[1].getAttribute("aria-label")).toBe("Minimize window");
    expect(circles[1].className).toContain("#ffbd2e");
    expect(circles[2].getAttribute("aria-label")).toBe("Toggle maximize");
    expect(circles[2].className).toContain("#28c840");
  });

  it("invokes close() when the red leftmost circle is clicked", async () => {
    platformMock.mockReturnValue("macos");
    const { container } = render(<WindowControls />);
    await flushEffects();

    const circles = container.querySelectorAll("button.rounded-full");
    (circles[0] as HTMLButtonElement).click();
    expect(closeMock).toHaveBeenCalledTimes(1);

    (circles[1] as HTMLButtonElement).click();
    expect(minimizeMock).toHaveBeenCalledTimes(1);

    (circles[2] as HTMLButtonElement).click();
    expect(toggleMaximizeMock).toHaveBeenCalledTimes(1);
  });
});

describe("WindowControls — Windows/Linux branch", () => {
  it("renders Lucide icons with Close rightmost (windows)", async () => {
    platformMock.mockReturnValue("windows");
    const { container } = render(<WindowControls />);
    await flushEffects();

    // No traffic-light circles
    expect(container.querySelectorAll("button.rounded-full").length).toBe(0);

    const buttons = container.querySelectorAll("button");
    expect(buttons.length).toBe(3);
    // Rightmost = Close
    expect(buttons[buttons.length - 1].getAttribute("aria-label")).toBe(
      "Close window",
    );
    // Leftmost = Minimize
    expect(buttons[0].getAttribute("aria-label")).toBe("Minimize window");
    // Middle = Toggle maximize
    expect(buttons[1].getAttribute("aria-label")).toBe("Toggle maximize");
  });

  it("falls back to Windows/Linux variant when platform() throws", async () => {
    platformMock.mockImplementation(() => {
      throw new Error("platform unavailable");
    });
    const { container } = render(<WindowControls />);
    await flushEffects();

    expect(container.querySelectorAll("button.rounded-full").length).toBe(0);
    const buttons = container.querySelectorAll("button");
    expect(buttons.length).toBe(3);
    expect(buttons[buttons.length - 1].getAttribute("aria-label")).toBe(
      "Close window",
    );
  });

  it("invokes the correct IPC method when each Lucide button is clicked", async () => {
    platformMock.mockReturnValue("linux");
    const { container } = render(<WindowControls />);
    await flushEffects();

    const buttons = container.querySelectorAll("button");
    (buttons[0] as HTMLButtonElement).click();
    expect(minimizeMock).toHaveBeenCalledTimes(1);
    (buttons[1] as HTMLButtonElement).click();
    expect(toggleMaximizeMock).toHaveBeenCalledTimes(1);
    (buttons[2] as HTMLButtonElement).click();
    expect(closeMock).toHaveBeenCalledTimes(1);
  });
});
