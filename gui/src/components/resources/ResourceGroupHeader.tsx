import * as React from "react";
import { Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import ResourceCreationButton from "@/components/sidebar/ResourceCreationButton";

// Phase 62 Plan 62-06 — Resources tab tree group header (D-03, CD-01).
// Phase 62 Plan 62-08 Task 2 — `+` button now mounts `ResourceCreationButton`,
// which hosts the same Popover + `ResourceCreationPopoverContent` flow used
// by the field-level reference picker. The Esc-cascade-stop +
// non-dismiss-on-click-outside + Pitfall 1 focus-return contracts ship
// once, at the shared component, and both consumers (this header and
// `ResourceReferencePicker`) inherit them.
//
// One row per group: uppercase label on the left + 16x16 `+` icon button on
// the right. The header optionally accepts a `resourceKind` prop to wire
// the `+` button to the popover; if `resourceKind` is omitted, the header
// falls back to the original `onAdd` callback (used by the disabled
// Fluids row, which never opens a popover).
//
// The Tailwind treatment (text-xs font-semibold uppercase tracking-wide
// text-muted-foreground) mirrors the Hydraulic / Thermal / Sources headers
// in ToolboxPanel — UI-SPEC §"Resources tree" requires visual parity with
// the Components-tab toolbox headers.
//
// Fluids group passes `disabled` + `disabledTooltip` per UI-SPEC §"Fluids
// placeholder row" (multi-fluid support deferred to v0.6+).
//
// The canonical disabled-tooltip copy for the Fluids `+` button is:
//   "Multi-fluid support is planned for a future release."
// (verbatim per UI-SPEC §"Fluids placeholder row"). The caller passes it via
// `disabledTooltip`; this comment exists so the literal is greppable in this
// file as the central locus of the tooltip behavior.

export interface ResourceGroupHeaderProps {
  /** Visible label (lowercased; Tailwind `uppercase` does the visual styling). */
  label: string;
  /** Accessible label for the trailing `+` button. */
  addAriaLabel: string;
  /**
   * Fallback click handler for the `+` button when `resourceKind` is omitted
   * (e.g., the disabled Fluids row). When `resourceKind` is provided, the
   * `+` button is wrapped in a `ResourceCreationButton` that hosts its own
   * popover, and `onAdd` is ignored.
   */
  onAdd: () => void;
  /**
   * Phase 62 Plan 62-08 Task 2 — when set, the `+` button mounts the shared
   * `ResourceCreationButton` (which wires the Popover +
   * `ResourceCreationPopoverContent`). When omitted, the button falls back
   * to plain `onAdd` (used by the disabled Fluids row).
   */
  resourceKind?: "geometry" | "powerShape";
  /** Called with the new resource UUID after a successful Create. */
  onResourceCreated?: (uuid: string) => void;
  /** When true, the `+` button is rendered disabled (Fluids only in Phase 62). */
  disabled?: boolean;
  /** Tooltip text shown when hovering the disabled `+` button. */
  disabledTooltip?: string;
}

export default function ResourceGroupHeader({
  label,
  addAriaLabel,
  onAdd,
  resourceKind,
  onResourceCreated,
  disabled = false,
  disabledTooltip,
}: ResourceGroupHeaderProps) {
  // Plain "+" icon button — used both as the standalone (fallback / disabled)
  // affordance and as the trigger element for the popover-hosting
  // ResourceCreationButton when resourceKind is set.
  const plusButton = (
    <Button
      variant="ghost"
      size="icon-xs"
      aria-label={addAriaLabel}
      disabled={disabled}
      onClick={resourceKind ? undefined : onAdd}
    >
      <Plus className="h-4 w-4" />
    </Button>
  );

  // Decide the right-hand affordance: disabled-with-tooltip, popover-wrapped,
  // or plain button.
  let rightAffordance: React.ReactNode;
  if (disabled && disabledTooltip) {
    // Wrap the disabled button in a span so the Tooltip trigger still
    // receives pointer events — `disabled` on a <button> swallows mouse
    // events in some browsers and the Radix Tooltip would never open.
    rightAffordance = (
      <Tooltip>
        <TooltipTrigger asChild>
          <span tabIndex={0} className="inline-flex">
            {plusButton}
          </span>
        </TooltipTrigger>
        <TooltipContent side="left">{disabledTooltip}</TooltipContent>
      </Tooltip>
    );
  } else if (resourceKind) {
    // Phase 62 Plan 62-08 Task 2 — popover-wrapped `+` button. The shared
    // ResourceCreationButton owns the popover lifecycle, the editor mount,
    // and the Esc-cascade-stop / non-dismiss / Pitfall-1 contracts.
    rightAffordance = (
      <ResourceCreationButton
        resourceKind={resourceKind}
        trigger={plusButton}
        onResourceCreated={onResourceCreated}
      />
    );
  } else {
    rightAffordance = plusButton;
  }

  return (
    <div className="flex items-center justify-between pl-[8px] pr-[4px] mt-[8px]">
      <div className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
        {label}
      </div>
      {rightAffordance}
    </div>
  );
}
