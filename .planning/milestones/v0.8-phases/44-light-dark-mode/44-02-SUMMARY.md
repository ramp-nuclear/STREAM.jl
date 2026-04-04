---
phase: 44-light-dark-mode
plan: 02
subsystem: ui
tags: [react, tailwind, dark-mode, reactflow, one-dark-pro, shadcn]

# Dependency graph
requires:
  - phase: 44-01
    provides: useTheme hook, ThemeMenu dropdown, resolvedTheme prop plumbed to CanvasPanel
  - phase: 43-ui-polish
    provides: Toolbar right section, shadcn/ui components, index.css with :root and .dark CSS variable token sets
provides:
  - ReactFlow colorMode prop wired to active theme
  - Background dot color overriding via inline --xy-background-color and color prop
  - One Dark Pro palette applied to canvas, panels, sidebar, and text tokens
  - Layer toggle items legible in dark mode via dark: variant overrides
affects: [any future phase touching CanvasPanel.tsx or Toolbar.tsx]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "colorMode prop on ReactFlow component is the canonical way to switch Controls/MiniMap to dark styling"
    - "Override --xy-background-color inline on <ReactFlow> to force canvas background (Tailwind dark: class does not reach the xyflow CSS var)"
    - "One Dark Pro palette: canvas #282c34, panels #2c313a, sidebar #21252b, text #abb2bf, dots #4b5263"
    - "dark:data-[state=on]: Tailwind variants fix shadcn ToggleGroupItem active-state contrast in dark mode"

key-files:
  created: []
  modified:
    - gui/src/components/CanvasPanel.tsx
    - gui/src/components/HydraulicEdge.tsx
    - gui/src/index.css

key-decisions:
  - "One Dark Pro palette chosen over Tailwind slate defaults for canvas and panel backgrounds — more contrast-balanced for engineering tool aesthetics"
  - "canvas background override via inline style on ReactFlow rather than CSS var in index.css — Tailwind dark: cannot target xyflow CSS vars injected by the ReactFlow package"

patterns-established:
  - "ReactFlow theming: colorMode prop + inline --xy-background-color override + Background color prop — three touch points required"

requirements-completed: [SC-4, SC-5]

# Metrics
duration: ~15min
completed: 2026-04-04
---

# Phase 44 Plan 02: ReactFlow Dark Mode Integration Summary

**ReactFlow canvas wired to theme via colorMode prop with One Dark Pro palette overrides; layer toggle dark contrast fixed via dark:data- Tailwind variants**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-04-03T23:30:00Z
- **Completed:** 2026-04-04T00:00:00Z
- **Tasks:** 2 (1 auto + 1 human-verify checkpoint)
- **Files modified:** 3

## Accomplishments
- ReactFlow `colorMode` prop set from `resolvedTheme`, enabling built-in dark styling for Controls and MiniMap
- Canvas background override applied via `--xy-background-color` inline style and `<Background color>` prop — standard CSS dark: class cannot reach ReactFlow's internal CSS variables
- One Dark Pro palette applied throughout: canvas `#282c34`, panels `#2c313a`, sidebar `#21252b`, text `#abb2bf`, grid dots `#4b5263`
- Layer toggle ToggleGroupItems given `dark:data-[state=on]:` Tailwind overrides so Hydraulic/Both/Thermal labels remain legible in dark mode
- Visual checkpoint passed: all surfaces correct in both light and dark themes

## Task Commits

1. **Task 1: Add ReactFlow colorMode and Background color, fix layer toggle dark contrast** - `91cc462` (feat)
2. **Task 1 (theme refinement): One Dark Pro palette + canvas color fix** - `d241a34` (feat)

**Plan metadata:** (docs commit follows this summary)

## Files Created/Modified
- `gui/src/components/CanvasPanel.tsx` - colorMode prop on ReactFlow, --xy-background-color inline override, Background color prop, One Dark Pro canvas background
- `gui/src/components/HydraulicEdge.tsx` - dark mode edge color adjustments
- `gui/src/index.css` - One Dark Pro CSS variable palette for panels, sidebar, text, and dot grid

## Decisions Made
- One Dark Pro palette over Tailwind slate defaults: the slate grays were too warm/light for an engineering tool with technical content; One Dark Pro is widely used in developer tooling and has battle-tested contrast ratios.
- Canvas background override strategy: ReactFlow injects `--xy-background-color` as an inline CSS variable on the `.react-flow` element, which is not reachable via Tailwind's `.dark` class selector in `index.css`. The only reliable override is setting it inline on the `<ReactFlow>` component itself.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Canvas background stayed white in dark mode despite Tailwind .dark class**
- **Found during:** Task 1 (after initial colorMode implementation)
- **Issue:** Adding `colorMode="dark"` to ReactFlow changed Controls/MiniMap but canvas background remained white; `--xy-background-color` is injected inline by ReactFlow and Tailwind `.dark` CSS selectors cannot override it
- **Fix:** Added `style={{ "--xy-background-color": resolvedTheme === "dark" ? "#282c34" : "#ffffff" } as React.CSSProperties}` inline on the ReactFlow component; also replaced default dark dot color with One Dark Pro `#4b5263`
- **Files modified:** gui/src/components/CanvasPanel.tsx, gui/src/index.css
- **Verification:** Visual inspection — canvas background matched panel colors in dark mode
- **Committed in:** d241a34

---

**Total deviations:** 1 auto-fixed (1 bug — ReactFlow CSS variable scoping)
**Impact on plan:** Necessary fix for the primary goal of the plan. No scope creep.

## Issues Encountered
- ReactFlow's `--xy-background-color` CSS variable is injected as an inline style at the `.react-flow` root element level, making it impossible to override via external CSS (including Tailwind's `.dark` class). Required inline style approach on the React component.

## User Setup Required
None - no external service configuration required.

## Known Stubs

None — both light and dark themes are fully functional. All surfaces adapt correctly and the visual checkpoint was approved.

## Next Phase Readiness
- Phase 44 is now complete (both plans done)
- All v0.8 STREAM Composer GUI phases complete
- v0.8 milestone ready for shipping

---
*Phase: 44-light-dark-mode*
*Completed: 2026-04-04*
