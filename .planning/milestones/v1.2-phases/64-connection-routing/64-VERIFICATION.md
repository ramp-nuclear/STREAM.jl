---
phase: 64-connection-routing
verified: 2026-05-14T14:08:00Z
human_uat_resolved: 2026-05-21
status: complete
score: 18/18 must-haves verified; human UAT closed 2026-05-21 (4/5 pass, 1 cosmetic issue routed to Phase 72 follow-up — see 64-HUMAN-UAT.md Test 5 + .planning/todos/pending/2026-05-16-phase72-handle-port-visual-rework.md)
overrides_applied: 0
human_verification:
  - test: "Open `gui/export_examples/simple_loop.scp` (or build a pump-CAC-pump loop) and confirm each FlowPort handle visually sits on the side facing its connected neighbor (no more ugly arrows from the §3.3 example_*.png screenshots)."
    expected: "Handles face their neighbors; CAC thermal pair lands on opposing top/bottom faces; brief 1-pixel flicker at 45° dominant-axis transition is acceptable per D-14."
    why_human: "The phase goal is rooted in visual ugliness verified in the example_*.png screenshots. Programmatic tests assert the math + DOM class names but cannot verify the human perception of 'no longer ugly'."
    result: pass
    resolved_in: 64-HUMAN-UAT.md Test 1
  - test: "Wire two pumps with bidirectional hydraulic edges (`pump1.port_out → pump2.port_in` and `pump2.port_out → pump1.port_in`) and confirm the two edges render as a ±8px parallel offset instead of overlapping on a single midline (Example-1 X-cross fix)."
    expected: "Two clearly separated parallel paths; deterministic direction (smaller-id bow on one side, larger-id on the other); no flicker on re-render."
    why_human: "Visual confirmation that the anti-parallel bow renders correctly on the real canvas; tests assert path-d-attribute math but eyeball confirmation of 'looks good in the GUI' is human."
    result: pass
    resolved_in: 64-HUMAN-UAT.md Test 2
  - test: "Drag a node around and confirm autoflip recomputes live (handles flip as the dominant axis to the neighbor changes) without sticky edges. If sticky-edge race surfaces during rapid drag, switch the per-handle `useEffect` body to `setTimeout(() => updateNodeInternals(nodeId), 0)` per Pitfall 2 (inline comment in StreamNode.tsx flags the location)."
    expected: "Edges follow handles fluidly during drag; `useUpdateNodeInternals` keeps the wires attached to the live handle positions."
    why_human: "Real-time drag interaction with rendering loop and ReactFlow internals — cannot be exercised programmatically."
    result: pass
    resolved_in: 64-HUMAN-UAT.md Test 3
  - test: "Switch active layer from Hydraulic to Thermal and back. Confirm edges DIM but do NOT re-route (D-05 invariant)."
    expected: "Visual dimming applied via `dimFlowHandles` / `dimThermalHandles` opacity; edge paths remain identical across layer switches."
    why_human: "Visual perception of dimming vs re-routing; programmatic tests cover that selectors don't read `activeLayer` but the live render needs a smoke check."
    result: pass
    resolved_in: 64-HUMAN-UAT.md Test 4
  - test: "Trigger D-15 by arranging a CAC with hydraulic neighbor on one side AND a thermal neighbor on the SAME horizontal axis. Confirm the amber chip 'Hydraulic and thermal neighbors on same axis — consider repositioning.' appears at the bottom-right of the CAC and the red ring does NOT light up."
    expected: "Chip is non-blocking; node root has NO `ring-destructive` class when only the topology hint fires."
    why_human: "Visual confirmation of warning vs error severity separation; D-15 is genuinely rare per the design doc and was not exercised by the parallel executor's smoke checkpoint."
    result: issue-deferred
    resolved_in: 64-HUMAN-UAT.md Test 5
    resolution: "Owner rejected the topology-hint chip feature outright AND flagged separate handle-design visual problems (color, shape, size, behavior). Routed to Phase 72 follow-up via .planning/todos/pending/2026-05-16-phase72-handle-port-visual-rework.md. Severity: cosmetic. Not a Phase 64 routing-correctness gap."
---

# Phase 64: Connection Routing Verification Report

**Phase Goal:** Solve the connection-arrow ugliness verified in the example_*.png screenshots. Per-port autoflip moves each FlowPort handle to the side facing its connected neighbor. Asymmetric same-side placement disambiguates when both ports of a component end up on the same edge. Thermal-port-pair axis-flip for CAC/HD (left/right or top/bottom). Optional polish hook for anti-parallel offset of bidirectional pairs.

**Verified:** 2026-05-14T14:08:00Z
**Status:** complete (human UAT closed 2026-05-21 — see 64-HUMAN-UAT.md; 4/5 pass, 1 cosmetic issue routed to Phase 72)
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

Truths sourced from PLAN frontmatter must_haves across the four plans (64-01..64-04) plus the phase goal text.

| #  | Truth | Status | Evidence |
| -- | ----- | ------ | -------- |
| 1  | `gui/src/lib/autoflip.ts` exists as a pure module exporting `resolveFlowPortSide`, `resolveAsymmetricOffset`, `resolveThermalPairSides`, `detectAxisCollision`, `findAntiParallelSibling` + types `Side`, `OffsetStyle` | VERIFIED | File at `gui/src/lib/autoflip.ts` (326 lines); all five functions + both types declared; signatures match plan |
| 2  | autoflip.ts purity invariant — zero runtime React/ReactFlow/Zustand imports (only `import type`) | VERIFIED | `grep -v '^import type' gui/src/lib/autoflip.ts \| grep -cE 'from "@xyflow/react"\|from "react"\|from "zustand"'` returns 0 |
| 3  | `resolveFlowPortSide` returns registry-default for zero-connection ports (D-11) and uses dominant-axis center-to-center vector with `|dx| >= |dy|` tie-break (D-13, D-14, D-16) | VERIFIED | autoflip.ts lines 88, 101-104; 7 `it` cases in `autoflip.test.ts > resolveFlowPortSide` all green |
| 4  | `resolveAsymmetricOffset` returns 25%/75% offsets per D-09/D-10 with reading-direction axis; returns `undefined` on different sides | VERIFIED | autoflip.ts lines 154, 156-163; 4 `it` cases green |
| 5  | `resolveThermalPairSides` is suffix-locked per D-18 (only axis flips); D-11 default-axis fallback for zero neighbors | VERIFIED | autoflip.ts lines 192-241 (definitive `isLeftSuffix` switch + aggregated `|sumDx|` vs `|sumDy|`); 5 `it` cases green |
| 6  | `detectAxisCollision` returns `true` exactly when FlowPort axis and thermal-pair axis match orientation (D-15) | VERIFIED | autoflip.ts lines 262-299; 3 `it` cases green |
| 7  | Anti-parallel sibling detection filters by `edge.type === "hydraulicEdge"` (D-17 same-type-only) | VERIFIED | `findAntiParallelSibling` in autoflip.ts lines 314-326; inline duplicate in `HydraulicEdge.tsx` line 57 also filters on `"hydraulicEdge"`; D-17 negative cases tested |
| 8  | `HydraulicEdge.tsx` applies ±8px perpendicular bow between same-type swap siblings (D-06, D-07, D-08) | VERIFIED | `BOW_PX = 8` at line 37; sibling find at lines 54-60; lexicographic id ordering at line 65; perpendicular pre-offset at lines 75-78; 7 `it` cases in `HydraulicEdge.bow.test.tsx` green |
| 9  | Bow direction stable via lexicographic id ordering (smaller-id +BOW, larger-id −BOW) | VERIFIED | `HydraulicEdge.tsx:65`: `id < sibling.id ? BOW_PX : -BOW_PX`; tested by D-08 opposite-direction guarantee |
| 10 | Solitary hydraulic edge renders with zero bow (no regression on baseline) | VERIFIED | `bow = sibling ? ... : 0` at HydraulicEdge.tsx line 65; baseline test in HydraulicEdge.bow.test.tsx passes |
| 11 | HydraulicEdge reads sibling state via `useStore.getState()` synchronously — no hook subscription (render-storm guard) | VERIFIED | `grep -E "useStore\(" gui/src/components/HydraulicEdge.tsx \| grep -v "useStore\.getState"` returns no matches; `useStore.getState()` used at line 53 |
| 12 | `FlowPortHandle` in StreamNode consumes `resolveFlowPortSide` via primitive-string Zustand selector (D-01/D-02 live derivation) | VERIFIED | StreamNode.tsx lines 215-229; selector returns `Side` primitive string; `useCallback` memoized |
| 13 | Anchor glyph co-renders with the live-resolved port side (D-04) | VERIFIED | StreamNode.tsx line 288: `style={anchorIndicatorStyleFor(resolvedSide)}`; not the registry `port.side`; tested in autoflip.test.tsx D-04 anchor co-location case |
| 14 | Asymmetric same-side placement (D-09/D-10) applied via inline `style.left`/`style.top` | VERIFIED | StreamNode.tsx line 275: `...(offsetStyle ?? {})` spread into Handle style; `parseOffsetString` decodes selector's primitive string |
| 15 | Thermal `<Handle>` consumes `resolveThermalPairSides` for `pair_with` ports (Pitfall 6 CAC bug closed — no more undefined Position) | VERIFIED | `ThermalPortHandle` at StreamNode.tsx lines 305-363; dispatch at lines 472-488; `grep -c "port\.side!" StreamNode.tsx` returns 0 |
| 16 | `useUpdateNodeInternals(nodeId)` fires from `useEffect` keyed on resolved side (Pattern 2 / Pitfall 1) | VERIFIED | StreamNode.tsx lines 260-263 (FlowPort) and 336-339 (Thermal); both keyed on `resolvedSide` |
| 17 | `selectTopologyHints` is a pure selector mirroring `nodeErrors.ts`; emits `topology-axis-collision` exactly when D-15 holds | VERIFIED | topologyHints.ts lines 72-107; delegates to `detectAxisCollision`; dual-layer pre-check at lines 91-95; purity grep returns 0 |
| 18 | Yellow non-blocking chip renders inside StreamNode when `hasTopologyHint` is true; NOT mixed into `hasAnyError` (D-15 severity isolation) | VERIFIED | StreamNode.tsx lines 454-463: chip renders with `data-testid="topology-hint-chip"`, amber-100/900 styling, non-blocking; line 415 confirms `hasAnyError = hasError \|\| hasBCError` (no `hasTopologyHint` mixin); StreamNode.topologyHint.test.tsx asserts absence of `ring-destructive` |

**Score:** 18/18 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `gui/src/lib/autoflip.ts` | Pure geometric autoflip rules; 5 functions + 2 types | VERIFIED | 326 lines; all exports present; purity invariant holds |
| `gui/src/lib/__tests__/autoflip.test.ts` | Unit tests covering D-08..D-18 | VERIFIED | 23 `it` cases (plan required ≥18); all green |
| `gui/src/components/HydraulicEdge.tsx` | Anti-parallel bow implementation | VERIFIED | 93 lines; `BOW_PX = 8`; same-type swap filter; perpendicular pre-offset |
| `gui/src/components/__tests__/HydraulicEdge.bow.test.tsx` | Bow detection + filter + direction tests | VERIFIED | 7 `it` cases green |
| `gui/src/components/StreamNode.tsx` | Autoflipped FlowPort + thermal handles + anchor co-location + useUpdateNodeInternals wiring | VERIFIED | All Phase-64 hooks present; sub-components `FlowPortHandle` + `ThermalPortHandle`; chip block; no `port.side!` |
| `gui/src/components/__tests__/StreamNode.autoflip.test.tsx` | Rendered-handle assertions | VERIFIED | 15 `it` cases green (plan required ≥11) |
| `gui/src/lib/selectors/topologyHints.ts` | Pure validator-as-selector (D-15) | VERIFIED | 107 lines; mirrors `nodeErrors.ts` shape; delegates to `detectAxisCollision`; purity grep returns 0 |
| `gui/src/lib/selectors/__tests__/topologyHints.test.ts` | Pure-selector D-15 tests | VERIFIED | 9 `it` cases green |
| `gui/src/components/__tests__/StreamNode.topologyHint.test.tsx` | Rendered chip + severity isolation | VERIFIED | 5 `it` cases green (one more than the plan's ≥4 minimum) |

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | -- | --- | ------ | ------- |
| `autoflip.ts` | `registry/types.ts` | `import type { ComponentDefinition }` | WIRED | autoflip.ts line 17 |
| `autoflip.test.ts` | `autoflip.ts` | named imports | WIRED | Tests pass |
| `HydraulicEdge.tsx` | `useStore` | `useStore.getState().edges` synchronously | WIRED | HydraulicEdge.tsx lines 8, 53; NO hook form |
| `StreamNode.tsx` | `@/lib/autoflip` | `import { resolveFlowPortSide, resolveAsymmetricOffset, resolveThermalPairSides, type Side, type OffsetStyle }` | WIRED | StreamNode.tsx lines 19-30 |
| `StreamNode.tsx` | `@xyflow/react` `useUpdateNodeInternals` | `useEffect` keyed on `resolvedSide` | WIRED | StreamNode.tsx lines 260-263 (FlowPort) + 336-339 (Thermal) |
| `topologyHints.ts` | `autoflip.ts` | `import { detectAxisCollision } from "../autoflip"` | WIRED | topologyHints.ts line 22 |
| `StreamNode.tsx` | `@/lib/selectors/topologyHints` | `useStore(useCallback(s => selectTopologyHints(...).length > 0, [id]))` | WIRED | StreamNode.tsx lines 19-22, 385-395 |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| -------- | ------------- | ------ | ------------------ | ------ |
| `FlowPortHandle.resolvedSide` | `Side` (primitive string) | `useStore(useCallback(s => resolveFlowPortSide(s.nodes, s.edges, ...)))` | Yes — re-runs every render with live `s.nodes`/`s.edges` | FLOWING |
| `FlowPortHandle.offsetStyle` | `OffsetStyle \| undefined` | Selector returns primitive string, parsed in body via `parseOffsetString` | Yes — same selector cache as resolvedSide | FLOWING |
| `ThermalPortHandle.resolvedSide` | `Side` | `useStore(useCallback(s => resolveThermalPairSides(...).thisSide))` | Yes — primitive string from live state | FLOWING |
| `HydraulicEdge` bow | endpoint coords pre-offset by `bow` | `useStore.getState().edges` synchronous read at render time | Yes — every drag tick re-reads | FLOWING |
| `StreamNode.hasTopologyHint` | boolean | `useStore(useCallback(s => selectTopologyHints(...).length > 0))` | Yes — re-evaluates on state change | FLOWING |
| Anchor glyph indicator | inline `React.CSSProperties` | `anchorIndicatorStyleFor(resolvedSide)` driven by autoflipped side | Yes — anchor follows handle by construction | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Vitest gate (9 files, 100 expected) | `cd gui && npx vitest run src/lib/__tests__/autoflip.test.ts src/lib/selectors/__tests__/topologyHints.test.ts src/lib/selectors/__tests__/nodeErrors.test.ts src/components/__tests__/HydraulicEdge.bow.test.tsx src/components/__tests__/StreamNode.autoflip.test.tsx src/components/__tests__/StreamNode.topologyHint.test.tsx src/components/__tests__/StreamNode.test.tsx src/components/__tests__/StreamNode.anchor.test.tsx src/components/__tests__/BCEdge.test.tsx` | 9 files passed, 100 tests passed, 704ms | PASS |
| autoflip.ts purity | `grep -v '^import type' gui/src/lib/autoflip.ts \| grep -cE 'from "@xyflow/react"\|from "react"\|from "zustand"'` | 0 | PASS |
| topologyHints.ts purity | `grep -v '^import type' gui/src/lib/selectors/topologyHints.ts \| grep -cE 'from "@xyflow/react"\|from "react"\|from "zustand"'` | 0 | PASS |
| HydraulicEdge render-storm guard | `grep -E "useStore\(" gui/src/components/HydraulicEdge.tsx \| grep -v "useStore\.getState"` | no matches | PASS |
| Pitfall 6 fix (no `port.side!`) | `grep -c "port\.side!" gui/src/components/StreamNode.tsx` | 0 | PASS |
| `hasAnyError` not contaminated by `hasTopologyHint` | `grep -E "hasAnyError\s*=" gui/src/components/StreamNode.tsx` | `const hasAnyError = hasError \|\| hasBCError;` (no topology-hint mixin) | PASS |

### Probe Execution

Not applicable — Phase 64 is a GUI-only TypeScript refactor with no shell-runnable probes. The vitest gate above is the equivalent runnable check.

### Requirements Coverage

Per the verification request: phase has `requirements: null` in all four plan frontmatters and no formal CR-* IDs registered for this phase in REQUIREMENTS.md. Verification reduces to the goal text + PLAN must_haves, both fully covered above.

### Anti-Patterns Found

Scanned `autoflip.ts`, `topologyHints.ts`, `HydraulicEdge.tsx`, `StreamNode.tsx`:

- No `TBD`, `FIXME`, or `XXX` debt markers.
- Five `Pitfall N` references inside StreamNode.tsx comments — these are documentation cross-references to `64-RESEARCH.md`, not unresolved-work markers.
- One unused-callback parameter in autoflip.ts (`_getComponent` in `resolveFlowPortSide` and `resolveThermalPairSides`) suppressed by `@typescript-eslint/no-unused-vars` — intentional uniformity of public callback signature per Plan 01 SUMMARY decision; not a stub.
- `findAntiParallelSibling` is exported from `autoflip.ts` and unit-tested, but `HydraulicEdge.tsx` re-implements the same logic inline at line 54-60 rather than importing it. The two code paths apply identical filters (`type === "hydraulicEdge"` + swap of source/target). Both branches are independently tested. **Info-level observation** — not a goal-achievement gap.

### Human Verification Required

See frontmatter `human_verification` items. Summary: the phase goal anchors on visual ugliness in the example_*.png screenshots, which is inherently a perceptual claim. Programmatic coverage proves the math, DOM class names, severity isolation, and render-storm safety; a 5-step human smoke pass on a real canvas closes the loop.

### Gaps Summary

No gaps. All 18 must-have truths verified; 100/100 tests pass; all purity invariants hold; all key wiring traced end-to-end. The phase delivers the autoflip rules, anti-parallel bow, anchor co-location, thermal-pair axis-flip closing the CAC undefined-Position latent bug, and the non-blocking topology hint chip per D-15 with proper severity isolation from the red-ring error path.

Status is `human_needed` only because the phase goal references visual screenshots (`example_*.png`) and visual perception of "not ugly anymore" cannot be asserted programmatically. The known-deferred pre-existing failure in `SidebarPanel.anchors.test.tsx` and the 11 pre-existing tsc errors are confirmed Phase 71 scope, not Phase 64 regressions.

---

*Verified: 2026-05-14T14:08:00Z*
*Verifier: Claude (gsd-verifier)*
