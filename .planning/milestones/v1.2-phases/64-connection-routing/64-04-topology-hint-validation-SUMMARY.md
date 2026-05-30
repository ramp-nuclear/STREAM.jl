---
phase: 64-connection-routing
plan: 04
subsystem: ui
tags: [react, zustand, vitest, validators, selectors, autoflip, topology-hints]

# Dependency graph
requires:
  - phase: 64-connection-routing
    provides: "detectAxisCollision from gui/src/lib/autoflip.ts (Plan 01) + the autoflip-wired StreamNode handle render path (Plan 03)"
  - phase: 63.1-bc-architecture-rework-unified-bcs-tab
    provides: "Pure-selector validator template (selectNodeErrors) + Pitfall-3 primitive-boolean Zustand subscription pattern"
provides:
  - "Pure topology-hint validator selectTopologyHints (D-15) at gui/src/lib/selectors/topologyHints.ts — first warning-severity selector in the validator-as-selector family"
  - "Non-blocking yellow chip rendered inside StreamNode.tsx surfacing D-15's crowded-edge warning text"
  - "Warning-severity discriminator: chip is independent of hasAnyError / errorNodeIds / codegen gating — establishes the precedent for future non-blocking validators"
affects: [phase-71, phase-65, phase-68]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Validator-as-pure-selector (Phase 63.1 D-19) — extended with a warning-severity outcome"
    - "Primitive-boolean Zustand selector wrap (Pattern 1 / Pitfall 3) — re-applied for hasTopologyHint"

key-files:
  created:
    - "gui/src/lib/selectors/topologyHints.ts"
    - "gui/src/lib/selectors/__tests__/topologyHints.test.ts"
    - "gui/src/components/__tests__/StreamNode.topologyHint.test.tsx"
  modified:
    - "gui/src/components/StreamNode.tsx"

key-decisions:
  - "Severity discriminator added by dedicating a separate selector + separate consumer boolean (hasTopologyHint); chip and red ring stay on independent render paths"
  - "Selector delegates the geometric math to detectAxisCollision (Plan 01) and only adds the dual-layer presence pre-check + the public tag constant"
  - "Chip text is hard-coded in StreamNode.tsx; no i18n pipeline planned for v1.2 — matches the rest of the GUI"

patterns-established:
  - "Warning-severity validators emit their own tag from a dedicated selector; consumers wrap into a primitive boolean and render independently of the red-ring outline"
  - "Test fixtures for pure selectors inline the ComponentDefinition objects rather than importing the registry — keeps the test self-contained and the selector's contract grep-able"

requirements-completed: []

# Metrics
duration: 6m
completed: 2026-05-14
---

# Phase 64 Plan 04: Topology Hint Validation Summary

**D-15 crowded-edge validator shipped as a pure selector + non-blocking yellow chip — first warning-severity validator in the Phase 63.1 selector family, independent of the red-ring error path.**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-05-14T10:54:23Z
- **Completed:** 2026-05-14T~11:00Z
- **Tasks:** 3
- **Files modified:** 4 (3 created, 1 modified)

## Accomplishments

- New pure selector `selectTopologyHints(state, nodeId, getComponent): string[]` mirrors `nodeErrors.ts` exactly: zero React/Zustand/ReactFlow runtime imports, only `import type`. Delegates the axis-collision math to `detectAxisCollision` (Plan 01) and adds the dual-layer pre-check (component must have BOTH a FlowPort AND a thermal pair carrying `pair_with`).
- `HINT_AXIS_COLLISION = "topology-axis-collision"` tag constant exported so consumers reference the constant instead of stringly-typing the tag.
- StreamNode renders a non-blocking yellow chip (`<div data-testid="topology-hint-chip" role="status" aria-label="Topology hint">`) inside the node container when D-15 fires. Text: *"Hydraulic and thermal neighbors on same axis — consider repositioning."*
- The chip is INDEPENDENT of `hasAnyError`: `hasAnyError = hasError || hasBCError` is untouched. `hasTopologyHint` is its own primitive-boolean Zustand selector. The red ring continues to light up only for blocking errors; the chip surfaces only the warning.
- 13 new vitest cases (9 selector + 4 rendered-chip) all green. Full Phase 64 + Phase 63.1 surface (100 cases across 9 files) passes with no regression.

## Task Commits

Each task was committed atomically:

1. **Task 1: RED → GREEN — selectTopologyHints pure selector + tests** — `6beb06a` (feat)
2. **Task 2: RED — StreamNode topology-hint chip render test** — `a915d85` (test)
3. **Task 3: GREEN — wire topology hint into StreamNode** — `d70ac74` (feat)

_Note: Task 1 was a single TDD commit because the test file and the implementation file landed together (the selector module did not exist on the Wave-2 base, so the test file alone would have been an import-error, not a meaningful RED). Tasks 2 and 3 followed strict RED → GREEN ordering._

## Files Created/Modified

### Created
- `gui/src/lib/selectors/topologyHints.ts` — Pure selector module. Exports `selectTopologyHints`, `HINT_AXIS_COLLISION`, and `TopologyHintsInput` (the sub-state shape consumed by the selector). Mirrors `nodeErrors.ts` header conventions, section dividers, and the "consumers MUST wrap into a primitive" advisory comment.
- `gui/src/lib/selectors/__tests__/topologyHints.test.ts` — 9 unit tests. Covers D-15 positive (crowded CAC), orthogonal-axes negative, flow-only / thermal-only exemptions, isolated CAC default, unknown-node / unknown-component guards, fresh-array-stability invariant, and the tag-constant exact-value invariant.
- `gui/src/components/__tests__/StreamNode.topologyHint.test.tsx` — 4 rendered-chip tests with `@vitest-environment happy-dom`. Asserts presence on a crowded CAC (`textContent` contains "same axis"), absence on orthogonal axes, absence on an isolated Pump, and the non-blocking-severity invariant (chip presence does NOT introduce `ring-destructive` on the node root).

### Modified
- `gui/src/components/StreamNode.tsx` — Imported `selectTopologyHints` + `TopologyHintsInput`. Added a `hasTopologyHint` primitive-boolean useStore selector right after `hasBCError` (Pattern 1 / Pitfall 3). Conditionally renders the yellow chip element between the `source-block-label` div and the `flowPorts.map(...)` block. Chip uses Tailwind `amber-100` / `amber-900` (matches the existing thermal accent color family).

## Decisions Made

- **Severity discriminator strategy:** Resolves the research's Open Question 3. Rather than introducing a `severity` field on the existing `selectNodeErrors` return shape (which would have required either a tag-prefix convention like `warn:topology-axis-collision` or a return-type widening to `{tag, severity}[]`), we dedicated a separate selector with its own consumer boolean. This keeps the existing red-ring code path completely untouched (`hasAnyError = hasError || hasBCError` line in `StreamNode.tsx:415` is unchanged) and makes the warning-severity contract immediately legible at the call site (`hasTopologyHint` reads as "show the warning chip", not "is in some error state").
- **Selector-level dual-layer pre-check:** `detectAxisCollision` already short-circuits for components missing either layer, so the dual-layer guard in `selectTopologyHints` is technically redundant. We kept it because (a) it makes the selector's contract locally legible without cross-file reading, and (b) it gives a future maintainer a single grep target (`hasFlowPort && hasThermalPair`) for the D-15 trigger condition.
- **No regression test on the red-ring path was added** beyond the existing `StreamNode.anchor.test.tsx` / `StreamNode.test.tsx` coverage — the non-blocking-severity invariant is asserted positively inside the new chip test (the assertion that `ring-destructive` is absent when only the chip fires), which is the precise property that would regress if a future change accidentally mixed the chip into `hasAnyError`.

## Deviations from Plan

None — plan executed exactly as written. The plan's `<sequencing_note>` (about Plan 03 / Plan 04 both touching StreamNode.tsx) was already resolved by the orchestrator scheduling this plan in Wave 3 on top of Plan 03's already-landed StreamNode.tsx changes.

## Issues Encountered

- The worktree's `gui/node_modules` was not present on first invocation (each worktree is a fresh checkout). Symlinked `gui/node_modules → /home/itay/projects/Julia-STREAM/gui/node_modules` to run vitest. This is a Phase 64 / parallel-executor convention (per `worktree-path-safety.md`) and matches what Plans 01 / 03 did. Not a code issue.

## User Setup Required

None — no external service configuration required.

## Manual Verification Suggestion (Plan 03 follow-up)

Per the plan's `<output>` recommendation: D-15 is genuinely rare in practice (§3.4 "not load-bearing"). To smoke-test the chip on the real canvas, the user must arrange a CAC with a hydraulic neighbor on its left/right AND a thermal neighbor on the same horizontal axis (e.g., another CAC, HD, or ConstantTemperature placed roughly co-linear). The chip appears at the bottom-right of the CAC node with amber background. If reproducing the D-15 setup proves awkward, a follow-up phase candidate (Phase 71) could expand the validator severity-routing into a unified panel that lists all hint tags in one place — but that's a polish concern, not a v1.2 must-have.

## Next Phase Readiness

- D-15 is now closed; Phase 64's full scope is covered (Plans 01–04). Wave 3 is the final wave for this phase.
- Phase 71 (design-system / unified validator panel) inherits the warning-severity discriminator pattern established here. The natural extension is to route every selector's tag list through a single panel keyed by severity (`error` → red ring + panel entry; `warning` → chip + panel entry).
- No blockers.

## Self-Check: PASSED

- `gui/src/lib/selectors/topologyHints.ts` exists.
- `gui/src/lib/selectors/__tests__/topologyHints.test.ts` exists; 9 cases, all green.
- `gui/src/components/__tests__/StreamNode.topologyHint.test.tsx` exists; 4 cases, all green.
- `gui/src/components/StreamNode.tsx` references `selectTopologyHints` (twice) and `topology-hint-chip` (once). `hasAnyError = hasError || hasBCError` is unchanged (no `hasTopologyHint` mixin).
- Commits `6beb06a`, `a915d85`, `d70ac74` all present in `git log`.
- Phase 64 + Phase 63.1 regression: 100/100 vitest cases pass across `autoflip.test.ts`, `topologyHints.test.ts`, `nodeErrors.test.ts`, `HydraulicEdge.bow.test.tsx`, `StreamNode.autoflip.test.tsx`, `StreamNode.topologyHint.test.tsx`, `StreamNode.test.tsx`, `StreamNode.anchor.test.tsx`, `BCEdge.test.tsx`.

---
*Phase: 64-connection-routing*
*Completed: 2026-05-14*
