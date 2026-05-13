# Phase 63: BCs tab + value-source components in GUI — Research

**Researched:** 2026-05-13
**Domain:** GUI (React + ReactFlow + zustand + shadcn) **and** Julia helpers (src/utilities.jl)
**Confidence:** HIGH — every recommendation cross-checks against the verified Phase 62 store, the verified ReactFlow v12 API, and the verified Phase 62 utilities helper precedent.

## Summary

Phase 63 is a two-language, four-surface change that ships the user-visible mechanism for v1.1 channel external-input BCs. The surfaces are: (1) the right-sidebar Properties/BCs tab split with a 5-pill mode picker per field, (2) a `BCEdge` custom-edge renderer with a click-to-cycle target-side chip, (3) extensions to `StreamNode` (BCPort hollow-square handle + whole-body drop activation filtered by in-flight drag's source-port type), and (4) a new store slice `bcMode` keyed by `(componentId, externalInputName)` with codegen consuming it for per-mode Julia emission. The Julia side is a single new helper `rebin_intensive` in `src/utilities.jl` with tests in `test/test_utilities.jl`, plus an export append in `STREAM.jl`.

**Primary recommendation:** Partition the plan into **four sub-plans** that minimize coupling:

| Sub-plan | Scope | Smoke-test surface |
|----------|-------|---------------------|
| **63-A: Julia rebin_intensive helper** | `src/utilities.jl` + `test/test_utilities.jl` + `STREAM.jl` export | `bin/jl test/test_utilities.jl` |
| **63-B: Store + codegen** | `useStore.ts` (`bcMode` slice, validation hooks, edge-deletion sync) + `codeGenerator.ts` (5-mode emit) + tests | `gui && npm test` (vitest) |
| **63-C: BCs tab UI** | `SidebarPanel.tsx` Tabs strip, new `BCsTabForm.tsx`, new `SegmentedButtonGroup.tsx` primitive (extracted from `ModeToggle`), `ToolboxPanel.tsx` Sources entries | `npm run tauri dev` — click Channel, observe tab strip + mode picker; drag WT from toolbox |
| **63-D: Canvas BC edge + drop target** | `StreamNode.tsx` (BCPort handle + whole-body drop), new `BCEdge.tsx`, `CanvasPanel.tsx` (edgeTypes register, isValidConnection extension) | `npm run tauri dev` — drag from WT.T_wall_out to Channel body, see dashed edge with chip |

63-A and 63-B can ship in parallel (independent files). 63-C depends on 63-B (consumes store). 63-D depends on 63-B (consumes store + codegen for round-trip) and 63-C (the BCs tab "Source" mode picker triggers the same store mutation that creates the canvas edge).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| BC mode authoring (5-pill picker, editor) | React UI (sidebar) | Zustand store | Authored in sidebar; persisted in store; bidirectionally synced to canvas |
| BC edge rendering (dashed line + chip) | ReactFlow custom edge | EdgeLabelRenderer portal | Visual idiom in BCEdge; click chip is HTML overlay (SVG can't render clickable text natively) |
| BC drop target activation | StreamNode renderer | useConnection hook | Whole-body drop zone reads in-flight drag's `fromHandle` data.portType |
| BC type-check + n-mismatch | `isValidConnection` (hard-block) + store `addEdge` post-check (soft-warn) | Registry FK lookup | Type mismatch blocked at connect; n-mismatch creates edge + flags red-ring |
| `bcMode` state | Zustand store slice | Snapshot via `_pushSnapshot` | Single source of truth; edge & BCs-tab subscribe to same entry |
| Codegen 5-mode emission | `codeGenerator.ts` (pure) | Reads store snapshot | Per-mode Julia text; no React deps; emitted post-component, pre-`eqs` |
| `rebin_intensive` math | Julia (`src/utilities.jl`) | Tests in `test/test_utilities.jl` | Mirrors `rebin_extensive`; runs at script runtime, not at codegen |
| Cosine helper for BCs | Julia (reuse `cosine_power_shape`) | — | Mathematically identical shape; rename context only |

## Standard Stack

### Already in the project — no new dependencies

| Library | Version | Purpose | Why standard |
|---------|---------|---------|--------------|
| `@xyflow/react` | ^12.10.2 [VERIFIED: gui/package.json] | Canvas, custom nodes/edges, connection state hook | Already the project's flow library |
| `zustand` | ^5.0.12 [VERIFIED: gui/package.json] | Store with `_pushSnapshot` discipline | Phase 62 dropped zundo middleware for explicit snapshots |
| `react` | ^19.1.0 [VERIFIED: gui/package.json] | UI | — |
| `radix-ui` | ^1.4.3 [VERIFIED: gui/package.json] | shadcn primitives (Tabs, Button, Select, Popover, Separator) | All required primitives already imported |
| `lucide-react` | ^1.7.0 [VERIFIED: gui/package.json] | Icons (Info, etc.) | Already in use |

### ReactFlow v12 APIs used in Phase 63

| API | Purpose in Phase 63 | Source |
|-----|---------------------|--------|
| `useConnection()` | Read in-flight drag state to activate whole-body drop target [CITED: reactflow.dev/api-reference/hooks/use-connection] | Already exists in v12.10 |
| `ConnectionState.fromHandle` | Inspect source handle (carries `data.portType`) during drag [CITED: reactflow.dev/api-reference/types/connection-state] | Returns `Handle \| null`; `inProgress`, `isValid`, `fromNode`, `fromPosition` also available |
| `EdgeLabelRenderer` | Render the HTML click-to-cycle chip mid-edge (escapes SVG) [CITED: reactflow.dev/api-reference/components/edge-label-renderer] | Portal-based; requires `pointerEvents: 'all'` + `nopan` className |
| `getSmoothStepPath` | Already used by HydraulicEdge; returns `[path, labelX, labelY]` | The 2nd/3rd tuple elements give the chip anchor point |
| `BaseEdge` | Already used by HydraulicEdge; renders the SVG path | Style overrides per D-12 |
| `isValidConnection` callback | Already wired in CanvasPanel.tsx:141 for FlowPort↔FlowPort enforcement | Extended in Phase 63 with BCPort type-check rules (D-21) |

> [VERIFIED: WebFetch reactflow.dev] All four ReactFlow APIs above are documented for v12. `useConnection` returns null when no drag is in progress; during a drag it returns `{ inProgress, isValid, fromHandle, fromNode, fromPosition, from, to, toHandle, toNode, toPosition, pointer }`.

### Julia helpers (existing — Phase 63 extends one file)

| Symbol | Location | Status in Phase 63 |
|--------|----------|---------------------|
| `_rebin_1d` (private) | `src/utilities.jl` | **Reused** as-is — both extensive and intensive 1D passes share the same overlap arithmetic |
| `rebin_extensive` | `src/utilities.jl` | Reference for separable z-then-x ordering pattern |
| `cosine_power_shape(nz, nx; amplitude)` | `src/utilities.jl` | **Reused** for BC Profile mode — mathematically identical shape, just different physical interpretation (see CD-02 recommendation below) |

**No new package dependencies for Julia.** `rebin_intensive` uses only base Julia (matches `rebin_extensive`).

## Architecture Patterns

### System Architecture Diagram

```
User edits BCs tab               User drags BCPort handle             User clicks BC edge chip
       │                              from WT.T_wall_out                      │
       ▼                                     │                                ▼
┌──────────────────┐                         ▼                       ┌─────────────────┐
│ SidebarPanel     │              ┌──────────────────────┐           │ BCEdge          │
│   ↓ tab strip    │              │ ReactFlow useConn()  │           │  ↓ chip click    │
│   ↓ BCsTabForm   │              │  fromHandle.data     │           │   (L+R → L → R) │
│   ↓ 5-pill       │              │   .portType="BCPort" │           └────────┬────────┘
│   ↓ per-mode     │              └──────────┬───────────┘                    │
│     editor       │                         │ filter activation               │
└────────┬─────────┘                         ▼                                 │
         │                          ┌──────────────────────┐                   │
         │ setBCMode()              │ StreamNode (target)  │                   │
         │ (componentId,            │  whole-body drop     │                   │
         │  externalInputName,      │  outline + chip      │                   │
         │  {mode, params})         └──────────┬───────────┘                   │
         │                                     │ onDrop                       │
         │                                     ▼                              │
         │                          ┌──────────────────────┐                  │
         │                          │ store.setBCMode      │                  │
         │                          │ (mode='source',      │                  │
         │                          │  sourceNodeId)       │                  │
         ▼                          └──────────┬───────────┘                  │
┌─────────────────────────────────────────────────────────────────────────────┴───┐
│                          useStore — Zustand                                       │
│  bcMode: Record<"<componentId>::<externalInputName>", BCModeEntry>                │
│  edges: Edge[] (BC edges derived from bcMode entries with mode='source')          │
│  _pushSnapshot() before every mutation → _undoPast stack                          │
└─────┬────────────────────────────────────────────────────────────────┬───────────┘
      │ subscriber                                                       │ subscriber
      ▼                                                                  ▼
┌──────────────────┐                                            ┌──────────────────┐
│ codeGenerator.ts │                                            │ CanvasPanel      │
│  (pure)          │                                            │  edges → ReactFlow│
│  ↓ per-mode emit │                                            │  + BCEdge renderer│
└─────────┬────────┘                                            └──────────────────┘
          │
          ▼
   Generated .jl text
   (Code Preview panel)
```

### Recommended Project Structure

```
gui/src/
├── components/
│   ├── BCEdge.tsx                              # NEW: dashed edge + click-to-cycle chip
│   ├── StreamNode.tsx                          # MODIFIED: BCPort handle + whole-body drop
│   ├── CanvasPanel.tsx                         # MODIFIED: register BCEdge type, extend isValidConnection
│   ├── ToolboxPanel.tsx                        # MODIFIED: render WT + HFS under Sources
│   └── sidebar/
│       ├── SidebarPanel.tsx                    # MODIFIED: Tabs strip when external_inputs.length > 0
│       ├── BCsTabForm.tsx                      # NEW: BCs-tab body — symmetric toggle + per-field 5-pill picker
│       ├── BCModePicker.tsx                    # NEW: 5-pill segmented control with required-unset state
│       ├── SegmentedButtonGroup.tsx            # NEW: extracted primitive (replaces ModeToggle's inline JSX)
│       ├── ModeToggle.tsx                      # MODIFIED: delegate to SegmentedButtonGroup
│       └── bc-editors/                         # NEW directory for per-mode editor components
│           ├── BCValueEditor.tsx               # mode=Value (reuses NumericField)
│           ├── BCProfileEditor.tsx             # mode=Profile (preset + import)
│           ├── BCFunctionEditor.tsx            # mode=Function (signature picker + name)
│           ├── BCMarkEditor.tsx                # mode=Mark (no editor body)
│           └── BCSourceEditor.tsx              # mode=Source (dropdown + inline + New)
├── store/
│   └── useStore.ts                             # MODIFIED: bcMode slice, actions, snapshot integration
└── lib/
    ├── codeGenerator.ts                        # MODIFIED: per-mode emit shapes
    └── bcMode.ts                               # NEW: shared types + bcModeKey() helper

src/
└── utilities.jl                                # MODIFIED: append rebin_intensive (1D + 2D)

test/
└── test_utilities.jl                           # MODIFIED: append mean-conservation tests
```

### Pattern 1: Per-mode store key shape

The store entry per `(componentId, externalInputName)` is discriminated by mode:

```typescript
// gui/src/lib/bcMode.ts (NEW)
export type BCModeEntry =
  | { mode: "value"; value: number }
  | { mode: "profile"; preset: "cosine"; amplitude: number; peakingFactor: number }
  | { mode: "profile"; preset: "file"; path: string }
  | { mode: "function"; signature: "fn(t)" | "fn(t, i)"; functionName: string }
  | { mode: "mark" }
  | { mode: "source"; sourceNodeId: string };

// Composite key — Map lookup faster than nested Record. Pick one and stick with it.
export function bcModeKey(componentId: string, externalInputName: string): string {
  return `${componentId}::${externalInputName}`;
}

export interface BCEdgeData {
  componentId: string;                 // consumer node id
  externalInputName: string;           // "T_wall_left" / "T_wall_right" / "q_left" / "q_right"
  targetSide: "left" | "right" | "both";
}
```

`bcMode` lives in the store as `Record<string, BCModeEntry>` keyed by `bcModeKey()`. Absence of a key = required-unset (D-09).

> **Note on the "symmetric" L=R toggle (D-05):** The toggle is a *view affordance* — it means "edit one editor, write to both keys." Implementation: when symmetric is ON, `setBCMode("…::T_wall_left", entry)` also writes the same entry under `…::T_wall_right`. When OFF, the two keys hold independent entries. The toggle state itself is persisted per-component-instance under `node.data.bcSymmetric: Record<string /* base field */, boolean>` (see CD-05 recommendation below).

### Pattern 2: Whole-body drop target via useConnection (D-10, CD-03 recommendation)

```typescript
// Inside StreamNode.tsx
import { useConnection } from "@xyflow/react";

const connection = useConnection();
const inFlightFromBCPort =
  connection?.inProgress &&
  connection.fromHandle?.id != null &&
  // Look up port type from registry using fromHandle.nodeId + handleId.
  // Cannot rely on connection.fromHandle.data — ReactFlow v12 doesn't carry
  // arbitrary handle data into ConnectionState. Use the registry-driven lookup
  // that CanvasPanel.tsx already exposes (`getPortType(nodeId, handleId)`).
  getPortType(connection.fromNode!.id, connection.fromHandle.id) === "BCPort";

const isConsumerNode =
  component.external_inputs != null && component.external_inputs.length > 0;

const dropActive = inFlightFromBCPort && isConsumerNode;
```

Render a dashed-outline overlay + "Connect BC" chip when `dropActive === true`. On `onMouseUp` while `dropActive`, programmatically dispatch a connect (call `store.setBCMode` with `mode: 'source'` and `sourceNodeId: connection.fromNode.id`, which in turn adds the edge — see Pattern 6).

**Recommended path among CD-03's three candidates:** **Pure CSS overlay driven by `useConnection`** (Pattern 2). Rejected alternatives:
- *Invisible child handle*: ReactFlow would treat it as a real handle, polluting the connection state and breaking the "Channels have NO visible BC handle" §3.11 invariant. Wrong tier — this is a view concern, not a data-graph concern.
- *Custom node prop*: Would require plumbing through the registry; less local than `useConnection`. The hook already exists for exactly this use case.

The CSS-overlay approach is **idiomatic ReactFlow v12** per their docs ("typical use case is to colorize handles based on a certain condition").

### Pattern 3: BCEdge custom edge (D-11 + D-12)

```typescript
// gui/src/components/BCEdge.tsx (NEW — sibling of HydraulicEdge.tsx)
import { memo } from "react";
import { getSmoothStepPath, BaseEdge, EdgeLabelRenderer, type EdgeProps } from "@xyflow/react";
import useStore from "../store/useStore";

const SIDE_LABELS: Record<"left" | "right" | "both", string> = {
  left: "L", right: "R", both: "L+R",
};
const SIDE_CYCLE: Record<"left" | "right" | "both", "left" | "right" | "both"> = {
  both: "left", left: "right", right: "both",
};

function BCEdge({ id, sourceX, sourceY, targetX, targetY, sourcePosition, targetPosition, data }: EdgeProps) {
  const [path, labelX, labelY] = getSmoothStepPath({
    sourceX, sourceY, targetX, targetY, sourcePosition, targetPosition,
  });
  const targetSide = (data as { targetSide?: "left" | "right" | "both" })?.targetSide ?? "both";
  const cycleSide = useStore((s) => s.cycleBCEdgeTargetSide);

  return (
    <>
      <BaseEdge
        id={id}
        path={path}
        style={{ stroke: "var(--muted-foreground)", strokeWidth: 1.5, strokeDasharray: "6 3" }}
      />
      <EdgeLabelRenderer>
        <div
          className="nopan"
          style={{
            position: "absolute",
            transform: `translate(-50%, -50%) translate(${labelX}px, ${labelY}px)`,
            background: "var(--background)",
            border: "1px solid var(--muted-foreground)",
            borderRadius: 4,
            padding: "0 4px",
            fontSize: 10,
            lineHeight: "16px",
            color: "var(--muted-foreground)",
            cursor: "pointer",
            pointerEvents: "all",
            userSelect: "none",
          }}
          onClick={(e) => {
            e.stopPropagation();
            cycleSide(id, SIDE_CYCLE[targetSide]);
          }}
        >
          {SIDE_LABELS[targetSide]}
        </div>
      </EdgeLabelRenderer>
    </>
  );
}

export default memo(BCEdge);
```

**Key facts:**
- The chip is HTML (via `EdgeLabelRenderer` portal), **not SVG text** — necessary because SVG `<text>` is not clickable without complex pointer-events tricks, and HTML lets us reuse CSS tokens (`var(--background)`, `var(--muted-foreground)`).
- `nopan` class prevents ReactFlow from panning the canvas while the user clicks the chip [CITED: reactflow.dev/api-reference/components/edge-label-renderer].
- `pointerEvents: "all"` is mandatory — EdgeLabelRenderer's default container has no pointer events.
- The chip's click handler calls a new store action `cycleBCEdgeTargetSide(edgeId, newSide)` that pushes a snapshot and updates `edge.data.targetSide`.

### Pattern 4: Segmented control primitive (D-04, CD-shared)

Extract a `SegmentedButtonGroup<T>` from `ModeToggle.tsx`:

```typescript
// gui/src/components/sidebar/SegmentedButtonGroup.tsx (NEW)
import { Button } from "@/components/ui/button";

interface SegmentedButtonGroupProps<T extends string> {
  options: Array<{ value: T; label: string }>;
  /** undefined = no active pill (required-unset state, D-09). */
  active: T | undefined;
  onChange: (value: T) => void;
  /** Size of the buttons (matches shadcn Button size variants). */
  size?: "sm" | "default";
}

export default function SegmentedButtonGroup<T extends string>({
  options, active, onChange, size = "sm",
}: SegmentedButtonGroupProps<T>) {
  return (
    <div className="flex">
      {options.map((opt, idx) => (
        <Button
          key={opt.value}
          variant={opt.value === active ? "default" : "outline"}
          size={size}
          className={
            idx === 0 ? "rounded-r-none"
            : idx === options.length - 1 ? "rounded-l-none"
            : "rounded-none"
          }
          onClick={() => onChange(opt.value)}
        >
          {opt.label}
        </Button>
      ))}
    </div>
  );
}
```

> [VERIFIED: gui/src/components/sidebar/ModeToggle.tsx] The required-unset state is **trivially supported** by shadcn's `variant="default"` vs `variant="outline"` pattern: when `active === undefined`, no button matches, so every button renders as `outline`. No hack needed.

`ModeToggle.tsx` becomes a thin wrapper that maps `ConstructorMode[]` to `options` and forwards.

### Pattern 5: Tabs strip (D-01, D-03)

`SidebarPanel.tsx`'s component branch grows from:

```typescript
<InstanceNameField ... />
<Badge>{component.label}</Badge>
<Separator />
{/* ... ModeToggle + ParameterForm ... */}
```

to:

```typescript
<InstanceNameField ... />
<Badge>{component.label}</Badge>
<Separator />
{component.external_inputs && component.external_inputs.length > 0 ? (
  // Tab strip + Tabs from radix-ui (shadcn pattern). D-03: resets to "Properties" on selection change.
  <Tabs value={activeTab} onValueChange={setActiveTab}>
    <TabsList>
      <TabsTrigger value="properties">Properties</TabsTrigger>
      <TabsTrigger value="bcs">BCs</TabsTrigger>
    </TabsList>
    <TabsContent value="properties">
      <ModeToggle ... />
      <ParameterForm ... />
    </TabsContent>
    <TabsContent value="bcs">
      <BCsTabForm component={component} nodeId={selectedNodeId} />
    </TabsContent>
  </Tabs>
) : (
  // Today's behavior — no tabs.
  <>
    <ModeToggle ... />
    <ParameterForm ... />
  </>
)}
```

**D-03 reset behavior:** Reset `activeTab` to `"properties"` whenever `selectedNodeId` changes. The existing `<div key={selectedNodeId}>` pattern in SidebarPanel.tsx:151 already remounts the whole branch on selection change — so a `useState("properties")` inside that subtree resets automatically without extra useEffect plumbing. **Use the remount-resets-state pattern, don't add useEffect dependencies.**

### Pattern 6: Store slice — bcMode + edge derivation (D-23)

**Critical design question:** Does the store hold BC edges directly in `edges[]`, or derive them from `bcMode` entries via a selector?

**Recommendation: hold them directly in `edges[]`, with a strict invariant that BC edges' existence is *only* mutated by `setBCMode`/`removeBCMode`/`removeEdge` paths.**

Rationale:
- ReactFlow's `applyEdgeChanges` mutates `edges[]` in place for `select`, `position`, `remove` events. A derived-via-selector approach would fight this (we'd need to suppress ReactFlow's edge mutations for BC edges only).
- `enrichEdges` in useStore.ts:493 already gates edge typing by inspecting source-port type at mutation time. The same pattern extends naturally: BC edges get `type: "bcEdge"`, hydraulic gets `type: "hydraulicEdge"`, thermal gets dashed amber.
- `onEdgesChange` already snapshots on `"remove"` (useStore.ts:709). When a BC edge is removed via Delete key, we need to ALSO revert the corresponding `bcMode` entry — that revert lives in a new helper `_onBCEdgeRemoved(edgeId)` called from `onEdgesChange` and `removeEdge`.

**Store contract:**

```typescript
// New state
bcMode: Record<string, BCModeEntry>;   // keyed by bcModeKey()
bcSymmetric: Record<string, Record<string, boolean>>;
   // nodeId -> { "T_wall": true, ... }; missing = ON (default per D-05).

// New actions
setBCMode(componentId, externalInputName, entry): void
clearBCMode(componentId, externalInputName): void
setBCEdgeTargetSide(edgeId, side): void
cycleBCEdgeTargetSide(edgeId, nextSide): void  // helper called by BCEdge chip
setBCSymmetric(nodeId, baseField, symmetric): void  // "T_wall" / "q" (no _left/_right)

// Internal — called from addEdge / onEdgesChange / removeEdge when an edge is a BC edge:
_onBCEdgeAdded(edge): void   // store mutation when a Source-mode edge is created on the canvas
_onBCEdgeRemoved(edge): void // revert bcMode to prior mode (or undefined)
```

**Snapshot granularity:** Phase 62's `_pushSnapshot` pattern (useStore.ts:613-622) captures the whole `{nodes, edges, bcs, resources, modelOptions}` — Phase 63 must add `bcMode` and `bcSymmetric` to `CanvasSnapshot`. **No partialize/equality semantics needed because Phase 62 dropped zundo entirely** (useStore.ts:601-608: *"Why not zundo (temporal middleware)? ReactFlow fires many noise events…"*).

> **Correction to the question in the objective:** The objective references "zundo's `partialize` and `equality` functions," but Phase 62's RESEARCH-driven decision was to **drop zundo**. Phase 63 uses the explicit-snapshot pattern. `zundo` remains in `package.json` (^2.3.0) but is unused; cleaning it up is out of scope for Phase 63 — let Phase 66/67 prune.

### Pattern 7: Validation hooks at connect time (D-21, D-22)

`isValidConnection` (CanvasPanel.tsx:141) extends to:

```typescript
const isValidConnection = useCallback((connection: Edge | Connection) => {
  if (!connection.source || !connection.target || !connection.sourceHandle || !connection.targetHandle) return false;
  const sourceType = getPortType(connection.source, connection.sourceHandle);
  const targetType = getPortType(connection.target, connection.targetHandle);

  // Existing FlowPort/ThermalPort rule preserved.
  if (sourceType === "FlowPort" || sourceType === "ThermalPort") {
    if (sourceType !== targetType) return false;
    return true;
  }

  // NEW Phase 63: BCPort-source connection rules (D-21).
  if (sourceType === "BCPort") {
    // Drops are NOT onto handles; they're onto the whole node body. But ReactFlow
    // still calls isValidConnection with a synthetic target handle when the user
    // releases over a node. We need to validate by source component + target component
    // identity (per the WT→Channel / HFS→CHF table in D-21).
    const srcNode = useStore.getState().nodes.find(n => n.id === connection.source);
    const tgtNode = useStore.getState().nodes.find(n => n.id === connection.target);
    if (!srcNode || !tgtNode) return false;
    const srcCompId = (srcNode.data as StreamNodeData).componentId;
    const tgtCompId = (tgtNode.data as StreamNodeData).componentId;
    if (srcCompId === "WallTemperature"  && tgtCompId === "Channel")         return true;
    if (srcCompId === "HeatFluxSource"   && tgtCompId === "ChannelHeatFlux") return true;
    return false; // Hard-block everything else (D-21: CAC always blocked, cross-type always blocked).
  }
  return false;
}, []);
```

The **n-mismatch soft warning (D-22)** is *post-creation*. It runs inside the BC-edge-added path (`_onBCEdgeAdded`) in the store and pushes both endpoints onto `errorNodeIds`, identical to how Phase 39 wires `validateAndGate` (useStore.ts:1120-1126).

### Pattern 8: Codegen per-mode emission (D-06 through D-09 + CD-01)

`codeGenerator.ts` already has a TODO at line 268-272 for exactly this. The cleanest emit order (matching the simple_loop.scp example structure):

```julia
using ModelingToolkit, STREAM
using ModelingToolkit: t_nounits as t
using DelimitedFiles  # only if any Profile-import is present

# ------ Resources ------ (Phase 62 — unchanged)
geom_mtr = PipeGeometry_rectangular(...)
power_shape_axial_cos_for_hd_1 = cosine_power_shape(5, 3; amplitude=1.0)

# ------ Components ------
@named pump_1 = Pump(; dP_pump=30000.0)
@named ch_1   = Channel(; n=10, geometry=geom_mtr, g=9.80665, h_left=15000.0, h_right=15000.0)
@named wt_inlet = WallTemperature(; n=10, T_wall=373.15)

# ------ BC profile imports ------ (Phase 63 NEW — emitted between @named and eqs)
T_wall_left_inlet  = rebin_intensive(readdlm(joinpath(@__DIR__, "shapes/inlet_T.csv"), ','), 10)

# ------ BC function stubs ------ (Phase 63 NEW)
ch_1_T_wall_right_fn(t, i) = 320.0  # TODO: define your time-varying boundary condition

# ------ Equations ------
eqs = [
    connect(pump_1.port_out, ch_1.port_in),
    connect(ch_1.port_out, pump_1.port_in),
    # NEW: BC bindings (one block per (component, external_input) with mode != Mark and != unset)
    [ch_1.T_wall_left[i]  ~ T_wall_left_inlet[i] for i in 1:10]...,
    [ch_1.T_wall_right[i] ~ ch_1_T_wall_right_fn(t, i) for i in 1:10]...,
    # Mode=Source becomes:
    # [ch_1.T_wall_left[i] ~ wt_inlet.T_wall_out[i] for i in 1:10]...,
    # Mode=Mark emits NO equation, just a comment:
    # TODO: set ch_1.T_wall_left[i] here
    # Mode=unset (required-unset) emits the same comment shape as Mark, per D-09.
]
```

**Emit phases (insertion points in the existing flat-string code):**

| Phase 63 insertion | Position in `codeGenerator.ts` | What it emits |
|---------------------|-------------------------------|---------------|
| `using DelimitedFiles` (already conditional for Phase 62 file-loaded shapes) | Existing logic — extend the OR condition to include "any BC in Profile mode with `preset === 'file'`" | Same line — already covered by `hasFileLoadedShape` shape; rename to `hasFileImport` |
| BC profile-import bindings | NEW section after the components loop (lines 902-941), BEFORE `eqs = [` | One assignment per `mode === 'profile'` BC field |
| BC function stubs | NEW section after profile-imports, BEFORE `eqs = [` | One stub def per `mode === 'function'` BC field |
| BC binding equations | NEW lines INSIDE the `eqs = [` block, AFTER `connect()` lines and BEFORE `bcs` (pressure anchors) | One `[ch.field[i] ~ expr for i in 1:n]...` per non-Mark, non-unset BC field |
| Mark/unset TODO comments | Emit AT TOP of the eqs block as `# TODO: set ch.field[i] here` (CD-01 default) | One comment per Mark / required-unset field |

**Why this insertion shape works with the planned Phase 66 `CodeSection[]` rework:** every Phase 63 addition is a coherent prefix of text (no inter-leaving with Phase 62 emit), so Phase 66 will be able to refactor each block into its own `CodeSection` cleanly. Phase 63 does NOT need to anticipate the section shape — flat strings now, structured later.

### Anti-Patterns to Avoid

- **Hand-rolling a connection-state subscriber via raw mouse events on StreamNode.** ReactFlow's `useConnection()` hook is the supported way to read in-flight drag state. A manual `mouseenter`/`mouseleave` listener would miss touch events, miss `Escape` cancellation, and re-implement state ReactFlow already exposes.
- **Storing `BCModeEntry` inside `node.data.bcMode`.** The bidirectional sync invariant (D-23) demands a *single* store entry that both the BCs tab and the canvas edge renderer read. Per-node embedding would create two sources of truth and require event plumbing to keep them in sync — the explicit thing the design rejects.
- **Implementing required-unset (D-09) via a magic "unset" mode value.** It's the **absence** of a key in the `bcMode` record. Storing `{mode: "unset"}` as an entry would force the UI to differentiate "never set" from "explicitly set to unset" — meaningless distinction. `bcMode[key] === undefined` is the correct sentinel, matching Phase 62's SENTINEL_UNSET_POWER_SHAPE handling at the store-load level.
- **Using SVG `<text>` for the click-to-cycle chip.** SVG text on edges is the wrong primitive: not styleable with Tailwind tokens, not focusable, can't host hover affordance, and clickable only via complex `pointer-events` setup. `EdgeLabelRenderer` is the supported portal.
- **Driving BC edges from a selector function `(state) => deriveBCEdges(state.bcMode)` recomputed on every render.** Two problems: (a) ReactFlow's edge model mutates `edges[]` for selection/drag (selectors would clobber the mutations), and (b) re-derivation on every store update is unnecessary for a single-source-of-truth that we already control at mutation points. Hold edges in `edges[]` directly and gate mutations.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| In-flight drag detection | `mousedown`/`mousemove` listeners on the canvas | `useConnection()` from `@xyflow/react` | Handles touch, escape, validity, browser quirks |
| Clickable label on a SVG edge | Custom SVG `<text>` + pointer-events hacks | `EdgeLabelRenderer` portal | Official ReactFlow primitive; HTML body |
| Tabs primitive | Custom tab strip | shadcn `Tabs` (already imported elsewhere) | Radix-backed; keyboard-accessible |
| 5-pill segmented control | New shadcn primitive | Extract `SegmentedButtonGroup<T>` from existing `ModeToggle.tsx` | Phase 62's idiom — keeps codebase DRY; required-unset works via "no value matches `active`" |
| Per-component popover for `+ New WallTemperature` | Custom anchored popover | Reuse Phase 62's `ResourceCreationPopover.tsx` discipline (anchored, no click-outside) | Established pattern; CONTEXT.md D-20 explicitly mirrors it |
| Area-weighted rebin in Julia | `for` loops in user codegen | `rebin_intensive` helper in `src/utilities.jl` | Symmetric companion to `rebin_extensive`; ~25 lines; one place to fix bugs |
| Axial cosine for T_wall profile | New `cosine_T_wall_profile` function | **Reuse `cosine_power_shape(n, 1; amplitude=...)[:, 1]`** OR add a 1-line alias for readability | Mathematically the same shape; see CD-02 recommendation |

**Key insight:** Two surfaces in Phase 63 — the in-flight drag detection and the edge label — have *exactly one* idiomatic ReactFlow v12 solution each (`useConnection` and `EdgeLabelRenderer`). The temptation to hand-roll is real but every hand-rolled variant has been seen as a pitfall in the ReactFlow community.

## Runtime State Inventory

Phase 63 is greenfield (new BCs tab, new BC edges, new Julia helper). No renames, no migrations of existing data.

- **Stored data:** None — `bcMode` slice is new; .scp schema gains a `bcs` extension field (the existing `bcs` array is for pressure anchors; Phase 63 adds a separate `bc_modes` block — see Pitfall 4 below for the schema-bump discussion).
- **Live service config:** None.
- **OS-registered state:** None.
- **Secrets/env vars:** None.
- **Build artifacts:** None — the Julia daemon (`bin/jl-up`) will pick up `rebin_intensive` via Revise; struct/type definitions don't change, so no daemon restart needed.

**Nothing in any category requires migration.** Existing .scp files load cleanly because the new `bc_modes` block is additive — absence on load means "all required-unset" (the brand-new-Channel default per D-09).

## Common Pitfalls

### Pitfall 1: Misreading `useConnection().fromHandle.data`

**What goes wrong:** Developer expects the source handle's `data` prop to flow through to `connection.fromHandle` as a `data` field.

**Why it happens:** StreamNode.tsx:74 already passes `data={{ portType: port.type }}` to each `<Handle>`. Reading the docs naively, you'd expect it to surface in ConnectionState.

**How to avoid:** ReactFlow v12's `ConnectionState.fromHandle` is a `Handle` object (typed by xyflow internals), not the JSX `data` prop. To get port type during a drag, **look it up from the registry using `fromNode.id` + `fromHandle.id`** — exactly what CanvasPanel.tsx already does in `getPortType(nodeId, handleId)` at line 25-32. Reuse this helper.

**Warning signs:** `connection.fromHandle.data` returns `undefined` despite the StreamNode JSX setting it.

### Pitfall 2: BCs tab body remount loses scroll position

**What goes wrong:** Switching from Properties to BCs scroll-jumps to top because the parent `<div key={selectedNodeId}>` remount cascades.

**Why it happens:** SidebarPanel.tsx:151 keys the entire body by `selectedNodeId` (intentional, to reset state on selection change per D-03).

**How to avoid:** The Tabs primitive should be the inner wrapper, not the outer. Place `<Tabs>` *inside* the `<div key={selectedNodeId}>`, so switching tabs is a normal tab switch (no remount), while switching nodes still remounts and resets the active tab back to "Properties."

**Warning signs:** Scroll jumps when clicking BCs tab the first time.

### Pitfall 3: BC edge delete via Delete key doesn't revert `bcMode`

**What goes wrong:** User has BC field in `mode: "source"`. They select the dashed edge on canvas and press Delete. The edge disappears, but the BCs tab still shows Source mode with a now-orphaned `sourceNodeId`.

**Why it happens:** `onEdgesChange` (useStore.ts:704) only snapshots and applies; doesn't inspect deleted edges.

**How to avoid:** Inside `onEdgesChange`, after computing the result of `applyEdgeChanges`, diff against the prior `edges[]` to find removed edges. For each removed BC edge, call `_onBCEdgeRemoved(edgeId)` which: (a) finds the consumer node + external_input from `edge.data`, (b) clears the matching `bcMode` entry, (c) optionally restores a prior non-source mode if we tracked one (D-23: "or back to required-unset if it was created fresh"). Simplest correct behavior: revert to `undefined` (required-unset). The "restore prior mode" path is nice-to-have polish; CONTEXT.md is ambiguous — recommend the simpler revert-to-undefined.

**Warning signs:** BCs tab Source mode shows a node-id that doesn't exist on the canvas.

### Pitfall 4: .scp schema bump for `bc_modes`

**What goes wrong:** Adding a new top-level `bc_modes` field to .scp without bumping `format_version` silently loads garbage when a pre-Phase-63 .scp is opened (or vice versa).

**Why it happens:** simple_loop.scp shows `"format_version": "2.0"` — Phase 62's bump. Phase 63 is additive but the schema *shape* changes.

**How to avoid:** Either (a) keep `format_version: "2.0"` and define `bc_modes` as optional (missing = empty record = all required-unset, matching brand-new-Channel default), OR (b) bump to `2.1` per semver-style "additive" rule and update `projectIO.ts` to accept both 2.0 and 2.1. **Recommend (a)** — strictly additive, no version bump needed; matches how `bcs` (pressure anchors) was added in Phase 36 without a bump.

**Warning signs:** Loading a Phase 62 .scp blows up; or Phase 63 .scp loaded in older build silently drops BC info.

### Pitfall 5: Codegen-time vs runtime confusion for `rebin_intensive`

**What goes wrong:** Developer tries to call `rebin_intensive` from TypeScript at codegen time to "pre-rebin" the CSV.

**Why it happens:** Familiarity with web-app dataflow where everything is JS.

**How to avoid:** D-16 is explicit — the call is emitted *as Julia text*, evaluated at script-run time. The CSV file lives on disk; the .scp stores only the *path* (D-24 + Phase 62 INV-10). TypeScript never reads the CSV. **Codegen emits a single Julia expression**: `rebin_intensive(readdlm(joinpath(@__DIR__, "<path>"), ','), n)`. This mirrors `rebin_extensive` precisely (codeGenerator.ts:867).

**Warning signs:** A TypeScript test file imports `rebin_intensive` from somewhere or tries to mock it.

### Pitfall 6: `cosine_power_shape` reuse vs alias

**What goes wrong:** Adding a `cosine_T_wall_profile(n; amplitude, peaking_factor)` Julia function that "wraps" `cosine_power_shape` introduces a slightly different signature (`peaking_factor` parameter) without a clear mathematical link.

**Why it happens:** D-06 says Profile mode has `amplitude` AND `peaking_factor`. `cosine_power_shape` only has `amplitude`.

**How to avoid:** **Recommendation for CD-02:**

- **Add a thin alias `cosine_T_wall_profile(n::Integer; amplitude::Real=1.0, peaking_factor::Real=1.0)`** in `src/utilities.jl`.
- Implement as: `peaking_factor .* cosine_power_shape(n, 1; amplitude)[:, 1]`. This is 1D (n-length Vector); the BCs tab Profile mode is per-side per-channel.
- Document the relationship in the docstring: *"Identical axial shape to `cosine_power_shape`; the separate function is for readability at call sites in BCs codegen."*
- The mathematical identity `peaking_factor * cos^2((i-0.5)π/n - π/2)` is well-defined: `peaking_factor` scales the peak-to-average ratio after `amplitude` scales the magnitude. For axial cosine on [0,1], avg = 0.5, peak = 1.0, so peak/avg = 2.0; a `peaking_factor` of 1.0 means no extra peaking beyond cosine, and >1 sharpens. (Document this; defer the actual peaking math to the planner — likely just `peaking_factor` as a multiplier on top of cos² since the design contract treats it as a free user param.)

**Why not reuse `cosine_power_shape` directly:** Two reasons. (1) Call site readability — `cosine_T_wall_profile(n; amplitude=20, peaking_factor=1.2)` reads naturally; `cosine_power_shape(n, 1; amplitude=20)[:, 1]` does not. (2) Future divergence — if Phase 71+ adds T_wall-specific options (e.g., offset baseline temperature), the alias gives us a place to put them without touching the power-shape function.

**Warning signs:** Inconsistent docstrings or two cosine implementations diverging silently.

### Pitfall 7: Soft-warn n-mismatch fires before edge is actually created

**What goes wrong:** `isValidConnection` returns true for `WallTemperature.n=10 → Channel.n=12`, ReactFlow calls `onConnect`, store calls `addEdge`, store dispatches n-mismatch red-ring. But if the user *cancels* the drag mid-way (releases off the node), `errorNodeIds` could have been pre-populated by a stale check.

**Why it happens:** `isValidConnection` runs per-mouse-move during the drag for visual feedback. Don't push state mutations from inside it.

**How to avoid:** Keep `isValidConnection` *pure* — it should only return boolean. The n-mismatch red-ring fires inside `addEdge` (or the new `_onBCEdgeAdded`), AFTER the connection is committed. No state mutation in `isValidConnection`.

**Warning signs:** Red ring flickering on nodes during incomplete drags.

## Code Examples

### Example 1: Julia `rebin_intensive` — 1D + 2D

```julia
# src/utilities.jl — append below rebin_extensive

"""
    _rebin_1d_intensive(v::AbstractVector{<:Real}, n_out::Integer) -> Vector{Float64}

Internal helper. Rebin a 1D intensive vector `v` of length `n_in` to length
`n_out`, preserving the area-weighted mean: `mean(out) == mean(v)` for
uniform input, and the integral `∫ v dx` is preserved up to floating-point
precision.

Each target cell `j` gets the area-weighted average of the source cells
overlapping it: `out[j] = Σᵢ v[i] · overlap_ij · n_out`. When `n_in == n_out`
the input is copied through unchanged.
"""
function _rebin_1d_intensive(v::AbstractVector{<:Real}, n_out::Integer)
    n_in = length(v)
    out  = zeros(Float64, n_out)
    if n_in == n_out
        copyto!(out, v)
        return out
    end
    inv_n_in = 1.0 / n_in
    for i in 1:n_in
        src_lo = (i - 1) * inv_n_in
        src_hi = i * inv_n_in
        j_lo = max(1, floor(Int, src_lo * n_out) + 1)
        j_hi = min(n_out, ceil(Int, src_hi * n_out))
        for j in j_lo:j_hi
            tgt_lo = (j - 1) / n_out
            tgt_hi = j / n_out
            overlap = max(0.0, min(src_hi, tgt_hi) - max(src_lo, tgt_lo))
            # Intensive: divide by target-cell width (1/n_out) <=> multiply by n_out.
            out[j] += v[i] * overlap * n_out
        end
    end
    return out
end

"""
    rebin_intensive(v::AbstractVector{<:Real}, n_target::Integer) -> Vector{Float64}
    rebin_intensive(M::AbstractMatrix{<:Real}, target_shape::Tuple{Int,Int}) -> Matrix{Float64}

Conservatively rebin an intensive quantity (T, q heat-flux density, p, etc.)
to a new grid, preserving the area-weighted mean. Symmetric to
`rebin_extensive` (which preserves the sum / integrated total).

Used by Phase 63 codegen for Profile-mode imports on BC fields. Caller-trust
posture (per `feedback_power_shape_trust_caller.md`): no validation, no
normalization, no NaN guards. Negative values, zeros, and NaNs flow through.

# Identity (cross-check with rebin_extensive)

For any input vector `v` of length `n_in`,
```
rebin_intensive(v, n_out) ≈ rebin_extensive(v, n_out) .* (n_out / n_in)
```
to floating-point precision. This follows from `rebin_extensive` being a
linear operation that preserves `sum`, and `rebin_intensive` being the
same linear operation rescaled by the target/source cell-width ratio.
"""
function rebin_intensive(v::AbstractVector{<:Real}, n_target::Integer)
    return _rebin_1d_intensive(v, n_target)
end

function rebin_intensive(M::AbstractMatrix{<:Real}, target_shape::Tuple{Int,Int})
    nz_out, nx_out = target_shape
    nz_in, nx_in   = size(M)
    # Separable: pass 1 along z, pass 2 along x. Same z-then-x ordering as
    # rebin_extensive for reproducibility.
    intermediate = Matrix{Float64}(undef, nz_out, nx_in)
    for j in 1:nx_in
        intermediate[:, j] = _rebin_1d_intensive(view(M, :, j), nz_out)
    end
    out = Matrix{Float64}(undef, nz_out, nx_out)
    for i in 1:nz_out
        out[i, :] = _rebin_1d_intensive(view(intermediate, i, :), nx_out)
    end
    return out
end
```

### Example 2: `rebin_intensive` test (mean-conservation + cross-check identity)

```julia
# test/test_utilities.jl — append below the existing CONS-01..04 testsets.

@testset "INT-01: rebin_intensive uniform input is exactly preserved" begin
    # rebin_intensive(ones(N), M) == ones(M) for any N, M
    @test all(rebin_intensive(ones(5), 7) .≈ 1.0)
    @test all(rebin_intensive(ones(7), 3) .≈ 1.0)
    @test all(rebin_intensive(fill(3.14, 4), 9) .≈ 3.14)
end

@testset "INT-02: rebin_intensive identity (target == source)" begin
    v = rand(8)
    @test rebin_intensive(v, 8) == v
    M = rand(4, 6)
    @test rebin_intensive(M, (4, 6)) == M
end

@testset "INT-03: rebin_intensive ≈ rebin_extensive * (n_out / n_in) — D-15 cross-check" begin
    rtol = 1e-12
    for (n_in, n_out) in [(4, 9), (9, 4), (5, 7), (8, 1), (1, 8), (3, 12)]
        v = rand(n_in)
        ext_scaled  = rebin_extensive(reshape(v, n_in, 1), (n_out, 1))[:, 1] .* (n_out / n_in)
        int_direct  = rebin_intensive(v, n_out)
        @test isapprox(int_direct, ext_scaled; rtol=rtol)
    end
end

@testset "INT-04: rebin_intensive 2D — same identity, separable" begin
    M = rand(5, 7)
    rtol = 1e-12
    out_int = rebin_intensive(M, (9, 3))
    # area-weighted total: sum(M) * (1/(5*7)) * (9*3) == sum(out_int) * (1/(9*3)) * (9*3)
    @test isapprox(
        sum(out_int) * (1.0 / (9 * 3)),
        sum(M) * (1.0 / (5 * 7));
        rtol=rtol,
    )
end

@testset "INT-05: degenerate row/column passthroughs" begin
    @test all(rebin_intensive(ones(1, 8), (1, 3)) .≈ 1.0)
    @test all(rebin_intensive(fill(7.0, 8, 1), (3, 1)) .≈ 7.0)
end
```

> **Math verification of D-15 identity** [VERIFIED: derivation in this RESEARCH session]: For source cell width `dx_src = 1/n_in` and target cell width `dx_tgt = 1/n_out`, the extensive rebin assigns `out_ext[j] = Σᵢ v[i] · (overlap_ij / dx_src) = Σᵢ v[i] · overlap_ij · n_in`. The intensive rebin assigns `out_int[j] = Σᵢ v[i] · (overlap_ij / dx_tgt) = Σᵢ v[i] · overlap_ij · n_out`. Therefore `out_int[j] = out_ext[j] · (n_out / n_in)`. The user-suggested form `rebin_intensive(x, n) == rebin_extensive(x .* dx_src, n) ./ dx_tgt` is algebraically equivalent: `rebin_extensive(x .* dx_src, n) = rebin_extensive(x, n) .* dx_src` (linearity), then `÷ dx_tgt` gives `rebin_extensive(x, n) .* (dx_src / dx_tgt) = rebin_extensive(x, n) .* (n_out/n_in)`. Same identity, two forms. The Test 3 form `int_direct ≈ ext * (n_out/n_in)` is simpler — recommend that one.

### Example 3: BCs tab body skeleton

```typescript
// gui/src/components/sidebar/BCsTabForm.tsx (NEW)
import { useState } from "react";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Separator } from "@/components/ui/separator";
import useStore from "@/store/useStore";
import { bcModeKey, type BCModeEntry } from "@/lib/bcMode";
import BCModePicker from "./BCModePicker";
import BCValueEditor from "./bc-editors/BCValueEditor";
import BCProfileEditor from "./bc-editors/BCProfileEditor";
import BCFunctionEditor from "./bc-editors/BCFunctionEditor";
import BCSourceEditor from "./bc-editors/BCSourceEditor";
import type { ComponentDefinition, ExternalInput } from "@/registry/types";

interface BCsTabFormProps {
  component: ComponentDefinition;
  nodeId: string;
}

export default function BCsTabForm({ component, nodeId }: BCsTabFormProps) {
  const bcMode = useStore((s) => s.bcMode);
  const setBCMode = useStore((s) => s.setBCMode);
  const clearBCMode = useStore((s) => s.clearBCMode);
  const bcSymmetric = useStore((s) => s.bcSymmetric);
  const setBCSymmetric = useStore((s) => s.setBCSymmetric);

  // Pair fields by base name. T_wall_left + T_wall_right -> base "T_wall".
  // q_left + q_right -> base "q". Use a runtime grouping so this works for
  // any future paired external_inputs.
  const pairs = pairExternalInputs(component.external_inputs);

  return (
    <div className="flex flex-col gap-[16px] mt-[16px]">
      {pairs.map(({ base, left, right }) => {
        const symKey = `${nodeId}::${base}`;
        // Default ON per D-05 — undefined means symmetric.
        const symmetric = bcSymmetric[nodeId]?.[base] ?? true;

        return (
          <div key={base} className="flex flex-col gap-[8px]">
            <div className="flex items-center justify-between">
              <Label className="text-[13px] font-semibold">{base} BCs</Label>
              <div className="flex items-center gap-[6px]">
                <Label className="text-[12px] text-muted-foreground">Symmetric (L = R)</Label>
                <Switch
                  checked={symmetric}
                  onCheckedChange={(c) => setBCSymmetric(nodeId, base, c)}
                />
              </div>
            </div>

            {symmetric ? (
              <BCFieldBlock nodeId={nodeId} field={left} />
            ) : (
              <>
                <BCFieldBlock nodeId={nodeId} field={left} />
                <Separator />
                <BCFieldBlock nodeId={nodeId} field={right} />
              </>
            )}
          </div>
        );
      })}
    </div>
  );
}

function BCFieldBlock(/* nodeId, field — renders BCModePicker + per-mode editor */) {
  // Picker switches active mode; below it, render BCValueEditor / BCProfileEditor /
  // BCFunctionEditor / nothing (Mark) / BCSourceEditor based on the active mode.
  // When mode is undefined (required-unset): show "BC required — select a mode" hint
  // in muted-destructive text below the picker.
  ...
}
```

### Example 4: Per-mode codegen emit

```typescript
// gui/src/lib/codeGenerator.ts — new helper

function emitBCBindings(
  node: Node,
  component: ComponentDefinition,
  bcMode: Record<string, BCModeEntry>,
  bcSymmetric: Record<string, Record<string, boolean>>,
): { profileImports: string[]; functionStubs: string[]; bindingEquations: string[]; todoComments: string[] } {
  const data = node.data as unknown as StreamNodeData;
  const nodeId = node.id;
  const n = data.parameters["n"];
  const profileImports: string[] = [];
  const functionStubs: string[] = [];
  const bindingEquations: string[] = [];
  const todoComments: string[] = [];

  for (const ext of component.external_inputs ?? []) {
    const key = `${nodeId}::${ext.name}`;
    const entry = bcMode[key];
    const inst = data.instanceName;
    const field = ext.name;

    if (entry === undefined) {
      // Required-unset (D-09) — TODO comment, no equation.
      todoComments.push(`# TODO: set ${inst}.${field}[i] here  (BC required — open the BCs tab)`);
      continue;
    }

    switch (entry.mode) {
      case "value":
        bindingEquations.push(`[${inst}.${field}[i] ~ ${formatReal(entry.value)} for i in 1:${n}]...,`);
        break;
      case "profile":
        if (entry.preset === "cosine") {
          // CD-02 — emit cosine_T_wall_profile (q analog: emit a power-shape-like helper or inline cos² for q-flux).
          bindingEquations.push(
            `[${inst}.${field}[i] ~ cosine_T_wall_profile(${n}; amplitude=${formatReal(entry.amplitude)}, peaking_factor=${formatReal(entry.peakingFactor)})[i] for i in 1:${n}]...,`
          );
        } else { // file
          const varName = `${field}_${inst}`;
          profileImports.push(
            `${varName} = rebin_intensive(readdlm(joinpath(@__DIR__, ${JSON.stringify(entry.path)}), ','), ${n})`
          );
          bindingEquations.push(`[${inst}.${field}[i] ~ ${varName}[i] for i in 1:${n}]...,`);
        }
        break;
      case "function": {
        const fnName = entry.functionName;
        const sig = entry.signature; // "fn(t)" or "fn(t, i)"
        if (sig === "fn(t)") {
          functionStubs.push(`${fnName}(t) = 0.0  # TODO: define your time-varying boundary condition`);
          bindingEquations.push(`[${inst}.${field}[i] ~ ${fnName}(t) for i in 1:${n}]...,`);
        } else {
          functionStubs.push(`${fnName}(t, i) = 0.0  # TODO: define your time-varying boundary condition`);
          bindingEquations.push(`[${inst}.${field}[i] ~ ${fnName}(t, i) for i in 1:${n}]...,`);
        }
        break;
      }
      case "mark":
        todoComments.push(`# TODO: set ${inst}.${field}[i] here`);
        break;
      case "source": {
        const srcNode = /* lookup by sourceNodeId */;
        const srcInst = srcNode.data.instanceName;
        const srcPort = component.id === "Channel" ? "T_wall_out" : "q_out";
        bindingEquations.push(`[${inst}.${field}[i] ~ ${srcInst}.${srcPort}[i] for i in 1:${n}]...,`);
        break;
      }
    }
  }
  return { profileImports, functionStubs, bindingEquations, todoComments };
}
```

## State of the Art

| Old (pre-Phase-63) | New (Phase 63) | When | Impact |
|---------------------|----------------|------|--------|
| BC mechanism = pressure anchors only (Phase 36 `BottomPanel`) | + per-component external-input BCs (Phase 63 BCs tab) | Phase 63 | Two BC mechanisms coexist (D-25) with clean semantic split |
| Profile imports for Power Shape via `rebin_extensive` (sum-conserving) | + `rebin_intensive` for intensive imports (T, q) | Phase 63 | Two helpers, one per conservation law |
| ReactFlow drag tracking via custom mouse handlers (some other codebases) | `useConnection()` v12 hook | ReactFlow v12 GA (2024) | First-class API; the project should standardize on it |
| Edge labels via SVG `<text>` | `EdgeLabelRenderer` portal | ReactFlow v12 | Required for clickable interactive chips |
| `zundo` middleware for undo | Explicit `_pushSnapshot` (Phase 62 decision) | Phase 62 | Phase 63 follows the same discipline; do NOT reintroduce zundo |

**Deprecated/outdated:**
- The `WallPort` and `HeatFluxPort` connector types (Phase 52 / CONN-01-02) were retired in Phase 54 / Phase 55 D-06. External inputs are now **plain `@variables` on Channel and CHF**, not MTK connector ports — which is exactly why Phase 63 needs a UI to close them. [VERIFIED: src/components/channels.jl lines 255-260, 381-382 — external_input variables are declared inline]
- Any reference to `HeatFluxPort` in old Phase 52-era docs is historical.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `cosine_T_wall_profile`'s `peaking_factor` is a scalar multiplier on top of cos² | Pitfall 6, Code Example 4 | LOW — if the user wants peaking as a shape exponent (cos^(2p)), the alias needs a one-line change; tests would catch the difference |
| A2 | The "restore prior mode on edge delete" path of D-23 simplifies to "revert to undefined (required-unset)" | Pitfall 3 | LOW — user surfaces a slightly worse delete-undo experience; can be polished in Phase 65/72 |
| A3 | .scp `bc_modes` block is additive — no `format_version` bump needed | Pitfall 4 | MEDIUM — if Phase 71 validation gates depend on schema version, planner should verify projectIO.ts loads pre-Phase-63 .scp cleanly with empty bc_modes |
| A4 | The "Source"-mode dropdown is keyed by source-component-id literal (`WallTemperature` for T_wall_*; `HeatFluxSource` for q_*) rather than by registry FK | Code Example 4 | LOW — the registry already has `source_component` field on each external_input declaration (verified in components.json lines 84/96/626/640); use that FK directly, don't hardcode the string |
| A5 | The `+ New WallTemperature` button (D-20) reuses Phase 62's `ResourceCreationPopover` discipline (anchored, no click-outside) | "Don't Hand-Roll" section | LOW — visual idiom may need adjustment but the discipline carries over |

**A4 update for the planner:** Use the registry FK. `external_input.source_component === "WallTemperature"` is the canonical lookup. The Source-mode dropdown is `nodes.filter(n => n.data.componentId === ext.source_component)`. This eliminates a hardcoded mapping.

## Open Questions

1. **Symmetric-toggle persistence shape (CD-05).**
   - What we know: Phase 62 stores per-node parameters under `node.data.parameters: Record<string, unknown>`. .scp round-trips this transparently (simple_loop.scp `data.parameters`).
   - What's unclear: Whether symmetric is a per-base-field or per-component-instance concept.
   - **Recommendation: per-(node, base-field), stored as `node.data.bcSymmetric: Record<"T_wall" | "q", boolean>`.** Simpler shape, fits the existing .scp `data` blob shape, no schema bump. Persistent (survives reload). Confirmed CD-05's "per-component-persistent is the natural default."

2. **Should the +New popover anchor on the BCs-tab dropdown trigger, or on the BCs-tab field row?**
   - What we know: Phase 62 anchors popovers on the trigger button.
   - **Recommendation: anchor on the dropdown trigger button**, matching Phase 62 idiom exactly. Click → popover opens beside the dropdown → user types name + `n` → submits → block appears on canvas (positioned ~120px left of consumer, same y) → dropdown auto-selects new block → popover closes → edge gets created.

3. **Function-mode default function body shape.**
   - What we know: D-08 says emit `# TODO: define your time-varying boundary condition`.
   - What's unclear: What's the actual placeholder body? `T_wall_left_fn(t) = 320.0` (concrete) vs `T_wall_left_fn(t) = ...` (literal Julia "ellipsis" which won't parse).
   - **Recommendation: emit a numerical placeholder so the script *runs* without edit but produces obviously-wrong physics.** E.g., `T_wall_left_fn(t) = 320.0  # TODO: define your time-varying boundary condition`. The TODO marker carries the user instruction; the literal `320.0` keeps the script compilable so `mtkcompile` doesn't blow up before the user notices the TODO.

4. **BCs-tab body for required-unset vs Mark mode — visually distinguishable?**
   - What we know: D-09 says required-unset shows `BC required — select a mode` in muted-destructive. Mark mode has no editor.
   - What's unclear: How does the user tell them apart?
   - **Recommendation: required-unset = no pill active + red hint text. Mark = "Mark" pill active + small grey "No editor — code-gen emits a TODO comment" body text.** The active-pill state distinguishes them visually at a glance.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `julia` daemon | `rebin_intensive` tests | ✓ | 1.12.6 | `julia --project=. test/runtests.jl` (cold start, slower) |
| `bin/jl` script | Daemon submission | ✓ | n/a | `julia --project=.` cold |
| `node` / `npm` | GUI build/test | (presumed) | — | — |
| `cargo` / Tauri | `npm run tauri dev` smoke test | (presumed) | — | — |
| `@xyflow/react` v12.10 with `useConnection` + `EdgeLabelRenderer` | Drop target, edge chip | ✓ | ^12.10.2 [VERIFIED: gui/package.json:18] | None — APIs are GA in v12 |

**Missing dependencies with no fallback:** None identified.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework (Julia) | `Test` stdlib + `bin/jl` daemon |
| Framework (TS/React) | `vitest` ^4.1.2 [VERIFIED: gui/package.json:48] |
| Config file (Julia) | `test/runtests.jl` (orchestrator includes one-line per `test_*.jl`) |
| Config file (TS) | `gui/vitest.config.ts` (presumed; standard vite layout) |
| Quick run (Julia helper) | `bin/jl test/test_utilities.jl` |
| Quick run (codegen) | `cd gui && npx vitest run src/lib/codeGenerator.test.ts` |
| Full suite (Julia) | `bin/jl test/runtests.jl` |
| Full suite (TS) | `cd gui && npm test` |
| GUI smoke | `cd gui && npm run tauri dev` |

### Phase Requirements → Test Map

> Phase 63 does not have v1.1-style numbered REQ-IDs in REQUIREMENTS.md (the v1.1 list closed at TEST-04/05; v1.2 GUI redesign is a phase-list, not a REQ-list). Map by decision id (D-NN) instead.

| Decision | Behavior | Test type | Automated command | File exists? |
|----------|----------|-----------|-------------------|-------------|
| D-13 | `rebin_intensive(ones(N), M) == ones(M)` | unit (Julia) | `bin/jl test/test_utilities.jl` | ❌ Wave 0 — append testsets |
| D-15 | `rebin_intensive(x, n) ≈ rebin_extensive(x, n) * (n_out/n_in)` | unit (Julia) | `bin/jl test/test_utilities.jl` | ❌ Wave 0 |
| D-13 (2D) | `rebin_intensive(M, (a,b))` area-weighted-mean preserved | unit (Julia) | `bin/jl test/test_utilities.jl` | ❌ Wave 0 |
| D-14 | `rebin_intensive` exported from STREAM | smoke (Julia) | `bin/jl -e 'using STREAM; @assert isdefined(STREAM, :rebin_intensive)'` | ❌ Wave 0 |
| D-04 | 5-pill picker renders + activates | unit (vitest + @testing-library/react) | `npx vitest run sidebar/BCModePicker.test.tsx` | ❌ Wave 0 |
| D-09 | Required-unset state — no active pill, hint visible | unit (vitest) | `npx vitest run sidebar/BCModePicker.test.tsx` | ❌ Wave 0 |
| D-21 | Type-mismatch BCPort connection hard-blocked | unit (vitest, isValidConnection) | `npx vitest run components/CanvasPanel.test.tsx` | ❌ Wave 0 |
| D-22 | n-mismatch creates edge + flags both endpoints in errorNodeIds | unit (vitest, store) | `npx vitest run store/useStore.bc.test.ts` | ❌ Wave 0 |
| D-23 | Setting source mode in BCs tab creates a canvas edge AND vice versa | unit (vitest, store integration) | `npx vitest run store/useStore.bc.test.ts` | ❌ Wave 0 |
| D-11 | Click chip on BC edge cycles L+R → L → R → L+R | unit (vitest, BCEdge isolated) | `npx vitest run components/BCEdge.test.tsx` | ❌ Wave 0 |
| D-12 | BC edge style matches dashed muted-foreground | unit (vitest snapshot) | `npx vitest run components/BCEdge.test.tsx` | ❌ Wave 0 |
| D-06 | Codegen for Value mode emits `[ch.T_wall_left[i] ~ <val> for i in 1:n]...` | unit (vitest) | `npx vitest run lib/codeGenerator.bc.test.ts` | ❌ Wave 0 |
| D-07 | Codegen for Profile-file mode emits `rebin_intensive(readdlm(...))` | unit (vitest, snapshot) | `npx vitest run lib/codeGenerator.bc.test.ts` | ❌ Wave 0 |
| D-08 | Codegen for Function mode emits stub + binding | unit (vitest) | `npx vitest run lib/codeGenerator.bc.test.ts` | ❌ Wave 0 |
| D-09 + CD-01 | Codegen for unset emits `# TODO: set …` comment, no equation | unit (vitest) | `npx vitest run lib/codeGenerator.bc.test.ts` | ❌ Wave 0 |
| D-10 | Whole-body drop target activates only on BCPort drag | manual smoke (npm run tauri dev) | drag from WT.T_wall_out onto Channel | ❌ Manual only |
| D-20 | `+ New WallTemperature` inline button spawns and auto-selects | manual smoke (npm run tauri dev) | empty canvas → Channel → BCs tab → T_wall → Source → `+ New` | ❌ Manual only |

### Sampling Rate
- **Per task commit:** `bin/jl test/test_utilities.jl` (Julia tasks) OR `cd gui && npx vitest run <touched files>` (GUI tasks). < 30 seconds either way once daemon is warm.
- **Per wave merge:** `bin/jl test/runtests.jl` + `cd gui && npm test`.
- **Phase gate:** Full suites green; `npm run tauri dev` smoke pass for D-10/D-20 manual checks before `/gsd-verify-work`.

### Wave 0 Gaps
- [ ] `test/test_utilities.jl` — append INT-01..05 testsets (file exists; append-only).
- [ ] `gui/src/components/sidebar/BCModePicker.test.tsx` — new vitest file.
- [ ] `gui/src/components/sidebar/BCsTabForm.test.tsx` — new vitest file.
- [ ] `gui/src/components/BCEdge.test.tsx` — new vitest file.
- [ ] `gui/src/components/CanvasPanel.test.tsx` — new vitest file (or extend if one exists).
- [ ] `gui/src/store/useStore.bc.test.ts` — new vitest file (BC mode actions + edge sync).
- [ ] `gui/src/lib/codeGenerator.bc.test.ts` — new vitest file (5-mode emit snapshots).
- [ ] `gui/src/lib/bcMode.ts` — new shared types + `bcModeKey()` helper.

*(D-10 whole-body drop activation and D-20 `+ New` flow are manual-only — they involve drag-and-drop and Tauri dialog interactions that vitest/jsdom can't faithfully simulate. Document in the plan that these get a `npm run tauri dev` checklist step at phase close.)*

## Project Constraints (from CLAUDE.md)

| Constraint | How Phase 63 honors it |
|------------|------------------------|
| Working branch `gui-redesign`, GSD must NEVER create branches | Planner must NOT set `git.branching_strategy`; all work commits on `gui-redesign` |
| `.planning/config.json` `git.branching_strategy = "none"` | Verify before plan runs |
| `src/components/` for new components / `src/utilities.jl` for helpers | `rebin_intensive` lands in `src/utilities.jl` (correct per file structure standard) |
| Test placement mirrors src | `rebin_intensive` tests in `test/test_utilities.jl` (correct) |
| Exports in `STREAM.jl` only, never inside component files | Append `rebin_intensive` to line 100 export list |
| Positional vs keyword arg rule | `rebin_intensive(vec, n_target)` positional (1 phys param, dispatch on AbstractVector vs AbstractMatrix) — matches `rebin_extensive` |
| ASCII-only Julia identifiers | All new Julia names ASCII (`peaking_factor` not `β`, etc.) |
| Daemon dev loop primary | Smoke instructions in plan say `bin/jl test/test_utilities.jl`, never `julia ...` |
| Struct/type-definition edits don't hot-reload | `rebin_intensive` is a new function (no type changes) — daemon picks it up via Revise without restart |
| Don't add inline `export` statements | Adhered (one append to STREAM.jl line 100) |

## Sources

### Primary (HIGH confidence)
- `.planning/phases/63-bcs-tab-value-source-components-in-gui/63-CONTEXT.md` — 25 locked decisions + 5 discretion items [READ in this session]
- `.planning/notes/gui-redesign-design-decisions.md` §3.10, §3.11 — design contract [READ lines 841-994]
- `gui/src/store/useStore.ts` — Phase 62 store, explicit _pushSnapshot, no zundo [READ entire file]
- `gui/src/components/sidebar/ModeToggle.tsx` — segmented control idiom [READ entire file]
- `gui/src/components/HydraulicEdge.tsx` — custom edge pattern [READ entire file]
- `gui/src/components/StreamNode.tsx` — handle rendering pattern [READ entire file]
- `gui/src/components/CanvasPanel.tsx` — useReactFlow + isValidConnection + onConnect [READ entire file]
- `gui/src/components/ToolboxPanel.tsx` — Phase 62 Sources placeholder [READ entire file]
- `gui/src/components/sidebar/SidebarPanel.tsx` — selection-kind router [READ entire file]
- `gui/src/components/sidebar/ParameterForm.tsx` — Properties tab body [READ entire file]
- `gui/src/lib/codeGenerator.ts` — flat-string emit, TODO Phase 66 mark [READ entire file]
- `gui/src/registry/components.json` — external_inputs + WT/HFS entries [READ relevant ranges 79-98, 568-642, 1015-1082]
- `src/utilities.jl` — rebin_extensive + cosine_power_shape [READ entire file]
- `src/components/sources.jl` — WallTemperature + HeatFluxSource Julia signatures [READ entire file]
- `src/components/channels.jl` — external_input variable declarations [READ via grep, lines 13/35/255-300/375-430]
- `src/STREAM.jl` — exports list [READ entire file]
- `test/test_utilities.jl` — Phase 62 test idioms [READ entire file]
- `gui/export_examples/simple_loop.scp` — post-Phase-62 .scp shape [READ entire file]
- `gui/package.json` — verified versions [READ entire file]
- `CLAUDE.md` — file structure / branching / daemon [from prompt context]

### Secondary (MEDIUM confidence — single doc lookup)
- [ReactFlow useConnection docs](https://reactflow.dev/api-reference/hooks/use-connection) — exists in v12; returns ConnectionState
- [ReactFlow ConnectionState type](https://reactflow.dev/api-reference/types/connection-state) — fields: `inProgress`, `isValid`, `fromHandle`, `fromNode`, `fromPosition`, `from`, `to`, `toHandle`, `toNode`, `toPosition`, `pointer`
- [ReactFlow EdgeLabelRenderer docs](https://reactflow.dev/api-reference/components/edge-label-renderer) — portal; requires `pointerEvents: 'all'` + `nopan` class; usable with getSmoothStepPath
- [ReactFlow TypeScript guide](https://reactflow.dev/learn/advanced-use/typescript) — Edge/Node generics, `useNodeConnections` available in v12

### Tertiary (LOW confidence — none in this research)
None — all critical claims verified against either local code or official ReactFlow docs.

## Metadata

**Confidence breakdown:**
- Julia `rebin_intensive` math: HIGH — derivation in this session, identity verified algebraically, mirror-pattern of existing helper
- ReactFlow v12 hooks (`useConnection`, `EdgeLabelRenderer`): HIGH — official docs fetched, version verified against package.json
- Store / codegen extensions: HIGH — direct read of existing files, additive-only changes
- Codegen Julia emit shapes: HIGH — pattern matches Phase 62 (`rebin_extensive(readdlm(...))`) exactly
- BCs tab UI shape: MEDIUM-HIGH — shadcn Tabs and SegmentedButtonGroup are well-trodden; required-unset state shown to work without hacks
- D-22 n-mismatch wiring: MEDIUM — uses existing `errorNodeIds` infrastructure; planner should verify Phase 39 validation entry path
- CD-02 cosine helper shape: MEDIUM — recommendation given; planner should confirm `peaking_factor` semantics in discuss-phase or first task

**Research date:** 2026-05-13
**Valid until:** 2026-06-13 (30 days — ReactFlow v12 is stable; shadcn/Tailwind unlikely to drift)

## RESEARCH COMPLETE
