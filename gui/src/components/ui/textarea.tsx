import * as React from "react"

import { cn } from "@/lib/utils"

// Phase 72 — primitive-layer recommit (mirrors Input):
//   - shadow-xs removed, rounded-sm, text-body, hover border lift
//   - inset focus ring; aria-invalid → ring vocabulary
//   - min-h-16 retained as a sensible default; consumers override per-surface
function Textarea({ className, ...props }: React.ComponentProps<"textarea">) {
  return (
    <textarea
      data-slot="textarea"
      className={cn(
        "flex field-sizing-content min-h-16 w-full rounded-sm border border-border bg-transparent px-2.5 py-1.5 text-body outline-none transition-colors duration-[80ms] motion-reduce:transition-none placeholder:text-foreground/45 hover:border-border-hover focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-inset focus-visible:border-transparent disabled:cursor-not-allowed disabled:opacity-50 aria-invalid:ring-2 aria-invalid:ring-destructive aria-invalid:ring-inset",
        className
      )}
      {...props}
    />
  )
}

export { Textarea }
