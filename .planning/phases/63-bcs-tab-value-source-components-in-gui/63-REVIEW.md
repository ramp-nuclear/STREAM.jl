---
phase: 63-bcs-tab-value-source-components-in-gui
reviewed: 2026-05-13T00:00:00Z
depth: standard
files_reviewed: 27
files_reviewed_list:
  - gui/src/components/BCEdge.tsx
  - gui/src/components/CanvasPanel.tsx
  - gui/src/components/CodePreview.tsx
  - gui/src/components/StreamNode.tsx
  - gui/src/components/Toolbar.tsx
  - gui/src/components/ToolboxPanel.tsx
  - gui/src/components/__tests__/BCEdge.test.tsx
  - gui/src/components/__tests__/CanvasPanel.bc.test.tsx
  - gui/src/components/__tests__/StreamNode.test.tsx
  - gui/src/components/__tests__/ToolboxPanel.test.tsx
  - gui/src/components/sidebar/BCModePicker.tsx
  - gui/src/components/sidebar/BCsTabForm.tsx
  - gui/src/components/sidebar/ModeToggle.tsx
  - gui/src/components/sidebar/SegmentedButtonGroup.tsx
  - gui/src/components/sidebar/SidebarPanel.tsx
  - gui/src/components/sidebar/__tests__/BCModePicker.test.tsx
  - gui/src/components/sidebar/__tests__/BCsTabForm.test.tsx
  - gui/src/components/sidebar/__tests__/SidebarPanel.test.tsx
  - gui/src/lib/__tests__/codeGenerator.bc.test.ts
  - gui/src/lib/bcMode.ts
  - gui/src/lib/codeGenerator.ts
  - gui/src/store/__tests__/useStore.bc.test.ts
  - gui/src/store/useStore.ts
  - src/STREAM.jl
  - src/utilities.jl
  - test/test_utilities.jl
findings:
  critical: 3
  warning: 8
  info: 5
  total: 16
status: issues_found
---

# Phase 63: Code Review Report

**Reviewed:** 2026-05-13
**Depth:** standard
**Files Reviewed:** 27
**Status:** issues_found

## Summary

Phase 63 ships the BCs-tab UI, the canvas BC edge (BCPort), the value-source
toolbox category (`WallTemperature`, `HeatFluxSource`), and the per-mode codegen
emit, plus the Julia `rebin_intensive` / `cosine_T_wall_profile` helpers.

The Julia side (`src/utilities.jl`, `test/test_utilities.jl`) is well-tested
and self-consistent. The GUI side has three correctness defects in the BC
state-sync surface and several quality concerns that hurt maintainability.

Specifically, the canvas-drag and BCs-tab paths into the BC slice are not
fully reciprocal — dragging a BC edge on the canvas creates a `bcEdge` without
a `bcMode` entry, which the codegen then silently elides into a TODO comment.
A symmetric-toggle "left wins" rule lacks a clear-when-left-is-undefined
branch, leaking right-side state. The same toggle ignores the BC edges +
n-mismatch tags it should be re-syncing.

Most issues are localized; none touch the Julia physics core.

## Critical Issues

### CR-01: Canvas-drag path creates BC edge with no matching `bcMode` entry — state-sync drift

**File:** `gui/src/store/useStore.ts:1047-1062`
**Issue:** When the user drags a BCPort connection on the canvas, `addEdge`
detects the BCPort source type, sets `edges` (the edge is enriched as
`type: "bcEdge"` via `enrichEdges`), and calls `_checkBCNMismatch`. It does
**not** create a corresponding `bcMode[bcModeKey(target, targetHandle)] = { mode: "source", sourceNodeId }`
entry. Consequences:

  1. The codegen `bcEmitPlan` builder (codeGenerator.ts:1075-1131) sees the
     entry as `undefined` (D-09 required-unset) and emits only a
     `# TODO: set ch.<input>[i] here` comment — the dashed canvas edge looks
     wired up, but the generated Julia file produces no binding equation.
  2. The Properties → BCs tab will render the picker as required-unset
     (no pill highlighted) even though there is a visible BC edge on the canvas.
  3. The two user paths into BCs (BCsTabForm `setBCMode` vs canvas-drag
     `addEdge`) are not symmetric. The store comment at useStore.ts:1041
     claims "both user paths converge through `_checkBCNMismatch`" — but only
     the mismatch flag converges; the `bcMode` entry diverges.

The bidirectional-sync invariant claimed in CONTEXT D-23 is half-implemented.
The edge-removal direction (`_revertBCModeForEdge`, useStore.ts:1322-1362) is
wired; the edge-creation direction is not.

**Fix:** In `addEdge` BCPort branch (after `set({ edges: finalEdges, ... })`),
materialize the `bcMode` entry too:

```ts
if (srcPort?.type === "BCPort") {
  // Existing: set edges first
  set({ edges: finalEdges, isDirty: true });
  // NEW: materialize bcMode entry so the codegen + BCs-tab UI see the connection
  if (connection.targetHandle) {
    const key = bcModeKey(connection.target, connection.targetHandle);
    const baseField = stripSideSuffix(connection.targetHandle);
    const symKey = `${connection.target}::${baseField}`;
    const symmetric = get().bcSymmetric[symKey] ?? true;
    const siblingName = symmetric
      ? siblingExternalInputName(connection.targetHandle)
      : null;
    const entry: BCModeEntry = {
      mode: "source",
      sourceNodeId: connection.source,
    };
    const nextBCMode = { ...get().bcMode, [key]: entry };
    if (siblingName) nextBCMode[bcModeKey(connection.target, siblingName)] = entry;
    set({ bcMode: nextBCMode });
  }
  get()._checkBCNMismatch(connection.source, connection.target);
  return;
}
```

(Tests at `CanvasPanel.bc.test.tsx:112-127` only assert
`errorTagsByNodeId` — a regression test should additionally verify
`useStore.getState().bcMode[bcModeKey("ch2", "T_wall_left")]?.mode === "source"`
to lock in the contract.)

---

### CR-02: `setBCSymmetric(true)` does not clear `right` when `left` is undefined — "left wins" rule has a hole

**File:** `gui/src/store/useStore.ts:1283-1303`
**Issue:** The contract per CD-05 / line 1293 is "left-wins: if turning ON and
left/right entries differ, copy left to right". The guard at line 1298 reads:

```ts
if (leftEntry !== undefined && leftEntry !== rightEntry) {
  nextBCMode = { ...state.bcMode, [rightKey]: leftEntry };
}
```

When `leftEntry === undefined` and `rightEntry` is defined, the condition is
false and `rightEntry` survives. The user toggled Symmetric ON expecting both
sides to share state (left wins → both undefined per D-09 required-unset), but
the right side retains its prior asymmetric setting. The codegen will then
emit a binding equation for the right side only, contradicting the
user-visible "Symmetric (L = R)" toggle state.

**Fix:** Branch on both cases:

```ts
if (symmetric) {
  const leftKey = bcModeKey(nodeId, `${baseField}_left`);
  const rightKey = bcModeKey(nodeId, `${baseField}_right`);
  const leftEntry = state.bcMode[leftKey];
  const rightEntry = state.bcMode[rightKey];
  if (leftEntry === undefined && rightEntry !== undefined) {
    // Left wins: undefined wins too — drop right.
    const next = { ...state.bcMode };
    delete next[rightKey];
    nextBCMode = next;
  } else if (leftEntry !== undefined && leftEntry !== rightEntry) {
    nextBCMode = { ...state.bcMode, [rightKey]: leftEntry };
  }
}
```

---

### CR-03: `setBCSymmetric(true)` does not sync BC edges or n-mismatch tags after copying `left → right`

**File:** `gui/src/store/useStore.ts:1283-1303`
**Issue:** When `setBCSymmetric(true)` mirrors `leftEntry` onto `rightKey`,
and the entry is `mode: "source"`, the store does NOT:

  1. Create the corresponding BC edge from the source node to the right-side
     target handle (compare with `setBCMode` lines 1166-1208 which materialize
     edges for source mode).
  2. Re-run `_checkBCNMismatch` on the newly-mirrored pair.
  3. Remove any stale BC edge that was previously wired to the right handle
     under a different source entry.

Concretely: if right previously had `{ mode: "source", sourceNodeId: "wtB" }`
with a live BC edge, and left has `{ mode: "source", sourceNodeId: "wtA" }`,
toggling Symmetric ON copies `wtA` into the `bcMode[rightKey]` slot but the
canvas still shows the `wtB → right` edge. State and visuals diverge.

**Fix:** When the mirrored entry is source-mode, fold in the same edge
add/remove + `_checkBCNMismatch` logic that `setBCMode` runs for the right
key. Easiest path: after computing `nextBCMode`, if `leftEntry?.mode === "source"`,
delegate by invoking `setBCMode(nodeId, baseField + "_right", leftEntry)`
after the symmetric flag flip — but that re-pushes a snapshot, so refactor
the edge-materialization logic out of `setBCMode` into a helper and call it
here too.

(Tests at `useStore.bc.test.ts:301-324` cover the value-mode symmetric flip
but never exercise the source-mode flip with a live edge. Add a test for the
source-mode case.)

## Warnings

### WR-01: `enrichEdges` overloads the `componentId` field with a node-id value

**File:** `gui/src/store/useStore.ts:622` and `gui/src/lib/bcMode.ts:50-53`
**Issue:** `BCEdgeData.componentId` is documented as "the consumer node id"
(bcMode.ts:51-52), but the field name `componentId` is the same name used
throughout the registry (`ComponentDefinition.id`, `StreamNodeData.componentId`)
to mean a component **type** id ("Channel", "WallTemperature", etc.). The
codebase uses both `componentId` meanings in adjacent files; this is precisely
the kind of overload that causes future readers to write
`getComponent(data.componentId)` and silently get `undefined`.

**Fix:** Rename `BCEdgeData.componentId` → `BCEdgeData.consumerNodeId` (and
in `setBCMode`'s first arg comment) for clarity. Cascade through `_revertBCModeForEdge`
and tests. Pure rename; no behavior change.

### WR-02: `enrichEdges` BCPort branch silently produces an empty-handle key when `targetHandle` is missing

**File:** `gui/src/store/useStore.ts:622-625`
**Issue:** `externalInputName: e.targetHandle ?? ""` — falling back to `""`
creates a `BCEdgeData` whose `externalInputName` is empty. Downstream,
`bcModeKey(componentId, "")` produces a key like `"nodeId::"` which can never
match a real entry, and `_revertBCModeForEdge` will silently delete a
non-existent key on edge removal. The branch is reached only when a `bcEdge`
edge was hand-crafted without a `targetHandle`, but this case is not asserted
against.

**Fix:** Skip the BCPort branch when `targetHandle` is absent:

```ts
if (srcPort?.type === "BCPort") {
  if (!e.targetHandle) return e; // can't materialize BC data without target handle
  // ...rest of the branch
}
```

### WR-03: Function-mode codegen emits one stub per consumer field — duplicate stub names will produce a Julia redefinition warning

**File:** `gui/src/lib/codeGenerator.ts:1160-1168`
**Issue:** The pre-eqs pass emits `${functionName}(args) = 0.0` per plan item
of mode `function`. The default `functionName` from `BCsTabForm.defaultEntryFor`
is `${consumerComponentLabel}_${externalInputName}_fn` — unique per
(instance, ext) by construction. BUT the user can rename the function via
`FunctionModeEditor` (BCsTabForm.tsx:617-642), and nothing prevents two
different fields from pointing at the same function name. The codegen then
emits:

```julia
my_fn(t) = 0.0  # TODO: ...
my_fn(t) = 0.0  # TODO: ...
```

Julia will warn at parse time (`WARNING: Method definition my_fn(...) overwritten`).
Worse, if signatures differ (`fn(t)` vs `fn(t, i)`), both methods coexist and
the dispatch result is non-obvious.

**Fix:** De-duplicate function stubs across `bcEmitPlan` before emission. Key
by `(functionName, signature)`:

```ts
const emittedFns = new Set<string>();
for (const item of bcEmitPlan) {
  const entry = item.entry;
  if (entry?.mode !== "function") continue;
  const key = `${entry.functionName}::${entry.signature}`;
  if (emittedFns.has(key)) continue;
  emittedFns.add(key);
  ensureBCHeader();
  // ...emit
}
```

### WR-04: `setBCMode` source-mode silently skips edge creation when `sourceNodeId` is empty or unresolvable

**File:** `gui/src/store/useStore.ts:1166-1208`
**Issue:** When `entry.mode === "source"` and either:
  - `entry.sourceNodeId === ""` (the empty-string default from `defaultEntryFor`
    when no sources exist; BCsTabForm.tsx:149), OR
  - `state.nodes.find(...)` returns undefined,

the bcMode entry IS persisted but NO BC edge is created. The user sees a
"required-unset"-like state in the UI (no edge, source dropdown empty) but
the entry IS present in store — so subsequent `clearBCMode` calls behave
differently than required-unset, and `setBCSymmetric` can mirror an unresolvable
entry. There's no surfaced warning.

**Fix:** Either (a) reject the call early — refuse to store a source entry
with empty `sourceNodeId`, OR (b) log a console warning, OR (c) keep current
behavior but emit a `# WARNING:` comment in generated code. Option (a) is
cleanest; the BCsTabForm.tsx:257-260 guard for the `+ New` flow already
prevents this from happening via the UI, so making the store guard match is a
defense-in-depth measure.

### WR-05: `cycleBCEdgeTargetSide` pushes a full undo snapshot per click — undo stack bloat

**File:** `gui/src/store/useStore.ts:1305-1320`
**Issue:** Every click on the L+R/L/R chip pushes a snapshot to `_undoPast`.
The chip is intentionally fast-cycle (3-state, 1-click). A user fiddling with
the chip 10 times burns 10 undo slots on what is purely cosmetic state; with
`-50` truncation that pushes real edits off the undo stack.

**Fix:** Either (a) drop the snapshot push for this action (target-side is
visual, not content); (b) coalesce consecutive cycle calls into one snapshot
via a debounce or "last action was cycle" check.

### WR-06: `detectThermalTopology` orphan-thermal-edges branch is dead code

**File:** `gui/src/lib/codeGenerator.ts:633-638`
**Issue:** `if (orphanThermalEdges.length > 0) { ... }` block contains only
comments and never executes any logic. Either it's an unfinished feature, or
it should be deleted. Dead code mid-function is a maintenance trap.

**Fix:** Delete the block, or move the comment to a `// TODO: Phase XX —
handle orphan thermal edges` line above the `return assemblies;`.

### WR-07: `stripSideSuffix` defined twice with identical behavior in two files

**File:** `gui/src/store/useStore.ts:536-544` and `gui/src/components/sidebar/BCsTabForm.tsx:81-85`
**Issue:** The same helper is implemented twice. Drift risk: if `_left2`
suffix is ever added (or behavior changes), one site will be missed.

**Fix:** Move `stripSideSuffix` (and `siblingExternalInputName`) into
`gui/src/lib/bcMode.ts` as named exports; import both sites from there.
`bcMode.ts` is already the dependency-free single-source-of-truth module per
its own header comment.

### WR-08: `BCsTabForm` reads `useStore.getState()` from inside a React event handler — fresh-state pattern leaks store coupling across the component tree

**File:** `gui/src/components/sidebar/BCsTabForm.tsx:673-703`
**Issue:** `handleNewSource` reads `useStore.getState()` four times. Each call
is fine in isolation, but the pattern bypasses the standard `useStore(selector)`
subscription model. If `addNode` ever becomes async (Phase 64+ resource
loading?), the synchronous diff-the-id-set trick at lines 683-691 breaks
silently. The comment at line 689 acknowledges "last added is the newest by
store-append order" — that ordering assumption is not enforced anywhere in
`useStore.addNode`.

**Fix:** Refactor `useStore.addNode` to return the new node id (it already
mints one at line 945: `const id = crypto.randomUUID();`), then use the
returned id directly:

```ts
// useStore.ts:
addNode: (componentId, position) => {
  // ...
  set({ nodes: [...get().nodes, newNode], isDirty: true });
  return id;  // NEW
},
// type signature: addNode: (...) => string

// BCsTabForm.tsx:
const newId = state.addNode(sourceCompId, position);
state.updateNodeParams(newId, { parameters: { n: consumerN } });
state.setBCMode(nodeId, fieldName, { mode: "source", sourceNodeId: newId });
```

## Info

### IN-01: `Toolbar` and `CodePreview` independently call `generateCode` on every BC slice change

**File:** `gui/src/components/Toolbar.tsx:37-44` and `gui/src/components/CodePreview.tsx:16-23`
**Issue:** Two components each `useMemo` over `generateCode(nodes, edges, bcs, getComponent, resources, {bcMode, bcSymmetric})`.
Identical inputs, identical output, computed twice on every render.

**Fix:** Lift `generateCode` into a memoized selector in the store (or a
shared `useGeneratedCode()` hook backed by zustand), then both consumers
subscribe to the same memoized value. Phase 63 already has the slices in
zustand; the selector is a 1-file addition.

### IN-02: `cycleBCEdgeTargetSide` chip is a generic `<button>` — no `aria-label`

**File:** `gui/src/components/BCEdge.tsx:68-73`
**Issue:** The chip text alternates between "L+R" / "L" / "R" with no
`aria-label`. Screen readers will read "L plus R" or just "L", but the user
has no idea what the button does. Accessibility-minor.

**Fix:** Add `aria-label={`BC edge target side: ${chipLabel}; click to cycle`}`.

### IN-03: `BCsTabForm` `useState(name)` in `FunctionModeEditor` initialises from `entry.functionName` once and never re-syncs

**File:** `gui/src/components/sidebar/BCsTabForm.tsx:617`
**Issue:** Local state `const [name, setName] = useState(entry.functionName)`
captures the initial value only. If `entry.functionName` changes externally
(e.g., a sibling field's symmetric mirror, or undo), the input value goes
stale. Same pattern exists for `ProfileFileBlock`'s `path` (line 587).

**Fix:** Either drop the local state and lift to controlled
(`value={entry.functionName}`, `onChange → onUpdate`), or sync via
`useEffect(() => setName(entry.functionName), [entry.functionName])`.
Local state is only useful here if you want to defer commit until blur — if
that's the intent, document it and add the resync effect.

### IN-04: `_rebin_1d_intensive` is a near-clone of `_rebin_1d` — single-line algorithmic difference

**File:** `src/utilities.jl:33-56` and `src/utilities.jl:213-236`
**Issue:** The two helpers differ only in the final accumulation line
(`v[i] * overlap * n_in` vs `v[i] * overlap * n_out`). Maintenance smell:
a bug fix in one will have to be hand-mirrored in the other. The shared
loop structure could be factored:

```julia
function _rebin_1d_core(v, n_out, scale_factor)
    # ... loop ...
    out[j] += v[i] * overlap * scale_factor
end
_rebin_1d(v, n_out) = _rebin_1d_core(v, n_out, length(v))
_rebin_1d_intensive(v, n_out) = _rebin_1d_core(v, n_out, n_out)
```

**Fix:** Optional — extract the shared body. Not urgent (both are <30 lines
and have full test coverage), but worth a refactor pass when touching this
file next.

### IN-05: `power_shape_unset_for_${hdName}` and `power_shape_${name}_for_${hdName}` variable names risk shadowing user-defined Julia identifiers

**File:** `gui/src/lib/codeGenerator.ts:835` and `:860`
**Issue:** The codegen mints local Julia variable names like
`power_shape_unset_for_hd_1`. If the user happens to name a node
`power_shape_unset_for_hd_1` (technically valid Julia identifier), the
generated code shadows or collides. The existing collision-warning
infrastructure (`componentInstanceNames`) only checks resource names against
instance names; the synthesized `power_shape_..._for_...` names are not
covered.

**Fix:** Either (a) extend the collision check to the synthesized names, or
(b) prefix the synthesized names with a known-rare token (`__ps_unset__hd_1`)
that's unlikely-but-still-valid. Low priority — practical collision risk is
near-zero given the verbosity of the synthesized name.

---

_Reviewed: 2026-05-13_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
