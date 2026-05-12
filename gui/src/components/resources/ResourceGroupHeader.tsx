import { Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@/components/ui/tooltip";

// Phase 62 Plan 62-06 — Resources tab tree group header (D-03, CD-01).
//
// One row per group: uppercase label on the left + 16x16 `+` icon button on
// the right. The `+` button opens the same `+ New…` popover used by the
// field-level reference picker (62-08). For this plan, 62-08's popover is
// not yet implemented, so the `+ button` is wired to a stub via the
// `onAdd` prop the caller supplies (in 62-06 a console.log; the seam is
// documented in the plan's `<integration_seam_for_popover_creation>`).
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
  /** Click handler for the `+` button. */
  onAdd: () => void;
  /** When true, the `+` button is rendered disabled (Fluids only in Phase 62). */
  disabled?: boolean;
  /** Tooltip text shown when hovering the disabled `+` button. */
  disabledTooltip?: string;
}

export default function ResourceGroupHeader({
  label,
  addAriaLabel,
  onAdd,
  disabled = false,
  disabledTooltip,
}: ResourceGroupHeaderProps) {
  const addButton = (
    <Button
      variant="ghost"
      size="icon-xs"
      aria-label={addAriaLabel}
      disabled={disabled}
      onClick={onAdd}
    >
      <Plus className="h-4 w-4" />
    </Button>
  );

  return (
    <div className="flex items-center justify-between pl-[8px] pr-[4px] mt-[8px]">
      <div className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
        {label}
      </div>
      {disabled && disabledTooltip ? (
        // Wrap the disabled button in a span so the Tooltip trigger still
        // receives pointer events — `disabled` on a <button> swallows mouse
        // events in some browsers and the Radix Tooltip would never open.
        <Tooltip>
          <TooltipTrigger asChild>
            <span tabIndex={0} className="inline-flex">
              {addButton}
            </span>
          </TooltipTrigger>
          <TooltipContent side="left">{disabledTooltip}</TooltipContent>
        </Tooltip>
      ) : (
        addButton
      )}
    </div>
  );
}
