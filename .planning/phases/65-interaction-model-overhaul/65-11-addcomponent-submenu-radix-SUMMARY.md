---
phase: 65-interaction-model-overhaul
plan: 11
subsystem: ui
tags: [context-menu, submenu, radix, dropdown-menu, floating-ui, gap-closure, phase-65]

requires:
  - phase: 65-interaction-model-overhaul
    provides: "Plan 05 PopoverMenuSub* hand-rolled submenu primitives (replaced here)"
provides:
  - "Radix DropdownMenu.Sub wiring for AddComponent canvas submenus with viewport-collision-aware placement"
  - "Removal of dead PopoverMenuSub / PopoverMenuSubTrigger / PopoverMenuSubContent / PopoverMenuSubContext from context-menu.tsx"
  - "Regression test (AddComponentSubmenu.test.tsx) covering category SubTriggers and addNode wiring"
affects: [canvas-context-menu, AddComponentSubmenu, CanvasContextMenu, dropdown-menu, context-menu]

tech-stack:
  added: []  # @radix-ui/react-dropdown-menu was already a transitive dep via radix-ui bundle (no new package)
  patterns:
    - "Nested Radix DropdownMenu inside Popover host (DropdownMenu owns its own root context, Popover only owns outer dismiss)"
    - "DropdownMenu defaultOpen={true} + onOpenChange propagation as close-bridge from inner dropdown to outer Popover"

key-files:
  created:
    - "gui/src/components/canvasMenus/__tests__/AddComponentSubmenu.test.tsx"
  modified:
    - "gui/src/components/ui/dropdown-menu.tsx (added Plan 11 header comment — already exported all 9 required primitives)"
    - "gui/src/components/ui/context-menu.tsx (removed PopoverMenuSub*, kept PopoverMenuItem / PopoverMenuSeparator)"
    - "gui/src/components/canvasMenus/CanvasContextMenu.tsx (Add Component now hosted in Radix DropdownMenu)"
    - "gui/src/components/canvasMenus/AddComponentSubmenu.tsx (emits DropdownMenuSub / SubTrigger / SubContent per category)"

key-decisions:
  - "Reused existing dropdown-menu.tsx shim (already exported all 9 documented primitives) instead of overwriting it; only added the Plan 11 file-header comment."
  - "Used DropdownMenu defaultOpen={true} + onOpenChange (preferred per plan §3) rather than open={true} (forced uncontrolled) — closure of inner dropdown now propagates to outer Popover via onClose()."
  - "Wrapped DropdownMenuSubContent in DropdownMenuPortal in AddComponentSubmenu so SubContent portals to body (escapes Popover host overflow + correct stacking)."

patterns-established:
  - "Nested Radix DropdownMenu inside Popover content: DropdownMenu defaultOpen={true} with onOpenChange={(open)=>{if(!open)onClose()}} bridges the two root contexts; DropdownMenu owns its own dismissable-layer behavior."
  - "Test pattern for DropdownMenu.Sub components: wrap the system under test in <DropdownMenu defaultOpen><DropdownMenuContent>{ui}</DropdownMenuContent></DropdownMenu> to satisfy SubTrigger's MenuContentContext requirement."

requirements-completed: []  # Plan frontmatter requirements: [] — gap-closure plan, no requirement IDs.

duration: 5min
completed: 2026-05-15
---

# Phase 65 Plan 11: AddComponent submenu Radix swap Summary

**Hand-rolled PopoverMenuSub* (W10 workaround from Plan 65-05) replaced with Radix DropdownMenu.Sub, giving the Add Component canvas submenus Floating-UI viewport-collision flipping that they were missing.**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-05-15T14:46:30Z
- **Completed:** 2026-05-15T14:51:00Z
- **Tasks:** 2 (Task 1 = primitive swap, Task 2 = regression test)
- **Files modified:** 4
- **Files created:** 1

## Accomplishments

- Submenus from "Add Component" near the right edge of the viewport now flip left instead of clipping offscreen — Radix DropdownMenuSubContent ships with Floating UI's `flip()` + `shift()` middleware by default (closes UAT Test 13).
- `gui/src/components/ui/context-menu.tsx` reduced by ~80 lines (deleted four functions + a private context). Public surface now: PopoverMenuItem, PopoverMenuSeparator + the standard shadcn ContextMenu* exports.
- New regression test `AddComponentSubmenu.test.tsx` (2 cases) guards the primitive swap: (1) one `DropdownMenuSubTrigger` rendered per registry category, (2) leaf click invokes `useStore.getState().addNode(componentId, flowPosition)` and `onClose()` exactly once.
- No new tsc errors (12 → 12, baseline preserved). All canvasMenus vitests pass (6/6).

## Task Commits

Each task was committed atomically:

1. **Task 1: dropdown-menu shim header + primitive swap** — `bb48ba5` (fix)
2. **Task 2: AddComponentSubmenu regression test** — `72cf7ff` (test)

## Files Created/Modified

- `gui/src/components/ui/dropdown-menu.tsx` (modified) — added Plan 11 file-header comment; already exported `DropdownMenu`, `DropdownMenuTrigger`, `DropdownMenuPortal`, `DropdownMenuContent`, `DropdownMenuItem`, `DropdownMenuSub`, `DropdownMenuSubTrigger`, `DropdownMenuSubContent`, `DropdownMenuSeparator` (+ Group/Label/Checkbox/Radio/Shortcut beyond plan minimums).
- `gui/src/components/ui/context-menu.tsx` (modified) — deleted `PopoverMenuSub`, `PopoverMenuSubTrigger`, `PopoverMenuSubContent`, and the private `PopoverMenuSubContext` (~80 LOC). Replaced docblock with a Plan 11 removal note. `PopoverMenuItem` / `PopoverMenuSeparator` retained — still used by Paste/Auto-Layout rows of CanvasContextMenu and by NodeContextMenu / EdgeContextMenu (untouched).
- `gui/src/components/canvasMenus/CanvasContextMenu.tsx` (modified) — Add Component row now wrapped in `<DropdownMenu defaultOpen={true} onOpenChange={(open) => { if (!open) onClose(); }}>` + `DropdownMenuTrigger asChild` (row markup with role="menuitem", `<ChevronRightIcon className="ml-auto size-4">`) + `DropdownMenuPortal` + `DropdownMenuContent side="right" align="start" sideOffset={4}` containing `<AddComponentSubmenu …>`. Paste / Auto-Layout / Separator unchanged (still `PopoverMenuItem` / `PopoverMenuSeparator`).
- `gui/src/components/canvasMenus/AddComponentSubmenu.tsx` (modified) — emits `DropdownMenuSub` per category, with `DropdownMenuSubTrigger` (category name) + `DropdownMenuPortal` + `DropdownMenuSubContent` + per-component `DropdownMenuItem` (onSelect calls `e.preventDefault?.()` then `addNode` + `onClose`). Memoized grouping logic and registry sort unchanged.
- `gui/src/components/canvasMenus/__tests__/AddComponentSubmenu.test.tsx` (created) — vitest happy-dom suite, wraps the submenu in a parent `<DropdownMenu defaultOpen>` to satisfy Radix Sub context. Two test cases (see Accomplishments above).

## Decisions Made

- **Reused the existing `dropdown-menu.tsx` shim** rather than overwriting it. Discovery: the shim was already present in the project (pre-Plan-11) with all 9 required exports + extras (Group/Label/Checkbox/Radio/Shortcut). Replacing it would have churned unrelated callers in `Toolbar.tsx`, `BCControl.tsx`, etc. The plan's Step 1 reduced to a one-line header-comment update.
- **`defaultOpen={true}` + `onOpenChange` rather than forced `open={true}`** — preferred path called out in Plan §3 "PREFERRED". Closing the inner dropdown (Esc / outside click) now propagates closure to the outer Popover host via `onClose`. Forced `open={true}` would have made the inner dropdown un-dismissable from inside.
- **`DropdownMenuPortal` wraps each `DropdownMenuSubContent`** in AddComponentSubmenu. This portals SubContent to `document.body`, escaping the Popover host's `overflow:hidden` and any stacking-context issues from the canvas/Reactflow ancestors.
- **Test does not assert viewport-flip placement.** Floating-UI's flip() is Radix's responsibility and is exercised by the manual UAT Test 13 re-run — automating it in jsdom/happy-dom would require simulating real viewport measurements, which the test environment doesn't provide reliably.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] Ran `npm install` in fresh worktree before pre-flight check**
- **Found during:** Task 1 pre-flight (`ls gui/node_modules/@radix-ui/react-dropdown-menu/dist/index.d.ts`)
- **Issue:** Fresh worktree had no `gui/node_modules/` (parallel executor was spawned with a clean worktree per `<parallel_execution>` note in the prompt). Pre-flight would have failed despite the package being declared as a transitive dep via the `radix-ui` umbrella package.
- **Fix:** Ran `npm install` from `gui/` once. After install, `gui/node_modules/@radix-ui/react-dropdown-menu/dist/index.d.ts` existed — the plan's environmental assumption was satisfied.
- **Files modified:** none committed (node_modules is gitignored).
- **Verification:** `ls gui/node_modules/@radix-ui/react-dropdown-menu/dist/index.d.ts` → file exists.
- **Note:** This was explicitly allowed by the parallel_execution note: "In a fresh worktree, run `npm install` from `gui/` once before building/testing if not already installed in the worktree's gui/node_modules." Not a deviation in the strict sense, but logged here for traceability.

**2. [Reused-not-overwritten] dropdown-menu.tsx shim already existed**
- **Found during:** Task 1 Step 1.
- **Issue:** Plan §1 said "Create a new shadcn-style shim `gui/src/components/ui/dropdown-menu.tsx`." The file already existed and already exported all 9 documented primitives (plus extras).
- **Fix:** Treated Step 1 as a verify-and-annotate operation — added only the Plan 11 header comment, left the existing implementation intact. All required exports verified present.
- **Files modified:** `gui/src/components/ui/dropdown-menu.tsx` (one-line header added).
- **Verification:** `grep -E '^(export \\{|  DropdownMenu)' gui/src/components/ui/dropdown-menu.tsx` confirms the 9 names. tsc clean.

**3. [Documentation] Pre-existing tsc baseline is 12, not 11**
- **Found during:** Task 1 verify step (capture pre-edit tsc count).
- **Issue:** Plan referenced "the pre-existing 11 tsc errors (Phase 71 owns them per STATE.md)". Measured count on the worktree base (commit `0293a68`) is 12.
- **Fix:** Adopted the measured baseline as the not-to-exceed threshold (post-edit count must remain ≤ 12). Post-edit count is 12 — preserved exactly.
- **Files modified:** none.
- **Verification:** `cd gui && npx tsc --noEmit 2>&1 | grep -c "error TS"` → 12 (before) and 12 (after).

---

**Total deviations:** 3 (all benign — 1 expected npm install, 1 reused existing artifact, 1 baseline correction). No new code paths added beyond the plan's intent.
**Impact on plan:** None — all original objectives met. Shim reuse reduced churn on unrelated callers (`Toolbar.tsx` etc.). Baseline correction is bookkeeping, not behavioral.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Manual UAT Recommendation (not gating, but the actual closure for UAT Test 13)

In Tauri dev, right-click near the right edge of the canvas → hover **Add Component** → hover any category. The per-category submenu should now be fully visible (flipped to the LEFT of the trigger when the right edge is too close). Before this plan, only a thin sliver was visible.

## Self-Check: PASSED

- File `gui/src/components/ui/dropdown-menu.tsx` exists — FOUND.
- File `gui/src/components/ui/context-menu.tsx` exists — FOUND.
- File `gui/src/components/canvasMenus/CanvasContextMenu.tsx` exists — FOUND.
- File `gui/src/components/canvasMenus/AddComponentSubmenu.tsx` exists — FOUND.
- File `gui/src/components/canvasMenus/__tests__/AddComponentSubmenu.test.tsx` exists — FOUND.
- Commit `bb48ba5` exists — FOUND.
- Commit `72cf7ff` exists — FOUND.
- `grep PopoverMenuSub gui/src --include='*.tsx'` returns only file-header comments, no consumers — VERIFIED.
- tsc error count: 12 (== baseline) — VERIFIED.
- canvasMenus vitest: 6/6 passing — VERIFIED.

## Next Phase Readiness

- UAT Test 13 (canvas Add Component submenu placement) is unblocked. A manual re-run is recommended.
- Other Phase 65 plans in the gap-closure wave (Plans 09, 10, 12, 13, 14) are unaffected — this swap touches only the canvasMenus subtree and one shim file.
- Pre-existing 12 tsc errors are still owned by Phase 71 (out of scope).

---
*Phase: 65-interaction-model-overhaul*
*Completed: 2026-05-15*
