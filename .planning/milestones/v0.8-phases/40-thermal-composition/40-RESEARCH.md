# Phase 40: Thermal Composition - Research

**Researched:** 2026-04-03
**Domain:** ReactFlow canvas thermal port rendering + pattern-based Julia code generation
**Confidence:** HIGH

## Summary

Phase 40 adds ThermalPort handle rendering to canvas nodes, port-type connection enforcement, and thermal topology-aware code generation. The GUI must render amber-colored ThermalPort handles on ChannelAndContacts (top/bottom), HeatDiffusion (left/right), and ConstantTemperature (left) nodes. The `isValidConnection` callback must prevent cross-type connections (FlowPort to ThermalPort). The code generator must detect thermal wiring topologies (symmetric_plate, plate, one_sided_connection) from the edge graph and emit the corresponding STREAM.jl composition helper calls instead of raw `connect()` calls.

All three changes touch existing files with well-established patterns: `StreamNode.tsx` (handle rendering), `CanvasPanel.tsx` (connection validation), and `codeGenerator.ts` (Julia output). The registry already has complete ThermalPort definitions with `array: true` and `arrayParam` fields. No new dependencies are needed.

**Primary recommendation:** Split into two plans: (1) ThermalPort rendering + connection enforcement (THERM-01, THERM-02), (2) thermal topology detection + code generation (THERM-03).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- D-01: Each ThermalPort is rendered as one handle per side (not per cell). thermal_left and thermal_right each appear as a single handle regardless of n/nz. The GUI abstracts away per-cell detail.
- D-02: ChannelAndContacts: thermal_left on top edge, thermal_right on bottom edge. HeatDiffusion: thermal_left on left edge, thermal_right on right edge. ConstantTemperature: single thermal on left edge.
- D-03: ThermalPort handles use amber color (#f59e0b) to distinguish from FlowPort handles. ThermalPort edges also render in amber.
- D-04: The array: true field in registry is used only by the code generator. Renderer ignores it -- always one handle per ThermalPort entry.
- D-05: isValidConnection enforces port type matching. FlowPort-to-FlowPort only, ThermalPort-to-ThermalPort only. Cross-type connections blocked at draw time.
- D-06: Port type derived from registry type field. Handle data carries portType: "FlowPort" | "ThermalPort" so isValidConnection can compare without registry lookup.
- D-07: Code generator detects thermal wiring topology from edges array and emits correct helper: symmetric_plate, plate, one_sided_connection. Detection rules based on which ThermalPort handles of which component types are connected.
- D-08: Thermal assembly helper is emitted as @named declaration; hydraulic FlowPort connects reference assembly.cac.inlet path. compose_systems wraps the assembly with hydraulic connections.
- D-09: No thermal edges = Phase 36 format (ODESystem). Helper format only when thermal topology detected.
- D-10: Unrecognized thermal wiring emits raw connect(port(...)) calls with # TODO comment.
- D-11: No new VALD rules for ThermalPorts. Unconnected ThermalPorts are valid (adiabatic default).
- D-12: ThermalPort connections NOT included in VALD-01 FlowPort check (already scoped to FlowPort).

### Claude's Discretion
- Exact amber shade for ThermalPort handles and edges (should harmonize with amber-500 category border)
- Whether thermal edges have dashed vs solid style to distinguish from FlowPort edges
- ReactFlow handle shape for ThermalPort (circle vs diamond)
- Assembly naming convention when multiple thermal assemblies exist
- Error behavior when nz != n (code gen can emit a # NOTE comment)

### Deferred Ideas (OUT OF SCOPE)
- Layered canvas (Phase 41) -- hydraulic/thermal layer toggling
- Per-cell ThermalPort connections -- individual thermal_left[i] handles
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| THERM-01 | ChannelAndContacts canvas node displays thermal_left and thermal_right port handles | StreamNode.tsx handle rendering pattern; registry ThermalPort entries already defined; D-01 locks single-handle-per-side |
| THERM-02 | User can connect HeatDiffusion thermal ports to ChannelAndContacts thermal ports | isValidConnection in CanvasPanel.tsx; Handle data portType attribute; D-05/D-06 port-type enforcement |
| THERM-03 | Code generator detects thermal topologies and emits composition helper calls | codeGenerator.ts extension; helpers.jl signatures; D-07 through D-10 detection rules |
</phase_requirements>

## Standard Stack

### Core (already installed, no changes)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| @xyflow/react | ^12.10.2 | Canvas, Handle, Edge rendering | Already in use; Handle component supports custom styling and data attributes |
| vitest | ^4.1.2 | Test framework | Already configured with happy-dom for component tests |
| react | ^19.1.0 | UI framework | Already in use |

### Supporting (already installed)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| @testing-library/react | (installed) | Component test rendering | StreamNode and CanvasPanel tests |
| happy-dom | (installed) | DOM environment for vitest | Per-file @vitest-environment happy-dom docblock |

**No new dependencies required.** All functionality is achievable with existing libraries.

## Architecture Patterns

### File Change Map

```
gui/src/
  components/
    StreamNode.tsx          # ADD: ThermalPort handle rendering (amber handles, portType data)
    CanvasPanel.tsx         # MODIFY: isValidConnection port-type enforcement
  lib/
    codeGenerator.ts        # EXTEND: thermal topology detection + helper emission
    codeGenerator.test.ts   # EXTEND: thermal code gen tests
  components/__tests__/
    StreamNode.test.tsx     # EXTEND: ThermalPort handle rendering tests
```

### Pattern 1: ThermalPort Handle Rendering in StreamNode.tsx

**What:** Add a second handle loop for ThermalPort entries alongside existing FlowPort handles.

**Current code (line 31):**
```typescript
const flowPorts = component.ports.filter((p) => p.type === "FlowPort");
```

**Extension pattern:**
```typescript
const flowPorts = component.ports.filter((p) => p.type === "FlowPort");
const thermalPorts = component.ports.filter((p) => p.type === "ThermalPort");
```

Then render ThermalPort handles in a second `.map()` block with:
- Amber fill color (#f59e0b) via inline style (immune to Tailwind JIT gaps, matching existing pattern on line 9-12)
- `data-port-type="ThermalPort"` attribute on the Handle for isValidConnection lookup
- `id={port.name}` matching registry port name (thermal_left, thermal_right, thermal)
- Position from `sideToPosition[port.side]` (already maps top/bottom/left/right)

**Handle type for acausal ThermalPorts:** Use `type="source"` consistently for all ThermalPorts (per CONTEXT.md: "for acausal ports it doesn't matter; pick one consistently"). This allows connections in either direction on the canvas.

**FlowPort handles also need portType data:** Add `data-port-type="FlowPort"` to existing FlowPort Handle elements so isValidConnection can check both sides.

### Pattern 2: isValidConnection Port-Type Enforcement in CanvasPanel.tsx

**What:** Extend the existing isValidConnection callback to check port type compatibility.

**Current code (line 78-85):**
```typescript
const isValidConnection = useCallback((connection: Edge | Connection) => {
  return !!(
    connection.source &&
    connection.target &&
    connection.sourceHandle &&
    connection.targetHandle
  );
}, []);
```

**Challenge:** ReactFlow's `isValidConnection` callback receives a `Connection` object with `source`, `target`, `sourceHandle`, `targetHandle` -- but NOT handle data attributes directly. To get portType, the callback needs access to node data.

**Two approaches:**
1. **Registry lookup (simpler):** Import `getComponent` from registry. Look up source/target node componentId from store, find the port definition, check its `type` field. Requires store access from the callback.
2. **Handle ID encoding (D-06 preferred):** Encode portType into the handle ID itself (e.g., `FlowPort:inlet`, `ThermalPort:thermal_left`). Then `isValidConnection` splits the handle ID to extract type. However, this changes handle IDs throughout the codebase and breaks edge sourceHandle/targetHandle references.

**Recommended approach:** Use store access. The `isValidConnection` callback already lives in CanvasPanel which imports `useStore`. Add a helper that takes a nodeId + handleId and returns the port type by looking up the node's componentId in the store and then the port definition in the registry.

```typescript
// Inside CanvasPanel or a utility
function getPortType(nodeId: string, handleId: string): string | null {
  const node = useStore.getState().nodes.find(n => n.id === nodeId);
  if (!node) return null;
  const comp = getComponent((node.data as StreamNodeData).componentId);
  if (!comp) return null;
  const port = comp.ports.find(p => p.name === handleId);
  return port?.type ?? null;
}
```

Then in `isValidConnection`:
```typescript
const sourceType = getPortType(connection.source, connection.sourceHandle);
const targetType = getPortType(connection.target, connection.targetHandle);
if (sourceType && targetType && sourceType !== targetType) return false;
```

### Pattern 3: Thermal Topology Detection in codeGenerator.ts

**What:** Add a pre-pass that groups thermal edges by HeatDiffusion node, classifies the wiring topology, and emits helper declarations before the hydraulic `eqs = [...]` block.

**Detection algorithm:**

1. Partition edges into `flowEdges` (both handles are FlowPort) and `thermalEdges` (both handles are ThermalPort).
2. For each HeatDiffusion node, find all thermal edges connecting to it.
3. Classify based on connected components:
   - **symmetric_plate:** One CAC has BOTH thermal_left and thermal_right wired to the same HD (thermal_right->HD.thermal_left AND thermal_left->HD.thermal_right)
   - **plate:** Two different CACs each wired to one side of the same HD
   - **one_sided_connection:** One CAC wired to exactly one side of the HD
   - **ConstantTemperature:** A CT node wired to a thermal port
   - **Fallback:** Raw connect(port(...)) with TODO comment

4. For each detected assembly, emit:
   ```julia
   @named assembly_1 = symmetric_plate(cac_1, fuel_1)
   ```

5. Hydraulic `connect()` calls that reference a CAC inside an assembly use dotted path: `assembly_1.cac_1.inlet`

6. Top-level system uses `compose_systems(assembly_1; connections=eqs, name=:sys)` instead of `ODESystem(eqs, t; systems=[...])`.

**Key data structure:**
```typescript
interface ThermalAssembly {
  type: "symmetric_plate" | "plate" | "one_sided_connection";
  hdNodeId: string;      // HeatDiffusion node
  cacNodeIds: string[];   // ChannelAndContacts node(s)
  ctNodeIds?: string[];   // ConstantTemperature nodes (if any)
  assemblyName: string;   // e.g., "assembly_1"
}
```

### Pattern 4: Edge Styling for ThermalPort Connections

**What:** ThermalPort edges should render in amber to visually distinguish from FlowPort edges.

**ReactFlow approach:** The `defaultEdgeOptions` in CanvasPanel sets `type: "smoothstep"` for all edges. To color thermal edges differently, set `style` on the edge when it's created in `addEdge` (store), or apply it post-hoc based on handle type.

**Recommended:** In the store's `addEdge` function, after creating the edge, check if the connected handles are ThermalPorts and set `style: { stroke: "#f59e0b" }` on the edge object. This requires a registry lookup at edge creation time.

### Anti-Patterns to Avoid
- **Per-cell handles:** D-01 explicitly locks single handle per side. Do NOT render n handles.
- **Modifying handle IDs:** Do not encode portType into handle IDs. Keep existing `inlet`, `outlet`, `thermal_left`, `thermal_right` names. These are used by codeGenerator and stored in .streamgui files.
- **Touching validation.ts VALD checks:** D-11/D-12 explicitly exclude ThermalPorts from topology validation. Do not modify `validateTopology`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Handle styling | Custom SVG handle components | ReactFlow Handle with inline `style` prop | Handle accepts style prop directly; custom component adds complexity |
| Port type lookup | Parsing handle IDs or DOM attributes | Registry lookup via `getComponent(componentId).ports` | Registry is the single source of truth; already imported in StreamNode |
| Thermal edge coloring | Custom edge component | Edge `style` property on edge object | ReactFlow smoothstep edge supports inline style.stroke |

## Common Pitfalls

### Pitfall 1: Handle Position Overlap
**What goes wrong:** Two ThermalPort handles on the same side (e.g., thermal_left on top, thermal_right on bottom) overlap with FlowPort handles if the FlowPort is also on that side.
**Why it happens:** ChannelAndContacts has inlet on left, outlet on right (FlowPort), thermal_left on top, thermal_right on bottom (ThermalPort). No overlap. HeatDiffusion has thermal_left on left, thermal_right on right -- no FlowPorts, no overlap. ConstantTemperature has thermal on left -- no FlowPorts, no overlap.
**How to avoid:** The registry side assignments in D-02 were specifically chosen to avoid overlap. Verify registry entries match D-02 before implementation.
**Warning signs:** Handles visually stacking on top of each other.

### Pitfall 2: isValidConnection Closure Stale State
**What goes wrong:** isValidConnection reads stale node data because it captures state at callback creation time.
**Why it happens:** `useCallback` with empty deps `[]` captures nothing from store.
**How to avoid:** Use `useStore.getState()` inside the callback (direct Zustand access, always fresh) instead of reading from a captured variable.

### Pitfall 3: Edge Creation Direction for Acausal Ports
**What goes wrong:** ThermalPort handles are all `type="source"`, so ReactFlow only allows dragging FROM thermal handles, not TO them.
**Why it happens:** ReactFlow requires one source and one target handle for a connection. If both handles are `type="source"`, the connection cannot be made.
**How to avoid:** Use opposite types for left/right or top/bottom ThermalPorts. For example: thermal_left = `type="target"`, thermal_right = `type="source"`. Or: determine handle type based on registry `side` -- left/top = target, right/bottom = source. The key constraint is that one end must be source and the other target. Since ThermalPorts are acausal, the source/target designation is arbitrary but must allow both-direction connections.
**Warning signs:** Cannot draw edges between two thermal handles.

### Pitfall 4: compose_systems vs ODESystem Code Gen Path
**What goes wrong:** Generated code uses compose_systems when there are thermal assemblies but still lists assembly-internal components in the top-level systems array.
**Why it happens:** Components consumed by a thermal assembly helper should NOT appear in the top-level systems list -- they are already subsystems of the assembly.
**How to avoid:** Track which nodeIds are "consumed" by a thermal assembly. Exclude them from the top-level systems list. Only include the assembly name and non-consumed nodes.

### Pitfall 5: Backward Compatibility with .streamgui Files
**What goes wrong:** Existing .streamgui project files saved before Phase 40 fail to load because the code expects new fields.
**Why it happens:** Adding new edge properties (style, portType metadata) that old files don't have.
**How to avoid:** All new fields must have safe defaults. Edge style defaults to the existing smoothstep style. No schema version bump needed if new fields are optional.

## Code Examples

### ThermalPort Handle Rendering (StreamNode.tsx extension)
```typescript
// Source: Existing StreamNode.tsx pattern + D-01/D-02/D-03
const THERMAL_HANDLE_COLOR = "#f59e0b"; // amber-500

// In StreamNode component, after flowPorts:
const thermalPorts = component.ports.filter((p) => p.type === "ThermalPort");

// In JSX, after flowPorts.map:
{thermalPorts.map((port) => (
  <Handle
    key={port.name}
    id={port.name}
    type={port.side === "right" || port.side === "bottom" ? "source" : "target"}
    position={sideToPosition[port.side]}
    style={{
      background: THERMAL_HANDLE_COLOR,
      border: `1px solid ${THERMAL_HANDLE_COLOR}`,
      width: 8,
      height: 8,
    }}
  />
))}
```

### isValidConnection Extension (CanvasPanel.tsx)
```typescript
// Source: D-05/D-06 + CanvasPanel.tsx existing pattern
import { getComponent } from "../registry";

const isValidConnection = useCallback((connection: Edge | Connection) => {
  if (!connection.source || !connection.target ||
      !connection.sourceHandle || !connection.targetHandle) {
    return false;
  }
  // Port-type enforcement (D-05)
  const sourceNode = useStore.getState().nodes.find(n => n.id === connection.source);
  const targetNode = useStore.getState().nodes.find(n => n.id === connection.target);
  if (!sourceNode || !targetNode) return false;

  const srcComp = getComponent((sourceNode.data as StreamNodeData).componentId);
  const tgtComp = getComponent((targetNode.data as StreamNodeData).componentId);
  if (!srcComp || !tgtComp) return false;

  const srcPort = srcComp.ports.find(p => p.name === connection.sourceHandle);
  const tgtPort = tgtComp.ports.find(p => p.name === connection.targetHandle);
  if (!srcPort || !tgtPort) return false;

  return srcPort.type === tgtPort.type;
}, []);
```

### Thermal Topology Detection (codeGenerator.ts)
```typescript
// Source: D-07 detection rules + helpers.jl signatures
interface ThermalAssembly {
  type: "symmetric_plate" | "plate" | "one_sided_connection" | "unknown";
  hdNodeId: string;
  hdInstanceName: string;
  cacEntries: Array<{ nodeId: string; instanceName: string; side: "left" | "right" | "both" }>;
  assemblyName: string;
}

function detectThermalTopology(
  nodes: Node[],
  edges: Edge[],
  nodeDataMap: Map<string, StreamNodeData>,
  getComponent: (id: string) => ComponentDefinition | undefined,
): ThermalAssembly[] {
  // 1. Find thermal edges (both handles are ThermalPort type)
  // 2. Group by HeatDiffusion node
  // 3. For each HD: analyze which CACs connect to which side
  // 4. Classify as symmetric_plate / plate / one_sided_connection / unknown
  // Return array of assemblies
}
```

### Generated Code: symmetric_plate Pattern
```julia
# Source: D-08 + helpers.jl symmetric_plate signature
using ModelingToolkit, STREAM
using ModelingToolkit: t_nounits as t

@named cac_1 = ChannelAndContacts(; n=5, geometry=PipeGeometry_rectangular(0.5, 0.01, 0.003))
@named fuel_1 = HeatDiffusion(; nz=5, nx=3, Lz=0.5, Lx=0.001, y=0.0005, k=15.0, rho=6500.0, cp=300.0)

# Thermal assembly (auto-detected: symmetric_plate)
@named assembly_1 = symmetric_plate(cac_1, fuel_1)

@named pump_1 = Pump(30000.0)

eqs = [
    connect(pump_1.outlet, assembly_1.cac_1.inlet),
    connect(assembly_1.cac_1.outlet, pump_1.inlet),
    pump_1.inlet.P ~ 1.0e5,
]
@named sys = compose_systems(assembly_1, pump_1; connections=eqs, name=:sys)
ssys = mtkcompile(sys)
```

### Generated Code: Fallback (no recognized pattern)
```julia
# Source: D-10
# TODO: verify thermal wiring
# connect(port(cac_1, :thermal_left, i), port(fuel_1, :thermal_right, i)) for i in 1:n
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| FlowPort-only handles | FlowPort + ThermalPort handles | Phase 40 | StreamNode.tsx renders both port types |
| ODESystem-only code gen | ODESystem + compose_systems helper-based code gen | Phase 40 | codeGenerator.ts detects topology, emits helpers |
| No connection type enforcement | portType matching in isValidConnection | Phase 40 | CanvasPanel.tsx blocks cross-type connections |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | vitest 4.1.2 |
| Config file | gui/vitest.config.ts |
| Quick run command | `cd gui && npx vitest run --reporter=verbose` |
| Full suite command | `cd gui && npx vitest run --reporter=verbose` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| THERM-01 | ChannelAndContacts renders thermal handles | unit (happy-dom) | `cd gui && npx vitest run src/components/__tests__/StreamNode.test.tsx` | Exists, needs extension |
| THERM-01 | HeatDiffusion renders thermal handles | unit (happy-dom) | same file | Exists, needs extension |
| THERM-01 | ConstantTemperature renders thermal handle | unit (happy-dom) | same file | Exists, needs extension |
| THERM-02 | isValidConnection blocks FlowPort-to-ThermalPort | unit | `cd gui && npx vitest run src/lib/codeGenerator.test.ts` or new test file | New test needed |
| THERM-02 | isValidConnection allows ThermalPort-to-ThermalPort | unit | same | New test needed |
| THERM-03 | symmetric_plate topology detected and code emitted | unit | `cd gui && npx vitest run src/lib/codeGenerator.test.ts` | Exists, needs extension |
| THERM-03 | plate topology detected and code emitted | unit | same | Exists, needs extension |
| THERM-03 | one_sided_connection topology detected and code emitted | unit | same | Exists, needs extension |
| THERM-03 | No thermal edges = Phase 36 ODESystem format | unit | same | Already covered by existing tests |
| THERM-03 | Unrecognized topology = raw connect with TODO | unit | same | Needs new test |

### Sampling Rate
- **Per task commit:** `cd gui && npx vitest run --reporter=verbose`
- **Per wave merge:** `cd gui && npx vitest run --reporter=verbose`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] StreamNode.test.tsx -- add tests for ThermalPort handle count on ChannelAndContacts, HeatDiffusion, ConstantTemperature
- [ ] codeGenerator.test.ts -- add thermal topology detection tests (symmetric_plate, plate, one_sided_connection, fallback)
- [ ] New test for isValidConnection port-type enforcement (may go in a CanvasPanel test file or a standalone validation test)

## Open Questions

1. **Handle type assignment for acausal ThermalPorts**
   - What we know: ReactFlow requires source/target pairing. ThermalPorts are physically acausal.
   - What's unclear: Best assignment strategy that allows all valid connection patterns.
   - Recommendation: Use side-based assignment (left/top = target, right/bottom = source). This mirrors the spatial layout and ensures every valid connection has one source and one target. Verify HeatDiffusion (left=target, right=source) can connect to ChannelAndContacts (top=target, bottom=source) -- yes, HD.thermal_left(target) connects to CAC.thermal_right(source on bottom). Wait -- that means source connects to target, which is the expected ReactFlow direction. Confirmed: works.

2. **Edge styling scope**
   - What we know: D-03 says ThermalPort edges render in amber.
   - What's unclear: Whether to set edge style at creation time (in store addEdge) or at render time (custom edge component or defaultEdgeOptions override).
   - Recommendation: Set at creation time in addEdge. When addEdge processes a connection, look up both handles' port types. If both are ThermalPort, set `style: { stroke: "#f59e0b" }` on the edge.

3. **ConstantTemperature code generation**
   - What we know: D-07 says CT wired to any ThermalPort emits connect() inside equations.
   - What's unclear: Exact syntax for CT connection -- it has a single `thermal` port (not array). The STREAM.jl CT component connects to individual port array elements via `connect(ct.thermal, port(cac, :thermal_left, i))`.
   - Recommendation: For CT connections in code gen, emit `connect(ct_name.thermal, port(cac_name, :side, i))` syntax. Since the GUI uses single-handle-per-side, the code gen must expand to per-cell connections using a for loop comment or the helper. This needs careful handling -- the CT connects to ALL cells on one side, so emit the range version.

## Sources

### Primary (HIGH confidence)
- `gui/src/components/StreamNode.tsx` -- Current handle rendering pattern (FlowPort only, line 31-56)
- `gui/src/components/CanvasPanel.tsx` -- Current isValidConnection (line 78-85), onConnect, ReactFlow props
- `gui/src/lib/codeGenerator.ts` -- Current code gen structure (generateCode function, 365 lines)
- `gui/src/registry/components.json` -- ThermalPort definitions for ChannelAndContacts (line 180-181), HeatDiffusion (line 809-810), ConstantTemperature (line 783)
- `gui/src/registry/types.ts` -- Port interface with type, side, array, arrayParam fields
- `src/composition/helpers.jl` -- symmetric_plate, plate, one_sided_connection, compose_systems signatures and wiring conventions
- `gui/src/lib/validation.ts` -- validateTopology FlowPort-scoped (line 91, already excludes ThermalPort)
- `.planning/phases/40-thermal-composition/40-CONTEXT.md` -- All decisions D-01 through D-12

### Secondary (MEDIUM confidence)
- ReactFlow @xyflow/react Handle component API -- supports style prop, id, type (source/target), position
- ReactFlow isValidConnection callback -- receives Connection object with source/target/sourceHandle/targetHandle

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - No new dependencies; all existing libraries confirmed in package.json
- Architecture: HIGH - Clear extension points in existing code; patterns well-established across 7 prior GUI phases
- Pitfalls: HIGH - Based on direct code reading of all touched files; handle overlap and port-type enforcement verified against registry data

**Research date:** 2026-04-03
**Valid until:** 2026-05-03 (stable -- ReactFlow API and project patterns unlikely to change)
