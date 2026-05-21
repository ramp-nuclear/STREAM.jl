---
slug: test-suite-drift-phase70
status: resolved
trigger: "Three gui/src/components test files have been failing on `npx vitest run` since before Phase 70 (confirmed on commit e00d6bc): AppShell.test.tsx (5 failures, including 2 tab-binding assertions invalidated by the Phase 70 reshuffle from Components/Resources/Project to Components/Presets/Resources/Project), canvasMenus/contextMenus.test.tsx (4 failures, all Radix useContext2 errors in MenuItem), and sidebar/SidebarPanel.anchors.test.tsx (1 failure, missing 'Symmetric (L = R)' text from BCsTabForm). Suspected test drift rather than production regressions — none of these surfaces have been touched by the active milestone work; all failures predate Phase 70's first commit."
goal: find_root_cause_only
created: 2026-05-21T03:30:00Z
updated: 2026-05-21T03:40:00Z
---

## Symptoms

- **Expected behavior:** `cd gui && npx vitest run` reports 0 failing tests (current pass count is 920 / 930 incl. todo).
- **Actual behavior:** 10 tests fail across 3 files (consistently across multiple runs, no flakes).
- **Error messages:**
  - `AppShell.test.tsx` — 5 failures.
    - Three are `waitFor` timeouts on tab-trigger rendering (rendered three tab triggers; Components default active; Resources flips aria-selected) — looks like an `<App />` render-hang in jsdom.
    - Two assert old bindings: `Ctrl+2 → Resources`, `Ctrl+3 → Project`. The Phase 70 tab reorder (commit `018373c`) flipped these to `Ctrl+2 → Presets`, `Ctrl+3 → Resources`, `Ctrl+4 → Project`. These two were masked earlier by the render hang and became visible after the `4ddac3f` static-import change advanced past the hang.
  - `canvasMenus/contextMenus.test.tsx` — 4 failures, all stack-trace `useContext2 at MenuItem (node_modules/@radix-ui/react-menu/src/menu.tsx:618:24)`. Looks like the tests render `<NodeContextMenu>` / `<EdgeContextMenu>` / `<CanvasContextMenu>` without wrapping in the parent `<ContextMenu>` / `<DropdownMenu>` provider, so `MenuItem` can't find its context.
  - `sidebar/SidebarPanel.anchors.test.tsx` — `expect(screen.getByText("Symmetric (L = R)")).toBeTruthy()` fails: the string is no longer in the rendered tree. The component (`BCsTabForm`) was refactored by an earlier phase (commit history pending verification) and the literal copy changed or moved, but the test wasn't updated.
- **Timeline:** All 10 failures present on commit `e00d6bc` (pre-Phase-70 HEAD — manually verified earlier in this session via `git checkout e00d6bc -- gui/`). Not introduced by Phase 70.
- **Reproduction:** `cd gui && npx vitest run` → 3 failed files / 10 failed tests / 920 passed / 10 todo (930 total).

## Current Focus

hypothesis: All three failures are test-drift after the production code evolved. (a) AppShell render hang likely caused by an `await` in App.tsx mount that the test doesn't `waitFor`; the binding-assertion failures need a literal D-01 update. (b) contextMenus tests need to wrap their components in the proper Radix provider — likely a regression from a Radix major upgrade. (c) SidebarPanel.anchors needs the assertion updated to the current BCsTabForm copy.
test: For each file, `git log -10 --oneline -- <test-file>` + diff the test setup against the current production code to spot the drift.
expecting: 3 isolated test-update fixes, no production code changes.
next_action: Triage each failing file: read test source, read production source, identify exactly what diverged, classify (test-only fix vs production regression vs API-contract change).
specialist_hint: vitest + react-testing-library + radix-ui

## Evidence

- timestamp: 2026-05-21T03:30:00Z
  observation: Per earlier verification (this session), `git checkout e00d6bc -- gui/ && npx vitest run` produced the same 8-failure baseline (since refined to 10 with the static-import advance). Phase 70's vitest additions (presetIO + presetActions, 35 tests) all pass — phase 70 source is clean.
- timestamp: 2026-05-21T03:30:00Z
  observation: Last meaningful touch to each failing file (from git log):
    - `gui/src/components/__tests__/AppShell.test.tsx` — `46b07b0 test(65-08): fix AppShell tests for AutoRecover render gate`. Phase 65, before the Phase 70 reorder.
    - `gui/src/components/canvasMenus/__tests__/contextMenus.test.tsx` — `638a733 feat(65-05): wire context menus in CanvasPanel via Popover + add PopoverMenuItem primitives`. Phase 65, before Phase 65 Plan 11 switched from Popover+PopoverMenuItem to DropdownMenu+DropdownMenuItem.
    - `gui/src/components/sidebar/__tests__/SidebarPanel.anchors.test.tsx` — Phase 63.1 Plan 06 surface; not touched since.
- timestamp: 2026-05-21T03:40:00Z
  observation: AppShell render hang root — App.tsx uses `useWindowMaximized` hook (gui/src/hooks/useWindowMaximized.ts:41) which calls `getCurrentWindow().onResized(...)`. The vi.mock in AppShell.test.tsx mocks `getCurrentWindow()` to return `{ setTitle, onCloseRequested, destroy }` — it does NOT mock `onResized`. Result: `getCurrentWindow().onResized is not a function` throws at mount → App never finishes rendering → `findByRole("tab", ...)` times out after 1000ms. The test mock was written at Phase 65 before the `useWindowMaximized` hook was added (or before it started calling `onResized`).
- timestamp: 2026-05-21T03:40:00Z
  observation: AppShell keyboard binding drift — App.tsx lines 283-310 confirm Phase 70 reorder: Ctrl+1=Components, Ctrl+2=Presets, Ctrl+3=Resources, Ctrl+4=Project. AppShell.test.tsx line 129 still asserts Ctrl+2 → "Resources"; line 157 asserts Ctrl+3 → "Project". Both assertions are stale post-Phase-70. Additionally the test at line 84 only checks for three tabs (Components, Resources, Project) and does not check for "Presets" — this test will continue to fail once the render hang is fixed, because the DOM will have four tabs but the tab-count assertion targets "Resources" which now has a different position.
- timestamp: 2026-05-21T03:40:00Z
  observation: contextMenus Radix provider mismatch — Phase 65 Plan 11 commit `638a733` introduced `PopoverMenuItem` and wired menus via Popover; the test (also committed at Phase 65 Plan 05, `638a733`) was written against that Popover-based API. Phase 65 Plan 11 LATER rewired all three menus to `DropdownMenuItem` (Radix `DropdownMenuPrimitive.Item`) which requires a `DropdownMenuPrimitive.Root` ancestor in the tree. The tests render the three `*ContextMenu` components bare — no `<DropdownMenu>` wrapper — so `MenuItem` cannot find its `Menu` context (`useContext2` throws). The test was NOT updated when Plan 11 landed. No Radix version-bump is involved; confirmed `radix-ui: ^1.4.3` in package.json is a single unified package, not a major jump.
- timestamp: 2026-05-21T03:40:00Z
  observation: SidebarPanel.anchors "Symmetric (L = R)" string — BCsTabForm.tsx was refactored in Phase 63.1 D-12 (confirmed in source comment line 286: "Phase 63.1 D-12: labeled SegmentedButtonGroup replaces the legacy 'Symmetric (L = R)' custom switch"). The literal string "Symmetric (L = R)" no longer appears anywhere in BCsTabForm.tsx. The component now renders two SegmentedButtonGroup option labels: "Symmetric" and "Asymmetric". The test at line 124 (`getByText("Symmetric (L = R)")`) was never updated after D-12 landed.

## Eliminated

- Radix major version upgrade: ruled out. `package.json` shows `radix-ui: ^1.4.3` (single unified package). The error is a missing provider context, not an API removal.
- Production regression in Phase 70: ruled out. All 10 failures reproduce on pre-Phase-70 commit `e00d6bc`. Phase 70 added only `presetIO` and `presetActions` test files, both passing.
- Flaky tests: ruled out. Failures are 100% reproducible across multiple runs.

## Resolution

root_cause: Three independent test-drift failures, all caused by tests that were not updated when production code changed:
  (A) AppShell.test.tsx — TWO sub-causes: (1) The `getCurrentWindow` mock is missing `onResized`, added by the `useWindowMaximized` hook after Phase 65. This causes a mount-time throw that prevents the workspace from rendering, making all three `findByRole("tab",...)` tests time out. (2) The Ctrl+2 and Ctrl+3 binding assertions were written for the Phase 62 three-tab order (Components/Resources/Project) and were never updated after Phase 70 reshuffled to four tabs (Components/Presets/Resources/Project).
  (B) contextMenus.test.tsx — The three `*ContextMenu` components were migrated from `PopoverMenuItem` to `DropdownMenuItem` (Radix `DropdownMenuPrimitive.Item`) in Phase 65 Plan 11. `DropdownMenuItem` requires a `<DropdownMenu>` (i.e., `DropdownMenuPrimitive.Root`) ancestor. The tests render the components without that wrapper, so Radix throws `MenuItem must be used within Menu`.
  (C) SidebarPanel.anchors.test.tsx — Phase 63.1 D-12 replaced the "Symmetric (L = R)" toggle switch with a `SegmentedButtonGroup` whose options are labeled "Symmetric" and "Asymmetric". The test assertion `getByText("Symmetric (L = R)")` targets the deleted string.

fix: applied in 4 atomic commits on `gui-redesign` after user approved post-diagnosis:
  - `ea62d4d` test(70) A1 — add `onResized` to AppShell `vi.mock("@tauri-apps/api/window")` (mirrors `WindowControls.test.tsx`). Restored 3 render-hang tests.
  - `38b1553` test(70) A2 — describe block renamed `Ctrl+1/2/3` → `Ctrl+1..4`; D-01 render expects four tabs (adds Presets); Ctrl+2 binding now `Presets` (was Resources), Ctrl+3 now `Resources` (was Project); added Ctrl+4 → Project; Ctrl+1 setup starts from Presets. Restored 2 binding tests.
  - `442bb69` test(70) B — added `renderInDropdown` helper (mirrors CanvasPanel.tsx wrapper); replaced 4 `render(<*ContextMenu …/>)` with `renderInDropdown(...)`; updated `data-slot='popover-menu-item'` → `'dropdown-menu-item'`. Restored 4 contextMenu tests.
  - `24d53b2` test(70) C — replaced `getByText("Symmetric (L = R)")` (Phase 63.1 D-12 deleted that literal) with `getByText("Symmetric")` + `getByText("Asymmetric")`. Restored 1 anchors test.

verification: Full GUI vitest now 82 files / 921 tests passing / 10 todo / 0 failures (post-fix), up from 79 files / 910 passing / 10 failing / 10 todo (pre-fix).
files_changed:
  - gui/src/components/__tests__/AppShell.test.tsx
  - gui/src/components/canvasMenus/__tests__/contextMenus.test.tsx
  - gui/src/components/sidebar/__tests__/SidebarPanel.anchors.test.tsx
