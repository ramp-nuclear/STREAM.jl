---
phase: 63
plan: C
subsystem: gui-ui
tags: [bcs-tab, sidebar, tabs, segmented-button, mode-picker, value-source]
dependency_graph:
  requires:
    - Phase 63-B store contract (bcMode / bcSymmetric slices + setBCMode / setBCSymmetric / clearBCMode actions; BCMode / BCModeEntry / bcModeKey from gui/src/lib/bcMode.ts)
    - Phase 62 SidebarPanel selection-kind router (D-05/D-06) and remount-on-selection discipline (the `<div key={selectedNodeId}>` line preserved verbatim, used as the D-03 reset-on-selection mechanism)
    - Phase 22 ModeToggle (refactored into a thin wrapper around the new primitive)
  provides:
    - SegmentedButtonGroup<T> generic primitive (consumed by ModeToggle, BCModePicker, BCsTabForm sub-pickers, and future segmented controls)
    - BCModePicker (5-pill picker with D-09 required-unset visual baked in)
    - BCsTabForm (BCs-tab body: symmetric toggle + per-field picker + 5 per-mode editor branches + `+ New <SourceKind>` flow)
    - Tabs wrapper inside SidebarPanel.tsx component branch (conditional on external_inputs.length > 0)
  affects:
    - 63-D will read errorTagsByNodeId from the store for red-ring on BC errors; BCs tab does not write that slice (only the store's _checkBCNMismatch does)
tech_stack:
  added: []
  patterns:
    - "Generic segmented-button primitive over T extends string (single shared row layout for ModeToggle, BCModePicker, Profile-preset picker, Function-signature picker)"
    - "Required-unset-via-absence: active === undefined → no highlight (free from the variant equality check in SegmentedButtonGroup) + muted-destructive hint in BCModePicker"
    - "Tab-strip remount-on-selection: outer <div key={selectedNodeId}> already in SidebarPanel was reused as the D-03 reset mechanism (no per-mount listener needed)"
    - "Diff-after-addNode for new-node-id recovery (addNode is void-returning per useStore.ts:188)"
    - "Symmetric mirror handled inside the store action (setBCMode mirrors to sibling key when bcSymmetric[symKey] ?? true) — UI only writes to the primary field"
key_files:
  created:
    - gui/src/components/sidebar/SegmentedButtonGroup.tsx
    - gui/src/components/sidebar/BCModePicker.tsx
    - gui/src/components/sidebar/BCsTabForm.tsx
    - gui/src/components/sidebar/__tests__/BCModePicker.test.tsx
    - gui/src/components/sidebar/__tests__/BCsTabForm.test.tsx
  modified:
    - gui/src/components/sidebar/ModeToggle.tsx
    - gui/src/components/sidebar/SidebarPanel.tsx
    - gui/src/components/sidebar/__tests__/SidebarPanel.test.tsx
decisions:
  - "ASCII-only variable names — per project memory feedback_ascii_variable_names.md."
  - "No shadcn Switch primitive exists in gui/src/components/ui — implemented SymmetricToggle inline as a role='switch' button with aria-checked. The visual idiom is a 36x20 pill with a sliding knob; this avoids adding a new ui/ primitive and Radix dependency for one consumer site."
  - "addNode returns void (useStore.ts:188) — the `+ New <SourceKind>` handler reads back the freshly-added node by diffing pre/post node-id sets. Documented inline; this avoids touching the 63-B store contract."
  - "n-seed on new source-block happens BEFORE setBCMode dispatches. setBCMode materializes the BC edge AND fires _checkBCNMismatch; seeding n first means a brand-new Channel(n=12) → WallTemperature(n=12) pair cannot trip the soft-warning on first creation (D-20 explicit)."
  - "Registry does NOT declare pair_with on external_inputs (only on thermal ports per Phase 61 schema). 63-B SUMMARY confirmed the pairing convention is the _left/_right suffix; BCsTabForm replicates that via a local stripSideSuffix helper."
metrics:
  duration: 17m
  completed: 2026-05-13
---

# Phase 63 Plan C: BCs-tab UI Summary

Right-sidebar BCs-tab UI delivery: generic `SegmentedButtonGroup<T>` primitive extracted, 5-pill `BCModePicker` with D-09 required-unset visual, `BCsTabForm` with symmetric toggle + per-mode editor dispatch + `+ New <SourceKind>` flow, and a Tabs wrapper inside `SidebarPanel.tsx` gated on `external_inputs.length > 0`. 4 tasks, 4 commits, 23 new tests across 3 files, 0 regressions in the 91-test sidebar suite.

## What shipped

### gui/src/components/sidebar/SegmentedButtonGroup.tsx (NEW — 49 lines)

Generic over `T extends string`. Same row layout previously inlined in `ModeToggle.tsx` (rounded-r-none / rounded-l-none / rounded-none by index). The crucial line — `variant={opt.value === active ? "default" : "outline"}` — means `active === undefined` leaves EVERY pill in outline variant, delivering the D-09 required-unset visual for the BCs tab without a special branch.

Three consumers in 63-C:

1. `ModeToggle.tsx` (Pump fixed-dP / fixed-mdot picker) — pre-existing.
2. `BCModePicker.tsx` — Value/Profile/Function/Mark/Source.
3. `BCsTabForm.tsx` Profile-preset sub-picker (Cosine / File) and Function-signature sub-picker (fn(t) / fn(t, i)).

### gui/src/components/sidebar/ModeToggle.tsx (MODIFIED — ~30 lines)

Refactored into a thin wrapper that maps `ConstructorMode[]` to an options array via the existing `MODE_LABELS` lookup and delegates to `<SegmentedButtonGroup>`. External API preserved exactly — the single Pump call site in `SidebarPanel.tsx` continues to work unchanged. Existing `ModeToggle.test.tsx` (1 passing + 2 todo) still passes with zero test edits, proving contract preservation.

### gui/src/components/sidebar/BCModePicker.tsx (NEW — 56 lines)

5-pill picker in D-04 order (Value Profile Function Mark Source) with the required-unset hint `BC required — select a mode` (D-09 muted-destructive) shown ONLY when `active === undefined`. Props are `{label, active, onChange}` — fully stateless; all writes bubble to the parent via the `onChange(mode)` callback.

### gui/src/components/sidebar/__tests__/BCModePicker.test.tsx (NEW — 7 tests)

D-04 order assertion (textContent of all 5 buttons in exact order), D-09 required-unset (no `bg-primary` class on any button when active is undefined, hint visible), opposite cases (hint hidden when active is set, active pill highlighted), `onChange` dispatch on click, and label prop propagation.

### gui/src/components/sidebar/BCsTabForm.tsx (NEW — ~480 lines)

BCs-tab body. Structure:

1. **Pair grouping** — partition `component.external_inputs` by stripping the `_left`/`_right` suffix. Pairs render with the Symmetric (L = R) toggle; singletons render directly.
2. **GroupBlock** — per-group rendering: heading `T_wall` (base field), inline `SymmetricToggle` (when paired), then either ONE `FieldRow` (symmetric ON or singleton) or TWO stacked `FieldRow`s separated by a Separator (symmetric OFF).
3. **FieldRow** — `<BCModePicker>` on top, `<ModeEditorBody>` below, dispatching on the entry's `mode` discriminator into one of five sub-editors.
4. **ModeEditorBody dispatch table**:
   - `value` → `ValueModeEditor` (single NumericField).
   - `profile` → `ProfileModeEditor` (preset sub-picker Cosine/File; cosine renders amplitude + peakingFactor NumericFields; file renders a CSV path Input + disabled "Choose file..." button).
   - `function` → `FunctionModeEditor` (fn(t) / fn(t, i) sub-picker + functionName Input).
   - `mark` → muted "Marked in code — set <comp>.<field>[i] manually in generated .jl" hint, no editor.
   - `source` → `SourceModeEditor`. When zero existing nodes match `external_inputs[i].source_component`, renders inline `+ New <SourceKind>` button (D-20). Otherwise renders a Radix `Select` listing the matching nodes by `instanceName`.

5. **`+ New <SourceKind>` flow** (D-20 critical detail):

   ```
   handleNewSource():
     consumerN = consumerNode.data.parameters.n ?? 1
     beforeIds = new Set(nodes.map(n => n.id))
     addNode(sourceComponentId, {x: consumer.x - 120, y: consumer.y})
     newNode = nodes.find(n => !beforeIds.has(n.id))   // diff-discovery (addNode is void)
     updateNodeParams(newNode.id, {parameters: {n: consumerN}})  // SEED n FIRST
     setBCMode(nodeId, fieldName, {mode: "source", sourceNodeId: newNode.id})
   ```

   Seeding `n` BEFORE `setBCMode` matters: `setBCMode` materializes the BC edge AND fires `_checkBCNMismatch`. Without the seed, the brand-new pair `Channel(n=12)` → `WallTemperature(n=1)` (registry default) would immediately raise the `bc-n-mismatch` soft warning. The test "+ New WallTemperature seeds the new WT's n from the consumer" gates this explicitly.

6. **Symmetric mirror** — UI writes to the primary field only. The store's `setBCMode` checks `bcSymmetric[symKey] ?? true` and mirrors to the sibling key internally (useStore.ts:1133-1135). UI never duplicates the write.

### gui/src/components/sidebar/__tests__/BCsTabForm.test.tsx (NEW — 11 tests)

D-04 (mode order), D-05 (symmetric toggle: single picker when ON, two stacked groups when OFF), D-08 (function-mode signature picker + name input; mark-mode hint), D-09 (no required-unset hint shown for set entries — covered transitively), D-20 (Source mode empty → `+ New WallTemperature`; populated → `<Select>`; click `+ New` flow updates both `nodes` and `bcMode`), and the explicit n-default-from-consumer gate (Channel n=12 → spawned WT.parameters.n === 12).

### gui/src/components/sidebar/SidebarPanel.tsx (MODIFIED)

The `selectionKind === "component"` branch now conditionally renders a `<Tabs>` strip when `component.external_inputs?.length ?? 0 > 0`:

- **Header (above strip):** unchanged — `InstanceNameField + Badge`, followed by the existing `<Separator className="my-[24px]" />`. Position preserved (D-01 — strip below header).
- **When hasBCs:** new private `<ComponentTabs>` component holds the `useState<"properties" | "bcs">("properties")`. The two TabsContent panels are (1) the original `ModeToggle (if multi-mode) + ParameterForm` subtree and (2) `<BCsTabForm component={component} nodeId={selectedNodeId} />`.
- **When NOT hasBCs:** the pre-Phase-63 layout is preserved exactly — no Tabs wrapper, no BCs tab. Pump, ChannelAndContacts, HeatDiffusion, and the value-sources themselves take this path.
- **D-03 reset:** delivered for FREE by the outer `<div key={selectedNodeId}>` (preserved verbatim from Phase 62). When the selected node changes, the entire subtree remounts, defaulting `activeTab` back to `"properties"`. No per-mount selectNode listener needed.

### gui/src/components/sidebar/__tests__/SidebarPanel.test.tsx (REPLACED — 4 it.todo → 5 real tests)

Replaced the Phase-22 placeholder. New tests:

- **D-01, D-02:** Channel selection → both Properties and BCs tabs render.
- **D-02 negative:** Pump selection (no external_inputs) → `BCs` tab is absent.
- **D-03:** Switching from Channel-A (with BCs tab manually activated) to Channel-B remounts the subtree and resets to Properties (verified by `data-state="active"` on Properties tab).
- **D-01 ordering:** InstanceNameField input appears before the BCs tab in document order (compareDocumentPosition mask).
- **Smoke click:** mouseDown + click on the BCs tab (Radix Tabs activates on mouseDown — AppShell.test.tsx idiom) renders the `Symmetric (L = R)` BCsTabForm artefact.

## Test counts

| File                                   | New `it(...)` blocks |
| -------------------------------------- | -------------------- |
| `__tests__/BCModePicker.test.tsx`      | 7                    |
| `__tests__/BCsTabForm.test.tsx`        | 11                   |
| `__tests__/SidebarPanel.test.tsx`      | 5                    |
| **Total new**                          | **23**               |

Full sidebar suite after 63-C: **91 passing, 9 todo, 0 failing** (vs. 68 passing / 9 todo prior; ~23 new tests added).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] BCsTabForm.tsx tsc errors: `n.data as StreamNodeData` lacks `as unknown` middle step**

- **Found during:** Task 63-C-03 (post-write `tsc --noEmit` check).
- **Issue:** ReactFlow's `Node.data` is typed `Record<string, unknown>`; casting directly to `StreamNodeData` triggers `TS2352: Conversion of type may be a mistake because neither type sufficiently overlaps`. The existing store code uses the `as unknown as StreamNodeData` two-step (e.g., useStore.ts:1369-1370).
- **Fix:** Updated all 5 cast sites in `BCsTabForm.tsx` to `as unknown as StreamNodeData` matching the existing convention.
- **Files modified:** `gui/src/components/sidebar/BCsTabForm.tsx`.
- **Commit:** `ce0287b`.

**2. [Rule 1 - Bug] BCsTabForm.tsx tsc error: `group.sibling` possibly undefined inside arrow-function callbacks**

- **Found during:** Task 63-C-03 (post-write `tsc --noEmit` check).
- **Issue:** TypeScript's flow-narrowing does not propagate the outer `group.sibling &&` truthy check into the JSX children's nested arrow callbacks (`(m) => modeChangeFor(group.sibling.name, m)`). Errors TS18048 fired on lines 316-317.
- **Fix:** Hoisted `group.sibling` into a local const `sib` inside an IIFE under the `&&` guard, then passed `sib` everywhere. This is a known TS narrowing limitation; the IIFE is the standard workaround.
- **Files modified:** `gui/src/components/sidebar/BCsTabForm.tsx`.
- **Commit:** `ce0287b`.

**3. [Rule 1 - Bug] BCsTabForm test "renders NumericField below the picker when mode is Value" used `getByText("Value")` which matches both the pill text AND the NumericField label**

- **Found during:** Task 63-C-03 (first vitest run).
- **Issue:** When mode is Value, "Value" appears twice in the DOM (the BCModePicker pill + the NumericField's Label). `screen.getByText("Value")` is non-unique → throws.
- **Fix:** Asserted `getAllByText("Value").length >= 1` and continued to verify the numeric Input value separately.
- **Files modified:** `gui/src/components/sidebar/__tests__/BCsTabForm.test.tsx`.
- **Commit:** `ce0287b`.

**4. [Rule 1 - Bug] SidebarPanel.test.tsx Radix Tabs activates on mouseDown, not click**

- **Found during:** Task 63-C-04 (first vitest run; 2 tests failed).
- **Issue:** Plain `fireEvent.click` on a Radix `<TabsTrigger>` does not toggle the underlying `data-state` in happy-dom — Radix's pointer-down activation never fires. Pre-existing `AppShell.test.tsx:86-97` documents the workaround.
- **Fix:** Use `fireEvent.mouseDown` followed by `fireEvent.click` to drive both the Radix activation listener AND any post-click handlers.
- **Files modified:** `gui/src/components/sidebar/__tests__/SidebarPanel.test.tsx`.
- **Commit:** `08ddb82`.

## Contract for 63-D consumption

63-D does not import any artefact from 63-C. Their work shares:

- `errorTagsByNodeId` slice — 63-D's `StreamNode.tsx` should read `errorTagsByNodeId[id]` to drive red-ring rendering. 63-C does NOT write to that slice (the store's `_checkBCNMismatch` is the only writer; fired from inside `setBCMode` / `addEdge`).
- `bcMode` / `bcSymmetric` slices — read-only for 63-D's purposes; only `cycleBCEdgeTargetSide` (action invoked from 63-D's BCEdge mid-edge chip) writes new state, and that store action already exists in 63-B.

## Note for future visual polish

`feedback_smoke_test_scope_match.md` — this plan ONLY touched sidebar files. It does NOT claim canvas behavior, BC edge rendering, or drag-and-drop activation — those land in 63-D. Visual polish of the tab strip and `+ New <SourceKind>` button styling is Phase-72 design-pass scope, NOT a Phase-63 gate.

## Verification

- `cd gui && npx vitest run src/components/sidebar/__tests__/ModeToggle.test.tsx` → 1 pass + 2 todo (regression: contract preserved).
- `cd gui && npx vitest run src/components/sidebar/__tests__/BCModePicker.test.tsx` → 7 pass.
- `cd gui && npx vitest run src/components/sidebar/__tests__/BCsTabForm.test.tsx` → 11 pass.
- `cd gui && npx vitest run src/components/sidebar/__tests__/SidebarPanel.test.tsx` → 5 pass.
- `cd gui && npx vitest run src/components/sidebar/` (full sidebar suite) → 91 pass, 9 todo, 0 fail.
- `cd gui && npx tsc --noEmit 2>&1 | grep -E '(BCModePicker|BCsTabForm|SidebarPanel|SegmentedButtonGroup|ModeToggle)\.tsx'` → 0 lines (no tsc errors in any plan file).
- Pre-existing `SidebarRouter.test.tsx` and `ParameterForm.test.tsx` both continue green (no regression).

## Self-Check: PASSED

Files created:
- `gui/src/components/sidebar/SegmentedButtonGroup.tsx` — FOUND
- `gui/src/components/sidebar/BCModePicker.tsx` — FOUND
- `gui/src/components/sidebar/BCsTabForm.tsx` — FOUND
- `gui/src/components/sidebar/__tests__/BCModePicker.test.tsx` — FOUND
- `gui/src/components/sidebar/__tests__/BCsTabForm.test.tsx` — FOUND

Files modified:
- `gui/src/components/sidebar/ModeToggle.tsx` — FOUND
- `gui/src/components/sidebar/SidebarPanel.tsx` — FOUND
- `gui/src/components/sidebar/__tests__/SidebarPanel.test.tsx` — FOUND

Commits:
- `1baf71f` refactor(63-C): extract SegmentedButtonGroup<T> primitive from ModeToggle — FOUND
- `283ea68` feat(63-C): add BCModePicker (5-pill picker with required-unset hint) — FOUND
- `ce0287b` feat(63-C): add BCsTabForm (BCs-tab body with 5-mode editors + symmetric toggle) — FOUND
- `08ddb82` feat(63-C): wrap component branch in Tabs + add SidebarPanel.test.tsx — FOUND
