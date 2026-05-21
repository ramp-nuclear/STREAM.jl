import * as React from "react"
import { cva, type VariantProps } from "class-variance-authority"
import { Slot } from "radix-ui"

import { cn } from "@/lib/utils"

// Phase 72 — primitive-layer recommit per /impeccable shape shadcn-primitive-layer.
//
// Density: h-8 (32 px) global default. sm: 28 px, xs: 24 px. No h-9/h-10 — the
// brief explicitly bans them; the previous "lg" variant is removed (no consumers).
//
// Radius: rounded-sm (4 px) per the compact-controls tier. rounded-md is reserved
// for surfaces (Popover, Dialog).
//
// Shadow: NONE. The previous "outline" variant carried shadow-xs as ambient
// atmosphere; doctrine §4 forbids it. Tonal contrast + border carries the affordance.
//
// Motion: transition-colors only, 80 ms. The previous transition-all swept layout
// properties too. Under prefers-reduced-motion: reduce, Tailwind's motion-reduce:
// variant collapses to instant.
//
// Focus ring: 2 px ring of var(--ring) at offset 0. The previous shadcn default
// (`focus-visible:ring-[3px] focus-visible:ring-ring/50` + border swap) doubled
// the focus signal; one clean ring is enough.
//
// Default variant uses bg-primary + text-primary-foreground which already resolves
// to a neutral high-contrast slab in both themes (--primary is the light neutral
// text color in dark mode; --primary-foreground is the canvas-dark). No accent
// fill — that stays canvas-side per the canvas-as-product hierarchy.
const buttonVariants = cva(
  "inline-flex shrink-0 items-center justify-center gap-1.5 rounded-sm text-body font-medium whitespace-nowrap outline-none transition-colors duration-[80ms] motion-reduce:transition-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-0 disabled:pointer-events-none disabled:opacity-50 aria-invalid:ring-2 aria-invalid:ring-destructive [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-3.5 [&_svg]:stroke-[1.5]",
  {
    variants: {
      variant: {
        // Neutral high-contrast slab. Reads as action-of-record via contrast,
        // not color. Used identically in chrome + modal contexts — the modal
        // scrim provides the permission to read confidently.
        default: "bg-primary text-primary-foreground hover:bg-primary/90 active:opacity-90",
        // The one accent slab in the primitive layer; semantic gravity earns
        // it. No dark-mode opacity halving (the previous shadcn pattern made
        // destructive read tentative in dark mode).
        destructive: "bg-destructive text-background hover:bg-destructive/90 focus-visible:ring-destructive active:opacity-90",
        // Border-only. Hover lifts the border to --border-hover; no fill on
        // hover (was hover:bg-accent which competed with the default slab).
        outline: "border border-border bg-transparent text-foreground hover:border-border-hover hover:bg-card/60",
        // Subdued filled. Reads as "this is interactive, but not the primary
        // action." Used for secondary actions in modals (Cancel) and for
        // toolbar-style buttons in chrome.
        secondary: "bg-secondary text-secondary-foreground hover:bg-card",
        // No chrome until hover. Most chrome buttons (panel toggles, titlebar
        // controls) live here.
        ghost: "text-foreground hover:bg-card",
        // Text-only. Underline-on-hover. For inline references inside body
        // copy or dialog bodies.
        link: "text-foreground underline-offset-4 hover:underline",
      },
      size: {
        default: "h-8 px-3 has-[>svg]:px-2.5",
        sm: "h-7 gap-1 px-2.5 has-[>svg]:px-2",
        xs: "h-6 gap-1 px-2 text-label has-[>svg]:px-1.5 [&_svg:not([class*='size-'])]:size-3",
        icon: "size-8",
        "icon-sm": "size-7",
        "icon-xs": "size-6 [&_svg:not([class*='size-'])]:size-3",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  }
)

function Button({
  className,
  variant = "default",
  size = "default",
  asChild = false,
  ...props
}: React.ComponentProps<"button"> &
  VariantProps<typeof buttonVariants> & {
    asChild?: boolean
  }) {
  const Comp = asChild ? Slot.Root : "button"

  return (
    <Comp
      data-slot="button"
      data-variant={variant}
      data-size={size}
      className={cn(buttonVariants({ variant, size, className }))}
      {...props}
    />
  )
}

export { Button, buttonVariants }
