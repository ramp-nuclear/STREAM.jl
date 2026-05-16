# PERF-AUDIT — gui/src perf sweep

Scratch document feeding the perf-sweep commit. Findings categorized by
verdict:

- **FIX** — high-confidence safe refactor; apply
- **SKIP-risky** — real perf cost but touches subtle behavior; document only
- **SKIP-low-impact** — pattern exists but not on a hot path
- **FALSE-POSITIVE** — looked suspicious, but actually correct

Baseline before sweep: vitest 827 pass / 5 pre-existing fail / 10 todo;
tsc 12 errors.

---

## FIX items

### F1 — Toolbar.tsx subscribes to nodes/edges/anchors/resources/bcMode/bcSymmetric only to consume in click handler
- **File:** `gui/src/components/Toolbar.tsx:21-30`
- **Impact:** HIGH — Toolbar is always mounted at the top of the screen; each
  of these subscriptions fires on every ReactFlow drag tick (60 Hz). 6
  needless re-render triggers per tick.
- **Fix:** Apply the proven BottomPanel pattern (commit 6c08bcd): subscribe
  ONLY to a derived `hasNodes` boolean for the Export-button disabled state,
  read everything else via `useStore.getState()` at click time in
  `handleExport`.

### F2 — WelcomeOverlay.tsx subscribes to nodes/edges only to gate render
- **File:** `gui/src/components/WelcomeOverlay.tsx:5-6`
- **Impact:** MEDIUM-HIGH — WelcomeOverlay is rendered inside CanvasPanel,
  so it's always mounted; the gate `nodes.length > 0 || edges.length > 0`
  fires on every drag tick.
- **Fix:** Replace both subscriptions with one derived primitive boolean:
  `const empty = useStore((s) => s.nodes.length === 0 && s.edges.length === 0);`.

### F3 — CanvasPanel.tsx uses `useStore()` with no selector
- **File:** `gui/src/components/CanvasPanel.tsx:66-67`
- **Impact:** CRITICAL — `const { nodes, edges, onNodesChange, onEdgesChange,
  addNode, addEdge, selectNode } = useStore();` calling `useStore()` with
  NO selector triggers re-render on ANY state change anywhere in the store
  (hoveredSourceIds, pinnedSourceIds, bcMode, anchors, resources — every
  one of them re-renders the canvas). CanvasPanel hosts ReactFlow, so this
  is the worst possible place for a no-selector subscription.
- **Fix:** Split into individual selectors. Actions (`onNodesChange`,
  `onEdgesChange`, `addNode`, `addEdge`, `selectNode`) are stable refs from
  zustand — safe to subscribe individually. `nodes` and `edges` must be
  subscribed individually too (they're the live arrays ReactFlow needs).
  Net result: identical render output, but the canvas no longer re-renders
  when (e.g.) the code-panel hover changes.

### F4 — SidebarPanel.tsx subscribes to whole `nodes` array, but only reads selected node
- **File:** `gui/src/components/sidebar/SidebarPanel.tsx:68`
- **Impact:** MEDIUM — SidebarPanel is always mounted on the right side; on
  every drag tick, the whole `nodes` array reference changes, re-rendering
  SidebarPanel + its memoized children. The component only uses `nodes` in
  `renderBody()` to look up the selected node via `nodes.find(...)`.
- **Fix:** Subscribe to just the selected node's `data` ref. Per
  `applyNodeChanges` semantics (xyflow internal), position updates produce
  a new node object but PRESERVE the `data` reference. So a selector that
  returns `nodes.find(n => n.id === selectedNodeId)?.data` is stable across
  position-only updates. The current code reads `node.data` exclusively, so
  this is a transparent refactor.

### F5 — BCsTabForm.tsx subscribes to whole `nodes` array
- **File:** `gui/src/components/sidebar/BCsTabForm.tsx:169`
- **Impact:** MEDIUM — mounted inside SidebarPanel for components with BCs;
  re-renders on every drag tick when visible. The `nodes` array is read
  inside GroupBlock children (passed via prop).
- **Fix:** Drop the render-time subscription (it's only used as a snapshot
  for reading other-node names in the BC form's pair display). Lookups
  happen at user-interaction time inside the form — those can read live via
  `useStore.getState().nodes`. Pass a stable getter or read fresh at use.
  **Safest variant:** keep the subscription but mark with a `useShallow`-
  style stable equality on the IDs only (drop noisy position updates).
  Actually the simplest safe fix: subscribe to a serialized fingerprint of
  `nodes.map(n => [n.id, (n.data as any)?.instanceName, (n.data as any)?.componentId])` —
  what the BCs form actually reads. Position changes don't affect this
  fingerprint, so no re-renders during drag.
  **Chosen:** subscribe via custom selector that returns the array of
  shallow snapshots `[{id, instanceName, componentId}, ...]` plus a custom
  equality function. This keeps the nodes-prop API to GroupBlock the same
  shape (an array of node-like objects), just with stable references when
  positions change.
  **Reconsidered:** the GroupBlock prop is typed
  `ReturnType<typeof useStore.getState>["nodes"]` — a hard contract. Let me
  keep it simple: leave BCsTabForm alone, document as SKIP-risky (the
  contract surface is wider than I want to refactor in a perf sweep). The
  Properties panel is hidden when no node is selected, and when one IS
  selected the user is by definition not dragging — so this is at worst
  cold-path during edit, not hot-path during drag. **Demote to SKIP-low-impact.**

### F6 — App.tsx and other consumers: nothing else stood out
- Skimmed App.tsx, FileMenu.tsx, AnchorsSection.tsx, FluidEdge.tsx,
  HydraulicEdge.tsx, BCEdge.tsx, ToolboxPanel.tsx, ToolboxItem.tsx,
  ResourcesTreePanel.tsx, ResourceCreationButton.tsx, ModelOptionsPanel.tsx,
  ValidationDialog.tsx, ResourceReferencePicker.tsx, and the canvasMenus.
  All either subscribe to primitives, to action functions (stable refs),
  or are mounted infrequently / behind tab gates. No additional FIX items.

---

## SKIP-risky items (documented in PERFORMANCE.md ## Known Followup Work)

### S1 — StreamNode.tsx FlowPortHandle/ThermalPortHandle resolveFlowPortAssignment/resolveThermalPairSides selectors
- **File:** `gui/src/components/StreamNode.tsx:187` (`resolveFlowPortAssignment`),
  `gui/src/components/StreamNode.tsx:261` (`resolveThermalPairSides`)
- **Impact:** SEVERE on large graphs. Every StreamNode has 1-2 FlowPort
  subscriptions + 0-1 ThermalPort subscriptions whose selector body calls
  `resolveFlowPortAssignment(s.nodes, s.edges, ...)` or
  `resolveThermalPairSides(s.nodes, s.edges, ...)`. Each call walks all
  nodes and edges. With N nodes, the cost per store update is
  O(N × (N+M)) — quadratic in N. Even a code-panel hover (which writes
  `hoveredSourceIds`) triggers every subscriber to re-run its selector.
- **Why SKIP:** Phase 64's port autoflip logic is subtle (suffix-locked
  pair invariants, repeated `updateNodeInternals` calls, side-resolution
  ties). Refactoring this selector requires understanding the full autoflip
  contract, which is out of scope for a perf sweep.
- **Suggested fix (for Phase 67+):** compute port assignments once per
  nodes/edges change in a `useMemo` at App level (or via a subscribe-with-
  selector listener), store the result in a stable Map keyed by
  `{nodeId, portName}` → `Side`. Have each StreamNode read from the Map by
  id with a primitive-boolean per-port selector (same shape as the
  `hoveredSourceIds.has(id)` pattern). That converts the per-tick cost
  from O(N²) to O(N+M) once + O(1) lookups.

### S2 — ResourceRow.tsx subscribes to nodes for usage tracking
- **File:** `gui/src/components/resources/ResourceRow.tsx:93`
- **Impact:** MEDIUM only when Resources tab active; each row recomputes
  `usages = nodes.filter(...)` on every drag tick. With M rows × N nodes,
  this is O(M × N) per tick.
- **Why SKIP:** Fixing requires subscribing with a custom equality
  function (compare only the param values the usage filter reads, not
  positions). That's a non-trivial change to verify. ResourceRow is gated
  behind the Resources tab — most users spend most of their time on the
  Components tab, so this is rarely a hot path in practice.
- **Suggested fix:** subscribe to a derived primitive — the count of nodes
  whose `parameters[paramKey] === resource.uuid` (which is what the row
  needs for the badge). The full `usages` array is only needed in the
  expand-popover, which can read live via `useStore.getState().nodes` at
  popover-open time.

### S3 — General: validation.ts walks the graph each call, and validations may be invoked from selectors elsewhere
- **File:** spread across `gui/src/lib/validation.ts` consumers
- **Why SKIP:** Out of scope; would need a system-wide audit.

---

## SKIP-low-impact / FALSE-POSITIVE notes

- ResourceReferencePicker subscribes to both `geometries` and `powerShapes`
  — only the active one is needed. But the picker only mounts when the user
  is editing a parameter that references a resource — cold path.
- ParameterForm subscribes to `nodes` (line 93). Only used inside the
  ParameterForm body for cross-component name lookups. Properties panel
  cold path. Skip.
- StreamNode line 309/317/328/331 use per-id Set membership selectors
  returning primitive booleans — these are the CORRECT pattern, not an
  antipattern.
- BCEdge line 59 selector returns a primitive string — fine.
- HydraulicEdge has no store subscription — fine.

---

## Apply order

Top 4 items (F1-F4) all in one commit. Run vitest after each edit, full
suite at the end. No new failures permitted.
