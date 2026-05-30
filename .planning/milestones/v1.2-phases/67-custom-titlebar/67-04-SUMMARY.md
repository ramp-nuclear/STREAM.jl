---
phase: 67
plan: 04
subsystem: gui
tags: [chrome, theming, tailwind-v4, shadcn]
requires: []
provides:
  - bg-chrome / bg-panel / bg-canvas Tailwind utilities (depth tier tokens)
  - Flat ghost-variant chrome menu triggers in CustomTitlebar
  - Borderless Layer ToggleGroup with subtle active-state fill
affects:
  - gui/src/index.css (added --chrome / --panel / --canvas tokens)
  - gui/src/App.tsx (left panel wrapper bg-panel)
  - gui/src/components/CustomTitlebar.tsx (bg-chrome)
  - gui/src/components/SecondaryToolbar.tsx (bg-chrome + ghost controls + borderless toggles)
  - gui/src/components/BottomPanel.tsx (bg-panel)
  - gui/src/components/CanvasPanel.tsx (bg-canvas)
  - gui/src/components/sidebar/SidebarPanel.tsx (bg-panel)
  - gui/src/components/FileMenu.tsx / EditMenu.tsx / ViewMenu.tsx / HelpMenu.tsx (ghost triggers, no chevrons)
tech-stack:
  added: []
  patterns:
    - "Tailwind v4 `@theme inline` block — generate utilities from --color-* tokens"
    - "shadcn variant=\"ghost\" for chrome controls"
key-files:
  created:
    - .planning/phases/67-custom-titlebar/67-04-SUMMARY.md
  modified:
    - gui/src/index.css
    - gui/src/App.tsx
    - gui/src/components/CustomTitlebar.tsx
    - gui/src/components/SecondaryToolbar.tsx
    - gui/src/components/BottomPanel.tsx
    - gui/src/components/CanvasPanel.tsx
    - gui/src/components/sidebar/SidebarPanel.tsx
    - gui/src/components/FileMenu.tsx
    - gui/src/components/EditMenu.tsx
    - gui/src/components/ViewMenu.tsx
    - gui/src/components/HelpMenu.tsx
decisions:
  - "Three semantic depth tokens (--chrome / --panel / --canvas) rather than repurposing existing --background/--card/--muted. The existing tokens are load-bearing for shadcn primitive styling (popovers, dialogs, tooltips, dropdown content); changing their luminance would visually shift every primitive in the app. New tokens isolate the chrome/panel/canvas layering from primitive theming."
  - "Dark-mode --canvas keeps oklch(0.24 0.012 254) — exactly the prior --background value — so all ReactFlow tuning (--xy-background-color, MiniMap colors, edge contrast checks from Phase 65/66) remains pixel-stable. Only --chrome and --panel introduce visible new shades."
  - "Layer toggle active state uses tint-only fills (blue-500/15, amber-500/15) instead of bordered outlines. The colored hue still communicates hydraulic vs thermal affordance, but without the boxed-control geometry that was making the chrome feel form-y."
  - "Code button uses ghost+bg-accent for its on state instead of variant=\"default\" (primary fill). Primary-fill on a chrome toggle was overpowering relative to the new flat chrome — bg-accent matches VSCode panel-toggle convention."
metrics:
  duration: "~35 min"
  completed: "2026-05-16"
---

# Phase 67 Plan 04: VSCode-Style Chrome Polish Summary

Gap-closure pass on Phase 67's custom titlebar — replaces the bordered
form-control look with flat ghost-variant chrome and a VSCode-style three-tier
depth hierarchy (chrome / panel / canvas) using same-hue luminance steps.

## Thread 1 — Three-tier depth tokens

Added three semantic CSS variables in `gui/src/index.css`, exposed as Tailwind
v4 utilities via the `@theme inline` block:

| Tier   | Token       | Utility      | Light                | Dark (oklch hue 254)     |
| ------ | ----------- | ------------ | -------------------- | ------------------------ |
| 1 (darkest) | `--chrome`  | `bg-chrome`  | `oklch(0.92 0 0)`    | `oklch(0.19 0.011 254)`  |
| 2 (mid)     | `--panel`   | `bg-panel`   | `oklch(0.97 0 0)`    | `oklch(0.215 0.012 254)` |
| 3 (lightest)| `--canvas`  | `bg-canvas`  | `oklch(1 0 0)`       | `oklch(0.24 0.012 254)`  |

Applied as:

- **Tier 1 (chrome):** `CustomTitlebar.tsx`, `SecondaryToolbar.tsx`
- **Tier 2 (panel):** App.tsx left-tabs wrapper, `sidebar/SidebarPanel.tsx`, `BottomPanel.tsx`
- **Tier 3 (canvas):** `CanvasPanel.tsx` outer container

Dark-mode `--canvas` (0.24) matches the prior `--background` exactly, so
ReactFlow, MiniMap, and per-node ring colors stay stable. Light-mode keeps a
neutral grayscale ramp; dark-mode preserves the One Dark Pro warm blue-grey
hue across all three tiers.

## Thread 2 — Ghost-variant chrome controls

- **Menu triggers (File / Edit / View / Help):** `variant="outline"` →
  `variant="ghost"`, chevron icons dropped, sized at `h-7 px-2 text-xs
  font-normal`. Hover background fills via shadcn's existing
  `hover:bg-accent`; no resting border.
- **Layer ToggleGroup (Hydraulic / Both / Thermal):** Wrapper border + rounded-md
  removed. Each item is `border-0 bg-transparent hover:bg-accent`; active state
  uses subtle `data-[state=on]:bg-{blue|accent|amber}` fills (no border outline).
- **Code button:** `variant="ghost"` + dynamic `bg-accent` when
  `bottomPanelOpen` (peer to View → Toggle Code Preview check).
- **Export button:** `variant="default"` (filled primary) → `variant="ghost"`
  so it sits flat alongside Code.
- **WindowControls Linux/Windows:** already ghost-variant; left as-is. Close
  still flips to `hover:bg-destructive` on hover.

## Commits

| Hash      | Type   | Description                                                                |
| --------- | ------ | -------------------------------------------------------------------------- |
| `f84c813` | style  | VSCode-style three-tier depth tokens (chrome/panel/canvas)                 |
| `9c6f8d7` | style  | Ghost-variant chrome controls (flat menu triggers, borderless toggles)     |
| (this)    | docs   | Plan 04 summary                                                            |

## Verification

- `cd gui && npm run build` → 12 TS errors. All in `StreamNode.tsx` (4),
  `BCsTabForm.test.tsx` (3), `SidebarRouter.test.tsx` (2), `validation.test.ts`
  (3) — none in files this plan touched. Baseline from STATE.md was 13; the
  delta is from pre-existing churn, not this plan. **No new errors introduced.**
- `cd gui && npm test` → 829 passed / 8 failed (pre-existing failures in
  `contextMenus.test.tsx`, `AppShell.test.tsx`, `SidebarPanel.anchors.test.tsx`).
  None of the failing tests reference the components or styling I touched
  (verified with `grep -l "FileMenu|EditMenu|ViewMenu|HelpMenu|SecondaryToolbar|Layer|Hydraulic|Thermal"` over each failing test file — no matches). The 1
  baseline failure called out in STATE.md is presumably one of these 8.

## Deviations from Plan

None — both threads landed exactly as scoped:

- 3 tokens (not 4), same hue across both modes, dark-canvas held at the prior
  background luminance.
- Menu triggers + Layer toggle + Code/Export all ghost-style; WindowControls
  Linux/Windows already ghost.
- macOS WindowControls branch (traffic lights) untouched per constraint.
- `decorations: false`, `snap_layout.rs`, menu CONTENT, dirty-dot logic — all
  untouched.

## Known Stubs

None.

## Self-Check: PASSED

- Files exist:
  - `gui/src/index.css` — modified (FOUND)
  - `gui/src/App.tsx` — modified (FOUND)
  - `gui/src/components/CustomTitlebar.tsx` — modified (FOUND)
  - `gui/src/components/SecondaryToolbar.tsx` — modified (FOUND)
  - `gui/src/components/BottomPanel.tsx` — modified (FOUND)
  - `gui/src/components/CanvasPanel.tsx` — modified (FOUND)
  - `gui/src/components/sidebar/SidebarPanel.tsx` — modified (FOUND)
  - `gui/src/components/FileMenu.tsx` — modified (FOUND)
  - `gui/src/components/EditMenu.tsx` — modified (FOUND)
  - `gui/src/components/ViewMenu.tsx` — modified (FOUND)
  - `gui/src/components/HelpMenu.tsx` — modified (FOUND)
- Commits exist: `f84c813` (FOUND), `9c6f8d7` (FOUND)
