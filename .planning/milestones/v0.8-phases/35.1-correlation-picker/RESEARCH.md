# Research: Phase 35.1 Correlation Picker

**Researched:** 2026-04-02
**Domain:** React/TypeScript sidebar UI — factory correlation sub-field rendering
**Confidence:** HIGH (all findings from direct code inspection; no external library research needed)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Every field label gets a small circled-i icon to the right. Hovering shows a shadcn Tooltip with `param.description` text. Applied to ALL sidebar field types: NumericField, FunctionSelect, PipeGeometryPicker sub-fields, and new factory sub-fields.
- **D-02:** No secondary text below labels. Tooltip-on-label-hover rejected. Icon-next-to-label is the chosen pattern.
- **D-03:** Sub-fields render inline below the parent dropdown, indented with a left border accent (`border-l-2 pl-3` or equivalent). No expand/collapse animation.
- **D-04:** Sub-fields use the same components as regular fields: `FunctionSelect` for Function-type sub-params, `NumericField` for Real sub-params. On-blur validation applies.
- **D-05:** Switching away from a factory discards sub-param values. Switching between two factories also discards previous sub-param values.
- **D-06:** Simple closures stored as plain strings: `parameters["htc_correlation"] = "dittus_boelter"`.
- **D-07:** Factory selections stored as `FactoryCorrelationValue` objects.
- **D-08:** Export `FactoryCorrelationValue` interface from `registry/types.ts`:
  ```ts
  export interface FactoryCorrelationValue {
    kind: "factory";
    value: string;
    subParams: Record<string, unknown>;
  }
  ```
- **D-09:** Add `sub_parameters?: Parameter[]` to `FunctionOption` in `types.ts`. Update `components.json` factory entries.
- **D-10:** Factory sub-parameter definitions to add:
  - `regime_dependent`: `htc_forced` (Function, simple HTC only), `htc_natural` (Function, simple HTC only), `threshold` (Real, default=1.0)
  - `elenbaas_htc`: `b` (Real, m), `L` (Real, m), `Dh` (Real, m), `g` (Real, default=9.80665)
  - `maximal_htc`: `htc1` (Function, simple HTC only), `htc2` (Function, simple HTC only)
- **D-11:** Sub-dropdowns only list simple closures — enforced by registry options array containing only `kind: "simple"` entries.
- **D-12:** `dittus_boelter`, `constant_Nusselt` (HTC) and `blasius_friction`, `laminar_friction` (friction) remain simple.
- **D-13:** `marco_han_nusselt` is NOT in STREAM.jl exports — do not add to picker.

### Claude's Discretion

- Exact Tailwind classes for the indented sub-field container
- Whether the circled-i icon uses a lucide-react icon or shadcn's built-in
- Default value pre-population for factory sub-fields (use registry `default` if present, otherwise leave empty/blank)

### Deferred Ideas (OUT OF SCOPE)

- `constant_Nusselt` sub-param (Nu): always defaults to 8.235; defer Nu input
- friction_correlation factory correlations: none exist in STREAM.jl v0.7
- Recursive factory-in-factory: capped at one level
</user_constraints>

---

## Current State Analysis

### FunctionSelect.tsx — Factory Branch

**File:** `gui/src/components/sidebar/FunctionSelect.tsx` (74 lines)

The entire rendering logic is a single `options.map()` that branches on `option.kind`:

```
// Lines 44-67
{options.map((option) =>
  option.kind === "factory" ? (
    <Tooltip key={option.value}>
      <TooltipTrigger asChild>
        <div>
          <SelectItem value={option.value} disabled className="text-muted-foreground">
            {option.label}
          </SelectItem>
        </div>
      </TooltipTrigger>
      <TooltipContent side="right">
        Factory correlation editing coming in a future update
      </TooltipContent>
    </Tooltip>
  ) : (
    <SelectItem key={option.value} value={option.value}>
      {option.label}
    </SelectItem>
  )
)}
```

The `disabled` attribute on `<SelectItem>` and the tooltip around it are the two things to remove/replace.

**What changes in Phase 35.1:**

1. Remove `disabled` from `<SelectItem>` for factory options — they become selectable.
2. Remove the "Factory correlation editing coming in a future update" tooltip.
3. After the entire `<Select>` block (outside `<SelectContent>`), add a conditional sub-field container: when the current value matches a factory option, render its `sub_parameters`.

The `onChange` prop signature changes behavior: when a factory is selected, call `onChange` with a `FactoryCorrelationValue` object instead of a plain string. This requires changing `FunctionSelectProps.onChange` from `(value: string) => void` to `(value: string | FactoryCorrelationValue) => void`, or keeping it narrow and having `FunctionSelect` call the parent with the structured type via a separate callback.

**Current `onChange` call site in ParameterForm.tsx (line 81):**
```ts
onChange={(v) => onParamChange(param.name, v)}
```
`onParamChange` already accepts `unknown` as the value, so widening the type here is clean.

**Sub-field rendering location:** The sub-field block goes OUTSIDE the `<TooltipProvider>` / `<Select>` tree, as a sibling `<div>` in the outer `<div className="flex flex-col gap-[8px]">`. This keeps Select's controlled value management separate from sub-field state.

**State needed inside FunctionSelect:** When a factory is selected, FunctionSelect needs to hold sub-param values locally until committed upward. The sub-param values are part of the `FactoryCorrelationValue.subParams` object that gets passed to `onChange`. Each sub-field's `onChange` triggers a new `FactoryCorrelationValue` with updated `subParams`, which propagates up via `onParamChange`.

**Initializing sub-params from existing store value:** When `value` prop is a `FactoryCorrelationValue`, FunctionSelect must detect it via `value.kind === "factory"` and render sub-fields pre-populated with `value.subParams`.

---

### Registry — components.json

**Current htc_correlation options (no sub_parameters field today):**
```json
"options": [
  { "value": "dittus_boelter", "label": "Dittus-Boelter", "kind": "simple" },
  { "value": "constant_Nusselt", "label": "Constant Nusselt", "kind": "simple" },
  { "value": "regime_dependent", "label": "Regime Dependent", "kind": "factory" },
  { "value": "elenbaas_htc", "label": "Elenbaas", "kind": "factory" },
  { "value": "maximal_htc", "label": "Maximal HTC", "kind": "factory" }
]
```

Factory options have `"kind": "factory"` already — that field EXISTS in the current schema. What is missing is `sub_parameters`.

**Changes needed to components.json:**

Add `sub_parameters` array to the three factory entries. This same change must be applied to ALL THREE components that have `htc_correlation`: `Channel`, `ChannelAndContacts`, and `ChannelHeatFlux`. Each has an identical options array.

Example for `regime_dependent`:
```json
{
  "value": "regime_dependent",
  "label": "Regime Dependent",
  "kind": "factory",
  "sub_parameters": [
    {
      "name": "htc_forced",
      "type": "Function",
      "description": "HTC closure for forced convection regime",
      "required": true,
      "positional": false,
      "options": [
        { "value": "dittus_boelter", "label": "Dittus-Boelter", "kind": "simple" },
        { "value": "constant_Nusselt", "label": "Constant Nusselt", "kind": "simple" }
      ]
    },
    {
      "name": "htc_natural",
      "type": "Function",
      "description": "HTC closure for natural convection regime",
      "required": true,
      "positional": false,
      "options": [
        { "value": "dittus_boelter", "label": "Dittus-Boelter", "kind": "simple" },
        { "value": "constant_Nusselt", "label": "Constant Nusselt", "kind": "simple" }
      ]
    },
    {
      "name": "threshold",
      "type": "Real",
      "unit": "—",
      "default": 1.0,
      "description": "Gr/Re² threshold for NC detection",
      "required": false,
      "positional": false
    }
  ]
}
```

Note: `elenbaas_htc` sub-params include a `Dh` field with the same name as the parent Channel's `Dh` — this is fine because sub-params are namespaced under the parent option's `subParams` map in the store, not the component's top-level `parameters`.

**Repetition concern:** The same `sub_parameters` block for all three factory options must appear in all three Channel-family components (Channel, ChannelAndContacts, ChannelHeatFlux). That is 3 components × 3 factories = 9 sub_parameters blocks to add. They are all identical — copy-paste in the JSON. No DRY mechanism exists in the registry schema; this is acceptable for now.

---

### ParameterForm.tsx — Rendering Loop

**File:** `gui/src/components/sidebar/ParameterForm.tsx` (123 lines)

The rendering flow:
1. Filter visible params by active constructor mode (lines 24-31)
2. Group by type: scalar, geometry, function, matrix (lines 33-42)
3. Each group becomes a section with a heading (lines 94-106)
4. `renderField(param)` dispatches on `param.type` (lines 43-92)

For `Function` type (lines 79-86), `renderField` renders `<FunctionSelect>` with:
```ts
onChange={(v) => onParamChange(param.name, v)}
```

**Does ParameterForm need changes?** Minimal. The `onParamChange(name, value)` callback already accepts `unknown` for value (see `ParameterFormProps.onParamChange: (name: string, value: unknown) => void`). Passing a `FactoryCorrelationValue` object works without type changes at the ParameterForm level.

**The sub-field rendering happens entirely inside FunctionSelect**, not in ParameterForm. ParameterForm does not need to know about factory sub-fields — it calls `onParamChange(param.name, factoryValue)` and FunctionSelect handles the internal sub-field state.

**The `onChange` type in FunctionSelectProps** needs widening from `(value: string) => void` to `(value: string | FactoryCorrelationValue) => void`. The call in ParameterForm's `renderField` passes `v` directly to `onParamChange`, which accepts `unknown`, so ParameterForm itself does not need type changes.

---

### NumericField / Info Icon Pattern

**File:** `gui/src/components/sidebar/NumericField.tsx` (58 lines)

**Current label (lines 33-35):**
```tsx
<Label className="text-[13px] font-semibold leading-[1.4]">
  {param.name}
</Label>
```

**Required change:** Add inline Info icon + Tooltip after the label text:
```tsx
<Label className="text-[13px] font-semibold leading-[1.4] flex items-center gap-1">
  {param.name}
  {param.description && (
    <TooltipProvider>
      <Tooltip>
        <TooltipTrigger asChild>
          <Info className="h-3 w-3 text-muted-foreground cursor-default" />
        </TooltipTrigger>
        <TooltipContent>{param.description}</TooltipContent>
      </Tooltip>
    </TooltipProvider>
  )}
</Label>
```

**Imports needed in NumericField.tsx:**
- `import { Info } from "lucide-react"` — already in dependencies (`"lucide-react": "^1.7.0"`)
- `import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip"` — already imported in FunctionSelect.tsx so shadcn tooltip is available

**No structural changes** to NumericField logic (validation, blur handling, unit display). Only the label JSX changes.

**Same pattern applies to FunctionSelect label (lines 35-37):**
```tsx
<Label className="text-[13px] font-semibold leading-[1.4]">
  {param.name}
</Label>
```
Needs the same inline icon treatment.

---

### Store — updateNodeParams

**File:** `gui/src/store/useStore.ts` (lines 82-105)

```ts
updateNodeParams: (nodeId, patch) => {
  const { nodes } = get();
  set({
    nodes: nodes.map((n) => {
      if (n.id !== nodeId) return n;
      const data = n.data as unknown as StreamNodeData;
      return {
        ...n,
        data: {
          ...data,
          ...(patch.parameters !== undefined && {
            parameters: { ...data.parameters, ...patch.parameters },
          }),
        },
      };
    }),
  });
},
```

`parameters` is `Record<string, unknown>`. The merge is shallow: `{ ...data.parameters, ...patch.parameters }`.

**Compatibility with FactoryCorrelationValue:** When `onParamChange("htc_correlation", factoryValue)` is called in SidebarPanel:
```ts
updateNodeParams(selectedNodeId, { parameters: { htc_correlation: factoryValue } })
```
This becomes `{ ...data.parameters, htc_correlation: factoryValue }` — a `FactoryCorrelationValue` object stored under the `htc_correlation` key. Works as-is. No store changes needed.

**D-05 enforcement (discard sub-params on factory switch):** When a user switches from `regime_dependent` to `elenbaas_htc`, `FunctionSelect.onChange` emits a new `FactoryCorrelationValue` with `value: "elenbaas_htc"` and `subParams: {}` (empty, populated as user fills fields). This replaces the previous factory value entirely. The store's shallow merge (`{ ...data.parameters, htc_correlation: newFactoryValue }`) overwrites the previous value — correct behavior.

**D-06 enforcement (simple stays string):** When a user switches to `dittus_boelter`, `FunctionSelect.onChange` emits the plain string `"dittus_boelter"`. Store receives `{ htc_correlation: "dittus_boelter" }` — a string, overwriting any previous `FactoryCorrelationValue`. Correct.

---

### TypeScript Safety

**File:** `gui/src/registry/types.ts` (49 lines)

**Current `FunctionOption` interface (lines 11-15):**
```ts
export interface FunctionOption {
  value: string;
  label: string;
  kind: "simple" | "factory";
}
```

**Required addition per D-09:**
```ts
export interface FunctionOption {
  value: string;
  label: string;
  kind: "simple" | "factory";
  sub_parameters?: Parameter[];
}
```

**Required new interface per D-08:**
```ts
export interface FactoryCorrelationValue {
  kind: "factory";
  value: string;
  subParams: Record<string, unknown>;
}
```

**Risk areas — places that assume `parameters[key]` is a string:**

1. **FunctionSelect.tsx line 31:**
   ```ts
   const currentValue = String(value ?? param.default ?? "");
   ```
   When `value` is a `FactoryCorrelationValue`, `String({ kind: "factory", ... })` produces `"[object Object]"`. This will break the `<Select value={currentValue}>` controlled value.
   
   Fix: detect object values and extract `.value` field:
   ```ts
   const currentValue = typeof value === "object" && value !== null && "kind" in value
     ? (value as FactoryCorrelationValue).value
     : String(value ?? param.default ?? "");
   ```

2. **Phase 36 code generation** (not yet built): must check `typeof parameters[key] === "string"` vs `parameters[key].kind === "factory"`. No current code affected since Phase 36 is not started.

3. **`addNode` in useStore.ts (lines 59-66):** Sets default parameter values from registry `param.default`. Function params have `default: "dittus_boelter"` (a string), so they initialize as strings — correct. No change needed.

4. **ParameterForm `renderField`:** Passes `value={values[param.name]}` directly to components. `FunctionSelect` receives `unknown`, which is the current signature. The `FunctionSelect` component is responsible for handling both string and `FactoryCorrelationValue`. Safe.

5. **Test files:** `ParameterForm.test.tsx` uses a mock without Function-type params. Tests for FunctionSelect (none currently) will need to be written for Phase 35.1.

---

### PipeGeometryPicker + InstanceNameField

**PipeGeometryPicker.tsx** (196 lines):

The `DimensionField` internal component (lines 39-66) has its own label:
```tsx
<Label className="text-[13px] font-semibold leading-[1.4]">
  {label}
</Label>
```
The `label` prop is a plain string (`"L"`, `"D"`, `"W"`, `"H"`). There is no `description` associated with these sub-fields — they are geometry dimension labels, not registry `Parameter` objects.

**Decision:** D-01 says ⓘ icons on ALL sidebar field types. For PipeGeometryPicker, descriptions for L/D/W/H would need to be added to `DimensionField`. The simplest approach: add an optional `description?: string` prop to `DimensionField` and the static field definitions. The circularFields/rectangularFields arrays (lines 149-157) become:
```ts
const circularFields = [
  { label: "L", key: "L", description: "Channel length" },
  { label: "D", key: "D", description: "Inner diameter" },
];
```

The outer `PipeGeometryPicker` component has no label of its own — it is rendered inside the "Geometry" section of ParameterForm. The section heading serves as context. No outer-level ⓘ icon needed on the picker itself.

**InstanceNameField.tsx** (41 lines):

The component has NO label element at all — it renders a bare `<Input>` with `className="text-base font-semibold"`. The instance name is shown directly in the input as the "title" of the node.

Per D-01, ⓘ icon is for field LABELS. Since InstanceNameField has no label, adding ⓘ here is ambiguous. The name field has no `description` property — it's not a registry `Parameter`.

**Decision:** InstanceNameField likely needs a label added ("Instance Name" or "Name") with the ⓘ tooltip. Or, if the input-as-title pattern is intentional, skip the ⓘ here. This is a minor judgment call in implementation. A reasonable approach: add a `<Label>` with text "Name" above the input, and a tooltip with "Julia variable name for this component instance". No registry `param` needed — hardcode the description.

---

## Implementation Approach

Recommended order (each step builds on the previous, no circular dependencies):

### Step 1: Extend TypeScript types (`registry/types.ts`)
- Add `sub_parameters?: Parameter[]` to `FunctionOption`
- Add `FactoryCorrelationValue` interface
- No component changes yet; TypeScript will flag downstream callers immediately

### Step 2: Extend `components.json` registry
- Add `sub_parameters` to all factory-kind options in Channel, ChannelAndContacts, ChannelHeatFlux
- Three factory options × three components = 9 additions
- Sub-option arrays for Function sub-params: only simple closures (dittus_boelter, constant_Nusselt)
- Validate JSON parses without errors

### Step 3: Upgrade `FunctionSelect.tsx` — core factory logic
- Fix `currentValue` derivation to handle `FactoryCorrelationValue` input
- Remove `disabled` from factory `<SelectItem>` entries
- Remove factory tooltip "coming in a future update"
- Change `onChange` type from `string` to `string | FactoryCorrelationValue`
- Add sub-field container below `<Select>`: conditional on selected option having `sub_parameters`
- Sub-field container renders `NumericField` or `FunctionSelect` per sub-param type
- Sub-field `onChange` calls parent's `onChange` with updated `FactoryCorrelationValue`
- When switching to simple: emit plain string
- When switching to factory: emit `{ kind: "factory", value, subParams: {} }` initially, then `subParams` fill in

### Step 4: Add ⓘ icon to `NumericField.tsx`
- Import `Info` from `lucide-react`, Tooltip components from shadcn
- Wrap label text + Info icon in `flex items-center gap-1`
- Guard with `param.description &&` so empty descriptions don't show stale icon

### Step 5: Add ⓘ icon to `FunctionSelect.tsx` label
- Same pattern as NumericField
- FunctionSelect already imports Tooltip/TooltipProvider — reuse

### Step 6: Add ⓘ icon to `PipeGeometryPicker.tsx`
- Add `description?: string` to `DimensionField` props
- Add descriptions to `circularFields`/`rectangularFields` arrays
- Apply the same icon pattern in `DimensionField` label

### Step 7: Add label + ⓘ icon to `InstanceNameField.tsx`
- Add `<Label>` "Name" above the input
- Add tooltip with hardcoded description string

### Step 8: Update tests
- Add FunctionSelect tests covering: simple selection, factory selection (sub-fields appear), factory-to-simple switch (sub-fields disappear), FactoryCorrelationValue emitted correctly
- Update ParameterForm tests to include Function-type params
- No store changes needed — no store tests to update

---

## Risk Areas

### 1. Controlled Select value when store holds FactoryCorrelationValue

The `<Select value={currentValue}>` expects a string matching one of the `<SelectItem value>` strings. If `currentValue` is derived from `String(value)` and `value` is a `FactoryCorrelationValue` object, it produces `"[object Object]"` which matches nothing — the Select shows blank or the placeholder.

**Mitigation:** Fix `currentValue` derivation in Step 3 as described above. Test this path explicitly.

### 2. Sub-field FunctionSelect recursion guard

Sub-dropdowns receive a `param` with `options` that only include `kind: "simple"` entries (enforced by registry). But FunctionSelect currently still checks `option.kind === "factory"` in its rendering loop. Sub-dropdown factory entries (there are none by design) would still render as disabled — which is the safe fallback. No code changes needed to prevent recursion beyond the registry constraint, but it is worth confirming the sub-FunctionSelect never receives options with `kind: "factory"`.

### 3. ParameterForm `onChange` type widening

`ParameterForm.onParamChange` is typed as `(name: string, value: unknown) => void` — this is already wide enough. `FunctionSelectProps.onChange` needs widening from `(value: string)` to `(value: string | FactoryCorrelationValue)`. The call in `renderField`:
```ts
onChange={(v) => onParamChange(param.name, v)}
```
TypeScript will accept this since `onParamChange` accepts `unknown`. No cascading type errors expected.

### 4. Default value initialization for factory sub-params

When a factory is first selected, `subParams` starts as `{}`. Sub-fields with `param.default` defined (e.g., `threshold: 1.0`, `g: 9.80665`) should be pre-populated. The `NumericField` component already reads `param.default` as its initial `localValue` via `String(value ?? param.default ?? "")`. Since sub-field `value` will be `undefined` initially (subParams is empty), it will fall through to `param.default` correctly — no special initialization needed for NumericField.

For sub-FunctionSelect, the same applies: `currentValue = String(value ?? param.default ?? "")`. Function sub-params have no `default` in the proposed registry schema — they are required with no default. User must select explicitly. This means sub-dropdowns for htc_forced/htc_natural initially show blank/placeholder until the user picks. This is acceptable but worth noting in the plan — consider setting `default: "dittus_boelter"` on the Function sub-params to give a reasonable starting value.

### 5. Three-component repetition in components.json

`Channel`, `ChannelAndContacts`, and `ChannelHeatFlux` all share the same `htc_correlation` options structure. The sub_parameters blocks will be duplicated 3x for each factory (9 total). If the sub-param definitions change in the future, all three must be updated. This is a known maintenance cost with no DRY fix available at the registry JSON level. The plan should note this explicitly so the implementer doesn't write just one and miss the other two.

### 6. InstanceNameField has no description metadata

The ⓘ icon pattern requires a `description` string. `InstanceNameField` doesn't receive a `Parameter` object — it only gets `value: string` and `onChange`. Any description text for the instance name field must be hardcoded in the component. This is a one-off that doesn't follow the registry-driven pattern. Keep it simple: hardcode `"Julia variable name for this component in generated code"`.

### 7. Test coverage gap

There are currently NO tests for `FunctionSelect.tsx` (no `FunctionSelect.test.tsx` in `__tests__/`). Phase 35.1 introduces significant new logic in this component. The plan must include a task to write FunctionSelect tests. The existing `ParameterForm.test.tsx` has `it.todo("renders FunctionSelect for Function-type params")` — this also needs filling in.

---

## Sources

All findings are from direct inspection of the current codebase. No external documentation was needed — this is a pure code analysis phase.

- `gui/src/components/sidebar/FunctionSelect.tsx` — factory disabled branch (lines 44-67)
- `gui/src/components/sidebar/NumericField.tsx` — current label JSX (lines 33-35)
- `gui/src/components/sidebar/ParameterForm.tsx` — rendering loop and `onParamChange` signature
- `gui/src/components/sidebar/PipeGeometryPicker.tsx` — DimensionField label pattern
- `gui/src/components/sidebar/InstanceNameField.tsx` — no label present
- `gui/src/registry/components.json` — htc_correlation options (lines 46-52, 117-123, 202-208)
- `gui/src/registry/types.ts` — FunctionOption (lines 11-15), Parameter (lines 17-26)
- `gui/src/store/useStore.ts` — updateNodeParams implementation (lines 82-105), StreamNodeData (lines 15-20)
- `gui/package.json` — confirms `lucide-react` available
