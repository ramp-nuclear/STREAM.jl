---
phase: 64-connection-routing
reviewed: 2026-05-14T00:00:00Z
depth: standard
files_reviewed: 9
files_reviewed_list:
  - gui/src/lib/autoflip.ts
  - gui/src/lib/__tests__/autoflip.test.ts
  - gui/src/components/HydraulicEdge.tsx
  - gui/src/components/__tests__/HydraulicEdge.bow.test.tsx
  - gui/src/components/StreamNode.tsx
  - gui/src/components/__tests__/StreamNode.autoflip.test.tsx
  - gui/src/lib/selectors/topologyHints.ts
  - gui/src/lib/selectors/__tests__/topologyHints.test.ts
  - gui/src/components/__tests__/StreamNode.topologyHint.test.tsx
findings:
  critical: 0
  warning: 6
  info: 6
  total: 12
status: issues_found
---

# Phase 64: Code Review Report

**Reviewed:** 2026-05-14
**Depth:** standard
**Files Reviewed:** 9
**Status:** issues_found

## Summary

Phase 64 delivers (1) a pure geometric autoflip module (`autoflip.ts`), (2) anti-parallel ±8 px perpendicular bow in `HydraulicEdge.tsx`, (3) per-port FlowPort/ThermalPortHandle sub-components wired into `StreamNode.tsx`, and (4) a non-blocking topology-hint chip via the `topologyHints.ts` selector. The phase-locked constraints — pure helper, `useStore.getState()` Pattern 3 read in the edge, severity-isolated warning chip — are honored.

There are no critical correctness bugs, but several warnings highlight real fragility: the FlowPort heuristic disagrees with the thermal aggregation strategy on multi-edge ports, the anti-parallel-sibling rule is implemented twice (once in `autoflip.ts` and once inline in `HydraulicEdge.tsx`) and could drift, `OffsetStyle` round-tripping silently drops one axis if both keys ever co-exist, and several docstrings undersell or misstate the underlying math. The `portName.includes("in")` heuristic is a foot-gun that survives only because the current registry happens to be well-behaved.

## Warnings

### WR-01: `findAntiParallelSibling` is duplicated inline in `HydraulicEdge.tsx`

**File:** `gui/src/components/HydraulicEdge.tsx:53-60`
**Issue:** `autoflip.ts` exports `findAntiParallelSibling(edge, edges)` for exactly this consumer (D-08/D-17), but `HydraulicEdge.tsx` re-implements the swap-and-same-type filter inline:

```ts
const sibling = allEdges.find(
  (e) =>
    e.id !== id &&
    e.type === "hydraulicEdge" &&
    e.source === target &&
    e.target === source,
);
```

If D-17 ever broadens (e.g. excludes self-loops, includes a `selected` filter, or supports a future `hydraulicEdgeAnimated` variant), both copies must change in lockstep. `findAntiParallelSibling` is also tested independently — the inline version has no direct unit guarantee that it tracks the helper.

**Fix:** Replace the inline `.find` with a call to the helper:

```ts
import { findAntiParallelSibling } from "@/lib/autoflip";
// ...
const allEdges = useStore.getState().edges;
const thisEdge = allEdges.find((e) => e.id === id);
const sibling = thisEdge ? findAntiParallelSibling(thisEdge, allEdges) : undefined;
```

The extra lookup is O(E); to avoid the second scan, expose a `findAntiParallelSiblingById(id, edges)` overload that does both in one pass.

---

### WR-02: `portName.includes("in")` is a substring match — fragile across future port names

**File:** `gui/src/lib/autoflip.ts:81, 157, 271, 201` (and `StreamNode.tsx:201`)
**Issue:** The "is this an input port?" heuristic is `port.name.includes("in")`. The current registry only declares `port_in` / `port_out`, but the substring `"in"` also matches names like `inlet`, `pin`, `engine_in_a`, `drain` (`drain` contains `in`), `injection`, `spin`. Any future FlowPort name that contains the substring `in` outside the prefix is silently classified as an input port. Conversely, a non-`in` input name (`primary`, `feed`) would be classified as an output.

The thermal path uses `endsWith("_left")` which is similarly suffix-based and similarly fragile if a port is named `thermal_lefthand_*` (no current case, but worth tightening).

**Fix:** Use exact-name matching or prefix matching aligned with the registry convention:

```ts
const isInPort = portName === "port_in" || portName.startsWith("port_in");
```

Or, more robustly, derive the role from the `Port` definition (the registry knows whether a port is logically `in` vs `out`; pass that into the helper rather than re-deriving from the string). The unused `_getComponent` parameter is already there to support this — wire it.

---

### WR-03: `resolveFlowPortSide` uses only the FIRST connected edge — inconsistent with thermal aggregation

**File:** `gui/src/lib/autoflip.ts:83-88`
**Issue:** `resolveFlowPortSide` does `edges.find(...)` and resolves the side from that single edge's neighbor. By contrast `resolveThermalPairSides` (lines 212-241) sums absolute deltas across ALL thermal edges touching the pair. If a FlowPort ever has more than one edge — accidentally (duplicate-edge bug), or intentionally (manifold, splitter, future signify replication) — the side is decided by whichever edge happens to be first in the array. Edge array order is non-deterministic across store mutations: re-arranging an unrelated edge can flip the rendered side of a downstream port.

The behavior is not documented in `resolveFlowPortSide`'s docstring; the test suite never asserts multi-edge behavior. The function silently picks one.

**Fix:** Either (a) document the single-edge contract explicitly and assert it, or (b) aggregate across all edges hitting the port the same way the thermal path does. Recommended (b) for parity:

```ts
const myEdges = edges.filter((e) =>
  isInPort
    ? e.target === nodeId && e.targetHandle === portName
    : e.source === nodeId && e.sourceHandle === portName,
);
if (myEdges.length === 0) return defaultSide;
// aggregate |dx| / |dy| across myEdges, then tie-break per D-13.
```

---

### WR-04: `offsetToString` / `parseOffsetString` silently drop one axis if both `left` and `top` are ever set

**File:** `gui/src/components/StreamNode.tsx:157-170`
**Issue:** `OffsetStyle` is declared as `{ left?: string; top?: string }` — both keys can be present simultaneously. `offsetToString` short-circuits on `offset.left !== undefined`, so an offset of `{ left: "25%", top: "10%" }` becomes the string `"left:25%"` and the `top` is dropped on the way through the selector encoding. Symmetric on `parseOffsetString`.

Today, `resolveAsymmetricOffset` only ever returns ONE key at a time (line 162-163 of `autoflip.ts`), so the encoder happens to be lossless. But the type permits both, and any future "corner offset" use case (e.g., 25% left × 25% top for a diagonal-anchored port) would be silently corrupted by the selector round-trip.

**Fix:** Either tighten the type to a tagged union (`{ axis: 'left' | 'top', pct: string }`) so it cannot represent corner offsets, or extend the encoder to a two-axis string format (e.g., `"left:25%;top:75%"`). Pick one and align the type to the encoder's actual capability.

```ts
export type OffsetStyle =
  | { axis: "left"; pct: string }
  | { axis: "top"; pct: string };
```

---

### WR-05: `useCallback` dep arrays in `FlowPortHandle` / `ThermalPortHandle` omit `getComponent`

**File:** `gui/src/components/StreamNode.tsx:210, 228, 249, 331`
**Issue:** Each Zustand selector body references the module-level `getComponent` import, but the `useCallback` dependency arrays don't list it. Today `getComponent` is a module-level function and is referentially stable, so the omission is benign. But it is exactly the pattern `react-hooks/exhaustive-deps` flags, and if the registry ever moves to a hook-injected accessor (e.g. for multi-fluid registries per project memory `project_fluids_longterm`), the closure will capture a stale reference and emit silently wrong sides.

**Fix:** Add an explicit eslint disable with a comment explaining the module-level stability, OR pass `getComponent` through the React dependency tree so the lint rule is satisfied honestly. Match the pattern used in `autoflip.ts:78` (`// eslint-disable-next-line @typescript-eslint/no-unused-vars`).

```ts
const resolvedSide = useStore(
  useCallback(
    (s: { nodes: Node[]; edges: Edge[] }) =>
      resolveFlowPortSide(s.nodes, s.edges, nodeId, port.name, defaultSide, getComponent),
    // getComponent is module-level and referentially stable — intentionally omitted.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [nodeId, port.name, defaultSide],
  ),
);
```

---

### WR-06: `HydraulicEdge.tsx` `bow` direction is *lexicographic* on edge id — fragile when ids are `e1` / `e10` / `e2`

**File:** `gui/src/components/HydraulicEdge.tsx:65`
**Issue:** `const bow = sibling ? (id < sibling.id ? BOW_PX : -BOW_PX) : 0;` compares ids with the JS string `<` operator. The docstring (line 63-64) says "Lexicographic id comparison makes the choice stable across re-renders, so the two siblings always bow in OPPOSITE directions and never flicker." That property holds — but the *which-edge-goes-up* assignment is counter-intuitive when ids are unpadded numerics: `"e10" < "e2"` is `true`, so `e10` bows up and `e2` bows down. The two tests (`bow.test.tsx:110-135`) only exercise `e1` vs `e2` where lex and numeric agree.

The behavior is stable (deterministic, no flicker), so this is not a correctness bug — but a future test that uses ids like `edge-10` vs `edge-2`, or any code path that asserts "smaller numeric id = +8 px", will fail surprisingly.

**Fix:** Either (a) extend the test matrix to cover `e10` / `e2` so the lex contract is explicit, or (b) switch to a numerically-stable comparator (parse the id suffix). Option (a) is cheaper and matches the existing UUIDv4-style id strategy elsewhere in the codebase.

---

## Info

### IN-01: `resolveThermalPairSides` docstring says "`|sumDx|` vs `|sumDy|`" but the code sums absolute deltas

**File:** `gui/src/lib/autoflip.ts:178, 236-237`
**Issue:** The docstring says "aggregate `|sumDx|` vs `|sumDy|` across ALL thermal edges". The code actually computes `sumDx += Math.abs(oc.x - meC.x)`, i.e. it sums the *absolute values of per-edge dx*, not the absolute value of a signed sum. The two are different (two neighbors at +300 and -300 sum-of-abs to 600, sum-then-abs to 0). The implementation is the intended one for axis-dominance detection (the alternative would let opposite neighbors cancel and fall back to the default axis). The docstring undersells the choice.

**Fix:** Rename the variables or clarify the docstring:

```ts
// Aggregate per-edge |dx| / |dy| (sum of absolute deltas, not |sum of deltas|).
// Two neighbors on opposite sides reinforce the same axis rather than canceling.
let absDxSum = 0;
let absDySum = 0;
```

---

### IN-02: `nodeCenter` fallback dimensions (140 × 70) are hard-coded magic numbers

**File:** `gui/src/lib/autoflip.ts:46-51`
**Issue:** The fallback width 140 and height 70 are inlined with a comment pointing at `StreamNode.tsx`'s `min-w-[140px]`. The height 70 is an estimate that does NOT account for the source-block label (`StreamNode.tsx:446-453`) or the topology-hint chip (`StreamNode.tsx:454-463`) added by this very phase. The error is bounded (first-frame only — ReactFlow measures on mount), but the magic numbers will silently drift.

**Fix:** Extract a single shared constant:

```ts
// src/lib/canvasConstants.ts
export const NODE_FALLBACK_WIDTH = 140;
export const NODE_FALLBACK_HEIGHT = 70;
```

And reference it from both `autoflip.ts` and any test fixtures that hard-code `{ width: 140, height: 70 }`.

---

### IN-03: `StreamNode.tsx:438` re-asserts `outlineColor` inline despite the className already setting `ring-destructive`

**File:** `gui/src/components/StreamNode.tsx:435-439`
**Issue:** The className already adds `outline outline-2 outline-offset-1 ring-2 ring-destructive` when `hasAnyError` is true, AND the inline style adds `outlineColor: "var(--destructive)"`. The inline override is redundant — Tailwind's `outline-destructive` does the same job. The duplication suggests the author was guarding against the JIT-scanning gap noted at the top of the file (line 32 comment), but `ring-destructive` and `outline` color don't need that guard since they're both first-class Tailwind utilities, not arbitrary values.

**Fix:** Drop the inline `outlineColor` assignment, or keep it but remove the className `ring-destructive` to make the inline path authoritative.

---

### IN-04: Test fixtures omit required `ComponentDefinition` fields and lean on `as unknown as`

**File:** `gui/src/lib/selectors/__tests__/topologyHints.test.ts:105, 117, 141`
**Issue:** The fixture `CAC_DEF` (and `PUMP_DEF`, `HD_DEF`) omits `constructorModes` (required by the interface) and is cast `as unknown as ComponentDefinition`. The autoflip test (`autoflip.test.ts:55-68`) does include `constructorModes: []`. If the `ComponentDefinition` schema gets a new required field (e.g. Phase 65 adds `category` validation), the topologyHints tests silently keep passing on broken fixtures.

**Fix:** Centralize a single fixture factory under `gui/src/test-utils/componentFixtures.ts` that returns valid `ComponentDefinition` objects with every required field, and share it across `autoflip.test.ts`, `topologyHints.test.ts`, and any future selector test.

---

### IN-05: Source-grep test in `HydraulicEdge.bow.test.tsx:180-190` is brittle to refactors

**File:** `gui/src/components/__tests__/HydraulicEdge.bow.test.tsx:180-190`
**Issue:** The render-storm guard reads `HydraulicEdge.tsx` from disk and regexes for `useStore(`. This passes today, but:
- A `// useStore(` comment in a future doc rewrite would fail the test.
- Renaming the hook (e.g. to `useAppStore`) silently passes — the test would no longer guard anything.
- The regex `/\buseStore\(/` does NOT match `useStore.getState()` (correct), but it also doesn't match `useStore<T>(` if a generic is added.

**Fix:** Pair the source-grep with a behavioral guard — for example, mount the component, mutate an unrelated slice of the store, and assert the component did NOT re-render (via a render-count spy). That guards the actual property "no render storm" rather than the proxy "no `useStore(` string in source".

---

### IN-06: `detectAxisCollision` and `selectTopologyHints` duplicate the dual-layer pre-check

**File:** `gui/src/lib/autoflip.ts:270-276` and `gui/src/lib/selectors/topologyHints.ts:91-95`
**Issue:** `selectTopologyHints` checks `hasFlowPort && hasThermalPair` and then calls `detectAxisCollision`, which immediately performs the same lookup (`comp.ports.find((p) => p.type === "FlowPort" && p.name.includes("in"))`, etc.). The `topologyHints.ts` comment at line 96-101 acknowledges the duplication ("duplicating the dual-layer guard here keeps `selectTopologyHints` self-documenting"). Acceptable trade-off, but the two implementations are not byte-identical: `detectAxisCollision` insists on a port whose name includes `"in"` AND a thermal port ending in `_left`, while `selectTopologyHints` only checks `.type === "FlowPort"`. If a component has only `port_out` and no `port_in` (single-FlowPort hypothetical), `selectTopologyHints` would proceed but `detectAxisCollision` would bail. The combined behavior is still correct (no false positive), but the asymmetry is subtle.

**Fix:** Move the dual-layer guard into a shared helper (`hasDualLayerPorts(comp)`) and call it from both sites so there is one source of truth. Drop the duplicated check from `detectAxisCollision`, or assert it explicitly.

---

_Reviewed: 2026-05-14_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
