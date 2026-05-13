// ResourceReferencePicker.tsx — Phase 62 Plan 62-08 Task 2.
//
// Single-row reference picker for a Resource-FK component parameter
// (geometry_ref / power_shape_ref). Layout per UI-SPEC §"Reference picker":
//
//   [ Select (grows-flex) ] [ + New… ] [ Edit… ]   gap-[8px]
//
// • Dropdown lists resources of the matching kind in creation order.
// • For Power Shape, the dropdown also renders the sentinel
//   `(leave unset — set in code)` as the fixed top entry, followed by
//   a `<SelectSeparator />`, then the user's named Power Shapes
//   (D-26 + UI-SPEC §"Power Shape picker — extra fixed top entry";
//   sentinel copy updated in 62-15 per VERIFICATION.md Gap #4).
// • Empty-state copy (no resources of this kind yet) is rendered as the
//   `<SelectValue>` placeholder — single line, italic, truncate. Copy
//   rewritten in 62-15 to engineering-tool voice (VERIFICATION.md Gap #4):
//   `No geometries. Use + New or the Resources tab.`
//   / `No power shapes. Use + New or the Resources tab.`
// • `+ New…` mounts `ResourceCreationButton` which hosts the popover with
//   the contract enforced by `ResourceCreationPopoverContent` (D-15, D-16,
//   Esc-cascade-stop, Pitfall 1 focus return). On Create, the new UUID is
//   auto-selected via `onChange` (D-15 auto-select).
// • `Edit…` per D-18: switches the left tab to `Resources`, selects the
//   row, right Properties panel re-renders as the resource editor (the
//   right-panel router is wired in 62-09). The button is disabled when
//   the picker has no current selection OR is on the unset sentinel
//   (UI-SPEC §"Edit… disabled rules" + disabled-tooltip
//   `Pick a resource first.` — rewritten in 62-15 per VERIFICATION.md Gap #4).

import { useMemo } from "react";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectSeparator,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import ResourceCreationButton from "./ResourceCreationButton";
import useStore, { SENTINEL_UNSET_POWER_SHAPE } from "@/store/useStore";

export type PickerResourceKind = "geometry" | "powerShape";

export interface ResourceReferencePickerProps {
  resourceKind: PickerResourceKind;
  value: string | null;
  onChange: (uuid: string | null) => void;
}

export default function ResourceReferencePicker({
  resourceKind,
  value,
  onChange,
}: ResourceReferencePickerProps) {
  const geometries = useStore((s) => s.resources.geometries);
  const powerShapes = useStore((s) => s.resources.powerShapes);
  const selectResource = useStore((s) => s.selectResource);
  const setActiveLeftTab = useStore((s) => s.setActiveLeftTab);

  // Per-kind data + verbatim copy (UI-SPEC §"Reference picker" empty-state copy).
  const isGeometry = resourceKind === "geometry";
  const emptyCopy = isGeometry
    ? "No geometries. Use + New or the Resources tab."
    : "No power shapes. Use + New or the Resources tab.";

  // Build the list of selectable resources. For power shapes, prepend the
  // sentinel as the fixed top entry per D-26, then a separator, then user
  // shapes. For geometries, no sentinel — straight creation-order list.
  const userResources = useMemo(() => {
    if (isGeometry) {
      return Object.values(geometries).map((g) => ({
        uuid: g.uuid,
        name: g.name,
      }));
    }
    return Object.values(powerShapes)
      .filter((p) => p.uuid !== SENTINEL_UNSET_POWER_SHAPE)
      .map((p) => ({ uuid: p.uuid, name: p.name }));
  }, [isGeometry, geometries, powerShapes]);

  const hasNoResources = isGeometry && userResources.length === 0;

  // Edit… disabled when:
  //   - picker has no selection (null / empty / power-shape sentinel), OR
  //   - value is a dangling reference (UUID points to a resource that no
  //     longer exists, typically because the user deleted it from the
  //     Resources tree). The Select trigger already falls back to the
  //     placeholder UI in that case; the Edit button must follow suit or
  //     clicking it routes the user to a non-existent resource.
  const valueResolvesToResource =
    value != null &&
    value !== "" &&
    value !== SENTINEL_UNSET_POWER_SHAPE &&
    userResources.some((r) => r.uuid === value);
  const isEditDisabled = !valueResolvesToResource;

  function handleEdit() {
    if (isEditDisabled || value == null) return;
    // D-18: switch left tab + select the row. Right panel re-renders in 62-09.
    selectResource(value, resourceKind);
    setActiveLeftTab("Resources");
  }

  function handleSelectChange(v: string) {
    // Treat empty string as "no selection" — Radix Select doesn't allow
    // null values, but the consumer's parameters store accepts null.
    onChange(v === "" ? null : v);
  }

  // Trigger button for the `+ New…` mount inside ResourceCreationButton.
  // We use a real `<Button>` with `variant="outline" size="sm"` per UI-SPEC.
  // `shrink-0` keeps the button at its intrinsic width when the row wraps —
  // see plan 62-12 (close VERIFICATION.md Critical Gap #1).
  const newButtonTrigger = (
    <Button variant="outline" size="sm" className="shrink-0">
      + New…
    </Button>
  );

  return (
    // 62-12: `flex-wrap` lets the row break onto a second visual row when the
    // sidebar inner width (≈280-300px at the App.tsx default of 320px, ≈180px
    // at the 200px min) cannot fit Select + `+ New…` + `Edit…` in a single
    // line. Combined with `basis-full sm:basis-0` on the Select wrapper this
    // pins the wrap branch under the sidebar's real width range and keeps
    // both buttons fully visible. See VERIFICATION.md Critical Gap #1.
    <div className="flex flex-wrap items-center gap-[6px] min-w-0">
      <div className="flex-1 min-w-0 basis-full sm:basis-0">
        <Select
          value={value ?? ""}
          onValueChange={handleSelectChange}
        >
          <SelectTrigger size="sm" className="w-full">
            {hasNoResources ? (
              // Empty-state placeholder copy — italic + truncated single line
              // per UI-SPEC §"Empty-state style". Rendered as the trigger
              // child directly because Radix's `placeholder` would only
              // render when value is empty AND no item matches; passing it
              // through here keeps the empty-state copy stable even when
              // the user hovers the dropdown.
              <span className="text-[14px] italic text-muted-foreground truncate">
                {emptyCopy}
              </span>
            ) : (
              <SelectValue
                placeholder={
                  <span className="text-[14px] italic text-muted-foreground truncate">
                    {emptyCopy}
                  </span>
                }
              />
            )}
          </SelectTrigger>
          <SelectContent>
            {/* Power Shape sentinel + separator (D-26). */}
            {!isGeometry && (
              <>
                <SelectItem value={SENTINEL_UNSET_POWER_SHAPE}>
                  <span className="italic text-muted-foreground">
                    (leave unset — set in code)
                  </span>
                </SelectItem>
                {userResources.length > 0 && <SelectSeparator />}
              </>
            )}
            {userResources.map((r) => (
              <SelectItem key={r.uuid} value={r.uuid}>
                {r.name}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      <ResourceCreationButton
        resourceKind={resourceKind}
        trigger={newButtonTrigger}
        onResourceCreated={(uuid) => onChange(uuid)}
      />

      {isEditDisabled ? (
        <Tooltip>
          <TooltipTrigger asChild>
            {/* 62-12: `shrink-0` on the span wrapper keeps the disabled-Edit
                button at intrinsic width when the row wraps. The wrapper
                <span> is the flex item, not the inner <Button>. */}
            <span tabIndex={0} className="inline-flex shrink-0">
              <Button variant="outline" size="sm" disabled>
                Edit…
              </Button>
            </span>
          </TooltipTrigger>
          <TooltipContent>Pick a resource first.</TooltipContent>
        </Tooltip>
      ) : (
        <Button
          variant="outline"
          size="sm"
          className="shrink-0"
          onClick={handleEdit}
        >
          Edit…
        </Button>
      )}
    </div>
  );
}
