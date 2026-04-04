---
phase: 38-ui-design-pass
plan: 01
subsystem: ui
tags: [lucide-react, tailwind, react, icons, visual-differentiation]

# Dependency graph
requires:
  - phase: 34-gui-foundation
    provides: StreamNode, ToolboxItem, component registry
provides:
  - COMPONENT_ICONS map (12 components to Lucide icons)
  - getCategoryBorderClass for Hydraulic/Thermal color coding
  - Visually differentiated canvas nodes with icon + category border stripe
  - Toolbox items with matching component icons
affects: [38-02-PLAN, 38-03-PLAN]

# Tech tracking
tech-stack:
  added: []
  patterns: [single-source-of-truth icon map, full-literal Tailwind class strings for JIT]

key-files:
  created: [gui/src/registry/icons.ts, gui/src/registry/__tests__/icons.test.ts]
  modified: [gui/src/components/StreamNode.tsx, gui/src/components/ToolboxItem.tsx, gui/src/components/__tests__/StreamNode.test.tsx]

key-decisions:
  - "COMPONENT_ICONS is a Record<string, LucideIcon> in registry/icons.ts, single source of truth for both canvas and toolbox"
  - "CATEGORY_BORDER_CLASSES uses full literal Tailwind strings (not dynamic construction) to avoid JIT scanning issues"

patterns-established:
  - "Icon map pattern: all component visual identity flows from registry/icons.ts"
  - "Category color pattern: border-l-[3px] with CATEGORY_BORDER_CLASSES lookup"

requirements-completed: [DSGN-03, DSGN-04]

# Metrics
duration: 2min
completed: 2026-04-03
---

# Phase 38 Plan 01: Component Icons & Category Color Summary

**Lucide icon map for all 12 STREAM components with blue/amber category border stripes on canvas nodes and matching icons in toolbox**

## Performance

- **Duration:** 2 min
- **Started:** 2026-04-02T22:50:48Z
- **Completed:** 2026-04-02T22:52:56Z
- **Tasks:** 1 (TDD: RED + GREEN)
- **Files modified:** 5

## Accomplishments
- Created `icons.ts` with COMPONENT_ICONS map covering all 12 STREAM components (Channel, ChannelAndContacts, ChannelHeatFlux, Pump, Flapper, Friction, Gravity, Resistor, Inertia, HeatExchanger, ConstantTemperature, HeatDiffusion)
- StreamNode now displays 3px left border stripe (blue-500 for Hydraulic, amber-500 for Thermal) and inline Lucide icon next to component type label
- ToolboxItem now displays matching Lucide icon before label text
- 15 tests pass (9 icon map tests + 6 StreamNode tests including 3 new visual tests)

## Task Commits

Each task was committed atomically (TDD):

1. **Task 1 RED: Failing tests for icon map and StreamNode visual differentiation** - `10a2609` (test)
2. **Task 1 GREEN: Implement icon map, StreamNode border+icon, ToolboxItem icon** - `f8dcfde` (feat)

## Files Created/Modified
- `gui/src/registry/icons.ts` - COMPONENT_ICONS map, FALLBACK_ICON, getComponentIcon, CATEGORY_BORDER_CLASSES, getCategoryBorderClass
- `gui/src/registry/__tests__/icons.test.ts` - 9 tests covering icon map completeness, fallback, and category border classes
- `gui/src/components/StreamNode.tsx` - Added icon + 3px left border stripe with category color
- `gui/src/components/ToolboxItem.tsx` - Added matching Lucide icon before label
- `gui/src/components/__tests__/StreamNode.test.tsx` - Added 3 new tests (Hydraulic border, Thermal border, SVG icon)

## Decisions Made
- COMPONENT_ICONS is a Record<string, LucideIcon> in registry/icons.ts, single source of truth for both canvas and toolbox
- CATEGORY_BORDER_CLASSES uses full literal Tailwind strings (not dynamic construction) to avoid JIT scanning issues
- StreamNode test queries use querySelector for class presence rather than firstElementChild traversal (more robust against DOM wrapper changes)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed StreamNode test DOM traversal**
- **Found during:** Task 1 GREEN phase
- **Issue:** Test used `container.firstElementChild?.firstElementChild` which pointed to inner label div, not the node container with border classes
- **Fix:** Changed to `container.querySelector(".border-l-blue-500")` / `.border-l-amber-500` pattern
- **Files modified:** gui/src/components/__tests__/StreamNode.test.tsx
- **Verification:** All 15 tests pass
- **Committed in:** f8dcfde (Task 1 GREEN commit)

---

**Total deviations:** 1 auto-fixed (1 bug in test assertion)
**Impact on plan:** Minor test selector adjustment. No scope creep.

## Issues Encountered
None

## Known Stubs
None - all 12 components have icons, both categories have border classes.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Icon map and category color system ready for Plan 02 (panel collapse/resize) and Plan 03 (shadcn audit)
- COMPONENT_ICONS can be extended when new components are added to the registry

---
*Phase: 38-ui-design-pass*
*Completed: 2026-04-03*
