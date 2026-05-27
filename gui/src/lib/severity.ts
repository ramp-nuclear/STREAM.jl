// Phase 72 extract — single source of truth for the severity vocabulary
// (color CSS-var, Lucide icon, full-word label) consumed by ValidationPanel,
// ValidationStatusBar, PreferencesDialog, and CanvasPanel. Promoted from
// four parallel inline copies (two map literals + two inline ternaries).
//
// Severity ordering is intentional (error → warning → info): matches the
// validator runner's emission order and the panel's default sort.

import type { LucideIcon } from "lucide-react";
import { CircleX, Info, TriangleAlert } from "lucide-react";

export type Severity = "error" | "warning" | "info";

export const SEVERITY_ORDER: readonly Severity[] = ["error", "warning", "info"];

/** Lucide glyph used by the status-bar icon idiom (DESIGN.md §5
 *  "Status-Bar-Icons-Are-The-IDE-Convention" carve-out). */
export const SEVERITY_ICON: Record<Severity, LucideIcon> = {
  error: CircleX,
  warning: TriangleAlert,
  info: Info,
};

/** Lowercase full-word label used in ValidationPanel rows + filter pills.
 *  The panel uses full words (`error / warning / info`) where space allows;
 *  the status bar uses icons (no room for words). */
export const SEVERITY_LABEL: Record<Severity, string> = {
  error: "error",
  warning: "warning",
  info: "info",
};

/** CSS `var()` expression for each severity's locked color token. Pass
 *  through to `color`, `stroke`, `style={{ color: ... }}`, or as a CSS
 *  custom-property value. Resolves to `--destructive`, `--color-warning`,
 *  or `--color-info` (all WCAG AA on chrome/panel/canvas/popover/card per
 *  the Phase 72 harden pass). */
export const SEVERITY_COLOR_VAR: Record<Severity, string> = {
  error: "var(--destructive)",
  warning: "var(--color-warning)",
  info: "var(--color-info)",
};
