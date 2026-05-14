---
phase: 64-connection-routing
plan: 01
subsystem: ui
tags: [react-flow, autoflip, pure-module, geometric-rules, vitest, typescript]

# Dependency graph
requires:
  - phase: 61-registry-audit-rewrite-for-v1-1
    provides: "Port.default_axis / Port.pair_with / Port.array_size schema fields consumed by the autoflip thermal-pair rules"
  - phase: 63.1-bc-architecture-rework-unified-bcs-tab
    provides: "Pure-selector pattern (gui/src/lib/selectors/nodeErrors.ts) — the purity discipline mirrored by autoflip"
provides:
  - "gui/src/lib/autoflip.ts pure module — five rule functions + two exported types"
  - "Vitest coverage of every locked decision D-08..D-18 (22 it-cases)"
  - "Foundation for Plans 03 (FlowPort/thermal handle render integration) and 04 (anti-parallel bow + topology-hint validator)"
affects:
  - 64-02-anti-parallel-bow
  - 64-03-streamnode-integration
  - 64-04-topology-hint-validation

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pure-module purity invariant: only `import type` from peer modules; zero runtime React / ReactFlow / Zustand imports (precedent: gui/src/lib/layers.ts, gui/src/lib/selectors/nodeErrors.ts)"
    - "Caller-injected `getComponent` callback instead of importing the registry singleton (keeps the module tree-shakeable and trivially mockable)"
    - "Suffix-definitive thermal-port mapping: `_left` → spatial left/top, `_right` → spatial right/bottom; only the axis flips (D-18)"

key-files:
  created:
    - gui/src/lib/autoflip.ts
    - gui/src/lib/__tests__/autoflip.test.ts
  modified: []

key-decisions:
  - "Honored D-18 strictly: per-suffix side assignment is fixed; only the axis flips based on aggregated |sumDx| vs |sumDy|."
  - "Implemented same-type-only anti-parallel sibling filter (D-17): `findAntiParallelSibling` rejects when either edge is not type=='hydraulicEdge'."
  - "Kept registry-singleton dependency out of the module: `getComponent` is a callback parameter, not an import."
  - "Used Vitest `@vitest-environment node` (no DOM) — these are pure functions; happy-dom would be wasted overhead."

patterns-established:
  - "Pure geometric-rule module: deterministic (state, ids) → primitive result, zero side effects, zero runtime hooks."

requirements-completed: []

# Metrics
duration: 2min
completed: 2026-05-14
---

# Phase 64 Plan 01: Autoflip Pure Module Summary

**Pure TypeScript module `gui/src/lib/autoflip.ts` encoding all locked geometric autoflip rules (D-08..D-18) as five testable functions, with 22 Vitest cases covering every decision ID.**

## Performance

- **Duration:** ~2 min (executor wall-clock)
- **Started:** 2026-05-14T13:39Z (worktree base, post-`npm install`)
- **Completed:** 2026-05-14T13:42Z
- **Tasks:** 2 (Task 1 RED, Task 2 GREEN)
- **Files created:** 2

## Accomplishments

- Pure module `gui/src/lib/autoflip.ts` (326 lines) exporting:
  - `type Side = "left" | "right" | "top" | "bottom"`
  - `type OffsetStyle = { left?: string; top?: string }`
  - `function resolveFlowPortSide(nodes, edges, nodeId, portName, defaultSide, getComponent): Side`
  - `function resolveAsymmetricOffset(nodes, edges, nodeId, side, portName, defaultSide, getComponent): OffsetStyle | undefined`
  - `function resolveThermalPairSides(nodes, edges, nodeId, thisPortName, pairWith, defaultAxis, getComponent): { thisSide: Side; pairSide: Side }`
  - `function detectAxisCollision(nodes, edges, nodeId, getComponent): boolean`
  - `function findAntiParallelSibling(edge, edges): Edge | undefined`
- Test file `gui/src/lib/__tests__/autoflip.test.ts` (574 lines) — 22 Vitest `it(...)` cases, one or more per D-ID:
  | D-ID | Coverage |
  | --- | --- |
  | D-08 | `findAntiParallelSibling` — same-direction-swap detection |
  | D-09 | `resolveAsymmetricOffset` — 25%/75% offsets on same-side collision; negative case returns `undefined` |
  | D-10 | Reading-direction axis: top/bottom side → `left` percentage key; left/right side → `top` percentage key |
  | D-11 | Zero-edges fallback to registry defaults for both FlowPort and thermal-pair |
  | D-12 | `resolveAsymmetricOffset` returns `undefined` for thermal-only components (no FlowPort sibling) |
  | D-13 | `|dx| == |dy|` tie-break prefers horizontal (FlowPort + thermal-pair aggregate) |
  | D-14 | Strict comparison: single-pixel asymmetry flips the axis |
  | D-15 | `detectAxisCollision` true when both axes horizontal or both vertical; false otherwise |
  | D-16 | Node-center anchor (fallbacks to 140×70 when `measured` unset) |
  | D-17 | `findAntiParallelSibling` rejects bcEdge or non-`hydraulicEdge` siblings |
  | D-18 | Suffix-definitive: `thermal_left` → left or top; `thermal_right` → right or bottom; only axis flips |
- Purity invariant verified: `grep -v '^import type' gui/src/lib/autoflip.ts | grep -cE 'from "@xyflow/react"|from "react"|from "zustand"'` returns 0.

## Task Commits

1. **Task 1: RED — Write autoflip rule unit tests** — `1939246` (test)
2. **Task 2: GREEN — Implement autoflip pure module** — `4ebeaed` (feat)

## Files Created/Modified

- `gui/src/lib/autoflip.ts` (created) — Pure geometric autoflip rules (5 functions, 2 types). Mirrors `gui/src/lib/layers.ts` in shape and docstring discipline.
- `gui/src/lib/__tests__/autoflip.test.ts` (created) — Vitest spec; `@vitest-environment node`; inline fixture helpers (`makeNode`, `makeEdge`, `makeGetComponent`, fixture component definitions for Pump / CAC / HD).

## Final Shape of `autoflip.ts` Exports

```typescript
export type Side = "left" | "right" | "top" | "bottom";
export type OffsetStyle = { left?: string; top?: string };

export function resolveFlowPortSide(
  nodes: Node[],
  edges: Edge[],
  nodeId: string,
  portName: string,
  defaultSide: Side,
  _getComponent: (id: string) => ComponentDefinition | undefined,
): Side;

export function resolveAsymmetricOffset(
  nodes: Node[],
  edges: Edge[],
  nodeId: string,
  side: Side,
  portName: string,
  defaultSide: Side,
  getComponent: (id: string) => ComponentDefinition | undefined,
): OffsetStyle | undefined;

export function resolveThermalPairSides(
  nodes: Node[],
  edges: Edge[],
  nodeId: string,
  thisPortName: string,
  pairWith: string,
  defaultAxis: "horizontal" | "vertical",
  _getComponent: (id: string) => ComponentDefinition | undefined,
): { thisSide: Side; pairSide: Side };

export function detectAxisCollision(
  nodes: Node[],
  edges: Edge[],
  nodeId: string,
  getComponent: (id: string) => ComponentDefinition | undefined,
): boolean;

export function findAntiParallelSibling(
  edge: Edge,
  edges: Edge[],
): Edge | undefined;
```

## Test Count and D-ID Coverage

22 Vitest cases across 5 `describe` blocks:

| describe | it count | D-IDs covered |
| --- | --- | --- |
| `resolveFlowPortSide` | 7 | D-11, D-13, D-14, D-16; plus targetHandle filter regression |
| `resolveAsymmetricOffset` | 4 | D-09 (same-side + negative), D-10, D-12 |
| `resolveThermalPairSides` | 5 | D-11 (vertical default), D-11 (horizontal default), D-18 (vertical axis), D-18 (horizontal axis), D-13 tie-break |
| `detectAxisCollision` | 3 | D-15 (collision true), D-15 (no collision), D-15 (no thermal pair → false) |
| `findAntiParallelSibling` | 3 | D-08, D-17 (bcEdge), D-17 (thermal-styled edge) |

Total: 22 cases (plan required ≥18). All green via `npx vitest run src/lib/__tests__/autoflip.test.ts`.

## Decisions Made

- **`getComponent` as a callback parameter rather than a registry import:** Keeps the module fully tree-shakeable and trivially mockable from the test file. Matches the discipline of `gui/src/lib/selectors/nodeErrors.ts`, which takes a state-shape sub-slice rather than importing the full Zustand store.
- **Single-edge resolution for `resolveFlowPortSide`:** The autoflip rule uses the FIRST edge wired to the port — matches the §3.3 spec's "facing the connected neighbor" wording. A FlowPort with multiple connections is not a documented case (the registry connection rules forbid it).
- **Aggregate signed-magnitude for thermal-pair axis:** Used `|sumDx|` and `|sumDy|` (per-edge magnitudes, then summed) rather than `|sum of signed dx|`. Matches the RESEARCH.md `## Code Examples` reference; "where are the neighbors" is the question, not "which side wins by signed mass."

## Deviations from Plan

None — plan executed exactly as written. The implementation mirrors the pseudocode in 64-RESEARCH.md `## Code Examples` with no untested complexity added. The two `_getComponent` callback parameters that the simpler functions don't actually consume are intentionally retained to keep the public callback signature uniform across all resolution functions (callers don't have to remember which functions need it).

## Issues Encountered

- **No `node_modules/` in fresh worktree:** Ran `npm install` once to bring up Vitest. This is expected worktree behavior (a fresh worktree has no node_modules) — not a planning gap. The install added 1051 packages from the existing lockfile (no version drift).

## Deferred Issues

- **Pre-existing TypeScript errors in unrelated files** (`gui/src/components/StreamNode.tsx`, `gui/src/components/sidebar/__tests__/BCsTabForm.test.tsx`, `gui/src/lib/validation.test.ts`, `gui/src/components/sidebar/__tests__/SidebarRouter.test.tsx`): Surfaced by `npx tsc --noEmit` but not caused by autoflip. Out of scope per the SCOPE BOUNDARY rule; my new files (`autoflip.ts` and `autoflip.test.ts`) compile clean. Logging here so a future cleanup phase can pick them up.

## Threat Flags

None — pure-module change. No new network endpoints, no auth paths, no file access, no schema changes.

## Self-Check

- [x] `gui/src/lib/autoflip.ts` exists (326 lines).
- [x] `gui/src/lib/__tests__/autoflip.test.ts` exists (574 lines, 22 `it` cases).
- [x] Commit `1939246` exists in `git log`.
- [x] Commit `4ebeaed` exists in `git log`.
- [x] `npx vitest run src/lib/__tests__/autoflip.test.ts` exits 0 with 22 passing.
- [x] Purity invariant: zero runtime imports from `@xyflow/react` / `react` / `zustand`.

## Self-Check: PASSED

## Next Plan Readiness

- Plan 03 (StreamNode handle render integration) can now `import { resolveFlowPortSide, resolveAsymmetricOffset, resolveThermalPairSides } from "@/lib/autoflip"` and wire them into `FlowPortHandle` / thermal handle render blocks. Use `useStore(useCallback(s => resolveFlowPortSide(s.nodes, s.edges, id, name, default, getComp), [...]))` to keep a primitive-string return per Phase 63.1's anti-render-storm discipline.
- Plan 02 (anti-parallel bow inside `HydraulicEdge.tsx`) can `import { findAntiParallelSibling } from "@/lib/autoflip"` and apply the ±8px perpendicular offset per D-07.
- Plan 04 (topology-hint validator) can `import { detectAxisCollision } from "@/lib/autoflip"` directly inside `gui/src/lib/selectors/topologyHints.ts` (new file) and surface `'topology-axis-collision'` for D-15.

---

*Phase: 64-connection-routing*
*Plan: 01*
*Completed: 2026-05-14*
