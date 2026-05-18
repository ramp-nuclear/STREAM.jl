---
phase: 69-command-palette-jump-only
plan: 01
subsystem: ui
tags: [cmdk, shadcn, command-palette, radix-ui, search-pool, scrollIntoView, vitest]

# Dependency graph
requires:
  - phase: 62-resources-panel-architecture
    provides: ResourcesSliceState, ResourceRow data-resource-uuid/kind attributes, SENTINEL_UNSET_POWER_SHAPE, selectedResourceId/Kind store slice
  - phase: 61-registry-audit-rewrite-for-v1-1
    provides: getComponent() registry lookup, ComponentDefinition shape (label, category)
  - phase: 68-layers-system-overhaul
    provides: ActiveLayers + getComponentLayers (consumed by Plan 02, not this plan)
provides:
  - cmdk@1.1.1 pinned dependency with PASS audit artifact (69-CMDK-AUDIT.md)
  - shadcn command.tsx shim re-exporting 8 cmdk primitives with project Tailwind tokens
  - buildSearchPool(nodes, resources) pure helper returning SearchItem[] (5 discriminated kinds)
  - ResourcesTreePanel scrollIntoView effect keyed on selectedResourceId/Kind (D-06 wiring for Plan 02)
affects: [69-02-command-palette-component, 69-03-app-integration-uat]

# Tech tracking
tech-stack:
  added: [cmdk@1.1.1]
  patterns:
    - "shadcn primitive shim — cmdk re-exported with project Tailwind tokens (data-slot, bg-popover, max-h-[400px]); centering Dialog wrapper deliberately omitted because Plan 02 needs top-anchor positioning per D-02"
    - "Pure selector helper for transient palette state — buildSearchPool follows the gui/src/lib/selectors/nodeErrors.ts pattern (Phase 63.1 D-19): zero React, zero zustand, zero ReactFlow runtime imports; consumer wraps in useMemo"
    - "DOM-side scroll-to-selection (D-06) — querySelector on existing data-resource-uuid/data-resource-kind attrs + scrollIntoView({ block: 'center', behavior: 'smooth' }); single requestAnimationFrame retry handles cross-tab mount race; NO new store slice"

key-files:
  created:
    - .planning/phases/69-command-palette-jump-only/69-CMDK-AUDIT.md
    - gui/src/components/ui/command.tsx
    - gui/src/lib/commandPalette/searchPool.ts
    - gui/src/lib/commandPalette/__tests__/searchPool.test.ts
  modified:
    - gui/package.json
    - gui/package-lock.json
    - gui/src/components/resources/ResourcesTreePanel.tsx

key-decisions:
  - "cmdk@1.1.1 audit verdict PASS — slopcheck [OK], single hoisted @radix-ui/react-dialog@1.1.15 (Pitfall 4 clear), no install-time scripts, 4 official Radix direct deps; pinned with --save-exact"
  - "command.tsx omits CommandDialog deliberately — Plan 02 rolls top-anchored variant via radix Dialog primitives because shadcn's default centers"
  - "SENTINEL_UNSET_POWER_SHAPE filtered from search pool; SENTINEL_LIGHT_WATER_FLUID is NOT filtered (light_water is a real selectable fluid)"
  - "Project Options sentinel row emitted last, always exactly once (D-05)"
  - "scrollIntoView effect uses { block: 'center' } not 'nearest' (CONTEXT.md D-06 override of the original research suggestion)"

patterns-established:
  - "shadcn ui/ shim — Tailwind-styled re-export of a third-party headless primitive, drop CommandDialog when the default wrapper conflicts with phase-specific positioning"
  - "Search-pool helper as pure selector — buildSearchPool consumes only the store slice shape, no React, testable with hand-built fixtures"
  - "DOM-side scroll-to-selection — leverage existing data-* attributes + ref-scoped querySelector; do NOT introduce expand/collapse state when the underlying tree is already flat"

requirements-completed: []

# Metrics
duration: 7min
completed: 2026-05-18
---

# Phase 69 Plan 01: Foundation (cmdk audit, command.tsx shim, searchPool, scroll-into-view) Summary

**cmdk@1.1.1 audited (PASS) and pinned, shadcn command.tsx shim shipped without CommandDialog, pure `buildSearchPool` helper with 7 passing tests, and ResourcesTreePanel scrollIntoView effect wired for D-06 — every Plan-02 prerequisite is in place.**

## Performance

- **Duration:** ~7 min (5 commits across 4 tasks; first commit 23:37:28 +03:00, last 23:44:08 +03:00)
- **Started:** 2026-05-18T20:37:28Z
- **Completed:** 2026-05-18T20:44:08Z
- **Tasks:** 4 (all autonomous, one TDD with RED+GREEN split commits)
- **Files modified:** 7 (3 created in source tree, 1 modified, 1 audit artifact, 2 npm metadata files)

## Accomplishments

- **Live audit + dependency pin (Task 1)** — Re-ran six probes from a clean shell (npm view version/metadata/scripts/deps/peers, slopcheck `[OK]`, GitHub repo health). Verdict `Audit verdict: PASS`. `cmdk@1.1.1` exact-pinned via `--save-exact`. `npm ls @radix-ui/react-dialog` confirms single hoisted 1.1.15 — Pitfall 4 (duplicate Dialog focus-trap conflict) is clear.
- **shadcn command.tsx shim (Task 2)** — Verbatim adaptation of canonical shadcn template (Pattern 2 from RESEARCH). Exports exactly the 8 primitives Plan 02 needs (`Command`, `CommandInput`, `CommandList`, `CommandEmpty`, `CommandGroup`, `CommandItem`, `CommandSeparator`, `CommandShortcut`). The centering Dialog wrapper that ships in the canonical shadcn file is deliberately omitted because Plan 02 needs top-anchor positioning per D-02.
- **buildSearchPool helper with 7 TDD tests (Task 3)** — Pure helper (zero React/zustand/ReactFlow runtime imports). Discriminated `SearchItem` union over 5 kinds. Tests RED-then-GREEN per `tdd="true"`. Real `getComponent()` resolution exercised (no mock). 7/7 vitest cases pass.
- **D-06 scroll-into-view wiring (Task 4)** — `useEffect` in `ResourcesTreePanel` keyed on `[selectedResourceId, selectedResourceKind]` queries the matching ResourceRow via its existing `data-resource-uuid` / `data-resource-kind` attributes (already present from Phase 62) and calls `scrollIntoView({ block: "center", behavior: "smooth" })`. `requestAnimationFrame` retry handles the cross-tab mount race. No new store slice.

## Task Commits

Each task was committed atomically (5 commits across 4 tasks — Task 3 follows the TDD RED+GREEN protocol):

1. **Task 1: cmdk audit + install** — `4a554c4` (chore)
2. **Task 2: command.tsx shim** — `6657b76` (feat)
3. **Task 3 (RED): failing tests for buildSearchPool** — `f4571f7` (test)
4. **Task 3 (GREEN): implement buildSearchPool** — `eab654f` (feat)
5. **Task 4: ResourcesTreePanel scrollIntoView effect** — `afaa6df` (feat)

_Note: No refactor commit on Task 3 — the GREEN implementation already matched the canonical Pattern 4 body from RESEARCH and required no cleanup pass._

## Files Created/Modified

**Created:**

- `.planning/phases/69-command-palette-jump-only/69-CMDK-AUDIT.md` — Audit artifact: commands run, findings table, verdict (PASS), post-install verification.
- `gui/src/components/ui/command.tsx` — Tailwind-styled re-export of cmdk primitives (8 named exports, no CommandDialog).
- `gui/src/lib/commandPalette/searchPool.ts` — Pure helper: `buildSearchPool(nodes, resources) → SearchItem[]`; discriminated union of 5 kinds.
- `gui/src/lib/commandPalette/__tests__/searchPool.test.ts` — 7 vitest cases covering empty/component/unknown-componentId/geometry/powerShape-sentinel-skip/fluid/modelOptions-last behaviors.

**Modified:**

- `gui/package.json` — Added `cmdk: "1.1.1"` (exact pin, no caret) under `dependencies`.
- `gui/package-lock.json` — Lockfile entry for cmdk@1.1.1 + integrity hash.
- `gui/src/components/resources/ResourcesTreePanel.tsx` — Added `panelRootRef`, the `useEffect` watcher on `[selectedResourceId, selectedResourceKind]`, and the `scrollIntoView` querySelector logic. ResourceRow.tsx **not** modified — it already emitted the data attributes from Phase 62.

## Decisions Made

- **Dependency-pin format** — Used `--save-exact` (writes `"cmdk": "1.1.1"`) rather than the npm default caret range. Plan 01's audit gate is per-version; allowing minor bumps would invalidate the audit on `npm install` upgrades.
- **CommandDialog absent from the shim** — Verified by `! grep -q "CommandDialog" command.tsx`. The literal string does not appear anywhere in the file (header comment was rewritten to describe the omission without naming the symbol). Plan 02's top-anchor variant will not be tempted to import the centering wrapper.
- **Fluid sentinel NOT filtered** — `SENTINEL_LIGHT_WATER_FLUID` IS a real selectable fluid (light_water IS what users select); only `SENTINEL_UNSET_POWER_SHAPE` (the "(leave unset)" placeholder) is filtered. Verified by a dedicated test case.
- **No modification of ResourceRow.tsx** — The plan listed it under `files`, but the file already carried `data-resource-uuid` and `data-resource-kind` attrs on the `<li role="treeitem">` from Phase 62 (lines 273-274 verbatim). Modifying it would be churn. Documented in Deviations below.

## Deviations from Plan

### Non-fix scope adjustments (informational)

**1. ResourceRow.tsx not modified — already satisfied the data-attribute requirement**

- **Found during:** Task 4 setup
- **Plan asked for:** "Modify `ResourceRow.tsx`: add `data-resource-uuid` and `data-resource-kind` to its outermost rendered DOM element."
- **Actual state:** `gui/src/components/resources/ResourceRow.tsx` lines 273-274 (Phase 62) already emit both attributes on the `<li role="treeitem">`:

  ```tsx
  data-resource-uuid={resource.uuid}
  data-resource-kind={kind}
  ```

- **Resolution:** Left ResourceRow.tsx untouched. The plan's `<verify>` grep gate (`grep -q "data-resource-uuid" src/components/resources/ResourceRow.tsx`) passes against the existing code.
- **Files modified:** none (zero churn).
- **Verification:** `grep -q "data-resource-uuid" src/components/resources/ResourceRow.tsx; echo $?` → 0.

### Auto-fixed issues

None. The plan executed without triggering Rules 1–3.

---

**Total deviations:** 1 informational (no code change required).
**Impact on plan:** Plan 02 inherits exactly what the plan promised. No scope creep.

## Issues Encountered

- **Pre-existing test failures unrelated to Plan 01 (deferred per scope-boundary rule).** Running the full `npm test` shows 8 failing tests in 3 files I did not touch:
  - `src/components/__tests__/AppShell.test.tsx` (3 failures — Phase 62 left-panel Tabs)
  - `src/components/canvasMenus/__tests__/contextMenus.test.tsx` (4 failures — Phase 65 context menus)
  - `src/components/sidebar/__tests__/SidebarPanel.anchors.test.tsx` (1 failure — `"Symmetric (L = R)"`, explicitly documented as pre-existing in STATE.md)

  Grep confirmed none of those test files reference any code I changed in this plan (`grep -lE "(command\.tsx|searchPool|ResourcesTreePanel)"` returned empty). These are pre-existing failures inherited from prior phases; STATE.md tracks the SidebarPanel one explicitly and the others are Phase 71 reconciliation work.

  Per execute-plan scope-boundary rule: out-of-scope, not fixed, logged here for SUMMARY traceability.

- **tsc baseline unchanged.** Pre-existing 13 errors before any Plan 01 work; still 13 after all 4 tasks. None of the new files introduce a new tsc error. (STATE.md cites "11 pre-existing tsc errors" — the current worktree shows 13, presumably due to drift since STATE.md was last refreshed. Either way, this plan adds zero.)

- **slopcheck side-effect.** `slopcheck install -e npm cmdk` does a real install during its check rather than a pure dry-run, leaving cmdk in `node_modules` with a `^` range. Recovered immediately by re-running `npm install cmdk@1.1.1 --save-exact` to set the exact pin. Audit artifact records the pin format explicitly.

## Threat Flags

None. All new surface (cmdk shim, pure helper, DOM scroll effect) was anticipated by the plan's `<threat_model>` block and was mitigated by the Task 1 audit (T-69-01, T-69-02, T-69-SC). No new endpoints, no auth paths, no trust-boundary changes.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness (Plan 02)

Plan 02 (`CommandPalette` component) inherits:

- `cmdk@1.1.1` resolvable via `import { Command as CommandPrimitive } from "cmdk"`.
- All 8 named exports from `@/components/ui/command` — `Command`, `CommandInput`, `CommandList`, `CommandEmpty`, `CommandGroup`, `CommandItem`, `CommandSeparator`, `CommandShortcut`.
- `buildSearchPool` callable as `import { buildSearchPool } from "@/lib/commandPalette/searchPool"`. The `SearchItem` discriminated union is the contract for Plan 02's `renderItem` switch.
- `ResourcesTreePanel` reacts to `selectedResourceId` / `selectedResourceKind` changes by scrolling the matched row into view — Plan 02 only needs to set those store fields; the DOM side-effect is already wired.

No blockers. Plan 02 can start immediately upon merge.

## Self-Check: PASSED

Verified files and commits exist before declaring this summary final:

- File `gui/src/components/ui/command.tsx` — FOUND
- File `gui/src/lib/commandPalette/searchPool.ts` — FOUND
- File `gui/src/lib/commandPalette/__tests__/searchPool.test.ts` — FOUND
- File `.planning/phases/69-command-palette-jump-only/69-CMDK-AUDIT.md` — FOUND
- Commit `4a554c4` (Task 1) — FOUND
- Commit `6657b76` (Task 2) — FOUND
- Commit `f4571f7` (Task 3 RED) — FOUND
- Commit `eab654f` (Task 3 GREEN) — FOUND
- Commit `afaa6df` (Task 4) — FOUND
- Audit artifact contains "Audit verdict: PASS" — VERIFIED
- 7/7 searchPool.test.ts cases pass — VERIFIED
- `grep -q "data-resource-uuid"` ResourceRow.tsx — VERIFIED
- `grep -q "scrollIntoView"` ResourcesTreePanel.tsx — VERIFIED
- `grep -q 'block:.*"center"'` ResourcesTreePanel.tsx — VERIFIED
- No `CommandDialog` reference in command.tsx — VERIFIED
- tsc baseline unchanged (13 → 13) — VERIFIED

---

*Phase: 69-command-palette-jump-only*
*Plan: 01 — Foundation (audit, shim, search-pool, scroll-into-view)*
*Completed: 2026-05-18*
