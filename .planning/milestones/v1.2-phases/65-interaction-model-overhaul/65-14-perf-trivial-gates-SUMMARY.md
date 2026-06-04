---
phase: 65-interaction-model-overhaul
plan: 14
subsystem: gui/store + gui/App.tsx
tags: [perf, zustand, subscribe-with-selector, autorecover, title-sync, gap-closure, phase-65]
requires: [65-13]
provides:
  - subscribeWithSelector middleware on useStore (enables selector-gated subscribe overload)
  - selector-gated title-sync subscribe (setTitle IPC fires only on filePath/dirty change)
  - selector-gated autoRecover subscribe (writer.schedule/cancel fire only on isDirty transitions)
affects:
  - gui/src/store/useStore.ts
  - gui/src/App.tsx
tech_stack:
  added:
    - zustand/middleware (already bundled with zustand 5.0.12; no new dependency)
  patterns:
    - "create<T>()(subscribeWithSelector((set, get) => ({ ... })))"
    - "useStore.subscribe(selector, listener, { equalityFn? })"
key_files:
  created:
    - gui/src/store/__tests__/subscribeWithSelector.test.ts
  modified:
    - gui/src/store/useStore.ts
    - gui/src/App.tsx
decisions:
  - "Selector-gated semantics (2s after first dirty edit) preferred over closure-tracked rapid-reset; documented inline. Trivial fix only — autoflip memoization + onNodeDragStop dirty flipping deferred to a future perf phase."
metrics:
  duration: ~15 minutes
  completed: 2026-05-15
---

# Phase 65 Plan 14: Perf Trivial Gates Summary

Closed the UAT Test 4 minor perf gap's trivial dimension: wrapped useStore with the
`subscribeWithSelector` middleware and converted two per-set subscribes (App.tsx title-sync
and useStore autoRecover) to fire only on the values they actually depend on.

## What Shipped

### 1. `subscribeWithSelector` middleware on useStore

- Added `import { subscribeWithSelector } from "zustand/middleware"` at line 2 of
  `gui/src/store/useStore.ts` (no new package dependency — zustand 5.0.12 already bundles it).
- Wrapped the store factory: `create<AppState>()(subscribeWithSelector((set, get) => ({ ... })))`.
- Closing parens count corrected from `}));` to `})));` (one extra `)` to close
  `subscribeWithSelector`).

The middleware adds a 2-arg / 3-arg overload `useStore.subscribe(selector, listener, options?)`
without breaking the legacy single-arg `useStore.subscribe(listener)`. Existing callers (every
non-Plan-14 subscribe site) continue to fire on every `set()` exactly as before.

### 2. App.tsx title-sync gate

`gui/src/App.tsx` lines 288-296: replaced the single-arg subscribe with the selector-gated
overload. The new shape selects `{ filePath: state.currentFilePath, dirty: state.isDirty }`
and the listener invokes `syncTitle(filePath, dirty)` only when an inline equality function
detects an actual change in either field. Tauri's `setTitle` IPC is therefore no longer fired
on every store `set()` (per-pixel mousemove during node drag was the worst case).

Initial-call line and `syncTitle` body are unchanged — the functional contract ("title reflects
filename + dirty marker") is preserved.

### 3. useStore.ts autoRecover gate (line ~2699)

Replaced the single-arg subscribe inside `initAutoRecover` with the primitive-selector overload
selecting `state.isDirty`. The listener calls `writer.schedule()` on `false→true` and
`writer.cancel()` on `true→false`, never both on the same `set()`.

Documented inline that this is a deliberate semantic shift from Plan 07's "rapid edits reset the
2s timer" to "2s after the first edit in a dirty session" — both satisfy the AutoRecover safety
goal of "save within ~2s of user activity". Alternative (closure-tracked rapid-reset) was
considered and rejected per the plan's "decision for this plan" guidance; the selector-gated
version is simpler and provides a stricter (not weaker) guarantee.

## Verification

| Check                                           | Result                                                |
| ----------------------------------------------- | ----------------------------------------------------- |
| `grep "subscribeWithSelector" useStore.ts`      | 2 hits (import + create call)                         |
| `grep "equalityFn" App.tsx`                     | 1 hit (title-sync subscribe)                          |
| New vitest suite (3 cases)                      | 3 / 3 pass                                            |
| Full store vitest (207 tests)                   | 207 / 207 pass                                        |
| Full gui vitest run                             | 769 pass, 1 fail (Phase 71-owned SidebarPanel flake)  |
| `tsc --noEmit` error count                      | 12 (unchanged from pre-edit baseline)                 |
| Atomic commits recorded                         | 3 (test RED, feat middleware, perf gates)             |

Notes:
- Baseline `tsc` reported 12 errors (plan stated "≤ 11" but the live baseline in this worktree
  is 12 — Phase 71 owns the pre-existing errors). Final count is identical to baseline, so the
  "tsc not worse" gate passes.
- The single vitest failure (`SidebarPanel.anchors.test.tsx`) is documented as a pre-existing
  Phase-71-owned flake and explicitly excepted by Plan 14's success criteria.

## Commits

| Hash    | Message                                                          |
| ------- | ---------------------------------------------------------------- |
| 3de80a9 | test(65-14): RED — subscribeWithSelector overload                |
| 065701e | feat(65-14): subscribeWithSelector middleware on useStore        |
| 456d25f | perf(65-14): gate title-sync + autoRecover subscribes            |

## Deviations from Plan

None — plan executed exactly as written. The plan's `<interfaces>` block was followed
verbatim; the selector-gated autoRecover variant was preferred (per the plan's explicit
"decision for this plan" guidance) over the closure-tracked rapid-reset alternative.

One non-deviation worth noting: the tsc baseline was 12 (not 11 as the plan's `<verify>` block
assumed). The plan's actual gate is "≤ baseline"; final count of 12 matches baseline, so the
gate passes. No code change was made for this — the count is just acknowledged.

## Self-Check: PASSED

- `gui/src/store/useStore.ts`: FOUND, contains `subscribeWithSelector` import + middleware composition.
- `gui/src/App.tsx`: FOUND, contains `equalityFn` + inline `a.filePath === b.filePath && a.dirty === b.dirty`.
- `gui/src/store/__tests__/subscribeWithSelector.test.ts`: FOUND.
- Commit 3de80a9: FOUND.
- Commit 065701e: FOUND.
- Commit 456d25f: FOUND.
