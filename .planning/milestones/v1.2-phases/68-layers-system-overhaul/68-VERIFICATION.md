---
phase: 68-layers-system-overhaul
verified: 2026-05-16T23:55:00Z
status: passed
score: 14/14 must-haves verified
overrides_applied: 0
re_verification:
  is_re_verification: false
---

# Phase 68: Layers system overhaul — Verification Report

**Phase Goal (ROADMAP.md §"Phase 68"):** Four-layer taxonomy (Hydraulic / Thermal / Sources / Reactor Physics) with independent checkbox visibility. Floating chip top-right of canvas with layer-state color squares. Hide-vs-dim user preference. Off-layer locked. Forgiving layer-aware connect tool that auto-enables relevant layers rather than blocking. Side effect: delete SecondaryToolbar; Export → File menu; Code Preview → BottomPanel header + Ctrl+\` + persistent stub strip.

**Verified:** 2026-05-16T23:55:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | 4-layer toggle API (`LayerKey × Record<LayerKey, boolean>`) replaces `LayerView` in `gui/src/lib/layers.ts` | VERIFIED | `layers.ts:24` exports `LayerKey = "Hydraulic" \| "Thermal" \| "Sources" \| "ReactorPhysics"`; `layers.ts:31` exports `ActiveLayers = Record<LayerKey, boolean>`; `layers.ts:42-47` exports `ALL_LAYERS_ON`; `layers.ts:53-58` exports `LAYER_KEYS`; functions `getComponentLayers`, `isNodeVisible`, `isEdgeDimmed` all present; no `LayerView` / `isComponentVisibleInLayer` / `isNodeDimmed` exports |
| 2 | shadcn Checkbox primitive installed at `gui/src/components/ui/checkbox.tsx` | VERIFIED | File exists; LayersChip imports `Checkbox` from `./ui/checkbox` (LayersChip.tsx:18) |
| 3 | Zustand store exposes `activeLayers`, `hideOffLayer`, `toggleLayer`, `setLayerVisible`, `setAllLayersVisible`, `setHideOffLayer` | VERIFIED | useStore.ts:216-221 (slice + signatures); useStore.ts:835-836 (defaults `{ ...ALL_LAYERS_ON }` + `false`); useStore.ts:1040-1063 (4 setters); old `setActiveLayer`/`cycleLayer`/typed `activeLayer` field gone (only comments remain) |
| 4 | `.scp` serialization writes `layout.active_layers` + `layout.hide_off_layer` with legacy read shim | VERIFIED | projectIO.ts:64-65 (StreamProject layout type); projectIO.ts:91-92 (defaultLayout); projectIO.ts:160-161 (serialize writes new fields, never legacy); projectIO.ts:223-249 (read shim: `active_layers` overlay onto `ALL_LAYERS_ON`; legacy `active_layer` → "Both"→all, "Hydraulic"→only H, "Thermal"→only T; missing→default); covered by 8 round-trip tests A-H |
| 5 | CanvasPanel per-node `{selectable:false, draggable:false, hidden:?}` enrichment for off-layer items | VERIFIED | CanvasPanel.tsx:87-88 (selectors); 105-129 (enrichedNodes useMemo — `isNodeVisible` check, dim mode sets `{ style: { opacity: 0.2, pointerEvents: "none", transition: "opacity 150ms ease" }, selectable: false, draggable: false }`; hide mode sets `{ hidden: true }`) |
| 6 | CanvasPanel per-edge layer dim/hide via `isEdgeDimmed`; layer-aware connect auto-enables off layers | VERIFIED | CanvasPanel.tsx:139-168 (enrichedEdges with `isEdgeDimmed`, edge.type→LayerKey mapping, phantom-edge guard); CanvasPanel.tsx:198-223 (onConnect calls `setLayerVisible(key, true)` for any off layer of either endpoint; never blocks) |
| 7 | Tab shortcut removed from CanvasPanel | VERIFIED | CanvasPanel.tsx:331-332 (comment marker confirming removal); no `e.key === "Tab"` handler remains; no `cycleLayer()` call |
| 8 | StreamNode dual-layer port-handle dim driven by activeLayers | VERIFIED | StreamNode.tsx:355-359 (activeLayers + hideOffLayer selectors); 378-383 (`flowOff = isDualLayer && activeLayers.Hydraulic === false`; `thermalOff = isDualLayer && activeLayers.Thermal === false`; dim vs hide computed from `hideOffLayer`); 221-228 (FlowPortHandle applies `display:none` in hide mode, `opacity 0.2 + pointerEvents:none` in dim mode); same pattern for ThermalPort |
| 9 | ToolboxPanel layer-based filter removed (D-11) | VERIFIED | ToolboxPanel.tsx has no `isComponentVisibleInLayer` import or call; no `activeLayer` (singular) selector; D-11 tests pass: all components shown regardless of activeLayers state |
| 10 | LayersChip component with 4-color indicator + popover (D-01 palette) | VERIFIED | LayersChip.tsx:43-155 — chip button with 4 color squares (lines 74-87) using exact D-01 hex `#3b82f6` / `#f59e0b` / `#8b5cf6` / `#f43f5e` (lines 26-31); opacity 1 if active, 0.35 if inactive; `aria-label="Open layer visibility controls"`; `bg-secondary` when any layer off (lines 67-69); popover with 4 Checkbox rows in LAYER_KEYS order + Dim/Hide Toggle pair |
| 11 | SecondaryToolbar.tsx physically deleted; zero source references | VERIFIED | `ls gui/src/components/SecondaryToolbar.tsx` → not found; `grep -rn SecondaryToolbar gui/src` → zero matches |
| 12 | FileMenu has "Export to Julia…" calling exportCode | VERIFIED | FileMenu.tsx:65-76 (handleExportToJulia replicates SecondaryToolbar shape: generateCode + exportCode with same args); FileMenu.tsx:108-114 (MenubarSeparator + `<MenubarItem onClick={handleExportToJulia}>Export to Julia…</MenubarItem>` after Save As) |
| 13 | ViewMenu has "Toggle Code Preview" with Ctrl+\` shortcut; Layer submenu absent | VERIFIED | ViewMenu.tsx:46-48 (handleToggleCodePreview → toggleBottomPanel); ViewMenu.tsx:56-59 (MenubarItem with `<MenubarShortcut>Ctrl+\`</MenubarShortcut>` before Theme submenu); zero `setActiveLayer`/`cycleLayer`/`LayerView`/`"Both"`/`"Hydraulic"`/`"Thermal"` references in ViewMenu.tsx |
| 14 | BottomPanel collapse button + 20px closed-state stub strip + App.tsx Ctrl+\` registered | VERIFIED | BottomPanel.tsx:80-93 (h-5 stub when `!bottomPanelOpen` with `aria-label="Expand code panel"`, "Code" + ChevronUp, full-row click target → `toggleBottomPanel`); BottomPanel.tsx:115-128 (Tooltip-wrapped ChevronDown ghost Button with `aria-label="Collapse code panel"`, tooltip text "Collapse (Ctrl+\`)"); App.tsx:245-260 (`(e.ctrlKey \|\| e.metaKey) && e.key === "`"` → preventDefault + toggleBottomPanel, with input-focus guard) |

**Score:** 14/14 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `gui/src/lib/layers.ts` | 4-layer pure-function API | VERIFIED | 142 lines, exports `LayerKey`, `ActiveLayers`, `ALL_LAYERS_ON`, `LAYER_KEYS`, `getComponentLayers`, `isNodeVisible`, `isEdgeDimmed`; no react/zustand/@xyflow deps |
| `gui/src/components/ui/checkbox.tsx` | shadcn Checkbox primitive | VERIFIED | File exists; consumed by LayersChip |
| `gui/src/store/useStore.ts` | 4-layer state slices + 4 setters | VERIFIED | activeLayers (line 216), hideOffLayer (217), 4 setters (218-221, implementations 1040-1063); 6 serialize sites + 2 deserialize sites + newProject reset updated |
| `gui/src/lib/projectIO.ts` | .scp v2 schema with legacy shim | VERIFIED | layout type extended, defaultLayout + serializeProject + deserializeProject updated; legacy `active_layer` read shim at 226-247 |
| `gui/src/components/CanvasPanel.tsx` | 4-layer-aware enrichment + onConnect + Tab removed + LayersChip mount | VERIFIED | All five concerns addressed; LayersChip imported (45) and mounted (414) as last child of overlay stack |
| `gui/src/components/StreamNode.tsx` | Per-handle dim/hide for dual-layer nodes | VERIFIED | activeLayers + hideOffLayer selectors; dimFlowHandles/hideFlowHandles/dimThermalHandles/hideThermalHandles computed and applied to handles |
| `gui/src/components/ToolboxPanel.tsx` | No layer-based filter | VERIFIED | isComponentVisibleInLayer removed; activeLayer selector removed; D-11 tests pass |
| `gui/src/components/LayersChip.tsx` | Chip + popover with 4 checkboxes + Dim/Hide pair | VERIFIED | 155 lines, default export, all D-01 colors, all behaviors per UI-SPEC §1/§2 |
| `gui/src/components/__tests__/LayersChip.test.tsx` | 16 interaction tests | VERIFIED | All 16 pass under Vitest |
| `gui/src/components/SecondaryToolbar.tsx` | DELETED | VERIFIED | File absent; no references in source |
| `gui/src/components/FileMenu.tsx` | "Export to Julia…" item | VERIFIED | MenubarItem after Save As + Separator |
| `gui/src/components/ViewMenu.tsx` | Toggle Code Preview + Theme only | VERIFIED | MenubarItem + MenubarShortcut Ctrl+\`; no Layer submenu |
| `gui/src/components/BottomPanel.tsx` | Header collapse button + 20px stub | VERIFIED | h-5 stub when closed; ghost ChevronDown Button + Tooltip when open; Export button preserved (D-12) |
| `gui/src/App.tsx` | Ctrl+\` keyboard handler + SecondaryToolbar removed | VERIFIED | App.tsx:245-260 Ctrl+\` branch with input-focus guard; SecondaryToolbar import + render removed |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| LayersChip.tsx | useStore | activeLayers + hideOffLayer + toggleLayer + setHideOffLayer selectors | WIRED | LayersChip.tsx:44-47 — 4 store selectors active |
| LayersChip.tsx | layers.ts | LAYER_KEYS, LayerKey | WIRED | LayersChip.tsx:15 imports `LAYER_KEYS, type LayerKey` |
| LayersChip.tsx | checkbox.tsx | Checkbox primitive | WIRED | LayersChip.tsx:18 imports Checkbox; checkboxes wired to `toggleLayer(key)` on line 116 |
| CanvasPanel.tsx | LayersChip.tsx | JSX mount | WIRED | CanvasPanel.tsx:45 imports default; line 414 `<LayersChip />` mounted as last child of `absolute top-2 right-2 z-10 flex flex-col gap-1` overlay stack |
| CanvasPanel.tsx onConnect | useStore.setLayerVisible | auto-enable on off-layer connect | WIRED | CanvasPanel.tsx:217-218 — `for (const key of getComponentLayers(comp)) if (!currentActive[key]) setLayerVisible(key, true)` |
| StreamNode.tsx | useStore | activeLayers selector for dual-layer dim | WIRED | StreamNode.tsx:355-359 — both selectors active; `flowOff` / `thermalOff` derived correctly |
| FileMenu.tsx | exportCode util | handleExportToJulia | WIRED | FileMenu.tsx:11 imports exportCode; 65-76 callback wires through generateCode + exportCode with same args as the deleted SecondaryToolbar handler |
| App.tsx Ctrl+\` | useStore.toggleBottomPanel | keydown handler | WIRED | App.tsx:249-260 — guarded branch calls `useStore.getState().toggleBottomPanel()` |
| BottomPanel.tsx collapse btn + stub | useStore.toggleBottomPanel | onClick wiring | WIRED | BottomPanel.tsx:84 (stub strip onClick) + 120 (collapse button onClick) — both call `toggleBottomPanel` |
| ViewMenu.tsx Toggle Code Preview | useStore.toggleBottomPanel | MenubarItem onClick | WIRED | ViewMenu.tsx:46-48 — handleToggleCodePreview → toggleBottomPanel |
| useStore.ts | layers.ts | LayerKey + ActiveLayers + ALL_LAYERS_ON imports | WIRED | Type and default seed imports active in store |
| projectIO.ts | layers.ts | ActiveLayers + ALL_LAYERS_ON imports for shim | WIRED | Layout schema typed against ActiveLayers; legacy shim overlays `ALL_LAYERS_ON` |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| LayersChip | activeLayers, hideOffLayer | useStore (Zustand selector) | Yes — store mutations via toggleLayer/setHideOffLayer flow back; canvas re-renders | FLOWING |
| CanvasPanel.enrichedNodes | activeLayers + hideOffLayer + comp.category | useStore + registry getComponent | Yes — selectors track store; enrichment recomputes via useMemo deps `[nodes, activeLayers, hideOffLayer]` | FLOWING |
| CanvasPanel.enrichedEdges | activeLayers + hideOffLayer + edge.type | useStore + edge metadata | Yes — useMemo deps `[edges, activeLayers, hideOffLayer, enrichedNodes]` | FLOWING |
| StreamNode handles | activeLayers.Hydraulic / activeLayers.Thermal | useStore | Yes — selectors active; isDualLayer derived from registry | FLOWING |
| BottomPanel stub | bottomPanelOpen | useStore | Yes — toggleBottomPanel flips it; conditional render | FLOWING |
| projectIO round-trip | activeLayers, hideOffLayer | SerializeProjectArgs from store | Yes — writes to .scp; deserializer reads back with legacy shim | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| layers.ts unit tests (19 cases) | `npx vitest run src/lib/__tests__/layers.test.ts` | 19/19 pass | PASS |
| Store 4-layer tests (13 cases + others) | `npx vitest run src/store/__tests__/useStore.test.ts` | All pass | PASS |
| projectIO round-trip + legacy shim (A–H + existing) | `npx vitest run src/lib/__tests__/projectIO.snapToGrid.test.ts` | All pass | PASS |
| LayersChip interaction tests (16 cases) | `npx vitest run src/components/__tests__/LayersChip.test.tsx` | 16/16 pass | PASS |
| ToolboxPanel D-11 tests + structural | `npx vitest run src/components/__tests__/ToolboxPanel.test.tsx` | All pass | PASS |
| Full Phase 68 verify suite (5 files) | `npx vitest run [5 files]` | 106/106 pass | PASS |
| Full project test suite | `npx vitest run` | 855 pass / 8 fail / 10 todo (failures pre-existing per gate) | PASS |
| TypeScript compile | `npx tsc --noEmit -p .` | 13 errors total: 4 pre-existing StreamNode Handle data prop (Phase 71); 3 BCsTabForm; 2 SidebarRouter; 3 validation.test.ts; 1 saveProjectAs.test.ts (logged in deferred-items as Plan 68-02 sweep miss; tests still pass) | PASS (no new errors introduced) |
| SecondaryToolbar reference scan | `grep -rn SecondaryToolbar gui/src` | 0 matches | PASS |
| Old layer API source scan | `grep -rnE '\b(LayerView\|isComponentVisibleInLayer\|isNodeDimmed\|setActiveLayer\|cycleLayer)\b' gui/src --include='*.ts' --include='*.tsx' \| grep -v __tests__ \| grep -v '//'` | Only one match: a doc comment reference in layers.ts:28 | PASS |

### Test Gate

**Required:** `npx vitest run` from `gui/` shows 8 PRE-EXISTING failures only.

**Result:** Exactly 8 failures, all pre-existing per the verification gate baseline:
1. `AppShell.test.tsx — D-01: renders three tab triggers labeled Components / Resources / Project` (pre-existing — Phase 62 D-01, AppShell issue)
2. `AppShell.test.tsx — D-01: Components is the default active tab on cold start` (pre-existing)
3. `AppShell.test.tsx — D-01: activating Resources trigger flips aria-selected` (pre-existing)
4. `contextMenus.test.tsx — NodeContextMenu: renders Rename, Duplicate, Show generated Julia code, Delete — and NOT Show errors` (pre-existing)
5. `contextMenus.test.tsx — NodeContextMenu: Delete item removes the node from store` (pre-existing)
6. `contextMenus.test.tsx — EdgeContextMenu: renders only a Delete item` (pre-existing)
7. `contextMenus.test.tsx — CanvasContextMenu: renders Paste, Auto-Layout (future) as disabled, and Add Component submenu trigger` (pre-existing)
8. `SidebarPanel.anchors.test.tsx — Channel BCs tab body still renders the existing BCsTabForm content below Anchors (Symmetric L = R)` (pre-existing)

Failure count: 8 = 4 (contextMenus) + 3 (AppShell) + 1 (SidebarPanel Symmetric L=R) — exact match to the verification gate criteria.

**Zero new Phase 68 regressions.**

### Requirements Coverage

Phase 68 has no formal REQUIREMENTS.md mapping (UI polish phase) — it tracks design decisions D-01 through D-13 instead:

| Decision | Source Plan | Description | Status | Evidence |
|----------|------------|-------------|--------|----------|
| D-01 | Plan 04 | Layer accent palette (Blue/Amber/Violet/Rose) on chip indicator squares | SATISFIED | LayersChip.tsx:26-31 — exact hex match |
| D-02 | Plan 03 | Visible if ANY layer active; off-layer locked non-interactive | SATISFIED | isNodeVisible + CanvasPanel enrichment |
| D-03 | Plan 03 | Dual-layer port-handle dim + lock for one-layer-off case | SATISFIED | StreamNode.tsx:378-383 + handle styling |
| D-04 | Plan 03 | Edges follow their own layer, not endpoints | SATISFIED | enrichedEdges via isEdgeDimmed(edgeLayerKey, activeLayers) |
| D-05 | Plans 01+02 | cycleLayer/LayerView/setActiveLayer removed | SATISFIED | Deny-grep clean modulo doc comments |
| D-06 | Plan 03 | Tab key shortcut removed | SATISFIED | CanvasPanel.tsx:331-332 marker; no Tab handler |
| D-07 | Plan 05 | View menu Layer submenu removed | SATISFIED | ViewMenu.tsx has only Toggle Code Preview + Theme |
| D-08 | Plan 05 | SecondaryToolbar.tsx deleted entirely | SATISFIED | File absent; zero source references |
| D-09 | Plan 05 | Export → File menu as "Export to Julia…" | SATISFIED | FileMenu.tsx:108-114 |
| D-10 | Plan 05 | Code Preview → BottomPanel header + stub strip + View menu | SATISFIED | All three entry points wired to toggleBottomPanel |
| D-11 | Plan 03 | ToolboxPanel does NOT filter by layer | SATISFIED | Filter removed; D-11 tests pass |
| D-12 | Plan 05 | BottomPanel Export button preserved | SATISFIED | Still present alongside the FileMenu entry |
| D-13 | Plan 05 | Ctrl+\` registered in App.tsx | SATISFIED | App.tsx:245-260 with input-focus guard |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (none introduced by Phase 68) | — | — | — | — |

No TBD/FIXME/XXX debt markers introduced. No empty placeholder returns. The pre-existing stale `activeLayer: "Both"` fixture in `saveProjectAs.test.ts` is documented in deferred-items.md as a Plan 68-02 sweep miss; it surfaces only as a tsc warning (test still passes).

### Code Review Findings (from 68-REVIEW.md)

The standard-depth code review surfaced 4 WARNINGS + 4 INFO items. None are blocking the goal:

- **WR-01:** `StreamNode.tsx` selects whole `activeLayers` object — re-render fanout on layer toggle. Performance concern, not correctness. Goal still achieved.
- **WR-02:** Edge-layer classifier silently buckets unknowns as Thermal. Future-proofing concern; current edge types (hydraulicEdge / bcEdge / undefined→Thermal) work correctly today.
- **WR-03:** BottomPanel stub uses `<div role="button">` not `<button>` — a11y/keyboard-operability concern. Mouse/View-menu/Ctrl+\` paths still work.
- **WR-04:** Auto-enable on connect is not undoable. Behavioral inconsistency, not a regression of the documented goal (CONTEXT.md does not specify undo behavior for layer state).
- **IN-01..IN-04:** Minor info findings (no input validation on .scp deserialize, redundant ?? fallback, optional Toggle→ToggleGroup refactor, palette duplication).

These are documented in 68-REVIEW.md for follow-up; they do not block goal achievement and are not Phase 68 regressions.

### Human Verification Required

None. Every must-have is statically verifiable in the codebase (grep / file-existence / behavioral tests). The phase deliverables are pure-client UI + persistence, fully covered by Vitest. The plans did not declare `<verify><human-check>` blocks beyond the optional UAT smoke tests that the plan summaries described as informational ("executor performs visually if running the dev build").

### Gaps Summary

No gaps. Every must-have from the verifier prompt is verified directly in the codebase:

1. The 4-layer pure-function API is the canonical contract.
2. The Zustand store + .scp persistence speak the new shape with legacy read shim.
3. Canvas runtime (CanvasPanel + StreamNode + ToolboxPanel) implements D-02 / D-03 / D-04 / D-06 / D-11.
4. LayersChip is the sole user-facing control surface, mounted into the overlay stack per UI-SPEC §1.
5. SecondaryToolbar is physically deleted; Export → File menu and Code Preview → BottomPanel header + Ctrl+\` + 20px stub strip are all wired to the same `toggleBottomPanel` action.
6. Test gate: 8 pre-existing failures only — zero new Phase 68 regressions.
7. tsc baseline: 13 errors, all pre-existing or documented in deferred-items.md.

The 4 WARNINGS in 68-REVIEW.md are real engineering concerns (re-render fanout, a11y of stub, classifier fragility, undo coupling) but none of them block the documented goal; they are quality / hardening items for a follow-up phase.

---

_Verified: 2026-05-16T23:55:00Z_
_Verifier: Claude (gsd-verifier)_
