# gui/ — Performance Rules

STREAM Composer is a React + Vite + zustand v5 + ReactFlow (`@xyflow/react`)
desktop app. ReactFlow replaces the `nodes` array on every drag-frame
position update — 60 Hz while the user is dragging a node. The zustand
store is the choke point: **any antipattern in store consumption multiplies
across all subscribers**, and a single misplaced subscription in an always-
mounted component re-renders that component at the drag tick rate, even
when nothing the component reads has actually changed.

This file documents the rules so the patterns don't recur. It was written
after a perf sweep that fixed four of them in one shot
(`commit perf(gui): systematic perf sweep`).

---

## Rules

### 1. Never call `useStore()` with no selector.

```tsx
// WRONG — subscribes to the entire store, re-renders on ANY mutation
const { nodes, edges, addNode } = useStore();

// RIGHT — one selector per slice
const nodes = useStore((s) => s.nodes);
const edges = useStore((s) => s.edges);
const addNode = useStore((s) => s.addNode);
```

zustand's default comparator is `Object.is`. With no selector, the
returned value is the entire state object — which changes by reference on
every `set()`. Result: re-renders on hover toggles, BC writes, autosave
metadata flips, anything.

### 2. If a slice is only read in click/keydown handlers, don't subscribe — use `useStore.getState()` at call time.

```tsx
// WRONG — subscribes just to pass into handler
const nodes = useStore((s) => s.nodes);
const edges = useStore((s) => s.edges);
async function handleExport() {
  await exportCode({ nodes, edges });
}

// RIGHT — read live state at click time
async function handleExport() {
  const s = useStore.getState();
  await exportCode({ nodes: s.nodes, edges: s.edges });
}
```

`getState()` does NOT subscribe — it's a one-shot read. A tick-old
reference is fine inside an event handler because the user just triggered
the event, so they've stopped dragging.

### 3. If a render output needs a render-time flag derived from a noisy slice, subscribe to the DERIVED PRIMITIVE — not the slice.

`BottomPanel.tsx` (commit 6c08bcd) pioneered the pattern; `Toolbar.tsx` now
follows it. The Export/Copy buttons need a boolean for `disabled=` — they
do NOT need the live `nodes` array.

```tsx
// WRONG — every drag tick fires this subscription, re-renders Toolbar
const nodes = useStore((s) => s.nodes);
return <Button disabled={nodes.length === 0}>Export</Button>;

// RIGHT — fires only when the canvas crosses the empty/non-empty boundary
const hasNodes = useStore((s) => s.nodes.length > 0);
return <Button disabled={!hasNodes}>Export</Button>;
```

The selector still RUNS on every store mutation (zustand has no choice
about that), but a primitive boolean comparison short-circuits the
re-render. Selectors should be cheap — never call expensive
graph-walking functions in selector bodies (see Rule 6).

### 4. If you need just one entry from a Record/array, subscribe to that entry — not the whole container.

```tsx
// WRONG — re-renders SidebarPanel every drag tick (whole array swapped)
const nodes = useStore((s) => s.nodes);
const node = nodes.find((n) => n.id === selectedNodeId);

// RIGHT — subscribe only to the selected node
const selectedNode = useStore((s) =>
  selectedNodeId != null
    ? s.nodes.find((n) => n.id === selectedNodeId)
    : undefined,
);
```

Caveat: this works because `@xyflow/react`'s `applyNodeChanges` preserves
the `data` reference across position-only updates. If you only read `data`
inside the component, the subscription is stable while dragging even the
selected node — re-render fires only on rename / param-edit / etc.

### 5. For per-id membership tests, use a primitive-boolean selector.

```tsx
// RIGHT — per-id boolean, exactly one StreamNode re-renders on Set toggle
const isCodeHovered = useStore(
  useCallback((s) => s.hoveredSourceIds.has(id), [id]),
);
```

This pattern is used in `StreamNode.tsx` for `hoveredSourceIds`,
`pinnedSourceIds`, `errorNodeIds`. Zustand sees the boolean flip for `id =
"n1"` only and skips the other N-1 subscribers — re-render fanout is O(1),
not O(N).

### 6. Never call expensive functions inside a selector body.

```tsx
// WRONG — runs on every store mutation, walks the whole graph each time
const sides = useStore((s) =>
  resolveFlowPortAssignment(s.nodes, s.edges, id, getComponent),
);

// BETTER — compute once per nodes/edges change, store in a stable Map,
// then read by id via primitive selectors
const portAssignments = useMemo(
  () => computeAllPortAssignments(nodes, edges, getComponent),
  [nodes, edges],
);
// pass portAssignments down; have leaves read from it via getById helpers
```

Selectors must be cheap (microseconds) — they run on every `set()`. If a
selector calls a function that walks `s.nodes` and `s.edges`, the cost per
mutation is O(N+M); with K subscribers in the tree, total is O(K × (N+M))
per mutation — and a hover-toggle is a mutation. See **Known Followup
Work** below for the StreamNode case that currently violates this rule.

### 7. Don't return fresh objects/arrays from selectors. Use `useShallow` or split.

```tsx
// WRONG — returns a fresh object every store update, re-renders always
const {a, b} = useStore((s) => ({a: s.a, b: s.b}));

// RIGHT — use `useShallow` from zustand/react/shallow when you really do
// want object-shape return
import { useShallow } from "zustand/react/shallow";
const {a, b} = useStore(useShallow((s) => ({a: s.a, b: s.b})));

// SIMPLER (preferred for ≤3 fields) — split into individual subscriptions
const a = useStore((s) => s.a);
const b = useStore((s) => s.b);
```

`useShallow` is already a transitive dependency of zustand v5 — no new
install needed.

### 8. Memoize leaf components in tight loops; pass stable handler refs.

Per-node, per-row, per-token components benefit hugely from `React.memo`
+ a content-equality comparator + `useCallback`-stable handlers (passed
down as props). The classic example is `CodeSubBlockView` in
`CodePreview.tsx` — without memo, every drag tick re-creates hundreds of
token `<span>`s and React reconciles the whole tree.

```tsx
const Row = memo(function Row(props: RowProps) { /* ... */ }, (prev, next) => {
  // content equality — `lines` ref is fresh each render, compare by value
  if (prev.id !== next.id) return false;
  if (prev.lines.length !== next.lines.length) return false;
  for (let i = 0; i < prev.lines.length; i++)
    if (prev.lines[i] !== next.lines[i]) return false;
  return true;
});
```

### 9. CSS performance footguns

- Avoid `box-shadow` with blur on children of the ReactFlow viewport
  (transformed parent → layer repaint on every pan/zoom).
- Avoid animated `opacity` transitions on heavy subtrees.
- Avoid `filter: blur(...)` near the canvas.
- Don't `will-change: transform` on every node — that defeats the
  composite-layer budget. Reserve it for genuinely dragged elements.

If you can replace a glow effect with a flat ring/border, do it. The
`stream-node--code-hover` / `stream-node--code-pinned` rings landed
exactly because animated shadows were a measurable canvas-pan stutter
source (see Phase 66).

---

## Subscription decision tree

Faced with a new `useStore(...)` call, pick the matching row:

| Condition                                                         | What to do                                                              |
| ----------------------------------------------------------------- | ----------------------------------------------------------------------- |
| You need the value in `return (...)` rendering                    | Subscribe with a selector that returns a **primitive** (string/number/bool) if possible |
| You need an object from a Record/array, keyed by some local id    | Subscribe to that one entry — `useStore((s) => s.records[id])`         |
| You need a derived flag, computed from a noisy slice              | Compute it inside the selector — return the derived value, not the slice |
| You need the value only inside a click/keydown handler            | **Drop the subscription.** Read via `useStore.getState()` at call time  |
| You need multiple fields together                                 | Split into separate selectors (≤3 fields), or `useShallow` (>3 fields)  |
| You need to call an expensive graph-walking function              | Lift to App-level `useMemo`, store the result in a stable Map, expose per-id primitive lookups (see Rule 6) |

---

## Known Followup Work

These are real perf issues identified during the sweep but NOT fixed because
they touch subtle behavior the perf sweep is scoped not to break. They
should be planned as standalone tasks.

### KFW-1 — StreamNode per-port `resolveFlowPortAssignment` / `resolveThermalPairSides` selectors are O(N²)

- **Files:**
  `gui/src/components/StreamNode.tsx:187-195` (`FlowPortHandle`,
  `resolveFlowPortAssignment`),
  `gui/src/components/StreamNode.tsx:261-275` (`ThermalPortHandle`,
  `resolveThermalPairSides`).
- **Cost:** Each FlowPortHandle subscribes with a selector that calls
  `resolveFlowPortAssignment(s.nodes, s.edges, ...)` — a function walking
  all nodes and edges. Each ThermalPortHandle does the same with
  `resolveThermalPairSides`. With N nodes × ~2 flow ports per node, the
  cost per store mutation is O(N × (N+M)) — quadratic. Even a
  hover-over-sub-block in the code panel triggers this (it writes to
  `hoveredSourceIds`, fires every selector).
- **Why not fixed:** Phase 64 autoflip is subtle — suffix-locked pair
  invariants, repeated `updateNodeInternals` calls, side-resolution ties.
  A safe refactor requires understanding the full autoflip contract.
- **Suggested approach (Phase 67+):**
  1. At App or CanvasPanel level, compute the full port-assignment map
     once per nodes/edges change inside a `useMemo`:
     ```tsx
     const portAssignments = useMemo(
       () => computeAllPortAssignments(nodes, edges, getComponent),
       [nodes, edges],
     );
     ```
  2. Push the resulting `Map<string, Side>` (keyed by
     `${nodeId}:${portName}`) into a dedicated zustand slice OR pass it via
     a React context.
  3. Inside `FlowPortHandle` / `ThermalPortHandle`, subscribe with a
     primitive-string selector that reads the per-port side from the Map:
     ```tsx
     const resolvedSide = useStore(
       useCallback((s) => s.portAssignments.get(`${nodeId}:${portName}`) ?? defaultSide, [nodeId, portName]),
     );
     ```
  4. The per-port selector now returns a primitive string — zustand
     short-circuits re-renders unless the side actually flipped. Total
     cost per mutation becomes O(N+M) once + O(1) per subscriber.

### KFW-2 — ResourceRow.tsx subscribes to whole `nodes` array for per-resource usage tracking

- **File:** `gui/src/components/resources/ResourceRow.tsx:93`
- **Cost:** When the Resources tab is active, each row subscribes to the
  full `nodes` array and runs `nodes.filter(...)` in a `useMemo` keyed on
  `[nodes, kind, resource.uuid]`. With M rows × N nodes, O(M × N) work
  per drag tick — but only while the Resources tab is the active tab.
- **Why not fixed:** Refactor requires a custom equality function that
  ignores position updates. ResourceRow is gated behind the Resources tab
  and is rarely the active tab during canvas editing, so this is a
  medium-priority followup, not urgent.
- **Suggested approach:** subscribe to a derived integer — the count of
  nodes referencing this resource — using a custom equality function on
  IDs only. Materialize the full `usages` list only inside the
  expand-popover, reading live via `useStore.getState().nodes` at
  open-time.

### KFW-3 — BCsTabForm.tsx still passes the whole `nodes` array to GroupBlock

- **File:** `gui/src/components/sidebar/BCsTabForm.tsx:169, 197`
- **Cost:** Properties panel cold path (only re-renders while a node is
  selected, and users typically aren't dragging while editing). Low
  priority.
- **Why not fixed:** GroupBlock's prop type is
  `ReturnType<typeof useStore.getState>["nodes"]` — wider than I want to
  refactor in a perf-only sweep.
- **Suggested approach:** narrow GroupBlock's prop to the shape it
  actually reads (`{id, instanceName, componentId}` per-node tuple), then
  derive that fingerprint inside BCsTabForm via a `useShallow`-style
  selector with structural equality. Position updates would no longer
  re-render.

### KFW-4 — Validation / topology functions invoked from selectors elsewhere

- **Scope:** spread across `gui/src/lib/validation.ts` consumers.
- **Cost:** unknown without instrumentation.
- **Why not fixed:** would need a full audit of every site calling
  `validate*`, `selectNodeErrors`, `topology*` etc. Out of scope.

---

## How this gets enforced

There is no automated enforcement yet. The intent is:

1. **Code review** — PRs touching components or the store should check
   against the Rules table above. The 4 fixes in the perf sweep all could
   have been caught by enforcing Rule 1 / Rule 2 / Rule 3 at PR time.
2. **Future ESLint rule (sketch, NOT implemented)** — a custom rule that
   flags:
   - `useStore(...)` calls with no arguments
   - selectors that return `s.nodes` or `s.edges` directly (not behind a
     `.length`, `.find()` projection, or other accessor)
   - selectors that include function calls to a module-level list of
     known-expensive helpers (`resolveFlowPortAssignment`,
     `resolveThermalPairSides`, `validate*`, `topology*`, `generateCode`).
3. **Future `npm run perf-check` script (sketch, NOT implemented)** —
   a grep-based diff guard that runs in CI and fails the build on PRs
   re-introducing the most dangerous patterns:
   ```bash
   # Pseudocode
   if git diff --staged | grep -E 'useStore\(\)' ; then
     echo "ERROR: useStore() with no selector — see gui/PERFORMANCE.md §1"
     exit 1
   fi
   if git diff --staged | grep -E 'useStore\(\(s\) => s\.(nodes|edges|resources)\)\s*;' ; then
     echo "WARN: full-array subscription — see gui/PERFORMANCE.md §3/§4"
   fi
   ```
   The grep is intentionally crude; a real implementation belongs in the
   ESLint rule above.

Neither is implemented in this sweep — they're sketched here so the next
person picking up perf work has a starting point.
