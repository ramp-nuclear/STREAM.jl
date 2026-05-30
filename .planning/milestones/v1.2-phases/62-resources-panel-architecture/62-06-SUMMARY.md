---
phase: 62
plan: 06
subsystem: gui/resources
tags: [gui, resources-tab, tree, context-menu, hand-rolled-tree, react, radix]
requires:
  - 62-02  # useStore Resources slice (geometries / powerShapes / fluids + selectResource + SENTINEL_UNSET_POWER_SHAPE)
  - 62-03  # context-menu.tsx + popover.tsx Radix shims
  - 62-05  # App.tsx left-tab strip that mounted the Resources stub <div>
provides:
  - "ResourcesTreePanel: top-level hand-rolled <ul role=\"tree\"> with three group blocks, search filter, sentinel-filtered Power Shapes"
  - "ResourceGroupHeader: GEOMETRIES / POWER SHAPES / FLUIDS uppercase header + 16px Plus icon button (Fluids disabled with locked tooltip)"
  - "ResourceRow: 28px row with selection, F2/double-click inline rename, Radix ContextMenu (Rename / Duplicate / Delete / Show usages), AlertDialog on Delete-with-usages, anchored Popover for Show usages"
affects:
  - "gui/src/App.tsx: TabsContent for Resources now mounts <ResourcesTreePanel /> instead of the 62-05 stub <div>"
tech-stack:
  added: []
  patterns:
    - "Hand-rolled <ul>-based tree (CD-01) — NOT react-arborist"
    - "Radix ContextMenu + Popover + AlertDialog composition on a single row via asChild chaining"
    - "Sentinel UUID filter at render time (D-26)"
key-files:
  created:
    - gui/src/components/resources/ResourcesTreePanel.tsx
    - gui/src/components/resources/ResourceGroupHeader.tsx
    - gui/src/components/resources/ResourceRow.tsx
    - gui/src/components/resources/__tests__/ResourcesTreePanel.test.tsx
  modified:
    - gui/src/App.tsx
decisions:
  - "D-03: Resources tab body is a tree with per-group + button, rename, context menu, search"
  - "CD-01: Tree widget is hand-rolled <ul>-based (NOT react-arborist)"
  - "D-05: Selecting a resource clears selectedNodeId (mutual exclusivity verified in test)"
  - "D-20: Empty group post-filter renders the locked (none yet — click +) placeholder"
  - "D-26: Sentinel PowerShape filtered out of the visible tree"
  - "Integration seam strategy 2 (local Popover per consumer): + button stubbed to console.log until 62-08 ships the shared editor forms"
  - "Keyboard arrow nav across rows deferred to v1+ — Tab-only for v1 (UI-SPEC CD-01 leeway, documented in ResourceRow.tsx + ResourcesTreePanel.tsx code comments)"
metrics:
  duration: ~25 minutes
  completed: 2026-05-12
---

# Phase 62 Plan 06: Resources Panel Tree Summary

Hand-rolled `<ul>`-based Resources tab body — three group headers (GEOMETRIES / POWER SHAPES / FLUIDS), top search box, per-row inline rename and context menu, sentinel PowerShape filtered out — wired into the left tab strip from 62-05.

## What Was Built

### `gui/src/components/resources/ResourcesTreePanel.tsx`

The Resources tab body. Renders:

1. A top search input (`Input` shim) with placeholder `Search resources…` (verbatim U+2026), case-insensitive substring filter against `resource.name`.
2. A `<ScrollArea>` wrapping a `<ul role="tree">` with three `<li role="none">` group blocks.
3. Each group: a `<ResourceGroupHeader>` and a child `<ul role="group">` of `<ResourceRow>`s. For Power Shapes, the sentinel UUID (`SENTINEL_UNSET_POWER_SHAPE`) is filtered out before render — D-26.
4. Empty groups (post-filter) render the locked `(none yet — click +)` line (12px italic muted) — D-20.
5. `+ button` handlers are stubs (`console.log(...)` + TODO comment) until 62-08 ships the shared `+ New…` popover. Per the plan's `<integration_seam_for_popover_creation>`, strategy 2 (local Popover per consumer) was chosen; this component will own its own Popover instance in 62-08.

### `gui/src/components/resources/ResourceGroupHeader.tsx`

Group header row: locked Tailwind `text-xs font-semibold uppercase tracking-wide text-muted-foreground` label + trailing 16x16 `Plus` icon button (`Button variant="ghost" size="icon-xs"`). When `disabled` is true (Fluids group only), the button is wrapped in a Tooltip that surfaces the verbatim `Multi-fluid support is planned for a future release.` copy. The disabled button is wrapped in a `<span tabIndex={0}>` so the Radix Tooltip trigger still receives pointer events (a `disabled` `<button>` swallows mouseenter on some browsers).

### `gui/src/components/resources/ResourceRow.tsx`

Per-resource row with the full interaction surface:

- Single-click → `useStore.selectResource(uuid, kind)` (D-05 clears selectedNodeId).
- F2 OR double-click → inline-rename mode. The row's name span swaps for an `<Input>` constrained to row height. Enter / click-outside commits via `useStore.renameResource(...)`; Esc reverts and exits rename mode; collision (the store action throws) leaves the user in rename mode with `aria-invalid` + destructive border + tooltip carrying the store error message.
- Right-click → Radix ContextMenu with the locked order Rename / Duplicate / Delete / Show usages. Delete uses `variant="destructive"`.
- Delete with `usages.length === 0` → immediate `removeResource(...)` (undoable via Ctrl+Z).
- Delete with `usages.length > 0` → opens an AlertDialog with the description `Delete <kind> <name>? It is used by <N> component(s).` and `Delete anyway` (destructive) / `Cancel` buttons.
- Show usages → anchored Radix Popover with header `Used by <N> component(s)` and a scrollable list of consuming nodes; clicking an entry calls `selectNode(id)` and closes the popover.
- The light_water Fluid placeholder row is rendered with `text-muted-foreground`, no hover background, no double-click rename, and no ContextMenu wrapper — entirely per UI-SPEC §"Fluids placeholder row".

### `gui/src/App.tsx`

The 62-05 stub `<div>Resources panel — coming in plan 62-06</div>` was replaced with `<ResourcesTreePanel />`.

### `gui/src/components/resources/__tests__/ResourcesTreePanel.test.tsx`

17 vitest specs (happy-dom environment), all green. Coverage:

- Tree shape (3 group headers, 3 add buttons, Fluids disabled).
- Fluid placeholder row: visible, no rename on double-click, no context menu on right-click.
- D-26 sentinel filter: sentinel name/UUID not in the rendered DOM, empty Power Shapes group shows the placeholder.
- Search: case-insensitive substring filter; clear restores; empty result across all groups renders three placeholder lines (D-20).
- D-05 selection mutual exclusivity: clicking a Geometry row clears `selectedNodeId` and sets `selectedResourceKind/Id`.
- Inline rename: F2 + Enter commits; Esc cancels (no DOM input remains); collision blocks commit, name unchanged, input gets `aria-invalid="true"`.
- Context menu: Rename triggers inline rename; Delete-with-zero-usages removes; Delete-with-usages opens AlertDialog with the verbatim copy and Cancel keeps the resource.

## Key Decisions

### Integration seam for `+ New…` popover (strategy 2)

The plan's `<integration_seam_for_popover_creation>` left the choice between (1) a centralized `<ResourceCreationPopover>` mounted at App level, or (2) a local Popover instance per consumer. Phase 62 picks **strategy 2** for simplicity — 62-08 will mount its own popover in `ResourceReferencePicker`, and `ResourcesTreePanel` will mount a local Popover anchored to the `+ button`. The shared piece is the inner editor form (62-08 implements `<GeometryResourceEditor>` and `<PowerShapeResourceEditor>` once; both call sites consume them). Until 62-08 ships those editors, the `+ button` handlers are `console.log(...)` stubs with TODO comments.

### Keyboard arrow navigation deferred (CD-01 leeway)

UI-SPEC §"Inside Resources tab — keyboard nav after switch" explicitly gives the executor a choice: implement Up/Down/Home/End on `role="treeitem"` or accept Tab-only nav for v1. We chose Tab-only — `<li role="treeitem" tabIndex={0}>` makes each row focusable via Tab from the search box / Add button. Arrow-key tree navigation would require a focus-management ref + an `aria-activedescendant` model, and the v1 row count (handfuls of resources) does not warrant it. The decision is documented as a code comment at the top of both `ResourcesTreePanel.tsx` and `ResourceRow.tsx`.

### ContextMenu + Popover wrapper ordering (structural)

The asChild chain `<Popover> → <ContextMenu> → <ContextMenuTrigger asChild> → <PopoverAnchor asChild> → <li>` resolves to the row `<li>` receiving both the Radix ContextMenu's `onContextMenu` handler and the Popover's anchor ref. Initially we wrapped Popover inside `ContextMenuTrigger asChild`, but Popover is a non-DOM root component, so the ContextMenuTrigger had no DOM child to attach `onContextMenu` to — the three context-menu vitests reproduced the bug and forced the fix.

### Fluid row: no ContextMenu wrapper

The light_water row branches out of the ContextMenu/Popover/AlertDialog block entirely — `if (isFluidPlaceholder) return baseRow;` — rather than conditionally enabling/disabling menu items. This guarantees right-click on the fluid row never opens a menu and double-click never triggers rename, matching the UI-SPEC's "context-menu and rename suppressed" rule without runtime checks per menu item.

## Test Notes

- `happy-dom` handles Radix portals correctly. Both `ContextMenuContent` and `AlertDialogContent` mount into `document.body`; `screen.findByRole(...)` (async) resolves once mounted.
- `fireEvent.contextMenu(row)` fires the DOM `contextmenu` event, which Radix's `ContextMenuTrigger.onContextMenu` handler picks up. No userEvent / pointerdown gymnastics needed for the mouse-context-menu path.
- `findBy*` (async) was used for the post-context-menu menu items and the AlertDialog description text. The Popover for "Show usages" was NOT tested per the plan's explicit deferral (`DO NOT test the Show-usages popover content interactions in this plan`).

## Self-Check: PASSED

- `gui/src/components/resources/ResourcesTreePanel.tsx` — FOUND
- `gui/src/components/resources/ResourceGroupHeader.tsx` — FOUND
- `gui/src/components/resources/ResourceRow.tsx` — FOUND
- `gui/src/components/resources/__tests__/ResourcesTreePanel.test.tsx` — FOUND
- `gui/src/App.tsx` — modified (ResourcesTreePanel mounted in TabsContent value="Resources")
- Task 1 commit `7ad208e` — present in git log
- Task 2 commit `f931344` — present in git log
- `npx vitest run src/components/resources/` → 17/17 passed
- `npx tsc --noEmit` → no new errors in 62-06 files (baseline 8 errors all pre-existing per Task 1)

## Deviations from Plan

None — the plan executed exactly as written. The ContextMenu/Popover structural fix in Task 2 was a discovered-during-test correction to the Task 1 implementation, but it is internal to the same Wave 2 plan and resolved before any tests reported red beyond the initial run.
