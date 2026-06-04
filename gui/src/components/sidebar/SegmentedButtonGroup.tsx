// SegmentedButtonGroup.tsx — Phase 63 Plan 63-C Task 01.
//
// Generic segmented-button primitive extracted verbatim from ModeToggle's
// internal layout (ModeToggle.tsx:28-46 — the horizontal-row JSX). Consumers:
//   1. ModeToggle (Pump fixed-dP / fixed-mdot picker; pre-existing).
//   2. BCsTabForm sub-pickers — Profile-preset, Function-signature, and the
//      Phase 63.1 D-12 Symmetric/Asymmetric segmented control (the legacy
//      5-pill BC mode picker was retired in Phase 63.1 Plan 07 in favor of
//      an inline shadcn Select).
//
// Generic over `T extends string` so each consumer can keep its discriminated
// union type without lossy stringification. When `active === undefined`, NO
// button receives the `variant="default"` highlight — every pill renders as
// `outline`.

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
