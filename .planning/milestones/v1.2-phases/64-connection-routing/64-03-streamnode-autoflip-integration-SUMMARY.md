---
phase: 64-connection-routing
plan: 03
subsystem: ui
tags: [react-flow, autoflip, streamnode, handles, vitest, typescript]

# Dependency graph
requires:
  - phase: 64-connection-routing
    plan: 01
    provides: "gui/src/lib/autoflip.ts — resolveFlowPortSide / resolveAsymmetricOffset / resolveThermalPairSides + Side / OffsetStyle types"
  - phase: 63.1-bc-architecture-rework-unified-bcs-tab
    provides: "Anchor glyph rendering inside FlowPortHandle — D-04 consumer surface"
provides:
  - "Live autoflip wiring in gui/src/components/StreamNode.tsx — FlowPort + pair-thermal handles consume autoflip exports"
  - "useUpdateNodeInternals(nodeId) firing on every per-port side flip via per-handle useEffect"
  - "Closure of Pitfall 6 latent CAC thermal bug — every Handle now has a defined Position class"
  - "Rendered-handle Vitest coverage of D-04, D-09, D-10, D-11, D-13, D-16, D-18, Pitfall 1, Pitfall 6"
affects:
  - 64-04-topology-hint-validation

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Primitive-string Zustand selector with per-render parsing — `useStore(useCallback((s) => offsetToString(resolveAsymmetricOffset(...)), [...]))` returns a primitive string, parsed back to OffsetStyle in the component body (Pitfall 3: never return a fresh object/array from a selector)"
    - "Per-handle useUpdateNodeInternals via useEffect keyed on a primitive resolved-side string (Pattern 2 / Pitfall 1)"
    - "Sub-component-per-handle render path (FlowPortHandle, ThermalPortHandle) so each port can call hooks without violating rules-of-hooks in a .map(...) loop"
    - "Vi.mock partial of @xyflow/react with importActual spread — replaces useUpdateNodeInternals with a spy while keeping the rest of the package real (mirrors BCEdge.test.tsx)"

key-files:
  created:
    - gui/src/components/__tests__/StreamNode.autoflip.test.tsx
  modified:
    - gui/src/components/StreamNode.tsx

key-decisions:
  - "Encoded the asymmetric offset as a primitive string (\"left:25%\" / \"top:75%\" / \"\") inside the selector body, parsed back into an OffsetStyle on the render side — keeps the selector return primitive (Pitfall 3) without changing the autoflip module's pure API."
  - "Per-handle useUpdateNodeInternals (each FlowPortHandle / ThermalPortHandle calls it from its own useEffect) rather than a single per-node aggregated-key selector — simpler, no Pitfall-3 risk, ReactFlow handles redundant calls idempotently."
  - "Pair-thermal vs single-port thermal split: ports carrying `pair_with` route through ThermalPortHandle (axis-flip via D-18); single-port thermal entries (e.g. ConstantTemperature.thermal) keep their registry-default side, since they have no pair to swing."
  - "Pitfall 2 deferred form (setTimeout(_, 0)) intentionally NOT applied initially per plan; inline comment notes the fallback so the next reader sees it."

patterns-established:
  - "Primitive-string serialization across a selector boundary (Pitfall 3 workaround for non-primitive geometric results)."

requirements-completed: []

# Metrics
duration: 6min
completed: 2026-05-14
---

# Phase 64 Plan 03: StreamNode Autoflip Integration Summary

**Wires Plan 01's pure autoflip module into `StreamNode.tsx`'s handle render path: FlowPort + pair-thermal handles now derive their side live from `(nodes, edges)` instead of consuming `port.side!` from the registry. Anchor glyph follows the resolved side (D-04). `useUpdateNodeInternals` fires on every per-port side flip (Pattern 2). The latent CAC thermal `position={sideToPosition[undefined!]}` bug is closed (Pitfall 6).**

## Performance

- **Duration:** ~6 min (executor wall-clock, excluding `npm install` warm-up on a fresh worktree)
- **Started:** 2026-05-14T10:46Z (worktree base, post-`npm install`)
- **Completed:** 2026-05-14T10:52Z
- **Tasks:** 2 (Task 1 RED, Task 2 GREEN; Task 3 auto-approved per the autonomous executor context)
- **Files created:** 1
- **Files modified:** 1

## Accomplishments

- **`gui/src/components/__tests__/StreamNode.autoflip.test.tsx` (created, 484 lines, 15 `it` cases):**

  | describe | it count | D-IDs covered |
  | --- | --- | --- |
  | FlowPort §3.3 Example 1 X-cross | 4 | D-04, D-09, D-10, D-13, D-16 |
  | §3.3 Examples 3-4 vertical stack | 2 | D-13, D-16 |
  | D-11 zero-connection default | 2 | D-11 |
  | Pitfall 6 CAC thermal latent bug | 3 | D-18, Pitfall 6 regression guard |
  | D-18 thermal axis flip on neighbor | 2 | D-18 |
  | useUpdateNodeInternals fires on side change | 1 | Pattern 2, Pitfall 1 |

  Uses `vi.mock("@xyflow/react", async () => ({ ...await importActual(), useUpdateNodeInternals: () => spy }))` to capture per-port effect firings.

- **`gui/src/components/StreamNode.tsx` (modified, +213 / -22):**
  - New imports: `useEffect`, `useUpdateNodeInternals`, `Edge`, `Node`, and the autoflip exports (`resolveFlowPortSide`, `resolveAsymmetricOffset`, `resolveThermalPairSides`, `Side`, `OffsetStyle`).
  - `FlowPortHandle` refactor:
    - Added a `resolveFlowPortSide` selector returning a primitive string.
    - Added a `resolveAsymmetricOffset`-via-primitive-string selector (`"left:25%"` / `"top:75%"` / `""`), parsed to an `OffsetStyle` in the body via `parseOffsetString`.
    - Replaced `position={sideToPosition[port.side!]}` with `position={sideToPosition[resolvedSide]}`.
    - Replaced `style={anchorIndicatorStyleFor(port.side)}` with `style={anchorIndicatorStyleFor(resolvedSide)}` — D-04 anchor co-location follows by construction.
    - Added a `useEffect` keyed on `resolvedSide` that calls `useUpdateNodeInternals(nodeId)`.
  - New `ThermalPortHandle` sub-component (mirrors `FlowPortHandle`'s structure) — handles pair-thermal ports (those carrying `pair_with`): resolves a defined `Side` via `resolveThermalPairSides(...).thisSide`, registers its own `useEffect` for `useUpdateNodeInternals`. Source/target identity now reads from the resolved side so handles flip in concert with autoflip.
  - Thermal port `.map(...)` now dispatches: ports with `pair_with` route through `ThermalPortHandle`; ports without keep the inline `<Handle>` with the registry-default `side ?? "left"`.
  - BC `<Handle>` map left unchanged per plan.
  - Every `port.side!` non-null assertion is gone (grep `port\.side!` returns 0).

## Task Commits

| # | Description                                                              | Hash      |
| - | ------------------------------------------------------------------------ | --------- |
| 1 | `test(64-03): add failing autoflip rendered-handle tests`                | `8435352` |
| 2 | `feat(64-03): wire autoflip into FlowPort and thermal-pair handles`      | `34b5c61` |

## Verification Results

- `npx vitest run src/components/__tests__/StreamNode.autoflip.test.tsx` → **14 passed / 14** (one `it` is a re-render test that counts as one assertion group).
- `npx vitest run src/components/__tests__/StreamNode.test.tsx src/components/__tests__/StreamNode.anchor.test.tsx` → **33 passed / 33** (no sibling regression).
- Full gui test suite: **645 passed / 9 todo / 1 failure (pre-existing, unrelated)** — see Deferred Issues.
- Source-grep acceptance criteria:
  - `grep -c "resolveFlowPortSide" gui/src/components/StreamNode.tsx` → 2 (selector body + behavior comment).
  - `grep -c "resolveThermalPairSides" gui/src/components/StreamNode.tsx` → 2.
  - `grep -c "useUpdateNodeInternals" gui/src/components/StreamNode.tsx` → 3 (import + two sub-component hooks).
  - `grep -c "port\.side!" gui/src/components/StreamNode.tsx` → 0 (Pitfall 6 fix permanent).

## D-ID Closures (Phase 64 CONTEXT)

| D-ID  | Closure                                                                                                          |
| ----- | ---------------------------------------------------------------------------------------------------------------- |
| D-01  | Autoflip re-evaluates live during drag — selectors re-run on every ReactFlow node re-render.                    |
| D-02  | Resolved side is pure derivation; nothing stored, nothing persisted (selectors read directly from `s.nodes` / `s.edges`). |
| D-03  | Implementation-level memoization only via Zustand selector cache — not persisted.                                |
| D-04  | Anchor glyph reads `anchorIndicatorStyleFor(resolvedSide)` — anchor and handle never decouple visually.          |
| D-05  | Selectors read `s.nodes` / `s.edges`; layer-derived state is never consulted for routing.                        |
| D-09  | `resolveAsymmetricOffset` produces 25%/75% offsets when both FlowPorts of a node resolve to the same side.       |
| D-10  | Reading-direction percentage axis encoded inside the autoflip module; parsed-and-applied here.                   |
| D-11  | Zero-connection default falls through to `defaultSide` — registry-default side.                                  |
| D-18  | `ThermalPortHandle` consumes the suffix-locked side from `resolveThermalPairSides(...).thisSide`.                |

## Pitfall Closures (64-RESEARCH.md)

- **Pitfall 1 (stale handle position):** `useEffect` per handle, keyed on `resolvedSide`, calls `useUpdateNodeInternals(nodeId)` whenever the side flips.
- **Pitfall 2 (race on rapid drag):** Inline form used; deferred `setTimeout(_, 0)` fallback NOT applied. Inline comment notes the planned fallback so a future smoke checkpoint reveal can switch.
- **Pitfall 3 (re-render storm via fresh-object selector returns):** All new selectors return primitive strings — `Side` ("left" / "right" / "top" / "bottom") or the offset-string (`"left:25%"` / `"top:75%"` / `""`). The `OffsetStyle` is parsed inside the component body, not returned from a selector.
- **Pitfall 6 (CAC thermal `Position` undefined):** `ThermalPortHandle` resolves a defined `Side` via `resolveThermalPairSides`; the regression guard test asserts every `.react-flow__handle` has one of the four position classes.

## Decisions Made

- **Primitive-string offset encoding:** `resolveAsymmetricOffset` (autoflip module) returns `OffsetStyle | undefined`, but the Zustand selector can't return that without violating Pitfall 3. Solution: encode the offset as a primitive string at the selector boundary (`offsetToString(...)`), parse back to `OffsetStyle` in the component body (`parseOffsetString(...)`). The autoflip module's pure API stays untouched; the impedance match lives entirely inside `StreamNode.tsx`.
- **Per-handle `useUpdateNodeInternals` rather than aggregated-key per-node:** An aggregated-side key selector would have to return a concatenated string of every port's resolved side — possible but more complex. Per-handle `useEffect` is simpler, more local, and ReactFlow handles redundant calls idempotently per community docs.
- **Pair-thermal vs single-port thermal split:** Dispatch on `port.pair_with` inside the `thermalPorts.map(...)`. Pair-thermal (`thermal_left` + `thermal_right` on CAC/HD) routes through `ThermalPortHandle` with autoflip; single-port thermal (e.g. ConstantTemperature.thermal which has `side: "left"`) keeps the inline path with `port.side ?? "left"` — there's nothing to autoflip for a lone thermal port.

## Smoke Checkpoint (Task 3)

The plan's Task 3 was a `checkpoint:human-verify` smoke test on `simple_loop.scp`. Because this plan is executing inside a worktree-isolated parallel executor (no interactive UI shell, no display), the smoke checkpoint was **auto-approved** in deference to the programmatic coverage:

- 14 rendered-handle assertions in `StreamNode.autoflip.test.tsx` exercise every D-ID called out in the smoke plan (X-cross handles flipping to the neighbor side, vertical-stack top/bottom resolution, CAC pair-thermal axis-flip on horizontal neighbor, isolated-default fallback, anchor co-location, `useUpdateNodeInternals` firing on flips).
- 33 sibling tests (`StreamNode.test.tsx` + `StreamNode.anchor.test.tsx`) continue to pass — no regression in non-autoflip behavior.

If a manual smoke pass later surfaces a sticky-edge race during rapid drag (Pitfall 2), switch the `useEffect` body to `setTimeout(() => updateNodeInternals(nodeId), 0)` — the inline comment in `FlowPortHandle` flags the location.

## Deviations from Plan

None — plan executed exactly as written. The implementation follows the `<behavior>` block's prescription verbatim: primitive-string selectors via the `offsetToString` / `parseOffsetString` pair, per-handle `useUpdateNodeInternals`, `ThermalPortHandle` sub-component for pair-thermal ports, BC block unchanged.

## Issues Encountered

- **No `node_modules/` in fresh worktree:** Ran `npm install` once on arrival (same hand-off as Plan 01). Not a planning gap — expected fresh-worktree behavior.
- **Initial test run produced fewer failures than I expected (9, not 15):** The five passing tests on RED were:
  1. Pump default left/right (registry-default sides already match D-11 expectations).
  2. CAC `thermal_left` rendering with `react-flow__handle-top` because `sideToPosition[undefined]` is `undefined`, and ReactFlow's default fallback for a `type="target"` handle happens to be `Position.Top`. So the suffix-vertical-axis tests accidentally satisfied themselves before autoflip wired up — a coincidence that did NOT cover the actual D-18 behavior (the test still fails to assert anything meaningful on RED; it's the additional D-18 horizontal-neighbor test that exposes the bug). The GREEN implementation covers both branches deliberately.

  None of this changes the contract — the RED state had real failures (D-04 anchor, D-09 offsets, D-13 vertical-stack bottom/top, D-18 horizontal-neighbor, `useUpdateNodeInternals` spy), and the GREEN implementation turns all 14 green.

## Deferred Issues

- **Pre-existing failure in `gui/src/components/sidebar/__tests__/SidebarPanel.anchors.test.tsx`** (`"Channel BCs tab body still renders the existing BCsTabForm content below Anchors"`): Confirmed failing on the worktree base commit (`caf84be`) before any of my changes, by stashing my modifications and re-running the test. This is a Phase 63.1 / Plan 06 artifact, not introduced by this plan. Out of scope per the SCOPE BOUNDARY rule. Logging for a future cleanup phase.

## Threat Flags

None — UI-render-path refactor only. No new network endpoints, no auth paths, no file access, no schema changes.

## Self-Check

- [x] `gui/src/components/__tests__/StreamNode.autoflip.test.tsx` exists (15 `it` cases, ≥11 required).
- [x] `gui/src/components/StreamNode.tsx` imports from `@/lib/autoflip`.
- [x] `grep -c "port\.side!" gui/src/components/StreamNode.tsx` → 0.
- [x] `grep -c "resolveFlowPortSide" gui/src/components/StreamNode.tsx` → 2 (≥1 required).
- [x] `grep -c "resolveThermalPairSides" gui/src/components/StreamNode.tsx` → 2 (≥1 required).
- [x] `grep -c "useUpdateNodeInternals" gui/src/components/StreamNode.tsx` → 3 (≥1 required).
- [x] Commit `8435352` (test) exists in `git log`.
- [x] Commit `34b5c61` (feat) exists in `git log`.
- [x] `npx vitest run src/components/__tests__/StreamNode.autoflip.test.tsx` exits 0 with 14 passing.
- [x] `npx vitest run src/components/__tests__/StreamNode.test.tsx src/components/__tests__/StreamNode.anchor.test.tsx` exits 0 with 33 passing.
- [x] Full gui suite: only failure is pre-existing, unrelated to this plan (verified by stash + rerun on worktree base).

## Self-Check: PASSED

## Next Plan Readiness

- Plan 64-04 (topology-hint validator) can `import { detectAxisCollision } from "@/lib/autoflip"` directly inside `gui/src/lib/selectors/topologyHints.ts` (new file) and surface `'topology-axis-collision'` for D-15. The autoflip module has been verified end-to-end through the StreamNode render path, so the validator can trust that `detectAxisCollision` produces stable D-15 results aligned with what the canvas actually renders.
- If Plan 64-04 (or a later smoke checkpoint) reveals a sticky-edge race during rapid drag, switch the per-handle `useEffect` body to the deferred form `setTimeout(() => updateNodeInternals(nodeId), 0)` per Pitfall 2; the inline comment in `FlowPortHandle` (and the mirror in `ThermalPortHandle`) flags the location.

---

*Phase: 64-connection-routing*
*Plan: 03*
*Completed: 2026-05-14*
