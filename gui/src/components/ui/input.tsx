import * as React from "react"

import { cn } from "@/lib/utils"

// Uniform select-on-focus across every <Input> in the app. Property fields,
// resource editors, and dialog text inputs all share one chokepoint here, so
// modifying this component propagates the behavior everywhere without per-
// callsite plumbing. UAT round 1 (Phase 69) found that having to manually
// clear a default value before editing was a paper-cut paid on every
// parameter edit; auto-select-all on focus makes "type to replace" the
// one-click default while still letting positional editing happen via
// subsequent clicks (browser positions the caret on click-within-focused).
// Only fires for text-like types where .select() is meaningful (some types
// like checkbox/radio/file/range throw or no-op).
//
// LOAD-BEARING: do not remove or alter the rAF.select() chokepoint without
// reading feedback_input_select_on_focus in user memory first.
const SELECT_ON_FOCUS_TYPES = new Set([
  "text",
  "number",
  "email",
  "tel",
  "url",
  "search",
  "password",
]);

// Phase 72 — primitive-layer recommit:
//   - shadow-xs removed (doctrine §4: no ambient atmosphere on form fields)
//   - rounded-md → rounded-sm (compact-control radius)
//   - text-[13px] → text-body (consumes the locked --text-body token)
//   - hover lifts border to --border-hover for affordance without filling
//   - focus ring is inset (ring-inset) so it sits inside the bounding box
//     and doesn't overflow into stacked form rows; the doubled
//     focus-visible:border-ring + focus-visible:ring-[3px] pattern collapses
//     to a single 2px inset ring
//   - aria-invalid renders the destructive ring instead of a border tint;
//     this matches the Toggle/Button error vocabulary (ring everywhere)
//   - dark:bg-input/30 removed; --input now resolves to a solid OKLCH so
//     the opacity-on-alpha hack is unnecessary
function Input({
  className,
  type,
  onFocus,
  ...props
}: React.ComponentProps<"input">) {
  const handleFocus = React.useCallback(
    (e: React.FocusEvent<HTMLInputElement>) => {
      // Compose with any caller-supplied onFocus first so they can opt-out
      // by calling e.preventDefault() (rare).
      onFocus?.(e);
      if (e.defaultPrevented) return;
      const el = e.currentTarget;
      const inputType = (el.type || "text").toLowerCase();
      if (!SELECT_ON_FOCUS_TYPES.has(inputType) || el.value === "") return;
      // Defer to the next animation frame. If we call select() synchronously
      // here, the mouseup that completes the click runs AFTER focus and
      // positions the caret at the click point — undoing the selection
      // visually a few ms after it appears. rAF runs after the click event
      // chain finishes, so the selection sticks. Recheck `document.activeElement`
      // to skip the call when the user has already moved focus elsewhere
      // (rapid tab/click sequences).
      requestAnimationFrame(() => {
        if (document.activeElement === el && el.value !== "") {
          el.select();
        }
      });
    },
    [onFocus],
  );

  return (
    <input
      type={type}
      data-slot="input"
      onFocus={handleFocus}
      className={cn(
        "h-8 w-full min-w-0 rounded-sm border border-border bg-transparent px-2.5 py-1 text-body outline-none transition-colors duration-[80ms] motion-reduce:transition-none selection:bg-foreground/85 selection:text-background hover:border-border-hover file:inline-flex file:h-7 file:border-0 file:bg-transparent file:text-body file:font-medium file:text-foreground placeholder:text-foreground/45 disabled:pointer-events-none disabled:cursor-not-allowed disabled:opacity-50",
        "focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-inset focus-visible:border-transparent",
        "aria-invalid:ring-2 aria-invalid:ring-destructive aria-invalid:ring-inset",
        className
      )}
      {...props}
    />
  )
}

export { Input }
