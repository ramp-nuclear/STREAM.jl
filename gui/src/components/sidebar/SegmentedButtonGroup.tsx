// SegmentedButtonGroup.tsx — Phase 63 Plan 63-C Task 01.
//
// Generic segmented-button primitive extracted verbatim from ModeToggle's
// internal layout (ModeToggle.tsx:28-46 — the horizontal-row JSX). Two
// consumers:
//   1. ModeToggle (Pump fixed-dP / fixed-mdot picker; pre-existing).
//   2. BCModePicker (5-pill BC mode picker; Phase 63-C Task 02).
//   3. BCsTabForm sub-pickers (Profile-preset, Function-signature; Task 03).
//
// Generic over `T extends string` so each consumer can keep its discriminated
// union type without lossy stringification. When `active === undefined`, NO
// button receives the `variant="default"` highlight — every pill renders as
// `outline`. This is the D-09 required-unset visual for the BCs tab; it's a
// free side-effect of the `variant={opt.value === active ? "default" : "outline"}`
// expression evaluating false for every opt when active is undefined.

import { Button } from "@/components/ui/button";

interface SegmentedButtonGroupProps<T extends string> {
  options: Array<{ value: T; label: string }>;
  /** undefined = no active pill (required-unset, D-09). All buttons render as outline. */
  active: T | undefined;
  onChange: (value: T) => void;
  size?: "sm" | "default";
  className?: string;
}

export default function SegmentedButtonGroup<T extends string>({
  options,
  active,
  onChange,
  size = "sm",
  className,
}: SegmentedButtonGroupProps<T>) {
  return (
    <div className={className ? `flex ${className}` : "flex"}>
      {options.map((opt, idx) => (
        <Button
          key={opt.value}
          variant={opt.value === active ? "default" : "outline"}
          size={size}
          className={
            idx === 0
              ? "rounded-r-none"
              : idx === options.length - 1
                ? "rounded-l-none"
                : "rounded-none"
          }
          onClick={() => onChange(opt.value)}
        >
          {opt.label}
        </Button>
      ))}
    </div>
  );
}
