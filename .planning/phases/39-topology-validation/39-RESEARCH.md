# Phase 39: Topology Validation - Research

**Researched:** 2026-04-03
**Domain:** React/TypeScript GUI -- topology validation, modal dialogs, Zustand state management
**Confidence:** HIGH

## Summary

Phase 39 adds topology validation to the STREAM Composer GUI. When a user attempts to export or save, a pure function checks for unconnected FlowPorts (VALD-01), missing pressure boundary conditions (VALD-02), and missing driving elements (VALD-03). On failure, a shadcn AlertDialog blocks the operation and lists all issues. After dismissal, affected nodes display a red destructive ring that clears reactively as edges are added.

The implementation is straightforward: a pure validation function, a new Zustand store field (`errorNodeIds: Set<string>`), a new `ValidationDialog` component using shadcn's `alert-dialog`, and wiring into two trigger points (Export button, Save action). All building blocks exist in the codebase; no new external dependencies are needed beyond generating the shadcn `alert-dialog.tsx` wrapper.

**Primary recommendation:** Implement as a pure function in `gui/src/lib/validation.ts` + thin store action + single `ValidationDialog.tsx` component. Keep the validation function fully testable with no store dependency.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Validation runs only on export/save, not continuously during construction
- **D-02:** Failed validation blocks the operation until the user dismisses the error dialog
- **D-03:** A shadcn AlertDialog (modal) lists all issues grouped by type (node-level first, system-level second)
- **D-04:** Dialog groups by issue type (node-level issues first, then system-level issues)
- **D-05:** Red rings (`ring-2 ring-destructive`) persist on affected nodes after dialog dismiss
- **D-06:** Red rings clear automatically when the underlying issue is fixed (port connected)
- **D-07:** A node with both error ring and selection ring shows both simultaneously; destructive ring uses `ring-2 ring-destructive ring-offset-1`
- **D-08:** Validation state is `errorNodeIds: Set<string>` in the Zustand store
- **D-09:** System-level checks (VALD-02/VALD-03) are pure functions -- no ring needed, only dialog text
- **D-10:** A FlowPort is connected if an edge exists with source/target handle matching that port name on that node. ThermalPorts not checked.
- **D-11:** "Pressure anchor" = `bcs.length > 0`. Empty bcs array triggers VALD-02.
- **D-12:** "Driving element" = at least one node with `componentId === "Pump"` or `componentId === "Gravity"`

### Claude's Discretion
- Exact ring layering when selected + error simultaneously
- Whether to extract `topologyValidator.ts` or keep in `validation.ts`
- Error dialog title text and icon
- Order of error items within each group in the dialog

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| VALD-01 | Visual warning on nodes with unconnected mandatory FlowPorts | Pure validation function checks each node's FlowPorts against edges array; `errorNodeIds` drives red ring on StreamNode |
| VALD-02 | Detect absence of pressure BC and show alert | `bcs.length === 0` check in validation function; shown as system-level error in AlertDialog |
| VALD-03 | Detect no driving element (no Pump/Gravity) and show alert | `nodes.some(n => n.data.componentId === "Pump" \|\| ...)` check; shown as system-level error in AlertDialog |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| @radix-ui/react-alert-dialog | installed via radix-ui@1.4.3 | Modal dialog primitive | Already in node_modules; shadcn wraps it |
| shadcn alert-dialog | generated | AlertDialog component wrapper | Consistent with all other UI primitives in the project |
| zustand | 5.0.12 | State management for errorNodeIds | Already the project store |
| lucide-react | 1.7.0 | AlertTriangle icon for dialog | Already installed and used throughout |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| vitest | existing | Unit tests for validation function | Testing validateTopology pure function |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| shadcn AlertDialog | Custom modal with Dialog | AlertDialog has built-in focus trap and escape handling for blocking modals; Dialog is for non-blocking |
| Zustand Set<string> | Node data prop `hasError` | Set in store is more efficient for reactive clearing; avoids mutating node data on every validation |

**Installation:**
```bash
cd gui && npx shadcn add alert-dialog
```

## Architecture Patterns

### Recommended File Structure
```
gui/src/
  lib/
    validation.ts              # Add validateTopology() pure function (existing file)
  components/
    ValidationDialog.tsx       # New: AlertDialog with grouped error list
    StreamNode.tsx             # Modified: conditional destructive ring class
    Toolbar.tsx                # Modified: validation gate before export
  store/
    useStore.ts                # Modified: errorNodeIds, validateTopology action, reactive edge clearing
```

### Pattern 1: Pure Validation Function
**What:** `validateTopology(nodes, edges, bcs, getComponent)` is a pure function that takes canvas state and returns a structured result. No store dependency.
**When to use:** Always -- this is the core of the phase.
**Example:**
```typescript
// gui/src/lib/validation.ts
interface TopologyError {
  nodeErrors: Array<{ nodeId: string; instanceName: string; portName: string }>;
  systemErrors: Array<{ message: string }>;
}

interface TopologyResult {
  valid: boolean;
  errors: TopologyError;
}

function validateTopology(
  nodes: Node[],
  edges: Edge[],
  bcs: BCEntry[],
  getComponentDef: (id: string) => ComponentDefinition | undefined
): TopologyResult {
  const nodeErrors: TopologyError["nodeErrors"] = [];
  
  for (const node of nodes) {
    const def = getComponentDef(node.data.componentId);
    if (!def) continue;
    const flowPorts = def.ports.filter(p => p.type === "FlowPort");
    for (const port of flowPorts) {
      const isInput = port.name.includes("in");
      const connected = edges.some(e =>
        isInput
          ? (e.target === node.id && e.targetHandle === port.name)
          : (e.source === node.id && e.sourceHandle === port.name)
      );
      if (!connected) {
        nodeErrors.push({
          nodeId: node.id,
          instanceName: node.data.instanceName,
          portName: port.name,
        });
      }
    }
  }
  
  const systemErrors: TopologyError["systemErrors"] = [];
  if (bcs.length === 0) {
    systemErrors.push({ message: "No pressure boundary condition" });
  }
  const hasDriving = nodes.some(n => 
    n.data.componentId === "Pump" || n.data.componentId === "Gravity"
  );
  if (!hasDriving) {
    systemErrors.push({ message: "No driving element (add a Pump or Gravity component)" });
  }
  
  return {
    valid: nodeErrors.length === 0 && systemErrors.length === 0,
    errors: { nodeErrors, systemErrors },
  };
}
```

### Pattern 2: Store Action Wrapping Pure Function
**What:** The Zustand store calls the pure function and stores the `errorNodeIds` Set.
**When to use:** When the export/save trigger fires.
**Example:**
```typescript
// In useStore.ts create() callback
validateTopology: () => {
  const { nodes, edges, bcs } = get();
  const result = validateTopologyFn(nodes, edges, bcs, getComponent);
  const errorIds = new Set(result.errors.nodeErrors.map(e => e.nodeId));
  set({ errorNodeIds: errorIds });
  return result;
},
```

### Pattern 3: Reactive Edge Clearing
**What:** When `addEdge` is called, re-check affected nodes and remove them from `errorNodeIds` if all their FlowPorts are now connected.
**When to use:** In the `addEdge` store action, after the edge is added.
**Example:**
```typescript
addEdge: (connection) => {
  get()._pushSnapshot();
  const newEdges = rfAddEdge(connection, get().edges);
  const { errorNodeIds } = get();
  
  if (errorNodeIds.size > 0) {
    const updatedErrors = new Set(errorNodeIds);
    // Check source and target nodes of the new edge
    for (const nodeId of [connection.source, connection.target]) {
      if (!nodeId || !updatedErrors.has(nodeId)) continue;
      const node = get().nodes.find(n => n.id === nodeId);
      if (!node) continue;
      const def = getComponent(node.data.componentId);
      if (!def) continue;
      const flowPorts = def.ports.filter(p => p.type === "FlowPort");
      const allConnected = flowPorts.every(port => {
        const isInput = port.name.includes("in");
        return newEdges.some(e =>
          isInput
            ? (e.target === nodeId && e.targetHandle === port.name)
            : (e.source === nodeId && e.sourceHandle === port.name)
        );
      });
      if (allConnected) updatedErrors.delete(nodeId);
    }
    set({ edges: newEdges, isDirty: true, errorNodeIds: updatedErrors });
  } else {
    set({ edges: newEdges, isDirty: true });
  }
},
```

### Pattern 4: Dual Ring Coexistence on StreamNode
**What:** StreamNode renders both selection ring and destructive ring simultaneously.
**When to use:** When a node is both selected and has an error.
**Implementation approach:** Use Tailwind's `ring` for the selection indicator and CSS `outline` for the error indicator (or vice versa). This avoids ring collision since `ring` and `outline` are separate CSS properties.
**Example:**
```typescript
// StreamNode.tsx
const hasError = useStore(s => s.errorNodeIds.has(nodeId));

<div className={cn(
  "border rounded-[var(--radius)] bg-card p-2 min-w-[140px]",
  selected && "ring-2 ring-[var(--ring)]",
  hasError && "outline outline-2 outline-destructive outline-offset-1"
)}>
```
**Why outline:** `ring` is a box-shadow in Tailwind. Using `outline` for the error indicator means both can render simultaneously without conflict. `outline-offset-1` provides visual separation.

### Anti-Patterns to Avoid
- **Storing error state in node.data:** This would dirty the document and push undo history entries for validation state changes. Keep error state in a separate store field.
- **Running validation on every node/edge change:** User explicitly rejected continuous validation (D-01). Only on export/save.
- **Clearing errorNodeIds on any state change:** Only clear on edge addition that resolves the specific error. Do not clear all errors when any edge changes.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Modal dialog with focus trap | Custom overlay + portal | shadcn AlertDialog | Focus trap, escape key, scroll lock, accessible ARIA roles |
| Port connection checking | Inline checks scattered in components | Pure `validateTopology` function | Single source of truth, easily testable |

## Common Pitfalls

### Pitfall 1: Ring Collision
**What goes wrong:** Both selection ring and error ring use Tailwind `ring-*` utilities, causing the later one to override the earlier one (they compile to the same CSS custom property `--tw-ring-*`).
**Why it happens:** Tailwind `ring` utilities all write to `--tw-ring-color`, `--tw-ring-offset-width`, etc. Two conflicting `ring-*` classes cancel each other.
**How to avoid:** Use `ring` for one purpose and `outline` for the other. `outline` is a separate CSS property that coexists with `ring` (box-shadow).
**Warning signs:** Error ring disappears when node is selected, or selection ring disappears when error ring is shown.

### Pitfall 2: Set Reactivity in Zustand
**What goes wrong:** `Set<string>` in Zustand does not trigger re-renders when mutated in-place because Zustand uses referential equality checks.
**Why it happens:** `errorNodeIds.add(id)` mutates the same Set reference; Zustand sees the same object and skips re-render.
**How to avoid:** Always create a new Set: `set({ errorNodeIds: new Set([...oldSet, newId]) })` or `new Set(errorNodeIds)` after mutation.
**Warning signs:** Error rings don't appear or disappear despite store state being correct in devtools.

### Pitfall 3: Validation Dialog State Management
**What goes wrong:** The AlertDialog open state and validation result need to be coordinated. If the dialog is controlled by React state in Toolbar, calling validation from saveProject (in the store) cannot open it.
**Why it happens:** Two trigger points (Export in Toolbar, Save in store) but only one dialog.
**How to avoid:** Store the validation result (or null) in Zustand store: `validationResult: TopologyResult | null`. Dialog renders when `validationResult !== null`. Both triggers set this state. Dialog dismiss clears it.
**Warning signs:** Save triggers validation but no dialog appears because the dialog state is local to Toolbar.

### Pitfall 4: ConstantTemperature and HeatDiffusion Have No FlowPorts
**What goes wrong:** These thermal-only components have zero FlowPorts but exist in the nodes array. Validation naively checking "all ports connected" would skip them (correctly), but a poorly written check might flag them as errors.
**Why it happens:** Not all components are hydraulic. Two components (ConstantTemperature, HeatDiffusion) have no FlowPorts at all.
**How to avoid:** Filter to `port.type === "FlowPort"` before checking connection status. Components with zero FlowPorts produce zero node errors.
**Warning signs:** Thermal-only components show red rings despite having no FlowPorts to connect.

### Pitfall 5: Undo/Redo and errorNodeIds
**What goes wrong:** Undo restores old edges but errorNodeIds still reflects post-validation state, showing stale error rings.
**Why it happens:** `errorNodeIds` is not part of `CanvasSnapshot` (and shouldn't be -- it's derived state, not content).
**How to avoid:** Clear `errorNodeIds` on undo/redo. Validation errors are only meaningful at the moment of export/save; after any topology change they should be cleared since the user hasn't re-triggered validation.
**Warning signs:** User undoes an edge addition, but the error ring that was cleared by that edge stays gone.

## Code Examples

### AlertDialog shadcn Component Usage
```typescript
// Source: shadcn alert-dialog docs
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";

// Controlled open state (no trigger -- opened programmatically)
<AlertDialog open={isOpen} onOpenChange={setIsOpen}>
  <AlertDialogContent>
    <AlertDialogHeader>
      <AlertDialogTitle>Validation Failed</AlertDialogTitle>
      <AlertDialogDescription>
        Fix the following issues before exporting.
      </AlertDialogDescription>
    </AlertDialogHeader>
    {/* Error list body */}
    <AlertDialogFooter>
      <AlertDialogAction>Back to Canvas</AlertDialogAction>
    </AlertDialogFooter>
  </AlertDialogContent>
</AlertDialog>
```

### Zustand Store Selector for Error Ring
```typescript
// In StreamNode.tsx -- subscribe to only this node's error status
const hasError = useStore(
  useCallback((s) => s.errorNodeIds.has(id), [id])
);
```

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | vitest (via gui/package.json) |
| Config file | gui/vitest.config.ts |
| Quick run command | `cd gui && npx vitest run --passWithNoTests` |
| Full suite command | `cd gui && npx vitest run` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| VALD-01 | Unconnected FlowPort detected | unit | `cd gui && npx vitest run src/lib/validation.test.ts -t "unconnected"` | Wave 0 |
| VALD-02 | Empty bcs triggers system error | unit | `cd gui && npx vitest run src/lib/validation.test.ts -t "pressure"` | Wave 0 |
| VALD-03 | No Pump/Gravity triggers system error | unit | `cd gui && npx vitest run src/lib/validation.test.ts -t "driving"` | Wave 0 |

### Sampling Rate
- **Per task commit:** `cd gui && npx vitest run`
- **Per wave merge:** `cd gui && npx vitest run`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `gui/src/lib/validation.test.ts` -- covers VALD-01, VALD-02, VALD-03 (pure function tests, no DOM needed)

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| @radix-ui/react-alert-dialog | AlertDialog component | Yes | via radix-ui@1.4.3 | -- |
| shadcn CLI | Generate alert-dialog.tsx | Yes | installed | -- |
| vitest | Tests | Yes | installed | -- |
| lucide-react | AlertTriangle icon | Yes | 1.7.0 | -- |

No missing dependencies.

## Open Questions

1. **Save validation trigger architecture**
   - What we know: Export button is in Toolbar.tsx (React component). Save is in the Zustand store action (async function). Both need to show the same dialog.
   - What's unclear: The save action is a store function with no React rendering context.
   - Recommendation: Store the validation result in Zustand (`validationResult: TopologyResult | null`). A `ValidationDialog` component at the App level reads this state. Both export and save set this state instead of directly opening a dialog. The save action sets the result and returns early (does not proceed with file write). The dialog dismiss callback clears the result. This gives both triggers a unified path to the dialog.

## Sources

### Primary (HIGH confidence)
- `gui/src/store/useStore.ts` -- Zustand store structure, undo/redo pattern, addEdge action
- `gui/src/components/StreamNode.tsx` -- Current ring implementation (`ring-2 ring-[var(--ring)]`)
- `gui/src/components/Toolbar.tsx` -- Export button handler location
- `gui/src/registry/components.json` -- All 12 components, port definitions (verified: all hydraulic components have exactly port_in + port_out; 2 thermal-only components have zero FlowPorts)
- `gui/src/lib/validation.ts` -- Existing field validation file (will add topology validation here)
- `.planning/phases/39-topology-validation/39-UI-SPEC.md` -- UI design contract
- `.planning/phases/39-topology-validation/39-CONTEXT.md` -- User decisions D-01 through D-12

### Secondary (MEDIUM confidence)
- shadcn AlertDialog documentation (controlled open state pattern)
- Tailwind ring vs outline CSS property separation for dual-ring coexistence

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - all libraries already installed and used in project
- Architecture: HIGH - straightforward pure function + store action + component pattern matches existing codebase conventions
- Pitfalls: HIGH - ring collision and Set reactivity are well-documented Tailwind/Zustand gotchas; save trigger architecture verified against actual store code

**Research date:** 2026-04-03
**Valid until:** 2026-05-03 (stable -- no fast-moving dependencies)
