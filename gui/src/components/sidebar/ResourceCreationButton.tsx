// ResourceCreationButton.tsx — Phase 62 Plan 62-08 Task 2.
//
// Shared mount of `<Popover>` + `<PopoverTrigger>` + the Resource editor
// inside `<ResourceCreationPopoverContent>`. Used by two consumers:
//
//   1. ResourceReferencePicker (field-level `+ New…`) — passes
//      `onResourceCreated` so the picker can auto-select the new UUID
//      (D-15 auto-select).
//   2. ResourceGroupHeader (Resources tab `+` per group) — typically passes
//      a no-op (the tree just re-renders with the new row); used via the
//      `ResourceGroupHeaderWithPopover` wrapper at the Resources-tab side.
//
// Centralising the popover wiring avoids duplicating the trigger ref +
// state management in both consumers and keeps the Esc/click-outside/focus
// contracts in one place. The trigger is rendered via `asChild` so the
// caller controls the visible button (label, variant, size, aria-label).

import * as React from "react";
import { Popover, PopoverTrigger } from "@/components/ui/popover";
import { ResourceCreationPopoverContent } from "./ResourceCreationPopover";
import GeometryResourceEditor, {
  type GeometrySubmitPayload,
} from "./GeometryResourceEditor";
import PowerShapeResourceEditor, {
  type PowerShapeSubmitPayload,
} from "./PowerShapeResourceEditor";
import useStore from "@/store/useStore";

export type ResourceKind = "geometry" | "powerShape";

export interface ResourceCreationButtonProps {
  resourceKind: ResourceKind;
  /**
   * The visible trigger element (e.g., `+ New…` button or group `+` icon).
   * The wrapper attaches the popover trigger via `asChild`. The trigger must
   * forward refs (use a real `<button>` or shadcn's `<Button>`).
   */
  trigger: React.ReactElement;
  /** Called with the new resource UUID after a successful Create. */
  onResourceCreated?: (uuid: string) => void;
}

export default function ResourceCreationButton({
  resourceKind,
  trigger,
  onResourceCreated,
}: ResourceCreationButtonProps) {
  const [open, setOpen] = React.useState(false);
  const triggerRef = React.useRef<HTMLElement>(null);

  const addGeometry = useStore((s) => s.addGeometry);
  const addPowerShape = useStore((s) => s.addPowerShape);

  // Wrap the consumer's trigger element with the ref so the popover
  // focus-return workaround (Pitfall 1) can reach it. Using
  // React.cloneElement keeps the trigger's visual semantics intact while
  // pinning our ref for the focus restore call after close.
  const triggerWithRef = React.cloneElement(
    trigger as React.ReactElement<{ ref?: React.Ref<HTMLElement> }>,
    {
      ref: triggerRef,
    },
  );

  function handleGeometrySubmit(payload: GeometrySubmitPayload) {
    try {
      const uuid = addGeometry({
        name: payload.name,
        kind: payload.kind,
        params: payload.params,
      });
      setOpen(false);
      onResourceCreated?.(uuid);
      // Pitfall 1 — restore focus to the trigger after Radix closes.
      setTimeout(() => triggerRef.current?.focus(), 0);
    } catch (err) {
      // The editor's local validation should have caught duplicates and
      // invalid identifiers. If the store still threw (e.g., race against
      // a concurrent create), surface it on the console — the user can
      // retry with a different name.
      console.error("[ResourceCreationButton] addGeometry failed:", err);
    }
  }

  function handlePowerShapeSubmit(payload: PowerShapeSubmitPayload) {
    try {
      const uuid = addPowerShape({
        name: payload.name,
        kind: payload.kind,
        params: payload.params,
      });
      setOpen(false);
      onResourceCreated?.(uuid);
      setTimeout(() => triggerRef.current?.focus(), 0);
    } catch (err) {
      console.error("[ResourceCreationButton] addPowerShape failed:", err);
    }
  }

  function handleCancel() {
    setOpen(false);
    setTimeout(() => triggerRef.current?.focus(), 0);
  }

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>{triggerWithRef}</PopoverTrigger>
      <ResourceCreationPopoverContent
        open={open}
        onOpenChange={setOpen}
        triggerRef={triggerRef}
      >
        {resourceKind === "geometry" ? (
          <GeometryResourceEditor
            mode="create"
            onSubmit={handleGeometrySubmit}
            onCancel={handleCancel}
          />
        ) : (
          <PowerShapeResourceEditor
            mode="create"
            onSubmit={handlePowerShapeSubmit}
            onCancel={handleCancel}
          />
        )}
      </ResourceCreationPopoverContent>
    </Popover>
  );
}
