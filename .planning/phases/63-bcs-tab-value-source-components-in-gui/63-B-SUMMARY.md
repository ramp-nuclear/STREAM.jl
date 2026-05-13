---
phase: 63
plan: B
subsystem: gui-data
tags: [bcs-tab, value-source, codegen, store-slice, types]
dependency_graph:
  requires:
    - Phase 61 registry (external_inputs[], BCPort port type, WallTemperature/HeatFluxSource entries)
    - Phase 62 useStore patterns (snapshot discipline, enrichEdges, CodegenResources shape)
  provides:
    - bcMode + bcSymmetric + errorTagsByNodeId store slices
    - setBCMode / clearBCMode / setBCSymmetric / cycleBCEdgeTargetSide store actions
    - BCModeEntry + BCEdgeData TypeScript types (gui/src/lib/bcMode.ts)
    - isAllowedBCConnection pure validator (consumed by 63-D's CanvasPanel.isValidConnection)
    - Per-mode BC emit logic in codeGenerator.ts
  affects:
    - gui/src/components/CodePreview.tsx (wires bcMode/bcSymmetric to generateCode)
    - gui/src/components/Toolbar.tsx (wires bcMode/bcSymmetric to generateCode)
tech_stack:
  added: []
  patterns:
    - "Sentinel-by-absence (bcMode[key] === undefined = required-unset)"
    - "Composite-key store slice: bcModeKey(componentId, externalInputName)"
    - "Discriminated-union BC entry (mirrors PowerShapeResource.kind switch)"
    - "Sibling slice for new error model (errorTagsByNodeId alongside legacy errorNodeIds Set)"
key_files:
  created:
    - gui/src/lib/bcMode.ts
    - gui/src/store/__tests__/useStore.bc.test.ts
    - gui/src/lib/__tests__/codeGenerator.bc.test.ts
  modified:
    - gui/src/store/useStore.ts
    - gui/src/lib/codeGenerator.ts
    - gui/src/components/CodePreview.tsx
    - gui/src/components/Toolbar.tsx
decisions:
  - "Kept existing errorNodeIds: Set<string> unchanged (Phase 39 has 5 consumer sites); added NEW sibling slice errorTagsByNodeId: Record<nodeId, string[]> for BC-specific error tags. Phase 71 will unify."
  - "Symmetric pairing via _left/_right suffix convention (registry external_inputs do NOT declare pair_with — only the thermal ports do)."
  - "Source-mode edge data uses BCEdgeData payload (componentId, externalInputName, targetSide='both' default)."
  - "Required-unset and Mark emit identical Julia text (TODO comment, no equation) — user intent differs but codegen output matches CD-01."
  - "cosine_T_wall_profile helper name (CD-02) — picked over cosine_power_shape to distinguish T-shape from power-shape semantics; the Julia-side helper lands in Phase 63-A."
metrics:
  duration: 14m
  completed: 2026-05-13
---

# Phase 63 Plan B: BCs Tab Data-Only Foundation Summary

Zustand slice + discriminated-union types + per-mode codegen for the v1.1 channel-family external-input BC model. 4 tasks, 4 commits, 31 new tests, zero UI changes.

## What shipped

### gui/src/lib/bcMode.ts (NEW — 126 lines)

Zero React / xyflow / zustand imports. Exports:

- `BCMode = "value" | "profile" | "function" | "mark" | "source"`
- `BCModeEntry` discriminated union (D-04..D-08):
  ```typescript
  | { mode: "value"; value: number }
  | { mode: "profile"; preset: "cosine"; amplitude: number; peakingFactor: number }
  | { mode: "profile"; preset: "file"; path: string }
  | { mode: "function"; signature: "fn(t)" | "fn(t, i)"; functionName: string }
  | { mode: "mark" }
  | { mode: "source"; sourceNodeId: string }
  ```
- `BCEdgeData { componentId, externalInputName, targetSide: "left" | "right" | "both" }` — ReactFlow Edge.data payload for `type: "bcEdge"` edges.
- `bcModeKey(componentId, externalInputName): string` — returns `${componentId}::${externalInputName}` (collision-free for v1.2; component UUIDs do not contain `::`).
- `isAllowedBCConnection(srcCompId, tgtCompId): boolean` — D-21 allow-list:
  - `(WallTemperature, Channel)` → true
  - `(HeatFluxSource, ChannelHeatFlux)` → true
  - All else → false (including any `ChannelAndContacts` target per D-25 / feedback_channel_hd_connection_rule.md).
- `cycleBCEdgeTargetSide(current): "left" | "right" | "both"` — cycle order `both → left → right → both` (D-11).

### gui/src/store/useStore.ts (MODIFIED — +539 lines, -9)

New AppState fields:

- `bcMode: Record<string, BCModeEntry>` — composite-key keyed by `bcModeKey(...)`. Absence = required-unset (D-09 sentinel-by-absence).
- `bcSymmetric: Record<string, boolean>` — composite-key `${nodeId}::${baseField}`. Consumer reads `bcSymmetric[key] ?? true` (default ON per CD-05).
- `errorTagsByNodeId: Record<string, string[]>` — NEW sibling slice. Phase 63 uses tag `"bc-n-mismatch"` for D-22 soft warnings. NOT a replacement for the existing `errorNodeIds: Set<string>` (used by 5 Phase-39 sites including ConnectionValidation test, StreamNode red-ring, ValidationDialog clear, saveProjectAs test, saveAndOpenErrors test).

New actions:

- `setBCMode(componentId, externalInputName, entry)` — snapshot → mutate. If symmetric ON, mirrors entry to sibling. If `entry.mode === "source"`, materializes the `type: "bcEdge"` edge in `edges[]` (idempotent — skips dup). Source → non-source transition or source-A → source-B replacement strips/replaces the stale BC edge. Fires `_checkBCNMismatch` for D-22 detection.
- `clearBCMode(componentId, externalInputName)` — snapshot → remove key + sibling (if symmetric ON) + BC edge + bc-n-mismatch tag (when no remaining source link).
- `setBCSymmetric(nodeId, baseField, symmetric)` — snapshot → flip flag. If turning ON with differing left/right entries, COPIES LEFT TO RIGHT (left wins — documented inline).
- `cycleBCEdgeTargetSide(edgeId)` — snapshot → walks edge's `data.targetSide` through `both → left → right → both`.
- `_revertBCModeForEdge(edge)` — internal; called from `onEdgesChange` when a bcEdge `remove` change lands. Does NOT push a snapshot (outer onEdgesChange already pushed one).
- `_checkBCNMismatch(sourceNodeId, targetNodeId)` — internal; idempotent. Reads `data.parameters.n` from both nodes; adds/removes `bc-n-mismatch` tag on BOTH endpoints accordingly.

Extended:

- `_pushSnapshot`, `undo`, `redo` carry `bcMode`, `bcSymmetric`, `errorTagsByNodeId` alongside the existing `{nodes, edges, bcs, resources, modelOptions}`.
- `enrichEdges` BCPort branch: `srcPort.type === "BCPort"` → strip `markerEnd`, set `type: "bcEdge"`, populate `BCEdgeData` with `targetSide: "both"` default (round-trips existing `targetSide` via data preservation).
- `onEdgesChange` — bcEdge removal triggers `_revertBCModeForEdge` BEFORE `applyEdgeChanges`.
- `addEdge` — when `connection.sourceHandle` resolves to a BCPort, runs `_checkBCNMismatch` AFTER edges land in the store. Wires D-22 for the canvas-drag user path (the BCs-tab user path is covered separately by `setBCMode`).
- `newProject` + `loadProjectFromPath` reset all three BC slices to `{}`. (.scp persistence for BC state is Phase 66 work.)

Module-private helpers added:

- `stripSideSuffix(name)`: `T_wall_left` → `T_wall`, `q_right` → `q`, else unchanged.
- `siblingExternalInputName(name)`: `T_wall_left` ↔ `T_wall_right`; returns null if no `_left`/`_right` suffix.
- `addTagInPlace(map, nodeId, tag)`, `removeTagInPlace(map, nodeId, tag)` — manage `errorTagsByNodeId` entries; remove deletes the key when the array goes empty.

### gui/src/lib/codeGenerator.ts (MODIFIED — +199 lines, -7)

- New exported type: `CodegenBCsState { bcMode, bcSymmetric }`.
- `generateCode(...)` signature extended with a 6th optional argument `bcsState?: CodegenBCsState`. Backward-compatible — pre-Phase-63 callers (none today after the wiring below) continue to work.
- Two emit phases added:
  1. **Pre-eqs BC block** (after thermal-assembly declarations, before `eqs = [`): Profile-cosine emits `cosine_T_wall_profile(n; amplitude=..., peaking_factor=...)` assignment; Profile-file emits `rebin_intensive(readdlm(joinpath(@__DIR__, "<path>"), ','), n)` assignment; Function emits `fn(t) = 0.0  # TODO: define ...` stub (or `fn(t, i)` per signature).
  2. **In-eqs BC binding equations** (after `connect()` calls, before `lines.push("]");`): Value emits `[<ch>.<field>[i] ~ <value> for i in 1:n]...,`; Profile emits binding against profile-var; Function emits binding against stub; Mark and absent entry emit `# TODO: set <ch>.<field>[i] here` (no equation); Source emits binding against source node's BCPort array variable (`<wt>.T_wall_out[i]` / `<hfs>.q_out[i]` resolved from the registry — not hardcoded).
- `using DelimitedFiles` import OR-extended to also fire for any Profile-file BC mode entry.
- Symmetric expansion: when `bcSymmetric[symKey] ?? true` and the `_left` entry exists, the L emission writes TWO binding lines (one for each side); the `_right` sibling is filtered out of the emit plan to avoid duplication.

### gui/src/components/CodePreview.tsx + Toolbar.tsx (MODIFIED — wiring only)

Subscribe to `bcMode` + `bcSymmetric` slices and pass them to `generateCode` as the 6th argument. Without this, the new emit logic would be dead code when 63-C/63-D land. Rule-2 critical scope: keeps the codegen path end-to-end functional.

## Test files

### gui/src/store/__tests__/useStore.bc.test.ts (NEW — 20 tests, 7 describe blocks)

1. **setBCMode core** — composite-key entry, isDirty=true, snapshot push, symmetric mirror, symmetric-OFF leaves sibling untouched.
2. **Source-mode edge creation (D-23)** — bcEdge type, BCEdgeData payload + targetSide=`both`, edge-deletion reverts bcMode, source-A → source-B no duplicate.
3. **N-mismatch soft warning (D-22)** — edge IS created on mismatch + both flagged; no flag on match; tag cleared on edge removal; **canvas-drag path test calling addEdge() directly** (gates the D-22 wiring at addEdge entry point, not only at setBCMode).
4. **clearBCMode (D-09 required-unset)** — key removal, bcEdge stripped, symmetric sibling cleared.
5. **bcSymmetric (CD-05)** — turning ON copies LEFT to RIGHT (left wins).
6. **cycleBCEdgeTargetSide (D-11)** — both → left → right → both.
7. **Snapshot/undo integration** — undo restores all three BC slices + edges.

### gui/src/lib/__tests__/codeGenerator.bc.test.ts (NEW — 11 tests, 1 describe block)

Per-mode codegen substring assertions (mirror codeGenerator.resources.test.ts idiom):
- Value scalar binding
- Profile-cosine: `cosine_T_wall_profile` call + binding
- Profile-file: `rebin_intensive` call + binding
- `using DelimitedFiles` import gated on Profile-file presence
- Function fn(t) and fn(t, i) stub + binding
- Mark TODO comment, no equation
- Required-unset (absent entry) TODO comment, no equation
- Symmetric ON single entry → both bindings
- Symmetric OFF → only one binding + sibling TODO
- Source mode binding against source node's BCPort array variable

## Contract for 63-C / 63-D consumption

**Store shapes 63-C and 63-D will subscribe to:**

| Slice | Shape | Default / sentinel | Read by |
|-------|-------|-------------------|---------|
| `bcMode` | `Record<bcModeKey(componentId, externalInputName), BCModeEntry>` | absence = required-unset (D-09) | BCs-tab UI (63-C); codeGenerator |
| `bcSymmetric` | `Record<${nodeId}::${baseField}, boolean>` | absence = ON (consumer reads `?? true`) | BCs-tab UI (63-C) |
| `errorTagsByNodeId` | `Record<nodeId, string[]>` | absence = no errors | StreamNode renderer (63-D) for red-ring |

**Error tag string format** consumed by 63-D: read `errorTagsByNodeId[nodeId]` (a `string[]`). Tags emitted by Phase 63-B:
- `"bc-n-mismatch"` — fires on D-22 soft warning when `WallTemperature.n !== Channel.n` (or analogous HFS/CHF pair).

Phase 71 will unify `errorNodeIds: Set<string>` and `errorTagsByNodeId` into a single Record-shaped error surface; until then, 63-D should read from `errorTagsByNodeId` for BC-specific tags and `errorNodeIds.has(id)` for Phase-39 topology errors.

**Codegen insertion order** (where BC content appears in the generated `.jl`):

```
using ModelingToolkit, STREAM
using ModelingToolkit: t_nounits as t
using DelimitedFiles  # for file_loaded power shapes / file BC profiles  [gated]
                                                                       [blank]
# ------------------------------------------------- [Resources block — Phase 62]
# Resources
geom_mtr = PipeGeometry_rectangular(...)
power_shape_<name>_for_<hd> = ones(nz, nx)
                                                                       [blank]
@named ch_1 = Channel(...)
@named wt_1 = WallTemperature(...)
                                                                       [blank]
# Thermal assembly (auto-detected: symmetric_plate)                     [Phase 62]
@named plate_1 = symmetric_plate(...)
                                                                       [blank]
# ------------------------------------------------- [Phase 63: BCs block]
# Boundary conditions (Phase 63)
ch_1_T_wall_left_profile = cosine_T_wall_profile(10; amplitude=50.0, peaking_factor=1.5)
T_wall_left_fn(t) = 0.0  # TODO: define your time-varying boundary condition
                                                                       [blank]
eqs = [
    connect(pump_1.port_out, ch_1.port_in),
    # ... other connects
    # BCs for ch_1:
    [ch_1.T_wall_left[i] ~ 320.0 for i in 1:10]...,
    [ch_1.T_wall_right[i] ~ 320.0 for i in 1:10]...,  # symmetric expansion
    # TODO: set ch_1.q_some_other[i] here              # required-unset
]
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Dropped unused `isAllowedBCConnection` import from useStore.ts**

- **Found during:** Task 63-B-02
- **Issue:** Plan said to import `isAllowedBCConnection` into useStore.ts; but the function is consumed only by `CanvasPanel.isValidConnection` (Phase 63-D, not yet landed). Importing-unused would fail `tsc --noEmit` (TS6133 declared-but-unused).
- **Fix:** Imported only the symbols useStore actually consumes: `bcModeKey`, `cycleBCEdgeTargetSide` (as `cycleBCEdgeTargetSidePure`), `BCModeEntry`, `BCEdgeData`. `isAllowedBCConnection` remains exported from `bcMode.ts` ready for 63-D consumption.
- **Files modified:** `gui/src/store/useStore.ts`
- **Commit:** b1d39db

**2. [Rule 2 - Critical scope] Added NEW sibling slice `errorTagsByNodeId` instead of mutating `errorNodeIds` shape**

- **Found during:** Task 63-B-02
- **Issue:** Plan specified `errorNodeIds: Record<string, string[]>` shape, but the existing `errorNodeIds: Set<string>` is used by 5 distinct sites: `validateAndGate` / `clearValidation` (Phase 39 topology validation), `addEdge` (errorNodeIds.size check + `new Set(errorNodeIds)`), `StreamNode.tsx` line 33 (`errorNodeIds.has(id)`), and three test files (`ConnectionValidation.test.tsx`, `saveProjectAs.test.ts`, `saveAndOpenErrors.test.ts`) that all do `errorNodeIds: new Set<string>()`. Changing the shape would force coordinated edits to 8+ files and break those tests with no functional benefit at this phase.
- **Fix:** Kept `errorNodeIds: Set<string>` untouched (Phase 39 semantics preserved); added a NEW sibling slice `errorTagsByNodeId: Record<nodeId, string[]>` for the BC-specific tag-shaped error model. The new BC slice is what 63-D will read for red-ring rendering on BC errors. The two surfaces will be unified in Phase 71 ("Phase 71 supersedes the shape — Phase 63 ships the minimal form" — plan's own caveat). Documented in code comments + this Summary.
- **Files modified:** `gui/src/store/useStore.ts`
- **Test impact:** The Task 63-B-03 test text uses `errorTagsByNodeId[wtId]` rather than the plan's verbatim `errorNodeIds[wtId]`. The plan's verbatim text was illustrative.
- **Commit:** b1d39db, a44314c

**3. [Rule 2 - Critical scope] Wired bcMode/bcSymmetric through CodePreview + Toolbar**

- **Found during:** Task 63-B-04
- **Issue:** `generateCode` gained a 6th optional argument for `bcsState`. Without updating `CodePreview.tsx` and `Toolbar.tsx` (the two production call sites — both call `generateCode(nodes, edges, bcs, getComponent, resources)`), the new BC emit logic would be dead code when 63-C/63-D land. Plan implicitly required the codegen to work end-to-end.
- **Fix:** Both components now subscribe to `bcMode` + `bcSymmetric` slices and pass them as the 6th argument. Behavior is fully backward-compatible — when no BC state is set, codegen output is unchanged.
- **Files modified:** `gui/src/components/CodePreview.tsx`, `gui/src/components/Toolbar.tsx`
- **Commit:** f884f5a

## Pre-existing items left untouched

- **Pre-existing tsc errors** in `StreamNode.tsx`, `ToolboxPanel.test.tsx`, `SidebarRouter.test.tsx`, `lib/validation.test.ts` are unchanged (Phase 61 / 62 deferred items per `.planning/phases/61-.../deferred-items.md`). This plan did not introduce ANY new tsc error in the modified files (confirmed: `npx tsc --noEmit 2>&1 | grep -E 'useStore\.ts|codeGenerator\.ts|bcMode\.ts' | wc -l` returns 0).
- **registry `pair_with` field on external_inputs** is NOT declared in v1.1 components.json (only the thermal ports declare it). Plan's `interfaces` excerpt suggested it might exist; we use the `_left`/`_right` suffix convention for symmetric pairing instead — documented in `stripSideSuffix` / `siblingExternalInputName` helpers.

## Verification

- ✅ `cd gui && npx vitest run src/store/__tests__/useStore.bc.test.ts src/lib/__tests__/codeGenerator.bc.test.ts` → 31/31 passing (20 BC slice tests + 11 BC codegen tests).
- ✅ `cd gui && npx vitest run` (full suite) → 471 passing, 13 todo, 1 skipped, 0 failing.
- ✅ `cd gui && npx tsc --noEmit 2>&1 | grep -E 'useStore\.ts|codeGenerator\.ts|bcMode\.ts'` → 0 lines (no new tsc errors in the modified files; pre-existing 7 tsc errors elsewhere are Phase 71 work).
- ✅ Pre-existing `codeGenerator.smoke.test.ts` + `codeGenerator.resources.test.ts` + `useStore.test.ts` all pass — no regressions.

## Self-Check: PASSED

Files created:
- `gui/src/lib/bcMode.ts` — FOUND
- `gui/src/store/__tests__/useStore.bc.test.ts` — FOUND
- `gui/src/lib/__tests__/codeGenerator.bc.test.ts` — FOUND

Commits:
- `25191dc` feat(63-B): add bcMode.ts shared types + pure validators — FOUND
- `b1d39db` feat(63-B): extend useStore with bcMode / bcSymmetric / errorTagsByNodeId slices — FOUND
- `a44314c` test(63-B): add useStore.bc.test.ts (20 tests across 7 describe blocks) — FOUND
- `f884f5a` feat(63-B): per-mode BC emit in codeGenerator + codeGenerator.bc.test.ts — FOUND

Smoke-test scope per `feedback_smoke_test_scope_match.md`: 63-B is data-only. The plan promised NO UI visibility — it ships only the store mutation contract + codegen output for the five BC modes. 63-C lands the BCs-tab UI; 63-D lands the canvas BC edge + StreamNode BCPort handle + drop overlay.
