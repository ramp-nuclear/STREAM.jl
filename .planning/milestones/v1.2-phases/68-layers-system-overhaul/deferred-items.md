# Phase 68 — Deferred Items

Out-of-scope discoveries logged during plan execution.

## Plan 68-03 — Pre-existing tsc errors in StreamNode.tsx

Discovered during Task 2 (StreamNode dual-layer port-handle dim).

Four pre-existing TS2322 errors on `Handle` components in StreamNode.tsx
(lines 215, 302, 462, 495). All four complain that the `data={{ portType }}`
prop is not assignable to `HandleProps`. Confirmed pre-existing by:

- Line 495 (bcPorts handle) was not modified by this plan and has the same
  error shape, so the issue is not introduced by Plan 68-03.
- Before Plan 68-03 changes, tsc reported 8 errors in StreamNode.tsx; after
  my changes it reports 4 — the new ones (was 4 about `LayerView`) are
  resolved; the 4 remaining about `Handle data` prop existed before.

Out of scope for Plan 68-03 (layer-system overhaul). Likely an `@xyflow/react`
v12 typing issue with `Handle`'s discriminated-union props. Fix in a follow-up
plan, e.g. by using a `data-port-type` HTML attribute (passes through DOM
attrs) or by widening with a type cast.

## Plan 68-04 — Stale `activeLayer` fixture in saveProjectAs.test.ts

Discovered during Task 2 final tsc gate (`cd gui && npx tsc --noEmit -p .`).

`gui/src/store/__tests__/saveProjectAs.test.ts` line 133 sets
`activeLayer: "Both"` in a `useStore.setState` fixture call. The
`activeLayer` field was deleted in Plan 68-02; the canonical replacement is
`activeLayers: { ...ALL_LAYERS_ON }` + `hideOffLayer: false` (see the
similar fixture in `gui/src/store/__tests__/useStore.codePanel.test.ts`
line 226). This is a Plan 68-02 sweep omission — that plan migrated three
test-file fixtures but missed this one.

Out of scope for Plan 68-04 (`files_modified` is LayersChip + CanvasPanel
only). Plan 68-05 or a sweep follow-up should:

```diff
-    activeLayer: "Both",
+    activeLayers: { Hydraulic: true, Thermal: true, Sources: true, ReactorPhysics: true },
+    hideOffLayer: false,
```

This is a single-line fix but introducing it here would violate the plan's
file-modification contract.

## Plan 68-04 — Other pre-existing tsc errors (not introduced by Phase 68)

The full `cd gui && npx tsc --noEmit -p .` report after Plan 04 GREEN +
mount includes the following NOT-touched-by-Phase-68 errors. Logged here
for completeness so any future audit knows they are not regressions:

- `src/components/sidebar/__tests__/BCsTabForm.test.tsx` (3× TS2352 —
  StreamNodeData cast errors at lines 290, 312, 315). Pre-existing.
- `src/components/sidebar/__tests__/SidebarRouter.test.tsx` (2× TS2353 —
  `peaking` property at lines 101, 144). Pre-existing.
- `src/lib/validation.test.ts` (3× TS6133 — unused type imports at lines
  6, 7, 8). Pre-existing.

All five files are untouched by Phase 68 and are owned by Phase 71 (tsc
baseline cleanup) per the master roadmap.
