---
phase: 68-layers-system-overhaul
plan: 01
subsystem: gui/layers
tags: [layers, refactor, types, tdd, shadcn]
dependency_graph:
  requires:
    - "gui/src/registry/types.ts (ComponentDefinition.category enum)"
  provides:
    - "gui/src/lib/layers.ts (4-layer pure API: LayerKey, ActiveLayers, ALL_LAYERS_ON, LAYER_KEYS, getComponentLayers, isNodeVisible, isEdgeDimmed)"
    - "gui/src/components/ui/checkbox.tsx (shadcn Checkbox primitive)"
  affects:
    - "gui/src/store/useStore.ts (Plan 02 will consume new types)"
    - "gui/src/lib/projectIO.ts (Plan 02 will migrate .scp layout block)"
    - "gui/src/components/CanvasPanel.tsx (Plan 03 will rewire enrichment)"
    - "gui/src/components/StreamNode.tsx (Plan 03)"
    - "gui/src/components/ToolboxPanel.tsx (Plan 03)"
    - "gui/src/components/LayersChip.tsx (Plan 04 — new file)"
tech-stack:
  added:
    - "shadcn Checkbox (re-exported from existing 'radix-ui' umbrella package)"
  patterns:
    - "Category-driven layer membership (not port sniffing)"
    - "Pure-function layer module — no react/zustand/@xyflow deps"
    - "TDD: RED → GREEN with separate commits per gate"
key-files:
  created:
    - "gui/src/components/ui/checkbox.tsx"
  modified:
    - "gui/src/lib/layers.ts (full rewrite)"
    - "gui/src/lib/__tests__/layers.test.ts (full rewrite)"
decisions:
  - "Category enum is the single source of truth for layer membership (D-05 + CONTEXT Claude's Discretion)"
  - "'Resources' category is intentionally NOT in CATEGORY_TO_LAYER_KEY — Resources have no canvas presence"
  - "getComponentLayers returns LayerKey[] (not single key) to keep room for future multi-layer components"
  - "isEdgeDimmed accepts LayerKey | null; null means 'edge has no layer association, never dimmed' — caller resolves edge layer from port type"
  - "shadcn Checkbox install uses the current registry shape (umbrella 'radix-ui' meta-package) — matches existing toggle.tsx pattern; no package.json/lock diff needed"
metrics:
  duration: "~10 min"
  completed: "2026-05-16"
  tasks_completed: 2
  files_changed: 3
  tests_added: 19
  tests_passing: 19
---

# Phase 68 Plan 01: Layers — types & primitive Summary

Rewrote `gui/src/lib/layers.ts` from the v0.8 `LayerView = "Hydraulic" | "Both" | "Thermal"` three-mode API to a 4-layer independent-toggle API driven by `ComponentDefinition.category` (Hydraulic / Thermal / Sources / ReactorPhysics), and installed the shadcn `Checkbox` primitive that Plan 04's LayersChip popover will consume.

## Contract Exposed to Downstream Plans

Plans 02/03/04 should import from `gui/src/lib/layers.ts`:

```ts
export type LayerKey = "Hydraulic" | "Thermal" | "Sources" | "ReactorPhysics";
export type ActiveLayers = Record<LayerKey, boolean>;
export const ALL_LAYERS_ON: ActiveLayers;          // all four true
export const LAYER_KEYS: readonly LayerKey[];      // canonical UI ordering
export function getComponentLayers(comp: ComponentDefinition): LayerKey[];
export function isNodeVisible(comp: ComponentDefinition, activeLayers: ActiveLayers): boolean;
export function isEdgeDimmed(edgeLayerKey: LayerKey | null, activeLayers: ActiveLayers): boolean;
```

**Deleted (clean break — no aliases):** `LayerView`, `isComponentVisibleInLayer`, `isNodeDimmed`, and the old port-sniffing `getComponentLayers` overload (returned `{hasFlow, hasThermal}`).

**Internal-only (do not import):** `CATEGORY_TO_LAYER_KEY` map. Note: registry category `"Reactor Physics"` (with space) maps to LayerKey `"ReactorPhysics"` (no space) — the LayerKey form is a TypeScript identifier. `"Resources"` is intentionally absent.

## Implementation Behavior (D-02 / D-04)

- **`isNodeVisible(comp, activeLayers)`** — D-02 "visible if ANY layer is active". A component with no layer association (Resources, unknown categories) returns `true` (always visible — layer system doesn't apply).
- **`isEdgeDimmed(edgeLayerKey, activeLayers)`** — D-04 "edges follow their own layer, not endpoint nodes". `null` layer never dims (no association — e.g. virtual ReactivityController links Plan 04 will introduce).

## Tasks Completed

| Task | Name                                          | Commit  | Files                                                                    |
| ---- | --------------------------------------------- | ------- | ------------------------------------------------------------------------ |
| 1    | Install shadcn Checkbox primitive             | 0bff2fb | gui/src/components/ui/checkbox.tsx                                       |
| 2a   | RED: failing tests for 4-layer API            | d298118 | gui/src/lib/\_\_tests\_\_/layers.test.ts                                 |
| 2b   | GREEN: rewrite layers.ts with new API         | 22e8e6b | gui/src/lib/layers.ts                                                    |

## Verification Results

```
$ cd gui && npx vitest run src/lib/__tests__/layers.test.ts
Test Files  1 passed (1)
     Tests  19 passed (19)
```

- `test -f gui/src/components/ui/checkbox.tsx` → exists, exports `Checkbox` Radix-based component.
- `grep -E 'export.*(LayerView|isComponentVisibleInLayer|isNodeDimmed)' gui/src/lib/layers.ts` → no matches (old API gone).
- `grep -E "from ['\"](react|zustand|@xyflow)" gui/src/lib/layers.ts` → no matches (pure module).
- Full `cd gui && npx tsc --noEmit` is **expected to fail** in this plan — Plan 02/03 consumers still reference deleted symbols. Wave 1's contract is solely `layers.ts` + `checkbox.tsx`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] Task 1 automated-verify command grep'd for `@radix-ui/react-checkbox` in `package.json` but no diff appeared**
- **Found during:** Task 1 (after `npx shadcn@latest add checkbox`)
- **Issue:** The plan's automated check expected `@radix-ui/react-checkbox` to be added to `gui/package.json`. The current shadcn registry instead generates `import { Checkbox as CheckboxPrimitive } from "radix-ui"` — the umbrella meta-package — which is **already** a top-level dependency in `package.json` (it backs `toggle.tsx` and other existing primitives). So no `package.json` / `package-lock.json` diff was produced.
- **Verification:** `node -e "console.log(Object.keys(require('radix-ui').Checkbox))"` → `['Checkbox', 'CheckboxIndicator', 'Indicator', 'Root', 'createCheckboxScope']` — Checkbox is resolvable at runtime.
- **Fix:** None needed. The plan's `<action>` rule "Do NOT modify the generated checkbox.tsx — it is the canonical shadcn output" took precedence over the literal package-name grep in `<automated>`. The functional intent (Checkbox primitive available for Plan 04) is satisfied. Plan-language drift only; no code change.
- **Files modified:** none beyond the shadcn-generated `gui/src/components/ui/checkbox.tsx`.
- **Commit:** 0bff2fb

**2. [Rule 3 — Blocking] Task 2 verify command `--reporter=basic` is not supported by Vitest v4.1.2**
- **Found during:** Task 2 RED gate
- **Issue:** `npx vitest run ... --reporter=basic` errors with "Failed to load url basic" — the `basic` reporter was renamed/removed in Vitest v4. Default reporter produces equivalent (more verbose) output.
- **Fix:** Dropped `--reporter=basic` flag; used the default reporter. Output is identical in semantics (pass/fail counts and per-test diagnostics).
- **Files modified:** none.
- **Commit:** n/a (verification-only deviation).

## TDD Gate Compliance

- **RED:** d298118 (`test(68-01): add failing tests for 4-layer independent API`) — 18 of 19 tests failed against the old `LayerView` API, confirming the contract did not previously exist.
- **GREEN:** 22e8e6b (`feat(68-01): rewrite layers.ts with 4-layer independent API`) — 19 of 19 tests pass.
- **REFACTOR:** none needed. New `layers.ts` is 138 lines with clear JSDoc on every export, single internal constant, no duplication.

## Known Stubs

None. `layers.ts` is fully implemented; the test suite exercises every exported symbol.

## Threat Flags

None. This plan is a pure refactor of a UI-layer-visibility module with no network, auth, persistence, or trust-boundary surface. The `category` lookup is a constant-time string match against a hardcoded internal map; no user input is interpreted.

## Self-Check

- [x] `gui/src/components/ui/checkbox.tsx` exists — verified via `test -f`
- [x] `gui/src/lib/layers.ts` rewritten — verified via grep of exports
- [x] `gui/src/lib/__tests__/layers.test.ts` rewritten — verified via vitest 19/19 passing
- [x] Commit 0bff2fb (Task 1) — `git log` shows hash
- [x] Commit d298118 (Task 2 RED) — `git log` shows hash
- [x] Commit 22e8e6b (Task 2 GREEN) — `git log` shows hash

## Self-Check: PASSED
