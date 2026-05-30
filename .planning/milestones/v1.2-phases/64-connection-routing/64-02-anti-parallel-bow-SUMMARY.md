---
phase: 64-connection-routing
plan: 02
subsystem: gui-connection-routing
tags: [gui, edge-routing, hydraulic-edge, anti-parallel-bow, tdd]
dependency-graph:
  requires:
    - "gui/src/store/useStore (edges array, type='hydraulicEdge' tagging by enrichEdges)"
    - "@xyflow/react 12.10.2 (getSmoothStepPath, BaseEdge, Position, EdgeProps)"
  provides:
    - "HydraulicEdge.tsx — anti-parallel ±8px perpendicular bow for bidirectional hydraulic pairs (D-06/D-07/D-08/D-17)"
    - "HydraulicEdge.bow.test.tsx — Vitest contract for bow detection, type filter, direction stability, render-storm guard"
  affects:
    - "Visual rendering of bidirectional hydraulic pairs in CanvasPanel (Example-1 X-cross fix)"
tech-stack:
  added: []
  patterns:
    - "Pattern 3 (RESEARCH.md): edges enrich themselves via useStore.getState() synchronously inside render — no hook subscription (avoids render-storm at drag time)"
    - "Pre-offset endpoint coords perpendicular to dominant axis before getSmoothStepPath (RESEARCH.md option (a)) — parallel-shifted smoothstep equivalent to a midpoint bow"
    - "Lexicographic id ordering for stable bow-direction selection (no flicker)"
key-files:
  created:
    - "gui/src/components/__tests__/HydraulicEdge.bow.test.tsx"
  modified:
    - "gui/src/components/HydraulicEdge.tsx"
decisions:
  - "D-06: in-scope as custom-edge tweak (not architectural)"
  - "D-07: constant ±8px perpendicular bow (no distance scaling, no Settings entry)"
  - "D-08: sibling detection swaps source/target between the two edges"
  - "D-17: same-type-only filter — only e.type === 'hydraulicEdge' counts as a sibling"
  - "Bow strategy: pre-offset endpoint coords before getSmoothStepPath (option (a))"
  - "Direction stability: smaller-id bows +8, larger-id bows -8 (lexicographic id compare)"
metrics:
  duration: "~12 minutes"
  completed: "2026-05-14"
  tasks: 2
  files_created: 1
  files_modified: 1
  tests_added: 7
---

# Phase 64 Plan 02: Anti-parallel bow on HydraulicEdge Summary

Bidirectional hydraulic pairs now render with a ±8px perpendicular bow on the smoothstep midline so the two siblings render as parallel offsets instead of overlapping (Example-1 X-cross fix); cross-type pairs and solitary edges render unchanged.

## What Was Built

`HydraulicEdge.tsx` gained the anti-parallel bow logic per D-06/D-07/D-08 and the D-17 same-type-only refinement. The sibling lookup runs synchronously via `useStore.getState().edges` inside the render function — Pattern 3 from `64-RESEARCH.md` — so no hook subscription is introduced and the per-drag-tick edge re-render does not balloon into a store-update render storm.

When the sibling exists, the implementation pre-offsets both endpoint coordinates perpendicular to the dominant axis by `±BOW_PX` (=8) BEFORE calling `getSmoothStepPath`. For a horizontal edge (`sourcePosition` is `Position.Left` or `Position.Right`) the bow shifts `sourceY` / `targetY`; otherwise it shifts `sourceX` / `targetX`. The smaller-id sibling bows `+BOW_PX`, the larger-id bows `-BOW_PX` — lexicographic id ordering keeps the two siblings on opposite sides and prevents flicker.

## Final Diff Summary — `gui/src/components/HydraulicEdge.tsx`

Before (32 lines): straight `getSmoothStepPath` with no store access.

After (~93 lines):
- New import: `useStore`, `Position` (the latter for the horizontal-axis check).
- New module-scope constant: `const BOW_PX = 8` (D-07).
- Inside the function body:
  1. `useStore.getState().edges` (synchronous, no hook).
  2. `find` a same-type swap sibling — filters by `e.type === "hydraulicEdge"` (D-17) AND `e.source === target && e.target === source` (D-08).
  3. Compute signed bow by lexicographic id compare.
  4. Decide axis from `sourcePosition` (horizontal vs vertical).
  5. Pre-offset endpoint coords perpendicular to the axis.
  6. Call `getSmoothStepPath` with the adjusted coords.
- `BaseEdge` render is unchanged (still consumes inbound `style` + `markerEnd`).
- Long doccomment block documents D-06/D-07/D-08/D-17, Pattern 3, and the option-(a) strategy choice with a reference to RESEARCH.md.

## Chosen Bow Strategy

**Option (a) — pre-offset endpoint coordinates perpendicular to the dominant axis before calling `getSmoothStepPath`** (RESEARCH.md §"Anti-parallel bow inside HydraulicEdge", Open Question 2).

Rationale: `getSmoothStepPath` has no native perpendicular-bow knob; option (a) keeps using the ReactFlow primitive untouched and produces a parallel-shifted smoothstep — visually equivalent to a "bow" at the midpoint where the two siblings would otherwise overlap. Option (b) (hand-built SVG path string with a perpendicular kink) was rejected as more complex for no visual benefit. The verifier should eyeball-test against `example_1.png` per RESEARCH.md.

## Tests (7 total — all green)

`gui/src/components/__tests__/HydraulicEdge.bow.test.tsx` — `@vitest-environment happy-dom`, `@xyflow/react`'s `ReactFlowProvider` + `<svg>` wrapper.

1. **Baseline (no sibling) → pixel-identical to pre-Phase-64 smoothstep.** Asserts the rendered `d` attribute is exactly the path returned by `getSmoothStepPath` with the un-offset coords; midline y is 0.
2. **D-08 smaller-id (`e1`) bows +8.** Two hydraulic edges, opposite directions; the rendered path midline y is `+8`.
3. **D-08 larger-id (`e2`) bows −8.** Same fixture, larger-id sibling; midline y is `−8`.
4. **D-08 opposite-direction guarantee.** `yE1 === -yE2` and `|yE1| === 8`. Direction stability is end-to-end (no flicker risk).
5. **D-17 BCEdge sibling → no bow.** Hydraulic `A→B` + bcEdge `B→A` → midline y is 0; the BCEdge does NOT count as a sibling.
6. **D-17 thermal-typed sibling → no bow.** Hydraulic `A→B` + a `type: "thermalEdge"` edge `B→A` → midline y is 0; the filter is type-based, not just direction-based.
7. **Render-storm guard.** Reads the `HydraulicEdge.tsx` source via `node:fs` and asserts the source does not contain `useStore(` (the hook subscription form). The synchronous `useStore.getState()` form is NOT matched by the regex — confirmed by inspection.

A helper `extractMidlineY(d: string)` parses the first y coordinate from the smoothstep path's `M{x} {y}L…` format — for the horizontal `(0,0) → (200,0)` fixture this is the midline y.

## Render-Storm Guard Confirmation

`grep -E "useStore\(" gui/src/components/HydraulicEdge.tsx | grep -v "useStore\.getState"` returns no matches — `HydraulicEdge.tsx` contains exactly two `useStore` references: the named import and the synchronous `useStore.getState().edges` read inside the render body. **No hook subscription** is introduced (Pattern 3 contract upheld).

## Regression Check

`pnpm -C gui vitest run src/components/__tests__/BCEdge.test.tsx` — all 7 BCEdge tests still green. The full GUI suite shows 609 passed / 1 pre-existing failure (`SidebarPanel.anchors.test.tsx`, unrelated to Plan 64-02; confirmed pre-existing by re-running with my changes stashed).

## Pre-existing failure — out of scope (logged for orchestrator)

`gui/src/components/sidebar/__tests__/SidebarPanel.anchors.test.tsx` > "Channel BCs tab body still renders the existing BCsTabForm content below Anchors" is failing on the worktree-base commit (`a26d130`) BEFORE this plan's changes. Not caused by this plan; not fixed by this plan (Phase 64 plan 02 scope boundary).

## Deviations from Plan

**None — plan executed exactly as written.** No Rule 1/2/3 auto-fixes were triggered; no architectural Rule 4 questions arose. The doccomment had to avoid containing the literal string `useStore(` because the test's render-storm guard regex matches the source verbatim — reworded "Subscribing via `useStore(...)`" to "Subscribing via the `useStore` hook" to keep the guard test honest.

## Commits

- `b8c1207` — `test(64-02): add failing tests for anti-parallel bow` (RED — 7 tests, 3 failing as expected)
- `3d4cdd8` — `feat(64-02): anti-parallel bow on HydraulicEdge` (GREEN — implementation; all 7 tests pass; BCEdge regression suite still green)

## Self-Check: PASSED

- File `gui/src/components/HydraulicEdge.tsx` exists and contains `const BOW_PX = 8`, `useStore.getState()`, and `"hydraulicEdge"` literal — FOUND.
- File `gui/src/components/__tests__/HydraulicEdge.bow.test.tsx` exists with `@vitest-environment happy-dom`, 7 `it(` calls, and both `"hydraulicEdge"` + `"bcEdge"` literals — FOUND.
- Commit `b8c1207` (RED test commit) — FOUND in git log.
- Commit `3d4cdd8` (GREEN feat commit) — FOUND in git log.
- `pnpm -C gui vitest run src/components/__tests__/HydraulicEdge.bow.test.tsx` exits 0 with 7 tests passing — CONFIRMED.
- `pnpm -C gui vitest run src/components/__tests__/BCEdge.test.tsx` exits 0 with all tests passing — CONFIRMED.
- Render-storm guard grep returns no matches — CONFIRMED.
