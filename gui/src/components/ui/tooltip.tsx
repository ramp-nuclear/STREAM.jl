import * as React from "react"
import { Tooltip as TooltipPrimitive } from "radix-ui"

import { cn } from "@/lib/utils"

// Phase 72 — primitive-layer recommit:
//   - rounded-md → rounded-sm (compact-control radius; tooltips are pills)
//   - px-3 py-1.5 → px-2 py-1 (denser pill)
//   - text-xs → text-label (consumes 11 px token)
//   - bg-foreground text-background retained — inverse pill is the right
//     read for a quick-info chip
//   - Default delay 400 ms (still configurable via TooltipProvider prop)
//   - No shadow; no zoom; no slide. Plain 100 ms fade open, 80 ms fade close.
//   - Arrow shrunk from 2.5 → 2 (denser)

// 400 ms is the conventional "deliberate hover" delay used by Linear,
// VSCode, and Figma. Was 0 in the inherited shadcn default — that's
// "appear on glance" which is appropriate for marketing but distracting
// inside a tool surface where the cursor passes over many tooltipped
// elements per second.
const DEFAULT_TOOLTIP_DELAY_MS = 400

function TooltipProvider({
  delayDuration = DEFAULT_TOOLTIP_DELAY_MS,
  ...props
}: React.ComponentProps<typeof TooltipPrimitive.Provider>) {
  return (
    <TooltipPrimitive.Provider
      data-slot="tooltip-provider"
      delayDuration={delayDuration}
      {...props}
    />
  )
}

function Tooltip({
  ...props
}: React.ComponentProps<typeof TooltipPrimitive.Root>) {
  return <TooltipPrimitive.Root data-slot="tooltip" {...props} />
}

function TooltipTrigger({
  ...props
}: React.ComponentProps<typeof TooltipPrimitive.Trigger>) {
  return <TooltipPrimitive.Trigger data-slot="tooltip-trigger" {...props} />
}

function TooltipContent({
  className,
  sideOffset = 4,
  children,
  ...props
}: React.ComponentProps<typeof TooltipPrimitive.Content>) {
  return (
    <TooltipPrimitive.Portal>
      <TooltipPrimitive.Content
        data-slot="tooltip-content"
        sideOffset={sideOffset}
        className={cn(
          "z-50 w-fit rounded-sm bg-foreground px-2 py-1 text-label text-balance text-background outline-none motion-reduce:!duration-0 data-[state=open]:animate-in data-[state=open]:fade-in-0 data-[state=open]:duration-100 data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=closed]:duration-[80ms]",
          className
        )}
        {...props}
      >
        {children}
        <TooltipPrimitive.Arrow className="z-50 size-2 translate-y-[calc(-50%_-_2px)] rotate-45 rounded-[1px] bg-foreground fill-foreground" />
      </TooltipPrimitive.Content>
    </TooltipPrimitive.Portal>
  )
}

export { Tooltip, TooltipTrigger, TooltipContent, TooltipProvider }
