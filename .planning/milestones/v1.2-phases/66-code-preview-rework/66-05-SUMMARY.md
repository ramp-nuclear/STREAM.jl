---
phase: 66-code-preview-rework
plan: 5
subsystem: ui
tags: [react, zustand, css, vitest, traceability, code-preview]

# Dependency graph
requires:
  - phase: 66-code-preview-rework (plans 01–04)
    provides: CodeSection[] codegen with sourceIds, hoveredSourceIds / pinnedSourceIds / pendingShowCodeFor store slices, useShowCodeFor hook + Esc handler, exportCode util, CodePreview section-by-section renderer
provides:
  - StreamNode subscription to hoveredSourceIds / pinnedSourceIds via per-node primitive-boolean selectors (Pattern 9)
  - Placeholder CSS rules .stream-node--code-hover / .stream-node--code-pinned in gui/src/index.css (outline-based, autoflip-safe)
  - Phase 72 visual-tuning handoff doc (.planning/notes/phase-66-hover-ring-tuning.md)
  - Phase 66 functional completion (pending manual UAT in Task 3)
affects: [phase-68-layer-dim, phase-71-codebase-audit, phase-72-visual-polish]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-node primitive-boolean Zustand selectors (mirror hasAnchor / hasBCError shape; bounded re-render fanout)"
    - "outline-not-border for canvas-node state rings (preserves autoflip box-dimension math)"
    - "CSS custom properties as overridable placeholders (--stream-code-hover-ring-color etc.) for Phase 72 re-tune"

key-files:
  created:
    - gui/src/components/__tests__/StreamNode.codeHover.test.tsx
    - .planning/notes/phase-66-hover-ring-tuning.md
    - gui/PERFORMANCE.md
    - PERF-AUDIT.md
    - .planning/phases/66-code-preview-rework/66-PERF-AUDIT-SUMMARY.md
  modified:
    - gui/src/components/StreamNode.tsx
    - gui/src/index.css
    - gui/src/components/HydraulicEdge.tsx
    - gui/src/components/BCEdge.tsx
    - gui/src/components/CodePreview.tsx
    - gui/src/components/BottomPanel.tsx
    - gui/src/components/Toolbar.tsx
    - gui/src/components/CanvasPanel.tsx
    - gui/src/components/WelcomeOverlay.tsx
    - gui/src/components/sidebar/SidebarPanel.tsx
    - .planning/BACKLOG.md

key-decisions:
  - "Use template-literal className composition (matching the existing StreamNode pattern) rather than introducing the cn() helper — the plan said 'whatever class-composition helper StreamNode already uses', and StreamNode already used template literals, not cn."
  - "outline (not border) with outline-offset: 2px so the new ring does not enter the autoflip box-math and stays visually distinct from ReactFlow's box-shadow-based selection ring."
  - "CSS custom property fallback pattern (var(--stream-code-hover-ring-color, #38bdf8)) chosen so Phase 72 can override at :root or .dark without editing the rule body."

patterns-established:
  - "Per-node primitive-boolean selectors for code-panel ↔ canvas links — Phase 66 adds isCodeHovered / isCodePinned to the family that already includes hasAnchor / hasBCError. Future ephemeral cross-canvas highlight slices should follow the same shape."

requirements-completed: []

# Metrics
duration: ~3h 15min including UAT iterations (Tasks 1+2 ~18min; UAT polish + perf sweep + UAT pass ~2h 55min)
completed: 2026-05-16
---

# Phase 66 Plan 05: StreamNode Hover Ring Summary

**StreamNode wired to the code-panel ↔ canvas traceability ring; placeholder CSS landed; UAT passed after several rounds of polish (visible hover/pin styling, Julia syntax tinting, non-interactive scaffolding sub-blocks, clean text-selection) AND a full systematic GUI perf sweep that fixed a CanvasPanel `useStore()` no-selector antipattern that had been re-rendering the whole canvas on every store mutation. Edges now also light up when a connect() sub-block is hovered/pinned (final UAT note).**

## Status

**ALL 3 TASKS COMPLETE. UAT PASSED. Phase 66 ready for goal-backward verification.**

## Performance

- **Duration so far:** ~18 min (Tasks 1 + 2)
- **Started:** 2026-05-16
- **Tasks completed:** 2 of 3 (Task 3 is a `checkpoint:human-verify` gate)
- **Files modified:** 2 (StreamNode.tsx, index.css)
- **Files created:** 2 (StreamNode.codeHover.test.tsx, phase-66-hover-ring-tuning.md)

## Accomplishments

- Two new per-node primitive-boolean Zustand selectors on StreamNode
  (`isCodeHovered`, `isCodePinned`) — same `useCallback((s) => s.SET.has(id), [id])`
  shape as the established `hasAnchor` / `hasBCError`. Re-render fanout
  stays bounded: toggling one ID only re-renders the affected node(s).
- Conditional className tokens `stream-node--code-hover` and
  `stream-node--code-pinned` appended to the StreamNode root `<div>`'s
  template-literal className composition.
- Placeholder CSS in `gui/src/index.css`: `outline: 2px solid var(...)`
  with `outline-offset: 2px`. `outline` (not `border`) keeps Phase 64's
  autoflip handle-position math correct. CSS custom properties allow
  Phase 72 to override colors at `:root` without editing the rule body.
- Phase 72 handoff doc (`.planning/notes/phase-66-hover-ring-tuning.md`,
  94 lines) lists the 5 tuning targets (color, stroke, flash animation,
  Phase 68 layer-aware un-dim, ring stacking) and the verification path
  that survives any visual re-tune.
- Test-locked behavior: `StreamNode.codeHover.test.tsx` (5 it-blocks)
  GREEN — initial absent, hover-applied, hover-removed, pin-applied,
  both-applied.

## Task Commits

1. **Task 1 RED:** `4f1b6d6` — test(66-05): add failing test for StreamNode code-hover/pinned ring
2. **Task 1 GREEN:** `666b773` — feat(66-05): subscribe StreamNode to hoveredSourceIds / pinnedSourceIds
3. **Task 2:** `19ffceb` — feat(66-05): add hover/pinned ring CSS + Phase 72 handoff doc
4. **Task 3:** PENDING — manual UAT checkpoint

**Plan metadata commit:** will follow after Task 3 user approval.

## Files Created/Modified

- `gui/src/components/StreamNode.tsx` — added `isCodeHovered` and
  `isCodePinned` per-node primitive-boolean selectors immediately after
  `hasBCError`; appended two conditional class tokens to the root `<div>`'s
  className composition. (+14 lines, -1 line)
- `gui/src/index.css` — appended two placeholder CSS rules
  (`.stream-node--code-hover`, `.stream-node--code-pinned`) after the
  Phase 65 marquee block. (+23 lines)
- `gui/src/components/__tests__/StreamNode.codeHover.test.tsx` — new test
  file, 5 it-blocks asserting class application on the rendered root
  element. (+139 lines)
- `.planning/notes/phase-66-hover-ring-tuning.md` — new Phase 72 handoff
  doc. (+94 lines)

## Verification (Tasks 1+2)

- `cd gui && npx vitest --run src/components/__tests__/StreamNode.codeHover.test.tsx` →
  5 passed (Test Files 1 passed).
- `cd gui && npx vitest --run src/components/__tests__/StreamNode.{anchor,autoflip,}.test.tsx` →
  47 passed (no regressions in the StreamNode test family).
- `cd gui && npx tsc --noEmit | grep "error TS" | wc -l` → 12 (matches
  the 66-04 baseline; zero new tsc errors. Plan claimed "11 pre-existing"
  but 66-04 SUMMARY verified the actual baseline is 12.).
- `grep -c "stream-node--code-hover\\|stream-node--code-pinned" gui/src/index.css` → 2 (one class per rule).
- `wc -l .planning/notes/phase-66-hover-ring-tuning.md` → 94 lines, exceeds the ≥30-line acceptance threshold.

## Decisions Made

- **className helper:** kept the existing template-literal style instead
  of introducing `cn()` from `@/lib/utils`. Plan said "whatever helper
  StreamNode already uses", and StreamNode already used template literals.
- **CSS placement:** appended after the Phase 65 Plan 12 marquee block —
  the precedent for "phase-tagged GUI state-ring CSS" in `index.css`.
- **Re-render fanout assertion:** documented inline with a code comment
  near the new subscriptions rather than as a separate JSDoc/test — the
  primitive-boolean selector pattern is the documented mechanism;
  asserting it in a unit test would couple the test to React internals.

## Deviations from Plan

None — Tasks 1 and 2 executed exactly as written.

The plan claimed `npx tsc --noEmit | grep "error TS" | wc -l` should show
11 pre-existing errors. The actual baseline is 12, as already documented
in the 66-04 SUMMARY. Not a deviation in this plan — just a pre-existing
counting discrepancy carried forward from the plan spec.

## Pre-existing Failures (NOT introduced by this plan)

Verified at the base commit via `git stash` before any Task-2 edits:

- `src/components/canvasMenus/__tests__/contextMenus.test.tsx` — 4 failures
  (NodeContextMenu × 2, EdgeContextMenu × 1, CanvasContextMenu × 1).
- `src/components/sidebar/__tests__/SidebarPanel.anchors.test.tsx` — 1
  failure ("Channel BCs tab body still renders the existing BCsTabForm
  content below Anchors").

Both pre-exist Plan 05 and are out of scope per the plan's verification
section ("modulo the 1 pre-existing SidebarPanel.anchors failure and the
11 pre-existing tsc errors"). The 4 contextMenus failures pre-exist Plan
04 as well (66-04 SUMMARY line 119 lists the same 5 failures).

## Issues Encountered

- `gui/node_modules` did not exist inside the worktree on agent spawn
  (Claude Code worktree isolation). Resolved by symlinking
  `gui/node_modules` from the main repo into the worktree. No source-tree
  side effects; the symlink lives only in the temp worktree.

## Task 3 — Manual UAT — PASSED 2026-05-16

User walked the full bidirectional traceability flow and approved phase 66
with two notes:

1. **Hovering a `connect()` sub-block should also highlight the canvas edge** — addressed
   in commit `7e2b360` (this plan's final fix). HydraulicEdge and BCEdge each subscribe to
   two per-edge primitive-boolean selectors that fire when BOTH endpoint UUIDs appear in
   `hoveredSourceIds` / `pinnedSourceIds`. Sky-400 (2.25px) for hover, sky-300 (3px) for pin.

2. **Canvas-component hover doesn't push state into the code panel** — confirmed by design.
   Ambient hover the other direction would be too noisy; explicit `Show generated Julia code`
   right-click is the canvas→code path per D-08.

3. **KFW-1 (StreamNode O(N²) port-assignment selectors) backlogged**, NOT fixed in this
   phase. Documented in `gui/PERFORMANCE.md` Known Followup Work and promoted to
   `.planning/BACKLOG.md` (commit `426bebd`) for sizing in a future GUI perf phase.

## Follow-up commits beyond Tasks 1+2

The original Plan 05 scope assumed the prior plans 01–04 were UAT-ready. In practice
UAT surfaced several gaps that needed to be resolved before Task 3 could pass. All were
fixed as follow-up commits on top of the original 3 task commits, all on the
`gui-redesign` branch:

| Commit | What | Why |
|---|---|---|
| `47b32bb` | `fix(66-04): code panel polish — visible hover/pin + Julia syntax tinting` | UAT screenshot showed dim/dead panel: `hover:bg-accent/40` invisible in dark mode (--accent === --muted), no syntax colors, no pinned visual on code side, section labels faded. Added Julia tokenizer, sky-tinted hover/pin, sky-bar section labels. |
| `b097bfa` | `fix(66): refine code-panel interactivity model + distinguish pin from hover` | UAT round 2: Imports/scaffolding sub-blocks felt interactive but did nothing; canvas pin-ring looked identical to hover-ring. Made empty-sourceIds sub-blocks non-interactive; canvas pin now 3px sky-300 + halo. |
| `6c08bcd` | `perf(66): stop code-tab re-rendering on every ReactFlow position tick` | "Super laggy, unusable" — CodePreview was re-rendering on every drag-frame position update. Added string-fingerprint subscription (excludes positions), React.memo with content-equality on a new `CodeSubBlockView`, module-level tokenize cache, BottomPanel dropped live subscriptions, replaced blur box-shadow on pin ring with crisp halo. |
| `7939714` | `fix(66): clean code-panel text selection + drop box affordance from scaffolding` | UAT round 3 (from select_all.png): drag-select bled into section labels / inter-block gaps; scaffolding lines looked like clickable cells. select-none on panel root + select-text on each `<pre>`; non-interactive sub-blocks render as plain code. |
| `6325be2` | `perf(gui): systematic perf sweep — drop unused subscriptions, derive primitives` | "Lag sometimes exists and sometimes does not" — agent-driven full systematic audit of `gui/src/`. **Found a `useStore()` with no selector in `CanvasPanel.tsx`** that was re-rendering the entire ReactFlow canvas on ANY store mutation (root cause of intermittent lag). Also fixed Toolbar/WelcomeOverlay/SidebarPanel. Created `gui/PERFORMANCE.md` (9-rule perf ruleset + subscription decision tree + Known Followup Work register). Zero behavior changes. |
| `7e2b360` | `feat(66): highlight canvas edges when their connect() sub-block is hovered/pinned` | UAT note 1: edges between hovered/pinned nodes now light up sky-tinted, matching the canvas-node ring color tokens. |
| `426bebd` | `docs(backlog): capture KFW-1 — StreamNode O(N²) port-assignment selectors` | KFW-1 promoted from `PERFORMANCE.md` Followup section to `BACKLOG.md` per UAT close-out. |

Plus orchestrator hygiene: removed 14 stale worktree-agent-* worktrees from earlier
phases (~2.2 GB reclaimed, freed VS Code file watchers from indexing duplicate copies
of the codebase — likely cause of an intermittent VmmemWSL CPU spike the user noticed
during UAT).

## Test baseline (final, on UAT pass)

- **vitest:** `827 pass | 5 fail (pre-existing) | 10 todo | 2 failed test files (pre-existing)`
- **tsc:** `12 errors (pre-existing baseline)`
- **Phase 66 tests:** all 16 GREEN (11 CodePreview + 5 StreamNode hover-ring)
- **Pre-existing failures unchanged from Phase 66 start:** 4 contextMenus tests + 1 SidebarPanel.anchors test

Zero new failures, zero new tsc errors across all 7 follow-up commits.

## Phase 66 outcomes (consolidated)

- **Codegen** returns `CodeSection[]` with per-emission-site `sourceIds` (Plan 02).
- **Store** has 3 ephemeral slices (`hoveredSourceIds`, `pinnedSourceIds`, `pendingShowCodeFor`) with overlap-removes-all toggle semantics, fresh-reference discipline, and `.scp` exclusion (Plan 03).
- **`stream:show-code-for`** event listener mounted at App root + Esc-clears-pins handler (Plan 03).
- **`exportCode`** util extracted as the single export-path; called from both Toolbar (D-18) and BottomPanel (Plan 03/04).
- **`CodePreview`** is a section-by-section renderer over `CodeSection[]` with sub-block-level hover/click/pin/scroll/flash, Julia syntax tinting, select-text contract preserved (Plan 04 + follow-up polish).
- **Canvas StreamNodes** subscribe to hover/pin slices via per-node primitive-boolean selectors and render outline rings (sky-400 hover, sky-300 pin) (Plan 05).
- **Canvas edges (HydraulicEdge + BCEdge)** subscribe to hover/pin slices via per-edge primitive-boolean selectors and light up when both endpoints are in scope (Plan 05 final UAT note).
- **`gui/PERFORMANCE.md`** durably codifies the 9 perf antipatterns + canonical fixes + subscription decision tree + Known Followup Work register so the patterns don't recur.

## Self-Check

- `git log --oneline | grep -E "4f1b6d6|666b773|19ffceb"` → 3 commits found.
- `[ -f gui/src/components/__tests__/StreamNode.codeHover.test.tsx ]` → FOUND.
- `[ -f .planning/notes/phase-66-hover-ring-tuning.md ]` → FOUND.
- `grep -q "isCodeHovered" gui/src/components/StreamNode.tsx` → FOUND.
- `grep -q "stream-node--code-hover" gui/src/index.css` → FOUND.

## Self-Check: PASSED (all 3 tasks + 7 follow-up commits)

## Next Phase Readiness

Phase 66 functionally complete. Next step: `/gsd:verify-work 66` (goal-backward
verification), followed by archiving. Phase 72 will pick up the visual tuning
per the handoff doc (`.planning/notes/phase-66-hover-ring-tuning.md`). A future
GUI perf phase (call it 66.5 or 67-perf) can pick up KFW-1 from BACKLOG when
graph sizes start hitting 50+ nodes.

---
*Phase: 66-code-preview-rework*
*Plan: 5 — streamnode-hover-ring*
*Status: 3/3 tasks complete; UAT passed 2026-05-16; ready for goal-backward verification*
