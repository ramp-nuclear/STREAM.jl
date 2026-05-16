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
  modified:
    - gui/src/components/StreamNode.tsx
    - gui/src/index.css

key-decisions:
  - "Use template-literal className composition (matching the existing StreamNode pattern) rather than introducing the cn() helper — the plan said 'whatever class-composition helper StreamNode already uses', and StreamNode already used template literals, not cn."
  - "outline (not border) with outline-offset: 2px so the new ring does not enter the autoflip box-math and stays visually distinct from ReactFlow's box-shadow-based selection ring."
  - "CSS custom property fallback pattern (var(--stream-code-hover-ring-color, #38bdf8)) chosen so Phase 72 can override at :root or .dark without editing the rule body."

patterns-established:
  - "Per-node primitive-boolean selectors for code-panel ↔ canvas links — Phase 66 adds isCodeHovered / isCodePinned to the family that already includes hasAnchor / hasBCError. Future ephemeral cross-canvas highlight slices should follow the same shape."

requirements-completed: []

# Metrics
duration: ~18min (partial — Task 3 manual UAT pending)
completed: 2026-05-16 (Tasks 1+2; Task 3 awaits user UAT)
---

# Phase 66 Plan 05: StreamNode Hover Ring Summary

**StreamNode wired to the code-panel ↔ canvas traceability ring via per-node primitive-boolean selectors; placeholder CSS lands; Phase 72 handoff doc commits the re-tune scope. Manual UAT is the acceptance gate (Task 3, pending).**

## Status

**Tasks 1 and 2 complete and committed. Task 3 (manual UAT) is the
checkpoint gate — the user must walk the end-to-end bidirectional
traceability flow before the plan can be marked complete.**

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

## Pending — Task 3 (Manual UAT)

The plan's Task 3 is a `checkpoint:human-verify` gate. The user must walk
the full bidirectional traceability flow with a live dev server before
the plan can be finalized. Verification script lives in the plan file
(Task 3 `how-to-verify`) — covers:

- Code → Canvas hover (sub-block hover lights up canvas node ring)
- Code → Canvas pin (sub-block click toggles sticky ring; additive pin;
  click-empty / Esc clears pins)
- Canvas → Code jump (right-click "Show generated Julia code" → panel
  opens, scrolls, flashes, pins; canvas node gets pinned ring)
- Copy / Export buttons in BottomPanel (D-12 header format, disabled
  state, Tauri save dialog)
- Text-selection across sub-block boundaries
- Disabled state with empty canvas
- Regression sweep (full vitest run shows the same 5 pre-existing failures
  and nothing new)

The user types "approved" to mark Phase 66 ready for `/gsd:verify-work 66`,
or "regression: <describe>" to flag a gap and trigger a Plan 06 gap-closure.

## Self-Check

- `git log --oneline | grep -E "4f1b6d6|666b773|19ffceb"` → 3 commits found.
- `[ -f gui/src/components/__tests__/StreamNode.codeHover.test.tsx ]` → FOUND.
- `[ -f .planning/notes/phase-66-hover-ring-tuning.md ]` → FOUND.
- `grep -q "isCodeHovered" gui/src/components/StreamNode.tsx` → FOUND.
- `grep -q "stream-node--code-hover" gui/src/index.css` → FOUND.

## Self-Check: PASSED (Tasks 1+2 only — Task 3 pending UAT)

## Next Phase Readiness

After Task 3 user approval, Phase 66 is functionally complete. The next
step is `/gsd:verify-work 66` (goal-backward verification), followed by
archiving. Phase 72 will pick up the visual tuning per the handoff doc.

---
*Phase: 66-code-preview-rework*
*Plan: 5 — streamnode-hover-ring*
*Status: 2/3 tasks complete; manual UAT pending*
