# Phase 35: Parameter Editing - Research

**Researched:** 2026-04-02
**Domain:** React form rendering, Zustand store actions, shadcn/ui components, validation
**Confidence:** HIGH

## Summary

Phase 35 replaces the SidebarPanel stub with a registry-driven parameter editing form. The existing codebase provides strong foundations: `getComponent(id)` returns full parameter metadata from `components.json`, the Zustand store already has `selectedNodeId` and `nodes` with `StreamNodeData`, and shadcn configuration (New York/Zinc) is ready for `npx shadcn add` component installs. The primary work is: (1) installing shadcn UI primitives, (2) building form field renderers per parameter type, (3) adding `updateNodeParams` to the store, (4) wiring `onNodeClick`/`onPaneClick` in CanvasPanel (not yet present), and (5) implementing on-blur validation.

The registry schema needs a small extension: adding an `options` field to Function-type parameters for correlation dropdown lists, and the `Parameter` TypeScript interface needs updating to match. The Pump component's `constructorModes` array already defines mode-specific parameter lists, which drives the mode toggle UI naturally.

**Primary recommendation:** Build a single `ParameterForm` component that reads the registry and dispatches to type-specific field renderers (NumericField, PipeGeometryPicker, FunctionSelect, etc.) -- no hardcoded component-specific forms.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** PipeGeometry picker is a segmented control: `[ Circular | Rectangular ]`. Conditional fields render below based on selection. Circular shows L + D; Rectangular shows L + W + H.
- **D-02:** Switching geometry type clears all dimension fields to empty. No value migration between types.
- **D-03:** Show a dropdown of all available correlation names for each Function-type parameter. Simple closures are fully interactive: `dittus_boelter`, `constant_Nusselt` (HTC); `blasius_friction`, `laminar_friction` (friction).
- **D-04:** Factory correlations (`regime_dependent`, `elenbaas_htc`, `maximal_htc`) appear in the dropdown but are grayed out and non-selectable in Phase 35, with a tooltip: "Factory correlation editing coming in a future update." Phase 35.1 activates them with nested sub-parameter forms.
- **D-05:** The dropdown option list must come from the registry -- add an `options` field to Function-type parameter entries in `components.json`. Do not hardcode correlation names in the UI component.
- **D-06:** Validation fires on-blur (when the user leaves a field). No validation noise while typing. Error message appears inline below the field.
- **D-07:** Validation rules per field type: `Int` -- positive integer; `Real` -- finite number (NaN/Infinity rejected); `PipeGeometry` sub-fields -- all required dimensions must be positive; component name -- must match Julia identifier pattern `[a-zA-Z_][a-zA-Z0-9_]*`.
- **D-08:** Clicking canvas background (deselect) clears sidebar to placeholder state. `selectedNodeId` in store returns to `null`.
- **D-09:** Clicking a node sets `selectedNodeId` and sidebar renders that node's form. Switching between nodes updates immediately.
- **D-10:** Add `updateNodeParams(nodeId, params)` action to the Zustand store. Undo/redo via zundo covers param edits automatically.

### Claude's Discretion
- Exact shadcn/ui components to install and use (Input, Label, Button for segmented control, Badge for read-only, Select for dropdowns)
- Sidebar section layout (name field at top, then parameters grouped by type)
- Exact error message wording for each validation rule
- Whether to show units (m, kg/s, Pa) as suffix labels on numeric inputs

### Deferred Ideas (OUT OF SCOPE)
- Factory correlation sub-parameter forms (Phase 35.1)
- marco_han_nusselt in correlation list (check export before adding; may be Phase 35.1 only)
- Correlation closure editing (v0.9+)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PARA-01 | Click any canvas node to open parameter editing sidebar | Wire `onNodeClick` in CanvasPanel to `selectNode(nodeId)`; SidebarPanel reads `selectedNodeId` from store; registry lookup via `getComponent(node.data.componentId)` |
| PARA-02 | Edit all scalar parameter values; changes reflected immediately | `updateNodeParams` store action writes to `nodes[].data.parameters`; form fields call this on valid blur; store subscription re-renders sidebar and StreamNode label |
| PARA-03 | Toggle Pump mode between fixed-dP and fixed-mdot; show appropriate fields | Pump's `constructorModes` array has `fixed-dP` and `fixed-mdot` entries with distinct `parameters` lists; render segmented control, filter visible fields by active mode |
| PARA-04 | Configure PipeGeometry: circular vs rectangular picker + dimension fields | PipeGeometry parameter type triggers dedicated sub-component with segmented control + conditional L/D or L/W/H fields; stored as structured object in `parameters.geometry` |
| PARA-05 | Rename component instance; invalid Julia identifiers rejected | Instance name text input at top of sidebar; validate on blur with `^[a-zA-Z_][a-zA-Z0-9_]*$`; `updateNodeParams(nodeId, { instanceName })` updates store; StreamNode reads from store for label |
| PARA-06 | Per-field validation error for wrong type/empty/out of range | On-blur validation per D-06/D-07; error text in destructive color below field; invalid values NOT written to store |
</phase_requirements>

## Standard Stack

### Core (already installed)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| react | 19.1.0 | UI framework | Already in project |
| zustand | 5.0.12 | State management | Already in project, store pattern established |
| zundo | 2.3.0 | Undo/redo for zustand | Already in project, temporal wrapper in place |
| @xyflow/react | 12.10.2 | Canvas/flow editor | Already in project |
| tailwindcss | 4.2.2 | CSS utility framework | Already configured with v4 + @tailwindcss/vite |

### shadcn/ui Components (to install)
| Component | Radix Dependency | Purpose |
|-----------|-----------------|---------|
| input | none | Numeric and text fields |
| label | @radix-ui/react-label | Field labels |
| button | @radix-ui/react-slot | Segmented controls (PipeGeometry, Pump mode) |
| select | @radix-ui/react-select 2.2.6 | Function-type correlation dropdowns |
| tooltip | @radix-ui/react-tooltip 1.2.8 | Disabled factory correlation hover explanation |
| separator | @radix-ui/react-separator 1.1.8 | Section dividers |
| badge | none (pure CSS variant) | Read-only Matrix display |
| scroll-area | @radix-ui/react-scroll-area 1.2.10 | Sidebar content overflow |

**Installation command:**
```bash
cd gui && npx shadcn add input label button select tooltip separator badge scroll-area
```

This installs component files into `gui/src/components/ui/` and auto-installs Radix peer dependencies.

### Supporting (already installed)
| Library | Version | Purpose |
|---------|---------|---------|
| clsx | 2.1.1 | Conditional class composition |
| tailwind-merge | 3.5.0 | Merge Tailwind classes without conflicts |
| lucide-react | 1.7.0 | Icons (if needed for dropdown chevrons, etc.) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Custom segmented control | @radix-ui/react-toggle-group | Would require separate install; two styled Buttons with variant toggling is simpler and matches UI-SPEC |
| React Hook Form | Manual onChange/onBlur | RHF is overkill for this use case -- form has no submit, values sync to store on blur, validation is field-level only |

## Architecture Patterns

### Recommended Component Structure
```
gui/src/
  components/
    ui/                          # shadcn-installed primitives (auto-generated)
      input.tsx
      label.tsx
      button.tsx
      select.tsx
      tooltip.tsx
      separator.tsx
      badge.tsx
      scroll-area.tsx
    sidebar/                     # Phase 35 sidebar components
      SidebarPanel.tsx           # Main sidebar (replaces existing stub)
      ParameterForm.tsx          # Registry-driven form dispatcher
      InstanceNameField.tsx      # Name input + Julia identifier validation
      NumericField.tsx           # Real/Int input with unit suffix + validation
      PipeGeometryPicker.tsx     # Segmented control + conditional dimension fields
      FunctionSelect.tsx         # Correlation dropdown with disabled factory items
      ModeToggle.tsx             # Pump mode segmented control
      MatrixBadge.tsx            # Read-only Matrix display badge
    SidebarPanel.tsx             # DELETED (moved to sidebar/)
    ...
  lib/
    validation.ts                # Validation functions (reusable, testable)
```

### Pattern 1: Registry-Driven Form Rendering
**What:** Loop over `component.parameters`, match each parameter's `type` to a field renderer component.
**When to use:** Always -- this is the core rendering pattern.
**Example:**
```typescript
// ParameterForm.tsx
function ParameterForm({ component, activeMode, values, onChange }: Props) {
  const modeParams = component.constructorModes.find(m => m.mode === activeMode);
  const visibleParamNames = modeParams?.parameters ?? component.parameters.map(p => p.name);

  return visibleParamNames.map(name => {
    const param = component.parameters.find(p => p.name === name);
    if (!param) return null;
    switch (param.type) {
      case "Int":
      case "Real":
        return <NumericField key={name} param={param} value={values[name]} onChange={v => onChange(name, v)} />;
      case "PipeGeometry":
        return <PipeGeometryPicker key={name} value={values[name]} onChange={v => onChange(name, v)} />;
      case "Function":
        return <FunctionSelect key={name} param={param} value={values[name]} onChange={v => onChange(name, v)} />;
      case "Matrix":
        return <MatrixBadge key={name} param={param} />;
      case "Bool":
        return <BoolToggle key={name} param={param} value={values[name]} onChange={v => onChange(name, v)} />;
    }
  });
}
```

### Pattern 2: Zustand Store Update Pattern
**What:** `updateNodeParams` uses immutable map-and-patch pattern already established in the store.
**Example:**
```typescript
updateNodeParams: (nodeId, patch) =>
  set({
    nodes: get().nodes.map(n =>
      n.id === nodeId
        ? { ...n, data: { ...n.data, ...patch, parameters: { ...(n.data as StreamNodeData).parameters, ...patch.parameters } } }
        : n
    ),
  }),
```

**Key detail:** The patch may contain `instanceName` (for rename) or `parameters` (for param edits) or both. The action must handle partial updates to the nested `parameters` object. The `Partial<StreamNodeData>` type from D-10 accommodates this.

### Pattern 3: On-Blur Validation with Store Gating
**What:** Field state is local (React useState) while typing. On blur: validate. If valid, write to store. If invalid, show error, do NOT write to store (retain previous valid value).
**When to use:** All editable fields.
**Example:**
```typescript
function NumericField({ param, value, onChange }: Props) {
  const [localValue, setLocalValue] = useState(String(value ?? param.default ?? ""));
  const [error, setError] = useState<string | null>(null);

  const handleBlur = () => {
    const result = validateNumeric(localValue, param.type as "Int" | "Real");
    if (result.valid) {
      setError(null);
      onChange(result.value);
    } else {
      setError(result.message);
    }
  };

  return (
    <div className="flex flex-col gap-[8px]">
      <Label>{param.name}{param.unit && <span className="text-muted-foreground ml-1">{param.unit}</span>}</Label>
      <Input value={localValue} onChange={e => setLocalValue(e.target.value)} onBlur={handleBlur} />
      {error && <p className="text-destructive text-xs">{error}</p>}
    </div>
  );
}
```

### Pattern 4: Canvas Selection Wiring
**What:** CanvasPanel needs `onNodeClick` and `onPaneClick` handlers to drive sidebar.
**Key finding:** These handlers are NOT yet in `CanvasPanel.tsx`. Phase 35 must add them.
**Example:**
```typescript
// In CanvasPanel.tsx ReactFlow props:
const { selectNode } = useStore();
<ReactFlow
  ...
  onNodeClick={(_event, node) => selectNode(node.id)}
  onPaneClick={() => selectNode(null)}
>
```

### Anti-Patterns to Avoid
- **Hardcoding component-specific forms:** Never write `if (componentId === "Pump") { ... }`. Always drive from registry data.
- **Validation on keystroke:** D-06 specifies on-blur only. Keystroke validation creates noise and frustrates users.
- **Writing invalid values to store:** Invalid data propagates to Phase 36 code generation, producing broken Julia code.
- **Storing PipeGeometry as flat params:** PipeGeometry should be stored as a structured object `{ type: "circular", L: 0.5, D: 0.01 }` or `{ type: "rectangular", L: 0.5, W: 0.06, H: 0.001 }` in `parameters.geometry`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Dropdown menus | Custom select with manual keyboard nav | shadcn Select (Radix) | Keyboard navigation, focus management, ARIA attributes |
| Tooltip | Custom hover div | shadcn Tooltip (Radix) | Delay handling, portal rendering, accessible tooltips |
| Scroll overflow | `overflow-y-auto` div | shadcn ScrollArea (Radix) | Custom scrollbar styling, cross-browser consistency |
| Class merging | Manual string concatenation | `cn()` from `lib/utils.ts` | Already in project, handles Tailwind class conflicts |

## Common Pitfalls

### Pitfall 1: Stale Form State When Switching Nodes
**What goes wrong:** User edits Channel_1 fields, clicks Channel_2 -- old values from Channel_1 appear briefly or remain.
**Why it happens:** Local React state in field components persists across parent re-renders if the component identity doesn't change.
**How to avoid:** Use `key={selectedNodeId}` on the ParameterForm component so React unmounts/remounts the entire form when the selected node changes. This resets all local state.
**Warning signs:** Values from a previous node appearing after clicking a different node.

### Pitfall 2: PipeGeometry Store Shape Mismatch
**What goes wrong:** Code generation (Phase 36) can't reconstruct `PipeGeometry_circular(L, D)` from stored parameters because geometry data is stored in a flat or inconsistent format.
**Why it happens:** No agreed serialization format for PipeGeometry in the store.
**How to avoid:** Define a clear TypeScript interface for stored PipeGeometry values:
```typescript
type PipeGeometryValue =
  | { type: "circular"; L: number; D: number }
  | { type: "rectangular"; L: number; W: number; H: number };
```
Store this object in `parameters.geometry`. Phase 36 reads `type` to determine which factory function to call.

### Pitfall 3: Pump Mode State Not Persisted
**What goes wrong:** User selects fixed-mdot mode and enters mdot0=0.5, saves, reloads -- mode resets to fixed-dP.
**Why it happens:** The active constructor mode is not stored in the node data.
**How to avoid:** Store `constructorMode: string` alongside `parameters` in `StreamNodeData`. Default to the first `constructorModes` entry. Persist this with the node.

### Pitfall 4: Default Values Not Populated on Node Creation
**What goes wrong:** Newly dropped node has empty parameters; sidebar shows all fields empty instead of defaults.
**Why it happens:** `addNode` in the store currently sets `parameters: {}`.
**How to avoid:** When `addNode` creates a node, populate `parameters` with defaults from the registry: loop over `component.parameters`, set each to `param.default` if defined. This ensures the form shows sensible defaults and code generation has values from the start.

### Pitfall 5: Unit Suffix Overlapping Input Text
**What goes wrong:** Long numbers push into the unit suffix text, making both unreadable.
**Why it happens:** Fixed-position suffix inside a flexible-width input.
**How to avoid:** Use `pr-12` (or similar right-padding) on the input to reserve space for the suffix. Position the suffix absolutely within a relative container.

### Pitfall 6: Registry options Field Missing Causes Runtime Error
**What goes wrong:** FunctionSelect component tries to read `param.options` but the registry entry has no `options` field, causing `undefined.map()` crash.
**Why it happens:** `options` field is new and needs to be added to both JSON and TypeScript interface.
**How to avoid:** Add `options` to the `Parameter` interface and to all Function-type entries in `components.json` in the same task that builds the FunctionSelect. Validate at render time with optional chaining.

## Code Examples

### Validation Functions
```typescript
// lib/validation.ts

export function validateInt(value: string): { valid: true; value: number } | { valid: false; message: string } {
  if (value.trim() === "") return { valid: false, message: "Required" };
  const n = Number(value);
  if (!Number.isInteger(n)) return { valid: false, message: "Must be a positive integer" };
  if (n <= 0) return { valid: false, message: "Must be a positive integer" };
  return { valid: true, value: n };
}

export function validateReal(value: string): { valid: true; value: number } | { valid: false; message: string } {
  if (value.trim() === "") return { valid: false, message: "Required" };
  const n = Number(value);
  if (isNaN(n) || !isFinite(n)) return { valid: false, message: "Must be a finite number" };
  return { valid: true, value: n };
}

export function validatePositiveReal(value: string): { valid: true; value: number } | { valid: false; message: string } {
  const result = validateReal(value);
  if (!result.valid) return result;
  if (result.value <= 0) return { valid: false, message: "Must be positive" };
  return result;
}

export function validateJuliaIdentifier(value: string): { valid: true; value: string } | { valid: false; message: string } {
  if (value.trim() === "") return { valid: false, message: "Required" };
  if (!/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(value)) {
    return { valid: false, message: "Must be a valid Julia identifier (letters, digits, underscores; start with letter or underscore)" };
  }
  return { valid: true, value };
}
```

### Registry Extension for Function Options
```json
{
  "name": "htc_correlation",
  "type": "Function",
  "default": "dittus_boelter",
  "description": "HTC correlation closure (Re, Pr, T_bulk, T_wall) -> Nu",
  "required": false,
  "positional": false,
  "options": [
    { "value": "dittus_boelter", "label": "Dittus-Boelter", "kind": "simple" },
    { "value": "constant_Nusselt", "label": "Constant Nusselt", "kind": "simple" },
    { "value": "regime_dependent", "label": "Regime Dependent", "kind": "factory" },
    { "value": "elenbaas_htc", "label": "Elenbaas", "kind": "factory" },
    { "value": "maximal_htc", "label": "Maximal HTC", "kind": "factory" }
  ]
}
```

TypeScript interface extension:
```typescript
export interface FunctionOption {
  value: string;
  label: string;
  kind: "simple" | "factory";
}

export interface Parameter {
  // ... existing fields ...
  options?: FunctionOption[];  // Only for Function-type parameters
}
```

### Store updateNodeParams Action
```typescript
// Added to AppState interface:
updateNodeParams: (nodeId: string, patch: Partial<StreamNodeData>) => void;

// Implementation inside create():
updateNodeParams: (nodeId, patch) => {
  const { nodes } = get();
  set({
    nodes: nodes.map(n => {
      if (n.id !== nodeId) return n;
      const data = n.data as StreamNodeData;
      return {
        ...n,
        data: {
          ...data,
          ...(patch.instanceName !== undefined && { instanceName: patch.instanceName }),
          ...(patch.parameters !== undefined && { parameters: { ...data.parameters, ...patch.parameters } }),
          ...(patch.constructorMode !== undefined && { constructorMode: patch.constructorMode }),
        },
      };
    }),
  });
},
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| shadcn v0 (copy-paste from docs) | shadcn CLI `npx shadcn add` | 2024 | Auto-installs Radix deps, generates component files |
| Tailwind v3 (tailwind.config.js) | Tailwind v4 (@tailwindcss/vite, CSS-first config) | 2025 | No config file needed; this project already uses v4 |
| React 18 controlled forms | React 19 same pattern | 2025 | No change to form patterns; controlled inputs still standard |

## Project Constraints (from CLAUDE.md)

- No Unicode variable names in Julia code (ASCII only)
- shadcn/ui CSS variables already configured (New York/Zinc)
- No `ui/` component files installed yet -- Phase 35 installs them via `npx shadcn add`
- `@vitest-environment happy-dom` docblock required for React component test files
- `vitest` default environment is `node`; test setup file polyfills `crypto.randomUUID`
- Path alias `@/*` maps to `./src/*` in both tsconfig and vitest config

## Open Questions

1. **StreamNodeData.constructorMode field**
   - What we know: Pump has two modes (fixed-dP, fixed-mdot). The active mode must be persisted with the node so it survives selection changes and page reloads.
   - What's unclear: The current `StreamNodeData` interface has no `constructorMode` field.
   - Recommendation: Add `constructorMode?: string` to `StreamNodeData`. Default to `constructorModes[0].mode` for each component. Most components have only one mode ("default"), so the field is optional and harmless.

2. **Default parameter population on addNode**
   - What we know: Currently `addNode` sets `parameters: {}`. Sidebar will show empty fields.
   - What's unclear: Whether defaults should be populated at node creation time or lazily when the form first renders.
   - Recommendation: Populate at creation time. This ensures code generation (Phase 36) always has values, and prevents a class of "no data" edge cases.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | vitest 4.1.2 |
| Config file | `gui/vitest.config.ts` |
| Quick run command | `cd gui && npx vitest run --passWithNoTests` |
| Full suite command | `cd gui && npx vitest run --passWithNoTests` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PARA-01 | Click node opens sidebar | integration (component) | `cd gui && npx vitest run src/components/sidebar/__tests__/SidebarPanel.test.tsx` | Wave 0 |
| PARA-02 | Edit scalar params, store updates | unit + integration | `cd gui && npx vitest run src/components/sidebar/__tests__/ParameterForm.test.tsx` | Wave 0 |
| PARA-03 | Pump mode toggle | unit | `cd gui && npx vitest run src/components/sidebar/__tests__/ModeToggle.test.tsx` | Wave 0 |
| PARA-04 | PipeGeometry picker | unit | `cd gui && npx vitest run src/components/sidebar/__tests__/PipeGeometryPicker.test.tsx` | Wave 0 |
| PARA-05 | Rename with Julia identifier validation | unit | `cd gui && npx vitest run src/components/sidebar/__tests__/InstanceNameField.test.tsx` | Wave 0 |
| PARA-06 | Validation errors | unit | `cd gui && npx vitest run src/lib/__tests__/validation.test.ts` | Wave 0 |

### Sampling Rate
- **Per task commit:** `cd gui && npx vitest run --passWithNoTests`
- **Per wave merge:** `cd gui && npx vitest run --passWithNoTests`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `gui/src/lib/__tests__/validation.test.ts` -- covers PARA-06 validation logic (pure functions, no DOM)
- [ ] `gui/src/components/sidebar/__tests__/SidebarPanel.test.tsx` -- covers PARA-01 selection/empty state
- [ ] `gui/src/components/sidebar/__tests__/ParameterForm.test.tsx` -- covers PARA-02 field rendering
- [ ] `gui/src/components/sidebar/__tests__/PipeGeometryPicker.test.tsx` -- covers PARA-04
- [ ] `gui/src/components/sidebar/__tests__/ModeToggle.test.tsx` -- covers PARA-03
- [ ] `gui/src/components/sidebar/__tests__/InstanceNameField.test.tsx` -- covers PARA-05
- [ ] `gui/src/store/__tests__/useStore.test.ts` -- extend for `updateNodeParams` action

## Sources

### Primary (HIGH confidence)
- `gui/src/store/useStore.ts` -- current store implementation, StreamNodeData interface
- `gui/src/registry/components.json` -- full component metadata including constructorModes
- `gui/src/registry/types.ts` -- TypeScript interfaces for registry schema
- `gui/src/components/SidebarPanel.tsx` -- current stub to replace
- `gui/src/components/CanvasPanel.tsx` -- needs onNodeClick/onPaneClick wiring
- `gui/src/components/StreamNode.tsx` -- reads nodeData.instanceName for canvas label
- `gui/components.json` -- shadcn configuration (New York/Zinc preset)
- `gui/vitest.config.ts` -- test configuration
- `gui/package.json` -- dependency versions

### Secondary (MEDIUM confidence)
- shadcn CLI v4.1.2 -- `npx shadcn add` installs components to `src/components/ui/`
- Radix UI component versions verified via npm registry (2026-04-02)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - all dependencies already installed or available via shadcn CLI; versions verified against npm registry
- Architecture: HIGH - pattern follows established registry-driven approach from Phase 33/34; store patterns from existing code
- Pitfalls: HIGH - identified from direct code inspection of current store and component implementations

**Research date:** 2026-04-02
**Valid until:** 2026-05-02 (stable -- no fast-moving dependencies)
