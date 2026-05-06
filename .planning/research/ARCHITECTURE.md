# Architecture Research: STREAM Composer GUI

**Domain:** Desktop GUI / Visual block-diagram editor / Julia code generator
**Researched:** 2026-04-01
**Confidence:** HIGH (architecture patterns well-established; Tauri 2 + ReactFlow are mature)

## System Overview

```
+-----------------------------------------------------------------------+
|                        Tauri 2 Desktop Shell                          |
|  (src-tauri/)         Rust: file I/O, native dialogs, app lifecycle   |
+-----------------------------------------------------------------------+
|                        React Frontend                                  |
|  +------------------+  +------------------+  +---------------------+  |
|  |  Toolbox Panel   |  |  ReactFlow       |  |  Parameter Sidebar  |  |
|  |  (component list)|  |  Canvas          |  |  (form generator)   |  |
|  |                  |  |  (nodes + edges) |  |                     |  |
|  +------------------+  +------------------+  +---------------------+  |
|                                                                       |
|  +------------------+  +------------------+  +---------------------+  |
|  |  Zustand Store   |  |  Code Generator  |  |  Validation Engine  |  |
|  |  (graph state,   |  |  (IR -> Julia)   |  |  (topology checks)  |  |
|  |   undo/redo)     |  |                  |  |                     |  |
|  +------------------+  +------------------+  +---------------------+  |
|                                                                       |
|  +------------------------------------------------------------------+ |
|  |  Component Registry  (components.json)                            | |
|  |  Source of truth for: ports, params, constructors, categories     | |
|  +------------------------------------------------------------------+ |
+-----------------------------------------------------------------------+
|                        Data Layer                                      |
|  .streamgui JSON files <-> Zustand state <-> Julia code strings       |
+-----------------------------------------------------------------------+
```

### Component Responsibilities

| Component | Responsibility | Implementation |
|-----------|----------------|----------------|
| Tauri Shell (`src-tauri/`) | Native window, file save/open dialogs, app packaging | Rust; minimal -- ~100 LOC of Tauri commands for file I/O |
| Component Registry | Maps STREAM.jl API to GUI node definitions | Static JSON loaded at startup; single source of truth |
| Zustand Store | All mutable app state: nodes, edges, params, selections, undo history | Zustand + Zundo middleware for undo/redo |
| ReactFlow Canvas | Visual node graph rendering, pan/zoom, edge drawing | ReactFlow with custom node types and typed handles |
| Toolbox Panel | Component palette grouped by category | Reads registry; drag events create new graph nodes |
| Parameter Sidebar | Dynamic form for selected node's parameters | Generated from registry schema; mode-aware (Pump toggle, PipeGeometry picker) |
| Code Generator | Transforms graph state into valid Julia code | Pure function: `GraphState -> string`. No side effects. |
| Validation Engine | Topology checks (unconnected ports, missing BC/driver) | Pure function on graph state; results rendered as alerts |
| Persistence Layer | Save/load .streamgui JSON; recent files; unsaved-changes guard | Tauri file commands + Zustand state serialization |

## Recommended Project Structure

The GUI lives in `gui/` at the repo root, alongside the existing Julia `src/` and `test/` directories. This keeps the two codebases sibling-level (not nested) with a clear boundary.

```
Julia-STREAM/
  src/                          # Existing Julia library (unchanged)
  test/                         # Existing Julia tests (unchanged)
  .planning/                    # Existing planning (unchanged)
  gui/                          # NEW: STREAM Composer GUI application
    package.json                # Node dependencies, scripts
    tsconfig.json               # TypeScript config
    vite.config.ts              # Vite bundler config
    tailwind.config.ts          # Tailwind CSS config
    components.json             # shadcn/ui components config
    index.html                  # Vite entry
    src-tauri/                  # Tauri 2 Rust backend
      Cargo.toml                # Rust dependencies
      tauri.conf.json           # Tauri app config (name, window, bundle)
      capabilities/
        default.json            # Tauri 2 capability permissions
      src/
        main.rs                 # Tauri entry point
        lib.rs                  # Tauri command handlers (file I/O)
    src/                        # React frontend
      main.tsx                  # React entry point
      App.tsx                   # Root component: three-panel layout
      registry/
        components.json         # Component metadata registry (THE contract)
        types.ts                # TypeScript types for registry schema
        loader.ts               # Registry loader + validation
      store/
        index.ts                # Zustand store: nodes, edges, params
        types.ts                # Store state types
        actions.ts              # Store actions (addNode, connect, etc.)
        selectors.ts            # Derived state (selected node, validation)
        history.ts              # Zundo undo/redo middleware config
      components/
        canvas/
          Canvas.tsx            # ReactFlow wrapper with custom config
          StreamNode.tsx        # Generic custom node (renders from registry)
          FlowPortHandle.tsx    # FlowPort handle (typed, validated)
          ThermalPortHandle.tsx # ThermalPort array handle (indexed)
          StreamEdge.tsx        # Custom edge component
        toolbox/
          Toolbox.tsx           # Left panel: component palette
          ToolboxItem.tsx       # Draggable component card
        sidebar/
          Sidebar.tsx           # Right panel: parameter editor
          ParameterField.tsx    # Generic field renderer (number, enum, etc.)
          PipeGeometryPicker.tsx  # Circular vs rectangular selector + fields
          PumpModePicker.tsx    # Fixed-dP vs fixed-mdot toggle
          BoundaryConditions.tsx  # Pressure anchor, thermal pins
        codegen/
          CodePreview.tsx       # Bottom/tab panel: live Julia code display
          ExportButton.tsx      # Export to .jl file via Tauri dialog
        validation/
          AlertBanner.tsx       # Non-blocking topology alert
          PortWarning.tsx       # Visual indicator on unconnected ports
        layout/
          ThreePanel.tsx        # Main layout: toolbox | canvas | sidebar
          MenuBar.tsx           # File menu (New, Open, Save, Export)
      codegen/
        generator.ts           # Core: GraphState -> Julia code string
        templates.ts           # Per-component code templates
        boundary-conditions.ts # BC code generation
        thermal-helpers.ts     # symmetric_plate / plate detection + codegen
        validators.ts          # Julia identifier validation
      validation/
        topology.ts            # Graph topology analysis
        rules.ts               # Validation rules (unconnected, no driver, no BC)
      hooks/
        useCodePreview.ts      # Debounced code generation hook
        useProjectFile.ts      # Save/load/recent-files hook
        useValidation.ts       # Live validation hook
      lib/
        tauri-commands.ts      # TypeScript wrappers for Tauri invoke() calls
        utils.ts               # General utilities
      styles/
        globals.css             # Tailwind base + shadcn/ui theme
```

### Structure Rationale

- **`gui/` at repo root:** Not inside `src/` (that is Julia). Not a separate repo (shared planning, shared git history). The `gui/` directory is self-contained -- `cd gui && npm run tauri dev` works standalone.
- **`registry/components.json`:** The coupling contract between STREAM.jl and the GUI. When STREAM.jl adds a new component, someone adds a JSON entry here. No TypeScript changes needed (SCAF-04).
- **`store/` with Zustand:** ReactFlow uses Zustand internally; using it for app state avoids a second state library. Zundo provides undo/redo for free.
- **`codegen/` separate from `components/`:** Code generation is a pure data transformation, not a UI concern. Testable without rendering.
- **`validation/` separate from `codegen/`:** Validation runs continuously on graph state. Code generation runs on demand. Different update frequencies, different concerns.
- **Custom nodes per port type, not per component:** One `StreamNode.tsx` renders ALL component types by reading registry metadata. Only port handles are specialized (FlowPort vs ThermalPort array).

## Architectural Patterns

### Pattern 1: Registry-Driven Node Rendering

**What:** A single `StreamNode` React component renders all STREAM.jl components by reading their definition from `components.json` at runtime. No per-component TSX files.
**When to use:** Always -- this is the core pattern that enables SCAF-04 (add component via JSON only).
**Trade-offs:** Slightly more complex node component (must handle all cases), but eliminates N separate component files and guarantees consistency.

**Example:**
```tsx
// StreamNode.tsx -- one component renders all STREAM.jl types
function StreamNode({ data }: NodeProps<StreamNodeData>) {
  const def = registry.get(data.componentType); // e.g., "Pump"
  return (
    <div className={`stream-node stream-node--${def.category}`}>
      <div className="stream-node__header">{data.label}</div>
      {Object.entries(def.ports).map(([name, port]) => (
        <Handle
          key={name}
          type={port.direction === 'in' ? 'target' : 'source'}
          position={port.side}
          id={name}
          className={`handle--${port.portType}`}
        />
      ))}
    </div>
  );
}
```

### Pattern 2: Immutable Graph State with Zustand + Zundo

**What:** All graph mutations go through Zustand actions. Zundo wraps the store to provide undo/redo by snapshotting state on each action.
**When to use:** All state changes (add node, delete, connect, rename, change param).
**Trade-offs:** Slightly more memory usage (undo history), but provides CANV-07 (undo/redo) essentially for free. ReactFlow already uses Zustand internally, so no conceptual overhead.

**Example:**
```ts
// store/index.ts
import { create } from 'zustand';
import { temporal } from 'zundo';

interface AppState {
  nodes: Node[];
  edges: Edge[];
  selectedNodeId: string | null;
  projectPath: string | null;
  isDirty: boolean;
  // actions
  addNode: (type: string, position: XYPosition) => void;
  deleteNode: (id: string) => void;
  updateNodeParam: (nodeId: string, param: string, value: any) => void;
  onNodesChange: OnNodesChange;
  onEdgesChange: OnEdgesChange;
  onConnect: OnConnect;
}

export const useAppStore = create<AppState>()(
  temporal(
    (set, get) => ({
      nodes: [],
      edges: [],
      selectedNodeId: null,
      // ... actions that call set()
    }),
    { limit: 50 } // undo history depth
  )
);
```

### Pattern 3: Pure-Function Code Generation Pipeline

**What:** Code generation is a deterministic pure function: `(nodes, edges, boundaryConditions, registry) -> string`. No side effects, no DOM, no React. Lives in `codegen/generator.ts`, fully unit-testable.
**When to use:** Always -- code generation must be trustworthy. Purity enables exhaustive testing.
**Trade-offs:** Requires the complete graph state as input (no shortcuts via component refs), which is actually a benefit for testability.

**Example:**
```ts
// codegen/generator.ts
export function generateJuliaCode(
  nodes: StreamNode[],
  edges: StreamEdge[],
  bcs: BoundaryCondition[],
  registry: ComponentRegistry
): string {
  const sections = [
    generateImports(),
    generateComponentDeclarations(nodes, registry),
    generateConnections(edges, nodes, registry),
    generateBoundaryConditions(bcs, nodes),
    generateComposition(nodes),
    generateCompile(),
  ];
  return sections.join('\n\n');
}
```

### Pattern 4: Connection Validation via Handle Typing

**What:** ReactFlow handles carry a `data-port-type` attribute ("FlowPort" or "ThermalPort"). The `isValidConnection` callback rejects cross-type connections (FlowPort to ThermalPort) and same-direction connections (out to out).
**When to use:** Always -- prevents invalid topology at draw time rather than after-the-fact validation.
**Trade-offs:** Slightly more handle setup, but eliminates an entire class of user errors.

**Example:**
```ts
const isValidConnection = useCallback((connection: Connection) => {
  const sourcePort = getPortDef(connection.source, connection.sourceHandle);
  const targetPort = getPortDef(connection.target, connection.targetHandle);
  // Must be same port type (FlowPort<->FlowPort, ThermalPort<->ThermalPort)
  if (sourcePort.portType !== targetPort.portType) return false;
  // Must connect out->in (source handle is output, target handle is input)
  if (sourcePort.direction !== 'out' || targetPort.direction !== 'in') return false;
  return true;
}, []);
```

## Data Flow

### Primary Data Flow: Canvas to Julia Code

```
User drags Pump from Toolbox
    |
    v
Zustand action: addNode("Pump", {x, y})
    |
    v
Store updates nodes[] array (Zundo snapshots for undo)
    |
    v
ReactFlow re-renders canvas (new Pump node appears)
    |
    v (simultaneously)
useCodePreview hook fires (debounced 300ms)
    |
    v
generateJuliaCode(nodes, edges, bcs, registry)
    |
    v
Code preview panel shows updated Julia code
```

### Graph State to Julia Code: Translation Algorithm

The code generator translates graph state through 3 stages:

**Stage 1: Component Instantiation**

For each node in the graph, emit an `@named` constructor call using the registry's constructor template:

```
Node { type: "Pump", name: "pump1", params: { dP_pump: 30000 }, mode: "fixed_dP" }
  -->  @named pump1 = Pump(30000.0)

Node { type: "Channel", name: "ch1", params: { n: 10 }, geometry: { type: "circular", L: 0.6, D: 0.01 } }
  -->  @named ch1 = Channel(n=10, geometry=PipeGeometry_circular(0.6, 0.01))
```

**Stage 2: Connections**

For each edge, emit a `connect()` call. The source/target handles map directly to STREAM.jl port names:

```
Edge { source: "pump1", sourceHandle: "port_out", target: "ch1", targetHandle: "port_in" }
  -->  connect(pump1.port_out, ch1.port_in)
```

For thermal connections (Phase 40), detect topology patterns and emit composition helper calls instead of raw connect():

```
If HeatDiffusion.thermal_left[1:n] all connect to CAC.thermal_right[1:n]
AND HeatDiffusion.thermal_right[1:n] all connect to CAC.thermal_left[1:n]
  -->  symmetric_plate(cac, fuel; name=:assembly)
```

**Stage 3: Boundary Conditions + Composition**

Emit the BC equations, compose() call, and mtkcompile():

```julia
connections = [
    connect(pump1.port_out, ch1.port_in),
    # ... more connections
    pump1.port_in.P ~ 1.0e5,          # pressure anchor
]
@named sys = compose(System(connections, t), pump1, ch1)
ssys = mtkcompile(sys)
```

### JSON Intermediate Representation (.streamgui format)

The `.streamgui` file is the complete serializable graph state:

```json
{
  "version": "0.8.0",
  "streamjl_version": "0.7.0",
  "nodes": [
    {
      "id": "node-1",
      "type": "Pump",
      "position": { "x": 100, "y": 200 },
      "data": {
        "label": "pump1",
        "mode": "fixed_dP",
        "params": { "dP_pump": 30000.0 }
      }
    },
    {
      "id": "node-2",
      "type": "Channel",
      "position": { "x": 400, "y": 200 },
      "data": {
        "label": "ch1",
        "params": { "n": 10, "g": 0.0 },
        "geometry": {
          "type": "circular",
          "L": 0.6,
          "D": 0.01
        }
      }
    }
  ],
  "edges": [
    {
      "id": "edge-1",
      "source": "node-1",
      "sourceHandle": "port_out",
      "target": "node-2",
      "targetHandle": "port_in"
    }
  ],
  "boundaryConditions": [
    { "type": "pressure_anchor", "nodeId": "node-1", "port": "port_in", "value": 100000.0 }
  ]
}
```

### State Management Flow

```
User interaction (drag, connect, edit param)
    |
    v
Zustand store action (with Zundo snapshotting)
    |
    +---> ReactFlow re-render (visual update)
    +---> useCodePreview recalculates (Julia code preview)
    +---> useValidation rechecks (topology alerts)
    +---> isDirty flag set to true (unsaved changes guard)
```

## Component Metadata Registry Schema

This is the central contract between STREAM.jl and the GUI. One JSON file defines everything the GUI needs to know about each component.

### Full Schema Definition

```typescript
// registry/types.ts

interface ComponentRegistry {
  version: string;               // STREAM.jl version this registry targets
  components: ComponentDef[];
}

interface ComponentDef {
  id: string;                    // e.g., "Pump", "Channel", "HeatDiffusion"
  label: string;                 // Display name
  category: "Hydraulic" | "Thermal" | "Utility";
  description: string;           // Tooltip / sidebar header
  ports: Record<string, PortDef>;
  parameters: ParameterDef[];
  constructorModes?: ConstructorMode[];  // multi-dispatch components (Pump)
  geometry?: GeometryConfig;     // components that accept PipeGeometry
}

interface PortDef {
  portType: "FlowPort" | "ThermalPort";
  direction: "in" | "out";
  side: "left" | "right" | "top" | "bottom";
  isArray?: boolean;             // true for thermal_left[1:n], thermal_right[1:n]
  arrayParam?: string;           // which param controls array size, e.g., "n"
}

interface ParameterDef {
  name: string;                  // Julia kwarg name
  type: "number" | "integer" | "enum" | "boolean";
  unit?: string;                 // display unit, e.g., "Pa", "K", "m"
  default?: number | string | boolean;
  description: string;
  min?: number;                  // physical range validation
  max?: number;
  required: boolean;
  showWhen?: string;             // conditional: show only in certain modes
}

interface ConstructorMode {
  id: string;                    // e.g., "fixed_dP", "fixed_mdot"
  label: string;                 // e.g., "Fixed Pressure", "Fixed Flow"
  signature: string;             // e.g., "Pump(dP_pump; name)" for display
  codeTemplate: string;          // e.g., "Pump({dP_pump})" with param substitution
  parameters: string[];          // which ParameterDef.name values are active
}

interface GeometryConfig {
  paramName: string;             // "geometry" (the Julia kwarg name)
  options: GeometryOption[];
}

interface GeometryOption {
  id: string;                    // "circular" | "rectangular"
  label: string;
  factory: string;               // "PipeGeometry_circular" | "PipeGeometry_rectangular"
  fields: GeometryField[];
}

interface GeometryField {
  name: string;                  // positional arg name in factory
  label: string;
  unit: string;
  default: number;
}
```

### Registry Instance Examples (hardest 3 components)

**Pump (multi-mode dispatch):**
```json
{
  "id": "Pump",
  "label": "Pump",
  "category": "Hydraulic",
  "description": "Fixed-pressure or fixed-flow driving element",
  "ports": {
    "port_in":  { "portType": "FlowPort", "direction": "in",  "side": "left" },
    "port_out": { "portType": "FlowPort", "direction": "out", "side": "right" }
  },
  "parameters": [
    { "name": "dP_pump", "type": "number", "unit": "Pa", "default": 30000,
      "description": "Pressure rise", "required": true, "showWhen": "fixed_dP" },
    { "name": "mdot0", "type": "number", "unit": "kg/s", "default": 0.5,
      "description": "Fixed mass flow rate", "required": true, "showWhen": "fixed_mdot" }
  ],
  "constructorModes": [
    { "id": "fixed_dP", "label": "Fixed Pressure",
      "signature": "Pump(dP_pump; name)",
      "codeTemplate": "Pump({dP_pump})",
      "parameters": ["dP_pump"] },
    { "id": "fixed_mdot", "label": "Fixed Flow",
      "signature": "Pump(; name, mdot0)",
      "codeTemplate": "Pump(; mdot0={mdot0})",
      "parameters": ["mdot0"] }
  ]
}
```

**Channel (PipeGeometry + optional kwargs):**
```json
{
  "id": "Channel",
  "label": "Channel",
  "category": "Hydraulic",
  "description": "Single-phase convective channel with n axial cells",
  "ports": {
    "port_in":  { "portType": "FlowPort", "direction": "in",  "side": "left" },
    "port_out": { "portType": "FlowPort", "direction": "out", "side": "right" },
    "thermal":  { "portType": "ThermalPort", "direction": "in", "side": "top" }
  },
  "parameters": [
    { "name": "n", "type": "integer", "default": 10,
      "description": "Number of axial cells", "required": true, "min": 1 },
    { "name": "g", "type": "number", "unit": "m/s^2", "default": 0.0,
      "description": "Gravitational acceleration", "required": false }
  ],
  "geometry": {
    "paramName": "geometry",
    "options": [
      { "id": "circular", "label": "Circular Pipe",
        "factory": "PipeGeometry_circular",
        "fields": [
          { "name": "L", "label": "Length", "unit": "m", "default": 0.6 },
          { "name": "D", "label": "Diameter", "unit": "m", "default": 0.01 }
        ] },
      { "id": "rectangular", "label": "Rectangular Channel",
        "factory": "PipeGeometry_rectangular",
        "fields": [
          { "name": "L", "label": "Length", "unit": "m", "default": 0.6 },
          { "name": "edge1", "label": "Edge 1 (width)", "unit": "m", "default": 0.066 },
          { "name": "edge2", "label": "Edge 2 (gap)", "unit": "m", "default": 0.00235 },
          { "name": "heated_edge", "label": "Heated edge", "unit": "m", "default": 0.062 }
        ] }
    ]
  }
}
```

**ChannelAndContacts (ThermalPort arrays):**
```json
{
  "id": "ChannelAndContacts",
  "label": "Channel & Contacts",
  "category": "Thermal",
  "description": "Channel with per-cell ThermalPort arrays for fuel plate coupling",
  "ports": {
    "port_in":  { "portType": "FlowPort", "direction": "in",  "side": "left" },
    "port_out": { "portType": "FlowPort", "direction": "out", "side": "right" },
    "thermal_left":  { "portType": "ThermalPort", "direction": "in", "side": "top",
                       "isArray": true, "arrayParam": "n" },
    "thermal_right": { "portType": "ThermalPort", "direction": "in", "side": "bottom",
                       "isArray": true, "arrayParam": "n" }
  },
  "parameters": [
    { "name": "n", "type": "integer", "default": 10,
      "description": "Number of axial cells", "required": true, "min": 1 },
    { "name": "g", "type": "number", "unit": "m/s^2", "default": 0.0,
      "description": "Gravitational acceleration", "required": false }
  ],
  "geometry": {
    "paramName": "geometry",
    "options": [
      { "id": "circular", "label": "Circular Pipe",
        "factory": "PipeGeometry_circular",
        "fields": [
          { "name": "L", "label": "Length", "unit": "m", "default": 0.6 },
          { "name": "D", "label": "Diameter", "unit": "m", "default": 0.01 }
        ] },
      { "id": "rectangular", "label": "Rectangular Channel",
        "factory": "PipeGeometry_rectangular",
        "fields": [
          { "name": "L", "label": "Length", "unit": "m", "default": 0.6 },
          { "name": "edge1", "label": "Edge 1 (width)", "unit": "m", "default": 0.066 },
          { "name": "edge2", "label": "Edge 2 (gap)", "unit": "m", "default": 0.00235 },
          { "name": "heated_edge", "label": "Heated edge", "unit": "m", "default": 0.062 }
        ] }
    ]
  }
}
```

### All 12 Components Coverage

| Component | Category | Ports | PipeGeometry | Modes | Complexity |
|-----------|----------|-------|-------------|-------|------------|
| Pump | Hydraulic | 2 FlowPort | No | fixed_dP, fixed_mdot | High (multi-mode) |
| Channel | Hydraulic | 2 FlowPort + 1 ThermalPort | Yes | None | Medium (geometry) |
| ChannelHeatFlux | Hydraulic | 2 FlowPort | Yes | None | Medium (geometry + T_wall param) |
| ChannelAndContacts | Thermal | 2 FlowPort + 2 ThermalPort arrays | Yes | None | High (array ports) |
| HeatDiffusion | Thermal | 2 ThermalPort arrays | No (own Lz,Lx,y) | None | High (many params) |
| HeatExchanger | Utility | 2 FlowPort | No | None | Low |
| Resistor | Hydraulic | 2 FlowPort | No | None | Low |
| Gravity | Hydraulic | 2 FlowPort | No | None | Low |
| Inertia | Hydraulic | 2 FlowPort | No | None | Low |
| Friction | Hydraulic | 2 FlowPort | No | None | Low |
| Flapper | Hydraulic | 2 FlowPort | No | None | Medium (many params) |
| ConstantTemperature | Thermal | 1 ThermalPort | No | None | Low |

### Constructor Signatures for Code Generation (from STREAM.jl source)

These are the exact Julia signatures the code generator must produce. Positional vs keyword follows CLAUDE.md conventions:

| Component | Signature | Code Template |
|-----------|-----------|---------------|
| Pump (fixed-dP) | `Pump(dP_pump::Real; name)` | `Pump({dP_pump})` |
| Pump (fixed-mdot) | `Pump(; name, mdot0)` | `Pump(; mdot0={mdot0})` |
| Channel | `Channel(; name, n, geometry, g=0.0)` | `Channel(n={n}, geometry={geometry}, g={g})` |
| ChannelHeatFlux | `ChannelHeatFlux(; name, n, geometry, g=0.0, T_wall)` | `ChannelHeatFlux(n={n}, geometry={geometry}, T_wall={T_wall})` |
| ChannelAndContacts | `ChannelAndContacts(; name, n, geometry, g=0.0)` | `ChannelAndContacts(n={n}, geometry={geometry})` |
| HeatDiffusion | `HeatDiffusion(; name, nz, nx, Lz, Lx, y, rho_s, cp_s, k_s, power_shape, power)` | (all kwargs) |
| HeatExchanger | `HeatExchanger(T_bc; name)` | `HeatExchanger({T_bc})` |
| Resistor | `Resistor(R; name)` | `Resistor({R})` |
| Gravity | `Gravity(H; name)` | `Gravity({H})` |
| Inertia | `Inertia(L_over_A; name)` | `Inertia({L_over_A})` |
| Friction | `Friction(; name, L, D, A)` | `Friction(; L={L}, D={D}, A={A})` |
| Flapper | `Flapper(; name, dt, threshold, R_closed, R_open)` | `Flapper(; ...)` |
| ConstantTemperature | `ConstantTemperature(T; name)` | `ConstantTemperature({T})` |

## Anti-Patterns

### Anti-Pattern 1: Per-Component TSX Files

**What people do:** Create `PumpNode.tsx`, `ChannelNode.tsx`, `ResistorNode.tsx` -- one React component per STREAM.jl component type.
**Why it's wrong:** Violates SCAF-04 (add component via JSON only). Every new component requires a new TSX file, new imports, new registration. 12 components = 12 files doing nearly identical things.
**Do this instead:** One `StreamNode.tsx` that reads the registry definition and renders ports/labels dynamically. Port handles are specialized by type (FlowPort vs ThermalPort), not by parent component.

### Anti-Pattern 2: Embedding Julia in the GUI Process

**What people do:** Use `child_process` or libjulia to validate/run Julia code from within the Tauri app.
**Why it's wrong:** Julia TTFX is 10-30 seconds for STREAM.jl. Every validation round-trip freezes the UI. Process management adds complexity (zombie processes, platform-specific IPC, error marshalling). The GUI becomes fragile when Julia is not installed.
**Do this instead:** Generate .jl files only. The user runs Julia separately. Defer live validation to v0.9+ with Oxygen.jl HTTP server (explicit separate process).

### Anti-Pattern 3: Code Generation via String Concatenation

**What people do:** Build Julia code with `+=` string concatenation scattered across multiple files.
**Why it's wrong:** Impossible to test individual sections. Whitespace/newline bugs. No separation between "what to generate" and "how to format it".
**Do this instead:** Generate code in structured sections (imports, declarations, connections, BCs, composition), each as a pure function returning a string. Assemble sections in one place. Test each section independently.

### Anti-Pattern 4: Storing Registry in TypeScript Objects

**What people do:** Define component metadata as TypeScript constants (e.g., `const PUMP_DEF = { ... }`) scattered across source files.
**Why it's wrong:** Violates SCAF-04. Adding a component requires TypeScript code changes and recompilation. Non-developers cannot update the registry.
**Do this instead:** Single `components.json` file loaded at runtime. TypeScript types validate the schema at build time but the data lives in JSON.

### Anti-Pattern 5: Direct ReactFlow State Mutation

**What people do:** Use `useNodesState()` and `useEdgesState()` hooks directly, passing callbacks through node data props.
**Why it's wrong:** Fine for small demos, but as the app grows, passing update functions through node `data` props creates prop-drilling and makes undo/redo impossible without manual implementation.
**Do this instead:** Zustand store owns all state. ReactFlow is a controlled component receiving `nodes` and `edges` from the store. Actions go through store methods. Zundo wraps the store for free undo/redo.

## Integration Points

### External Boundaries

| Boundary | Direction | Contract | Notes |
|----------|-----------|----------|-------|
| GUI <-> STREAM.jl | GUI reads STREAM.jl API via registry JSON | `components.json` defines ports, params, constructors | Updated manually when STREAM.jl API changes |
| GUI <-> File System | Save/load .streamgui, export .jl | Tauri `dialog` + `fs` plugins | Native file dialogs via Tauri commands |
| GUI <-> User's Julia | User opens exported .jl in their Julia REPL | Generated .jl file is the only artifact | No runtime coupling; GUI works without Julia installed |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| React <-> Tauri Rust | `invoke()` IPC for file save/open/export | Only 3-4 Tauri commands total; minimal Rust |
| Store <-> ReactFlow | Zustand state -> ReactFlow props | Controlled component pattern; store is single source of truth |
| Store <-> Code Generator | Store state -> pure function -> string | Generator subscribes to store changes via hook; debounced |
| Store <-> Validation | Store state -> pure function -> alerts | Same pattern as code generator; different output |
| Registry <-> All UI | Static JSON loaded once at startup | Toolbox reads it for palette, nodes read it for ports, sidebar reads it for forms, codegen reads it for templates |

## Phase Build Order (33-40) with Rationale

### Dependency Graph

```
Phase 33 (Scaffold)
    |
    v
Phase 34 (Canvas + Nodes)
    |
    +-----> Phase 39 (Topology Validation) -- only needs nodes + edges
    |
    v
Phase 35 (Parameter Editing)
    |
    v
Phase 36 (Code Generation)
    |
    +-----> Phase 40 (Thermal Composition) -- needs codegen for helper detection
    |
    v
Phase 37 (Persistence)

Phase 38 (UI Design Pass) -- retrofits all prior phases
```

### Recommended Order

| Order | Phase | Rationale |
|-------|-------|-----------|
| 1 | **33: Scaffold** | Foundation. No other phase can start without Tauri + React + ReactFlow running. Registry JSON is defined here and consumed by all subsequent phases. |
| 2 | **34: Canvas & Nodes** | Core interaction. Nodes and edges are the data that every other feature operates on. Must work before params, codegen, or validation. |
| 3 | **35: Parameter Editing** | Builds on nodes. Sidebar reads node data; PipeGeometry picker and Pump mode toggle require registry-driven forms. Needed before codegen because generated code needs param values. |
| 4 | **36: Code Generation** | Builds on params. This is the product's core value prop: graph -> Julia code. Requires nodes, edges, and parameter values to be complete. |
| 5 | **37: Persistence** | Builds on codegen. Save/load serializes the same state that codegen reads. Placing it after codegen means saved projects include all parameter and BC data. |
| 6 | **38: UI Design Pass** | Retrofit. Replaces any placeholder styling with shadcn/ui throughout. Must happen after all functional UI exists but before shipping. |
| 7 | **39: Topology Validation** | Depends only on Phase 34 (graph structure), but is lower priority than core features. Placed here because it is a polish feature that adds alerts to an already-working app. |
| 8 | **40: Thermal Composition** | Hardest phase. Requires Phase 34 (canvas with array port handles), Phase 36 (code generation with helper detection), and understanding of STREAM.jl's composition helpers. Last because it is the most specialized feature. |

**Why this order works:**
- Each phase produces immediately testable output (scaffold runs, canvas draws, params edit, code generates, files save).
- The UI design pass (38) comes late so it retrofits a complete functional app rather than polishing incomplete screens.
- Validation (39) and thermal (40) are independent of each other and can be parallelized if needed.
- The strict dependency chain is 33 -> 34 -> 35 -> 36 -> 37; phases 38, 39, 40 branch off.

## Scaling Considerations

| Concern | Small system (5 nodes) | Medium system (20 nodes) | Large system (50+ nodes) |
|---------|----------------------|-------------------------|--------------------------|
| Canvas performance | No issue | No issue | ReactFlow handles 1000+ nodes; no concern |
| Code generation speed | Instant (<1ms) | Instant (<5ms) | Still fast (<50ms); pure string ops |
| Undo/redo memory | Negligible | ~1MB for 50 snapshots | ~5MB; set Zundo limit to 50 |
| .streamgui file size | <5KB | <20KB | <100KB; JSON compression not needed |
| Registry load time | Instant | N/A (fixed at 12 components) | N/A |

The GUI is a code generator for a domain with 12 component types. Scaling is not a concern.

## Sources

- [Tauri 2 Project Structure](https://v2.tauri.app/start/project-structure/) -- official directory layout
- [ReactFlow State Management Guide](https://reactflow.dev/learn/advanced-use/state-management) -- Zustand integration pattern
- [ReactFlow useNodesState](https://reactflow.dev/api-reference/hooks/use-nodes-state) -- built-in state hooks
- [Tauri + React production template](https://github.com/dannysmith/tauri-template) -- reference structure for best practices
- [Synergy Codes: State management in React Flow](https://www.synergycodes.com/blog/state-management-in-react-flow) -- Zustand + ReactFlow patterns
- STREAM.jl source: `src/STREAM.jl` (exports), `src/components/*.jl` (constructor signatures), `src/composition/helpers.jl` (thermal wiring patterns)
- STREAM.jl examples: `src/examples.jl` (code generation target format -- build_loop, build_cube)
- `.planning/research/gui-feasibility/RESEARCH.md` -- prior feasibility study (2026-03-31)

---
*Architecture research for: STREAM Composer GUI (v0.8)*
*Researched: 2026-04-01*
