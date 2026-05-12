// @vitest-environment happy-dom
import { describe, it, expect, vi } from "vitest"
import { render, screen, fireEvent } from "@testing-library/react"
import { useState } from "react"

import {
  Popover,
  PopoverTrigger,
  PopoverContent,
} from "../popover"

// Guard-rail test for Phase 62 Wave 2 consumers (62-08 picker).
// Resolves RESEARCH §"Assumption A3": Radix Popover's
// `onInteractOutside={(e) => e.preventDefault()}` correctly suppresses
// click-outside dismissal without breaking Esc handling.
//
// Implementation note: Radix's dismissable layer registers its document-level
// `pointerdown` listener inside a `setTimeout(0)` (see
// node_modules/@radix-ui/react-dismissable-layer/dist/index.mjs —
// `usePointerDownOutside`). The test must therefore wait one macrotask after
// render before dispatching the outside pointerdown, otherwise the listener
// is not yet attached and the test silently no-ops.

function flushTimers() {
  return new Promise((resolve) => setTimeout(resolve, 0))
}

function dispatchOutsidePointerDown(target: Element) {
  // Use a bubbling `pointerdown` so the document-level listener Radix attaches
  // inside `usePointerDownOutside` actually fires. Non-touch pointerType so
  // Radix takes the synchronous dispatch path.
  const evt = new Event("pointerdown", { bubbles: true, cancelable: true })
  target.dispatchEvent(evt)
}

describe("Popover shim — non-dismiss-on-click-outside behavior", () => {
  function ControlledFixture({
    onInteractOutside,
    suppress = true,
  }: {
    onInteractOutside?: (e: Event) => void
    suppress?: boolean
  }) {
    const [open, setOpen] = useState(true)
    return (
      <div>
        <Popover open={open} onOpenChange={setOpen}>
          <PopoverTrigger>open</PopoverTrigger>
          <PopoverContent
            onInteractOutside={(e) => {
              if (suppress) e.preventDefault()
              onInteractOutside?.(e as unknown as Event)
            }}
          >
            <div>content</div>
          </PopoverContent>
        </Popover>
        <button type="button" data-testid="outside">
          outside
        </button>
      </div>
    )
  }

  it("does NOT close when an outside element is clicked (preventDefault path)", async () => {
    render(<ControlledFixture suppress={true} />)
    await flushTimers()
    expect(screen.queryByText("content")).not.toBeNull()

    const outside = screen.getByTestId("outside")
    dispatchOutsidePointerDown(outside)
    fireEvent.click(outside)

    // Content MUST still be in the document — preventDefault suppressed dismiss.
    expect(screen.queryByText("content")).not.toBeNull()
  })

  it("DOES close on Escape (Pitfall 1 is about focus-return, not Esc dismissal)", async () => {
    render(<ControlledFixture suppress={true} />)
    await flushTimers()
    expect(screen.queryByText("content")).not.toBeNull()

    fireEvent.keyDown(document.body, { key: "Escape", code: "Escape" })

    // Esc still dismisses even though onInteractOutside is preventDefault'd —
    // that's the entire reason the picker can rely on Esc as the keyboard exit.
    expect(screen.queryByText("content")).toBeNull()
  })

  it("invokes the onInteractOutside callback when an outside element is clicked", async () => {
    const spy = vi.fn()
    render(<ControlledFixture suppress={true} onInteractOutside={spy} />)
    await flushTimers()

    const outside = screen.getByTestId("outside")
    dispatchOutsidePointerDown(outside)
    fireEvent.click(outside)

    // Spy should have been called at least once — the callback is plumbed
    // through the shim to Radix Content. `onInteractOutside` is invoked by
    // Radix's dismissable layer when a pointerdown lands outside the content.
    expect(spy).toHaveBeenCalled()
  })
})
