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
const SELECT_ON_FOCUS_TYPES = new Set([
  "text",
  "number",
  "email",
  "tel",
  "url",
  "search",
  "password",
]);

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
        "h-8 w-full min-w-0 rounded-md border border-input bg-transparent px-2.5 py-1 text-[13px] shadow-xs transition-[color,box-shadow] outline-none selection:bg-primary selection:text-primary-foreground file:inline-flex file:h-7 file:border-0 file:bg-transparent file:text-sm file:font-medium file:text-foreground placeholder:text-muted-foreground disabled:pointer-events-none disabled:cursor-not-allowed disabled:opacity-50 dark:bg-input/30",
        "focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50",
        "aria-invalid:border-destructive aria-invalid:ring-destructive/20 dark:aria-invalid:ring-destructive/40",
        className
      )}
      {...props}
    />
  )
}

export { Input }
