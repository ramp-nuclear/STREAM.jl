---
phase: 68-layers-system-overhaul
plan: 04
subsystem: gui/layers-ui
tags: [layers, ui, chip, popover, shadcn, tdd]
dependency_graph:
  requires:
    - "Plan 68-01: gui/src/lib/layers.ts (LayerKey, LAYER_KEYS); gui/src/components/ui/checkbox.tsx (shadcn Checkbox)"
    - "Plan 68-02: useStore activeLayers + hideOffLayer + toggleLayer + setHideOffLayer"
    - "Plan 68-03: CanvasPanel.tsx overlay-stack mount point intact at line 407"
  provides:
    - "gui/src/components/LayersChip.tsx — floating 4-color chip + popover (Layers / Dim-Hide)"
    - "gui/src/components/__tests__/LayersChip.test.tsx — 16 Vitest interaction tests"
    - "gui/src/components/CanvasPanel.tsx — LayersChip mounted as last child of top-right overlay stack"
  affects:
    - "Plan 68-05 (SecondaryToolbar deletion + ViewMenu cleanup) — LayersChip is now the sole user-facing layer-toggle surface; the deleted Layer submenu / SecondaryToolbar layer-toggle have no remaining users to worry about"
tech-stack:
  added: []
  patterns:
    - "Controlled Popover open state (useState) — keeps aria-expanded on the chip button accurate even though Radix tracks internally"
    - "Per-LayerKey color square: inline style backgroundColor + opacity, data-testid='layer-square-<key>' for test addressability without DOM-position coupling"
    - "Module-scope LAYER_COLORS / LAYER_LABELS Records — single source of truth, no per-render object allocation"
    - "Toggle pair (Dim/Hide) instead of Switch — names both states explicitly per UI-SPEC §2 rationale"
key-files:
  created:
    - "gui/src/components/LayersChip.tsx (155 lines)"
    - "gui/src/components/__tests__/LayersChip.test.tsx (313 lines, 16 tests)"
  modified:
    - "gui/src/components/CanvasPanel.tsx (+2 lines: 1 import, 1 JSX child)"
    - ".planning/phases/68-layers-system-overhaul/deferred-items.md (+ stale activeLayer fixture log)"
decisions:
  - "Chip width is auto (px-2 padding) not fixed — 4 squares + 'Layers' label drive natural width; min-w-* not needed because the squares + label always render"
  - "Squares use data-testid for test addressability so tests don't depend on DOM child ordering as the addressing mechanism (the ordering IS asserted separately in Test 8)"
  - "data-state attribute on Toggle is the chosen press-state assertion (Radix Toggle sets data-state='on'|'off'); avoids the aria-pressed brittleness across Radix versions"
  - "Popover header text 'Layers' duplicates the chip label per UI-SPEC Copywriting Contract — brevity over disambiguation; tests use getAllByText to handle both occurrences"
  - "Legend swatches in popover rows are full-opacity (state is conveyed by Checkbox, not by swatch dimming) per UI-SPEC §2"
  - "Hide mode beats dim mode for off-layer port handles — established by Plan 03, not relevant to LayersChip itself but the chip drives the hideOffLayer state that triggers it"
requirements-completed: [D-01]
metrics:
  duration: "~15 min"
  completed: "2026-05-16"
  tasks_completed: 2
  files_changed: 4
  tests_added: 16
  tests_passing: 106
---

# Phase 68 Plan 04: LayersChip floating canvas control Summary

**Delivered the sole user-facing control surface for Phase 68's 4-layer system: a floating chip pinned top-right of the canvas with always-visible 4-color D-01 state indicators, opening a Popover containing 4 Checkbox rows + a Dim/Hide Toggle pair.** Mounts cleanly as the last child of the existing Phase 65 overlay stack — no separate cluster, no container restyling. All 16 Vitest interaction tests pass.

## Performance

- **Duration:** ~15 min
- **Completed:** 2026-05-16
- **Tasks:** 2 (Task 1 split RED + GREEN per `tdd="true"`)
- **Files changed:** 4 (2 new source, 1 modified consumer, 1 deferred-items log)
- **Tests added:** 16 (all in `LayersChip.test.tsx`)
- **Tests passing:** 106 across the 5 verify files (zero regressions)

## Contract Exposed to Downstream Plans

**Mount-point baseline for any future overlay-stack change:**

After Plan 68-04, the `absolute top-2 right-2 z-10 flex flex-col gap-1` overlay container in `CanvasPanel.tsx` (line 407) contains, top-to-bottom:

| Order | Component             | Plan (origin) |
| ----- | --------------------- | -------------- |
| 1     | `<ZoomInButton />`    | Phase 65 P13   |
| 2     | `<ZoomOutButton />`   | Phase 65 P13   |
| 3     | `<FitViewButton />`   | Phase 65 P13   |
| 4     | `<InteractiveLockButton />` | Phase 65 P13 |
| 5     | `<SnapToGridButton />`| Phase 65 P06   |
| 6     | `<LayersChip />`      | Phase 68 P04 (LAST per UI-SPEC §1) |

Future inserts go above LayersChip; LayersChip stays last unless UI-SPEC §1 is renegotiated.

**LayersChip public surface:**

```tsx
import LayersChip from "@/components/LayersChip";   // default export
// No props. The component pulls activeLayers + hideOffLayer + toggleLayer +
// setHideOffLayer directly from useStore selectors.
<LayersChip />
```

## Task Commits

| Task | Name                                                | Commit  | Files                                                              |
| ---- | --------------------------------------------------- | ------- | ------------------------------------------------------------------ |
| 1 RED   | Failing tests for LayersChip (16 cases)          | 1643d1d | gui/src/components/\_\_tests\_\_/LayersChip.test.tsx               |
| 1 GREEN | Implement LayersChip component                   | 1735057 | gui/src/components/LayersChip.tsx                                  |
| 2    | Mount LayersChip in CanvasPanel overlay stack     | 951ce77 | gui/src/components/CanvasPanel.tsx + deferred-items.md             |

## Verification Results

**Vitest — full plan suite (per the plan's `<verification>` block):**

```
$ cd gui && ./node_modules/.bin/vitest run \
    src/components/__tests__/LayersChip.test.tsx \
    src/lib/__tests__/layers.test.ts \
    src/store/__tests__/useStore.test.ts \
    src/lib/__tests__/projectIO.snapToGrid.test.ts \
    src/components/__tests__/ToolboxPanel.test.tsx
Test Files  5 passed (5)
     Tests  106 passed (106)
```

**Mount-site sanity (per the plan's `<verify>` for Task 2):**

```
$ cd gui && grep -rn LayersChip src
src/components/LayersChip.tsx:1:   // LayersChip.tsx — Phase 68 Plan 04
src/components/LayersChip.tsx:43:  export default function LayersChip() {
src/components/__tests__/LayersChip.test.tsx:13:  import LayersChip from "../LayersChip";
src/components/CanvasPanel.tsx:45: import LayersChip from "./LayersChip";
src/components/CanvasPanel.tsx:414:        <LayersChip />
```

Three sites only — definition, test, single mount. No stray references.

**TypeScript — `cd gui && npx tsc --noEmit -p .`:**

The two files this plan owns (`LayersChip.tsx`, `LayersChip.test.tsx`) compile **clean — zero errors**. `CanvasPanel.tsx` (the edited consumer) also compiles clean. The full-project tsc report still surfaces the following errors, all of which are **pre-existing and not introduced by Phase 68**:

- `StreamNode.tsx` — 4× TS2322 on `Handle` `data` prop (Plan 68-03 deferred-items, line 5)
- `BCsTabForm.test.tsx` — 3× TS2352 (Phase 71 baseline)
- `SidebarRouter.test.tsx` — 2× TS2353 (Phase 71 baseline)
- `validation.test.ts` — 3× TS6133 (Phase 71 baseline)
- `saveProjectAs.test.ts` — 1× TS2561 (stale `activeLayer` fixture from Plan 68-02 sweep omission; logged to deferred-items.md)

None of these files appear in this plan's `files_modified`. Total errors went 13 → 13 — zero new errors introduced.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] Worktree had no `gui/node_modules`; vitest unresolvable**

- **Found during:** Task 1 RED verification (`./node_modules/.bin/vitest` initially absent).
- **Issue:** Worktree spawn does not run `npm install` in `gui/`. Identical to Plans 68-02 and 68-03 deviations.
- **Fix:** Symlinked `gui/node_modules → /home/itay/projects/Julia-STREAM/gui/node_modules`. Standard worktree pattern for this repo.
- **Files modified:** None tracked by git (`node_modules` is gitignored).
- **Commit:** n/a (infrastructure-only deviation).

**2. [Out-of-scope discovery] Stale `activeLayer: "Both"` fixture in `saveProjectAs.test.ts`**

- **Found during:** Task 2 final tsc gate.
- **Issue:** `gui/src/store/__tests__/saveProjectAs.test.ts` line 133 sets `activeLayer: "Both"` in a `useStore.setState` fixture call. The `activeLayer` (singular) field was deleted in Plan 68-02; canonical replacement is `activeLayers` + `hideOffLayer`.
- **Root cause:** Plan 68-02 migrated three test fixtures (`useStore.test.ts`, `useStore.codePanel.test.ts`, `saveAndOpenErrors.test.ts`, `projectIO.snapToGrid.test.ts`) but missed `saveProjectAs.test.ts`.
- **Fix:** Logged to `.planning/phases/68-layers-system-overhaul/deferred-items.md` per SCOPE BOUNDARY. The fix is one diff hunk (3 lines) but lives in Plan 68-02's owned files; introducing it here would violate this plan's `files_modified` contract.
- **Files modified:** `.planning/phases/68-layers-system-overhaul/deferred-items.md` (log entry only).
- **Commit:** 951ce77 (bundled with the Task 2 mount commit since both are content for the same plan).

**3. [Hook noise — not a real deviation] PreToolUse:Edit hook emitted "READ-BEFORE-EDIT REMINDER" on Edit calls**

- **Found during:** Task 2 Edit calls.
- **Issue:** A hook fires a "you must Read first" reminder on every Edit even when Read was performed in the same session. Does not block — Edits succeeded.
- **Fix:** None — false positive (same pattern Plan 68-03 documented). Continuing through the reminders.
- **Files modified:** None.
- **Commit:** n/a.

---

**Total deviations:** 1 environment-only (vitest path) + 1 out-of-scope log + 1 false-positive hook reminder. **Zero plan-scope drift** — both tasks landed exactly as specified.

## TDD Gate Compliance

| Plan task | Gate    | Commit  | Status                                                                                              |
| --------- | ------- | ------- | --------------------------------------------------------------------------------------------------- |
| Task 1    | RED     | 1643d1d | 16 tests authored; import of `../LayersChip` fails (file does not exist yet) — RED confirmed.        |
| Task 1    | GREEN   | 1735057 | All 16/16 tests pass after `LayersChip.tsx` lands.                                                  |
| Task 2    | N/A     | 951ce77 | `tdd="false"` per plan — pure JSX mount + 1 import. Behaviorally verified via grep + tsc + suite.    |

**REFACTOR pass:** not needed. The component is 155 lines with a single responsibility, clear module-scope constants, no duplication. The test file mirrors the `<behavior>` section 1:1 so re-org would only hurt traceability.

## Known Stubs

None. The chip is fully wired to the store; clicking checkboxes updates `activeLayers` and the canvas re-renders via Plan 03's enrichment pass; clicking Dim/Hide updates `hideOffLayer` and the same enrichment pass switches between opacity-dim and `hidden:true` modes. End-to-end: chip → store → CanvasPanel enrichment → ReactFlow render.

## Threat Flags

None. This plan adds a pure-client UI component that reads/writes Zustand state. No network surface, no auth path, no persistence change (the layer state persistence is owned by Plan 68-02). The component does not accept any external props, query params, or user-typed strings — all inputs are typed booleans / `LayerKey` union literals.

## User Setup Required

None — the chip is live on the canvas the moment the dev build hot-reloads after this commit lands on the main branch.

## Next Phase Readiness

**Ready for Plan 68-05 (SecondaryToolbar deletion + ViewMenu / FileMenu / App cleanup):**

- The user-facing layer control is now LayersChip exclusively. Plan 05 can delete `SecondaryToolbar.tsx` and the View menu's "Layer" submenu without leaving any user-facing layer toggle missing.
- The stale `activeLayer: "Both"` fixture in `saveProjectAs.test.ts` (logged in deferred-items.md §"Plan 68-04") should be fixed as part of Plan 05's tsc-cleanup sweep, since Plan 05 owns the final tsc-green baseline per the phase plan.

## Self-Check

- [x] `gui/src/components/LayersChip.tsx` exists — verified via `test -f` (file present, default export `LayersChip`).
- [x] `gui/src/components/__tests__/LayersChip.test.tsx` exists with 16 tests — verified via `vitest run` (16 pass).
- [x] `gui/src/components/CanvasPanel.tsx` imports LayersChip and renders it inside the overlay stack — verified via `grep -nE 'LayersChip'` → line 45 import, line 414 JSX mount.
- [x] Overlay container className unchanged — verified `absolute top-2 right-2 z-10 flex flex-col gap-1` still at line 407.
- [x] D-01 hex values present in LayersChip.tsx — verified via `grep`: `#3b82f6` (Hydraulic), `#f59e0b` (Thermal), `#8b5cf6` (Sources), `#f43f5e` (ReactorPhysics).
- [x] Commit 1643d1d (Task 1 RED) — `git log --oneline` shows hash.
- [x] Commit 1735057 (Task 1 GREEN) — `git log --oneline` shows hash.
- [x] Commit 951ce77 (Task 2 mount) — `git log --oneline` shows hash.
- [x] Plan verification suite: 106/106 across 5 test files.
- [x] tsc clean for `LayersChip.tsx`, `LayersChip.test.tsx`, `CanvasPanel.tsx`. Pre-existing errors elsewhere unchanged (13 → 13).
- [x] No `git stash` invoked.
- [x] No modifications to STATE.md or ROADMAP.md (orchestrator owns those writes).

## Self-Check: PASSED

---
*Phase: 68-layers-system-overhaul*
*Completed: 2026-05-16*
