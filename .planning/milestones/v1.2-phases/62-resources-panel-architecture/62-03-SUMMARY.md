---
phase: 62-resources-panel-architecture
plan: 03
subsystem: ui
tags: [gui, shadcn, radix, ui-primitives, popover, context-menu, vitest]

# Dependency graph
requires:
  - phase: 62-resources-panel-architecture
    provides: "Wave 0 phase context (CONTEXT.md, UI-SPEC.md, RESEARCH.md, validation strategy)"
provides:
  - "shadcn Popover shim (gui/src/components/ui/popover.tsx) — unblocks 62-08 `+ New…` picker"
  - "shadcn ContextMenu shim (gui/src/components/ui/context-menu.tsx) — unblocks 62-06 Resources tree per-row menu"
  - "Verified Pitfall 1 (Assumption A3) — Radix `onInteractOutside={(e) => e.preventDefault()}` suppresses click-outside dismiss but Esc still dismisses"
affects: [62-06, 62-08, future-shadcn-consumers]

# Tech tracking
tech-stack:
  added: []  # zero new npm dependencies — Radix Popover/ContextMenu transitively present via radix-ui@1.4.3 aggregator
  patterns:
    - "shadcn shim convention: import from radix-ui aggregator (not @radix-ui/react-* per-package npm names); function declarations with React.ComponentProps<typeof X>; data-slot attributes; Portal wrap baked into Content"
    - "happy-dom-aware test pattern for Radix dismissable layer: await one macrotask (Promise + setTimeout 0) after render so Radix's deferred document-level pointerdown listener registers before dispatching the outside event"

key-files:
  created:
    - "gui/src/components/ui/popover.tsx"
    - "gui/src/components/ui/context-menu.tsx"
    - "gui/src/components/ui/__tests__/popover.test.tsx"
  modified: []

key-decisions:
  - "Followed existing project shim convention (function declarations + React.ComponentProps + data-slot) rather than the older forwardRef pattern described in the plan's action block — the existing tabs.tsx/scroll-area.tsx/dropdown-menu.tsx all use the function form, so consistency wins. Behavior is equivalent."
  - "ContextMenuItem variant='destructive' prop is supported (data-variant pattern mirrored from dropdown-menu.tsx) in addition to the className path the plan suggested — both work; gives 62-06 the choice."
  - "popover.tsx default width stays w-72 (288px); UI-SPEC §'Popover surface' allows 62-08 to override to 280px via inline style at the consumer site."
  - "Popover test must await a macrotask after render to give Radix time to attach its document-level pointerdown listener (setTimeout(0) inside usePointerDownOutside). Without this the test silently no-ops even though dispatches succeed."

patterns-established:
  - "shadcn-new-york shim: when adding a new ui/ primitive in this codebase, copy a sibling shim (tabs.tsx, scroll-area.tsx, dropdown-menu.tsx) and swap the namespace — do NOT run `npx shadcn add` (Phase 62 UI-SPEC §'Registry Safety')"
  - "Radix dismissable-layer test fixture: dispatch a bubbling native pointerdown Event after one-macrotask flush; do NOT rely on fireEvent.pointerDown alone if the test seems to no-op"

requirements-completed: [CD-02]

# Metrics
duration: "~25min"
completed: 2026-05-13
---

# Phase 62 Plan 03: Shadcn Popover + ContextMenu Shims Summary

**Two new shadcn-new-york shims (popover.tsx, context-menu.tsx) wrapping the transitively-available Radix primitives, plus a passing happy-dom guard-rail test that resolves RESEARCH Assumption A3 (click-outside-suppressed via `onInteractOutside={(e) => e.preventDefault()}` does NOT break Esc dismissal).**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-05-13T01:44Z
- **Completed:** 2026-05-13T01:51Z
- **Tasks:** 3
- **Files created:** 3
- **Files modified:** 0
- **npm dependencies added:** 0

## Accomplishments

- `gui/src/components/ui/popover.tsx` — Popover, PopoverTrigger, PopoverAnchor, PopoverPortal, PopoverContent (Portal-wrapped, new-york Tailwind classes, sensible w-72 default that 62-08 overrides to 280px)
- `gui/src/components/ui/context-menu.tsx` — full shadcn surface mirroring `dropdown-menu.tsx` (Root, Trigger, Group, Portal, Sub, RadioGroup, SubTrigger, SubContent, Content, Item with variant='destructive' support, CheckboxItem, RadioItem, Label, Separator, Shortcut)
- `gui/src/components/ui/__tests__/popover.test.tsx` — 3 green it() blocks proving Radix's `onInteractOutside={(e) => e.preventDefault()}` semantics for Phase 62 Wave 2 picker
- Zero new npm dependencies; Radix transitively available via `radix-ui@1.4.3` aggregator as RESEARCH §"Standard Stack" predicted

## Task Commits

Each task was committed atomically (worktree branch `worktree-agent-a083d81c0cac9fa6a`):

1. **Task 1: popover.tsx shim** — `fe7f11d` (feat)
2. **Task 2: context-menu.tsx shim** — `4af431a` (feat)
3. **Task 3: popover.test.tsx TDD verification** — `4bba792` (test — single GREEN commit because the underlying Radix primitive already worked; no implementation code was added/changed during this task)

## Files Created/Modified

- `gui/src/components/ui/popover.tsx` — Popover shim (55 lines)
- `gui/src/components/ui/context-menu.tsx` — ContextMenu shim (241 lines)
- `gui/src/components/ui/__tests__/popover.test.tsx` — 3 happy-dom it() blocks (104 lines)

## Decisions Made

- **Function-declaration shim form** chosen over `forwardRef` — the existing project convention (tabs.tsx / scroll-area.tsx / dropdown-menu.tsx) uses `function Foo({ ...props }: React.ComponentProps<typeof X>) { ... }` with `data-slot` attributes. Behavior is identical to forwardRef for these wrappers since Radix already forwards refs internally; using function form matches the rest of the codebase.
- **ContextMenuItem supports both `variant="destructive"` and className-only destructive styling.** Plan Task 2 Action point 3 suggested className-only; I kept the data-variant prop because dropdown-menu.tsx has it and shadcn consumers expect API symmetry. 62-06 may use whichever path is more convenient.
- **Test fixture awaits a macrotask after render** — Radix's `usePointerDownOutside` registers its document-level listener inside `setTimeout(0)`. Without `await flushTimers()` the test silently no-ops. Documented inline in the test file.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Initial popover.test.tsx callback-spy assertion silently no-op'd**
- **Found during:** Task 3 (TDD GREEN run)
- **Issue:** First run of the third `it()` block failed because the `pointerdown` was dispatched before Radix's `setTimeout(0)`-deferred document listener had attached. Radix's `react-dismissable-layer` defers listener attachment to break a layer-ordering race in its design.
- **Fix:** Added `flushTimers()` helper (returns `new Promise(r => setTimeout(r, 0))`) and `await flushTimers()` in each `it()` block after `render(...)` and before the outside dispatch. Also reviewed the `react-dismissable-layer` source (`node_modules/@radix-ui/react-dismissable-layer/dist/index.mjs`) and documented the rationale inline. Switched dispatch from `fireEvent.pointerDown` to a direct `new Event("pointerdown", {bubbles: true, cancelable: true})` on the outside element — the synthetic React event was not enough; we need the native event reaching `document` to trigger Radix's listener.
- **Files modified:** gui/src/components/ui/__tests__/popover.test.tsx
- **Verification:** All 3 tests pass; vitest run shows "Tests 3 passed".
- **Committed in:** 4bba792 (Task 3 commit, incorporated before the commit was made — the failing draft was only intermediate)

**2. [Rule 1 - Pattern adaptation] Shim style: function form instead of forwardRef**
- **Found during:** Task 1 (popover.tsx creation)
- **Issue:** Plan's `<action>` block (point 1 + point 3) referenced `forwardRef`, `React.ComponentRef`, `React.ComponentPropsWithoutRef`, and `displayName` — the older shadcn pattern. The actual project codebase (tabs.tsx, scroll-area.tsx, dropdown-menu.tsx) uses the newer function-declaration form with `React.ComponentProps<typeof X>` and `data-slot` attributes. This is a stale-instruction issue in the plan, not user-facing.
- **Fix:** Followed the existing project convention. Behavior is equivalent: Radix already forwards refs internally; the function form just elides the explicit `forwardRef` wrapper and the `displayName` boilerplate.
- **Files modified:** gui/src/components/ui/popover.tsx, gui/src/components/ui/context-menu.tsx
- **Verification:** tsc clean (7 baseline errors unchanged, none in new files); vitest green; acceptance grep `^export.*\b(Popover|...)\b` returns 5 for popover.tsx and 6 for context-menu.tsx.
- **Committed in:** fe7f11d, 4af431a

---

**Total deviations:** 2 auto-fixed (1 test-infrastructure bug, 1 pattern adaptation)
**Impact on plan:** Neither auto-fix expanded scope. The test fix was necessary for the GREEN gate to actually verify the behavior the plan asked us to verify; the style adaptation aligned new shims with the existing project codebase.

## Issues Encountered

- `gui/node_modules` was absent in the worktree at the start (worktrees don't share the main repo's node_modules). Resolved by running `npm install --no-audit --no-fund --prefer-offline` once at the top of the session — 8s install, no warnings of note.
- The first vitest pass on the failing-callback-spy assertion took two iterations to diagnose. The fix is documented inline in the test file so future authors don't repeat the same dead-end.

## Next Phase Readiness

- **Pitfall 1 (Assumption A3) verified:** Wave 2 plan 62-08 can rely on `<PopoverContent onInteractOutside={(e) => e.preventDefault()}>` to suppress click-outside dismissal without losing Esc dismissal. The guard-rail test will catch a Radix upgrade regression before it cascades.
- **Heads-up for 62-08 implementer:** The Pitfall 1 *focus-return* workaround (`triggerRef.current?.focus()` after `setPopoverOpen(false)`) is NOT in the shim — the shim has no trigger ref of its own. Implement focus-return at the consumer site per RESEARCH §"Pitfall 1" + UI-SPEC §"Focus return on dismiss".
- **Heads-up for 62-06 implementer:** The Delete row in the Resources tree per-row context menu can use either `<ContextMenuItem variant="destructive">` (data-variant path, recommended for parity with dropdown-menu.tsx in the rest of the GUI) or `<ContextMenuItem className="text-destructive focus:bg-destructive/10 focus:text-destructive">` (manual path). Both produce the same visual.

## Self-Check: PASSED

- `gui/src/components/ui/popover.tsx` — FOUND
- `gui/src/components/ui/context-menu.tsx` — FOUND
- `gui/src/components/ui/__tests__/popover.test.tsx` — FOUND
- Commit `fe7f11d` — FOUND
- Commit `4af431a` — FOUND
- Commit `4bba792` — FOUND
- `npx tsc --noEmit` — 7 errors (same as baseline; no new errors in plan 03 files)
- `npx vitest run src/components/ui/__tests__/popover.test.tsx` — 3 passed / 0 failed
- `grep -lE 'from "radix-ui"' gui/src/components/ui/*.tsx | wc -l` — 14 (includes the 12 pre-existing shims plus popover.tsx + context-menu.tsx; criterion was >= 4)
- `gui/package.json` — unchanged (zero new npm deps; verified via `git diff --stat`)

---
*Phase: 62-resources-panel-architecture*
*Completed: 2026-05-13*
