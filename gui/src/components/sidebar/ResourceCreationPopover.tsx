// ResourceCreationPopover.tsx — Phase 62 Plan 62-08 Task 1.
//
// Thin wrapper around Radix `<PopoverContent>` that enforces the popover
// interaction contract from 62-UI-SPEC §"`+ New…` anchored popover":
//
//   • D-16 non-dismiss-on-click-outside: `onInteractOutside={(e) => e.preventDefault()}`
//   • UI-SPEC §"Esc precedence cascade" item 1: pressing Esc inside the popover
//     closes the popover ONLY — it must NOT propagate further up the document
//     so that the global Esc cascade in SidebarPanel (62-09) does not also
//     fire and clear the selection on the same Esc press. We achieve this by
//     calling BOTH `e.preventDefault()` AND `e.stopPropagation()` on the
//     KeyboardEvent that Radix passes into `onEscapeKeyDown` BEFORE invoking
//     `onOpenChange(false)`.
//   • D-17 anchor + 280px width: side="right" align="start" sideOffset={4}
//     collisionPadding={8}, inline `style={{ width: 280 }}`.
//   • Pitfall 1 (RESEARCH §"Pitfall 1 focus-return workaround"): Radix
//     issue #646 — once `onInteractOutside` calls `preventDefault()`, Radix
//     skips its own focus-return on close. We MUST call
//     `triggerRef.current?.focus()` explicitly inside `setTimeout(..., 0)`
//     so Radix finishes its close animation before focus return.
//
// Design choice: this file exports `ResourceCreationPopoverContent`, a
// drop-in replacement for `<PopoverContent>` that carries the contract.
// The consumer (ResourceReferencePicker, ResourceGroupHeader) composes
// it directly under their own `<Popover>` + `<PopoverTrigger>` — see
// `ResourceReferencePicker.tsx` for a canonical mount. This is the
// "second approach" called out in 62-08-PLAN.md Task 1 action: smaller,
// more composable, and leaves the consumer in control of the trigger ref.
//
// The Trigger element (the consumer's button) is what holds the
// `triggerRef`; we forward it here only so the focus-return workaround
// can call `.focus()` on it explicitly after Esc / outside (suppressed) /
// Cancel / Create.

import * as React from "react";
import { PopoverContent } from "@/components/ui/popover";

export interface ResourceCreationPopoverContentProps {
  /**
   * Whether the popover is currently open. Owned by the consumer (the picker
   * or group header) — the wrapper is render-only and does not manage state.
   */
  open: boolean;
  /**
   * Setter for the open state; called with `false` on Esc / Cancel / Create.
   */
  onOpenChange: (open: boolean) => void;
  /**
   * Ref to the `+ New…` trigger button. Used to restore focus after the
   * popover closes (Pitfall 1 workaround).
   */
  triggerRef: React.RefObject<HTMLElement | null>;
  /**
   * Body content — the GeometryResourceEditor or PowerShapeResourceEditor.
   */
  children: React.ReactNode;
}

export function ResourceCreationPopoverContent({
  open,
  onOpenChange,
  triggerRef,
  children,
}: ResourceCreationPopoverContentProps) {
  // Defensive: silence the lint when `open` is unused at the JSX level. We
  // accept it as a prop so a future variant (e.g. focus management on mount)
  // can branch on it without an API break, and so the consumer's open/closed
  // model is explicit at the call site (the popover hierarchy is opaque from
  // the consumer's perspective without it).
  void open;

  return (
    <PopoverContent
      side="right"
      align="start"
      sideOffset={4}
      collisionPadding={8}
      style={{ width: 280 }}
      // D-16: click-outside must NOT dismiss.
      onInteractOutside={(e) => {
        e.preventDefault();
        // Pitfall 1 focus return — even on suppressed outside-click we keep
        // focus pinned on the trigger so Tab order stays coherent.
        setTimeout(() => triggerRef.current?.focus(), 0);
      }}
      // UI-SPEC §"Esc precedence cascade" item 1: close popover ONLY.
      // Both preventDefault() and stopPropagation() are real DOM methods on
      // the KeyboardEvent Radix forwards into this callback. Calling
      // stopPropagation() prevents the document-level keydown listener
      // SidebarPanel registers (62-09 Task 1) from also firing and clearing
      // the selection on the same Esc press. This is what ships the
      // popover contract-complete in 62-08 — 62-09 consumes it as-is.
      onEscapeKeyDown={(e) => {
        e.preventDefault();
        e.stopPropagation();
        onOpenChange(false);
        // Pitfall 1 focus return — explicit because preventDefault on
        // onInteractOutside has already broken Radix's automatic restore.
        setTimeout(() => triggerRef.current?.focus(), 0);
      }}
    >
      {children}
    </PopoverContent>
  );
}

export default ResourceCreationPopoverContent;
