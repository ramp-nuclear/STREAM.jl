import * as React from "react"
import { cva, type VariantProps } from "class-variance-authority"
import { Slot } from "radix-ui"

import { cn } from "@/lib/utils"

// Phase 72 — primitive-layer recommit. Badges shed:
//   - rounded-full → rounded-sm (matches the compact-control radius vocabulary)
//   - text-xs (raw Tailwind) → text-label (11 px from the locked type scale)
//   - "destructive" variant fill → relies on consumer semantic tokens; chrome
//     doesn't carry accent. Severity-coded badges in ValidationPanel use
//     --color-warning / --color-info / --destructive directly.
//   - transition-[color,box-shadow] → transition-colors duration-[80ms]
//
// Standard size h-5 px-1.5 — denser than the previous default (which had no
// height constraint and inherited line-height padding).
const badgeVariants = cva(
  "inline-flex h-5 w-fit shrink-0 items-center justify-center gap-1 overflow-hidden rounded-sm border border-transparent px-1.5 text-label font-medium whitespace-nowrap outline-none transition-colors duration-[80ms] motion-reduce:transition-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-0 aria-invalid:ring-2 aria-invalid:ring-destructive [&>svg]:pointer-events-none [&>svg]:size-3 [&>svg]:stroke-[1.5]",
  {
    variants: {
      variant: {
        default: "bg-card text-foreground [a&]:hover:bg-card/80",
        secondary:
          "bg-panel text-foreground/75 [a&]:hover:bg-card",
        outline:
          "border-border text-foreground/75 [a&]:hover:border-border-hover [a&]:hover:text-foreground",
        ghost: "text-foreground/75 [a&]:hover:bg-card",
      },
    },
    defaultVariants: {
      variant: "default",
    },
  }
)

function Badge({
  className,
  variant = "default",
  asChild = false,
  ...props
}: React.ComponentProps<"span"> &
  VariantProps<typeof badgeVariants> & { asChild?: boolean }) {
  const Comp = asChild ? Slot.Root : "span"

  return (
    <Comp
      data-slot="badge"
      data-variant={variant}
      className={cn(badgeVariants({ variant }), className)}
      {...props}
    />
  )
}

export { Badge, badgeVariants }
