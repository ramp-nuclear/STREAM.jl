import * as React from "react"
import { CheckIcon } from "lucide-react"
import { Checkbox as CheckboxPrimitive } from "radix-ui"

import { cn } from "@/lib/utils"

// Phase 72 — primitive-layer recommit:
//   - 14 px box (size-3.5; was size-4). Denser; matches the compact-control
//     vocabulary at h-8 button + h-8 input scale.
//   - shadow-xs removed; doctrine §4 forbids ambient shadow on form fields.
//   - Hover lifts border to --border-hover (consistent with Input/Textarea).
//   - Checked state uses primary (neutral high-contrast slab) as fill —
//     the same neutral token Button's default variant uses; chrome doesn't
//     carry accent.
//   - rounded-[4px] → rounded-sm (consumes the new --radius-sm token).
//   - Instant toggle. Primitives at this size look broken with motion; we
//     stay instant regardless of motion preference.
function Checkbox({
  className,
  ...props
}: React.ComponentProps<typeof CheckboxPrimitive.Root>) {
  return (
    <CheckboxPrimitive.Root
      data-slot="checkbox"
      className={cn(
        "peer size-3.5 shrink-0 rounded-sm border border-border outline-none transition-colors duration-[80ms] motion-reduce:transition-none hover:border-border-hover focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-0 disabled:cursor-not-allowed disabled:opacity-50 aria-invalid:ring-2 aria-invalid:ring-destructive data-[state=checked]:border-primary data-[state=checked]:bg-primary data-[state=checked]:text-primary-foreground",
        className
      )}
      {...props}
    >
      <CheckboxPrimitive.Indicator
        data-slot="checkbox-indicator"
        className="grid place-content-center text-current"
      >
        <CheckIcon className="size-3 stroke-[2.5]" />
      </CheckboxPrimitive.Indicator>
    </CheckboxPrimitive.Root>
  )
}

export { Checkbox }
