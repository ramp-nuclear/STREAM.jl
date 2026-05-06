# Phase 36: Code Generation - Research

**Researched:** 2026-04-02
**Domain:** Graph-to-Julia code generation, Tauri native file dialog, BC editing UI
**Confidence:** HIGH

## Summary

Phase 36 transforms the canvas graph (nodes, edges, parameters) into valid STREAM.jl Julia code, adds a boundary conditions editor, and provides file export via Tauri's native save dialog. The code generator is a pure function `(nodes, edges, bcs, registry) -> string` with no UI coupling. The UI adds three new components: a toolbar bar above the canvas, a collapsible bottom panel with Code/BCs tabs, and the BC structured form.

The primary technical challenge is correct code emission for all parameter types: positional vs keyword arguments (driven by `parameter.positional`), PipeGeometry factory calls, Function-type parameters (simple closures as bare identifiers vs factory calls with kwargs), and the active constructor mode determining which parameters to emit. All of this information is already in the registry and store -- the code generator reads it; it does not hardcode component behavior.

**Primary recommendation:** Build the code generator as a standalone pure module (`gui/src/lib/codeGenerator.ts`) with comprehensive unit tests, then wire it into the UI. Install `tauri-plugin-dialog` and `tauri-plugin-fs` for native file export.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Bottom panel below the full-width canvas (spanning Toolbox + Canvas + Sidebar columns). Collapsible. IDE convention layout.
- **D-02:** A "Code" button in a top toolbar / canvas header bar toggles the bottom panel open/closed. Export button also lives in this toolbar area.
- **D-03:** The bottom panel has two tabs: [Code] [BCs]. The BCs tab shows the boundary conditions list + Add button. Same panel, same toggle.
- **D-04:** BC entry uses a structured form: `[component dropdown] . [port.field dropdown] ~ [value input]` + `[Add]`. Component dropdown populated from canvas nodes (instanceNames). Port.field dropdown limited to FlowPort.P only (inlet.P and outlet.P). Thermal BCs come from ConstantTemperature canvas nodes (Phase 40).
- **D-05:** BC entries stored in Zustand store as `{ nodeId: string, portField: "inlet.P" | "outlet.P", value: number }[]`. Each entry renders as a row with expression string and delete [x] button.
- **D-06:** Full runnable stub format with `using ModelingToolkit, STREAM`, `@named` declarations, `eqs` array with `connect()` + BCs, `@named sys = ODESystem(eqs, t; systems=[...])`, `mtkcompile`, commented solve stub.
- **D-07:** Uses `ODESystem(eqs, t; systems=[...])` idiom, not `compose(System(...), ...)`.
- **D-08:** `@named` declarations use correct positional vs keyword convention from CLAUDE.md. Registry `positional` field drives this -- no hardcoding.
- **D-09:** Function-type params: string value -> bare Julia identifier; `value.kind === "factory"` -> factory call with kwargs.
- **D-10:** Component ordering follows insertion order (canvas node order). No topological sorting.
- **D-11:** Export via Tauri native save dialog (`tauri-plugin-dialog`), default filename `system.jl`, filter `.jl` files.

### Claude's Discretion
- Syntax highlighting library (decided: no highlighting in Phase 36 per UI-SPEC)
- Exact toolbar component layout and styling
- Whether bottom panel has resize handle or fixed height (decided: fixed 240px per UI-SPEC)
- shadcn/ui components for BC form
- Error display for CODE-07 identifier validation

### Deferred Ideas (OUT OF SCOPE)
- Thermal BC via BC panel (Phase 40 -- ConstantTemperature canvas node)
- Syntax highlighting (Phase 38 may add)
- Live validation feedback for unconnected ports (Phase 37/39)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CODE-01 | Live-updating read-only preview of generated Julia code in collapsible bottom panel | Bottom panel with Code tab; `useMemo` regeneration on store changes |
| CODE-02 | Export as `.jl` file via native file save dialog | `tauri-plugin-dialog` save() + `tauri-plugin-fs` writeTextFile() |
| CODE-03 | `@named` declarations with correct positional vs keyword args | Registry `positional` field + `constructorModes` active mode parameters |
| CODE-04 | One `connect()` call per canvas edge using port names | Edge `sourceHandle`/`targetHandle` carry port names directly |
| CODE-05 | ODESystem + mtkcompile boilerplate | Static template; D-06/D-07 define exact format |
| CODE-06 | BC panel for pressure anchors; BCs pushed into connections list | BC store state + structured form; emitted as `instanceName.portField ~ value` in eqs |
| CODE-07 | Julia identifier validation | Existing `validateJuliaIdentifier()` in `validation.ts`; warning comment in generated code |
</phase_requirements>

## Standard Stack

### Core (already installed)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| React | 18.x | UI framework | Already in project |
| Zustand | 4.x + zundo | State management | Already in project; BC state extends existing store |
| @xyflow/react | 12.x | Canvas graph (nodes/edges source) | Already in project |
| shadcn/ui | latest | UI components (Tabs new, rest existing) | Already in project |
| Vitest | latest | Testing | Already configured |

### New Dependencies (must install)
| Library | Purpose | Installation |
|---------|---------|-------------|
| `@tauri-apps/plugin-dialog` | Native save file dialog | `npm install @tauri-apps/plugin-dialog` + `cargo add tauri-plugin-dialog` in src-tauri |
| `@tauri-apps/plugin-fs` | Write file to disk | `npm install @tauri-apps/plugin-fs` + `cargo add tauri-plugin-fs` in src-tauri |

### New shadcn Component
| Component | Installation |
|-----------|-------------|
| Tabs | `npx shadcn@latest add tabs` |

**Installation:**
```bash
cd gui
npx shadcn@latest add tabs
npm install @tauri-apps/plugin-dialog @tauri-apps/plugin-fs
cd src-tauri && cargo add tauri-plugin-dialog tauri-plugin-fs
```

## Architecture Patterns

### New Files
```
gui/src/
  lib/
    codeGenerator.ts          # Pure function: (nodes, edges, bcs, registry) -> string
    codeGenerator.test.ts     # Unit tests for code generation (node environment)
  components/
    Toolbar.tsx               # Code toggle + Export buttons
    BottomPanel.tsx           # Collapsible panel with Tabs (Code/BCs)
    CodePreview.tsx           # Read-only <pre><code> with ScrollArea
    BCPanel.tsx               # BC list + add form
    BCRow.tsx                 # Single BC entry row with delete
```

### Layout Change (App.tsx)
Current: `<div class="flex h-screen">Toolbox | Canvas | Sidebar</div>`

New:
```
<div class="flex flex-col h-screen">
  <div class="flex flex-1 min-h-0">       <!-- existing 3-panel row -->
    <ToolboxPanel />
    <div class="flex flex-col flex-1">     <!-- canvas column -->
      <Toolbar />                          <!-- NEW: 36px -->
      <CanvasPanel />                      <!-- flex-1 -->
    </div>
    <SidebarPanel />
  </div>
  <BottomPanel />                          <!-- NEW: 240px or 0px -->
</div>
```

### Pattern 1: Code Generator as Pure Function
**What:** `generateCode(nodes, edges, bcs, getComponent)` is a pure function with zero React/DOM dependencies.
**When to use:** Always. The entire code generation logic lives in `lib/codeGenerator.ts`.
**Why:** Enables comprehensive unit testing in node environment (no jsdom needed). The React component just calls `useMemo(() => generateCode(...), [nodes, edges, bcs])`.

### Pattern 2: Parameter Emission by Type
**What:** The code generator must handle each parameter type differently.
**Rules:**

| Param Type | Store Value | Emitted Julia |
|------------|-------------|---------------|
| `Real` | `number` | `30000.0` (numeric literal) |
| `Int` | `number` | `5` (integer literal) |
| `Bool` | `boolean` | `true` / `false` |
| `PipeGeometry` | `{ type: "circular", L: 0.5, D: 0.01 }` | `PipeGeometry_circular(0.5, 0.01)` |
| `PipeGeometry` | `{ type: "rectangular", L: 0.5, W: 0.01, H: 0.003 }` | `PipeGeometry_rectangular(0.5, 0.01, 0.003)` |
| `Function` (simple) | `"dittus_boelter"` (string) | `dittus_boelter` (bare identifier) |
| `Function` (factory) | `{ kind: "factory", value: "elenbaas_htc", subParams: { b: 0.003, L: 0.6, Dh: 0.0025, g: 9.80665 } }` | `elenbaas_htc(b=0.003, L=0.6, Dh=0.0025, g=9.80665)` |
| `Matrix` | (not user-editable in Phase 36) | Skip or emit default |

**Factory sub-params that are themselves Function-type** (e.g., `regime_dependent.htc_forced = "dittus_boelter"` or `regime_dependent.htc_natural = { kind: "factory", value: "elenbaas_htc", ... }`): Recurse the same simple/factory check. Capped at one level of nesting per CONTEXT D-09 and Phase 35.1 design.

### Pattern 3: Constructor Mode Drives Parameter List
**What:** Each component has `constructorModes[]`. The active mode (stored in `node.data.constructorMode`) determines which parameters from the full `parameters[]` array are included in the emitted constructor call.
**Example:**
- Pump `fixed-dP` mode: parameters = `["dP_pump"]`, dP_pump is `positional: true` -> `Pump(30000.0)`
- Pump `fixed-mdot` mode: parameters = `["mdot0"]`, mdot0 is `positional: false` -> `Pump(; mdot0=0.5)`

**Algorithm for one component:**
1. Look up `constructorModes.find(m => m.mode === node.data.constructorMode)`
2. Get active parameter names from `mode.parameters`
3. For each parameter name, find the full `Parameter` definition from `component.parameters`
4. Partition into positional (emit in order, no name) and keyword (emit as `name=value`)
5. Format: positional args first, then `; ` separator (if any kwargs), then kwargs

### Pattern 4: BC Store Extension
**What:** Add `bcs: BCEntry[]`, `addBC`, `removeBC` to the Zustand store. BC entries reference nodes by `nodeId` and must resolve to `instanceName` at code generation time.
**Why nodeId not instanceName:** If the user renames a component after adding a BC, the BC must still reference the correct node. `nodeId` is stable; `instanceName` can change.

### Anti-Patterns to Avoid
- **Hardcoding component signatures:** Never write `if (componentId === "Pump") emit("Pump(${dP})")`. The registry is the source of truth.
- **Storing BCs by instanceName:** Use nodeId for stability; resolve instanceName at render/codegen time.
- **Putting code generation logic inside React components:** Keep it in `lib/codeGenerator.ts` for testability.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| File save dialog | Custom file picker modal | `@tauri-apps/plugin-dialog` save() | Native OS dialog, handles all platforms |
| File writing | Custom IPC command | `@tauri-apps/plugin-fs` writeTextFile() | Standard Tauri plugin, handles encoding |
| Tab component | Custom div-based tabs | shadcn Tabs (Radix UI) | Accessible, keyboard-navigable, styled consistently |
| Julia identifier validation | New regex | Existing `validateJuliaIdentifier()` in `validation.ts` | Already tested and used in Phase 35 |

## Common Pitfalls

### Pitfall 1: Forgetting Semicolon for Keyword-Only Constructors
**What goes wrong:** Emitting `Channel(n=5, geometry=...)` instead of `Channel(; n=5, geometry=...)`. Julia requires `;` before keyword-only arguments.
**Why it happens:** Code generator treats positional and keyword the same.
**How to avoid:** If all active-mode parameters are keyword-only (`positional: false`), emit `ComponentName(; kwarg1=v1, kwarg2=v2)`. If there are positional params, they come first and keywords follow after `;`.
**Warning signs:** Generated code fails with `MethodError: no method matching` in Julia.

### Pitfall 2: PipeGeometry With Empty Fields
**What goes wrong:** User creates a Channel but hasn't filled in the PipeGeometry dimensions yet (fields are `""`). Code generator emits `PipeGeometry_circular(, )`.
**Why it happens:** PipeGeometryPicker stores `""` for unfilled fields.
**How to avoid:** Check for empty/incomplete PipeGeometry values before emitting. Either skip the parameter (if optional) or emit a placeholder comment: `# TODO: set geometry dimensions`.
**Warning signs:** Generated code has syntax errors.

### Pitfall 3: Tauri Plugin Permissions Not Configured
**What goes wrong:** `save()` or `writeTextFile()` fails silently or throws at runtime.
**Why it happens:** Tauri 2 requires explicit capability permissions in `src-tauri/capabilities/default.json`.
**How to avoid:** Add `"dialog:default"` and `"fs:default"` (or more scoped permissions like `"fs:allow-write-text-file"`) to the permissions array. Also register both plugins in `lib.rs` with `.plugin(tauri_plugin_dialog::init())` and `.plugin(tauri_plugin_fs::init())`.

### Pitfall 4: BC References Stale After Node Deletion
**What goes wrong:** User adds a BC for a pump, then deletes that pump node. BC entry points to a nonexistent nodeId.
**Why it happens:** BC array is not cleaned up when nodes are removed.
**How to avoid:** In the `removeNode` store action, also filter out BCs whose `nodeId` matches the deleted node. Alternatively, the code generator skips BCs whose nodeId cannot be resolved.

### Pitfall 5: Default Parameter Values Emitted Unnecessarily
**What goes wrong:** Generated code includes `g=0.0` for horizontal channels, `friction_correlation=blasius_friction` when it's the default. This is valid but clutters the output.
**Why it happens:** Code gen emits every parameter regardless of whether it matches the default.
**How to avoid:** Compare parameter value against `parameter.default` from the registry. If equal, omit from the emitted constructor call. This produces cleaner, more readable code. Only emit non-default values.
**Exception:** Required parameters with no default must always be emitted.

### Pitfall 6: Number Formatting for Julia
**What goes wrong:** JavaScript `0.001` might serialize as `0.001` (fine) but `100000` as `100000` instead of `1.0e5`, or `5` as `5.0` when it should be an integer.
**Why it happens:** JavaScript's `Number.toString()` doesn't match Julia conventions.
**How to avoid:** For `Real` type: ensure at least one decimal point (append `.0` to integers so Julia reads them as Float64). For `Int` type: emit as integer (no decimal). For large/small numbers: scientific notation is fine but not required.

## Code Examples

### Code Generator Core Logic
```typescript
// gui/src/lib/codeGenerator.ts

interface BCEntry {
  nodeId: string;
  portField: "inlet.P" | "outlet.P";
  value: number;
}

function generateCode(
  nodes: Node[],
  edges: Edge[],
  bcs: BCEntry[],
  getComponent: (id: string) => ComponentDefinition | undefined
): string {
  if (nodes.length === 0) {
    return "# Add components to the canvas to generate Julia code.";
  }

  const lines: string[] = [];

  // Header
  lines.push("using ModelingToolkit, STREAM");
  lines.push("using ModelingToolkit: t_nounits as t");
  lines.push("");

  // Components
  lines.push("# Components");
  for (const node of nodes) {
    const data = node.data as StreamNodeData;
    const component = getComponent(data.componentId);
    if (!component) continue;
    lines.push(emitComponentDeclaration(data, component));
  }
  lines.push("");

  // Connections + BCs
  lines.push("# Connections");
  lines.push("eqs = [");
  // ... connect() calls from edges
  // ... BC equations
  lines.push("]");
  lines.push("");

  // System
  const systemsList = nodes
    .map((n) => (n.data as StreamNodeData).instanceName)
    .join(", ");
  lines.push(`@named sys = ODESystem(eqs, t; systems=[${systemsList}])`);
  lines.push("ssys = mtkcompile(sys)");
  lines.push("");

  // Solve stub
  lines.push("# Solve (uncomment to run)");
  lines.push("# sol = solve(SteadyStateProblem(ssys, []), DynamicSS(Rodas5P()))");

  return lines.join("\n");
}
```

### Parameter Value Formatting
```typescript
function formatParamValue(param: Parameter, value: unknown): string {
  switch (param.type) {
    case "Real":
      return formatReal(value as number);
    case "Int":
      return String(Math.round(value as number));
    case "Bool":
      return value ? "true" : "false";
    case "PipeGeometry":
      return formatPipeGeometry(value);
    case "Function":
      return formatFunctionParam(value);
    default:
      return String(value);
  }
}

function formatReal(n: number): string {
  const s = String(n);
  // Ensure Float64 literal (has decimal point)
  return s.includes(".") || s.includes("e") || s.includes("E")
    ? s
    : s + ".0";
}

function formatPipeGeometry(value: unknown): string {
  const geo = value as { type: string; L?: number; D?: number; W?: number; H?: number };
  if (geo.type === "circular") {
    return `PipeGeometry_circular(${formatReal(geo.L!)}, ${formatReal(geo.D!)})`;
  }
  return `PipeGeometry_rectangular(${formatReal(geo.L!)}, ${formatReal(geo.W!)}, ${formatReal(geo.H!)})`;
}

function formatFunctionParam(value: unknown): string {
  if (typeof value === "string") {
    return value; // bare identifier: dittus_boelter
  }
  if (typeof value === "object" && value !== null && (value as any).kind === "factory") {
    const fv = value as FactoryCorrelationValue;
    const args = Object.entries(fv.subParams)
      .map(([k, v]) => `${k}=${formatSubParamValue(v)}`)
      .join(", ");
    return `${fv.value}(${args})`;
  }
  return String(value);
}
```

### Tauri File Export
```typescript
import { save } from "@tauri-apps/plugin-dialog";
import { writeTextFile } from "@tauri-apps/plugin-fs";

async function exportCode(code: string): Promise<void> {
  const filePath = await save({
    defaultPath: "system.jl",
    filters: [{ name: "Julia files", extensions: ["jl"] }],
  });
  if (filePath) {
    await writeTextFile(filePath, code);
  }
}
```

### Tauri Plugin Registration (Rust)
```rust
// src-tauri/src/lib.rs
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .invoke_handler(tauri::generate_handler![greet])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

### Capabilities Configuration
```json
// src-tauri/capabilities/default.json
{
  "permissions": [
    "core:default",
    "opener:default",
    "dialog:default",
    "fs:default"
  ]
}
```

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Vitest (via vitest.config.ts) |
| Config file | `gui/vitest.config.ts` |
| Quick run command | `cd gui && npx vitest run --reporter verbose` |
| Full suite command | `cd gui && npx vitest run` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CODE-01 | Code preview updates on store changes | unit (code gen function) | `npx vitest run src/lib/codeGenerator.test.ts` | No -- Wave 0 |
| CODE-02 | Export writes file to disk | manual (Tauri-only API) | manual-only | N/A |
| CODE-03 | Positional vs keyword args correct | unit | `npx vitest run src/lib/codeGenerator.test.ts` | No -- Wave 0 |
| CODE-04 | connect() calls from edges | unit | `npx vitest run src/lib/codeGenerator.test.ts` | No -- Wave 0 |
| CODE-05 | ODESystem + mtkcompile boilerplate | unit | `npx vitest run src/lib/codeGenerator.test.ts` | No -- Wave 0 |
| CODE-06 | BC entries in generated code | unit | `npx vitest run src/lib/codeGenerator.test.ts` | No -- Wave 0 |
| CODE-07 | Invalid identifier warning in output | unit | `npx vitest run src/lib/codeGenerator.test.ts` | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** `cd gui && npx vitest run --reporter verbose`
- **Per wave merge:** `cd gui && npx vitest run`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `gui/src/lib/codeGenerator.test.ts` -- covers CODE-01, CODE-03..07 (pure function tests, node environment)
- [ ] No component render tests needed for bottom panel (manual verification sufficient; unit tests cover code gen logic)

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Node.js | GUI dev | Checked in prior phases | 18+ | -- |
| npm | Package install | Checked in prior phases | 9+ | -- |
| Cargo | Tauri plugin install | Checked in prior phases | -- | -- |
| tauri-plugin-dialog | CODE-02 (export) | Not installed | -- | Must install |
| tauri-plugin-fs | CODE-02 (file write) | Not installed | -- | Must install |
| shadcn Tabs | Bottom panel tabs | Not installed | -- | Must install via `npx shadcn@latest add tabs` |

**Missing dependencies with no fallback:**
- `tauri-plugin-dialog` and `tauri-plugin-fs` -- must be installed (npm + cargo + capability config)
- shadcn Tabs component -- must be added

## Sources

### Primary (HIGH confidence)
- `gui/src/registry/components.json` -- Full component definitions with positional flags, constructorModes, Function options
- `gui/src/registry/types.ts` -- TypeScript interfaces: Parameter, FactoryCorrelationValue, ConstructorMode
- `gui/src/store/useStore.ts` -- Current Zustand store structure, StreamNodeData interface
- `gui/src/lib/validation.ts` -- Existing validateJuliaIdentifier function
- `gui/src/components/sidebar/PipeGeometryPicker.tsx` -- PipeGeometryValue type definition (how geometry is stored)
- `gui/src/App.tsx` -- Current layout structure (3-panel flex row)
- `gui/src-tauri/capabilities/default.json` -- Current Tauri permissions
- `gui/src-tauri/src/lib.rs` -- Current Tauri plugin registration
- `gui/src-tauri/Cargo.toml` -- Current Rust dependencies

### Secondary (MEDIUM confidence)
- [Tauri Dialog Plugin v2](https://v2.tauri.app/plugin/dialog/) -- save() API, installation steps, permissions
- [Tauri FS Plugin v2](https://v2.tauri.app/reference/javascript/fs/) -- writeTextFile() API

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all libraries either already installed or well-documented Tauri plugins
- Architecture: HIGH -- code generator is a straightforward pure function; all input data structures already exist
- Pitfalls: HIGH -- identified from direct codebase inspection (PipeGeometry empty fields, BC node deletion, positional/keyword split)

**Research date:** 2026-04-02
**Valid until:** 2026-05-02 (stable -- no fast-moving dependencies)
