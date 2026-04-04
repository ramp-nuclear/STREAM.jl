# Phase 34: Canvas & Node Editor - Research

**Researched:** 2026-04-02
**Domain:** ReactFlow custom nodes, drag-and-drop, Zustand undo/redo, canvas interaction
**Confidence:** HIGH

## Summary

Phase 34 builds the interactive canvas layer on top of the Phase 33 scaffold. The core work is: (1) a custom ReactFlow node component (`StreamNode`) that renders FlowPort handles from registry metadata, (2) HTML5 drag-and-drop from the toolbox to the canvas, (3) edge connection validation enforcing FlowPort directionality, (4) node/edge deletion with keyboard shortcuts, and (5) undo/redo via zundo temporal middleware wrapping the Zustand store.

All required libraries are already installed (`@xyflow/react@12.10.2`, `zustand@5.0.12`) except `zundo` which must be added. The registry (`components.json`) with 12 components, port metadata, and TypeScript types is fully established from Phase 33. The existing store, CanvasPanel, and ToolboxPanel are stubs ready for extension.

**Primary recommendation:** Extend the existing Zustand store with zundo temporal middleware and 4 new actions (addNode, removeNode, addEdge, removeEdge), create StreamNode custom node component driven by registry port data, populate ToolboxPanel with registry-driven draggable items, and wire CanvasPanel with drop handler + connection validation.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Minimal card -- neutral/white background, component type as small subtitle label, instance name as bold title. No icons, no category colors (Phase 38 will redesign). Functional, not styled.
- **D-02:** FlowPort handles placed left/right per `port.side` field from the registry. Each component's handle positions come from `components.json` -- no hardcoding.
- **D-03:** ThermalPort handles are NOT rendered in Phase 34. They are deferred to Phase 40. The registry already has full thermal port metadata for when Phase 40 needs it.
- **D-04:** Node shows component type and user-assigned instance name. Default name is `comp_type_N` (e.g., `pump_1`, `channel_2`), per CANV-02.
- **D-05:** HTML5 drag-and-drop is the interaction model. Toolbox items use `onDragStart` to set `dataTransfer` payload (component id). Canvas `onDrop` reads it and calls `addNode`. Not react-dnd, not click-to-place.
- **D-06:** Strict FlowPort directionality: only FlowPort-out handles can be edge sources; only FlowPort-in handles can be edge targets. Implemented via ReactFlow's `isValidConnection` prop and handle `type` (`source` vs `target`).
- **D-07:** Higher-level topology rules deferred to Phase 39. Phase 34 only enforces source/target directionality.
- **D-08:** Use `zundo` library (Zustand temporal middleware). Must cover at least 10 sequential operations. Fallback: custom `past[]`/`future[]` snapshot stack if zundo causes issues.

### Claude's Discretion
- Default instance name counter strategy (per-type counter vs. global counter)
- Exact node card dimensions and CSS
- Handle colors for FlowPort in/out handles
- Keyboard shortcut for delete (Delete/Backspace) -- ReactFlow has built-in support

### Deferred Ideas (OUT OF SCOPE)
- ThermalPort handle rendering -- Phase 40
- Component icons/colors -- Phase 38 (UI design pass)
- Edge labels showing `connect(a.port_out, b.port_in)` -- Phase 36 or 38
- Multi-select with lasso tool -- may come free from ReactFlow
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CANV-01 | Empty canvas with zoom, pan, minimap, fit-to-view controls | Already working from Phase 33 CanvasPanel (Controls, MiniMap, Background wired) |
| CANV-02 | Drag component from toolbox onto canvas to create named instance | HTML5 drag-and-drop pattern: ToolboxItem `onDragStart` + CanvasPanel `onDrop` + `screenToFlowPosition` + `addNode` store action |
| CANV-03 | Connect FlowPort-out to FlowPort-in with visible edge | ReactFlow `onConnect` + `isValidConnection` callback + Handle `type` source/target + unique handle IDs per port |
| CANV-04 | Select and delete components and connections individually or as group | ReactFlow `deleteKeyCode` prop + `onNodesDelete`/`onEdgesDelete` callbacks + store removeNode/removeEdge |
| CANV-05 | Drag-reposition components without losing connections | Built-in ReactFlow behavior; `onNodesChange` with `applyNodeChanges` already wired in store |
| CANV-06 | Node displays component type label and instance name | StreamNode custom component: type label as `text-xs text-muted-foreground`, instance name as `font-semibold text-sm` |
| CANV-07 | Undo/redo canvas operations (add/delete/move node, add/delete edge) | zundo temporal middleware wrapping Zustand store; `undo()`/`redo()` + Ctrl+Z/Ctrl+Shift+Z keyboard bindings |
</phase_requirements>

## Standard Stack

### Core (already installed)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| @xyflow/react | 12.10.2 | Node-based canvas editor | Industry standard for React node editors; already installed in Phase 33 |
| zustand | 5.0.12 | State management | Already wired with ReactFlow in Phase 33 store |
| react | 19.1.0 | UI framework | Already installed |

### To Install
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| zundo | 2.3.0 | Undo/redo temporal middleware for Zustand | User-selected (D-08); peer dep zustand ^4.3.0 or ^5.0.0 -- compatible with installed 5.0.12; <700 bytes gzipped |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| zundo | Manual past[]/future[] stack | More control but more code; D-08 says try zundo first, fallback to manual |

**Installation:**
```bash
cd gui && npm install zundo
```

## Architecture Patterns

### File Structure
```
gui/src/
  components/
    StreamNode.tsx        # NEW: Custom ReactFlow node (card + handles)
    ToolboxItem.tsx       # NEW: Draggable toolbox entry
    ToolboxPanel.tsx      # MODIFY: Replace stub with registry-driven list
    CanvasPanel.tsx       # MODIFY: Add nodeTypes, onDrop, isValidConnection, deleteKeyCode
    SidebarPanel.tsx      # UNCHANGED
  store/
    useStore.ts           # MODIFY: Add actions, wrap with zundo temporal
  registry/
    index.ts              # UNCHANGED
    types.ts              # UNCHANGED
    components.json       # UNCHANGED
```

### Pattern 1: Zustand Store with zundo Temporal Middleware

**What:** Wrap the existing `create()` call with `temporal()` to get undo/redo for free.
**When to use:** Any store that needs undo/redo.
**Key detail:** The `partialize` option controls which state fields are tracked. Actions (functions) must be excluded. The `limit` option caps history depth.

```typescript
// Source: https://github.com/charkour/zundo
import { create } from 'zustand';
import { temporal } from 'zundo';

interface AppState {
  nodes: Node[];
  edges: Edge[];
  selectedNodeId: string | null;
  // ... actions
}

const useStore = create<AppState>()(
  temporal(
    (set, get) => ({
      nodes: [],
      edges: [],
      selectedNodeId: null,
      // ... all actions
    }),
    {
      // Only track data fields, not action functions
      partialize: (state) => ({
        nodes: state.nodes,
        edges: state.edges,
        selectedNodeId: state.selectedNodeId,
      }),
      limit: 50, // More than the 10 required by CANV-07
    }
  )
);

// Access undo/redo:
const { undo, redo, clear } = useStore.temporal.getState();
```

### Pattern 2: Custom Node with Registry-Driven Handles

**What:** A single `StreamNode` component that reads the component definition from the registry and renders the appropriate FlowPort handles based on `port.side`.
**When to use:** Every node on the canvas uses this component.

```typescript
// Source: https://reactflow.dev/api-reference/components/handle
import { Handle, Position, type NodeProps } from '@xyflow/react';
import { getComponent } from '../registry';
import type { StreamNodeData } from '../store/useStore';

const sideToPosition: Record<string, Position> = {
  left: Position.Left,
  right: Position.Right,
  top: Position.Top,
  bottom: Position.Bottom,
};

export default function StreamNode({ data }: NodeProps) {
  const nodeData = data as StreamNodeData;
  const component = getComponent(nodeData.componentId);
  if (!component) return null;

  // Filter to FlowPort only (D-03: no ThermalPort in Phase 34)
  const flowPorts = component.ports.filter(p => p.type === 'FlowPort');

  return (
    <div className="border rounded-[var(--radius)] bg-card p-2 min-w-[140px]">
      <div className="text-xs text-muted-foreground">{component.label}</div>
      <div className="font-semibold text-sm">{nodeData.instanceName}</div>
      {flowPorts.map(port => (
        <Handle
          key={port.name}
          id={port.name}
          type={port.name.includes('out') ? 'source' : 'target'}
          position={sideToPosition[port.side]}
        />
      ))}
    </div>
  );
}
```

### Pattern 3: HTML5 Drag-and-Drop from Toolbox

**What:** Standard HTML5 drag API -- no library needed.
**When to use:** Dragging components from toolbox to canvas.

```typescript
// ToolboxItem: onDragStart sets dataTransfer payload
const onDragStart = (event: React.DragEvent, componentId: string) => {
  event.dataTransfer.setData('application/streamcomponent', componentId);
  event.dataTransfer.effectAllowed = 'move';
};

// CanvasPanel: onDrop reads payload and creates node
const onDrop = useCallback((event: React.DragEvent) => {
  event.preventDefault();
  const componentId = event.dataTransfer.getData('application/streamcomponent');
  if (!componentId) return;
  const position = screenToFlowPosition({
    x: event.clientX,
    y: event.clientY,
  });
  addNode(componentId, position);
}, [screenToFlowPosition, addNode]);

const onDragOver = useCallback((event: React.DragEvent) => {
  event.preventDefault();
  event.dataTransfer.dropEffect = 'move';
}, []);
```

### Pattern 4: Connection Validation

**What:** `isValidConnection` callback on `<ReactFlow>` that enforces FlowPort directionality.
**When to use:** Prevents invalid connections at draw time.

```typescript
// Source: https://reactflow.dev/examples/interaction/validation
const isValidConnection = useCallback((connection: Connection) => {
  // sourceHandle and targetHandle carry the port name (e.g., "port_out", "port_in")
  // Handle type already enforces source->target (source handles are "source", target handles are "target")
  // Additional validation: both handles must exist
  return !!(connection.source && connection.target && connection.sourceHandle && connection.targetHandle);
}, []);
```

### Pattern 5: Node Deletion with Edge Cleanup

**What:** When a node is deleted, all connected edges must be removed too.
**When to use:** ReactFlow handles this automatically when using `deleteKeyCode` prop with `onNodesDelete`/`onEdgesDelete` callbacks that sync to the store.

```typescript
// ReactFlow's applyNodeChanges with type 'remove' handles edge cleanup
// when nodes are removed via deleteKeyCode. The onEdgesChange callback
// fires automatically for orphaned edges.
<ReactFlow
  deleteKeyCode={['Delete', 'Backspace']}
  // ReactFlow fires onNodesChange with remove changes for deleted nodes
  // and onEdgesChange with remove changes for orphaned edges
/>
```

### Anti-Patterns to Avoid
- **Hardcoding component port positions:** Always read from `components.json` registry. Node rendering must be data-driven.
- **Storing actions in zundo history:** Use `partialize` to exclude function properties from temporal tracking. Including them causes serialization issues and bloated history.
- **Using `react-dnd` for toolbox drag:** D-05 explicitly requires HTML5 native drag-and-drop, not react-dnd.
- **Modifying Phase 33 layout structure:** ToolboxPanel width (w-60), SidebarPanel width (w-80), three-panel layout are locked from Phase 33.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Undo/redo state tracking | Custom history stack | zundo `temporal()` middleware | Handles edge cases (state serialization, history limits); D-08 mandates trying zundo first |
| Node change application | Manual node array mutations | `applyNodeChanges` from @xyflow/react | Already wired in Phase 33 store; handles position, selection, removal atomically |
| Edge change application | Manual edge array mutations | `applyEdgeChanges` from @xyflow/react | Already wired in Phase 33 store |
| Screen-to-canvas coordinate conversion | Manual viewport math | `screenToFlowPosition` from `useReactFlow` hook | Accounts for zoom, pan, and viewport transforms |
| Keyboard delete handling | Custom keydown listeners | ReactFlow `deleteKeyCode` prop | Built-in, handles selection state correctly |

**Key insight:** ReactFlow v12 handles most of the complex canvas interactions (zoom, pan, selection, deletion, edge routing) natively. Phase 34's job is to wire the data flow between the registry, store, and ReactFlow -- not to build canvas primitives.

## Common Pitfalls

### Pitfall 1: zundo Tracking Action Functions
**What goes wrong:** If `partialize` is not set, zundo tries to snapshot the entire store including action functions, causing performance issues and broken undo.
**Why it happens:** Zustand stores mix data and functions in the same object.
**How to avoid:** Always use `partialize` to return only data fields (nodes, edges, selectedNodeId).
**Warning signs:** Undo restores old function references; console warnings about non-serializable values.

### Pitfall 2: Missing Handle IDs for Multi-Handle Nodes
**What goes wrong:** ReactFlow cannot distinguish between multiple handles on the same node, causing edges to snap to the wrong port.
**Why it happens:** Default Handle behavior assumes one source and one target per node.
**How to avoid:** Every `<Handle>` must have a unique `id` prop matching the port name from the registry (e.g., `id="port_in"`, `id="port_out"`).
**Warning signs:** Edges connecting to wrong handles; `sourceHandle`/`targetHandle` undefined in connection callbacks.

### Pitfall 3: useReactFlow Hook Outside ReactFlowProvider
**What goes wrong:** `useReactFlow()` throws when called outside `<ReactFlowProvider>`.
**Why it happens:** `<ReactFlow>` internally provides a context, but `useReactFlow()` in parent components needs an explicit provider.
**How to avoid:** The current CanvasPanel renders `<ReactFlow>` directly -- `useReactFlow()` must be called inside a child component of `<ReactFlow>`, or the onDrop handler must be wired inside CanvasPanel where the context is available. Alternatively, wrap `<ReactFlow>` in a `<ReactFlowProvider>`.
**Warning signs:** "useReactFlow must be used within a ReactFlowProvider" error.

### Pitfall 4: Node Type Registration Mismatch
**What goes wrong:** Nodes render as the default gray rectangle instead of StreamNode.
**Why it happens:** The `type` field on the node object must match a key in the `nodeTypes` map passed to `<ReactFlow>`. If the store creates nodes with `type: 'streamNode'` but nodeTypes has `{ StreamNode: ... }`, the case mismatch causes a fallback.
**How to avoid:** Use a consistent key like `streamNode` in both `nodeTypes` map and `addNode` action.
**Warning signs:** Nodes appear as plain gray boxes without handles.

### Pitfall 5: Stale Closure in onDrop with screenToFlowPosition
**What goes wrong:** Drop position is wrong (offset from where user dropped).
**Why it happens:** `screenToFlowPosition` from `useReactFlow()` captures stale viewport state if the `onDrop` callback is not properly memoized with the correct dependency.
**How to avoid:** Use `useCallback` with `screenToFlowPosition` in the dependency array.
**Warning signs:** Nodes appear at wrong positions, especially after zooming/panning.

### Pitfall 6: onNodesChange Doesn't Fire for Node Deletion in Some Cases
**What goes wrong:** Deleting a node via keyboard doesn't clean up connected edges.
**Why it happens:** ReactFlow's `deleteKeyCode` fires `onNodesChange` with remove changes, which also triggers `onEdgesChange` for connected edges -- but only if `onEdgesChange` is properly wired.
**How to avoid:** Ensure both `onNodesChange` and `onEdgesChange` are connected to the store (already done in Phase 33). ReactFlow handles cascading edge removal automatically.
**Warning signs:** Orphaned edges remain visible after node deletion.

## Code Examples

### Store Extension with zundo + New Actions

```typescript
// gui/src/store/useStore.ts
import { create } from 'zustand';
import { temporal } from 'zundo';
import {
  Node, Edge, Connection,
  applyNodeChanges, applyEdgeChanges,
  addEdge as rfAddEdge,
  NodeChange, EdgeChange,
} from '@xyflow/react';

export interface StreamNodeData {
  componentId: string;
  instanceName: string;
  parameters: Record<string, unknown>;
}

interface AppState {
  nodes: Node[];
  edges: Edge[];
  selectedNodeId: string | null;
  onNodesChange: (changes: NodeChange[]) => void;
  onEdgesChange: (changes: EdgeChange[]) => void;
  selectNode: (nodeId: string | null) => void;
  addNode: (componentId: string, position: { x: number; y: number }) => void;
  removeNode: (nodeId: string) => void;
  addEdge: (connection: Connection) => void;
  removeEdge: (edgeId: string) => void;
}

// Per-type instance counters for default naming
const instanceCounters: Record<string, number> = {};

function getNextInstanceName(componentId: string): string {
  const count = (instanceCounters[componentId] ?? 0) + 1;
  instanceCounters[componentId] = count;
  return `${componentId.toLowerCase()}_${count}`;
}

const useStore = create<AppState>()(
  temporal(
    (set, get) => ({
      nodes: [],
      edges: [],
      selectedNodeId: null,
      onNodesChange: (changes) =>
        set({ nodes: applyNodeChanges(changes, get().nodes) }),
      onEdgesChange: (changes) =>
        set({ edges: applyEdgeChanges(changes, get().edges) }),
      selectNode: (nodeId) => set({ selectedNodeId: nodeId }),
      addNode: (componentId, position) => {
        const id = `${componentId}-${Date.now()}`;
        const newNode: Node = {
          id,
          type: 'streamNode',
          position,
          data: {
            componentId,
            instanceName: getNextInstanceName(componentId),
            parameters: {},
          } satisfies StreamNodeData,
        };
        set({ nodes: [...get().nodes, newNode] });
      },
      removeNode: (nodeId) => {
        const { nodes, edges } = get();
        set({
          nodes: nodes.filter(n => n.id !== nodeId),
          edges: edges.filter(e => e.source !== nodeId && e.target !== nodeId),
          selectedNodeId: null,
        });
      },
      addEdge: (connection) => {
        set({ edges: rfAddEdge(connection, get().edges) });
      },
      removeEdge: (edgeId) => {
        set({ edges: get().edges.filter(e => e.id !== edgeId) });
      },
    }),
    {
      partialize: (state) => ({
        nodes: state.nodes,
        edges: state.edges,
        selectedNodeId: state.selectedNodeId,
      }),
      limit: 50,
    }
  )
);

export default useStore;
```

### nodeTypes Registration

```typescript
// In CanvasPanel.tsx
import StreamNode from './StreamNode';
import type { NodeTypes } from '@xyflow/react';

const nodeTypes: NodeTypes = {
  streamNode: StreamNode,
};

// Pass to <ReactFlow nodeTypes={nodeTypes} ... />
// IMPORTANT: nodeTypes must be defined OUTSIDE the component or memoized
// to prevent infinite re-renders (ReactFlow requirement)
```

### Keyboard Undo/Redo Binding

```typescript
// In CanvasPanel.tsx or App.tsx
import { useEffect } from 'react';
import useStore from '../store/useStore';

function useUndoRedo() {
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key === 'z' && !e.shiftKey) {
        e.preventDefault();
        useStore.temporal.getState().undo();
      }
      if ((e.ctrlKey || e.metaKey) && (e.key === 'y' || (e.key === 'z' && e.shiftKey))) {
        e.preventDefault();
        useStore.temporal.getState().redo();
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, []);
}
```

## Project Constraints (from CLAUDE.md)

- No Unicode variable names in Julia code (ASCII only)
- Component authoring conventions for positional vs keyword args
- `@named` macro injects `name=:varname` as keyword argument
- All exports declared in `STREAM.jl` module entry point
- Test file mirrors src file pattern

Note: Most CLAUDE.md directives pertain to the Julia library, not the GUI. The GUI-relevant constraints are:
- Registry `positional: boolean` field must be preserved for Phase 36 code generation
- Component registry schema established in Phase 33 must not be modified

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | vitest 4.1.2 |
| Config file | `gui/vitest.config.ts` (exists, node environment by default) |
| Quick run command | `cd gui && npx vitest run --passWithNoTests` |
| Full suite command | `cd gui && npx vitest run` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CANV-01 | Canvas with zoom/pan/minimap/fit-to-view | manual-only | N/A (visual, already working from Phase 33) | N/A |
| CANV-02 | Drag from toolbox creates named node | unit | `cd gui && npx vitest run src/store/__tests__/useStore.test.ts` | Wave 0 |
| CANV-03 | FlowPort-out to FlowPort-in connection | unit | `cd gui && npx vitest run src/store/__tests__/useStore.test.ts` | Wave 0 |
| CANV-04 | Select and delete nodes/edges | unit | `cd gui && npx vitest run src/store/__tests__/useStore.test.ts` | Wave 0 |
| CANV-05 | Drag-reposition preserves connections | manual-only | N/A (ReactFlow built-in behavior) | N/A |
| CANV-06 | Node displays type label and instance name | unit (jsdom) | `cd gui && npx vitest run src/components/__tests__/StreamNode.test.tsx` | Wave 0 |
| CANV-07 | Undo/redo covers 10+ sequential operations | unit | `cd gui && npx vitest run src/store/__tests__/useStore.test.ts` | Wave 0 |

### Sampling Rate
- **Per task commit:** `cd gui && npx vitest run --passWithNoTests`
- **Per wave merge:** `cd gui && npx vitest run`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `gui/src/store/__tests__/useStore.test.ts` -- covers CANV-02, CANV-03, CANV-04, CANV-07 (store actions: addNode, removeNode, addEdge, removeEdge, undo/redo)
- [ ] `gui/src/components/__tests__/StreamNode.test.tsx` -- covers CANV-06 (node rendering with type label + instance name); requires `@vitest-environment jsdom` docblock
- [ ] Framework install: `cd gui && npm install zundo` -- zundo not yet installed

## Open Questions

1. **Per-type vs global instance counter**
   - What we know: D-04 says default name is `comp_type_N` (e.g., `pump_1`, `channel_2`), suggesting per-type counters
   - What's unclear: Whether counters should persist across undo/redo (if user undoes adding pump_3, should the next pump still be pump_4 or pump_3?)
   - Recommendation: Per-type counters, non-decreasing (never reuse names). This is simpler and avoids name collisions. The counter lives outside the store (not tracked by zundo) so undo does not reset it.

2. **Node ID strategy**
   - What we know: Need unique IDs for nodes
   - What's unclear: Whether `componentId-timestamp` is robust enough or if a UUID is better
   - Recommendation: `${componentId}-${crypto.randomUUID()}` or a simple incrementing counter. Timestamps risk collision if two nodes are added in the same millisecond. A counter is simplest.

## Sources

### Primary (HIGH confidence)
- @xyflow/react v12.10.2 (installed, verified) - ReactFlow custom nodes, Handle component, isValidConnection, screenToFlowPosition, deleteKeyCode
- [ReactFlow Handle API](https://reactflow.dev/api-reference/components/handle) - Handle type/position/id props
- [ReactFlow Drag and Drop example](https://reactflow.dev/examples/interaction/drag-and-drop) - onDrop/onDragOver/screenToFlowPosition pattern
- [ReactFlow Validation example](https://reactflow.dev/examples/interaction/validation) - isValidConnection pattern
- zustand 5.0.12 (installed, verified) - State management
- [zundo GitHub](https://github.com/charkour/zundo) - temporal() middleware, partialize, limit options, undo/redo/clear API

### Secondary (MEDIUM confidence)
- [zundo npm](https://www.npmjs.com/package/zundo) - v2.3.0, peer dep zustand ^4.3.0 || ^5.0.0 (verified compatible)

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - all libraries verified installed or confirmed compatible; versions checked against npm registry
- Architecture: HIGH - patterns directly from ReactFlow official docs and zundo README; existing Phase 33 code provides clear extension points
- Pitfalls: HIGH - based on documented ReactFlow v12 behavior and zundo API constraints

**Research date:** 2026-04-02
**Valid until:** 2026-05-02 (stable libraries, no breaking changes expected)
