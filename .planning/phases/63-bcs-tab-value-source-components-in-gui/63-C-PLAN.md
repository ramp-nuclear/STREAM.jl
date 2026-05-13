---
phase: 63
plan: C
type: execute
wave: 2
depends_on:
  - B
files_modified:
  - gui/src/components/sidebar/SegmentedButtonGroup.tsx
  - gui/src/components/sidebar/ModeToggle.tsx
  - gui/src/components/sidebar/BCModePicker.tsx
  - gui/src/components/sidebar/BCsTabForm.tsx
  - gui/src/components/sidebar/SidebarPanel.tsx
  - gui/src/components/sidebar/__tests__/BCModePicker.test.tsx
  - gui/src/components/sidebar/__tests__/BCsTabForm.test.tsx
  - gui/src/components/sidebar/__tests__/SidebarPanel.test.tsx
autonomous: true
requirements:
  - D-01
  - D-02
  - D-03
  - D-04
  - D-05
  - D-06
  - D-08
  - D-09
  - D-20
  - CD-05
user_setup: []

must_haves:
  truths:
    - "Selecting a component whose registry entry has `external_inputs.length > 0` shows a `[Properties] [BCs]` tab strip below the instance-name header (D-01, D-02)"
    - "Selecting a component without external_inputs (e.g., ChannelAndContacts, Pump) shows NO tab strip — single Properties view (D-02)"
    - "Switching the selected component resets active tab to Properties (D-03)"
    - "BCs tab body renders one 5-pill mode picker per field-group (paired by registry `pair_with`), with required-unset = no active pill + muted-destructive hint (D-04, D-09)"
    - "Symmetric L=R toggle (default ON) collapses paired fields into one editor block; toggle OFF expands to two stacked editor blocks (D-05, CD-05)"
    - "Source-mode dropdown lists existing WallTemperature/HeatFluxSource nodes filtered by `external_inputs[].source_component`; when empty, shows inline `+ New <SourceKind>` button that spawns + auto-selects + sets bcMode to source (D-20)"
    - "All BC mode mutations go through the 63-B store actions (`setBCMode`, `clearBCMode`, `setBCSymmetric`) — sidebar holds no local state for BC mode values"
  artifacts:
    - path: "gui/src/components/sidebar/SegmentedButtonGroup.tsx"
      provides: "Generic <T extends string> segmented-button primitive extracted from ModeToggle"
      contains: "export default function SegmentedButtonGroup"
    - path: "gui/src/components/sidebar/ModeToggle.tsx"
      provides: "Thin wrapper around SegmentedButtonGroup (pre-existing API preserved)"
      contains: "SegmentedButtonGroup"
    - path: "gui/src/components/sidebar/BCModePicker.tsx"
      provides: "5-pill picker for BCMode with required-unset visual"
      contains: "BC required"
    - path: "gui/src/components/sidebar/BCsTabForm.tsx"
      provides: "BCs-tab body: symmetric toggle + per-field BCModePicker + per-mode editor renderer"
      contains: "bcSymmetric"
    - path: "gui/src/components/sidebar/SidebarPanel.tsx"
      provides: "Tabs wrapper around the existing component branch when external_inputs.length > 0"
      contains: "TabsList"
    - path: "gui/src/components/sidebar/__tests__/BCModePicker.test.tsx"
      provides: "5-pill render + required-unset coverage"
      contains: "describe(\"BCModePicker"
    - path: "gui/src/components/sidebar/__tests__/BCsTabForm.test.tsx"
      provides: "Symmetric toggle + Source-mode `+ New` flow coverage"
      contains: "describe(\"BCsTabForm"
    - path: "gui/src/components/sidebar/__tests__/SidebarPanel.test.tsx"
      provides: "Tab-strip visibility + active-tab reset on selection change"
      contains: "external_inputs"
  key_links:
    - from: "gui/src/components/sidebar/BCsTabForm.tsx"
      to: "gui/src/store/useStore.ts"
      via: "useStore selectors + setBCMode/clearBCMode/setBCSymmetric calls"
      pattern: "useStore\\(.*bcMode|useStore\\(.*setBCMode"
    - from: "gui/src/components/sidebar/SidebarPanel.tsx"
      to: "gui/src/components/sidebar/BCsTabForm.tsx"
      via: "<TabsContent value=\"bcs\"><BCsTabForm /></TabsContent>"
      pattern: "BCsTabForm"
    - from: "gui/src/components/sidebar/BCModePicker.tsx"
      to: "gui/src/components/sidebar/SegmentedButtonGroup.tsx"
      via: "renders <SegmentedButtonGroup> with the 5 BC mode options"
      pattern: "SegmentedButtonGroup"
---

<objective>
Land the right-sidebar BCs-tab UI. Extract a generic `SegmentedButtonGroup<T>` primitive from the existing `ModeToggle.tsx`, build a `BCModePicker` (5-pill with required-unset), build a `BCsTabForm` (symmetric toggle + per-mode editors), and wrap the existing component branch of `SidebarPanel.tsx` in a `<Tabs>` strip conditional on `external_inputs.length > 0`. All state lives in the 63-B store (no local UI state for BC values).

Purpose: This plan delivers truths M3 (tab-strip visibility), M4 (5-pill picker), M5 (required-unset visual), and the BCs-tab side of M10 (`+ New <SourceKind>` inline button). M6 (Sources toolbox draggables) and M7/M8/M9 (canvas BC edge + drop + type-block) ship in 63-D.

Output: 8 files (3 new components, 1 new primitive, 1 modified existing primitive, 1 modified router, 3 new vitest files).
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
@.planning/phases/63-bcs-tab-value-source-components-in-gui/63-B-PLAN.md
@gui/src/components/sidebar/ModeToggle.tsx
@gui/src/components/sidebar/ParameterForm.tsx
@gui/src/components/sidebar/SidebarPanel.tsx
@gui/src/components/sidebar/NumericField.tsx
@gui/src/components/sidebar/ResourceCreationButton.tsx
@gui/src/components/sidebar/__tests__/ModeToggle.test.tsx
@gui/src/components/sidebar/__tests__/ParameterForm.test.tsx
@gui/src/components/sidebar/__tests__/SidebarPanel.test.tsx
@gui/src/registry/types.ts
@gui/src/registry/components.json

<interfaces>
<!-- Pre-existing analogs to mirror exactly. -->

From gui/src/components/sidebar/ModeToggle.tsx (Phase 22 — Pump fixed-dP / fixed-mdot picker):
```typescript
interface ModeToggleProps {
  modes: ConstructorMode[];   // from registry/types.ts
  activeMode: string;
  onChange: (mode: string) => void;
}
```

From gui/src/components/sidebar/SidebarPanel.tsx (Phase 62 — selection-kind router):
- Component branch is at lines 134-189 (the `selectionKind === "component"` branch).
- Outer `<div key={selectedNodeId}>` at line 151 forces a remount on selection change (D-03 reset-on-selection mechanism).
- Existing layout: InstanceNameField + Badge → Separator → ModeToggle (if multi-mode) → Separator → ParameterForm.

From gui/src/components/sidebar/ParameterForm.tsx:
- Props: `{component: ComponentDefinition, activeMode: string, values: Record<string, unknown>, onParamChange: (name, value) => void}`.
- Section + grouping pattern at lines 36-43 partitions params by type.
- Section heading + Separator pattern at lines 139-178 — copy verbatim.

From gui/src/registry/types.ts:
- `interface ComponentDefinition { external_inputs?: ReadonlyArray<ExternalInput>; ... }` (line 236).
- `interface ExternalInput { name: string; type: string; array_size?: string; pair_with?: string; bc_modes?: ReadonlyArray<...>; source_component?: string; ... }`.

From gui/src/store/useStore.ts (post-63-B):
  setBCMode(componentId, externalInputName, entry: BCModeEntry): void
  clearBCMode(componentId, externalInputName): void
  setBCSymmetric(nodeId, baseField, symmetric: boolean): void
  bcMode: Record<string, BCModeEntry>
  bcSymmetric: Record<string, boolean>
  // Read access via selectors: useStore(state => state.bcMode[bcModeKey(nodeId, name)])

From gui/src/lib/bcMode.ts (post-63-B):
  export type BCMode = "value" | "profile" | "function" | "mark" | "source";
  export type BCModeEntry = { mode: "value"; value: number } | ... (full discriminated union);
  export function bcModeKey(componentId: string, externalInputName: string): string;

From gui/src/components/sidebar/ResourceCreationButton.tsx (Phase 62 — the `+ New <ResourceKind>` inline-button + popover pattern):
- Anchored popover, click does NOT dismiss on outside-click (Phase 62 Pitfall 1).
- onConfirm: calls store action, returns new UUID, parent auto-selects.
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 63-C-01: Extract `SegmentedButtonGroup<T>` primitive; refactor `ModeToggle.tsx` to delegate to it; preserve `ModeToggle` API contract</name>
  <files>gui/src/components/sidebar/SegmentedButtonGroup.tsx, gui/src/components/sidebar/ModeToggle.tsx, gui/src/components/sidebar/__tests__/ModeToggle.test.tsx</files>
  <read_first>
    - gui/src/components/sidebar/ModeToggle.tsx lines 1-49 (the entire file — this is the source of the extraction)
    - gui/src/components/sidebar/__tests__/ModeToggle.test.tsx (pre-existing test contract — must continue to pass with zero edits to the test file unless the component visibly changes labels)
    - .planning/phases/63-bcs-tab-value-source-components-in-gui/63-PATTERNS.md section "`gui/src/components/sidebar/SegmentedButtonGroup.tsx` (NEW)" lines ~206-249 — the full primitive template
  </read_first>
  <action>
A. Create `gui/src/components/sidebar/SegmentedButtonGroup.tsx`:

```
interface SegmentedButtonGroupProps<T extends string> {
  options: Array<{ value: T; label: string }>;
  /** undefined = no active pill (required-unset, D-09). All buttons render as outline-variant. */
  active: T | undefined;
  onChange: (value: T) => void;
  size?: "sm" | "default";
  className?: string;
}
```

Body: copy verbatim from 63-PATTERNS.md "`gui/src/components/sidebar/SegmentedButtonGroup.tsx` (NEW)" section. Generic over `T extends string`. Uses shadcn `Button` from `@/components/ui/button`. Renders horizontal row with rounded-r-none / rounded-l-none / rounded-none class logic per index. `variant={opt.value === active ? "default" : "outline"}`.

B. Refactor `gui/src/components/sidebar/ModeToggle.tsx`:

Preserve the existing prop signature exactly (`ModeToggleProps { modes: ConstructorMode[]; activeMode: string; onChange: (mode: string) => void }`). The body becomes:
- Map `modes` to `options: Array<{value: string; label: string}>` via the existing `MODE_LABELS` lookup.
- Render `<Label>Mode</Label>` (preserved from existing file).
- Render `<SegmentedButtonGroup options={options} active={activeMode} onChange={onChange} size="sm" />`.

Net effect: `ModeToggle` becomes a ~15-line wrapper. No visible behavior change.

C. Do NOT edit `gui/src/components/sidebar/__tests__/ModeToggle.test.tsx` unless a test fails. Run it after the refactor to confirm.
  </action>
  <verify>
    <automated>cd gui && npx vitest run src/components/sidebar/__tests__/ModeToggle.test.tsx</automated>
  </verify>
  <acceptance_criteria>
    - `gui/src/components/sidebar/SegmentedButtonGroup.tsx` exists
    - `grep -c '^export default function SegmentedButtonGroup' gui/src/components/sidebar/SegmentedButtonGroup.tsx` returns 1
    - `grep -c '<T extends string>' gui/src/components/sidebar/SegmentedButtonGroup.tsx` returns at least 1
    - `gui/src/components/sidebar/ModeToggle.tsx` imports `SegmentedButtonGroup`: `grep -E 'import .* from "./SegmentedButtonGroup"' gui/src/components/sidebar/ModeToggle.tsx` returns 1 line
    - `cd gui && npx vitest run src/components/sidebar/__tests__/ModeToggle.test.tsx` exits 0 (the existing 3 tests continue to pass — proves the wrapper preserves contract)
    - `cd gui && npx tsc --noEmit 2>&1 | grep -E '(SegmentedButtonGroup|ModeToggle)\.tsx'` returns 0 lines
  </acceptance_criteria>
  <done>Generic primitive extracted; existing `ModeToggle` consumers (Pump) work identically.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 63-C-02: Create `BCModePicker.tsx` (5-pill with required-unset) and `BCModePicker.test.tsx`</name>
  <files>gui/src/components/sidebar/BCModePicker.tsx, gui/src/components/sidebar/__tests__/BCModePicker.test.tsx</files>
  <read_first>
    - gui/src/components/sidebar/SegmentedButtonGroup.tsx (post-Task-63-C-01)
    - gui/src/components/sidebar/__tests__/ModeToggle.test.tsx (the vitest template)
    - gui/src/lib/bcMode.ts (post-63-B-01) — for the `BCMode` type
    - .planning/phases/63-bcs-tab-value-source-components-in-gui/63-PATTERNS.md section "`gui/src/components/sidebar/BCModePicker.tsx` (NEW — 5-pill segmented control)" — exact adaptation guidance + label dictionary
    - .planning/phases/63-bcs-tab-value-source-components-in-gui/63-CONTEXT.md — D-04 (order: Value Profile Function Mark Source), D-09 (required-unset visual + muted-destructive hint text "BC required — select a mode")
  </read_first>
  <action>
A. Create `gui/src/components/sidebar/BCModePicker.tsx`:

Imports: `Label` from `@/components/ui/label`, `SegmentedButtonGroup` from `./SegmentedButtonGroup`, `type BCMode` from `@/lib/bcMode`.

Props:
```
interface BCModePickerProps {
  label: string;                          // e.g., "T_wall_left[1:n]" or "T_wall"
  active: BCMode | undefined;             // undefined = required-unset
  onChange: (mode: BCMode) => void;
}
```

Body:
- Constant `BC_MODE_OPTIONS: Array<{value: BCMode; label: string}> = [{value:"value",label:"Value"}, {value:"profile",label:"Profile"}, {value:"function",label:"Function"}, {value:"mark",label:"Mark"}, {value:"source",label:"Source"}]` (D-04 order).
- Render:
  - `<Label className="text-[13px] font-semibold leading-[1.4]">{label}</Label>`
  - `<SegmentedButtonGroup options={BC_MODE_OPTIONS} active={active} onChange={onChange} size="sm" />`
  - When `active === undefined`: render `<p className="text-xs text-destructive/80 mt-[6px]">BC required — select a mode</p>` (the muted-destructive hint per D-09).

The "all buttons render outline when `active === undefined`" behavior is inherited for free from `SegmentedButtonGroup`'s `variant={opt.value === active ? "default" : "outline"}`.

B. Create `gui/src/components/sidebar/__tests__/BCModePicker.test.tsx`:

Header:
```
// @vitest-environment happy-dom
import { describe, it, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import BCModePicker from "../BCModePicker";
```

Tests:
- `it("renders all 5 mode pills in D-04 order")` — assert texts "Value", "Profile", "Function", "Mark", "Source" present.
- `it("renders no active pill when active === undefined (D-09 required-unset)")` — render with `active={undefined}`; assert NONE of the 5 buttons have the active highlight class (use `screen.getAllByRole('button')` + check `class` lacks `bg-primary` or whatever the default-variant class is — match against the actual classnames `SegmentedButtonGroup` produces).
- `it("renders the required-unset hint when active === undefined (D-09)")` — assert `screen.getByText(/BC required/i)` exists.
- `it("does NOT render the hint when active is set")` — render with `active="value"`; assert `screen.queryByText(/BC required/i)` returns null.
- `it("highlights the active pill when active is set")` — render with `active="profile"`; assert the "Profile" button has the active variant class.
- `it("calls onChange with the new mode when an inactive pill is clicked")` — use `fireEvent.click` or `userEvent.click`; assert `onChange` called once with the correct mode string.
- `it("renders the label prop")` — assert `screen.getByText("T_wall_left[1:n]")` exists when label is provided.

All assertions use `@testing-library/react` per the existing `ModeToggle.test.tsx` idiom.
  </action>
  <verify>
    <automated>cd gui && npx vitest run src/components/sidebar/__tests__/BCModePicker.test.tsx</automated>
  </verify>
  <acceptance_criteria>
    - `gui/src/components/sidebar/BCModePicker.tsx` exists
    - `grep -c '^export default function BCModePicker' gui/src/components/sidebar/BCModePicker.tsx` returns 1
    - `grep -c 'BC_MODE_OPTIONS' gui/src/components/sidebar/BCModePicker.tsx` returns at least 1
    - `grep -E '"Value".*"Profile".*"Function".*"Mark".*"Source"' gui/src/components/sidebar/BCModePicker.tsx` returns 0 lines (NOT on one line — the array spans multiple lines; just verify all 5 labels present:) `grep -cE '"(Value|Profile|Function|Mark|Source)"' gui/src/components/sidebar/BCModePicker.tsx` returns at least 5
    - `grep -E 'BC required' gui/src/components/sidebar/BCModePicker.tsx` returns 1 line
    - `gui/src/components/sidebar/__tests__/BCModePicker.test.tsx` exists with at least 7 `it(...)` blocks: `grep -c '^\s*it(' gui/src/components/sidebar/__tests__/BCModePicker.test.tsx` returns at least 7
    - `cd gui && npx vitest run src/components/sidebar/__tests__/BCModePicker.test.tsx` exits 0
  </acceptance_criteria>
  <done>5-pill BC mode picker renders, supports required-unset visual, fully covered.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 63-C-03: Create `BCsTabForm.tsx` (symmetric toggle + per-field BCModePicker + 5 per-mode editor branches with `+ New <SourceKind>` inline button) and its test file</name>
  <files>gui/src/components/sidebar/BCsTabForm.tsx, gui/src/components/sidebar/__tests__/BCsTabForm.test.tsx</files>
  <read_first>
    - gui/src/components/sidebar/ParameterForm.tsx (entire file — replicate the section + Separator + heading pattern from lines 139-178)
    - gui/src/components/sidebar/NumericField.tsx (Value-mode editor reuses this verbatim)
    - gui/src/components/sidebar/ResourceCreationButton.tsx (the `+ New <ResourceKind>` inline-button pattern; mirror for `+ New WallTemperature`)
    - gui/src/components/ui/switch.tsx (the symmetric toggle uses shadcn Switch)
    - gui/src/components/ui/select.tsx (the Source-mode dropdown uses shadcn Select)
    - gui/src/lib/bcMode.ts (`BCMode`, `BCModeEntry`, `bcModeKey`)
    - gui/src/store/useStore.ts (post-63-B — `setBCMode`, `clearBCMode`, `setBCSymmetric`, `bcMode`, `bcSymmetric`)
    - gui/src/registry/types.ts (`ExternalInput.pair_with`, `source_component`)
    - .planning/phases/63-bcs-tab-value-source-components-in-gui/63-PATTERNS.md section "`gui/src/components/sidebar/BCsTabForm.tsx` (NEW)" lines ~74-141
    - .planning/phases/63-bcs-tab-value-source-components-in-gui/63-CONTEXT.md — D-05 (symmetric toggle ON default, expansion behavior), D-08 (Function-mode editor minimal — signature picker + name field), D-19 (source block label for Source-mode dropdown), D-20 (`+ New` inline button when no sources exist), CD-05 (symmetric persisted per-component-instance)
    - .planning/phases/63-bcs-tab-value-source-components-in-gui/63-B-PLAN.md (the contract that 63-C consumes — confirm `setBCMode` action signature)
  </read_first>
  <action>
A. Create `gui/src/components/sidebar/BCsTabForm.tsx`:

Imports include: React, `useStore`, `Switch`, `Label`, `Separator`, `Select` (+ `SelectContent`, `SelectItem`, `SelectTrigger`, `SelectValue`), `Button`, `NumericField`, `BCModePicker`, `SegmentedButtonGroup`, types from `@/lib/bcMode` and `@/registry/types`.

Props:
```
interface BCsTabFormProps {
  component: ComponentDefinition;    // selected component's registry entry
  nodeId: string;                    // selected node id (from store)
}
```

Body structure (mirror ParameterForm sections layout):

1. Read from store via selectors:
   - `bcMode = useStore(state => state.bcMode)`
   - `bcSymmetric = useStore(state => state.bcSymmetric)`
   - `nodes = useStore(state => state.nodes)`
   - actions: `setBCMode`, `clearBCMode`, `setBCSymmetric`, `addNode` (for the `+ New` flow).

2. Group `component.external_inputs ?? []` by `pair_with`:
   - For each input, if `pair_with` is set and the sibling exists in the same array, they form a pair. Use the alphabetically-earlier name as the "primary" (e.g., `T_wall_left` is the primary of the `(T_wall_left, T_wall_right)` pair). Derive `baseField` by stripping the trailing `_left`/`_right` from the primary's name (e.g., `T_wall_left` → `T_wall`).
   - Inputs without `pair_with` render as singletons.

3. For each pair group:
   - Render `<h3 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground leading-[1.3] mb-[8px]">{baseField}</h3>` (e.g., "T_wall").
   - Render a `<div className="flex items-center gap-[8px] mb-[8px]">` containing `<Label htmlFor={...}>Symmetric (L = R)</Label>` + `<Switch checked={isSymmetric} onCheckedChange={(v) => setBCSymmetric(nodeId, baseField, v)} />`. Default isSymmetric = `bcSymmetric[\`${nodeId}::${baseField}\`] ?? true` (CD-05: per-instance, default ON).
   - If symmetric ON: render ONE `<BCModePicker label={baseField} active={bcMode[bcModeKey(nodeId, primaryName)]?.mode} onChange={(mode) => handleModeChange(primaryName, mode)} />` + the active mode's editor below. `handleModeChange` calls `setBCMode(nodeId, primaryName, defaultEntryFor(mode))` (see step 5 for `defaultEntryFor`).
   - If symmetric OFF: render TWO stacked groups, one for each sibling — each with its own `BCModePicker` + editor, separated by `<Separator />`. Heading per sibling = the sibling's full name (e.g., `T_wall_left[1:n]`).

4. For singleton inputs (no `pair_with`): render `<BCModePicker>` + editor directly, no symmetric toggle.

5. Per-mode editor renderer (helper function `renderModeEditor(entry, onUpdate, ctx)`):
   - `entry?.mode === undefined`: render nothing below the picker (required-unset hint is already in `BCModePicker`).
   - `mode === "value"`: render `<NumericField value={entry.value} onChange={(v) => onUpdate({mode:"value", value:v})} label="Value" />`. `defaultEntryFor("value")` returns `{mode:"value", value:0}`.
   - `mode === "profile"`: render a sub-`SegmentedButtonGroup` of options `[{value:"cosine",label:"Cosine"},{value:"file",label:"File"}]` for preset selection. If `preset === "cosine"`: render two `NumericField`s for `amplitude` and `peakingFactor`. If `preset === "file"`: render a Label + read-only TextInput showing `entry.path` + a `<Button>Choose file…</Button>` (the actual file picker uses tauri/dialog plugin — Phase 63 emits the path string; user can also edit inline). `defaultEntryFor("profile")` returns `{mode:"profile", preset:"cosine", amplitude:1.0, peakingFactor:1.0}`.
   - `mode === "function"`: render `<SegmentedButtonGroup options={[{value:"fn(t)",label:"fn(t)"},{value:"fn(t, i)",label:"fn(t, i)"}]} active={entry.signature} onChange={(s) => onUpdate({...entry, signature: s})} />` + a single-line text input for `functionName` (default = `${component.id}_${externalInputName}_fn` per D-08). `defaultEntryFor("function")` returns `{mode:"function", signature:"fn(t)", functionName: <auto-generated>}`.
   - `mode === "mark"`: render `<p className="text-xs text-muted-foreground">Marked in code — set ${component.id}.${externalInputName}[i] manually in generated .jl.</p>` (no editor body per D-08 spec for Mark).
   - `mode === "source"`:
     - Filter `nodes` for those whose registry `componentId === externalInputMeta.source_component` (e.g., `"WallTemperature"` for `T_wall_*`).
     - If `filteredNodes.length > 0`: render `<Select value={entry.sourceNodeId} onValueChange={(id) => onUpdate({mode:"source", sourceNodeId: id})}>` with `<SelectItem>` per source node (label = node instanceName).
     - If `filteredNodes.length === 0`: render an inline button `<Button variant="outline" size="sm" onClick={handleNewSource}>+ New {sourceComponentLabel}</Button>` where `handleNewSource`:
        * calls `addNode(sourceComponentId, {x: <consumer.x - 120>, y: consumer.y})` (sourceComponentId resolved from external input's `source_component` field; consumer position read from `nodes.find(n => n.id === nodeId).position`).
        * gets the new node's id from the addNode return value (or read latest node from store).
        * calls `setBCMode(nodeId, externalInputName, {mode:"source", sourceNodeId: newId})`.
     - `defaultEntryFor("source")` returns `{mode:"source", sourceNodeId: ""}` if no sources; else first available source's id.

6. Critical: ALL state mutations go through 63-B store actions. The form holds NO local state for BC entries — every keystroke calls `setBCMode` with the new partial entry.

7. ASCII-only variable names per project memory `feedback_ascii_variable_names.md`.

B. Create `gui/src/components/sidebar/__tests__/BCsTabForm.test.tsx`:

Fixture: a `Channel` registry-aligned `ComponentDefinition` with `external_inputs: [{name:"T_wall_left", pair_with:"T_wall_right", source_component:"WallTemperature"}, {name:"T_wall_right", pair_with:"T_wall_left", source_component:"WallTemperature"}]`. Seed `useStore.setState({nodes: [{id:"ch1", data: {componentId:"Channel", parameters:{n:10}}, position:{x:200,y:100}}], bcMode: {}, bcSymmetric: {}})` in `beforeEach`.

Tests:
- `it("renders one symmetric toggle + one BCModePicker group for a paired field set (default symmetric ON) (D-05)")` — assert `screen.getByText("Symmetric (L = R)")` + single BCModePicker (one "Value" button visible).
- `it("expands to two stacked BCModePicker groups when symmetric toggle is OFF (D-05)")` — toggle Switch via `userEvent.click`; assert two "Value" buttons present, one for `T_wall_left[1:n]`, one for `T_wall_right[1:n]`.
- `it("calls setBCMode on the primary field when mode is changed in symmetric-ON mode (D-04, D-05)")` — click "Value" pill → assert store's `bcMode["ch1::T_wall_left"]` exists with `mode:"value"`; AND if symmetric ON, the 63-B store also mirrored to `"ch1::T_wall_right"`.
- `it("renders NumericField below the picker when mode is Value")` — set initial `bcMode["ch1::T_wall_left"] = {mode:"value", value: 320}`; assert input with value 320 exists.
- `it("renders cosine NumericFields when mode is Profile + preset=cosine (D-06)")` — set initial entry; assert two number inputs for amplitude + peakingFactor.
- `it("renders signature picker + function name input when mode is Function (D-08)")` — assert "fn(t)" / "fn(t, i)" buttons + a text input.
- `it("renders 'Marked in code' hint and NO editor body when mode is Mark (D-08)")`.
- `it("Source mode with NO existing source nodes shows '+ New WallTemperature' inline button (D-20)")` — assert button text matches `/\+ New WallTemperature/`.
- `it("Source mode with existing source nodes shows a Select dropdown listing them (D-20)")` — seed `nodes` with a WT node; assert `screen.getByRole('combobox')` or appropriate select query reflects the WT node.
- `it("clicking '+ New WallTemperature' calls addNode and setBCMode (D-20)")` — mock or use real store; assert post-click, `useStore.getState().nodes.length === 2` (consumer + new WT) AND `useStore.getState().bcMode["ch1::T_wall_left"]?.mode === "source"`.
  </action>
  <verify>
    <automated>cd gui && npx vitest run src/components/sidebar/__tests__/BCsTabForm.test.tsx</automated>
  </verify>
  <acceptance_criteria>
    - `gui/src/components/sidebar/BCsTabForm.tsx` exists
    - `grep -c '^export default function BCsTabForm' gui/src/components/sidebar/BCsTabForm.tsx` returns 1
    - `grep -E 'setBCSymmetric|bcSymmetric' gui/src/components/sidebar/BCsTabForm.tsx` returns at least 2 lines
    - `grep -E 'setBCMode|clearBCMode' gui/src/components/sidebar/BCsTabForm.tsx` returns at least 2 lines
    - `grep -E '\+ New' gui/src/components/sidebar/BCsTabForm.tsx` returns 1 line
    - `grep -E 'addNode' gui/src/components/sidebar/BCsTabForm.tsx` returns at least 1 line
    - `grep -E 'pair_with' gui/src/components/sidebar/BCsTabForm.tsx` returns at least 1 line (grouping logic)
    - `gui/src/components/sidebar/__tests__/BCsTabForm.test.tsx` exists with at least 10 `it(...)` blocks: `grep -c '^\s*it(' gui/src/components/sidebar/__tests__/BCsTabForm.test.tsx` returns at least 10
    - `cd gui && npx vitest run src/components/sidebar/__tests__/BCsTabForm.test.tsx` exits 0
    - `cd gui && npx tsc --noEmit 2>&1 | grep -E 'BCsTabForm\.tsx'` returns 0 lines
  </acceptance_criteria>
  <done>BCs-tab body renders correctly for all 5 modes, symmetric toggle works, `+ New <SourceKind>` flow spawns + sets bcMode.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 63-C-04: Wrap the component branch of `SidebarPanel.tsx` in `<Tabs>` conditional on `external_inputs.length > 0`; create `SidebarPanel.test.tsx`</name>
  <files>gui/src/components/sidebar/SidebarPanel.tsx, gui/src/components/sidebar/__tests__/SidebarPanel.test.tsx</files>
  <read_first>
    - gui/src/components/sidebar/SidebarPanel.tsx (entire file — focus on lines 134-189, the component branch; understand the `<div key={selectedNodeId}>` remount discipline at line 151)
    - gui/src/components/ui/tabs.tsx (the shadcn Tabs primitive — confirm available subcomponents `Tabs`, `TabsList`, `TabsTrigger`, `TabsContent`)
    - gui/src/components/sidebar/__tests__/ParameterForm.test.tsx (a vitest test that renders a sidebar form with a registry-aligned fixture — the idiom for `SidebarPanel.test.tsx`)
    - gui/src/components/sidebar/__tests__/SidebarRouter.test.tsx (selection-kind router test idiom from Phase 62)
    - .planning/phases/63-bcs-tab-value-source-components-in-gui/63-PATTERNS.md section "`gui/src/components/sidebar/SidebarPanel.tsx` (MODIFIED)" lines ~382-415 — exact wrap strategy
    - .planning/phases/63-bcs-tab-value-source-components-in-gui/63-CONTEXT.md — D-01 (tab strip BELOW header), D-02 (visibility rule), D-03 (active tab resets to Properties on selection change)
  </read_first>
  <action>
A. Edit `gui/src/components/sidebar/SidebarPanel.tsx`:

1. Add imports:
   - `import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";`
   - `import BCsTabForm from "./BCsTabForm";`
   - `import { useState } from "react";` if not already imported.

2. Inside the component branch (currently around lines 150-188), AFTER the InstanceNameField + Badge + Separator block (which stays at the top — D-01 requires the tab strip BELOW the header) and BEFORE the existing ModeToggle + ParameterForm block:

   Pseudocode:
   ```
   const hasBCs = (component.external_inputs?.length ?? 0) > 0;
   const [activeTab, setActiveTab] = useState<"properties" | "bcs">("properties");
   ```

   When `hasBCs`:
   - Wrap the existing `ModeToggle (if multi-mode) + Separator + ParameterForm` in `<Tabs value={activeTab} onValueChange={(v) => setActiveTab(v as "properties" | "bcs")}>`.
   - Above the wrapped content, render `<TabsList className="mb-[16px]"><TabsTrigger value="properties">Properties</TabsTrigger><TabsTrigger value="bcs">BCs</TabsTrigger></TabsList>`.
   - `<TabsContent value="properties">` wraps the existing ModeToggle + ParameterForm subtree.
   - `<TabsContent value="bcs"><BCsTabForm component={component} nodeId={selectedNodeId} /></TabsContent>`.

   When NOT `hasBCs` (`external_inputs.length === 0` or undefined — includes CAC, Pump, etc.): render the existing layout unchanged (no Tabs wrapper, no BCs tab — D-02 hard rule).

3. The outer `<div key={selectedNodeId}>` at line 151 ALREADY provides D-03 reset behavior: when `selectedNodeId` changes, the entire subtree (including `<Tabs>` and its local `useState`) remounts, defaulting `activeTab` back to `"properties"`. Do NOT add any other reset mechanism.

B. Create `gui/src/components/sidebar/__tests__/SidebarPanel.test.tsx`:

Fixtures: minimal registry-aligned `ComponentDefinition`s — one Channel (`external_inputs.length === 2`) and one Pump (`external_inputs.length === 0` or undefined). Seed via `useStore.setState({nodes: [...], selectedNodeId: ...})` in `beforeEach`.

Tests:
- `it("renders the Properties/BCs tab strip when selected component has external_inputs (D-01, D-02)")` — selected Channel; assert `screen.getByRole('tab', {name: /Properties/i})` and `screen.getByRole('tab', {name: /BCs/i})` both exist.
- `it("does NOT render the tab strip when selected component has no external_inputs (D-02)")` — selected Pump; assert `screen.queryByRole('tab', {name: /BCs/i})` returns null.
- `it("active tab resets to Properties on selection change (D-03)")` — start with Channel selected + manually set activeTab to "bcs" (click BCs tab → assert content switched) → change `selectedNodeId` in store to a different Channel node → re-render → assert Properties content is active (BCs content not visible).
- `it("renders the InstanceNameField + Badge header ABOVE the tab strip (D-01)")` — query order: header element comes before tab strip in DOM order.
- `it("clicking the BCs tab renders the BCsTabForm body")` — click "BCs" tab → assert content includes BCsTabForm-specific text (e.g., "Symmetric (L = R)").
  </action>
  <verify>
    <automated>cd gui && npx vitest run src/components/sidebar/__tests__/SidebarPanel.test.tsx src/components/sidebar/__tests__/SidebarRouter.test.tsx</automated>
  </verify>
  <acceptance_criteria>
    - `grep -E 'import .* from "@/components/ui/tabs"' gui/src/components/sidebar/SidebarPanel.tsx` returns 1 line
    - `grep -E 'import .* from "./BCsTabForm"' gui/src/components/sidebar/SidebarPanel.tsx` returns 1 line
    - `grep -E 'external_inputs' gui/src/components/sidebar/SidebarPanel.tsx` returns at least 1 line (the conditional)
    - `grep -E 'TabsList|TabsTrigger|TabsContent' gui/src/components/sidebar/SidebarPanel.tsx` returns at least 4 lines
    - `grep -E '<BCsTabForm' gui/src/components/sidebar/SidebarPanel.tsx` returns 1 line
    - `gui/src/components/sidebar/__tests__/SidebarPanel.test.tsx` exists with at least 5 `it(...)` blocks: `grep -c '^\s*it(' gui/src/components/sidebar/__tests__/SidebarPanel.test.tsx` returns at least 5
    - `cd gui && npx vitest run src/components/sidebar/__tests__/SidebarPanel.test.tsx src/components/sidebar/__tests__/SidebarRouter.test.tsx` exits 0
    - `cd gui && npx vitest run src/components/sidebar/__tests__/ParameterForm.test.tsx` exits 0 (regression — Pump-style components still work)
    - `cd gui && npx tsc --noEmit 2>&1 | grep -E 'SidebarPanel\.tsx'` returns 0 lines
  </acceptance_criteria>
  <done>Tab strip renders conditionally; selection change resets to Properties; BCs tab shows BCsTabForm body.</done>
</task>

</tasks>

<verification>
After all four tasks:

1. `cd gui && npx vitest run src/components/sidebar/` exits 0 — all sidebar tests (pre-existing + new) pass.
2. `cd gui && npm test` exits 0 — full suite green.
3. `cd gui && npx tsc --noEmit 2>&1 | grep -E '(BCModePicker|BCsTabForm|SidebarPanel|SegmentedButtonGroup|ModeToggle)\.tsx'` returns 0 lines.

Smoke-test scope per `feedback_smoke_test_scope_match.md`: this plan ONLY touches sidebar files. It does NOT claim canvas behavior, edge rendering, or drag-and-drop activation — those are 63-D. Visual confirmation that the tab strip looks right and the `+ New` flow opens the popover smoothly is a Phase-72 design-pass concern, NOT a Phase-63 gate.

Manual smoke (Phase-63-end gate, not per-task):
- `cd gui && npm run tauri dev` → drop a Channel → see `[Properties] [BCs]` tab strip → click BCs → see `T_wall` symmetric toggle + 5-pill picker with required-unset hint.
- Drop a Pump → see Properties only (no tab strip).
- Switch from Channel to Pump and back → BCs tab content does not persist (D-03 reset).
</verification>

<success_criteria>
- M3 satisfied: Tab strip rendered conditionally per `external_inputs.length > 0` (D-01, D-02); active tab resets on selection change (D-03).
- M4 satisfied (UI part): 5-pill mode picker renders in D-04 order with active-pill highlighting.
- M5 satisfied (UI part): Brand-new Channel BC fields show no active pill + muted-destructive `BC required — select a mode` hint (D-09).
- M10 satisfied (sidebar part): `+ New WallTemperature` / `+ New HeatFluxSource` inline button visible when Source-mode dropdown is empty; click spawns new source-block at consumer.x - 120, auto-selects, calls setBCMode (D-20).
- Symmetric (L=R) toggle works per CD-05: per-instance default ON, toggle OFF expands to two stacked editor groups (D-05).
- No regressions in pre-existing sidebar tests (ModeToggle, ParameterForm, SidebarRouter, ResourceReferencePicker, etc.).
</success_criteria>

<output>
After completion, create `.planning/phases/63-bcs-tab-value-source-components-in-gui/63-C-SUMMARY.md` per template, documenting:
- The `SegmentedButtonGroup<T>` extraction (preserved `ModeToggle` API for Pump).
- BCModePicker file size + test count.
- BCsTabForm structure overview (grouping by `pair_with`, per-mode editor renderer dispatch table).
- SidebarPanel surgery: Tabs wrapper inserted between header and content; activeTab local state resets on remount.
- Note for 63-D: nothing here writes to `errorNodeIds`. 63-D's StreamNode renderer should read `errorNodeIds` from the store to drive red-ring; the BCs tab is informational only at the field level for now.
- Note: the `+ New <SourceKind>` flow in `BCsTabForm` uses `useStore.getState().addNode(...)` and reads back the latest node. If 63-D's StreamNode side-effects shift, revisit.
</output>
