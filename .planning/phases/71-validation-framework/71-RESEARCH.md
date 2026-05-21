# Phase 71: Validation Framework — Research

**Researched:** 2026-05-21
**Domain:** TypeScript/React — pluggable validator registry, unified validation UX, store refactor
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Panel + indicator surface**
- D-01: Validation panel = new tab in BottomPanel.tsx alongside Code tab.
- D-02: Status indicator = new dedicated statusbar strip (~22-24px) anchored UNDER BottomPanel. Always visible, not in CustomTitleBar.
- D-03: Statusbar chip pulses on error count 0→N. BottomPanel does NOT auto-open except via the export gate (D-15).
- D-04: Validation tab always visible. Empty state shows "No issues" (engineering voice). No badge when count = 0.
- D-05: Click statusbar chip → open BottomPanel + switch to Validation tab + pre-filter by severity. Click result entry → canvas pans + property panel opens for single field target. Right-click node → "Show errors for this component" navigates to panel.

**Validator registry API & file layout**
- D-06: `Validator` interface: `{ id, severity, description, scope, run(snapshot) }`. `ValidationSnapshot` = `{ nodes, edges, anchors, bcMode, resources, getComponentDef }`. Rule files MUST NOT import the store.
- D-07: Explicit registration array in `gui/src/lib/validation/index.ts`. No `import.meta.glob`.
- D-08: One file per rule under `gui/src/lib/validation/rules/<name>.ts`; co-located test at `gui/src/lib/validation/rules/__tests__/<name>.test.ts`.
- D-09: Run-all, debounced ~150ms on any mutation to `nodes`, `edges`, `anchors`, `bcMode`, `resources`. Single zustand `subscribe` listener. Per-rule caching is deferred.
- D-10: Runner in `gui/src/lib/validation/runner.ts`, decoupled from store. Store imports it and wires the subscription.

**`ValidationResult` target schema**
- D-11: `ValidationResult` = `{ id, validatorId, severity, description, targets[], fixAction? }`. Target kinds: `node`, `field`, `edge`, `port`.
- D-12: `fieldPath` is a dot-notation string. Property panel adds `data-field-path` HTML attribute ONCE in the field-render helper (not per-field). Resolution in one place; rules don't know about DOM.
- D-13: Array-shaped fields use whole-array target (`fieldPath = 'T_wall_left'`). Description carries offending indices.
- D-14: Edge-level rules emit edge + both endpoint targets.

**Rule scope + migration**
- D-15: All 8 rules from §3.9 ship in Phase 71 plus VALD-02 / VALD-03 lifts. Loop-closure + gravity-sum need `gui/src/lib/validation/loopTraversal.ts` (pure, tested).
- D-16: `validateTopology()` is folded into the registry. `gui/src/lib/validation.ts` is DELETED. Field helpers move to `gui/src/lib/validation/fields.ts`.
- D-17: `ValidationDialog.tsx` is DELETED. Export gate: synchronous `runValidators(snapshot)` → if any error → short toast + auto-open Validation tab + abort emit. Export button disabled (with tooltip) when error count > 0.
- D-18: `errorNodeIds: Set<string>` becomes a memoized selector derived from `validationResults`. `StreamNode.tsx` unchanged at contract level.
- D-19: Phase 63 connection-time hard-blocks reroute through the `portType` validator. `onConnect` consults the validator one-shot (not via debounced runner).
- D-20: Phase 63's BCs-tab n-mismatch red-text hint is superseded by `nMatch` validator. Ad-hoc check removed.

### Claude's Discretion
- Severity icon set + chip glyphs: planner picks v1 icons (lucide-react available).
- Sort order in panel: severity (error → warning → info) then validatorId.
- Statusbar height (22-24px), font size, hover state: planner picks reasonable values.
- Toast library / mount point: use whatever is already in the project; if nothing, add `sonner`.
- `data-field-path` injection site: planner finds smallest common ancestor in field-render helper.
- Empty-state copy: planner picks within engineering-voice constraint.
- Pre-export disabled-button tooltip wording: planner picks.

### Deferred Ideas (OUT OF SCOPE)
- Per-rule cache invalidation / incremental re-run.
- Per-rule enable/disable settings UI.
- Group-by-component panel toggle.
- Per-cell BC-vector targeting.
- "Fix all" batch remediation.
- Reverse-direction lint.
- Drag-from-panel "navigate to" affordance.
- Per-rule severity override.
- Validation history / time-travel.
- Cross-rule deduplication.
- Any new rules beyond the §3.9 list (10 validators total).
</user_constraints>

---

## Summary

Phase 71 is a pure TypeScript/React refactor inside the existing `gui/` Tauri app. No new external dependencies are required (zero package installs). The work is a four-part transformation:

1. **New `gui/src/lib/validation/` directory** — a registry + runner + per-rule files that replace `gui/src/lib/validation.ts` (deleted) and `gui/src/components/ValidationDialog.tsx` (deleted). The existing `validateTopology()` pure-function contract already mirrors the shape the new `Validator.run(snapshot)` contract needs; VALD-01/02/03 are exact folds.

2. **Store refactor** — `validationResult: TopologyResult | null` + `errorNodeIds` (ad-hoc mutated) + `validateAndGate()` are replaced by `validationResults: ValidationResult[]` (single slice) + a single debounced `useStore.subscribe` wiring + a memoized selector `errorNodeIds`. The `subscribeWithSelector` middleware is already installed in the store.

3. **New UI surfaces** — Validation tab in BottomPanel (one extra `TabsTrigger` + `TabsContent`), new statusbar strip mounted in App.tsx between BottomPanel and the window bottom edge.

4. **Export gate and onConnect reroute** — `exportCode.ts` swaps `validateAndGate()` for a synchronous `runValidators(snapshot)` call with D-17 toast UX. `isValidConnection` in CanvasPanel reroutes port-type hard-block through the `portType` validator rule.

No toast library is currently in the project. `sonner` must be added. There is no existing graph traversal utility — `loopTraversal.ts` must be written from scratch. The `data-field-path` injection point is the `renderField` function in `ParameterForm.tsx` (wrapping each rendered field element). The statusbar strip is new chrome that mounts directly in App.tsx at line 579, below `<BottomPanel />`, inside the existing `flex flex-col h-screen w-screen overflow-hidden` root div.

**Primary recommendation:** Build wave-by-wave: (a) types + runner + registry skeleton, (b) all 10 rule files in parallel, (c) store refactor + subscription wiring, (d) UI surfaces (Validation tab, statusbar), (e) export gate + onConnect reroute + deletions, (f) tests. Waves (a), (b), and parts of (f) are safe to parallelize.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Rule logic (physical/structural checks) | `gui/src/lib/validation/rules/` | — | Pure functions; no store/React; snapshot-in, results-out |
| Result aggregation + debounced re-run | `gui/src/store/useStore.ts` (subscribe wiring) | `gui/src/lib/validation/runner.ts` | Store owns the state slice; runner is a pure function the store calls |
| Canvas red-ring markers | `gui/src/components/StreamNode.tsx` | — | Already subscribed to `errorNodeIds: Set<string>`; shape unchanged |
| Validation panel UI | `gui/src/components/BottomPanel.tsx` | — | Existing Tabs shell; new tab added here |
| Statusbar strip | `gui/src/App.tsx` | new `ValidationStatusBar.tsx` | Mounted below BottomPanel in the root flex column |
| Field red-highlight bridge | `gui/src/components/sidebar/ParameterForm.tsx` | — | `data-field-path` injected once in `renderField` wrapper |
| Export gate | `gui/src/lib/exportCode.ts` | — | Swaps `validateAndGate()` for synchronous runner call |
| Connection-time hard-block | `gui/src/components/CanvasPanel.tsx` (isValidConnection) | `portType` rule | onConnect consults portType validator one-shot, not debounced runner |

---

## Standard Stack

### Core (all already in project)
| Library | Version | Purpose |
|---------|---------|---------|
| zustand | ^5.0.12 | Store + `subscribeWithSelector` middleware (already installed) |
| lucide-react | ^1.7.0 | Severity icons for panel entries + statusbar chips |
| @xyflow/react | ^12.10.2 | `Node`, `Edge` types consumed by `ValidationSnapshot` |
| vitest | ^4.1.2 | Per-rule unit tests |
| shadcn Tabs | (local copy in `gui/src/components/ui/tabs.tsx`) | Validation tab in BottomPanel |

[VERIFIED: project package.json] — all above confirmed present.

### New Dependency: `sonner`
**No toast library exists in the project.** The PresetRow.tsx comment (line 144) explicitly defers toast to "Phase 72 design system." The UI component directory (`gui/src/components/ui/`) has no `toast.tsx` or `sonner.tsx`. Phase 71 must add `sonner`.

[ASSUMED] — `sonner` is the shadcn-ecosystem toast library (confirmed on npmjs.com). The CONTEXT.md (Claude's Discretion section) names it as the candidate.

**Package legitimacy check (slopcheck unavailable — fallback):**
- `sonner` on npm: well-known shadcn/radix-ecosystem package maintained by Emil Kowalski. [ASSUMED — slopcheck not run; verified via known project ecosystem]

**Installation:**
```bash
cd gui && npm install sonner
```

Add `<Toaster />` mount to `App.tsx` inside `<TooltipProvider>`.

---

## Package Legitimacy Audit

| Package | Registry | slopcheck | Disposition |
|---------|----------|-----------|-------------|
| sonner | npm | [ASSUMED — not run] | Approved; well-known shadcn toast package; planner should add `checkpoint:human-verify` before install as a precaution per protocol |

*slopcheck was unavailable at research time. Treat `sonner` as `[ASSUMED]`; planner gates install behind a `checkpoint:human-verify` task.*

**Packages removed due to [SLOP]:** none
**Packages flagged [SUS]:** none confirmed, but `sonner` is tagged [ASSUMED] per protocol.

---

## Architecture Patterns

### System Architecture Diagram

```
Store mutation (nodes/edges/anchors/bcMode/resources)
        │
        ▼ useStore.subscribe (subscribeWithSelector, ~150ms debounce)
        │
        ▼ runner.ts: runValidators(snapshot)
        │    ├─ zNMatch.run(snapshot)       → ValidationResult[]
        │    ├─ lengthMatch.run(snapshot)   → ValidationResult[]
        │    ├─ nMatch.run(snapshot)        → ValidationResult[]
        │    ├─ portType.run(snapshot)      → ValidationResult[]
        │    ├─ requiredConnections.run()   → ValidationResult[]
        │    ├─ danglingFlowPort.run()      → ValidationResult[]
        │    ├─ loopClosure.run()           → ValidationResult[] (uses loopTraversal.ts)
        │    ├─ gravitySumPerLoop.run()     → ValidationResult[] (uses loopTraversal.ts)
        │    ├─ geometryConsistency.run()   → ValidationResult[]
        │    ├─ pressureBoundaryRequired()  → ValidationResult[]  ← VALD-02
        │    └─ drivingElementRequired()    → ValidationResult[]  ← VALD-03
        │
        ▼ store.set({ validationResults: [...] })
        │
        ├─▶ errorNodeIds selector (useMemo) → StreamNode.tsx red-ring (UNCHANGED CONTRACT)
        ├─▶ ValidationStatusBar.tsx → error/warning/info counts
        └─▶ BottomPanel Validation tab → full result list

onConnect (isValidConnection in CanvasPanel.tsx)
        │
        ▼ portType.run({ snapshot for proposed edge only }) — one-shot, synchronous
        │
        ├─ severity='error' → return false (hard block, existing behavior preserved)
        └─ otherwise → return true

exportCode.ts (Export button / Ctrl+S)
        │
        ▼ runValidators(snapshot) — synchronous, full run
        │
        ├─ any severity='error' → toast("Export blocked: N errors. See Validation panel.")
        │                       → set bottomPanelOpen=true, activeBottomTab='validation'
        │                       → return false (abort)
        └─ no errors → open save dialog (existing flow)
```

### Recommended Project Structure

```
gui/src/lib/validation/
  index.ts              # Validator[] export array (explicit registration)
  runner.ts             # runValidators(snapshot) → ValidationResult[]
  fields.ts             # validateInt, validateReal, validatePositiveReal, validateJuliaIdentifier (moved from validation.ts)
  snapshot.ts           # ValidationSnapshot type definition
  types.ts              # Validator, ValidationResult, Target, FixAction, Severity types
  loopTraversal.ts      # findHydraulicLoops(nodes, edges, getComponentDef) → loop arrays
  rules/
    zNMatch.ts
    lengthMatch.ts
    nMatch.ts
    portType.ts
    requiredConnections.ts
    danglingFlowPort.ts
    loopClosure.ts
    gravitySumPerLoop.ts
    geometryConsistency.ts
    pressureBoundaryRequired.ts
    drivingElementRequired.ts
    __tests__/
      zNMatch.test.ts
      lengthMatch.test.ts
      nMatch.test.ts
      portType.test.ts
      requiredConnections.test.ts
      danglingFlowPort.test.ts
      loopClosure.test.ts
      gravitySumPerLoop.test.ts
      geometryConsistency.test.ts
      pressureBoundaryRequired.test.ts
      drivingElementRequired.test.ts
      loopTraversal.test.ts

gui/src/components/
  ValidationStatusBar.tsx   # NEW: the ~22-24px statusbar strip
  (BottomPanel.tsx)         # MODIFY: add Validation tab
  (ValidationDialog.tsx)    # DELETE
  (StreamNode.tsx)          # UNCHANGED at contract level

gui/src/store/
  (useStore.ts)             # MODIFY: validationResults slice, subscribe wiring, retire validateAndGate

gui/src/lib/
  (validation.ts)           # DELETE — replaced by validation/ directory
  (exportCode.ts)           # MODIFY: swap validateAndGate for runValidators + D-17 UX

gui/src/components/sidebar/
  (ParameterForm.tsx)       # MODIFY: inject data-field-path in renderField wrapper
  (BCsTabForm.tsx)          # MODIFY: remove Phase 63 ad-hoc red-text hint for n-mismatch
```

### Pattern 1: Validator Interface (D-06)
**What:** Every rule implements the same interface — pure function of snapshot, returns result array.
**Source:** `71-CONTEXT.md` D-06 [CITED]

```typescript
// gui/src/lib/validation/types.ts
export interface Validator {
  id: string;
  severity: 'error' | 'warning' | 'info';
  description: string;
  scope: ('nodes'|'edges'|'anchors'|'bcMode'|'resources')[];
  run(snapshot: ValidationSnapshot): ValidationResult[];
}

export interface ValidationResult {
  id: string;
  validatorId: string;
  severity: 'error' | 'warning' | 'info';
  description: string;
  targets: Target[];
  fixAction?: FixAction;
}

export type Target =
  | { kind: 'node';  nodeId: string }
  | { kind: 'field'; nodeId: string; fieldPath: string }
  | { kind: 'edge';  edgeId: string }
  | { kind: 'port';  nodeId: string; portName: string };

export type FixAction =
  | { kind: 'lossless-sync'; label: string; apply: () => void }
  | { kind: 'value-transfer-picker'; optionA: { label: string; apply: () => void }; optionB: { label: string; apply: () => void } }
  | { kind: 'navigation-only'; label: string; nodeId: string };
```

### Pattern 2: Debounced Store Subscription (D-09)
**What:** Single `useStore.subscribe` call with debounce, wired at store initialization time.
**Source:** existing `initAutoRecover()` pattern in `useStore.ts:3280-3286` [VERIFIED: codebase]

The canonical pattern from autoRecover wiring:
```typescript
// Inside useStore initialization or a boot-time call in App.tsx
let debounceTimer: ReturnType<typeof setTimeout> | null = null;

const unsubscribeValidation = useStore.subscribe(
  (state) => ({
    nodes: state.nodes,
    edges: state.edges,
    anchors: state.anchors,
    bcMode: state.bcMode,
    resources: state.resources,
  }),
  (_slice) => {
    if (debounceTimer) clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => {
      const s = useStore.getState();
      const snapshot = buildSnapshot(s);
      const results = runValidators(snapshot);
      useStore.setState({ validationResults: results });
    }, 150);
  },
  {
    equalityFn: (a, b) =>
      a.nodes === b.nodes &&
      a.edges === b.edges &&
      a.anchors === b.anchors &&
      a.bcMode === b.bcMode &&
      a.resources === b.resources,
  },
);
```

**Note on wiring site:** `useStore.subscribe` is available on the exported store object at module scope. The existing `initAutoRecover()` function (a top-level async function exported from `useStore.ts`, called in `App.tsx:initAutoRecover()`) establishes the pattern. The validation subscription should be wired in a parallel top-level `initValidation()` function, also exported from `useStore.ts` and called once in `App.tsx` on mount — keeping the subscription lifecycle co-located with the store module.

### Pattern 3: errorNodeIds Derived Selector (D-18)
**What:** `errorNodeIds` shifts from a stored `Set<string>` (mutated ad-hoc) to a React `useMemo` derivation from `validationResults`. `StreamNode.tsx` receives the same `Set<string>` shape — zero change to the consumer.
**Source:** CONTEXT.md D-18 [CITED]

```typescript
// In a hook, e.g. useErrorNodeIds.ts, or inline in StreamNode.tsx's parent
const validationResults = useStore((s) => s.validationResults);
const errorNodeIds = useMemo(
  () => new Set(
    validationResults
      .filter(r => r.severity === 'error')
      .flatMap(r => r.targets)
      .filter((t): t is { kind: 'node' | 'port'; nodeId: string } =>
        t.kind === 'node' || t.kind === 'port'
      )
      .map(t => t.nodeId)
  ),
  [validationResults]
);
```

`StreamNode.tsx` currently subscribes via:
```typescript
const hasError = useStore(
  useCallback((s: { errorNodeIds: Set<string> }) => s.errorNodeIds.has(id), [id])
);
```

If `errorNodeIds` is removed from the store slice (preferred), `StreamNode.tsx` must switch to subscribing to `validationResults` and deriving the boolean inline — or the `errorNodeIds` key is kept in the store but populated by the subscription rather than ad-hoc mutations. **Planner decision:** keeping `errorNodeIds` in the store (populated by the runner subscription) avoids touching `StreamNode.tsx`. This is the simpler path.

### Pattern 4: onConnect Hard-Block Reroute (D-19)
**What:** `isValidConnection` in `CanvasPanel.tsx` currently calls `getPortType()` directly. D-19 routes through `portType` validator for a one-shot synchronous check.
**Source:** `CanvasPanel.tsx:263-288` [VERIFIED: codebase]

Current `isValidConnection` (lines 263-288):
```typescript
const isValidConnection = useCallback((connection: Edge | Connection) => {
  // ...null checks...
  const sourceType = getPortType(connection.source, connection.sourceHandle);
  const targetType = getPortType(connection.target, connection.targetHandle);
  if (sourceType && targetType && sourceType !== targetType) return false;
  if (sourceType === "BCPort") {
    // ...isAllowedBCConnection check...
  }
  return true;
}, []);
```

After D-19 reroute, the port-type mismatch branch is replaced by a call to `portType.run(syntheticSnapshot)` where `syntheticSnapshot` contains only the two nodes and the proposed edge. The `isAllowedBCConnection` path is subsumed into the `portType` validator's `run` logic.

### Pattern 5: `data-field-path` Injection in ParameterForm (D-12)
**What:** `renderField` in `ParameterForm.tsx` wraps each returned element with the `data-field-path` attribute. The `param.name` is the fieldPath for flat params; nested paths (`geom.L`) require the `fieldPath` to match the convention used by rules.
**Source:** `ParameterForm.tsx:277-383` [VERIFIED: codebase]

Injection site is the `renderField` function return, wrapping with a `<div data-field-path={param.name}>`:
```typescript
function renderField(param: Parameter) {
  const inner = (() => {
    // ... existing switch ...
  })();
  if (!inner) return null;
  return (
    <div key={param.name} data-field-path={param.name}>
      {inner}
    </div>
  );
}
```

Note: This wrapping div must not break existing layouts. Since each field already renders inside a `flex flex-col gap-[8px]` container, a plain wrapper div is transparent to layout.

**BCs-tab fields** (`BCsTabForm.tsx`) also need `data-field-path`. The injection site there mirrors this pattern — planner must identify the per-field render helper in BCsTabForm.

### Pattern 6: loopTraversal.ts (D-15)
**What:** A pure graph utility that finds closed hydraulic loops in the edge graph.
**Source:** No existing equivalent [VERIFIED: codebase — confirmed no graph/* files]

The hydraulic graph is a directed graph over `node.id` nodes connected by `FlowPort` edges (`edge.sourceHandle === 'port_out'`, `edge.targetHandle === 'port_in'`). Loop closure check is a cycle-detection pass (DFS or BFS from each node, returning cycles). `gravitySumPerLoop` uses the same loop sets, so the helper must return the full loop node lists for gravity sum accumulation.

```typescript
// gui/src/lib/validation/loopTraversal.ts
export interface HydraulicLoop {
  nodeIds: string[];   // ordered — first === last would be implicit; all unique
  edgeIds: string[];
}

export function findHydraulicLoops(
  nodes: Node[],
  edges: Edge[],
  getComponentDef: (id: string) => ComponentDefinition | undefined,
): HydraulicLoop[]
```

Only `FlowPort` edges participate (filtered on `edge.data.portType === 'FlowPort'` or by checking source/target handles against the component registry). The function is pure and tested standalone.

### Anti-Patterns to Avoid
- **Store import in rule files.** Rules are pure functions; importing `useStore` would couple them to React's rendering lifecycle and break testability. [CITED: D-06]
- **Mutating `errorNodeIds` ad-hoc from multiple call sites.** The Phase 63 pattern at `useStore.ts:1339-1361` (updating `errorNodeIds` during `addEdge`) must be removed; `errorNodeIds` must be derived from `validationResults` only. Leaving ad-hoc mutations in place after the refactor would produce duplicate or contradicting ring states.
- **Running the full validator suite synchronously inside `isValidConnection`.** `isValidConnection` is called on every drag-hover event — running the full suite (including loop traversal) would cause perceptible lag. D-19 specifies that `onConnect` consults the `portType` validator only, one-shot, not the debounced full runner.
- **Introducing a new `activeBottomTab` zustand slice.** The BottomPanel already has a local `defaultValue` on its `<Tabs>` component. The auto-open path from the export gate writes `bottomPanelOpen = true` via store action; switching to the Validation tab requires either lifting the active tab to the store or dispatching a custom event (e.g., `stream:open-validation-tab`). The planner should decide: store slice (cleaner, discoverable) vs custom event (avoids one new store key). Recommendation: add `activeBottomTab: 'code' | 'validation'` to the store — same pattern as `activeLeftTab`.
- **`ValidationDialog.tsx` deprecation instead of deletion.** D-17 is explicit: delete, not deprecate. If the file is kept around, the old modal can still fire. [CITED: D-17; memory `feedback_no_back_compat_during_heavy_dev.md`]

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Debounce implementation | Custom debounce function | `setTimeout` / `clearTimeout` inline (2 lines) | The existing autoRecover pattern uses this; no library needed for a single subscriber |
| Toast notifications | Custom toast component | `sonner` | shadcn-ecosystem; already planned; avoids reinventing positioning, animation, and stacking |
| Cycle detection | Custom graph algorithm from scratch | Standard DFS with visited + recursion stack | Well-understood; loopTraversal.ts is ~50 lines |
| Tab switching | Custom panel system | Existing shadcn `Tabs` in `BottomPanel.tsx` | The tabs shell is already there; just add a second `TabsTrigger` |

---

## Key Research Findings

### Finding 1: No toast library exists — sonner must be added

The project has no `sonner`, `react-hot-toast`, or shadcn `toast` component. The `gui/src/components/ui/` directory confirms this: no `toast.tsx`, no `sonner.tsx`. A `PresetRow.tsx` comment explicitly defers toast to "Phase 72 design system." D-17's export-gate toast requires adding `sonner` in this phase.

**Action:** `npm install sonner` + mount `<Toaster />` in `App.tsx` + configure position (bottom-right or bottom-left for engineering-tool conventions).

### Finding 2: No graph traversal utilities exist

`gui/src/lib/` has no `graph*`, `topology*`, `traverse*`, or `loop*` files. The `loopClosure` and `gravitySumPerLoop` validators both require finding closed hydraulic loops. `loopTraversal.ts` must be written from scratch. This is the only new non-trivial algorithm in the phase.

**Scope:** The hydraulic graph has only `FlowPort` edges. Node count in realistic STREAM models is ~5-30. DFS cycle detection is straightforward and sub-millisecond at this scale. No optimization needed.

### Finding 3: `selectNodeErrors` and `topologyHints` selectors have partial overlap with the new registry

`gui/src/lib/selectors/nodeErrors.ts` — the Phase 63.1 `selectNodeErrors` function implements the n-mismatch check (same logic as the new `nMatch` validator). Under D-20, this selector is retired and replaced by the registry's `nMatch` validator driving `validationResults`. **The selector must be REMOVED** from `StreamNode.tsx:334` and its consumers once the `nMatch` validator is live.

`gui/src/lib/selectors/topologyHints.ts` — the axis-collision hint used by `StreamNode.tsx` for the yellow chip. This is NOT a validation error; it is a layout hint. It does NOT map to any of the 10 validators. **Planner decision:** leave `topologyHints.ts` in place — it serves a different purpose (layout hint, not physical validation). The yellow chip in `StreamNode.tsx` for axis collision is out of scope for Phase 71.

### Finding 4: The debounce subscription wiring site

The store uses `subscribeWithSelector` middleware (confirmed: `useStore.ts:2` imports it). The `useStore.subscribe` API on the resulting store supports `(selector, listener, options)` with `equalityFn`. The existing `initAutoRecover()` pattern (exported from `useStore.ts`, called in `App.tsx:initializeRecentFiles()` effect) is the exact pattern to follow for `initValidation()`. The subscription must fire on reference equality changes to `nodes`, `edges`, `anchors`, `bcMode`, or `resources` — using object equality (same reference) per the zustand default.

**Registration site:** `App.tsx` mounts `initAutoRecover()` in a `useEffect` on mount. `initValidation()` should be called in the same effect or a sibling effect — not inside the store initializer, because the subscription writes back to the store and the initializer runs before the store is fully constructed.

### Finding 5: App.tsx layout for the statusbar strip mount point

App.tsx root structure (confirmed by reading the file):
```
<div className="flex flex-col h-screen w-screen overflow-hidden">
  <CustomTitlebar />
  <div className="flex flex-1 min-h-0">  ← main area (canvas + panels)
    ...
  </div>
  <BottomPanel />              ← line 579
</div>
```

The statusbar strip mounts **after `<BottomPanel />`** as a sibling at line 580 (currently the closing `</div>`). The `h-screen` root is `flex-col`; adding a ~22-24px tall strip below BottomPanel is structurally trivial. BottomPanel already uses explicit `height: bottomPanelHeight` from the store slice; the strip is fixed height and does not need store state.

**Important:** The strip is always visible. Even when `bottomPanelOpen = false`, BottomPanel renders a 14px stub (Phase 68 UAT: `h-3.5` closed stub). The statusbar strip sits below this stub. The total bottom chrome is stub (14px) + statusbar (22-24px) ≈ 36-38px when BottomPanel is closed. Acceptable.

### Finding 6: BottomPanel active-tab switching

BottomPanel currently has `<Tabs defaultValue="code">` (line 108) — local uncontrolled state. To allow the export gate (D-17) and statusbar chip click (D-05) to programmatically switch to the Validation tab, the tab state must become store-controlled. Add `activeBottomTab: 'code' | 'validation'` to the store (not a big slice — mirrors `activeLeftTab`). BottomPanel reads `activeBottomTab` from store and passes as `value=` (controlled Tabs). Store action `setActiveBottomTab` writes it.

### Finding 7: Phase 63 ad-hoc `errorNodeIds` mutation paths to remove

`useStore.ts:1339-1361` — inside `addEdge`: after the BCPort branch (line 1335 return), the code reads `errorNodeIds` and clears port-connected node IDs from it. This block is dead after D-18 (errorNodeIds becomes a derived selector). It must be removed entirely.

`useStore.ts:1876-1886` — `validateAndGate()` implementation: sets `errorNodeIds` + `validationResult`. The entire function is retired (D-16 / D-17).

`useStore.ts:1888-1890` — `clearValidation()`: sets both slices. Retired.

`gui/src/components/ValidationDialog.tsx` — entire file deleted.

`gui/src/App.tsx:15, 587` — `import ValidationDialog` + `<ValidationDialog />` mount removed.

`gui/src/lib/exportCode.ts:47-48` — `validateAndGate()` call replaced by `runValidators(snapshot)` + D-17 gate logic.

### Finding 8: `selectNodeErrors` subscriber in StreamNode.tsx

`StreamNode.tsx:334`:
```typescript
const hasBCError = useStore(
  useCallback(
    (s) => selectNodeErrors(s as unknown as NodeErrorsInput, id).length > 0,
    [id],
  ),
);
```

Under D-20, this subscriber is removed. The `nMatch` validator emits `ValidationResult` entries that populate `validationResults`, from which `errorNodeIds` is derived. The `hasError` subscriber at line 324 (reading `s.errorNodeIds`) then correctly covers n-mismatch errors too (since `nMatch` validator results flow through the same `errorNodeIds` derivation). The `hasAnyError` combinator at line 387 (`hasError || hasBCError`) reduces to just `hasError` once `hasBCError` is removed.

### Finding 9: Export button disabled-state pattern

Currently: `<Button disabled={!hasNodes}>` in BottomPanel (line 137-162). Phase 71 changes this to `disabled={!hasNodes || hasErrors}` where `hasErrors` is a primitive boolean derived from `validationResults.some(r => r.severity === 'error')`. The Tooltip wrapping the Export button surfaces the error count message.

### Finding 10: Test template for rule files

`gui/src/lib/validation.test.ts` is the canonical template:
- `import { describe, it, expect } from "vitest"` (no `vi` namespace imports needed for pure-function tests)
- Mock factory functions (`makeNode`, `makeEdge`) that return minimal `Node`/`Edge` objects
- Mock component definitions as a `Record<string, ComponentDefinition>`
- `describe("ruleName", () => { it("detects X", () => { ... }); })`
- Test environment: `node` (from `vitest.config.ts`) — no JSDOM needed for pure-function rule tests
- Each test passes a synthetic `ValidationSnapshot` directly to `rule.run(snapshot)` — no store, no React

---

## Common Pitfalls

### Pitfall 1: Zustand shallow equality and Set mutation
**What goes wrong:** The `validationResults` slice is an array. If the runner returns a new array with the same length and referentially equal elements, zustand's default equality check (`===` on the array reference) fires re-renders correctly. However, `errorNodeIds: Set<string>` in the store, if kept as a stored slice, must be replaced with `new Set(...)` on every write (not mutated in-place) — otherwise zustand's shallow equality sees the same Set reference and skips re-renders. The existing `clearValidation()` already demonstrates this with `new Set<string>()`.
**Prevention:** Always write `set({ errorNodeIds: new Set([...]) })`, never `errorNodeIds.add(x); set({ errorNodeIds })`.
**Warning signs:** Red rings stop appearing after the first clear.

### Pitfall 2: `isValidConnection` performance budget
**What goes wrong:** `isValidConnection` is called by ReactFlow on every drag tick while a port handle is being dragged over potential targets. Calling `runValidators(snapshot)` (which includes `loopTraversal`) inside `isValidConnection` would cause lag. The loop closure traversal is O(V+E) per loop, and with ~30 nodes it's fast, but invoking it on every hover event is unnecessary.
**Prevention:** D-19 says `onConnect` calls the `portType` validator only — not the full runner. The `portType` validator does not traverse loops; it only checks port type compatibility. Keep the `isValidConnection` path as a direct port-type check (same O(1) structure as current code).
**Warning signs:** Connection dragging becomes visibly sluggish.

### Pitfall 3: `data-field-path` wrapper div breaking layouts
**What goes wrong:** Wrapping each `renderField` return in a `<div data-field-path=...>` adds a new DOM element in the property panel's `flex flex-col gap-[8px]` container. If any `renderField` branch relies on being a direct child of that flex container for layout (e.g., using `self-stretch` or explicit `w-full`), the wrapper breaks it.
**Prevention:** Check that the wrapper div does not itself add any layout-affecting CSS class. The `div` should be an unstyled wrapper: `<div data-field-path={param.name}>` with no className. Existing children already have their own width / layout declarations.
**Warning signs:** Property panel fields look misaligned or have unexpected widths.

### Pitfall 4: `activeBottomTab` store slice vs controlled Tabs
**What goes wrong:** If BottomPanel's `<Tabs>` keeps `defaultValue="code"` (uncontrolled), the export gate can write `activeBottomTab` to the store but the Tabs component ignores it (it manages its own internal state after first render).
**Prevention:** Switch `<Tabs defaultValue="code">` to `<Tabs value={activeBottomTab} onValueChange={setActiveBottomTab}>` (controlled). Requires adding the store slice + action.
**Warning signs:** Export gate fires, sets store to 'validation', but Code tab remains active.

### Pitfall 5: `nMatch` validator vs `selectNodeErrors` coexistence
**What goes wrong:** After the `nMatch` validator is live, `selectNodeErrors` in `nodeErrors.ts` still runs on every StreamNode render (via `hasBCError` in `StreamNode.tsx:334`). If both are active simultaneously, the n-mismatch red ring fires twice — once from the new registry path (via `errorNodeIds`) and once from the legacy selector path (via `hasBCError`). This doesn't cause a visual bug (both contribute to `hasAnyError`) but it's wasted computation and a conceptual inconsistency.
**Prevention:** Remove `hasBCError` subscriber and the `selectNodeErrors` import from `StreamNode.tsx` as part of D-20 (same wave as adding `nMatch` validator). Do both in one task.

### Pitfall 6: Loop traversal on disconnected graphs
**What goes wrong:** `findHydraulicLoops` may be called on a graph where some nodes have no FlowPort edges (e.g., a thermal-only node like `HeatDiffusion`). A naive DFS starting from all nodes will traverse thermal-component nodes and find false "paths."
**Prevention:** Filter `nodes` to only hydraulic-category components (those with FlowPort entries in the registry) before building the adjacency structure. Only `FlowPort` edges participate in the loop traversal.

### Pitfall 7: FixAction closures capturing stale store state
**What goes wrong:** `FixAction.apply` closures (for lossless-sync and value-transfer-picker) are created inside `rule.run(snapshot)`. If the snapshot is stale (debounce fired 150ms ago), the `apply` closure may write a value that was already changed.
**Prevention:** For lossless-sync, the `apply` closure should call `useStore.getState().updateNodeParam(...)` at the time of invocation (not at creation). The rule creates the closure with the *recommended value* embedded; the store write happens at click time. This matches the existing pattern where button handlers call `useStore.getState()` to get fresh state.

---

## Code Examples

### Minimal Validator Rule Shape
```typescript
// Source: CONTEXT.md D-06, D-08 [CITED]
// gui/src/lib/validation/rules/pressureBoundaryRequired.ts

import type { Validator, ValidationResult } from '../types';
import type { ValidationSnapshot } from '../snapshot';

export const pressureBoundaryRequired: Validator = {
  id: 'pressure_boundary_required',
  severity: 'error',
  description: 'No pressure boundary condition',
  scope: ['anchors'],
  run(snapshot: ValidationSnapshot): ValidationResult[] {
    if (Object.keys(snapshot.anchors).length > 0) return [];
    return [{
      id: 'pressure_boundary_required::system',
      validatorId: 'pressure_boundary_required',
      severity: 'error',
      description: 'No pressure boundary condition. Set a pressure anchor on a FlowPort.',
      targets: [],    // system-level: no specific node target
    }];
  },
};
```

### Runner Shape
```typescript
// Source: CONTEXT.md D-10 [CITED]
// gui/src/lib/validation/runner.ts

import { validators } from './index';
import type { ValidationSnapshot } from './snapshot';
import type { ValidationResult } from './types';

export function runValidators(snapshot: ValidationSnapshot): ValidationResult[] {
  return validators.flatMap(v => v.run(snapshot));
}
```

### Store Subscription Wiring
```typescript
// Source: useStore.ts initAutoRecover pattern [VERIFIED: codebase]
// To be added as initValidation() exported from useStore.ts

export function initValidation(): () => void {
  let timer: ReturnType<typeof setTimeout> | null = null;

  const unsubscribe = useStore.subscribe(
    (s) => ({
      nodes: s.nodes,
      edges: s.edges,
      anchors: s.anchors,
      bcMode: s.bcMode,
      resources: s.resources,
    }),
    (_slice) => {
      if (timer) clearTimeout(timer);
      timer = setTimeout(() => {
        const s = useStore.getState();
        const snapshot = buildValidationSnapshot(s);
        const results = runValidators(snapshot);
        const errorNodeIds = new Set(
          results
            .filter(r => r.severity === 'error')
            .flatMap(r => r.targets)
            .filter(t => t.kind === 'node' || t.kind === 'port')
            .map(t => (t as { nodeId: string }).nodeId)
        );
        useStore.setState({ validationResults: results, errorNodeIds });
      }, 150);
    },
    { equalityFn: (a, b) =>
        a.nodes === b.nodes && a.edges === b.edges &&
        a.anchors === b.anchors && a.bcMode === b.bcMode &&
        a.resources === b.resources
    },
  );

  return () => { unsubscribe(); if (timer) clearTimeout(timer); };
}
```

### Export Gate Replacement
```typescript
// Source: CONTEXT.md D-17 [CITED]
// gui/src/lib/exportCode.ts — replacement for validateAndGate() call

export async function exportCode(opts: ExportCodeOptions): Promise<boolean> {
  if (opts.nodes.length === 0) return false;

  // D-17: synchronous full run (no debounce at export time)
  const s = useStore.getState();
  const snapshot = buildValidationSnapshot(s);
  const results = runValidators(snapshot);
  const errorCount = results.filter(r => r.severity === 'error').length;

  if (errorCount > 0) {
    toast.error(`Export blocked: ${errorCount} validation ${errorCount === 1 ? 'error' : 'errors'}. See Validation panel.`, {
      duration: 2000,
    });
    useStore.setState({
      validationResults: results,
      bottomPanelOpen: true,
      activeBottomTab: 'validation',
    });
    return false;
  }

  const filePath = await save({ ... });
  // ...
}
```

---

## State of the Art

| Old Approach | Current Approach | Impact |
|---|---|---|
| `validateTopology()` + modal dialog (Phase 39) | Pluggable registry + inline panel tab (Phase 71) | Removes friction; no modal interruption; always-visible status |
| `errorNodeIds: Set<string>` mutated from multiple call sites | Single derived slice from `validationResults` | Single source of truth; eliminates race conditions |
| Phase 63 `selectNodeErrors` ad-hoc per-render n-mismatch check | `nMatch` validator in registry | Eliminates dual code paths; uniform UX for all rule types |
| Phase 63 connection-time BCPort hard-block embedded in `addEdge` store action | `portType` validator consulted in `isValidConnection` | Rule definition lives in one place |

---

## Wave Decomposition for Planning

The planner should organize tasks into these natural parallel waves:

**Wave 0 — Types, runner, snapshot, fields.ts (blockers for everything else)**
- `gui/src/lib/validation/types.ts` (Validator, ValidationResult, Target, FixAction, Severity)
- `gui/src/lib/validation/snapshot.ts` (ValidationSnapshot type + buildValidationSnapshot function)
- `gui/src/lib/validation/runner.ts` (runValidators — depends on types and index.ts stub)
- `gui/src/lib/validation/index.ts` (empty array to start; rules added as they land)
- `gui/src/lib/validation/fields.ts` (move validateInt/validateReal/validatePositiveReal/validateJuliaIdentifier from validation.ts)
- `gui/src/lib/validation/loopTraversal.ts` (findHydraulicLoops — needed by two rules)

**Wave 1 — Rule files (parallelizable across rules after Wave 0)**
All 10 rule files can be written in parallel since each is a pure function with no dependency on other rules:
1. `danglingFlowPort.ts` (VALD-01 fold)
2. `pressureBoundaryRequired.ts` (VALD-02 fold)
3. `drivingElementRequired.ts` (VALD-03 fold)
4. `portType.ts` (port-type mismatch + BC-binding type mismatch)
5. `nMatch.ts` (source n vs channel n)
6. `zNMatch.ts` (CAC.n vs HD.nz on thermal connections)
7. `lengthMatch.ts` (cac.geom.L vs plate.Lz)
8. `requiredConnections.ts` (missing required connections)
9. `loopClosure.ts` (uses loopTraversal.ts)
10. `gravitySumPerLoop.ts` (uses loopTraversal.ts)
11. `geometryConsistency.ts` (shared geometry check across thermal coupling)

**Wave 2 — Store refactor (depends on Wave 0 types; independent of Wave 1 rule files)**
- Add `validationResults: ValidationResult[]` slice to store
- Add `activeBottomTab: 'code' | 'validation'` slice
- Add `setActiveBottomTab` action
- Remove `validationResult: TopologyResult | null` slice
- Keep `errorNodeIds: Set<string>` in store (populated by subscription, not ad-hoc)
- Remove `validateAndGate()` action
- Remove `clearValidation()` action
- Remove ad-hoc `errorNodeIds` mutation from `addEdge` (lines 1339-1361)
- Add `initValidation()` export + call in App.tsx

**Wave 3 — UI surfaces (depends on Wave 0 types + Wave 2 store slices)**
- BottomPanel.tsx: add Validation tab (`TabsTrigger` + `TabsContent`) + switch to controlled Tabs
- `ValidationStatusBar.tsx`: new component, mounted in App.tsx
- `ParameterForm.tsx`: inject `data-field-path` in `renderField` wrapper
- `BCsTabForm.tsx`: inject `data-field-path` in field renderer; remove Phase 63 ad-hoc n-mismatch red-text

**Wave 4 — Integration and deletions (depends on Wave 2 + Wave 3)**
- `exportCode.ts`: replace `validateAndGate()` with `runValidators(snapshot)` + D-17 UX (install sonner before this)
- `CanvasPanel.tsx`: reroute `isValidConnection` port-type hard-block through `portType` validator
- `StreamNode.tsx`: remove `hasBCError` subscriber + `selectNodeErrors` import
- Delete `gui/src/components/ValidationDialog.tsx`
- Remove `ValidationDialog` import + mount from `App.tsx`
- Delete `gui/src/lib/validation.ts` (after `fields.ts` is confirmed live)
- Verify `NumericField.tsx` still imports from `gui/src/lib/validation/fields.ts` (path update needed)

**Wave 5 — Tests (can run in parallel with Wave 1 rule files)**
- One test file per rule under `gui/src/lib/validation/rules/__tests__/`
- `loopTraversal.test.ts`
- Update `validation.test.ts` → confirm tests now import from `validation/fields.ts` (path only)
- Smoke test: `npm run test` must pass

---

## Files to Delete vs Touch

**DELETE (no replacement, no deprecation):**
- `gui/src/lib/validation.ts` → field helpers move to `validation/fields.ts`; topology logic folds into 3 registry rules
- `gui/src/components/ValidationDialog.tsx` → modal replaced by Validation tab

**REMOVE mount / import from App.tsx:**
- `import ValidationDialog from "./components/ValidationDialog"` (line 15)
- `<ValidationDialog />` (line 587)

**REMOVE call sites:**
- `useStore.ts:validateAndGate()` implementation (lines 1876-1886)
- `useStore.ts:clearValidation()` implementation (lines 1888-1890)
- `useStore.ts:1339-1361` ad-hoc errorNodeIds mutation inside `addEdge`

**MODIFY (existing files, surgical changes):**
- `gui/src/store/useStore.ts` — add new slices, subscription wiring, remove retired code
- `gui/src/lib/exportCode.ts` — replace validateAndGate with runValidators + D-17 UX
- `gui/src/components/BottomPanel.tsx` — add Validation tab, switch to controlled Tabs
- `gui/src/App.tsx` — add statusbar strip mount, call initValidation(), mount Toaster
- `gui/src/components/CanvasPanel.tsx` — reroute isValidConnection hard-block
- `gui/src/components/StreamNode.tsx` — remove hasBCError subscriber
- `gui/src/components/sidebar/ParameterForm.tsx` — inject data-field-path in renderField
- `gui/src/components/sidebar/BCsTabForm.tsx` — inject data-field-path; remove ad-hoc n-mismatch hint
- All files that `import { validateInt, validateReal, ... } from '@/lib/validation'` → update import path to `@/lib/validation/fields`

**LEAVE UNCHANGED:**
- `gui/src/lib/selectors/topologyHints.ts` — axis-collision hint is a layout hint, not a validation rule; out of scope
- `gui/src/components/StreamNode.tsx` — red-ring rendering logic untouched (only subscriber removed)

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `sonner` is the correct shadcn-ecosystem toast package and passes slopcheck | Standard Stack | Low — well-known package; worst case use shadcn's own Toast or a 10-line custom; does not block architecture |
| A2 | `selectTopologyHints` in `topologyHints.ts` is out of scope (axis-collision hint ≠ validation error) | Finding 3 | Low — if the planner wants to migrate it into the registry, it would be a warning-severity rule; not architecturally blocking |
| A3 | `loopTraversal.ts` DFS cycle detection is sufficient for the model sizes in scope | Finding 2 | Low — STREAM models are ~5-50 nodes; performance is not a concern |
| A4 | Keeping `errorNodeIds` as a stored slice (populated by subscription) is the correct approach to avoid touching `StreamNode.tsx` | Finding 3 / Pattern 3 | Medium — if the planner prefers deriving `errorNodeIds` in a hook, `StreamNode.tsx` must be modified; both approaches are valid |

---

## Open Questions

1. **`activeBottomTab` store slice vs custom event**
   - What we know: BottomPanel currently uses uncontrolled `<Tabs defaultValue="code">`; the export gate must programmatically switch to the Validation tab.
   - What's unclear: Whether to add `activeBottomTab` to the store (cleaner, more discoverable) or use a `CustomEvent` dispatch (avoids one store key, mirrors the `stream:open-save-preset` pattern).
   - Recommendation: Store slice — the `activeLeftTab` precedent already exists, and store slice is more testable.

2. **`data-field-path` for BCsTabForm**
   - What we know: `BCsTabForm.tsx` renders per-field rows for BC input variables. The `data-field-path` attribute must be injected there too.
   - What's unclear: The exact render helper structure in BCsTabForm (not read in detail for this research).
   - Recommendation: Planner reads BCsTabForm and identifies the equivalent of `renderField` there.

3. **11 pre-existing tsc errors**
   - What we know: STATE.md notes "11 pre-existing tsc errors + 1 pre-existing vitest failure" that Phase 71 owns reconciliation for (per Phase 61 deferred items).
   - What's unclear: Whether any of these tsc errors touch files that Phase 71 modifies (which would block compilation of Phase 71 deliverables).
   - Recommendation: Planner allocates a Wave 0 or Wave 5 task to run `tsc --noEmit` and reconcile the 11 errors as a precondition gate.

---

## Environment Availability

Step 2.6 SKIPPED — this phase is a pure TypeScript/React code change inside the existing `gui/` project. The only external dependency addition is `sonner` (npm package). No external services, databases, runtimes, or CLI tools beyond `npm` are required.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| npm | Package install (sonner) | ✓ | (confirmed via package.json) | — |
| vitest | Test runner | ✓ | ^4.1.2 | — |
| lucide-react | Severity icons | ✓ | ^1.7.0 | — |
| sonner | Export-gate toast | ✗ (not installed) | — | shadcn Toast (would need to be added manually; more work) |

**Missing dependencies with no fallback:** none that block the core architecture.
**Missing dependencies with fallback:** `sonner` — fallback is shadcn's own Toast component (would require manual implementation of positioning and stacking). Recommendation: install `sonner`.

---

## Validation Architecture

`nyquist_validation: false` in `.planning/config.json` — SKIPPED per config.

---

## Security Domain

`security_enforcement` key absent from `.planning/config.json` — treated as enabled.

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V5 Input Validation | yes (field validators moved to fields.ts) | existing `validateInt`, `validateReal`, `validatePositiveReal`, `validateJuliaIdentifier` functions — no change to logic |
| V2 Authentication | no | — |
| V3 Session Management | no | — |
| V4 Access Control | no | — |
| V6 Cryptography | no | — |

No new attack surface is introduced. The validation framework is purely client-side TypeScript logic operating on in-memory model data. Validator rule files are pure functions with no network calls, no file I/O, and no DOM manipulation.

---

## Sources

### Primary (HIGH confidence)
- `71-CONTEXT.md` — locked decisions D-01 through D-20, all architectural choices [CITED]
- `gui-redesign-design-decisions.md` §3.9 — upstream contract for validation framework [CITED]
- `gui/src/store/useStore.ts` — store interface, subscription pattern, existing slices [VERIFIED: codebase]
- `gui/src/lib/validation.ts` — VALD-01/02/03 logic to fold, field helpers to move [VERIFIED: codebase]
- `gui/src/components/BottomPanel.tsx` — Tabs shell, current structure [VERIFIED: codebase]
- `gui/src/components/StreamNode.tsx` — red-ring consumer contract [VERIFIED: codebase]
- `gui/src/components/CanvasPanel.tsx` — isValidConnection hard-block code path [VERIFIED: codebase]
- `gui/src/lib/selectors/nodeErrors.ts` — Phase 63.1 n-mismatch selector (to be retired) [VERIFIED: codebase]
- `gui/src/App.tsx` — layout structure, mount points, subscription patterns [VERIFIED: codebase]
- `gui/src/components/sidebar/ParameterForm.tsx` — renderField structure for data-field-path injection [VERIFIED: codebase]
- `gui/package.json` — dependency inventory (no toast library, lucide-react present) [VERIFIED: codebase]

### Secondary (MEDIUM confidence)
- `gui/src/lib/validation.test.ts` — test template pattern [VERIFIED: codebase]
- `gui/vitest.config.ts` — test environment configuration [VERIFIED: codebase]
- `gui/src/lib/selectors/topologyHints.ts` — axis-collision hint (confirmed out of scope) [VERIFIED: codebase]

### Tertiary (LOW confidence — ASSUMED)
- `sonner` npm package identity [ASSUMED — not verified via slopcheck or official docs in this session]

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — confirmed from package.json
- Architecture: HIGH — locked decisions in CONTEXT.md + codebase cross-references
- Pitfalls: HIGH — derived from direct code reading of the specific lines that change
- `loopTraversal.ts` algorithm: MEDIUM — confirmed no existing utility; algorithm scope is small and well-understood

**Research date:** 2026-05-21
**Valid until:** 2026-06-21 (stable codebase; 30-day window appropriate)
