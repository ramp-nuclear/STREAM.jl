import * as React from "react"
import { Popover as PopoverPrimitive } from "radix-ui"

import { cn } from "@/lib/utils"

// NOTE: This shim intentionally does NOT bake in click-outside suppression.
// Consumers that need click-outside-no-dismiss (e.g., Phase 62 `+ New…` picker
// per UI-SPEC §"+ New… anchored popover" + D-16) pass the relevant prop per
// use. Baking it in here would break other consumers.
//
// Phase 72 — primitive-layer recommit:
//   - shadow-md removed (doctrine §4: no ambient atmosphere; popovers float
//     on tonal step alone — bg-popover is one tone lighter than --panel)
//   - rounded-md retained (compact surface radius)
//   - p-4 → p-2 (denser; consumers can override per-surface)
//   - zoom-in/zoom-out removed; slide-in-from-* removed
//   - Plain 100 ms fade-in / 80 ms fade-out, motion-reduce → instant
//   - text-popover-foreground → text-foreground (popover-foreground inherits
//     foreground in our token system; explicit reference adds nothing)

export function Popover({
  ...props
}: React.ComponentProps<typeof PopoverPrimitive.Root>) {
  return <PopoverPrimitive.Root data-slot="popover" {...props} />
}

export function PopoverTrigger({
  ...props
}: React.ComponentProps<typeof PopoverPrimitive.Trigger>) {
  return <PopoverPrimitive.Trigger data-slot="popover-trigger" {...props} />
}

export function PopoverAnchor({
  ...props
}: React.ComponentProps<typeof PopoverPrimitive.Anchor>) {
  return <PopoverPrimitive.Anchor data-slot="popover-anchor" {...props} />
}

export function PopoverPortal({
  ...props
}: React.ComponentProps<typeof PopoverPrimitive.Portal>) {
  return <PopoverPrimitive.Portal data-slot="popover-portal" {...props} />
}

export function PopoverContent({
  className,
  align = "center",
  sideOffset = 4,
  ...props
}: React.ComponentProps<typeof PopoverPrimitive.Content>) {
  return (
    <PopoverPrimitive.Portal>
      <PopoverPrimitive.Content
        data-slot="popover-content"
        align={align}
        sideOffset={sideOffset}
        className={cn(
          "z-50 w-72 rounded-md border border-border bg-popover p-2 text-foreground outline-hidden motion-reduce:!duration-0 data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=closed]:duration-[80ms] data-[state=open]:fade-in-0 data-[state=open]:duration-100",
          className
        )}
        {...props}
      />
    </PopoverPrimitive.Portal>
  )
}
