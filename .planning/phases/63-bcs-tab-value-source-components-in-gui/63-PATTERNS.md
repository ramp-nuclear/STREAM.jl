# Phase 63: BCs tab + value-source components in GUI — Pattern Map

**Mapped:** 2026-05-13
**Files analyzed:** 14 (5 new GUI, 6 modified GUI, 3 modified Julia)
**Analogs found:** 14 / 14

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `gui/src/lib/bcMode.ts` (NEW) | utility / types | transform | `gui/src/lib/utils.ts` + inline types in `gui/src/store/useStore.ts` lines 64-97 | role-match |
| `gui/src/components/sidebar/BCsTabForm.tsx` (NEW) | component (sidebar form) | request-response | `gui/src/components/sidebar/ParameterForm.tsx` | exact |
| `gui/src/components/sidebar/BCModePicker.tsx` (NEW) | component (segmented control) | event-driven | `gui/src/components/sidebar/ModeToggle.tsx` | exact |
| `gui/src/components/sidebar/SegmentedButtonGroup.tsx` (NEW) | component (primitive) | event-driven | `gui/src/components/sidebar/ModeToggle.tsx` (lines 25-48) | exact |
| `gui/src/components/BCEdge.tsx` (NEW) | component (ReactFlow custom edge) | event-driven | `gui/src/components/HydraulicEdge.tsx` | exact |
| `gui/src/components/sidebar/__tests__/BCModePicker.test.tsx` (NEW) | test | request-response | `gui/src/components/sidebar/__tests__/ModeToggle.test.tsx` | exact |
| `gui/src/components/__tests__/BCEdge.test.tsx` (NEW) | test | request-response | `gui/src/components/__tests__/StreamNode.test.tsx` | role-match |
| `gui/src/store/__tests__/bcMode.slice.test.ts` (NEW) | test | request-response | `gui/src/store/__tests__/useStore.test.ts` + `resources.slice.test.ts` | exact |
| `gui/src/components/sidebar/SidebarPanel.tsx` (MOD) | component (router) | request-response | self (lines 134-189) — extend component branch | self-extension |
| `gui/src/components/StreamNode.tsx` (MOD) | component (ReactFlow custom node) | event-driven | self — extend handles loop + add drop overlay | self-extension |
| `gui/src/components/CanvasPanel.tsx` (MOD) | component (ReactFlow host) | event-driven | self (lines 38-40 edgeTypes; 141-155 isValidConnection) | self-extension |
| `gui/src/components/ToolboxPanel.tsx` (MOD) | component (toolbox) | request-response | self (lines 25-40 Hydraulic block — Sources mirrors it) | self-extension |
| `gui/src/store/useStore.ts` (MOD) | store (zustand slice) | event-driven | self — `resources` slice + `addEdge`/`onEdgesChange` patterns | self-extension |
| `gui/src/lib/codeGenerator.ts` (MOD) | utility (code emit) | transform | self — `power_shape_ref` emission (lines 800-877) | self-extension |
| `src/utilities.jl` (MOD) | utility (Julia helper) | transform | self — `rebin_extensive` + `_rebin_1d` (lines 33-109) | exact |
| `test/test_utilities.jl` (MOD) | test (Julia) | request-response | self — CONS-01..04 testsets (lines 16-101) | exact |
| `src/STREAM.jl` (MOD) | config (module) | — | self (line 100 `export rebin_extensive, cosine_power_shape`) | self-extension |

## Pattern Assignments

---

### `gui/src/lib/bcMode.ts` (NEW — utility / types)

**Analog:** `gui/src/lib/utils.ts` (file form factor — tiny pure helper module) + inline interface declarations from `gui/src/store/useStore.ts` lines 64-97.

**File-header pattern** (mirror the docblock style used elsewhere in `lib/`, e.g., the top of `codeGenerator.ts:1-15`):

```typescript
// bcMode.ts — Phase 63: shared BCs-tab + canvas BC edge types.
//
// Zero React dependencies (consumed by codeGenerator.ts pure pipeline).
// `bcModeKey(componentId, externalInputName)` is the single composite key
// for `Record<string, BCModeEntry>` in the store. Absence of a key =
// required-unset (D-09 sentinel pattern, mirroring SENTINEL_UNSET_POWER_SHAPE).
```

**Discriminated-union pattern** (mirror useStore.ts:76-91 `PowerShapeResource.kind` switch):

```typescript
export type BCModeEntry =
  | { mode: "value"; value: number }
  | { mode: "profile"; preset: "cosine"; amplitude: number; peakingFactor: number }
  | { mode: "profile"; preset: "file"; path: string }
  | { mode: "function"; signature: "fn(t)" | "fn(t, i)"; functionName: string }
  | { mode: "mark" }
  | { mode: "source"; sourceNodeId: string };

export function bcModeKey(componentId: string, externalInputName: string): string {
  return `${componentId}::${externalInputName}`;
}

export interface BCEdgeData {
  componentId: string;
  externalInputName: string;
  targetSide: "left" | "right" | "both";
}
```

**Naming-convention precedent** (from useStore.ts:36 — sentinel UUIDs are exported uppercase constants; same shape for any BC sentinels Phase 63 needs).

---

### `gui/src/components/sidebar/BCsTabForm.tsx` (NEW — component / form body)

**Analog:** `gui/src/components/sidebar/ParameterForm.tsx`

**Imports pattern** (ParameterForm.tsx:1-10):

```typescript
import { Info } from "lucide-react";
import { Separator } from "@/components/ui/separator";
import NumericField from "./NumericField";
// ... etc
import { Label } from "@/components/ui/label";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import type { ComponentDefinition, Parameter } from "@/registry/types";
```

For BCsTabForm: add `import { Switch } from "@/components/ui/switch";` and `import useStore from "@/store/useStore";` and `import { bcModeKey, type BCModeEntry } from "@/lib/bcMode";`. The shape — props with `component: ComponentDefinition` + a store-driven value setter — mirrors ParameterForm.

**Props shape** (ParameterForm.tsx:12-17 — the contract the planner replicates):

```typescript
interface ParameterFormProps {
  component: ComponentDefinition;
  activeMode: string;
  values: Record<string, unknown>;
  onParamChange: (name: string, value: unknown) => void;
}
```

For BCsTabForm the shape collapses to `{ component, nodeId }` because the BC store is keyed by `(nodeId, externalInputName)` and read via `useStore` selectors, not passed down as `values`.

**Section + grouping pattern** (ParameterForm.tsx:36-43 — partition params by type; mirror by partitioning external_inputs by pair_with):

```typescript
const scalarParams = visibleParams.filter(
  (p) => p.type === "Int" || p.type === "Real" || p.type === "Bool"
);
const geometryParams = visibleParams.filter(
  (p) => p.type === "PipeGeometry"
);
const functionParams = visibleParams.filter((p) => p.type === "Function");
```

For BCsTabForm: partition `component.external_inputs[]` by `pair_with` to build `{base: "T_wall", left: ..., right: ...}` groups. Each group renders the symmetric-toggle + one or two BCModePicker rows.

**Section heading pattern** (ParameterForm.tsx:139-178 — `sections` array of `{heading, params}` rendered with separators):

```typescript
return (
  <div className="flex flex-col gap-[12px] min-w-0">
    {sections.map((section, idx) => (
      <div key={section.heading} className="min-w-0">
        {idx > 0 && <Separator className="mb-[12px]" />}
        <h3 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground leading-[1.3] mb-[8px]">
          {section.heading}
        </h3>
        <div className="flex flex-col gap-[8px]">
          {section.params.map((param) => renderField(param))}
        </div>
      </div>
    ))}
  </div>
);
```

Apply verbatim — use heading `T_wall_left[1:n]` / `T_wall_right[1:n]` or just `T_wall` (symmetric ON), `q` etc.

---

### `gui/src/components/sidebar/BCModePicker.tsx` (NEW — 5-pill segmented control)

**Analog:** `gui/src/components/sidebar/ModeToggle.tsx`

**Full pattern to copy** (ModeToggle.tsx:1-49 — the entire file is the template; required-unset works trivially because `active === undefined` means no button matches):

```typescript
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import type { ConstructorMode } from "@/registry/types";

interface ModeToggleProps {
  modes: ConstructorMode[];
  activeMode: string;
  onChange: (mode: string) => void;
}

const MODE_LABELS: Record<string, string> = {
  "fixed-dP": "Fixed dP",
  "fixed-mdot": "Fixed mdot",
};

export default function ModeToggle({
  modes,
  activeMode,
  onChange,
}: ModeToggleProps) {
  return (
    <div className="flex flex-col gap-[8px]">
      <Label className="text-[13px] font-semibold leading-[1.4]">Mode</Label>
      <div className="flex">
        {modes.map((m, idx) => (
          <Button
            key={m.mode}
            variant={m.mode === activeMode ? "default" : "outline"}
            size="sm"
            className={
              idx === 0
                ? "rounded-r-none"
                : idx === modes.length - 1
                  ? "rounded-l-none"
                  : "rounded-none"
            }
            onClick={() => onChange(m.mode)}
          >
            {modeLabel(m.mode)}
          </Button>
        ))}
      </div>
    </div>
  );
}
```

**Adaptations for BCModePicker:**
- Props: `{ active: BCMode | undefined, onChange: (mode: BCMode) => void, label: string }` where `BCMode = "value" | "profile" | "function" | "mark" | "source"`.
- `MODE_LABELS = { value: "Value", profile: "Profile", function: "Function", mark: "Mark", source: "Source" }`.
- The `variant={m.mode === activeMode ? "default" : "outline"}` line, when `active === undefined`, makes ALL buttons `outline` — that's the D-09 required-unset visual for free.
- After the segmented-control row, emit the muted-destructive hint `BC required — select a mode` when `active === undefined`.

---

### `gui/src/components/sidebar/SegmentedButtonGroup.tsx` (NEW — extracted primitive)

**Analog:** `gui/src/components/sidebar/ModeToggle.tsx` internals (lines 25-48 — the JSX inside the wrapper).

The extracted primitive is parameterized over `T extends string`:

```typescript
// gui/src/components/sidebar/SegmentedButtonGroup.tsx (NEW)
import { Button } from "@/components/ui/button";

interface SegmentedButtonGroupProps<T extends string> {
  options: Array<{ value: T; label: string }>;
  /** undefined = no active pill (required-unset, D-09). */
  active: T | undefined;
  onChange: (value: T) => void;
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

**Refactor follow-up:** `ModeToggle.tsx` becomes a thin wrapper — maps `ConstructorMode[]` to `options` array and forwards to `<SegmentedButtonGroup>`. `BCModePicker.tsx` likewise. Same primitive, two consumers.

---

### `gui/src/components/BCEdge.tsx` (NEW — ReactFlow custom edge)

**Analog:** `gui/src/components/HydraulicEdge.tsx`

**Full pattern to copy** (HydraulicEdge.tsx:1-32 — sibling file, same exports shape):

```typescript
import { memo } from "react";
import { getSmoothStepPath, BaseEdge, type EdgeProps } from "@xyflow/react";

function HydraulicEdge({
  id,
  sourceX,
  sourceY,
  targetX,
  targetY,
  sourcePosition,
  targetPosition,
  style,
  markerEnd,
}: EdgeProps) {
  const [path] = getSmoothStepPath({
    sourceX,
    sourceY,
    targetX,
    targetY,
    sourcePosition,
    targetPosition,
  });

  return <BaseEdge id={id} path={path} style={style} markerEnd={markerEnd} />;
}

export default memo(HydraulicEdge);
```

**Extensions Phase 63 layers on top:**
1. Destructure `[path, labelX, labelY]` from `getSmoothStepPath` (the 2nd/3rd tuple elements are the mid-edge anchor for the chip).
2. Add `EdgeLabelRenderer` import and emit the chip with `className="nopan"`, `pointerEvents: "all"`, and an `onClick` that calls `useStore.getState().cycleBCEdgeTargetSide(id, ...)`.
3. Hard-code style `stroke: "var(--muted-foreground)"`, `strokeWidth: 1.5`, `strokeDasharray: "6 3"` (D-12) instead of consuming `style` prop — BC edges have a fixed visual idiom.
4. Read `data.targetSide` from `EdgeProps` (declared in `bcMode.ts:BCEdgeData`).

**Edge type registration** (CanvasPanel.tsx:38-40 — pattern to copy when adding to `edgeTypes`):

```typescript
const edgeTypes: EdgeTypes = {
  hydraulicEdge: HydraulicEdge,
};
```

Phase 63 adds `bcEdge: BCEdge` to the same map.

---

### `gui/src/components/sidebar/__tests__/BCModePicker.test.tsx` (NEW — vitest)

**Analog:** `gui/src/components/sidebar/__tests__/ModeToggle.test.tsx`

**Full template to copy** (ModeToggle.test.tsx:1-30 — happy-dom + render + screen):

```typescript
// @vitest-environment happy-dom
import { describe, it, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import ModeToggle from "../ModeToggle";

describe("ModeToggle", () => {
  const modes = [
    { mode: "fixed-dP", signature: "Pump(dP; name)", parameters: ["dP_pump"] },
    { mode: "fixed-mdot", signature: "Pump(mdot0; name)", parameters: ["mdot0"] },
  ];

  it("renders buttons for each mode", () => {
    render(<ModeToggle modes={modes} activeMode="fixed-dP" onChange={vi.fn()} />);
    expect(screen.getByText("Fixed dP")).toBeTruthy();
    expect(screen.getByText("Fixed mdot")).toBeTruthy();
  });

  it.todo("calls onChange when inactive mode button is clicked");
  it.todo("highlights active mode button");
});
```

**Additional BCModePicker-specific tests** (must add — required-unset is the new behavior):

```typescript
it("renders no active pill when active === undefined (D-09 required-unset)", () => {
  render(<BCModePicker active={undefined} onChange={vi.fn()} />);
  // All 5 buttons should be `variant="outline"` (no `default`).
  // Assert: none of the buttons carry the active highlight class.
});
it("renders the required-unset hint when active === undefined", () => {
  render(<BCModePicker active={undefined} onChange={vi.fn()} />);
  expect(screen.getByText(/BC required/i)).toBeTruthy();
});
```

---

### `gui/src/store/__tests__/bcMode.slice.test.ts` (NEW — vitest, store action coverage)

**Analog:** `gui/src/store/__tests__/useStore.test.ts` (test bootstrapping + `beforeEach` reset) + `gui/src/store/__tests__/resources.slice.test.ts` (slice-shaped coverage).

**Bootstrap pattern** (useStore.test.ts:1-12):

```typescript
import { describe, it, expect, beforeEach } from "vitest";
import { MarkerType } from "@xyflow/react";
import useStore from "../useStore";
import { enrichEdges } from "../useStore";
import type { StreamNodeData } from "../useStore";

beforeEach(() => {
  useStore.setState({
    nodes: [], edges: [], selectedNodeId: null, bcs: [],
    isDirty: false, _undoPast: [], _undoFuture: []
  });
});
```

For Phase 63 reset, add `bcMode: {}`, `bcSymmetric: {}` to the reset object.

**Coverage to mirror from `useStore.test.ts:13-90`:**
- `setBCMode` adds entry, sets `isDirty: true`, pushes snapshot.
- `clearBCMode` removes entry; key absence = required-unset (D-09).
- `setBCMode` with `mode: "source"` creates the corresponding BC edge in `edges[]`.
- Deleting a BC edge via `onEdgesChange` (with a `remove` change) reverts the matching `bcMode` entry to `undefined`.

---

### `gui/src/components/sidebar/SidebarPanel.tsx` (MODIFIED — component router)

**Self-analog:** SidebarPanel.tsx:134-189 — the existing `selectionKind === "component"` branch (lines 136-189) is the surgery target.

**Existing component-branch shape** (lines 150-188 — the structure Phase 63 wraps with Tabs):

```typescript
return (
  <div key={selectedNodeId}>
    <div className="mt-[24px] flex flex-col gap-[8px]">
      <InstanceNameField ... />
      <Badge variant="secondary">{component.label}</Badge>
    </div>
    <Separator className="my-[24px]" />
    {component.constructorModes.length > 1 && (
      <>
        <ModeToggle ... />
        <Separator className="my-[24px]" />
      </>
    )}
    <ParameterForm component={component} activeMode={activeMode} ... />
  </div>
);
```

**Phase 63 surgery** — wrap the `<ModeToggle/>` + `<ParameterForm/>` pair with `<Tabs>` conditional on `component.external_inputs?.length > 0` per RESEARCH §"Pattern 5". The outer `<div key={selectedNodeId}>` remount discipline (line 151) is reused: switching nodes remounts the subtree and resets the `useState("properties")` inside Tabs automatically (D-03 reset-on-selection-change behavior — RESEARCH Pitfall 2).

**Import pattern to add** (mirror existing imports at lines 38-51):

```typescript
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import BCsTabForm from "./BCsTabForm";
```

---

### `gui/src/components/StreamNode.tsx` (MODIFIED — BCPort handle + drop overlay)

**Self-analog:** StreamNode.tsx:65-99 — existing handle-rendering loop is the surgery target.

**Existing flow-port handle pattern** (StreamNode.tsx:65-81 — copy the shape for BCPort hollow-square):

```typescript
{flowPorts.map((port) => {
  const isInPort = port.name.includes("in");
  return (
    <Handle
      key={port.name}
      id={port.name}
      type={isInPort ? "target" : "source"}
      position={sideToPosition[port.side!]}
      data={{ portType: port.type }}
      style={{
        background: isInPort ? FLOW_IN_BG : FLOW_OUT_BG,
        border: `1.5px solid ${isInPort ? FLOW_IN_BORDER : FLOW_OUT_BORDER}`,
        ...(dimFlowHandles ? { opacity: 0.2, pointerEvents: "none" as const } : {}),
      }}
    />
  );
})}
```

**Phase 63 BCPort handle (add a sibling map)** — same `<Handle>` JSX with `type="source"`, hollow style:

```typescript
const bcPorts = component.ports.filter((p) => p.type === "BCPort");
// ...
{bcPorts.map((port) => (
  <Handle
    key={port.name}
    id={port.name}
    type="source"
    position={sideToPosition[port.side ?? "right"]}
    data={{ portType: port.type }}
    style={{
      background: "transparent",
      border: `1.5px solid var(--muted-foreground)`,
      width: 10,
      height: 10,
      borderRadius: 0,    // square, not circle (FlowPort) nor diamond (ThermalPort rotated)
    }}
  />
))}
```

**Drop-overlay pattern** (no prior analog in the repo — use `useConnection()` per RESEARCH Pattern 2). Pseudocode skeleton to layer onto StreamNode:

```typescript
import { useConnection } from "@xyflow/react";
import { getPortType } from "./CanvasPanel";  // already exported, line 25-32

const connection = useConnection();
const isConsumerNode = component.external_inputs?.length > 0;
const dropActive =
  connection?.inProgress &&
  connection.fromNode != null &&
  connection.fromHandle?.id != null &&
  getPortType(connection.fromNode.id, connection.fromHandle.id) === "BCPort" &&
  isConsumerNode;

// Render dashed-outline overlay + "Connect BC" chip when dropActive.
```

**ThermalPort handle precedent** (StreamNode.tsx:82-99 — same `data={{portType: port.type}}` propagation that CanvasPanel.tsx:25-32 `getPortType` reads back). BCPort follows the same convention.

---

### `gui/src/components/CanvasPanel.tsx` (MODIFIED — edgeTypes + isValidConnection)

**Self-analog:** CanvasPanel.tsx:38-40 (edgeTypes map) + lines 141-155 (isValidConnection callback).

**edgeTypes registration pattern** (lines 38-40):

```typescript
const edgeTypes: EdgeTypes = {
  hydraulicEdge: HydraulicEdge,
};
```

Phase 63 adds:

```typescript
import BCEdge from "./BCEdge";
const edgeTypes: EdgeTypes = {
  hydraulicEdge: HydraulicEdge,
  bcEdge: BCEdge,
};
```

**isValidConnection pattern** (lines 141-155 — the function to extend with BCPort rules per D-21):

```typescript
const isValidConnection = useCallback((connection: Edge | Connection) => {
  if (
    !connection.source ||
    !connection.target ||
    !connection.sourceHandle ||
    !connection.targetHandle
  ) {
    return false;
  }
  // Port-type enforcement (per D-05): FlowPort-to-FlowPort only, ThermalPort-to-ThermalPort only
  const sourceType = getPortType(connection.source, connection.sourceHandle);
  const targetType = getPortType(connection.target, connection.targetHandle);
  if (sourceType && targetType && sourceType !== targetType) return false;
  return true;
}, []);
```

**Phase 63 extension** — BCPort branch per RESEARCH Pattern 7. Keep `isValidConnection` PURE (no state mutation — RESEARCH Pitfall 7); push n-mismatch red-ring detection into the store's `addEdge` / `_onBCEdgeAdded`:

```typescript
if (sourceType === "BCPort") {
  const srcNode = useStore.getState().nodes.find(n => n.id === connection.source);
  const tgtNode = useStore.getState().nodes.find(n => n.id === connection.target);
  if (!srcNode || !tgtNode) return false;
  const srcCompId = (srcNode.data as StreamNodeData).componentId;
  const tgtCompId = (tgtNode.data as StreamNodeData).componentId;
  if (srcCompId === "WallTemperature"  && tgtCompId === "Channel")         return true;
  if (srcCompId === "HeatFluxSource"   && tgtCompId === "ChannelHeatFlux") return true;
  return false; // Hard-block everything else (D-21).
}
```

---

### `gui/src/components/ToolboxPanel.tsx` (MODIFIED — Sources draggables)

**Self-analog:** ToolboxPanel.tsx:25-40 (Hydraulic category block) — Phase 63 mirrors this for Sources.

**Hydraulic block pattern to copy** (lines 25-40):

```typescript
{visibleHydraulic.length > 0 && (
  <>
    <div className="text-xs font-semibold uppercase tracking-wide text-muted-foreground px-2 mb-1 mt-2">
      Hydraulic
    </div>
    <div className="space-y-px">
      {visibleHydraulic.map((comp) => (
        <ToolboxItem
          key={comp.id}
          componentId={comp.id}
          label={comp.label}
        />
      ))}
    </div>
  </>
)}
```

**Phase 63 Sources entries** — the existing header at lines 62-65 stays; ADD a `<div className="space-y-px">` map under it pulling `getComponentsByCategory("Sources")` (or whatever the registry tag is — Phase 61 work). Mirror the same `visible*.length > 0` + `ToolboxItem` map shape.

---

### `gui/src/store/useStore.ts` (MODIFIED — bcMode slice)

**Self-analog:** useStore.ts:546-571 (Resources slice initial state + actions) — Phase 63 mirrors the slice shape.

**Snapshot discipline pattern** (useStore.ts:613-622 — every mutation pushes a snapshot BEFORE `set(...)`):

```typescript
_pushSnapshot: () => {
  const { nodes, edges, bcs, resources, modelOptions, _undoPast } = get();
  set({
    _undoPast: [
      ..._undoPast,
      { nodes, edges, bcs, resources, modelOptions },
    ].slice(-50),
    _undoFuture: [],
  });
},
```

**Phase 63 extension** — add `bcMode` + `bcSymmetric` to the captured snapshot object (and to `undo`/`redo` set-payloads at lines 624-666). RESEARCH §"Pattern 6" final paragraph confirms.

**Action shape pattern** (useStore.ts:875-889 `addGeometry` — shows: validate, snapshot, mutate, isDirty=true):

```typescript
addGeometry: (g) => {
  const { resources } = get();
  validateResourceName("geometry", g.name, resources.geometries);
  get()._pushSnapshot();
  const uuid = crypto.randomUUID();
  const newRecord: GeometryResource = { uuid, ...g };
  set({
    resources: {
      ...resources,
      geometries: { ...resources.geometries, [uuid]: newRecord },
    },
    isDirty: true,
  });
  return uuid;
},
```

**Apply to BCs:**

```typescript
setBCMode: (componentId, externalInputName, entry) => {
  get()._pushSnapshot();
  const key = bcModeKey(componentId, externalInputName);
  set({
    bcMode: { ...get().bcMode, [key]: entry },
    isDirty: true,
  });
},

clearBCMode: (componentId, externalInputName) => {
  get()._pushSnapshot();
  const key = bcModeKey(componentId, externalInputName);
  const { [key]: _, ...rest } = get().bcMode;
  set({ bcMode: rest, isDirty: true });
},
```

**Edge-deletion-reverts-bcMode pattern** — extend `onEdgesChange` (useStore.ts:704-714) to diff removed edges and call `_onBCEdgeRemoved` per RESEARCH Pitfall 3:

```typescript
onEdgesChange: (changes) => {
  const isContentless = changes.every((c) => c.type === "select");
  if (isContentless) return;
  if (changes.some((c) => c.type === "remove")) {
    get()._pushSnapshot();
  }
  set({ edges: applyEdgeChanges(changes, get().edges), isDirty: true });
},
```

**Edge enrichment pattern for BC edges** (useStore.ts:493-520 `enrichEdges` — shows the type-discriminator + style assignment shape):

```typescript
export function enrichEdges(edges: Edge[], nodes: Node[]): Edge[] {
  const typedEdges = edges.map((e) => {
    const srcNode = nodes.find((n) => n.id === e.source);
    if (!srcNode) return e;
    const srcComp = getComponent((srcNode.data as unknown as StreamNodeData).componentId);
    if (!srcComp) return e;
    const srcPort = srcComp.ports.find((p) => p.name === e.sourceHandle);
    if (srcPort?.type === "ThermalPort") {
      const { markerEnd, ...rest } = e as Edge & { markerEnd?: unknown };
      return rest;
    }
    return {
      ...e,
      type: "hydraulicEdge",
      markerEnd: { type: MarkerType.ArrowClosed, width: 16, height: 16, color: "#b1b1b7" },
    };
  });
  return typedEdges;
}
```

**Phase 63 extension** — add a `srcPort?.type === "BCPort"` branch that sets `type: "bcEdge"` and strips `markerEnd`. Initial `data: { targetSide: "both" } satisfies BCEdgeData`.

**Per-instance counter precedent** (useStore.ts:237-241 `getNextInstanceName`) — Phase 63's D-20 `+ New WallTemperature` button reuses this via `addNode("WallTemperature", position)` which already calls `getNextInstanceName` at line 747.

---

### `gui/src/lib/codeGenerator.ts` (MODIFIED — 5-mode emit)

**Self-analog:** codeGenerator.ts:794-877 (Power Shape per-kind switch — the strongest precedent for per-mode emission).

**Per-kind switch pattern** (lines 853-871 — copy this shape for the 5 BC modes):

```typescript
switch (psResource.kind) {
  case "uniform":
    lines.push(`${varName} = ones(${nz}, ${nx})`);
    break;
  case "z_cosine": {
    const amp = psResource.params.amplitude ?? 1.0;
    lines.push(
      `${varName} = cosine_power_shape(${nz}, ${nx}; amplitude=${formatReal(amp)})`,
    );
    break;
  }
  case "file_loaded": {
    const path = psResource.params.path ?? "TODO_set_path.csv";
    lines.push(
      `${varName} = rebin_extensive(readdlm(joinpath(@__DIR__, ${JSON.stringify(path)}), ','), (${nz}, ${nx}))`,
    );
    break;
  }
}
```

**Unset-sentinel emit pattern** (lines 817-823 — copy this shape for Mark + required-unset per D-09 + CD-01):

```typescript
if (psRef === SENTINEL_UNSET_POWER_SHAPE_UUID) {
  const varName = `power_shape_unset_for_${hdName}`;
  psVarFor.set(node.id, varName);
  lines.push(
    `${varName} = ones(${nz}, ${nx})  # TODO: fill in your power shape`,
  );
  continue;
}
```

For Phase 63 Mark mode + required-unset, emit a comment-only line (no equation):

```typescript
// In the eqs section, replace the binding equation with a comment:
lines.push(`    # TODO: set ${chName}.${field}[i] here`);
```

**rebin_extensive emit precedent** (line 867 — exact shape Phase 63 reuses for `rebin_intensive`):

```typescript
`${varName} = rebin_extensive(readdlm(joinpath(@__DIR__, ${JSON.stringify(path)}), ','), (${nz}, ${nx}))`
```

For Phase 63 Profile-mode file import:

```typescript
`${varName} = rebin_intensive(readdlm(joinpath(@__DIR__, ${JSON.stringify(path)}), ','), ${n})`
```

(1D, not tuple `(nz, nx)` — `rebin_intensive` has both signatures; BCs use the 1D form.)

**Conditional `using DelimitedFiles` pattern** — codeGenerator.ts already emits this when any Power Shape is file_loaded; Phase 63 extends the OR condition (RESEARCH §"Emit phases" table). The planner finds this conditional at codeGenerator.ts (search for `"using DelimitedFiles"`).

**Insertion ordering** (RESEARCH §"Emit phases" table — these are the slots Phase 63 fills):
1. BC profile-import bindings: after Components loop (line 941), before `eqs = [`.
2. BC function stubs: after profile-imports, before `eqs = [`.
3. BC binding equations: inside `eqs = [`, after `connect()` lines.
4. Mark/unset TODO comments: emit at top of eqs block.

---

### `src/utilities.jl` (MODIFIED — append `rebin_intensive`)

**Self-analog:** `src/utilities.jl` lines 19-109 — the entire `_rebin_1d` + `rebin_extensive` block is the template.

**Internal helper pattern** (utilities.jl:33-56 — `_rebin_1d` private helper):

```julia
function _rebin_1d(v::AbstractVector{<:Real}, n_out::Integer)
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
            # Fraction of v[i] living in target cell j (overlap / source-width).
            out[j] += v[i] * overlap * n_in
        end
    end
    return out
end
```

**Phase 63 intensive variant** — same arithmetic, but multiply by `n_out` (target cell-width) instead of `n_in` (source cell-width). RESEARCH §"Example 1" gives the exact body.

**Public function pattern** (utilities.jl:95-109 — `rebin_extensive` 2D separable z-then-x):

```julia
function rebin_extensive(M::AbstractMatrix{<:Real}, target_shape::Tuple{Int,Int})
    nz_out, nx_out = target_shape
    nz_in, nx_in   = size(M)
    # Pass 1: rebin each column along z.
    intermediate = Matrix{Float64}(undef, nz_out, nx_in)
    for j in 1:nx_in
        intermediate[:, j] = _rebin_1d(view(M, :, j), nz_out)
    end
    # Pass 2: rebin each row along x.
    out = Matrix{Float64}(undef, nz_out, nx_out)
    for i in 1:nz_out
        out[i, :] = _rebin_1d(view(intermediate, i, :), nx_out)
    end
    return out
end
```

**Phase 63 2D `rebin_intensive`** — identical structure, calling a new `_rebin_1d_intensive` for both passes. RESEARCH §"Example 1" gives the full body.

**Docstring pattern** (utilities.jl:59-94 — Markdown sections `# Arguments`, `# Returns`, `# Algorithm`, `# Caller trust`):

The `# Caller trust` section is mandatory and must repeat the same caller-trust posture (per `feedback_power_shape_trust_caller.md` memory): no validation, no normalization, NaN flows through.

**Multiple dispatch pattern** (utilities.jl:95 + the new 1D form per RESEARCH Pattern: `rebin_intensive(v::AbstractVector, n)` vs `rebin_intensive(M::AbstractMatrix, shape::Tuple)`) — per `feedback_keyword_only_rule.md`, use positional + dispatch on array type, not kwargs. Same shape as `rebin_extensive`.

---

### `test/test_utilities.jl` (MODIFIED — append `rebin_intensive` testsets)

**Self-analog:** `test/test_utilities.jl` lines 16-101 — CONS-01..04 testsets are the template.

**Testset pattern** (test_utilities.jl:25-65 — CONS-01):

```julia
@testset "CONS-01: rebin_extensive sum-conservation across all reshape regimes" begin
    rtol = 1e-12

    # (a) identity 4x4 -> 4x4
    M = rand(4, 4)
    @test isapprox(sum(rebin_extensive(M, (4, 4))), sum(M); rtol=rtol)

    # (b) integer up 3x3 -> 9x9
    M = rand(3, 3)
    @test isapprox(sum(rebin_extensive(M, (9, 9))), sum(M); rtol=rtol)
    # ... cases (c) through (i)
end
```

**Phase 63 testsets** — INT-01..05 per RESEARCH §"Example 2" (uniform-input preservation, identity, cross-check identity with `rebin_extensive`, 2D separable, degenerate row/col).

**Import pattern** (test_utilities.jl:1-3):

```julia
using Test
using STREAM
import STREAM: rebin_extensive, cosine_power_shape
```

Phase 63 adds `rebin_intensive` to the import list:

```julia
import STREAM: rebin_extensive, rebin_intensive, cosine_power_shape
```

---

### `src/STREAM.jl` (MODIFIED — append export)

**Self-analog:** STREAM.jl:100 — the existing `export rebin_extensive, cosine_power_shape` line.

```julia
export rebin_extensive, cosine_power_shape
```

Phase 63 appends `rebin_intensive`:

```julia
export rebin_extensive, rebin_intensive, cosine_power_shape
```

Per CLAUDE.md: all public exports declared in `STREAM.jl`; never `export` inside component files.

---

## Shared Patterns

### Snapshot-before-mutation (zundo replacement)

**Source:** `gui/src/store/useStore.ts:613-622`
**Apply to:** Every Phase 63 store action that mutates state (setBCMode, clearBCMode, cycleBCEdgeTargetSide, setBCSymmetric, _onBCEdgeAdded, _onBCEdgeRemoved).

```typescript
_pushSnapshot: () => {
  const { nodes, edges, bcs, resources, modelOptions, _undoPast } = get();
  set({
    _undoPast: [...
    _undoPast,
    { nodes, edges, bcs, resources, modelOptions },
    ].slice(-50),
    _undoFuture: [],
  });
},
```

Phase 63 must extend the captured object to `{ nodes, edges, bcs, resources, modelOptions, bcMode, bcSymmetric }`. The `undo` and `redo` actions (lines 624-666) must mirror the extension.

### Registry-driven port-type lookup

**Source:** `gui/src/components/CanvasPanel.tsx:25-32`
**Apply to:** `StreamNode.tsx` drop-overlay activation (read `getPortType(connection.fromNode.id, connection.fromHandle.id)` to filter for BCPort drags). Also reused by `isValidConnection` BCPort branch.

```typescript
export function getPortType(nodeId: string, handleId: string): string | null {
  const node = useStore.getState().nodes.find((n) => n.id === nodeId);
  if (!node) return null;
  const comp = getComponent((node.data as unknown as StreamNodeData).componentId);
  if (!comp) return null;
  const port = comp.ports.find((p) => p.name === handleId);
  return port?.type ?? null;
}
```

### Caller-trust posture for Julia helpers

**Source:** `src/utilities.jl:13-15` + docstring section at lines 89-93
**Apply to:** `rebin_intensive` (both 1D and 2D signatures) — no input validation, no normalization, NaN/zero/negative flow through.

```julia
# Caller-trust posture (D-25 + project memory `feedback_power_shape_trust_caller.md`):
# these functions do NOT validate, normalize, or guard positivity / shape /
# NaN. Whatever you put in is what gets resampled.
```

The `# Caller trust` docstring section is required in `rebin_intensive` per the same memory.

### Hard-block connection rules

**Source:** `gui/src/components/CanvasPanel.tsx:141-155` (existing FlowPort/ThermalPort enforcement)
**Apply to:** `isValidConnection` extension for BCPort (per D-21 — WT→Channel allowed; WT→CHF/CAC blocked; HFS→CHF allowed; HFS→Channel/CAC blocked).

The pattern is: read `sourceType` + `targetType` via `getPortType`, branch by `sourceType`, return false for any mismatch. Keep the function pure — n-mismatch red-ring fires post-creation in the store (RESEARCH Pitfall 7).

### Sentinel-via-absence (required-unset)

**Source:** `gui/src/store/useStore.ts:36-44` (SENTINEL_UNSET_POWER_SHAPE) + RESEARCH Anti-Pattern: "Implementing required-unset via a magic 'unset' mode value"
**Apply to:** `bcMode[key] === undefined` is the canonical required-unset sentinel (D-09). Do NOT store `{mode: "unset"}` in the record. UI checks `active === undefined` to render the no-active-pill state; codegen emits the TODO comment when the key is missing.

---

## No Analog Found

No Phase 63 files lack a close analog. Every new file maps to either a sibling primitive in the same directory (HydraulicEdge for BCEdge, ModeToggle for BCModePicker, ParameterForm for BCsTabForm) or to the existing Phase 62 Power Shape Resource emit path (codeGenerator.ts) and `rebin_extensive` Julia helper (utilities.jl).

Two patterns Phase 63 introduces that have no direct prior:

| Pattern | Closest Existing | Recommendation |
|---------|------------------|----------------|
| ReactFlow `useConnection()` whole-body drop overlay | None — Phase 63 first use | Follow RESEARCH Pattern 2 verbatim; do NOT hand-roll mouse listeners (RESEARCH Anti-Pattern + Don't-Hand-Roll table) |
| `EdgeLabelRenderer` portal for click-to-cycle chip | None — Phase 63 first use | Follow RESEARCH Pattern 3 verbatim; SVG `<text>` is the anti-pattern |

Both are RESEARCH-anchored to single idiomatic ReactFlow v12 solutions; no codebase analog needed.

## Metadata

**Analog search scope:**
- `gui/src/components/sidebar/` — 11 files
- `gui/src/components/` — 17 files
- `gui/src/store/` — useStore.ts + __tests__
- `gui/src/lib/` — codeGenerator.ts, utils.ts, projectIO.ts
- `src/` — utilities.jl, STREAM.jl
- `test/` — test_utilities.jl
- `gui/src/components/__tests__/`, `gui/src/components/sidebar/__tests__/`, `gui/src/store/__tests__/`, `gui/src/lib/__tests__/`

**Files scanned:** ~40 (read targets) + analog-source files inspected for excerpts above.
**Pattern extraction date:** 2026-05-13
