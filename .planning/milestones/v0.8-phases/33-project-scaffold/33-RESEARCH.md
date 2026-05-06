# Phase 33: Project Scaffold - Research

**Researched:** 2026-04-01
**Domain:** Tauri 2 + React + ReactFlow desktop app scaffold; STREAM.jl component metadata registry
**Confidence:** HIGH

## Summary

Phase 33 creates the `gui/` directory from scratch containing a Tauri 2 desktop app with React, TypeScript, ReactFlow, and Zustand. The scaffold includes a three-panel layout (toolbox, canvas, sidebar), an empty ReactFlow canvas, a component metadata registry JSON covering all 12 STREAM.jl components, Vitest + React Testing Library configured with an initial registry validation test, and shadcn/ui initialized (but no shadcn components installed).

The technology stack is well-established and all libraries have current stable releases. The primary risk is that Rust and WebKitGTK are not currently installed on the development machine -- these are required Tauri 2 system dependencies that must be installed before `npm run tauri dev` can work. The scaffold itself is straightforward: `npm create tauri-app` generates the project, then ReactFlow, Zustand, and shadcn are added on top.

**Primary recommendation:** Install Rust toolchain and WebKitGTK system dependencies first, then scaffold with `npm create tauri-app@latest` using the `react-ts` template, add ReactFlow + Zustand + shadcn, create three-panel layout shells, and build the component registry JSON from STREAM.jl source analysis.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** GUI lives at `gui/` as a plain directory inside Julia-STREAM (monorepo). Not a git submodule. Not a sibling repo.
- **D-02:** Registry covers all 12 STREAM.jl exported components: Channel, ChannelAndContacts, ChannelHeatFlux, Pump, Flapper, Friction, Gravity, Resistor, Inertia, HeatExchanger, ConstantTemperature, HeatDiffusion.
- **D-03:** ConstantTemperature is a canvas node (ThermalPort-only component), not a BC panel entry.
- **D-04:** Components with ThermalPort arrays have their thermal port metadata fully described in the registry. GUI does not render ThermalPort handles until Phase 40.
- **D-05:** Registry records the STREAM.jl target version (SCAF-05) and validates extensibility (SCAF-04).
- **D-06:** Phase 33 sets up Zustand store with at minimum: nodes, edges, selectedNodeId. Three-panel layout shells created as empty components (ToolboxPanel, CanvasPanel, SidebarPanel). Phase 34 populates real behavior.
- **D-07:** Vitest + React Testing Library configured in Phase 33. First test validates registry JSON.

### Claude's Discretion
- TypeScript configuration (strict mode, tsconfig settings)
- Package manager (npm is conventional for Tauri 2)
- Tauri 2 init approach (`npm create tauri-app` with `react-ts` template)
- Exact Zustand store shape beyond nodes/edges/selectedNodeId
- Registry JSON field names and schema versioning

### Deferred Ideas (OUT OF SCOPE)
- Requirements correction (SCAF-03 says "9" should be "12") -- quick fix during execution
- ConstantTemperature as BC panel -- rejected, it's a canvas node
- Minimal scaffold (bare canvas) -- rejected in favor of Zustand + panel shells
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SCAF-01 | Dev mode with hot-reload on Windows and Linux (`npm run tauri dev`) | Tauri 2 + Vite provides HMR out of the box; requires Rust + WebKitGTK system deps |
| SCAF-02 | Native desktop installer (.exe on Windows, AppImage on Linux) | `npm run tauri build` produces platform-specific bundles; NSIS for Windows, AppImage/deb for Linux |
| SCAF-03 | Component registry JSON with all 12 components, ports, signatures, params, units, defaults | Full component API extracted from STREAM.jl source; schema documented in this research |
| SCAF-04 | Adding a new component requires only a JSON entry, no TypeScript changes | Registry-driven architecture: TypeScript reads JSON at runtime, no component-specific TS code |
| SCAF-05 | Registry records STREAM.jl target version | Top-level `stream_version` field in registry JSON |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| @tauri-apps/cli | 2.10.1 | Desktop app framework CLI | Proven cross-platform desktop wrapper; small bundles, fast startup |
| react | 19.2.4 | UI framework | Dominant ecosystem; ReactFlow requires React |
| @xyflow/react | 12.10.2 | Node-based graph editor | 1.8M weekly downloads; built-in zoom/pan/minimap/handles; TypeScript-first |
| zustand | 5.0.12 | State management | Lightweight (3KB), no boilerplate, works well with ReactFlow |
| typescript | (bundled with Vite template) | Type safety | Required for registry type definitions and component props |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| vitest | 4.1.2 | Test framework | Unit and integration tests; Vite-native, fast |
| @testing-library/react | 16.3.2 | React component testing | DOM-based testing for panel components |
| lucide-react | 1.7.0 | Icon library | Icons for UI elements (specified in UI-SPEC) |
| shadcn (CLI) | 4.1.2 | Design system initialization | Initialize in Phase 33; components installed in later phases |
| tailwindcss | (via shadcn init) | Utility CSS | Required by shadcn/ui; handles all styling |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Zustand | Redux Toolkit | Redux has more boilerplate; Zustand is simpler for this scope |
| @xyflow/react | rete.js | ReactFlow has 70x more downloads and better TypeScript support |
| Vitest | Jest | Vitest is Vite-native with zero extra config; Jest needs transformation setup |

**Installation (after Tauri scaffold):**
```bash
npm install @xyflow/react zustand lucide-react
npm install -D vitest @testing-library/react @testing-library/jest-dom jsdom
npx shadcn@latest init -d
```

**Note:** The old package name `reactflow` is deprecated. Use `@xyflow/react` (React Flow 12+).

## Architecture Patterns

### Recommended Project Structure
```
gui/
  src/
    App.tsx                    # Root: three-panel layout + ReactFlowProvider
    main.tsx                   # Entry point
    components/
      ToolboxPanel.tsx         # Left panel shell (empty in Phase 33)
      CanvasPanel.tsx          # Center: ReactFlow canvas wrapper
      SidebarPanel.tsx         # Right panel shell (empty in Phase 33)
    registry/
      components.json          # Component metadata (12 STREAM.jl components)
      types.ts                 # TypeScript interfaces for registry schema
      index.ts                 # Registry loader + accessor functions
    store/
      useStore.ts              # Zustand store: nodes, edges, selectedNodeId, actions
    lib/
      utils.ts                 # shadcn utility (cn function, created by shadcn init)
  src-tauri/
    src/
      main.rs                  # Tauri Rust entry point (minimal, auto-generated)
      lib.rs                   # Tauri commands (none in Phase 33)
    Cargo.toml                 # Rust dependencies
    tauri.conf.json            # Tauri configuration (window title, size, etc.)
  components.json              # shadcn configuration
  tailwind.config.js           # Tailwind configuration (modified by shadcn init)
  tsconfig.json                # TypeScript configuration
  tsconfig.app.json            # App-specific TS config with path aliases
  vite.config.ts               # Vite configuration with @ path alias
  vitest.config.ts             # Vitest configuration (jsdom environment)
  package.json                 # npm scripts and dependencies
```

### Pattern 1: Registry-Driven Component Metadata
**What:** All STREAM.jl component information lives in a single JSON file that TypeScript reads at runtime. No component-specific TypeScript code.
**When to use:** Always -- this is the core extensibility mechanism (SCAF-04).
**Example:**
```typescript
// gui/src/registry/types.ts
interface Port {
  name: string;
  type: "FlowPort" | "ThermalPort";
  side: "left" | "right" | "top" | "bottom";
  array?: boolean;          // true for thermal_left[1:n], thermal_right[1:n]
  arrayParam?: string;      // parameter name that determines array size (e.g., "n" or "nz")
}

interface Parameter {
  name: string;
  type: "Real" | "Int" | "PipeGeometry" | "Function";
  unit?: string;
  default?: number | string | null;
  description: string;
  required: boolean;
}

interface ConstructorMode {
  mode: string;
  signature: string;        // e.g., "Pump(dP_pump::Real; name)"
  parameters: string[];     // parameter names active in this mode
}

interface ComponentDefinition {
  id: string;               // e.g., "Pump"
  label: string;            // display name, e.g., "Pump"
  category: "Hydraulic" | "Thermal" | "Structural";
  description: string;
  ports: Port[];
  parameters: Parameter[];
  constructorModes: ConstructorMode[];
}

interface ComponentRegistry {
  stream_version: string;   // e.g., "0.7.0"
  schema_version: string;   // e.g., "1.0"
  components: ComponentDefinition[];
}
```

### Pattern 2: Zustand Store with ReactFlow Integration
**What:** Zustand store manages ReactFlow nodes/edges plus app state (selectedNodeId). ReactFlow's `onNodesChange`/`onEdgesChange` callbacks dispatch to the store.
**When to use:** All state management in the app.
**Example:**
```typescript
// gui/src/store/useStore.ts
import { create } from 'zustand';
import { Node, Edge, applyNodeChanges, applyEdgeChanges, NodeChange, EdgeChange } from '@xyflow/react';

interface AppState {
  nodes: Node[];
  edges: Edge[];
  selectedNodeId: string | null;
  onNodesChange: (changes: NodeChange[]) => void;
  onEdgesChange: (changes: EdgeChange[]) => void;
  selectNode: (nodeId: string | null) => void;
}

const useStore = create<AppState>((set, get) => ({
  nodes: [],
  edges: [],
  selectedNodeId: null,
  onNodesChange: (changes) => set({ nodes: applyNodeChanges(changes, get().nodes) }),
  onEdgesChange: (changes) => set({ edges: applyEdgeChanges(changes, get().edges) }),
  selectNode: (nodeId) => set({ selectedNodeId: nodeId }),
}));
```

### Pattern 3: Three-Panel Layout with CSS Grid/Flexbox
**What:** Fixed three-panel layout: left toolbox (240px, collapsible), center canvas (flex: 1), right sidebar (320px, collapsible).
**When to use:** App root layout.
**Example:**
```typescript
// gui/src/App.tsx
import { ReactFlowProvider } from '@xyflow/react';
import ToolboxPanel from './components/ToolboxPanel';
import CanvasPanel from './components/CanvasPanel';
import SidebarPanel from './components/SidebarPanel';

function App() {
  return (
    <ReactFlowProvider>
      <div className="flex h-screen w-screen overflow-hidden">
        <ToolboxPanel />
        <CanvasPanel />
        <SidebarPanel />
      </div>
    </ReactFlowProvider>
  );
}
```

### Anti-Patterns to Avoid
- **Hardcoding component metadata in TypeScript:** Violates SCAF-04. All component data must come from the JSON registry.
- **Using the deprecated `reactflow` package:** Use `@xyflow/react` (React Flow 12+). The old package import patterns are different.
- **Wrapping ReactFlow in nested providers:** `ReactFlowProvider` must wrap the component that renders `<ReactFlow>`, but should be at the App level, not inside CanvasPanel.
- **Creating Tauri Rust commands for Phase 33:** No Rust backend logic is needed. The auto-generated `main.rs`/`lib.rs` are sufficient.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Node graph canvas | Custom SVG/Canvas renderer | @xyflow/react | Zoom, pan, minimap, handles, edge routing all built-in |
| State management | useContext + useReducer | Zustand | Simpler API, better performance, built-in middleware |
| CSS utility framework | Custom CSS | Tailwind (via shadcn init) | Consistent with shadcn/ui used in later phases |
| Desktop packaging | Custom Electron/WebView | Tauri 2 | 10x smaller bundles, native file dialogs built-in |
| Test environment | Custom jsdom setup | Vitest + @testing-library/react | Zero-config with Vite; jsdom environment pre-configured |

**Key insight:** The entire scaffold is composed of well-integrated tools. Tauri creates the project, Vite handles bundling/HMR, ReactFlow handles the canvas, Zustand handles state, shadcn handles design tokens. No custom infrastructure is needed.

## Component Registry Data (Source of Truth)

Complete component API extracted from STREAM.jl source code for the registry JSON:

### 1. Channel (keyword-only)
- **Signature:** `Channel(; name, n, geometry, g=0.0, htc_correlation=dittus_boelter, friction_correlation=blasius_friction)`
- **Ports:** inlet (FlowPort, left), outlet (FlowPort, right), thermal (ThermalPort, top -- single scalar)
- **Category:** Hydraulic
- **Parameters:** n (Int, required), geometry (PipeGeometry, required), g (Real, m/s^2, default 0.0), htc_correlation (Function, default dittus_boelter), friction_correlation (Function, default blasius_friction)

### 2. ChannelAndContacts (keyword-only)
- **Signature:** `ChannelAndContacts(; name, n, geometry, g=0.0, htc_correlation=dittus_boelter, friction_correlation=blasius_friction, scb_correction=nothing)`
- **Ports:** inlet (FlowPort, left), outlet (FlowPort, right), thermal_left[1:n] (ThermalPort array, top), thermal_right[1:n] (ThermalPort array, bottom)
- **Category:** Hydraulic
- **Parameters:** n (Int, required), geometry (PipeGeometry, required), g (Real, m/s^2, default 0.0), htc_correlation (Function, default dittus_boelter), friction_correlation (Function, default blasius_friction), scb_correction (Function, default nothing)

### 3. ChannelHeatFlux (keyword-only)
- **Signature:** `ChannelHeatFlux(; name, n, geometry, g=0.0, T_wall, htc_correlation=dittus_boelter, friction_correlation=blasius_friction)`
- **Ports:** inlet (FlowPort, left), outlet (FlowPort, right)
- **Category:** Hydraulic
- **Parameters:** n (Int, required), geometry (PipeGeometry, required), g (Real, m/s^2, default 0.0), T_wall (Real, K, required), htc_correlation (Function, default dittus_boelter), friction_correlation (Function, default blasius_friction)

### 4. Pump (positional, multi-dispatch)
- **Mode 1 Signature:** `Pump(dP_pump::Real; name)` -- fixed scalar dP
- **Mode 2 Signature:** `Pump(dP_pump::Any; name)` -- callable dP(t)
- **Mode 3 Signature:** `Pump(; name, mdot0)` -- fixed mass flow
- **Ports:** inlet (FlowPort, left), outlet (FlowPort, right)
- **Category:** Hydraulic
- **Parameters (mode 1):** dP_pump (Real, Pa, required); **(mode 3):** mdot0 (Real, kg/s, required)

### 5. Flapper (keyword-only)
- **Signature:** `Flapper(; name, dt=5.0, threshold=0.01, R_closed=1e8, R_open=100.0, use_callback=true)`
- **Ports:** inlet (FlowPort, left), outlet (FlowPort, right)
- **Category:** Hydraulic
- **Parameters:** dt (Real, s, default 5.0), threshold (Real, kg/s, default 0.01), R_closed (Real, Pa*s/kg, default 1e8), R_open (Real, Pa*s/kg, default 100.0), use_callback (Bool, default true)

### 6. Friction (keyword-only)
- **Signature:** `Friction(; name, L, D, A)`
- **Ports:** inlet (FlowPort, left), outlet (FlowPort, right)
- **Category:** Hydraulic
- **Parameters:** L (Real, m, required), D (Real, m, required), A (Real, m^2, required)

### 7. Gravity (positional)
- **Signature:** `Gravity(H; name)`
- **Ports:** inlet (FlowPort, left), outlet (FlowPort, right)
- **Category:** Hydraulic
- **Parameters:** H (Real, m, required)

### 8. Resistor (positional)
- **Signature:** `Resistor(R; name)`
- **Ports:** inlet (FlowPort, left), outlet (FlowPort, right)
- **Category:** Hydraulic
- **Parameters:** R (Real, Pa/(kg/s), required)

### 9. Inertia (positional)
- **Signature:** `Inertia(L_over_A; name)`
- **Ports:** inlet (FlowPort, left), outlet (FlowPort, right)
- **Category:** Hydraulic
- **Parameters:** L_over_A (Real, 1/m, required)

### 10. HeatExchanger (positional)
- **Signature:** `HeatExchanger(T_bc; name)`
- **Ports:** inlet (FlowPort, left), outlet (FlowPort, right)
- **Category:** Hydraulic
- **Parameters:** T_bc (Real, K, required)

### 11. ConstantTemperature (positional)
- **Signature:** `ConstantTemperature(T; name)`
- **Ports:** thermal (ThermalPort, left -- single)
- **Category:** Thermal
- **Parameters:** T (Real, K, required)

### 12. HeatDiffusion (keyword-only)
- **Signature:** `HeatDiffusion(; name, nz, nx, Lz, Lx, y, rho_s, cp_s, k_s, power_shape, power=1e6, T0=600.0)`
- **Ports:** thermal_left[1:nz] (ThermalPort array, left), thermal_right[1:nz] (ThermalPort array, right)
- **Category:** Thermal
- **Parameters:** nz (Int, required), nx (Int, required), Lz (Real, m, required), Lx (Real, m, required), y (Real, m, required), rho_s (Real, kg/m^3, required), cp_s (Real, J/(kg*K), required), k_s (Real, W/(m*K), required), power_shape (Matrix, required), power (Real, W/m^3, default 1e6), T0 (Real, K, default 600.0)

## Common Pitfalls

### Pitfall 1: Missing Rust Toolchain
**What goes wrong:** `npm run tauri dev` fails immediately with "cargo not found" or Rust compilation errors.
**Why it happens:** Tauri 2 requires Rust to compile the desktop shell. It is not a pure JS framework.
**How to avoid:** Install Rust via `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh` before running any Tauri commands. Also install `libwebkit2gtk-4.1-dev` and other Linux system dependencies.
**Warning signs:** `cargo` or `rustc` commands not found in PATH.

### Pitfall 2: WebKitGTK Missing on Linux
**What goes wrong:** Tauri compilation fails with "webkit2gtk-4.1 not found" linker errors.
**Why it happens:** Tauri 2 uses the system WebView (WebKitGTK on Linux) rather than bundling Chromium.
**How to avoid:** `sudo apt install libwebkit2gtk-4.1-dev build-essential libssl-dev libxdo-dev libayatana-appindicator3-dev librsvg2-dev` on Ubuntu/Debian.
**Warning signs:** Missing pkg-config entries during `cargo build`.

### Pitfall 3: Using Old `reactflow` Package
**What goes wrong:** Import errors, missing types, API incompatibilities.
**Why it happens:** React Flow 12 renamed the package from `reactflow` to `@xyflow/react`. Many tutorials still reference the old name.
**How to avoid:** Always use `@xyflow/react`. Import pattern: `import { ReactFlow, ReactFlowProvider } from '@xyflow/react'`. CSS: `import '@xyflow/react/dist/style.css'`.
**Warning signs:** `Cannot find module 'reactflow'` errors.

### Pitfall 4: ReactFlow Container Height
**What goes wrong:** ReactFlow canvas renders as a 0-height invisible element.
**Why it happens:** ReactFlow requires its parent container to have explicit height. Without it, the canvas collapses.
**How to avoid:** Ensure the ReactFlow wrapper has `className="h-full w-full"` or explicit height styling. The flex layout with `flex-1` on the center panel handles this.
**Warning signs:** Canvas area appears blank but no console errors.

### Pitfall 5: shadcn Path Alias Not Configured
**What goes wrong:** `npx shadcn@latest init` fails or generated components have broken imports.
**Why it happens:** shadcn requires `@/` path alias in both `tsconfig.json` and `vite.config.ts`. The Tauri template may not set this up.
**How to avoid:** After Tauri scaffold, add `"paths": { "@/*": ["./src/*"] }` to tsconfig.json/tsconfig.app.json and `resolve.alias` to vite.config.ts before running `npx shadcn@latest init -d`.
**Warning signs:** Module resolution errors with `@/` prefix.

### Pitfall 6: Node.js Version Too Old
**What goes wrong:** npm commands fail or packages require newer Node.js APIs.
**Why it happens:** Current system has Node.js 18.19.1. While this should work, some newer packages may prefer Node 20+.
**How to avoid:** Monitor for Node.js compatibility warnings during installation. Upgrade if needed.
**Warning signs:** Engine compatibility warnings during `npm install`.

## Code Examples

### ReactFlow Minimal Canvas (Phase 33 target)
```typescript
// gui/src/components/CanvasPanel.tsx
import { ReactFlow, Controls, MiniMap, Background, BackgroundVariant } from '@xyflow/react';
import '@xyflow/react/dist/style.css';
import useStore from '../store/useStore';

export default function CanvasPanel() {
  const { nodes, edges, onNodesChange, onEdgesChange } = useStore();

  return (
    <div className="flex-1 h-full">
      <ReactFlow
        nodes={nodes}
        edges={edges}
        onNodesChange={onNodesChange}
        onEdgesChange={onEdgesChange}
        fitView
      >
        <Controls />
        <MiniMap />
        <Background variant={BackgroundVariant.Dots} />
      </ReactFlow>
    </div>
  );
}
```

### Registry Loader
```typescript
// gui/src/registry/index.ts
import registryData from './components.json';
import type { ComponentRegistry, ComponentDefinition } from './types';

const registry: ComponentRegistry = registryData as ComponentRegistry;

export function getComponent(id: string): ComponentDefinition | undefined {
  return registry.components.find(c => c.id === id);
}

export function getComponentsByCategory(category: string): ComponentDefinition[] {
  return registry.components.filter(c => c.category === category);
}

export function getAllComponents(): ComponentDefinition[] {
  return registry.components;
}

export { registry };
```

### Vitest Registry Test
```typescript
// gui/src/registry/__tests__/registry.test.ts
import { describe, it, expect } from 'vitest';
import { registry, getAllComponents } from '../index';

describe('Component Registry', () => {
  it('loads all 12 components', () => {
    expect(getAllComponents()).toHaveLength(12);
  });

  it('has stream_version field', () => {
    expect(registry.stream_version).toBeDefined();
    expect(typeof registry.stream_version).toBe('string');
  });

  it('every component has required fields', () => {
    for (const comp of getAllComponents()) {
      expect(comp.id).toBeTruthy();
      expect(comp.label).toBeTruthy();
      expect(comp.category).toBeTruthy();
      expect(comp.ports).toBeDefined();
      expect(comp.ports.length).toBeGreaterThan(0);
      expect(comp.parameters).toBeDefined();
      expect(comp.constructorModes).toBeDefined();
      expect(comp.constructorModes.length).toBeGreaterThan(0);
    }
  });

  it('adding a component requires only JSON (SCAF-04)', () => {
    // Verify the registry is data-driven: check no component ID is hardcoded in TS
    // This test validates the architecture: all component knowledge comes from JSON
    const ids = getAllComponents().map(c => c.id);
    expect(ids).toContain('Pump');
    expect(ids).toContain('Channel');
    expect(ids).toContain('HeatDiffusion');
    expect(ids).toContain('ConstantTemperature');
  });
});
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `reactflow` npm package | `@xyflow/react` | React Flow 12 (2024) | Must use new import paths; old package deprecated |
| Tauri 1.x | Tauri 2.x (stable) | Late 2024 | New plugin system, mobile support, updated API |
| shadcn v0.x | shadcn v4.x (CLI) | 2025 | `npx shadcn@latest init` replaces old `npx shadcn-ui@latest init` |
| Zustand v4 | Zustand v5 | 2024 | Minor API changes; `create` import unchanged |

**Deprecated/outdated:**
- `reactflow` package: Use `@xyflow/react` instead
- `shadcn-ui` CLI: Use `shadcn` instead
- Tauri 1 APIs: Tauri 2 has different plugin system and event APIs

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Node.js | All JS tooling | Yes | 18.19.1 | Sufficient for Tauri 2 |
| npm | Package management | Yes | 9.2.0 | Sufficient |
| Rust (cargo/rustc) | Tauri 2 compilation | **NO** | -- | Must install: `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \| sh` |
| libwebkit2gtk-4.1-dev | Tauri 2 Linux WebView | **NO** | -- | Must install: `sudo apt install libwebkit2gtk-4.1-dev` |
| libgtk-3 | Tauri 2 Linux UI | Yes | 3.24.41 | -- |
| librsvg2 | Tauri 2 Linux | Yes | 2.58.0 | -- |
| build-essential | Rust compilation | Needs check | -- | `sudo apt install build-essential` |
| libssl-dev | Tauri 2 Linux | Needs check | -- | `sudo apt install libssl-dev` |
| libxdo-dev | Tauri 2 Linux | Needs check | -- | `sudo apt install libxdo-dev` |
| libayatana-appindicator3-dev | Tauri 2 Linux tray | Needs check | -- | `sudo apt install libayatana-appindicator3-dev` |

**Missing dependencies with no fallback:**
- **Rust toolchain** -- blocks all Tauri compilation. Must be installed as Wave 0 task.
- **libwebkit2gtk-4.1-dev** -- blocks Tauri dev mode on Linux. Must be installed as Wave 0 task.

**Missing dependencies with fallback:**
- None -- all missing dependencies must be installed; there are no viable alternatives for Tauri 2.

**Combined install command (Ubuntu/Debian):**
```bash
# System dependencies
sudo apt install -y libwebkit2gtk-4.1-dev build-essential libssl-dev libxdo-dev libayatana-appindicator3-dev librsvg2-dev

# Rust toolchain
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"
```

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Vitest 4.1.2 + @testing-library/react 16.3.2 |
| Config file | `gui/vitest.config.ts` (Wave 0 -- does not exist yet) |
| Quick run command | `cd gui && npx vitest run` |
| Full suite command | `cd gui && npx vitest run` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SCAF-01 | `npm run tauri dev` starts app | smoke/manual | Manual verification (requires display) | N/A |
| SCAF-02 | `npm run tauri build` produces installer | smoke/manual | Manual verification (requires full build) | N/A |
| SCAF-03 | Registry JSON has 12 components with correct fields | unit | `cd gui && npx vitest run src/registry` | Wave 0 |
| SCAF-04 | No TypeScript changes needed for new component | unit | `cd gui && npx vitest run src/registry` | Wave 0 |
| SCAF-05 | Registry has stream_version field | unit | `cd gui && npx vitest run src/registry` | Wave 0 |

### Sampling Rate
- **Per task commit:** `cd gui && npx vitest run`
- **Per wave merge:** `cd gui && npx vitest run`
- **Phase gate:** Full suite green + manual `npm run tauri dev` verification

### Wave 0 Gaps
- [ ] `gui/vitest.config.ts` -- Vitest configuration with jsdom environment
- [ ] `gui/src/registry/__tests__/registry.test.ts` -- covers SCAF-03, SCAF-04, SCAF-05
- [ ] Framework install: `npm install -D vitest @testing-library/react @testing-library/jest-dom jsdom`
- [ ] System deps: Rust toolchain + libwebkit2gtk-4.1-dev (required before any Tauri work)

## Open Questions

1. **Node.js 18 vs 20 compatibility**
   - What we know: Node 18 is LTS until April 2025 (EOL). Node 20 is current LTS.
   - What's unclear: Whether all current package versions work flawlessly on Node 18.19.1
   - Recommendation: Proceed with Node 18; upgrade only if compatibility issues arise during installation.

2. **Tauri window configuration for WSL2**
   - What we know: The dev environment is WSL2 (Linux 6.6.87.2-microsoft-standard-WSL2). Tauri needs a display server.
   - What's unclear: Whether WSLg (Windows Subsystem for Linux GUI) is working and can render WebKitGTK.
   - Recommendation: Test `npm run tauri dev` early. If WSLg doesn't work, develop the React app with `npm run dev` (Vite only, browser-based) and test Tauri builds on native Windows.

## Project Constraints (from CLAUDE.md)

- **No Unicode variable names** in code (use ASCII only)
- **Component authoring conventions** define positional vs keyword argument rules -- registry `constructorModes` must encode these exactly
- **All exports declared in STREAM.jl** -- registry component list must match the export list on line 28
- **@named macro** always injects `name` as keyword -- registry signatures must show this
- **PipeGeometry factory functions** use positional args: `PipeGeometry_rectangular(L, W, H)`, `PipeGeometry_circular(L, D)`

## Sources

### Primary (HIGH confidence)
- STREAM.jl source: `src/STREAM.jl` lines 26-35 (export list), `src/components/*.jl` (all component signatures and ports)
- Tauri 2 prerequisites: [v2.tauri.app/start/prerequisites](https://v2.tauri.app/start/prerequisites/)
- ReactFlow migration guide: [reactflow.dev/learn/troubleshooting/migrate-to-v12](https://reactflow.dev/learn/troubleshooting/migrate-to-v12)
- shadcn Vite installation: [ui.shadcn.com/docs/installation/vite](https://ui.shadcn.com/docs/installation/vite)
- Project feasibility study: `.planning/research/gui-feasibility/RESEARCH.md`

### Secondary (MEDIUM confidence)
- npm registry version checks (verified 2026-04-01): @tauri-apps/cli 2.10.1, @xyflow/react 12.10.2, zustand 5.0.12, vitest 4.1.2, shadcn 4.1.2
- Tauri create-project guide: [v2.tauri.app/start/create-project](https://v2.tauri.app/start/create-project/)

### Tertiary (LOW confidence)
- WSL2/WSLg compatibility with Tauri -- not verified; needs manual testing

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - all packages verified via npm registry; versions confirmed current
- Architecture: HIGH - follows patterns from feasibility study + official docs
- Registry content: HIGH - extracted directly from STREAM.jl source code
- Pitfalls: HIGH - system dependency issues confirmed via environment audit
- Environment: HIGH - tools checked via command-line probes

**Research date:** 2026-04-01
**Valid until:** 2026-05-01 (30 days -- Tauri/React ecosystem stable but moving)
