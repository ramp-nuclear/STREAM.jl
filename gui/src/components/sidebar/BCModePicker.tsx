// BCModePicker.tsx — Phase 63 Plan 63-C Task 02.
//
// 5-pill segmented BC mode picker (D-04 order: Value Profile Function Mark
// Source) with the D-09 required-unset visual: when `active === undefined`,
// NO pill is highlighted and a muted-destructive hint "BC required — select
// a mode" appears below the strip.
//
// The required-unset visual is inherited from SegmentedButtonGroup — when
// `active` is undefined, every option compares unequal, so every Button
// resolves to `variant="outline"` (no `default` highlight).
//
// Consumed by BCsTabForm (Task 03) per pair-group field (and per side when
// the symmetric toggle is OFF). Stateless — receives the current entry's
// `mode` discriminator from the parent and bubbles changes up via onChange.

import { Label } from "@/components/ui/label";
import SegmentedButtonGroup from "./SegmentedButtonGroup";
import type { BCMode } from "@/lib/bcMode";

interface BCModePickerProps {
  /** Field label, e.g. "T_wall_left[1:n]" or "T_wall" (symmetric base). */
  label: string;
  /** undefined = required-unset (D-09 sentinel-by-absence). */
  active: BCMode | undefined;
  onChange: (mode: BCMode) => void;
}

const BC_MODE_OPTIONS: Array<{ value: BCMode; label: string }> = [
  { value: "value", label: "Value" },
  { value: "profile", label: "Profile" },
  { value: "function", label: "Function" },
  { value: "mark", label: "Mark" },
  { value: "source", label: "Source" },
];

export default function BCModePicker({
  label,
  active,
  onChange,
}: BCModePickerProps) {
  return (
    <div className="flex flex-col gap-[6px]">
      <Label className="text-[13px] font-semibold leading-[1.4]">{label}</Label>
      <SegmentedButtonGroup
        options={BC_MODE_OPTIONS}
        active={active}
        onChange={onChange}
        size="sm"
      />
      {active === undefined && (
        <p className="text-xs text-destructive/80 mt-[6px]">
          BC required — select a mode
        </p>
      )}
    </div>
  );
}
