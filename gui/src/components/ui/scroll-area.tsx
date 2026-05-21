import * as React from "react"
import { ScrollArea as ScrollAreaPrimitive } from "radix-ui"

import { cn } from "@/lib/utils"

// Phase 72 — primitive-layer recommit:
//   - Scrollbar w-2.5 (10 px) → w-1.5 (6 px) — denser; less SaaS-pill-scrollbar
//   - Thumb bg-border → bg-foreground/20 with hover bg-foreground/35
//   - Thumb rounded-full → rounded-none (no pill geometry; a square thumb
//     keeps the scrollbar reading as "tool", not "polished mobile app")
//   - Track stays transparent; the bar lives over the panel's tonal step
//   - Viewport focus ring 3px → 2px, no offset
function ScrollArea({
  className,
  children,
  ...props
}: React.ComponentProps<typeof ScrollAreaPrimitive.Root>) {
  return (
    <ScrollAreaPrimitive.Root
      data-slot="scroll-area"
      className={cn("relative", className)}
      {...props}
    >
      <ScrollAreaPrimitive.Viewport
        data-slot="scroll-area-viewport"
        // [&>div]:!block overrides Radix's default display:table on the viewport's inner
        // wrapper. Without this, children size to max-content (intrinsic width) and
        // escape the parent panel horizontally.
        className="size-full rounded-[inherit] outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-0 [&>div]:!block"
      >
        {children}
      </ScrollAreaPrimitive.Viewport>
      <ScrollBar />
      <ScrollAreaPrimitive.Corner />
    </ScrollAreaPrimitive.Root>
  )
}

function ScrollBar({
  className,
  orientation = "vertical",
  ...props
}: React.ComponentProps<typeof ScrollAreaPrimitive.ScrollAreaScrollbar>) {
  return (
    <ScrollAreaPrimitive.ScrollAreaScrollbar
      data-slot="scroll-area-scrollbar"
      orientation={orientation}
      className={cn(
        "flex touch-none select-none transition-colors duration-[80ms] motion-reduce:transition-none",
        orientation === "vertical" && "h-full w-1.5",
        orientation === "horizontal" && "h-1.5 flex-col",
        className
      )}
      {...props}
    >
      <ScrollAreaPrimitive.ScrollAreaThumb
        data-slot="scroll-area-thumb"
        className="relative flex-1 bg-foreground/20 transition-colors duration-[80ms] motion-reduce:transition-none hover:bg-foreground/35"
      />
    </ScrollAreaPrimitive.ScrollAreaScrollbar>
  )
}

export { ScrollArea, ScrollBar }
