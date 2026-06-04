// switch.tsx — Sliding-pill toggle primitive (Phase 72 Preferences shape)
//
// Added when Preferences became the first consumer. Switch is the right
// semantic for "binary on/off setting" — distinct from Toggle (a press-button
// with pressed state used in toolbars) and Checkbox (a form-field control
// used in lists / forms). DESIGN.md §5 primitive vocab is followed:
//
//   - Radius: rounded-full (exception to the two-tier sm/md scale; pill
//     shape is the affordance, and "rounded-sm switch" reads as a wrong
//     primitive). Documented exception, parallel to how Badge keeps
//     rounded-sm + h-5 as locked even though h-5 sits outside the
//     h-8/h-7/h-6 button-density scale.
//   - Size: h-5 w-9 (20 × 36 px) — matches Badge density. The "small switch"
//     read keeps Preferences dense without feeling cramped.
//   - Off state: bg-border (subtle, recedes). On state: bg-primary (neutral
//     high-contrast slab, matches Button primary posture).
//   - Thumb: bg-background (light dot in dark theme, dark dot in light) so
//     the moving thumb reads against the track regardless of theme.
//   - Focus ring: ring-2 ring-ring offset-2 outer (matches Button focus, not
//     the Input inset variant — Switch isn't a text-entry control).
//   - Motion: transition-colors 80 ms + thumb transition-transform 80 ms
//     (locked motion vocab); motion-reduce collapses both to instant.

import { Switch as SwitchPrimitive } from "radix-ui";
import { cn } from "@/lib/utils";

function Switch({
  className,
  ...props
}: React.ComponentProps<typeof SwitchPrimitive.Root>) {
  return (
    <SwitchPrimitive.Root
      data-slot="switch"
      className={cn(
        "peer inline-flex h-5 w-9 shrink-0 cursor-pointer items-center rounded-full border border-transparent outline-none",
        "transition-colors duration-[80ms] motion-reduce:transition-none",
        "focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-popover",
        "disabled:cursor-not-allowed disabled:opacity-50",
        "data-[state=checked]:bg-primary data-[state=unchecked]:bg-border",
        className,
      )}
      {...props}
    >
      <SwitchPrimitive.Thumb
        data-slot="switch-thumb"
        className={cn(
          "pointer-events-none block size-4 rounded-full bg-background shadow-none",
          "transition-transform duration-[80ms] motion-reduce:transition-none",
          "data-[state=checked]:translate-x-4 data-[state=unchecked]:translate-x-0.5",
        )}
      />
    </SwitchPrimitive.Root>
  );
}

export { Switch };
