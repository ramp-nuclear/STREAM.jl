import * as React from "react"
import { cva, type VariantProps } from "class-variance-authority"
import { Toggle as TogglePrimitive } from "radix-ui"

import { cn } from "@/lib/utils"

// Phase 72 — primitive-layer recommit. Mirrors Button's vocabulary:
// h-8 default (no h-9/h-10), rounded-sm, transition-colors 80ms, 2px focus
// ring. On state uses bg-card + border-border-hover (tonal step + border
// emphasis) instead of accent fill — chrome doesn't carry accent.
const toggleVariants = cva(
  "inline-flex items-center justify-center gap-1.5 rounded-sm text-body font-medium whitespace-nowrap outline-none transition-colors duration-[80ms] motion-reduce:transition-none hover:bg-card focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-0 disabled:pointer-events-none disabled:opacity-50 aria-invalid:ring-2 aria-invalid:ring-destructive data-[state=on]:bg-card data-[state=on]:border-border-hover [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-3.5 [&_svg]:stroke-[1.5]",
  {
    variants: {
      variant: {
        default: "bg-transparent border border-transparent",
        outline:
          "border border-border bg-transparent text-foreground hover:border-border-hover",
      },
      size: {
        default: "h-8 min-w-8 px-2",
        sm: "h-7 min-w-7 px-1.5",
        xs: "h-6 min-w-6 px-1 text-label [&_svg:not([class*='size-'])]:size-3",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  }
)

function Toggle({
  className,
  variant,
  size,
  ...props
}: React.ComponentProps<typeof TogglePrimitive.Root> &
  VariantProps<typeof toggleVariants>) {
  return (
    <TogglePrimitive.Root
      data-slot="toggle"
      className={cn(toggleVariants({ variant, size, className }))}
      {...props}
    />
  )
}

export { Toggle, toggleVariants }
