---
phase: 63
plan: B
type: execute
wave: 1
depends_on: []
files_modified:
  - gui/src/lib/bcMode.ts
  - gui/src/store/useStore.ts
  - gui/src/lib/codeGenerator.ts
  - gui/src/store/__tests__/useStore.bc.test.ts
  - gui/src/lib/__tests__/codeGenerator.bc.test.ts
autonomous: true
requirements:
  - D-04
  - D-05
  - D-06
  - D-07
  - D-08
  - D-09
  - D-21
  - D-22
  - D-23
  - CD-01
  - CD-02
  - CD-04
  - CD-05
user_setup: []

must_haves:
  truths:
    - "`bcMode` slice in zustand store with composite-key `(componentId, externalInputName)` is single source-of-truth (D-23)"
    - "Setting `mode='source'` via `setBCMode` creates the corresponding BC edge in `edges[]` and is undoable"
    - "Removing a BC edge via `onEdgesChange` reverts the matching `bcMode` entry to `undefined` (required-unset)"
    - "Codegen emits correct Julia text for all five BC modes (Value / Profile-cosine / Profile-file / Function / Mark) plus symmetric L=R expansion"
    - "n-mismatch on BCPort connect creates the edge AND records both endpoints in `errorNodeIds` (soft warning per D-22)"
    - "Type-mismatch validation rules are encoded in a registry-driven validator function reusable by `isValidConnection` (D-21) — pure function, no state mutation"
  artifacts:
    - path: "gui/src/lib/bcMode.ts"
      provides: "BCModeEntry discriminated union, BCEdgeData type, bcModeKey() helper, isAllowedBCConnection() pure validator"
      contains: "export type BCModeEntry"
    - path: "gui/src/store/useStore.ts"
      provides: "bcMode + bcSymmetric slice, setBCMode/clearBCMode/setBCSymmetric/cycleBCEdgeTargetSide actions, n-mismatch errorNodeIds detection, enrichEdges BCPort branch, snapshot integration"
      contains: "bcMode:"
    - path: "gui/src/lib/codeGenerator.ts"
      provides: "Per-channel BC emit logic: 5-mode switch + symmetric-L=R expansion + unset/Mark TODO emission"
      contains: "bcMode"
    - path: "gui/src/store/__tests__/useStore.bc.test.ts"
      provides: "Slice-shaped coverage: setBCMode/clearBCMode/source-edge sync/edge-deletion revert/n-mismatch flagging"
      contains: "describe(\"bcMode slice"
    - path: "gui/src/lib/__tests__/codeGenerator.bc.test.ts"
      provides: "Per-mode emit coverage + symmetric expansion snapshots"
      contains: "describe(\"codeGenerator BC emit"
  key_links:
    - from: "gui/src/store/useStore.ts"
      to: "gui/src/lib/bcMode.ts"
      via: "import { bcModeKey, BCModeEntry, isAllowedBCConnection }"
      pattern: "from .*lib/bcMode"
    - from: "gui/src/lib/codeGenerator.ts"
      to: "gui/src/store/useStore.ts"
      via: "reads store snapshot — `state.bcMode`, `state.bcSymmetric`"
      pattern: "state\\.bcMode|state\\.bcSymmetric"
    - from: "gui/src/store/useStore.ts (enrichEdges)"
      to: "gui/src/components/BCEdge.tsx (created in 63-D)"
      via: "edge.type = 'bcEdge' assignment + edge.data = { targetSide, componentId, externalInputName }"
      pattern: "type: \"bcEdge\""
---

<objective>
Land the data-only foundation that the BCs-tab UI (63-C) and the canvas BC edge (63-D) will subscribe to. Phase 63-B does NOT touch any visible React component file — it adds shared types (`gui/src/lib/bcMode.ts`), a zustand store slice + actions + edge-enrichment branch, and the per-mode emit logic in `codeGenerator.ts`. Two new vitest files (`useStore.bc.test.ts`, `codeGenerator.bc.test.ts`) cover the slice and the emit logic.

Per `feedback_smoke_test_scope_match.md`: this plan promises NO UI visibility. Its gate is `npx vitest run` on the two new test files plus the codegen smoke test continuing to pass.

Purpose: Provide the contract that 63-C and 63-D consume — `BCModeEntry`, `BCEdgeData`, `setBCMode`/`clearBCMode`/`cycleBCEdgeTargetSide`/`setBCSymmetric` actions, `enrichEdges` BCPort branch assigning `type: "bcEdge"`, and pure validator `isAllowedBCConnection`. Without this, the Wave-2 plans cannot wire up.
Output: One new shared types file, store extension, codegen extension, two new test files.
</objective>

<execution_context>
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/workflows/execute-plan.md
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@CLAUDE.md
@.planning/STATE.md
@.planning/phases/63-bcs-tab-value-source-components-in-gui/63-CONTEXT.md
@.planning/phases/63-bcs-tab-value-source-components-in-gui/63-RESEARCH.md
@.planning/phases/63-bcs-tab-value-source-components-in-gui/63-PATTERNS.md
@.planning/phases/63-bcs-tab-value-source-components-in-gui/63-VALIDATION.md
@gui/src/store/useStore.ts
@gui/src/lib/codeGenerator.ts
@gui/src/registry/types.ts
@gui/src/registry/components.json
@gui/src/store/__tests__/useStore.test.ts
@gui/src/store/__tests__/resources.slice.test.ts
@gui/src/lib/__tests__/codeGenerator.resources.test.ts

<interfaces>
<!-- Source-of-truth shapes Phase 63-B implements + consumes. -->

From gui/src/registry/types.ts (Phase 61):
  interface ExternalInput {
    name: string;           // e.g., "T_wall_left", "T_wall_right", "q_left", "q_right"
    type: string;           // e.g., "Real | Vector | Function"
    array_size?: string;    // "n"
    pair_with?: string;     // sibling field for symmetric-toggle grouping (e.g., T_wall_left ↔ T_wall_right)
    bc_modes?: ReadonlyArray<"value" | "profile" | "function" | "mark" | "source">;
    source_component?: string;  // "WallTemperature" or "HeatFluxSource"
    source_port?: string;
    default_axis?: "horizontal" | "vertical";
  }
  interface ComponentDefinition {
    external_inputs?: ReadonlyArray<ExternalInput>;
    // ... other fields per Phase 61
  }

From gui/src/registry/components.json (Phase 61, lines 79-98, 568-642, 1015-1082):
  Channel.external_inputs = [{name:"T_wall_left", pair_with:"T_wall_right", source_component:"WallTemperature", ...}, {name:"T_wall_right", pair_with:"T_wall_left", ...}]
  ChannelHeatFlux.external_inputs = [{name:"q_left", pair_with:"q_right", source_component:"HeatFluxSource", ...}, {name:"q_right", ...}]
  WallTemperature.ports = [{name:"T_wall_out", type:"BCPort", array_size:"n", side:"right"}]
  HeatFluxSource.ports = [{name:"q_out", type:"BCPort", array_size:"n", side:"right"}]

From gui/src/store/useStore.ts (Phase 62):
  - `_pushSnapshot()` at lines 613-622 captures `{nodes, edges, bcs, resources, modelOptions}` — 63-B extends to also capture `bcMode, bcSymmetric, errorNodeIds`.
  - `undo`/`redo` at lines 624-666 — must apply the extended snapshot shape.
  - `enrichEdges(edges, nodes)` at lines 493-520 — discriminates by source-port type; assigns `type: "hydraulicEdge"` and `markerEnd`. 63-B adds a `srcPort?.type === "BCPort"` branch that sets `type: "bcEdge"`, strips `markerEnd`, and initializes `data: { targetSide: "both", componentId, externalInputName }`.
  - `onEdgesChange` at lines 704-714 — 63-B extends to detect `remove` changes whose edge.type === "bcEdge" and call internal `_revertBCModeForEdge(edge)` BEFORE applyEdgeChanges.
  - `getNextInstanceName` at lines 237-241 — reused unchanged for source-block naming.
  - `addNode(componentId, position)` at line 747 — reused unchanged for `+ New` flow (63-C will call it).

From gui/src/lib/codeGenerator.ts (Phase 62):
  - Per-kind switch for PowerShape at lines 853-871 — model for 5-mode BC switch.
  - SENTINEL_UNSET_POWER_SHAPE_UUID block at lines 817-823 — model for required-unset TODO emit.
  - `rebin_extensive(readdlm(...), (nz, nx))` emit at line 867 — model for `rebin_intensive(readdlm(...), n)` emit.
  - Conditional `using DelimitedFiles` insertion (search for the string) — extend OR-condition to include Profile-file BC modes.
  - Components emit loop ends at line ~941 — Phase 63-B inserts BC profile-import vars + function stubs AFTER this, BEFORE `eqs = [`.
  - `eqs = [` block — Phase 63-B inserts BC binding equations AFTER `connect()` lines but inside `eqs = [`.
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 63-B-01: Create `gui/src/lib/bcMode.ts` with discriminated-union types and `isAllowedBCConnection` pure validator</name>
  <files>gui/src/lib/bcMode.ts</files>
  <read_first>
    - gui/src/lib/utils.ts (file form-factor — a tiny pure helper module, no React)
    - gui/src/store/useStore.ts lines 1-100 (existing top-level type declarations for the shape of inline-typed slices)
    - gui/src/registry/components.json lines 1015-1082 (`WallTemperature` and `HeatFluxSource` definitions — source-component allow-list ground truth)
    - .planning/phases/63-bcs-tab-value-source-components-in-gui/63-PATTERNS.md section "`gui/src/lib/bcMode.ts` (NEW — utility / types)" for the docblock + discriminated-union template
    - .planning/phases/63-bcs-tab-value-source-components-in-gui/63-CONTEXT.md — D-21 (type-mismatch allow-list), D-23 (single source of truth)
  </read_first>
  <action>
Create a new file `gui/src/lib/bcMode.ts`. Zero React imports. Zero zustand imports. The module exports:

1. `export type BCMode = "value" | "profile" | "function" | "mark" | "source";`

2. `export type BCModeEntry` — discriminated union per CONTEXT D-04..D-08:
   - `{ mode: "value"; value: number }`
   - `{ mode: "profile"; preset: "cosine"; amplitude: number; peakingFactor: number }`
   - `{ mode: "profile"; preset: "file"; path: string }`
   - `{ mode: "function"; signature: "fn(t)" | "fn(t, i)"; functionName: string }`
   - `{ mode: "mark" }`
   - `{ mode: "source"; sourceNodeId: string }`

3. `export interface BCEdgeData { componentId: string; externalInputName: string; targetSide: "left" | "right" | "both" }`

4. `export function bcModeKey(componentId: string, externalInputName: string): string` — returns `${componentId}::${externalInputName}` (`::` separator; component UUIDs do not contain `::`).

5. `export function isAllowedBCConnection(sourceComponentId: string, targetComponentId: string): boolean` — registry-grounded allow-list per D-21:
   - `("WallTemperature", "Channel")` → true
   - `("HeatFluxSource", "ChannelHeatFlux")` → true
   - all other pairs → false (including any pair where `targetComponentId === "ChannelAndContacts"`)

6. `export function cycleBCEdgeTargetSide(current: "left" | "right" | "both"): "left" | "right" | "both"` — cycle order `both → left → right → both` (per D-11 spec).

7. File header docblock matching the style at top of `codeGenerator.ts` (multi-line `//` comment). Reference D-09 sentinel-by-absence and D-23 single-source-of-truth.

`isAllowedBCConnection` is INTENTIONALLY pure (no store reads) so `isValidConnection` in `CanvasPanel.tsx` (63-D) can call it without violating the ReactFlow purity rule (RESEARCH Pitfall 7).
  </action>
  <behavior>
- `bcModeKey("ch1", "T_wall_left") === "ch1::T_wall_left"` (deterministic, collision-free for v1.2 because no UUID contains `::`).
- `isAllowedBCConnection("WallTemperature", "Channel") === true`.
- `isAllowedBCConnection("WallTemperature", "ChannelHeatFlux") === false`.
- `isAllowedBCConnection("HeatFluxSource", "Channel") === false`.
- `isAllowedBCConnection("HeatFluxSource", "ChannelAndContacts") === false`.
- `cycleBCEdgeTargetSide("both") === "left"`; `cycleBCEdgeTargetSide("left") === "right"`; `cycleBCEdgeTargetSide("right") === "both"`.
- Module has zero runtime side effects when imported.
- TypeScript `tsc --noEmit` accepts the discriminated union with no `any` casts in downstream consumers.
  </behavior>
  <verify>
    <automated>cd gui && npx tsc --noEmit src/lib/bcMode.ts</automated>
  </verify>
  <acceptance_criteria>
    - `gui/src/lib/bcMode.ts` exists
    - `grep -c '^export type BCModeEntry' gui/src/lib/bcMode.ts` returns 1
    - `grep -c '^export function isAllowedBCConnection' gui/src/lib/bcMode.ts` returns 1
    - `grep -c '^export function cycleBCEdgeTargetSide' gui/src/lib/bcMode.ts` returns 1
    - `grep -c '^export function bcModeKey' gui/src/lib/bcMode.ts` returns 1
    - `grep -c '^export interface BCEdgeData' gui/src/lib/bcMode.ts` returns 1
    - `cd gui && npx tsc --noEmit src/lib/bcMode.ts` exits 0
    - File has zero `import` statements for react, @xyflow/react, zustand (`grep -E '^import .* from .*(react|xyflow|zustand)' gui/src/lib/bcMode.ts` returns 0 lines)
  </acceptance_criteria>
  <done>Shared types + pure validator module exists; consumed by store and codegen below.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 63-B-02: Extend `useStore.ts` with `bcMode` + `bcSymmetric` + `errorNodeIds` slices, actions, enrichEdges branch, onEdgesChange revert, snapshot integration</name>
  <files>gui/src/store/useStore.ts</files>
  <read_first>
    - gui/src/store/useStore.ts (entire file — you MUST understand the snapshot discipline at lines 613-622, the undo/redo apply at 624-666, the `enrichEdges` at 493-520, the `onEdgesChange` at 704-714, the `addGeometry` action shape at 875-889, and the `addNode` at line 747 before editing)
    - gui/src/lib/bcMode.ts (post-Task-63-B-01) — confirm the symbols this file imports
    - gui/src/registry/index.ts — confirm `getComponent` signature for registry lookups
    - .planning/phases/63-bcs-tab-value-source-components-in-gui/63-PATTERNS.md section "`gui/src/store/useStore.ts` (MODIFIED — bcMode slice)" for snapshot + action + enrichEdges + onEdgesChange templates
    - .planning/phases/63-bcs-tab-value-source-components-in-gui/63-CONTEXT.md — D-22 (n-mismatch soft warning, errorNodeIds flagging), D-23 (sync), CD-05 (bcSymmetric persisted per-instance)
    - .planning/phases/63-bcs-tab-value-source-components-in-gui/63-RESEARCH.md Pattern 6 + Pitfall 3 (edge-deletion-reverts-bcMode requires diffing changes BEFORE applyEdgeChanges)
  </read_first>
  <action>
Surgically extend `useStore.ts`. All store actions follow the existing pattern: read get(), validate (if applicable), call `_pushSnapshot()`, set(...), set `isDirty: true`.

1. Add imports at the top of the file:
   `import { bcModeKey, isAllowedBCConnection, cycleBCEdgeTargetSide, type BCModeEntry, type BCEdgeData } from "@/lib/bcMode";`

2. Extend the state-shape interface (the typed `StoreState`/`StoreActions` interfaces near the top of the file — line numbers vary, locate via `grep -n 'interface.*State' useStore.ts`). Add three slices:
   - `bcMode: Record<string, BCModeEntry>` — composite-key `bcModeKey(componentId, externalInputName) → entry`. Absence of a key = required-unset.
   - `bcSymmetric: Record<string, boolean>` — composite-key `${nodeId}::${baseFieldName}` (e.g., `"ch1::T_wall"`) → boolean. Default ON (per CD-05 — persisted per-component-instance).
   - `errorNodeIds: Record<string, string[]>` — `nodeId → array of error tags` (e.g., `["bc-n-mismatch:WallTemperature-wt1"]`). Used by 63-D StreamNode renderer to show red-ring. Phase 71 supersedes the shape — Phase 63 ships the minimal form.

3. Initialize all three to `{}` in the store's initial-state literal.

4. Extend the `_pushSnapshot()` body (lines 613-622) to capture `bcMode, bcSymmetric, errorNodeIds` alongside the existing `{nodes, edges, bcs, resources, modelOptions}`.

5. Extend `undo` and `redo` (lines 624-666) to apply `bcMode, bcSymmetric, errorNodeIds` from the snapshot.

6. Add five new actions to the actions interface AND to the store implementation:

   a. `setBCMode(componentId: string, externalInputName: string, entry: BCModeEntry): void`
      - Push snapshot.
      - Mutate `bcMode[bcModeKey(componentId, externalInputName)] = entry`.
      - If `bcSymmetric` for this `(componentId, baseField)` is true (where `baseField` is the result of stripping the trailing `_left`/`_right` from `externalInputName`), ALSO write the entry to the sibling key (`bcModeKey(componentId, siblingName)`).
      - If `entry.mode === "source"`, call internal `_onBCEdgeAdded(componentId, externalInputName, entry.sourceNodeId)` which:
          * Constructs an `Edge` with `source: entry.sourceNodeId`, `sourceHandle: <BCPort name from registry — "T_wall_out" or "q_out">`, `target: componentId`, `targetHandle: <externalInputName>`, `data: { componentId, externalInputName, targetSide: "both" } satisfies BCEdgeData`.
          * Adds it to `edges[]` (skipping if an edge with same source/target/handles already exists — idempotent).
      - If the previous `bcMode[key]` had `mode === "source"` and the new entry's source differs OR the new entry is non-source, remove the old BC edge from `edges[]`.
      - Run n-mismatch check via internal `_checkBCNMismatch(componentId, sourceNodeId)`: read both nodes' `n` from `data.parameters.n` (registry-grounded); if mismatch, add error tag `"bc-n-mismatch"` to BOTH nodeIds in `errorNodeIds`; otherwise clear that tag from both.
      - `set({ ..., isDirty: true })`.

   b. `clearBCMode(componentId: string, externalInputName: string): void`
      - Push snapshot.
      - Remove the key. If symmetric is ON, also remove the sibling. If a source-mode edge existed for this key, remove it. Clear `bc-n-mismatch` tag from both endpoints if no other BC link remains.
      - `set({ ..., isDirty: true })`.

   c. `setBCSymmetric(nodeId: string, baseField: string, symmetric: boolean): void`
      - Push snapshot.
      - Set `bcSymmetric[\`${nodeId}::${baseField}\`] = symmetric`.
      - If turning ON and `bcMode` entries differ between `_left` and `_right`, COPY the `_left` entry to `_right` (left wins — predictable rule, documented inline).
      - `set({ ..., isDirty: true })`.

   d. `cycleBCEdgeTargetSide(edgeId: string): void`
      - Push snapshot.
      - Find the edge in `edges[]` by id; if found and `edge.type === "bcEdge"`, set `edge.data.targetSide = cycleBCEdgeTargetSide(edge.data.targetSide)` (using the imported pure helper).
      - `set({ edges: [...newEdges], isDirty: true })`.

   e. `_revertBCModeForEdge(edge: Edge): void` — internal, called from `onEdgesChange`:
      - If `edge.type === "bcEdge"`, extract `componentId, externalInputName` from `edge.data as BCEdgeData`. Clear `bcMode[bcModeKey(componentId, externalInputName)]` and the sibling if symmetric. Clear `bc-n-mismatch` tag from both endpoints.
      - Do NOT push a snapshot here — the outer `onEdgesChange` already pushed one for `remove` changes.

7. Extend `onEdgesChange` (lines 704-714):
   - Before `applyEdgeChanges`, iterate `changes.filter(c => c.type === "remove")` and look up each removed edge in `get().edges`. For each whose `type === "bcEdge"`, call `_revertBCModeForEdge(edge)`.
   - Keep the existing `_pushSnapshot()` call for any `remove` change.

8. Extend `enrichEdges` (lines 493-520):
   - In the existing `srcPort?.type === "ThermalPort"` branch, also handle `srcPort?.type === "BCPort"`: strip `markerEnd`, set `type: "bcEdge"`, set `data` to existing `e.data` if it already has `componentId/externalInputName/targetSide`, else initialize:
     `{ componentId: e.target, externalInputName: e.targetHandle ?? "", targetSide: (e.data as BCEdgeData | undefined)?.targetSide ?? "both" }`.

9. No GUI-side import of `gui/src/components/...` allowed in `useStore.ts` (store stays UI-agnostic per Phase 62 discipline). All edge-creation work is plain `Edge[]` mutation.

Critical: do NOT remove any pre-existing action, slice, or test-affecting export. Phase 63-B is purely additive at the store level.
  </action>
  <behavior>
- Setting `setBCMode("ch1", "T_wall_left", {mode: "value", value: 320})` with symmetric ON writes both `ch1::T_wall_left` and `ch1::T_wall_right` entries, sets `isDirty: true`, pushes snapshot.
- Setting `setBCMode("ch1", "T_wall_left", {mode: "source", sourceNodeId: "wt1"})` adds a BC edge `{source:"wt1", sourceHandle:"T_wall_out", target:"ch1", targetHandle:"T_wall_left", type:"bcEdge", data:{...,targetSide:"both"}}` to `edges[]`.
- Removing that edge via `onEdgesChange([{type:"remove", id:<id>}])` clears the `bcMode` entry (and the symmetric sibling if applicable) and clears the `bc-n-mismatch` tag.
- Setting `setBCMode` with `sourceNodeId` whose `n` differs from consumer's `n` adds tag `"bc-n-mismatch"` to BOTH `errorNodeIds[sourceNodeId]` and `errorNodeIds[consumerNodeId]`.
- `setBCSymmetric("ch1", "T_wall", true)` after differing left/right entries copies left to right (left wins).
- `cycleBCEdgeTargetSide(edgeId)` walks `both → left → right → both`.
- Undo after `setBCMode` restores all three slices (`bcMode`, `bcSymmetric`, `errorNodeIds`) AND `edges` to pre-mutation state.
  </behavior>
  <verify>
    <automated>cd gui && npx tsc --noEmit src/store/useStore.ts</automated>
  </verify>
  <acceptance_criteria>
    - `grep -c 'bcMode:' gui/src/store/useStore.ts` returns at least 3 (interface, initial state, snapshot/undo references)
    - `grep -c 'bcSymmetric:' gui/src/store/useStore.ts` returns at least 3
    - `grep -c 'errorNodeIds' gui/src/store/useStore.ts` returns at least 4
    - `grep -c 'setBCMode' gui/src/store/useStore.ts` returns at least 3 (interface, implementation, internal calls)
    - `grep -c 'clearBCMode' gui/src/store/useStore.ts` returns at least 2
    - `grep -c 'setBCSymmetric' gui/src/store/useStore.ts` returns at least 2
    - `grep -c 'cycleBCEdgeTargetSide' gui/src/store/useStore.ts` returns at least 2
    - `grep -c '_revertBCModeForEdge' gui/src/store/useStore.ts` returns at least 2
    - `grep -E 'type: "bcEdge"' gui/src/store/useStore.ts` returns at least 1 line (inside enrichEdges)
    - `grep -E 'from "@/lib/bcMode"' gui/src/store/useStore.ts` returns 1 line
    - `cd gui && npx tsc --noEmit` exits 0 (whole project compiles — exceptions: the 7 pre-existing tsc errors documented in `.planning/phases/61-.../deferred-items.md` may still appear; this task must not ADD any new tsc error in `useStore.ts` itself; verify by `cd gui && npx tsc --noEmit 2>&1 | grep useStore.ts` returns 0 lines)
    - `cd gui && npx vitest run src/store/__tests__/useStore.test.ts` exits 0 (pre-existing tests still green)
  </acceptance_criteria>
  <done>Store extended additively; all pre-existing tests green; new actions present and callable.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 63-B-03: Add `useStore.bc.test.ts` covering setBCMode / clearBCMode / source-sync / edge-deletion-revert / n-mismatch flagging / setBCSymmetric / cycleBCEdgeTargetSide</name>
  <files>gui/src/store/__tests__/useStore.bc.test.ts</files>
  <read_first>
    - gui/src/store/__tests__/useStore.test.ts (lines 1-90 — bootstrap pattern: `beforeEach` resets store state; happy-dom env directive)
    - gui/src/store/__tests__/resources.slice.test.ts (slice-shaped coverage idiom)
    - gui/src/store/useStore.ts (post-Task-63-B-02) — confirm exact action signatures and initial-state keys
    - gui/src/lib/bcMode.ts (post-Task-63-B-01) — for `BCModeEntry` shape used in test fixtures
    - .planning/phases/63-bcs-tab-value-source-components-in-gui/63-PATTERNS.md section "`gui/src/store/__tests__/bcMode.slice.test.ts` (NEW)" for bootstrap + coverage list
    - .planning/phases/63-bcs-tab-value-source-components-in-gui/63-VALIDATION.md tasks 63-B-01..03 (sample assertions)
  </read_first>
  <action>
Create a new vitest file. Header:
```
// @vitest-environment happy-dom
import { describe, it, expect, beforeEach } from "vitest";
import useStore from "../useStore";
```

`beforeEach` resets:
```
useStore.setState({
  nodes: [], edges: [], selectedNodeId: null, bcs: [],
  bcMode: {}, bcSymmetric: {}, errorNodeIds: {},
  isDirty: false, _undoPast: [], _undoFuture: [],
  // ... whatever other slices the existing reset block uses; copy from useStore.test.ts beforeEach.
});
```

Each describe block tests one action surface. Use minimal fixture nodes (`{id: "ch1", data: {componentId: "Channel", parameters: {n: 10}}}` and `{id: "wt1", data: {componentId: "WallTemperature", parameters: {n: 10}}}`) seeded via `useStore.setState({ nodes: [...] })` before exercising actions.

Test groups:

1. `describe("bcMode slice — setBCMode")`:
   - `it("creates a value-mode entry under the composite key (D-23)")`
   - `it("sets isDirty to true (D-23)")`
   - `it("pushes a snapshot (undo restores prior state)")`
   - `it("with symmetric ON, mirrors entry to sibling field (D-05)")`
   - `it("with symmetric OFF, leaves sibling untouched (D-05)")`

2. `describe("bcMode slice — source-mode edge creation (D-23 bidirectional sync)")`:
   - `it("creates an edge with type='bcEdge' when mode='source'")`
   - `it("edge data carries componentId, externalInputName, targetSide='both' (D-11 default)")`
   - `it("removing the BC edge via onEdgesChange reverts bcMode to undefined (D-23)")`
   - `it("changing from source-A to source-B replaces the edge, not duplicates it")`

3. `describe("bcMode slice — n-mismatch soft warning (D-22)")`:
   - `it("creates edge AND flags both nodes when source.n !== consumer.n")`
   - `it("does NOT flag when source.n === consumer.n")`
   - `it("clears bc-n-mismatch tag when the BC edge is removed")`

4. `describe("bcMode slice — clearBCMode (D-09 required-unset)")`:
   - `it("removes the key entirely; lookup returns undefined")`
   - `it("removes the BC edge if it was source-mode")`
   - `it("with symmetric ON, also clears the sibling")`

5. `describe("bcSymmetric slice (CD-05)")`:
   - `it("setBCSymmetric(true) when left/right differ copies left to right (left wins)")`
   - `it("setBCSymmetric(false) leaves existing entries untouched")`

6. `describe("cycleBCEdgeTargetSide (D-11)")`:
   - `it("walks both → left → right → both on successive calls")`

Use registry-grounded edge constants ("T_wall_out" / "T_wall_left" / etc.) from the production registry — do NOT hardcode strings divorced from what `enrichEdges` actually emits.

Snapshot integration test: after `setBCMode`, calling `useStore.getState().undo()` must restore `bcMode === {}`, `edges === []`, `errorNodeIds === {}`.
  </action>
  <verify>
    <automated>cd gui && npx vitest run src/store/__tests__/useStore.bc.test.ts</automated>
  </verify>
  <acceptance_criteria>
    - File exists
    - `grep -c '^describe(' gui/src/store/__tests__/useStore.bc.test.ts` returns at least 6
    - `grep -c '^\s*it(' gui/src/store/__tests__/useStore.bc.test.ts` returns at least 15
    - `cd gui && npx vitest run src/store/__tests__/useStore.bc.test.ts` exits 0
    - Vitest output reports zero failures and zero skipped tests
  </acceptance_criteria>
  <done>BC slice fully covered by vitest; sets the contract that 63-C and 63-D consume.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 63-B-04: Extend `codeGenerator.ts` with per-channel BC emit logic (5-mode switch + symmetric expansion + unset/Mark TODO) and add `codeGenerator.bc.test.ts`</name>
  <files>gui/src/lib/codeGenerator.ts, gui/src/lib/__tests__/codeGenerator.bc.test.ts</files>
  <read_first>
    - gui/src/lib/codeGenerator.ts (entire file — you MUST locate the Components emit loop end, the `eqs = [` block, the conditional `using DelimitedFiles` insertion, and the Power Shape per-kind switch at lines 794-877 before editing)
    - gui/src/lib/__tests__/codeGenerator.resources.test.ts (the test idiom for full-pipeline codegen assertions — `generate(state)` → assert substring presence; this is the model for `codeGenerator.bc.test.ts`)
    - gui/src/lib/__tests__/codeGenerator.smoke.test.ts (existing smoke that 63-B must not break)
    - gui/src/lib/bcMode.ts (post-Task-63-B-01) for the `BCModeEntry` discriminated union codegen switches on
    - .planning/phases/63-bcs-tab-value-source-components-in-gui/63-PATTERNS.md section "`gui/src/lib/codeGenerator.ts` (MODIFIED — 5-mode emit)" — has the exact emit shapes for each mode + the insertion-order table
    - .planning/phases/63-bcs-tab-value-source-components-in-gui/63-CONTEXT.md — D-06 (Profile-cosine emits `cosine_T_wall_profile`), D-07 (Profile-file uses `rebin_intensive`), D-08 (Function stub-and-edit), D-09 (unset = no equation + TODO comment), CD-01 (TODO text)
  </read_first>
  <action>

A. Extend `gui/src/lib/codeGenerator.ts`:

1. Import: `import type { BCModeEntry } from "@/lib/bcMode"; import { bcModeKey } from "@/lib/bcMode";` at top.

2. Locate the per-component emit loop (ends around line 941). After that loop, BEFORE the `eqs = [` block, insert a new "BC bindings" emit phase. For each consumer node in `state.nodes` whose registry entry has `external_inputs?.length > 0`:
   - Iterate `external_inputs`. For each entry, look up `state.bcMode[bcModeKey(node.id, externalInputName)]`.
   - If `state.bcSymmetric[\`${node.id}::${baseField}\`] === true` and the current entry is the `_right` sibling AND a `_left` entry already emitted, SKIP — the `_left` emission will write both sides via the `for` comprehension. (This is the codegen-side of D-05 symmetric expansion. Document inline with a comment.)
   - Switch on `entry?.mode`:

     - `entry === undefined` (required-unset, D-09):
       Emit ONLY a comment inside the eqs block at the right slot: `# TODO: set ${node.instanceName}.${externalInputName}[i] here` (no binding equation; per CD-01).

     - `entry.mode === "value"`:
       Inside `eqs`: emit `[${node.instanceName}.${externalInputName}[i] ~ ${entry.value} for i in 1:${n}]...`. If symmetric ON, ALSO emit the sibling line with `${siblingExternalInputName}`.

     - `entry.mode === "profile"` with `preset === "cosine"`:
       Emit a profile-var BEFORE `eqs`: `${node.instanceName}_${externalInputName}_profile = cosine_T_wall_profile(${n}; amplitude=${entry.amplitude}, peaking_factor=${entry.peakingFactor})`. Inside `eqs`: `[${node.instanceName}.${externalInputName}[i] ~ ${node.instanceName}_${externalInputName}_profile[i] for i in 1:${n}]...`. Symmetric expansion same shape.

     - `entry.mode === "profile"` with `preset === "file"`:
       Emit profile-var BEFORE `eqs`: `${node.instanceName}_${externalInputName}_profile = rebin_intensive(readdlm(joinpath(@__DIR__, ${JSON.stringify(entry.path)}), ','), ${n})`. Inside `eqs`: same binding equation as cosine case. Symmetric expansion same.
       Also: extend the `using DelimitedFiles` conditional so it fires if ANY consumer has a profile-file BC (in addition to existing Power Shape file_loaded triggers).

     - `entry.mode === "function"`:
       Emit a stub function BEFORE `eqs` (after profile-vars): `${entry.functionName}(${entry.signature === "fn(t, i)" ? "t, i" : "t"}) = 0.0  # TODO: define your time-varying boundary condition`. Inside `eqs`: `[${node.instanceName}.${externalInputName}[i] ~ ${entry.functionName}(${entry.signature === "fn(t, i)" ? "t, i" : "t"}) for i in 1:${n}]...`. Symmetric expansion: reuse the SAME function for both sides if symmetric ON; emit one stub.

     - `entry.mode === "mark"`:
       Inside `eqs`: emit only the TODO comment `# TODO: set ${node.instanceName}.${externalInputName}[i] here` (no binding equation; per CD-01). Same as the unset case from the codegen-output perspective — but the user's intent differs (they ACK'd `mark` explicitly vs leaving unset).

     - `entry.mode === "source"`:
       Inside `eqs`: emit the binding equation against the source node's array variable. Look up the source node by `entry.sourceNodeId` to get its instanceName. Source-block exposes its array as `${sourceNode.instanceName}.T_wall_out[i]` (for WallTemperature) or `${sourceNode.instanceName}.q_out[i]` (for HeatFluxSource). Read the source port name from the source-block's registry entry to avoid hardcoding (`getComponent(sourceComponentId).ports.find(p => p.type === "BCPort")?.name`). Emit: `[${node.instanceName}.${externalInputName}[i] ~ ${sourceNode.instanceName}.${sourcePortName}[i] for i in 1:${n}]...`. Symmetric expansion: same source for both sides.

3. For each consumer node with at least one BC binding, wrap the BC-binding equations in a clearly commented section inside `eqs` (one block per channel, mirroring the existing format in 63-PATTERNS shared-pattern):
   ```
   # BCs for ch_1:
   [ch_1.T_wall_left[i] ~ <expr> for i in 1:n]...,
   [ch_1.T_wall_right[i] ~ <expr> for i in 1:n]...,
   ```

4. Do NOT change the existing Power Shape emit logic, the existing `connect()` emit, or the Components emit. This is strictly additive.

B. Create `gui/src/lib/__tests__/codeGenerator.bc.test.ts` mirroring `codeGenerator.resources.test.ts`:

Test cases (one `describe("codeGenerator BC emit", ...)` block):
- `it("emits scalar binding for Value mode (D-06)")` — assert generated text contains `[ch_1.T_wall_left[i] ~ 320 for i in 1:10]...`
- `it("emits cosine_T_wall_profile call + binding for Profile-cosine mode (D-06, CD-02)")`
- `it("emits rebin_intensive call + binding for Profile-file mode (D-07)")`
- `it("includes 'using DelimitedFiles' import when any BC is Profile-file (D-07)")`
- `it("emits function stub + binding for Function mode fn(t) (D-08)")`
- `it("emits function stub + binding for Function mode fn(t, i) (D-08)")`
- `it("emits only a TODO comment (no equation) for Mark mode (D-09, CD-01)")`
- `it("emits only a TODO comment (no equation) when bcMode entry is absent (D-09 required-unset)")`
- `it("with symmetric ON, single Value entry produces BOTH left and right binding equations (D-05)")`
- `it("with symmetric OFF, only the side with an entry emits its binding")`
- `it("emits binding against source-node array variable for Source mode (D-23)")` — fixture: one WT node + one Channel node with `bcMode` = source-mode pointing at WT.
  </action>
  <verify>
    <automated>cd gui && npx vitest run src/lib/__tests__/codeGenerator.bc.test.ts src/lib/__tests__/codeGenerator.smoke.test.ts src/lib/__tests__/codeGenerator.resources.test.ts</automated>
  </verify>
  <acceptance_criteria>
    - `gui/src/lib/__tests__/codeGenerator.bc.test.ts` exists
    - `grep -c '^\s*it(' gui/src/lib/__tests__/codeGenerator.bc.test.ts` returns at least 11
    - `grep -E 'cosine_T_wall_profile' gui/src/lib/codeGenerator.ts` returns at least 1 line
    - `grep -E 'rebin_intensive' gui/src/lib/codeGenerator.ts` returns at least 1 line
    - `grep -E 'bcMode' gui/src/lib/codeGenerator.ts` returns at least 3 lines
    - `grep -E 'BC required|# TODO: set' gui/src/lib/codeGenerator.ts` returns at least 1 line (the unset/Mark TODO emission)
    - `cd gui && npx vitest run src/lib/__tests__/codeGenerator.bc.test.ts` exits 0
    - `cd gui && npx vitest run src/lib/__tests__/codeGenerator.smoke.test.ts` exits 0 (regression — pre-existing smoke must stay green)
    - `cd gui && npx vitest run src/lib/__tests__/codeGenerator.resources.test.ts` exits 0 (regression)
  </acceptance_criteria>
  <done>Codegen emits correct Julia text for all five BC modes plus symmetric expansion; pre-existing codegen tests unaffected.</done>
</task>

</tasks>

<verification>
After all four tasks:

1. `cd gui && npx vitest run src/store/__tests__/useStore.bc.test.ts src/lib/__tests__/codeGenerator.bc.test.ts` exits 0.
2. `cd gui && npm test` exits 0 (full suite — no regressions in pre-existing tests).
3. `cd gui && npx tsc --noEmit 2>&1 | grep -E 'useStore\.ts|codeGenerator\.ts|bcMode\.ts'` returns 0 lines (these specific files are clean — pre-existing 7 tsc errors in other files documented in `.planning/phases/61-.../deferred-items.md` may still appear elsewhere; Phase 71 owns that reconciliation).

Smoke-test scope per `feedback_smoke_test_scope_match.md`: 63-B is data-only. NO UI visibility claim. Plan does NOT promise that the BCs tab renders, the BCPort handle appears, or any visible artifact materializes — those are 63-C / 63-D deliverables. 63-B promises only: the store mutates correctly, the codegen produces the right Julia text, and existing tests stay green.
</verification>

<success_criteria>
- M2 (this plan only — partial): `cd gui && npx vitest run` on the two new test files exits 0.
- M4 (this plan only — partial: codegen part): All five BC modes emit correct Julia text (D-06..D-09 + CD-01 + CD-02).
- M5 (this plan only — partial: data-only part): Required-unset state is `bcMode[key] === undefined` AND codegen emits TODO comment + no equation for unset entries (D-09).
- M7 (this plan only — partial: data-only part): `enrichEdges` BCPort branch assigns `type: "bcEdge"` and initializes `data` shape (D-11 default `both`).
- M8 (this plan only — partial: store part): Setting BCs-tab mode to source creates edge in `edges[]`; deleting edge reverts bcMode (D-23 bidirectional sync — store layer).
- M9 (this plan only — partial: pure validator): `isAllowedBCConnection` enforces the type allow-list (D-21); pure, ready for 63-D's `isValidConnection` consumer.
- No new tsc errors introduced in the modified files (deferred ts errors documented in `.planning/phases/61-.../deferred-items.md` remain — Phase 71 owns).
</success_criteria>

<output>
After completion, create `.planning/phases/63-bcs-tab-value-source-components-in-gui/63-B-SUMMARY.md` per template, documenting:
- Exact shapes of `BCModeEntry`, `BCEdgeData`, store actions, error-tag string format (e.g., `"bc-n-mismatch"`) — these are the CONTRACT 63-C and 63-D consume.
- Insertion order of BC emit phases in `codeGenerator.ts` (where in the generated `.jl` BC profile-vars, function stubs, and binding equations appear).
- Confirmation that `cd gui && npm test` exits 0 with no regressions.
- The two new test files' coverage breakdown.
- Note for 63-D: the `errorNodeIds` shape is `Record<nodeId, string[]>` — read tags like `"bc-n-mismatch"` to drive red-ring rendering.
</output>
