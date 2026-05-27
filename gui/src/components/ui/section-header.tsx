import * as React from "react";

import { cn } from "@/lib/utils";

// Phase 72 extract — single source of truth for the chrome "section label"
// idiom locked in DESIGN.md §5: 10 px mono, uppercase, wide tracking,
// foreground/45. Promoted from 16 ad-hoc copies during the polish + retoken
// passes. Site-specific spacing (px-*, mb-*, mt-*, leading-*, truncate)
// flows through `className`; the base typographic identity is baked in.
//
// The AnatomyDialog tile-title variant (tracking-wider + foreground/55,
// inside dialog padding) is intentionally a different pattern and is NOT a
// SectionHeader.

type SectionHeaderTag = "div" | "span" | "h2" | "h3" | "h4";

interface SectionHeaderProps extends React.HTMLAttributes<HTMLElement> {
  as?: SectionHeaderTag;
}

function SectionHeader({
  as: Tag = "div",
  className,
  children,
  ...props
}: SectionHeaderProps) {
  return React.createElement(
    Tag,
    {
      "data-slot": "section-header",
      className: cn(
        "text-micro font-mono uppercase tracking-wide text-foreground/45",
        className,
      ),
      ...props,
    },
    children,
  );
}

export { SectionHeader };
