# Phase 39: Topology Validation - Context

**Gathered:** 2026-04-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Users receive immediate visual feedback when their system topology has structural problems. Three validation rules:
- **VALD-01**: Unconnected mandatory FlowPorts → red ring on affected node
- **VALD-02**: No pressure boundary condition → listed in error dialog
- **VALD-03**: No driving element (no Pump or Gravity node) → listed in error dialog

This phase adds validation-triggered UI only. No new components, no new canvas interactions, no code generator changes.

</domain>

<decisions>
## Implementation Decisions

### Validation Trigger
- **D-01:** Validation runs **only when the user attempts to export Julia code or save the project**. Not continuous/reactive. A freshly dragged, unwired node does not show errors during normal canvas construction.
- **D-02:** If validation finds issues, the export/save is **blocked** — the operation does not proceed until the user dismisses the error dialog.

### Error Presentation
- **D-03:** A **shadcn `AlertDialog`** (modal) appears when validation fails, listing all issues:
  - Unconnected ports: `{instanceName}: {portName} unconnected` (one line per port)
  - No pressure anchor: `No pressure boundary condition`
  - No driving element: `No driving element (add a Pump or Gravity component)`
  The user dismisses with a single OK/Close button.
- **D-04:** The dialog groups by issue type (node-level issues first, then system-level issues).

### Node Error Indicator (Post-Dialog)
- **D-05:** After the user dismisses the dialog, **red rings (`ring-2 ring-destructive`) persist on affected nodes** until each error is resolved. Same visual pattern as the selection ring (`ring-2 ring-[var(--ring)]`) but using the `destructive` color token.
- **D-06:** Red rings **clear automatically** when the underlying issue is fixed (port gets connected). No manual dismiss — reactive clearing only.
- **D-07:** A node with both an error ring and a selection ring shows both simultaneously. Destructive ring style: `ring-2 ring-destructive ring-offset-1` (slight offset to distinguish from selection ring if needed — Claude's discretion on exact layering).

### Validation State
- **D-08:** Validation state lives as a **computed set** in the Zustand store (or a derived selector): `errorNodeIds: Set<string>` — which nodes currently have error rings. Set is populated by the dialog trigger, cleared reactively as edges are added.
- **D-09:** System-level checks (VALD-02/VALD-03) are pure functions over `nodes` and `bcs` arrays — no ring needed, only dialog text.

### What Counts as "Connected"
- **D-10:** A FlowPort is considered connected if there is at least one edge in the `edges` array with a `source`/`target` handle matching that port name on that node. ThermalPorts are not checked (Phase 40 scope).
- **D-11:** "Pressure anchor" = at least one entry in the `bcs` array. If `bcs` is empty, VALD-02 fires. (Claude to verify this matches how the code generator interprets BCs.)
- **D-12:** "Driving element" = at least one node with `componentId === "Pump"` or `componentId === "Gravity"` in the `nodes` array.

### Claude's Discretion
- Exact ring layering when selected + error simultaneously
- Whether to extract a `topologyValidator.ts` lib function or keep inline in store action
- Error dialog title text and icon
- Order of error items within each group in the dialog

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` §"Topology Validation" → VALD-01, VALD-02, VALD-03 — Exact acceptance criteria

### Roadmap
- `.planning/ROADMAP.md` §"Phase 39: Topology Validation" — Goal, success criteria, depends-on Phase 34

### Existing UI code (read before making changes)
- `gui/src/components/StreamNode.tsx` — Current node rendering; add `hasError` prop / conditional ring class here
- `gui/src/store/useStore.ts` — Zustand store; add `errorNodeIds`, `validateTopology()` action, reactive edge-clear logic
- `gui/src/components/Toolbar.tsx` — Export button lives here; validation gate goes here before triggering export
- `gui/src/components/BottomPanel.tsx` — Code export/save flow lives here; validation gate also needed at save path
- `gui/src/components/ui/` — shadcn `AlertDialog` component (check if installed; if not, needs `npx shadcn add alert-dialog`)
- `gui/src/registry/components.json` — Source of truth for `ports[]` per component (what ports exist and their names)
- `gui/src/registry/types.ts` — `Port` interface with `name`, `type`, `side` fields

### Prior phase context
- `.planning/phases/34-canvas-node-editor/34-CONTEXT.md` — D-07: topology validation explicitly deferred to Phase 39; D-06: source/target directionality enforced at draw time
- `.planning/phases/38-ui-design-pass/38-CONTEXT.md` — D-04: category left border stripe (blue/amber); selection ring is `ring-2 ring-[var(--ring)]`; error ring must coexist

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `gui/src/components/ui/` — Check if `alert-dialog` is already installed (`ls gui/src/components/ui/`). If not, `npx shadcn add alert-dialog` in the `gui/` directory.
- `gui/src/store/useStore.ts` — `nodes`, `edges`, `bcs` already in store. Add `errorNodeIds: Set<string>` and a `validateTopology()` action that populates it and returns the error list for the dialog.
- `gui/src/lib/validation.ts` — Currently only has field validators. Could add `validateTopology(nodes, edges, bcs, registry)` as a pure function here, keeping store action thin.

### Established Patterns
- Store actions are defined inline in the `create()` call in `useStore.ts`
- Registry is imported via `getComponent(id)` and `getAllComponents()` from `gui/src/registry`
- shadcn primitives used: Button, Input, Label, Select, ScrollArea, Tabs, Tooltip, Badge, DropdownMenu, Separator — AlertDialog is NOT yet installed
- Node state (`selected`, `componentId`, `instanceName`) is in `node.data` as `StreamNodeData`
- Edge `sourceHandle` / `targetHandle` contain the port name (e.g., `"port_in"`, `"port_out"`)

### Integration Points
- `validateTopology()` called from export button handler (Toolbar) and save action (store's `saveProject`)
- `StreamNode.tsx` needs `hasError: boolean` signal — either via store selector on `errorNodeIds.has(id)`, or via node data prop
- Edge addition (`addEdge` action) should clear the relevant node from `errorNodeIds` when both ports of the new edge are now connected
- `bcs` array in store: if empty → VALD-02; checking `componentId` across `nodes` array for Pump/Gravity → VALD-03

</code_context>

<specifics>
## Specific Ideas

- "Only on export/save, not while I'm building" — user explicitly rejected always-on indicators to avoid noise during construction
- Red ring persists after dismiss so the user can see which nodes to fix without re-triggering export
- Modal dialog chosen over inline banners or toasts — clean, blocks export, lists all issues at once

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 39-topology-validation*
*Context gathered: 2026-04-03*
