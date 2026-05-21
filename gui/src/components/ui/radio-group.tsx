import * as React from "react"
import { RadioGroup as RadioGroupPrimitive } from "radix-ui"

import { cn } from "@/lib/utils"

// Phase 72 — primitive-layer recommit. Mirrors Checkbox:
//   - 14 px outer (size-3.5; was size-4). 6 px inner dot (size-1.5; was 2).
//   - shadow-xs removed; hover lifts border to --border-hover; ring focus.
//   - Inner dot uses bg-foreground (the same neutral token Checkbox uses
//     for its check icon). No accent.
//   - Lucide CircleIcon removed — rendering the inner dot as a styled
//     <span> is one fewer SVG paint per radio and reads cleaner at 6 px.
//   - Instant toggle (no transition); doctrine for sub-16px controls.
function RadioGroup({
  className,
  ...props
}: React.ComponentProps<typeof RadioGroupPrimitive.Root>) {
  return (
    <RadioGroupPrimitive.Root
      data-slot="radio-group"
      className={cn("grid gap-2", className)}
      {...props}
    />
  )
}

function RadioGroupItem({
  className,
  ...props
}: React.ComponentProps<typeof RadioGroupPrimitive.Item>) {
  return (
    <RadioGroupPrimitive.Item
      data-slot="radio-group-item"
      className={cn(
        "aspect-square size-3.5 shrink-0 rounded-full border border-border outline-none transition-colors duration-[80ms] motion-reduce:transition-none hover:border-border-hover focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-0 disabled:cursor-not-allowed disabled:opacity-50 aria-invalid:ring-2 aria-invalid:ring-destructive data-[state=checked]:border-foreground",
        className
      )}
      {...props}
    >
      <RadioGroupPrimitive.Indicator
        data-slot="radio-group-indicator"
        className="relative flex items-center justify-center"
      >
        <span className="size-1.5 rounded-full bg-foreground" />
      </RadioGroupPrimitive.Indicator>
    </RadioGroupPrimitive.Item>
  )
}

export { RadioGroup, RadioGroupItem }
