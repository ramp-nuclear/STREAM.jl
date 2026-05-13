---
phase: 63
plan: D
type: execute
wave: 2
depends_on:
  - B
files_modified:
  - gui/src/components/BCEdge.tsx
  - gui/src/components/StreamNode.tsx
  - gui/src/components/CanvasPanel.tsx
  - gui/src/components/ToolboxPanel.tsx
  - gui/src/components/__tests__/BCEdge.test.tsx
  - gui/src/components/__tests__/StreamNode.test.tsx
  - gui/src/components/__tests__/CanvasPanel.bc.test.tsx
  - gui/src/components/__tests__/ToolboxPanel.test.tsx
autonomous: true
requirements:
  - D-10
  - D-11
  - D-12
  - D-17
  - D-18
  - D-19
  - D-21
  - D-22
  - D-24
  - CD-03
user_setup: []

must_haves:
  truths:
    - "`BCEdge.tsx` renders a smooth-step edge with `stroke=var(--muted-foreground)`, `strokeWidth=1.5`, `strokeDasharray='6 3'` (D-12) — no markerEnd arrowhead"
    - "BC edge displays an inline click-to-cycle chip at the mid-edge showing `L+R` / `L` / `R`; click cycles via `cycleBCEdgeTargetSide` store action (D-11)"
    - "`StreamNode.tsx` renders a hollow-square `BCPort` handle (no fill, 1.5px stroke `var(--muted-foreground)`, side='right') for nodes whose registry entry has a `BCPort`-typed port (WallTemperature, HeatFluxSource) (D-18)"
    - "Source blocks (WT, HFS) display a two-line label: instance name on top, mode-aware value on bottom (`T_wall = 320 K` / `T_wall = vector (n=10)` / `T_wall = fn(t)` / `T_wall = (unset)`) (D-19)"
    - "Whole-component drop-zone overlay activates on `StreamNode` ONLY when (a) a connection is in-flight AND (b) the in-flight drag's source port is BCPort AND (c) the target node has `external_inputs.length > 0` (D-10, CD-03)"
    - "`CanvasPanel.tsx` registers `bcEdge: BCEdge` in `edgeTypes`; `isValidConnection` extended with BCPort branch using `isAllowedBCConnection` allow-list — WT→Channel and HFS→CHF allowed; everything else hard-blocked (D-21)"
    - "n-mismatch flagged in store as red-ring on both endpoints; StreamNode renderer reads `errorNodeIds` and applies a red outline class when the node has any error tag (D-22)"
    - "Sources toolbox category lists `WallTemperature` and `HeatFluxSource` as draggable items; drag-onto-canvas creates a new node with smart-name (D-24)"
  artifacts:
    - path: "gui/src/components/BCEdge.tsx"
      provides: "ReactFlow custom edge with dashed style + EdgeLabelRenderer mid-edge chip"
      contains: "var(--muted-foreground)"
    - path: "gui/src/components/StreamNode.tsx"
      provides: "Extended StreamNode rendering: BCPort hollow-square handle, source-block two-line label, errorNodeIds-driven red-ring outline, useConnection-filtered whole-body drop overlay"
      contains: "BCPort"
    - path: "gui/src/components/CanvasPanel.tsx"
      provides: "edgeTypes.bcEdge registered + isValidConnection BCPort allow-list enforcement"
      contains: "isAllowedBCConnection"
    - path: "gui/src/components/ToolboxPanel.tsx"
      provides: "Sources category populated with WallTemperature + HeatFluxSource draggables"
      contains: "Sources"
  key_links:
    - from: "gui/src/components/CanvasPanel.tsx"
      to: "gui/src/lib/bcMode.ts"
      via: "import { isAllowedBCConnection }; called inside isValidConnection"
      pattern: "isAllowedBCConnection"
    - from: "gui/src/components/StreamNode.tsx"
      to: "gui/src/store/useStore.ts"
      via: "useStore selectors for bcMode (label rendering) + errorNodeIds (red-ring)"
      pattern: "errorNodeIds|bcMode"
    - from: "gui/src/components/BCEdge.tsx"
      to: "gui/src/store/useStore.ts"
      via: "cycleBCEdgeTargetSide action called from chip onClick"
      pattern: "cycleBCEdgeTargetSide"
    - from: "gui/src/components/CanvasPanel.tsx"
      to: "gui/src/components/BCEdge.tsx"
      via: "edgeTypes = { hydraulicEdge: HydraulicEdge, bcEdge: BCEdge }"
      pattern: "bcEdge: BCEdge"
---

<objective>
Land all canvas-side surfaces for Phase 63 BCs:

1. `BCEdge.tsx` — new custom edge with dashed style (D-12) + inline click-to-cycle target-side chip (D-11) via `EdgeLabelRenderer` portal.
2. `StreamNode.tsx` — extend to render BCPort hollow-square handles (D-18), source-block two-line labels (D-19), and a whole-body drop overlay activated only by BCPort drags filtered via `useConnection().fromHandle` port-type lookup (D-10, CD-03).
3. `CanvasPanel.tsx` — register `bcEdge` in `edgeTypes`; extend `isValidConnection` with the BCPort allow-list using the pure validator `isAllowedBCConnection` (D-21).
4. `ToolboxPanel.tsx` — populate the empty Sources category (reserved by Phase 62) with `WallTemperature` + `HeatFluxSource` draggables (D-24).

Per `feedback_smoke_test_scope_match.md`: the unit tests cover behavior; the whole-body drop activation and the `+ New` end-to-end flow are jsdom-unfriendly and are listed as Manual-Only in `63-VALIDATION.md` (D-10 manual smoke, D-20 manual smoke).

Output: 4 modified component files + 4 new/extended test files.
</objective>

<execution_context>
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/workflows/execute-plan.md
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@CLAUDE.md
@.planning/STATE.md
@.planning/phases/63-bcs-tab-value-source-components-in-gui/63-CONTEXT.md
@.planning/phases/63-bcs-tab-value-source-components-in-gui/63-RESEARCH.md
@.planning/phases/63-bcs-tab-value-source-components-in-gui/63-PATTERNS.md
@.planning/phases/63-bcs-tab-value-source-components-in-gui/63-VALIDATION.md
@.planning/phases/63-bcs-tab-value-source-components-in-gui/63-B-PLAN.md
@gui/src/components/HydraulicEdge.tsx
@gui/src/components/StreamNode.tsx
@gui/src/components/CanvasPanel.tsx
@gui/src/components/ToolboxPanel.tsx
@gui/src/components/ToolboxItem.tsx
@gui/src/components/__tests__/StreamNode.test.tsx
@gui/src/components/__tests__/ToolboxPanel.test.tsx
@gui/src/components/__tests__/ConnectionValidation.test.tsx
@gui/src/store/useStore.ts
@gui/src/lib/bcMode.ts
@gui/src/registry/components.json
@gui/src/registry/index.ts

<interfaces>
<!-- Source-of-truth shapes Phase 63-D consumes. -->

From gui/src/components/HydraulicEdge.tsx (sibling — exact analog):
  function HydraulicEdge({id, sourceX, sourceY, targetX, targetY, sourcePosition, targetPosition, style, markerEnd}: EdgeProps) {
    const [path] = getSmoothStepPath({sourceX, sourceY, targetX, targetY, sourcePosition, targetPosition});
    return <BaseEdge id={id} path={path} style={style} markerEnd={markerEnd} />;
  }

From gui/src/components/CanvasPanel.tsx:
  Line 25-32: export function getPortType(nodeId: string, handleId: string): string | null
  Line 38-40: const edgeTypes: EdgeTypes = { hydraulicEdge: HydraulicEdge };
  Line 141-155: const isValidConnection = useCallback((connection) => { ... port-type check ... }, []);

From gui/src/components/StreamNode.tsx:
  Lines 65-99: handle-rendering loop (flowPorts + thermalPorts maps over component.ports).
  Existing handle styles: FLOW_IN_BG/FLOW_OUT_BG (filled circles), thermal handles use diamond rotation.

From gui/src/components/ToolboxPanel.tsx:
  Lines 25-40: Hydraulic category block — `getComponentsByCategory("Hydraulic")` + ToolboxItem map.
  Lines 62-65 (per 63-PATTERNS): Sources category header from Phase 62 (currently empty).

From gui/src/store/useStore.ts (post-63-B):
  cycleBCEdgeTargetSide(edgeId: string): void
  bcMode: Record<string, BCModeEntry>
  errorNodeIds: Record<string, string[]>
  setBCMode(...) → adds BC edge when mode='source' (already handles edge creation; CanvasPanel just needs to allow the connection)

From gui/src/lib/bcMode.ts (post-63-B):
  isAllowedBCConnection(sourceComponentId: string, targetComponentId: string): boolean
  cycleBCEdgeTargetSide(current): next  // pure helper (NOT the store action of the same name; the store action calls this)
  BCEdgeData: { componentId; externalInputName; targetSide: "left" | "right" | "both" }

From gui/src/registry/index.ts:
  getComponentsByCategory(category: string): ComponentDefinition[]
  getComponent(id: string): ComponentDefinition | undefined

From gui/src/registry/components.json (Phase 61):
  WallTemperature: category "Sources", ports = [{name:"T_wall_out", type:"BCPort", side:"right"}]
  HeatFluxSource: category "Sources", ports = [{name:"q_out", type:"BCPort", side:"right"}]
  Both expose a single Real|Vector|Function `T_wall` (or `q`) parameter — read for D-19 label generation.

ReactFlow v12 APIs (per 63-RESEARCH §"ReactFlow v12 APIs"):
  useConnection() — returns ConnectionState | null. During drag: { inProgress, fromHandle: {id, nodeId, ...} | null, fromNode, ... }.
  EdgeLabelRenderer — portal-based component for HTML overlays at given coords; requires `pointerEvents: 'all'` + `nopan` className.
  getSmoothStepPath(...) → returns tuple [path, labelX, labelY]; labelX/labelY are the mid-edge anchor for the chip.
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 63-D-01: Create `BCEdge.tsx` (dashed style + EdgeLabelRenderer click-to-cycle chip) and its test file</name>
  <files>gui/src/components/BCEdge.tsx, gui/src/components/__tests__/BCEdge.test.tsx</files>
  <read_first>
    - gui/src/components/HydraulicEdge.tsx (entire file — the structural template; 32 lines, mirror exactly)
    - gui/src/lib/bcMode.ts (post-63-B-01) — `BCEdgeData` type + `cycleBCEdgeTargetSide` pure helper (the store action of the same name calls the pure helper)
    - gui/src/store/useStore.ts (post-63-B) — the action `cycleBCEdgeTargetSide(edgeId)` and edge.data shape
    - gui/src/components/__tests__/StreamNode.test.tsx (vitest pattern for a ReactFlow custom component test — note the `<ReactFlowProvider>` wrapper required for child renders)
    - .planning/phases/63-bcs-tab-value-source-components-in-gui/63-PATTERNS.md section "`gui/src/components/BCEdge.tsx` (NEW)" lines ~252-303 — the extension recipe
    - .planning/phases/63-bcs-tab-value-source-components-in-gui/63-CONTEXT.md — D-11 (chip cycles L+R → L → R → L+R, click-only, always visible), D-12 (exact style values)
    - .planning/phases/63-bcs-tab-value-source-components-in-gui/63-RESEARCH.md §"Pattern 3" (EdgeLabelRenderer portal pattern; `pointerEvents: 'all'` + `nopan` class)
  </read_first>
  <action>
A. Create `gui/src/components/BCEdge.tsx`:

```
import { memo } from "react";
import {
  BaseEdge,
  EdgeLabelRenderer,
  getSmoothStepPath,
  type EdgeProps,
} from "@xyflow/react";
import useStore from "@/store/useStore";
import type { BCEdgeData } from "@/lib/bcMode";
```

Component body:
1. Destructure `id, sourceX, sourceY, targetX, targetY, sourcePosition, targetPosition, data` from `EdgeProps`.
2. `const [path, labelX, labelY] = getSmoothStepPath({sourceX, sourceY, targetX, targetY, sourcePosition, targetPosition})`.
3. `const edgeData = data as BCEdgeData | undefined;`
4. `const targetSide = edgeData?.targetSide ?? "both";`
5. `const chipLabel = targetSide === "both" ? "L+R" : targetSide === "left" ? "L" : "R";` (D-11 chip text mapping).
6. `const cycle = useStore(state => state.cycleBCEdgeTargetSide);` — read action.
7. Render:
   ```
   <>
     <BaseEdge
       id={id}
       path={path}
       style={{
         stroke: "var(--muted-foreground)",
         strokeWidth: 1.5,
         strokeDasharray: "6 3",
       }}
     />
     <EdgeLabelRenderer>
       <div
         className="nopan absolute pointer-events-auto"
         style={{
           transform: `translate(-50%, -50%) translate(${labelX}px, ${labelY}px)`,
           pointerEvents: "all",
         }}
       >
         <button
           type="button"
           onClick={() => cycle(id)}
           className="rounded border bg-background px-[6px] py-[2px] text-xs text-muted-foreground hover:bg-accent"
         >
           {chipLabel}
         </button>
       </div>
     </EdgeLabelRenderer>
   </>
   ```

8. `export default memo(BCEdge);`

Do NOT consume the `style` or `markerEnd` props from `EdgeProps` — BC edges have a fixed visual idiom per D-12 (no arrowhead, fixed dashed style).

B. Create `gui/src/components/__tests__/BCEdge.test.tsx`:

```
// @vitest-environment happy-dom
import { describe, it, expect, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { ReactFlowProvider } from "@xyflow/react";
import BCEdge from "../BCEdge";
import useStore from "@/store/useStore";
```

Tests:
- `it("renders a path with dashed muted-foreground style (D-12)")` — render the component inside `<ReactFlowProvider>` with EdgeProps fixture; query for the `<path>` SVG element and assert `style.strokeDasharray === "6 3"` and `style.strokeWidth === "1.5"` and `style.stroke` references `var(--muted-foreground)`.
- `it("renders the chip label 'L+R' by default when targetSide is 'both' (D-11)")` — fixture `data: {targetSide: "both", componentId:"ch1", externalInputName:"T_wall_left"}`; assert `screen.getByText("L+R")` exists.
- `it("renders the chip label 'L' when targetSide is 'left' (D-11)")`.
- `it("renders the chip label 'R' when targetSide is 'right' (D-11)")`.
- `it("clicking the chip calls cycleBCEdgeTargetSide with the edge id (D-11)")` — mock `useStore.getState()` or spy on `cycleBCEdgeTargetSide`; `fireEvent.click(screen.getByText("L+R"))`; assert spy called once with edge id.
- `it("does NOT render any markerEnd arrowhead (D-12 — BC edges have no arrow)")` — assert no `<marker>` or `markerEnd` attribute on the path.

Use a `wrapper` that provides `<ReactFlowProvider>` because `useStore` + `EdgeLabelRenderer` may depend on context. If EdgeLabelRenderer requires a renderer panel, you can also render the edge inside a minimal `<ReactFlow nodes={[]} edges={[]}>...</ReactFlow>` test harness (consult existing edge tests in `gui/src/components/__tests__/` for the proven pattern; if none exist, use a stub wrapper that mocks `EdgeLabelRenderer` to `({children}) => <div>{children}</div>` via `vi.mock("@xyflow/react", ...)`).
  </action>
  <verify>
    <automated>cd gui && npx vitest run src/components/__tests__/BCEdge.test.tsx</automated>
  </verify>
  <acceptance_criteria>
    - `gui/src/components/BCEdge.tsx` exists
    - `grep -E 'var\(--muted-foreground\)' gui/src/components/BCEdge.tsx` returns at least 1 line
    - `grep -E 'strokeDasharray.*"6 3"' gui/src/components/BCEdge.tsx` returns 1 line
    - `grep -E 'strokeWidth.*1\.5' gui/src/components/BCEdge.tsx` returns 1 line
    - `grep -E 'EdgeLabelRenderer' gui/src/components/BCEdge.tsx` returns at least 1 line
    - `grep -E 'cycleBCEdgeTargetSide' gui/src/components/BCEdge.tsx` returns at least 1 line
    - `grep -E '"L\+R"|"L"|"R"' gui/src/components/BCEdge.tsx` returns at least 3 lines (the three chip-label cases)
    - `gui/src/components/__tests__/BCEdge.test.tsx` has at least 6 `it(...)` blocks: `grep -c '^\s*it(' gui/src/components/__tests__/BCEdge.test.tsx` returns at least 6
    - `cd gui && npx vitest run src/components/__tests__/BCEdge.test.tsx` exits 0
  </acceptance_criteria>
  <done>BCEdge renders dashed + chip; click cycles via store action; visible behavior covered by vitest.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 63-D-02: Extend `StreamNode.tsx` with BCPort hollow-square handle, source-block two-line label, errorNodeIds red-ring outline, whole-body BCPort drop overlay; extend `StreamNode.test.tsx`</name>
  <files>gui/src/components/StreamNode.tsx, gui/src/components/__tests__/StreamNode.test.tsx</files>
  <read_first>
    - gui/src/components/StreamNode.tsx (entire file — focus on handle-rendering loop at lines 65-99; understand FLOW_IN/FLOW_OUT/ThermalPort styling conventions)
    - gui/src/components/CanvasPanel.tsx lines 25-32 (`getPortType(nodeId, handleId)` — reused for drop activation filter)
    - gui/src/store/useStore.ts (post-63-B) — `errorNodeIds`, `bcMode` (for label rendering)
    - gui/src/lib/bcMode.ts (post-63-B) — `bcModeKey`, `BCModeEntry`
    - gui/src/registry/components.json — confirm `WallTemperature` and `HeatFluxSource` have a Properties-tab parameter (e.g., `T_wall` for WT, `q` for HFS) of type `Real | Vector | Function`
    - .planning/phases/63-bcs-tab-value-source-components-in-gui/63-PATTERNS.md section "`gui/src/components/StreamNode.tsx` (MODIFIED)" lines ~417-485 — exact BCPort handle JSX + drop overlay pseudocode
    - .planning/phases/63-bcs-tab-value-source-components-in-gui/63-CONTEXT.md — D-18 (hollow square style), D-19 (two-line label with mode-aware bottom line), D-10 (whole-body drop activation rules), CD-03 (use ReactFlow useConnection, not hand-rolled mouse listeners)
    - .planning/phases/63-bcs-tab-value-source-components-in-gui/63-RESEARCH.md §"Pattern 2" + Pitfall 4 (useConnection() returns null when no drag; gate all overlay logic on `connection?.inProgress`)
    - gui/src/components/__tests__/StreamNode.test.tsx (pre-existing test scaffold; add new tests, don't replace)
  </read_first>
  <action>
A. Edit `gui/src/components/StreamNode.tsx`:

1. Add imports:
   - `import { useConnection } from "@xyflow/react";` (alongside existing `Handle`, `Position` imports)
   - `import useStore from "@/store/useStore";`
   - `import { bcModeKey, type BCModeEntry } from "@/lib/bcMode";`
   - `import { getPortType } from "./CanvasPanel";` (already exported per 63-PATTERNS)

2. Add BCPort handle rendering loop. After the existing FlowPort + ThermalPort handle maps (around line 99), add:

   ```
   const bcPorts = (component.ports ?? []).filter((p) => p.type === "BCPort");
   ```

   then in JSX (alongside the existing handle maps):

   ```
   {bcPorts.map((port) => (
     <Handle
       key={port.name}
       id={port.name}
       type="source"
       position={sideToPosition[port.side ?? "right"]}
       data={{ portType: port.type }}
       style={{
         background: "transparent",
         border: "1.5px solid var(--muted-foreground)",
         width: 10,
         height: 10,
         borderRadius: 0,
       }}
     />
   ))}
   ```

3. Add whole-body drop-zone overlay. At the top of the component body:

   ```
   const connection = useConnection();
   const isConsumerNode = (component.external_inputs?.length ?? 0) > 0;
   const dropActive =
     !!connection?.inProgress &&
     !!connection.fromNode &&
     !!connection.fromHandle?.id &&
     getPortType(connection.fromNode.id, connection.fromHandle.id) === "BCPort" &&
     isConsumerNode &&
     connection.fromNode.id !== id;  // don't self-drop
   ```

   Then in JSX, ABOVE the main node body div, render:

   ```
   {dropActive && (
     <div
       className="absolute inset-0 rounded border-2 border-dashed pointer-events-none"
       style={{ borderColor: "var(--muted-foreground)" }}
     >
       <div className="absolute -top-[20px] left-1/2 -translate-x-1/2 rounded bg-background px-[6px] py-[2px] text-xs text-muted-foreground border">
         Connect BC
       </div>
     </div>
   )}
   ```

   Note: `pointer-events-none` so the dashed outline doesn't intercept the actual drop; ReactFlow's connection-drop mechanism handles the underlying handle hit-testing (we just visualize availability per CD-03 — pure ReactFlow extensibility, no hand-rolled mouse listeners).

4. Add errorNodeIds red-ring outline. Read `const errorTags = useStore(state => state.errorNodeIds[id] ?? [])`. If `errorTags.length > 0`, add an outer class `ring-2 ring-destructive ring-offset-1` (or equivalent existing convention) to the node root div. Existing selection / hover ring should NOT be replaced — combine via class composition.

5. Source-block two-line label (D-19). For nodes whose `component.id === "WallTemperature"` or `"HeatFluxSource"`:
   - Top line: existing instance name rendering (unchanged).
   - Bottom line: read the relevant constructor parameter from `node.data.parameters` (`T_wall` for WT, `q` for HFS).
     * If value is a number: render `${label} = ${value} ${unit}` (e.g., `T_wall = 320 K`). Unit comes from registry parameter metadata.
     * If value is a vector (Array.isArray): render `${label} = vector (n=${parameters.n})` — D-19 line 88.
     * If value is a Function or signature string (the registry uses string-encoded Function values): render `${label} = fn(t)`.
     * If value is `undefined` or null or empty string: render `${label} = (unset)` with `className="text-destructive/80"`.

   Implementation: add a small helper inside `StreamNode.tsx` (private, not exported): `function sourceLabelLine(parameters: Record<string, unknown>, fieldName: string, unit: string): {text: string, muted: boolean}`. Use it for both WT and HFS branches.

   For non-source-block nodes (Pump, Channel, etc.): existing single-line label rendering unchanged.

B. Extend `gui/src/components/__tests__/StreamNode.test.tsx` (append new tests; do NOT delete pre-existing tests):

Add tests:
- `it("renders BCPort hollow-square handle on WallTemperature (D-18)")` — render WT node fixture; query the BCPort handle element; assert its style: `background === "transparent"`, `border` contains `1.5px solid var(--muted-foreground)`, `borderRadius === "0px"`.
- `it("renders BCPort hollow-square handle on HeatFluxSource (D-18)")`.
- `it("does NOT render BCPort handle on a Channel (Channel has no BCPort port)")` — render Channel fixture; assert no element with the BCPort style.
- `it("renders source-block label 'T_wall = 320 K' when T_wall is a scalar (D-19)")` — WT node with `parameters: {T_wall: 320, n: 10}`; assert text matches `/T_wall\s*=\s*320/`.
- `it("renders source-block label 'T_wall = vector (n=10)' when T_wall is an array (D-19)")`.
- `it("renders source-block label 'T_wall = fn(t)' when T_wall is a function-typed value (D-19)")` — registry function values are encoded as strings (e.g., `"fn(t)"`) — match the encoding the registry actually uses; consult `gui/src/components/sidebar/FunctionSelect.tsx` for the encoding.
- `it("renders source-block label 'T_wall = (unset)' in muted-destructive when T_wall is unset (D-19)")` — assert text + the element has the muted-destructive class.
- `it("applies red-ring outline when errorNodeIds[nodeId] contains a tag (D-22)")` — seed `useStore.setState({errorNodeIds: {"wt1": ["bc-n-mismatch"]}})`; render WT; assert outer div has a class matching `/ring-destructive/`.
- `it("does NOT apply red-ring when errorNodeIds is empty for that node")`.

DO NOT add a test for the whole-body drop overlay activation visibility — that requires a live `useConnection()` state that jsdom cannot simulate faithfully (per 63-VALIDATION.md Manual-Only table, D-10 is manual-smoke-only).
  </action>
  <verify>
    <automated>cd gui && npx vitest run src/components/__tests__/StreamNode.test.tsx</automated>
  </verify>
  <acceptance_criteria>
    - `grep -E 'BCPort' gui/src/components/StreamNode.tsx` returns at least 3 lines (filter, handle, drop overlay activation)
    - `grep -E 'useConnection' gui/src/components/StreamNode.tsx` returns at least 1 line
    - `grep -E 'getPortType' gui/src/components/StreamNode.tsx` returns at least 1 line
    - `grep -E 'errorNodeIds' gui/src/components/StreamNode.tsx` returns at least 1 line
    - `grep -E 'Connect BC' gui/src/components/StreamNode.tsx` returns 1 line
    - `grep -E 'borderRadius: 0' gui/src/components/StreamNode.tsx` returns at least 1 line (the hollow-square handle)
    - `grep -E 'WallTemperature|HeatFluxSource' gui/src/components/StreamNode.tsx` returns at least 2 lines (source-label branches)
    - `grep -E '\(unset\)' gui/src/components/StreamNode.tsx` returns at least 1 line
    - `cd gui && npx vitest run src/components/__tests__/StreamNode.test.tsx` exits 0
    - `cd gui && npx tsc --noEmit 2>&1 | grep -E 'StreamNode\.tsx'` returns 0 lines
  </acceptance_criteria>
  <done>StreamNode renders BCPort handles, source-block labels, error red-ring, and drop overlay (active state inspectable via manual smoke).</done>
</task>

<task type="auto" tdd="true">
  <name>Task 63-D-03: Extend `CanvasPanel.tsx` — register `bcEdge` in edgeTypes + extend `isValidConnection` with BCPort allow-list; add `CanvasPanel.bc.test.tsx`</name>
  <files>gui/src/components/CanvasPanel.tsx, gui/src/components/__tests__/CanvasPanel.bc.test.tsx</files>
  <read_first>
    - gui/src/components/CanvasPanel.tsx (focus on lines 25-32 `getPortType`, lines 38-40 `edgeTypes`, lines 141-155 `isValidConnection`)
    - gui/src/components/__tests__/ConnectionValidation.test.tsx (pre-existing test for `isValidConnection` — model for the new BCPort test cases)
    - gui/src/lib/bcMode.ts (post-63-B-01) — `isAllowedBCConnection` pure validator
    - gui/src/store/useStore.ts (post-63-B) — read `nodes` via `useStore.getState()`; `addEdge` already triggers `enrichEdges` which sets `edge.type = "bcEdge"`
    - .planning/phases/63-bcs-tab-value-source-components-in-gui/63-PATTERNS.md section "`gui/src/components/CanvasPanel.tsx` (MODIFIED)" lines ~488-545 — exact extension shape
    - .planning/phases/63-bcs-tab-value-source-components-in-gui/63-CONTEXT.md — D-21 (allow-list: WT→Channel, HFS→CHF; everything else hard-blocked)
    - .planning/phases/63-bcs-tab-value-source-components-in-gui/63-RESEARCH.md §"Pattern 7" + Pitfall 7 (isValidConnection MUST stay pure — no state mutation; n-mismatch flagging happens in store on addEdge, not here)
  </read_first>
  <action>
A. Edit `gui/src/components/CanvasPanel.tsx`:

1. Add imports:
   - `import BCEdge from "./BCEdge";`
   - `import { isAllowedBCConnection } from "@/lib/bcMode";`

2. Extend the `edgeTypes` map (lines 38-40):
   ```
   const edgeTypes: EdgeTypes = {
     hydraulicEdge: HydraulicEdge,
     bcEdge: BCEdge,
   };
   ```

3. Extend `isValidConnection` callback (lines 141-155). After the existing port-type check `if (sourceType && targetType && sourceType !== targetType) return false;`, add a BCPort branch:

   ```
   if (sourceType === "BCPort") {
     // Read consumer componentId from store; this stays PURE (read-only, no mutation).
     const srcNode = useStore.getState().nodes.find((n) => n.id === connection.source);
     const tgtNode = useStore.getState().nodes.find((n) => n.id === connection.target);
     if (!srcNode || !tgtNode) return false;
     const srcCompId = (srcNode.data as { componentId: string }).componentId;
     const tgtCompId = (tgtNode.data as { componentId: string }).componentId;
     return isAllowedBCConnection(srcCompId, tgtCompId);
   }
   ```

4. Do NOT mutate any store state inside `isValidConnection` (Pitfall 7). The store's `addEdge` action (triggered AFTER `isValidConnection` returns true) is the right place for the n-mismatch flagging (already handled by 63-B's `setBCMode`/`_onBCEdgeAdded` paths; for direct drag-to-connect, the connection callback path is `onConnect → addEdge → enrichEdges → store also runs n-mismatch check`). Verify the call chain: locate `onConnect` in CanvasPanel and confirm it ultimately calls a store action that runs `_checkBCNMismatch` for BC edges. If 63-B did not wire the n-check into `addEdge` proper, file a deferred-item note in this plan's SUMMARY for follow-up (planner judges if a minor extension is needed; default action: add a 1-line call to `_checkBCNMismatch` from `addEdge` for any new bcEdge created via `onConnect`).

B. Create `gui/src/components/__tests__/CanvasPanel.bc.test.tsx` (do NOT clobber `ConnectionValidation.test.tsx`):

```
// @vitest-environment happy-dom
import { describe, it, expect, beforeEach } from "vitest";
import useStore from "@/store/useStore";
import { isAllowedBCConnection } from "@/lib/bcMode";
```

Tests focus on the `isAllowedBCConnection` validator behavior AND on a higher-level "drag-to-connect creates an edge" path if testable in jsdom. Pragmatic test surface:

- `it("isAllowedBCConnection(WT, Channel) returns true (D-21)")`
- `it("isAllowedBCConnection(WT, ChannelHeatFlux) returns false (D-21)")`
- `it("isAllowedBCConnection(HFS, ChannelHeatFlux) returns true (D-21)")`
- `it("isAllowedBCConnection(HFS, Channel) returns false (D-21)")`
- `it("isAllowedBCConnection(*, ChannelAndContacts) returns false for all sources (D-21 CAC carve-out)")`
- `it("creating a WT→Channel BC edge through the store triggers enrichEdges to assign type=bcEdge")` — seed nodes; call `useStore.getState().setBCMode("ch1", "T_wall_left", {mode:"source", sourceNodeId:"wt1"})`; assert `useStore.getState().edges.find(e => e.type === "bcEdge")` exists.
- `it("creating an n-mismatched WT→Channel BC edge flags both endpoints in errorNodeIds (D-22)")` — seed WT.n=10, Channel.n=12; call setBCMode; assert `errorNodeIds["wt1"]` and `errorNodeIds["ch1"]` both contain a `"bc-n-mismatch"` tag.

The 7 isAllowedBCConnection tests are PURE — no React, no jsdom needed. The integration tests (last two) hit the store; same pattern as `useStore.bc.test.ts` from 63-B. Reusable fixture.
  </action>
  <verify>
    <automated>cd gui && npx vitest run src/components/__tests__/CanvasPanel.bc.test.tsx src/components/__tests__/ConnectionValidation.test.tsx</automated>
  </verify>
  <acceptance_criteria>
    - `grep -E 'bcEdge: BCEdge' gui/src/components/CanvasPanel.tsx` returns 1 line
    - `grep -E 'isAllowedBCConnection' gui/src/components/CanvasPanel.tsx` returns at least 1 line
    - `grep -E 'sourceType === "BCPort"' gui/src/components/CanvasPanel.tsx` returns 1 line
    - `cd gui && npx vitest run src/components/__tests__/CanvasPanel.bc.test.tsx` exits 0 (7+ tests green)
    - `cd gui && npx vitest run src/components/__tests__/ConnectionValidation.test.tsx` exits 0 (pre-existing FlowPort/ThermalPort enforcement still works)
    - `cd gui && npx tsc --noEmit 2>&1 | grep -E 'CanvasPanel\.tsx'` returns 0 lines
  </acceptance_criteria>
  <done>BCEdge registered, type allow-list enforced, n-mismatch flagging confirmed via store, FlowPort/ThermalPort enforcement preserved.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 63-D-04: Populate Sources toolbox category with `WallTemperature` + `HeatFluxSource` draggables in `ToolboxPanel.tsx`; extend test</name>
  <files>gui/src/components/ToolboxPanel.tsx, gui/src/components/__tests__/ToolboxPanel.test.tsx</files>
  <read_first>
    - gui/src/components/ToolboxPanel.tsx (entire file — Phase 62 reserved the empty Sources header around lines 62-65; the Hydraulic category block at lines 25-40 is the template)
    - gui/src/components/ToolboxItem.tsx (the draggable item component)
    - gui/src/registry/index.ts — `getComponentsByCategory("Sources")` lookup
    - gui/src/registry/components.json — confirm `WallTemperature.category === "Sources"` and `HeatFluxSource.category === "Sources"`
    - gui/src/components/__tests__/ToolboxPanel.test.tsx (pre-existing test — extend, do not replace)
    - .planning/phases/63-bcs-tab-value-source-components-in-gui/63-PATTERNS.md section "`gui/src/components/ToolboxPanel.tsx` (MODIFIED)" lines ~548-573 — exact mirroring of Hydraulic block
    - .planning/phases/63-bcs-tab-value-source-components-in-gui/63-CONTEXT.md — D-24 (Phase 62 left placeholder; Phase 63 fills it)
  </read_first>
  <action>
A. Edit `gui/src/components/ToolboxPanel.tsx`:

1. At top of component body, add (alongside the existing `hydraulicComponents`, `thermalComponents`):
   ```
   const sourceComponents = getComponentsByCategory("Sources");
   ```
   (`visibleSources` if filtering follows the Hydraulic pattern — copy the same `.filter(...)` predicates the Hydraulic block uses.)

2. Locate the existing Sources category header (Phase 62 placeholder, lines 62-65 per 63-PATTERNS). UNDER the header, add a draggable items map mirroring the Hydraulic block at lines 25-40:

   ```
   {visibleSources.length > 0 && (
     <div className="space-y-px">
       {visibleSources.map((comp) => (
         <ToolboxItem
           key={comp.id}
           componentId={comp.id}
           label={comp.label}
         />
       ))}
     </div>
   )}
   ```

   Do NOT remove the existing category header — it remains the section title.

3. Verify the `ToolboxItem` drag-onto-canvas path already exists and works (Phase 62 wired it for Hydraulic; Sources should reuse the identical drop mechanism). If `ToolboxItem` reads `componentId` and triggers `addNode(componentId, position)` on drop, no further changes needed — `addNode` already runs `getNextInstanceName` per Phase 62 (smart-name `wall_temperature_<n>` / `heat_flux_source_<n>` shared per-kind counter per CD-04).

B. Extend `gui/src/components/__tests__/ToolboxPanel.test.tsx`:

Append tests (preserve pre-existing tests):
- `it("renders WallTemperature in the Sources category (D-24)")` — assert `screen.getByText("WallTemperature")` (or whatever the registry `label` field says — read from `gui/src/registry/components.json:1015-1048` for the exact label) is present.
- `it("renders HeatFluxSource in the Sources category (D-24)")`.
- `it("Sources category header is visible (preserves Phase 62 placeholder)")`.
- `it("WallTemperature and HeatFluxSource are draggable (i.e., they render as ToolboxItem)")` — assert they appear with the same role/element shape as Hydraulic items (e.g., both rendered via the same `<ToolboxItem>` component → query by `data-testid` or class consistent with existing items).

Use the same render harness the pre-existing tests use (likely a basic `render(<ToolboxPanel />)` since ToolboxPanel reads registry directly, not via store).
  </action>
  <verify>
    <automated>cd gui && npx vitest run src/components/__tests__/ToolboxPanel.test.tsx</automated>
  </verify>
  <acceptance_criteria>
    - `grep -E 'getComponentsByCategory\("Sources"\)' gui/src/components/ToolboxPanel.tsx` returns 1 line
    - `grep -E '(sourceComponents|visibleSources)' gui/src/components/ToolboxPanel.tsx` returns at least 2 lines
    - `grep -E '<ToolboxItem' gui/src/components/ToolboxPanel.tsx` returns at least 2 lines (Hydraulic + Thermal + Sources — was 2 before, now 3+; sanity check by counting all `<ToolboxItem`)
    - `cd gui && npx vitest run src/components/__tests__/ToolboxPanel.test.tsx` exits 0 (pre-existing + new tests green)
    - `cd gui && npx tsc --noEmit 2>&1 | grep -E 'ToolboxPanel\.tsx'` returns 0 lines
  </acceptance_criteria>
  <done>Sources category populated; WT + HFS draggable to canvas; smart-name-increment reuses Phase 62 per-kind counter.</done>
</task>

</tasks>

<verification>
After all four tasks:

1. `cd gui && npx vitest run src/components/` exits 0 — all canvas-side tests (pre-existing + new) green.
2. `cd gui && npm test` exits 0 — full suite green (regression check against 63-B and 63-C tests).
3. `cd gui && npx tsc --noEmit 2>&1 | grep -E '(BCEdge|StreamNode|CanvasPanel|ToolboxPanel)\.tsx'` returns 0 lines.

Smoke-test scope per `feedback_smoke_test_scope_match.md`: vitest covers (a) edge rendering style + chip click, (b) BCPort handle JSX + source-block label content + error red-ring, (c) `isAllowedBCConnection` allow-list + store-side n-mismatch flagging, (d) Sources toolbox draggable list. The two manual smokes are explicitly out of unit scope:

Manual smoke (Phase-63-end gate, listed in `63-VALIDATION.md` Manual-Only table):
- **D-10 whole-body drop activation:** `cd gui && npm run tauri dev` → drag from WallTemperature.T_wall_out onto a Channel body → expect dashed-outline overlay + `Connect BC` chip → release → dashed BC edge created with `targetSide = "both"`.
- **D-20 `+ New WallTemperature` end-to-end flow:** Start empty canvas → drop Channel → select → BCs tab → click "Source" mode pill → empty dropdown shows `+ New WallTemperature` button → click → expect new WT node ~120px left of Channel + auto-selected in dropdown + dashed edge auto-created.
- **D-22 visual red-ring:** Smoke confirmation that the red-ring CSS class actually paints on both endpoints (unit test verifies the class is applied; only visual confirmation is manual).
</verification>

<success_criteria>
- M6 satisfied: WallTemperature + HeatFluxSource draggable from Sources toolbox category (D-24).
- M7 satisfied: BC edges render dashed `var(--muted-foreground)` style with click-to-cycle L+R/L/R chip (D-11, D-12).
- M8 satisfied (canvas part): BC edges discriminated from FlowPort/ThermalPort edges via `type="bcEdge"`; chip click invokes store action.
- M9 satisfied: Type-mismatch connections hard-blocked via `isAllowedBCConnection` in `isValidConnection`; allowed pairs create the edge; n-mismatch flags both endpoints with `bc-n-mismatch` tag in `errorNodeIds` (D-21, D-22).
- BCPort hollow-square handle, source-block two-line label, error red-ring on StreamNode all unit-tested (D-17, D-18, D-19).
- No regressions in `ConnectionValidation.test.tsx`, pre-existing `StreamNode.test.tsx`, `ToolboxPanel.test.tsx` tests.
</success_criteria>

<output>
After completion, create `.planning/phases/63-bcs-tab-value-source-components-in-gui/63-D-SUMMARY.md` per template, documenting:
- BCEdge file size + test count; the exact dashed style values used (confirm match D-12).
- StreamNode delta: lines added, BCPort handle JSX inserted at, source-label helper function name, drop-overlay activation logic.
- CanvasPanel delta: edgeTypes line, isValidConnection BCPort branch.
- ToolboxPanel: Sources category now lists [N] components (verify N=2).
- Manual smoke checklist (D-10, D-20, D-22 visual) — confirm performed and observed-pass via `npm run tauri dev` BEFORE marking the plan complete.
- Note: any deferred items (e.g., if `addEdge → _checkBCNMismatch` wiring needs a Phase 71 follow-up to align with the validation framework).
</output>
