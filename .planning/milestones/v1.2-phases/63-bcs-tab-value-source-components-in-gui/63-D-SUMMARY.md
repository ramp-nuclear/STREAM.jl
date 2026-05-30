---
phase: 63
plan: D
subsystem: gui-canvas
tags: [bcs-tab, value-source, canvas, edge, handle, toolbox]
dependency_graph:
  requires:
    - Phase 63-B store contract (bcMode/bcSymmetric/errorTagsByNodeId slices, isAllowedBCConnection, cycleBCEdgeTargetSide store action, enrichEdges BCPort branch, addEdge → _checkBCNMismatch wiring)
    - Phase 61 registry (BCPort port type, WallTemperature/HeatFluxSource entries with category "Sources", external_inputs[])
    - Phase 62 toolbox patterns (getComponentsByCategory, ToolboxItem draggable, addNode smart-name handler)
  provides:
    - BCEdge custom edge (dashed style + click-to-cycle L+R/L/R chip)
    - StreamNode BCPort hollow-square handle, source-block two-line label, BC error red-ring (D-22), whole-body BC drop overlay (D-10)
    - CanvasPanel edgeTypes.bcEdge registration + isValidConnection BCPort allow-list
    - ToolboxPanel Sources category populated with WallTemperature + HeatFluxSource
  affects: []
tech_stack:
  added: []
  patterns:
    - "ReactFlow custom edge with EdgeLabelRenderer portal + click-to-cycle chip"
    - "useConnection() drag-state gating (CD-03: pure ReactFlow extensibility, no mouse listeners)"
    - "Primitive selector (hasBCError boolean) over fresh-array selector — stabilises zustand shallow equality"
    - "Registry-driven source-block label rendering via SOURCE_LABEL_FIELD map + private sourceLabelLine helper"
key_files:
  created:
    - gui/src/components/BCEdge.tsx
    - gui/src/components/__tests__/BCEdge.test.tsx
    - gui/src/components/__tests__/CanvasPanel.bc.test.tsx
  modified:
    - gui/src/components/StreamNode.tsx
    - gui/src/components/CanvasPanel.tsx
    - gui/src/components/ToolboxPanel.tsx
    - gui/src/components/__tests__/StreamNode.test.tsx
    - gui/src/components/__tests__/ToolboxPanel.test.tsx
decisions:
  - "Stabilise errorTagsByNodeId selector by reducing it to a primitive boolean (hasBCError) — returning `s.errorTagsByNodeId[id] ?? []` causes zustand to deliver a fresh array on every render and triggers maximum-update-depth loops."
  - "Whole-body drop overlay uses pointer-events-none — ReactFlow's own handle hit-testing performs the drop; the overlay is purely visual (per CD-03 / RESEARCH Pattern 2)."
  - "Source-block label encoding: scalar = number, vector = JS array, callable = string. Matches the existing ParameterForm/codeGenerator round-trip; no new type was introduced for Phase 63 — the label inspects the stored value's runtime shape."
  - "BCEdge does NOT consume the inbound EdgeProps.style/markerEnd — BC visual idiom is fixed per D-12 regardless of enrichEdges styling (which already strips markerEnd for type:bcEdge anyway)."
  - "Sources toolbox rows are not gated on activeLayer — value-sources carry only BCPorts which do not participate in the Hydraulic/Thermal layer split. They always show."
metrics:
  duration: ~20m
  completed: 2026-05-13
---

# Phase 63 Plan D: Canvas-side BC Surfaces Summary

Four-task plan — 4 commits, +31 vitest cases, zero new tsc errors in the modified files. Wires the BC tab's data contract from Phase 63-B onto the canvas: a custom dashed edge with click-to-cycle target-side chip, a hollow-square BCPort handle on StreamNode, source-block value labels, BC error red-ring, whole-body BC drop overlay, CanvasPanel allow-list enforcement, and value-source draggables in the toolbox.

## What shipped

### gui/src/components/BCEdge.tsx (NEW — 78 lines)

ReactFlow custom edge mirroring HydraulicEdge.tsx in shape with two extensions:

1. **Fixed dashed visual idiom (D-12):**
   - `stroke = var(--muted-foreground)`
   - `strokeWidth = 1.5`
   - `strokeDasharray = "6 3"`
   - No `markerEnd` arrowhead (the inbound EdgeProps style is intentionally NOT consumed — BC edges always render the same way).

2. **EdgeLabelRenderer mid-edge chip (D-11):**
   - Reads `data.targetSide` from `BCEdgeData` (`"left" | "right" | "both"`, defaults to `"both"` when data is absent).
   - Renders `"L+R"` / `"L"` / `"R"` accordingly.
   - `onClick` calls `useStore.getState().cycleBCEdgeTargetSide(id)` — the store action walks the cycle `both → left → right → both` via the pure `cycleBCEdgeTargetSidePure` helper in `bcMode.ts`.
   - `className="nopan"` + `pointerEvents: "all"` so the chip is clickable without panning the canvas.

### gui/src/components/StreamNode.tsx (MODIFIED — +127 / −8)

Four sub-features layered onto the existing component:

**1. BCPort hollow-square handle (D-18)** — `bcPorts.map(...)` alongside the existing flow/thermal handle maps:
```tsx
<Handle
  type="source"
  position={sideToPosition[port.side ?? "right"]}
  data={{ portType: port.type }}
  style={{
    background: "transparent",
    border: "1.5px solid var(--muted-foreground)",
    width: 10,
    height: 10,
    borderRadius: 0,
  }}
/>
```
Rendered for any port with `type === "BCPort"` — currently WallTemperature.`T_wall_out` and HeatFluxSource.`q_out`.

**2. Source-block two-line label (D-19)** — `SOURCE_LABEL_FIELD: Record<string, string>` maps componentId to its primary value parameter (`WallTemperature → T_wall`, `HeatFluxSource → q`). Private helper `sourceLabelLine(parameters, fieldName, unit)` inspects the value's runtime shape:
- `number` → `"T_wall = 320 K"`
- `Array.isArray(value)` → `"T_wall = vector (n=10)"` (n read from `parameters.n`, falls back to array length).
- `string` → `"T_wall = fn(t)"` (callable encoding).
- `undefined | null | ""` → `"T_wall = (unset)"` with `text-destructive/80`.

**3. BC error red-ring (D-22)** — subscribes to `errorTagsByNodeId[id]?.length > 0` via a `useStore` selector that **returns a primitive boolean** (not a fresh array). This was discovered as a bug during execution — see Deviations §1 below. Combined with the legacy `errorNodeIds.has(id)` (Phase-39 topology errors), the red ring lights up when either source has a flag for the node.

**4. Whole-body BC drop overlay (D-10, CD-03)** — `useConnection()` returns `ConnectionState | null` during the drag lifecycle. We gate the dashed-outline overlay on:
- `connection.inProgress === true`,
- `connection.fromHandle?.id` resolves to a `"BCPort"` via `getPortType(...)`,
- the target node has `external_inputs.length > 0` (i.e., is a consumer),
- the target is not the drag source itself.

The overlay is `pointer-events-none` so ReactFlow's own handle hit-testing performs the actual drop — per CD-03 we use the built-in `useConnection` hook rather than hand-rolled mouse listeners. The activated state is visually inspectable via `npm run tauri dev`; jsdom cannot faithfully simulate live drag state so the activation test is Manual-Only per 63-VALIDATION.md.

### gui/src/components/CanvasPanel.tsx (MODIFIED — +15 / −1)

- **edgeTypes registration:** `bcEdge: BCEdge` added alongside `hydraulicEdge: HydraulicEdge`.
- **isValidConnection BCPort branch (D-21):** after the existing port-type check, when `sourceType === "BCPort"` we resolve both endpoints' componentIds via `useStore.getState().nodes.find(...)` and return `isAllowedBCConnection(srcCompId, tgtCompId)`. Pure read — no store mutation inside the callback (RESEARCH Pitfall 7). The n-mismatch flagging (D-22) lives in `useStore.ts` (already wired by Phase 63-B in both `setBCMode` and `addEdge` paths).

### gui/src/components/ToolboxPanel.tsx (MODIFIED — +14 / −1)

`getComponentsByCategory("Sources")` returns the WallTemperature + HeatFluxSource entries. A `<div className="space-y-px">` map under the existing Sources header renders each as a draggable `<ToolboxItem>`. Drag-onto-canvas reuses Phase 62's `application/streamcomponent` dataTransfer path and `addNode`'s smart-name handler — no changes needed there.

## Test files

### gui/src/components/__tests__/BCEdge.test.tsx (NEW — 7 tests)

1. Path style: dashed muted-foreground, strokeWidth 1.5, strokeDasharray "6 3".
2. Chip label `"L+R"` when `targetSide: "both"`.
3. Chip label `"L"` when `targetSide: "left"`.
4. Chip label `"R"` when `targetSide: "right"`.
5. Click chip → `cycleBCEdgeTargetSide(id)` invoked once with edge id.
6. Defaults chip to `"L+R"` when `data` undefined.
7. No `marker-end` attribute on the path (D-12 — no arrow).

EdgeLabelRenderer is stubbed via `vi.mock("@xyflow/react", ...)` to a passthrough div — ReactFlow's portal needs a live renderer host which jsdom doesn't provide. The mock preserves all other exports via `vi.importActual`.

### gui/src/components/__tests__/StreamNode.test.tsx (EXTENDED — +12 / pre-existing 11 preserved)

Three new describe blocks:

- **BCPort handle (D-18) — 3 tests:** hollow-square on WT, hollow-square on HFS, Channel does NOT render BCPort handles.
- **Source-block label (D-19) — 6 tests:** scalar (`T_wall = 320 K`), vector (`T_wall = vector (n=10)`), callable (`T_wall = fn(t)`), unset (`T_wall = (unset)` in muted-destructive), HFS `q` variant, non-source components (Pump) do NOT render a source label.
- **BC error red-ring (D-22) — 2 tests:** tag present → ring-destructive class on root, no tag → no ring class.

### gui/src/components/__tests__/CanvasPanel.bc.test.tsx (NEW — 10 tests)

- **isAllowedBCConnection allow-list (D-21) — 6 tests:**
  - `(WT, Channel) = true`
  - `(WT, ChannelHeatFlux) = false`
  - `(HFS, ChannelHeatFlux) = true`
  - `(HFS, Channel) = false`
  - `(*, ChannelAndContacts) = false` for all sources (CAC carve-out)
  - `(WT, WT) / (HFS, HFS) = false` (same-kind denied)

- **Store path — BC edge materialization — 4 tests:**
  - `setBCMode(..., {mode: "source", ...})` → edge with `type: "bcEdge"` materialised by enrichEdges.
  - N-mismatch flags both endpoints via `errorTagsByNodeId` (D-22).
  - Matched-n does NOT flag.
  - **Canvas-drag (`addEdge`) path also runs `_checkBCNMismatch`** — gates the Blocker-2 wiring from plan-checker review (#3 references to `_checkBCNMismatch` in useStore.ts; ≥1 inside `addEdge` body).

### gui/src/components/__tests__/ToolboxPanel.test.tsx (EXTENDED — replaced 1 Phase-62 assertion with 4 Phase-63 tests)

Replaced the Phase-62 *"no WT / HFS rows in Phase 62"* test with:
- WallTemperature renders.
- HeatFluxSource renders.
- WallTemperature row is draggable (`draggable="true"` ancestor).
- HeatFluxSource row is draggable.
- Sources rows render AFTER the Sources header in DOM order.

Pre-existing Sources-header / DOM-order / styling tests preserved.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Bug] Maximum-update-depth loop from fresh-array zustand selector**

- **Found during:** Task 63-D-02 (first run of `StreamNode.test.tsx`).
- **Issue:** The initial implementation used `useStore(s => s.errorTagsByNodeId[id] ?? [])` to get the BC tag list for the current node. When the key is absent, `?? []` returns a **new array on every render**, and zustand's default shallow equality treats it as a state change → React schedules another render → infinite loop. All 21 new and pre-existing tests in `StreamNode.test.tsx` crashed with `Maximum update depth exceeded` on the first run.
- **Fix:** Replaced the array-returning selector with a primitive boolean selector: `useStore(s => (s.errorTagsByNodeId[id]?.length ?? 0) > 0)` → renamed `errorTags` to `hasBCError`. Booleans have stable identity under shallow equality, so the selector is now idempotent on absence. Same red-ring behavior, no loop.
- **Files modified:** `gui/src/components/StreamNode.tsx`
- **Commit:** 2a33b8d (rolled into Task 63-D-02 commit)

**2. [Rule 1 — Bug] Pre-existing ToolboxPanel.test.tsx asserted the absence of WT/HFS rows**

- **Found during:** Task 63-D-04.
- **Issue:** The Phase-62 test `"D-30: no WallTemperature or HeatFluxSource rows are rendered in Phase 62"` was correct in its phase but is **the exact opposite of what Phase 63-D ships**. Without an update the suite would have regressed.
- **Fix:** Replaced the negative assertion with the four positive Phase-63 assertions documented above. This is the plan's intended cutover (D-24 was always going to invert this assertion). Not a hidden change — explicitly called out in the plan's `<read_first>` for Task 04.
- **Files modified:** `gui/src/components/__tests__/ToolboxPanel.test.tsx`
- **Commit:** 01543d3

### Not auto-fixed (pre-existing items, out of scope)

- **Pre-existing tsc errors** in `StreamNode.tsx` (3 Handle `data` typing warnings — the same pattern carried over from existing FlowPort/ThermalPort handles; my BCPort handle adds one more instance of the same pattern, not a new class of error), `ToolboxPanel.test.tsx` (`activeLayer: "all"` literal — Phase 62 left this), `SidebarRouter.test.tsx`, `lib/validation.test.ts`. All pre-existing per 63-B Summary; Phase 71 will normalise the Handle `data` typing. **Verified my changes introduce NO new tsc errors** by running `git stash` + `tsc --noEmit` on the unstashed and stashed states — same line counts and same patterns.

## Manual-only smoke checklist

The following items cannot be unit-tested in jsdom and are listed in `63-VALIDATION.md` Manual-Only table. They will be exercised via `cd gui && npm run tauri dev` at the Phase-63 manual-verify gate (with sibling Plan 63-C also merged):

- **D-10 whole-body drop activation:** Drag from WallTemperature.T_wall_out onto a Channel body → dashed-outline + "Connect BC" chip appears → release → dashed BC edge created with `targetSide = "both"`.
- **D-20 `+ New WallTemperature` end-to-end flow** (63-C ships the BCs-tab UI; this Plan only ships the canvas side — the manual smoke exercises both together).
- **D-22 visual red-ring:** Confirm the `ring-destructive` class actually paints on both endpoints when an n-mismatched BC edge exists. The unit test covers class application; the manual smoke covers visual rendering.

## Verification

- ✅ `cd gui && npx vitest run src/components/__tests__/BCEdge.test.tsx` → 7/7 passing.
- ✅ `cd gui && npx vitest run src/components/__tests__/StreamNode.test.tsx` → 22/22 passing (11 pre-existing + 11 new).
- ✅ `cd gui && npx vitest run src/components/__tests__/CanvasPanel.bc.test.tsx` → 10/10 passing.
- ✅ `cd gui && npx vitest run src/components/__tests__/ConnectionValidation.test.tsx` → 8/8 passing (no regression to Phase-39 port-type enforcement).
- ✅ `cd gui && npx vitest run src/components/__tests__/ToolboxPanel.test.tsx` → 8/8 passing (4 pre-existing header tests + 4 new draggables tests).
- ✅ `cd gui && npx vitest run src/components/` → 175 passing, 13 todo, 0 failing.
- ✅ `cd gui && npx vitest run` (full suite) → 502 passing, 13 todo, 0 failing (was 471 before; +31 tests from this plan).
- ✅ `cd gui && npx tsc --noEmit` — no new errors in BCEdge.tsx, BCEdge.test.tsx, or CanvasPanel.bc.test.tsx. Pre-existing errors in StreamNode.tsx (Handle data typing), ToolboxPanel.test.tsx (activeLayer "all" literal) unchanged — same line numbers, same patterns as before this plan.
- ✅ `grep -c '_checkBCNMismatch' gui/src/store/useStore.ts` → 6 (≥3 required by acceptance criteria).
- ✅ `awk '/addEdge: \(connection\) =>/,/^  \},/' gui/src/store/useStore.ts | grep -c '_checkBCNMismatch'` → 3 (≥1 required).

## Self-Check: PASSED

Files created:
- `gui/src/components/BCEdge.tsx` — FOUND
- `gui/src/components/__tests__/BCEdge.test.tsx` — FOUND
- `gui/src/components/__tests__/CanvasPanel.bc.test.tsx` — FOUND

Files modified:
- `gui/src/components/StreamNode.tsx` — FOUND, +127 / −8
- `gui/src/components/CanvasPanel.tsx` — FOUND, +15 / −1
- `gui/src/components/ToolboxPanel.tsx` — FOUND, +14 / −1
- `gui/src/components/__tests__/StreamNode.test.tsx` — FOUND, +124 / −1
- `gui/src/components/__tests__/ToolboxPanel.test.tsx` — FOUND, +39 / −6

Commits:
- `d36cc46` feat(63-D): add BCEdge component (dashed style + click-to-cycle chip) — FOUND
- `2a33b8d` feat(63-D): extend StreamNode with BCPort handle, source label, BC error ring, drop overlay — FOUND
- `94200e5` feat(63-D): wire BCEdge + isValidConnection BCPort allow-list in CanvasPanel — FOUND
- `01543d3` feat(63-D): populate Sources toolbox category with WallTemperature + HeatFluxSource — FOUND
