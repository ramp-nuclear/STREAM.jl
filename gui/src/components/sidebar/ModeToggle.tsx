// ModeToggle.tsx — Pump fixed-dP / fixed-mdot picker.
//
// Phase 63 Plan 63-C Task 01: refactored to delegate the segmented-button
// rendering to the new generic `SegmentedButtonGroup<T>` primitive (extracted
// from this file's own internals). The external API of ModeToggle is preserved
// exactly so existing call sites (SidebarPanel component branch) keep working.
//
// What used to live here as inline JSX is now an option-array mapping +
// delegation. The `MODE_LABELS` dictionary still lives here because it's
// specific to ConstructorMode strings (`fixed-dP` etc.).

import { Label } from "@/components/ui/label";
import SegmentedButtonGroup from "./SegmentedButtonGroup";
import type { ConstructorMode } from "@/registry/types";

interface ModeToggleProps {
  modes: ConstructorMode[];
  activeMode: string;
  onChange: (mode: string) => void;
}

const MODE_LABELS: Record<string, string> = {
  "fixed-dP": "Fixed dP",
  "fixed-mdot": "Fixed mdot",
};

function modeLabel(mode: string): string {
  return MODE_LABELS[mode] ?? mode;
}

export default function ModeToggle({
  modes,
  activeMode,
  onChange,
}: ModeToggleProps) {
  const options = modes.map((m) => ({
    value: m.mode,
    label: modeLabel(m.mode),
  }));
  return (
    <div className="flex flex-col gap-[8px]">
      <Label className="text-[13px] font-semibold leading-[1.4]">Mode</Label>
      <SegmentedButtonGroup
        options={options}
        active={activeMode}
        onChange={onChange}
        size="sm"
      />
    </div>
  );
}
