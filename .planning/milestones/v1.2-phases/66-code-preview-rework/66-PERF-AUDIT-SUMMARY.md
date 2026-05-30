# Phase 66 — Perf Sweep Audit Summary

**Type:** out-of-band perf audit + safe-fix commit (NOT a plan; not part of
the planned Phase 66 plan sequence).

**Branch:** `worktree-agent-af755b462e5908900` (Claude Code worktree
exemption per `CLAUDE.md` branching policy).

**Scope:** `gui/src/` only — React + Vite + zustand v5 + ReactFlow. Zero
behavior changes; refactors of how state is consumed only.

**Trigger:** User reported recurring lag in the GUI. Orchestrator had
already identified two of the worst offenders and tasked this agent with
the rest.

---

## What was fixed (single atomic commit)

### F1 — `gui/src/components/Toolbar.tsx`
Toolbar previously subscribed to `nodes`, `edges`, `anchors`, `resources`,
`bcMode`, `bcSymmetric` — all six only consumed inside `handleExport`. The
Toolbar is always mounted at top of screen, so every one of these fired on
every ReactFlow drag tick (60 Hz). Applied the proven `BottomPanel.tsx`
pattern (commit 6c08bcd): subscribe ONLY to derived `hasNodes` boolean for
the Export-button disabled state; read everything else via
`useStore.getState()` at click time in `handleExport`. Removed 5
subscriptions, kept disabled-state behavior.

### F2 — `gui/src/components/WelcomeOverlay.tsx`
Subscribed to full `nodes` + `edges` arrays just to gate render on
`nodes.length > 0 || edges.length > 0`. WelcomeOverlay is rendered inside
CanvasPanel — always mounted. Replaced both with a derived `isEmpty`
boolean primitive — fires only on the empty/non-empty boundary cross.

### F3 — `gui/src/components/CanvasPanel.tsx` **(critical)**
Was destructuring `useStore()` with NO selector:
```tsx
const { nodes, edges, onNodesChange, onEdgesChange, addNode, addEdge, selectNode } = useStore();
```
A no-selector `useStore()` call subscribes to the entire state object —
re-renders on ANY mutation anywhere (`hoveredSourceIds` toggle,
`pinnedSourceIds` flip, BC writes, autosave metadata, etc.). CanvasPanel
hosts ReactFlow, so this was the worst possible location for a
no-selector subscription. Split into 7 individual selectors. Action refs
are stable by zustand contract — adding individual subscriptions for them
is free.

### F4 — `gui/src/components/sidebar/SidebarPanel.tsx`
Subscribed to the full `nodes` array just to look up the selected node in
`renderBody()`. SidebarPanel is always mounted on the right side; every
drag tick replaced the `nodes` array reference, re-rendering the whole
right panel + memoized children. Replaced with a selector that returns
just the selected node:
```tsx
const selectedNode = useStore((s) =>
  selectedNodeId != null ? s.nodes.find((n) => n.id === selectedNodeId) : undefined,
);
```
Per xyflow's `applyNodeChanges` semantics, position updates preserve the
`data` reference — so this selector is stable while dragging the
selected node too. Re-renders fire only on rename / param-edit (which
genuinely change data). Updated the consumer site (`renderBody`) to use
`selectedNode` instead of `nodes.find(...)`.

---

## Other findings — documented but NOT fixed

See `gui/PERFORMANCE.md` § Known Followup Work for the full list. Top
items:

- **KFW-1: StreamNode per-port `resolveFlowPortAssignment` /
  `resolveThermalPairSides` selectors are O(N²) per store mutation.** This
  is the single largest remaining perf cost. Refactor requires
  understanding Phase 64 autoflip — out of scope for a perf sweep.
  Suggestion in PERFORMANCE.md: lift port-assignment computation into an
  App-level `useMemo` that builds a stable `Map<{nodeId,portName}, Side>`,
  then have each handle read from the Map via primitive-string selectors.
- **KFW-2: ResourceRow per-row `nodes.filter()` for usage tracking.**
  Medium impact; only matters when the Resources tab is active.
- **KFW-3: BCsTabForm passes whole `nodes` to GroupBlock.** Cold path
  (only re-renders during editing). Low priority.
- **KFW-4: validation / topology / generateCode invoked from selectors
  elsewhere.** Would need a system-wide audit; deferred.

---

## What was created

- **`gui/PERFORMANCE.md`** (new) — codifies the 9 antipatterns and their
  fixes as durable rules, includes a subscription decision tree, the Known
  Followup Work register, and a sketch of future ESLint + `npm run
  perf-check` enforcement.

---

## Test deltas

Confirmed identical baseline before and after the sweep:

- **vitest:** 827 pass / 5 pre-existing failures / 10 todo. Zero new
  failures.
- **tsc:** 12 pre-existing errors (StreamNode.tsx Handle prop typing
  noise, BCsTabForm test cast noise, SidebarRouter test PowerShape
  `peaking` field, unused validation.test.ts imports). Zero new errors.

---

## Key files modified

| File                                              | Lines changed   | Pattern applied                            |
| ------------------------------------------------- | --------------- | ------------------------------------------ |
| `gui/src/components/Toolbar.tsx`                  | -10/+8 (selectors), +1/-1 (disabled prop) | Drop subscriptions; getState() in handler  |
| `gui/src/components/WelcomeOverlay.tsx`           | -2/+2 + gate    | Derived primitive boolean                  |
| `gui/src/components/CanvasPanel.tsx`              | -1/+7           | Split useStore() into 7 selectors          |
| `gui/src/components/sidebar/SidebarPanel.tsx`     | -1/+7 + consumer rewrite | Subscribe to selected node only            |

---

## Decisions made

1. **F3 took precedence over StreamNode KFW-1** for this commit because
   it's the worse architectural failure (no-selector subscription touches
   ReactFlow's render tree) AND a clean refactor (no behavior risk),
   whereas KFW-1 is bigger payoff but high risk.
2. **No new dependencies.** `useShallow` from `zustand/react/shallow` was
   considered but not needed — all fixed sites reduced cleanly to single
   primitive subscriptions.
3. **PERFORMANCE.md placement under `gui/`** (not repo root) — this is a
   GUI-package concern, and the file should live next to the code it
   governs.

---

## Self-check

Verified file paths exist and edits applied by reading the produced files
through the Edit tool's read-before-write contract; vitest pass count is
identical to baseline; tsc error count identical to baseline.

`## Self-Check: PASSED`
