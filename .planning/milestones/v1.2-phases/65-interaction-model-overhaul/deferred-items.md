# Phase 65 — Deferred Items

Out-of-scope discoveries logged during plan execution.

## From Plan 13 (canvas-controls-dedup)

- **Pre-existing vitest failure:** `gui/src/components/sidebar/__tests__/SidebarPanel.anchors.test.tsx`
  expects element with text "Symmetric (L = R)" that no longer renders. Reproduced on the
  pre-edit base of plan 13 (`stash` confirmed). Not caused by Plan 13. Likely owned by a
  subsequent Phase-65 plan that touches BCsTabForm / SidebarPanel anchors.
- **Pre-existing tsc errors (12):** StreamNode Handle prop typing (4), BCsTabForm test casts
  (3), SidebarRouter `peaking` field (2), validation.test.ts unused imports (3). The plan's
  baseline mention of 11 is off by one but matches what's tracked under Phase 71's tsc
  cleanup scope.
