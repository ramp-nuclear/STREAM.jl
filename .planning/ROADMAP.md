# Milestone v1.2: GUI Redesign

**Status:** Planning (active design exploration complete; ready for `/gsd:plan-phase` per phase)
**Phases:** 59–72 (14 phases)
**Branch:** `gui-redesign` (single working branch off `main`, single PR to `main` at end per CLAUDE.md branching policy)
**Defined:** 2026-05-11
**Design-decisions reference:** `.planning/notes/gui-redesign-design-decisions.md` (canonical, authoritative)

## Overview

A from-the-ground refresh of the STREAM Composer GUI (Tauri 2 + React + ReactFlow), driven by:

1. **SNAP research** (NUREG/CR-6974 CAFEAN Preprocessor API report + RELAP5 plug-in manual) — surfaced architectural patterns and feature gaps.
2. **The v1.1 channels-redesign architecture** (PR #15, branch `channels-redesign`, currently 1 commit ahead of main and FF-mergeable) — fundamentally changes channel ports: `Channel` and `ChannelHeatFlux` no longer have thermal ports, only `ChannelAndContacts` does. Two new value-source components (`WallTemperature`, `HeatFluxSource`) replace port-based wall BCs for Channel/CHF.
3. **User-identified pain in v0.8** — connection-arrow overlap, missing edge deletion, weak validation surfacing, "amateur playbox" visual feel rather than professional engineering tool.

**Core invariants** (frozen through the milestone — see `gui-redesign-design-decisions.md` Section 1):

- GUI is a code-generation tool, not a simulation environment. Julia file remains canonical for the executable model.
- Tauri 2 + React + ReactFlow shell stays. No framework swap.
- Static panel layout with resizable splits. No dockable workspaces.
- Channel and ChannelHeatFlux have no thermal ports (v1.1 architecture). Only ChannelAndContacts connects to HeatDiffusion.
- Per-channel signed gravity, not global.

## Prerequisites

- **PR #15 (v1.1 channels-redesign) merged to `main`.** Currently OPEN but not a blocker — `gui-redesign` branch is 1 planning commit ahead of `channels-redesign` and already contains the full v1.1 architecture. v1.2 phase work proceeds on `gui-redesign` now; when PR #15 merges, `gui-redesign` fast-forwards onto `main` trivially (no conflicts expected, cleanup commits don't touch channel API).

## Phases

- [x] **Phase 59: Correlation `geom`-first refactor** — `src/physical_models/`; every factory that needs geometry takes `geom::PipeGeometry` first; no more `Dh`/`L`/`depth`/`width` plumbed independently. `const HTCCorrelation = Function` alias. Tests + Python parity re-run. (completed 2026-05-11)
- [x] **Phase 60: `fuel_assembly` composition helper** — new helper in `src/composition/helpers.jl` covering 4 variants of alternating CAC↔Plate chains (channel-bookended, plate-bookended, mixed, closed annular). Tests + code-gen detection update. (completed 2026-05-11)
- [x] **Phase 61: Registry audit + rewrite for v1.1** — `gui/src/registry/components.json` rewritten against v1.1 source. Add `WallTemperature`, `HeatFluxSource`, `PointKinetics`, `ReactivityController`. Collapse correlation sub-param trees per geom-first. Add `scope` field per parameter (constructor_kwarg vs external_input) for Properties-tab vs BCs-tab split. Bump `stream_version` to `1.1.0`. (completed 2026-05-12)
- [x] **Phase 62: Resources panel architecture** — Navigator restructure to `Project → Model Options + Resources + Components`. Foreign-key UUID references. Save format (`.scp`). Reference picker UX. Sources toolbox category. (completed 2026-05-13)
- [x] **Phase 63: BCs tab + value-source components in GUI** — Properties tab vs BCs tab separation. Five BC modes (value / profile / function / mark-in-code / driven-by-source-block). `WallTemperature` and `HeatFluxSource` toolbox entries. Dashed BC edge style. Bidirectional sync between BCs tab and canvas connections. (completed 2026-05-13)
- [x] **Phase 64: Connection routing** — Per-port autoflip for FlowPorts with asymmetric same-side placement. Independent axis-flip for thermal-pair ports on CAC/HD. Anti-parallel offset for bidirectional pairs as polish hook. (completed 2026-05-14)
- [x] **Phase 65: Interaction model overhaul** ✓ shipped 2026-05-14 — Left-marquee selection, right-click drag pan, right-click no-drag context menu. Edge deletion (Del/Backspace + right-click). Copy/Cut/Paste/Duplicate (Ctrl+C/X/V/D) with smart-parse-and-increment naming. Reset-to-empty rule for property fields. Snap-to-grid toggle. AutoRecover sidecar snapshot mechanism.
- [x] **Phase 66: Code preview rework** — Structured `CodeSection[]` output replacing flat string code-gen. Section blocks (Imports / Resources / Components / Composition / Main). Bidirectional traceability (code-hover → canvas-highlight; canvas-select → explicit code-jump). Click-to-pin sections. Copy + Export buttons in code panel toolbar. Hand-rolled formatting rules. (completed 2026-05-16)
- [x] **Phase 67: Custom titlebar** — Tauri `decorations: false` + custom HTML titlebar. Integrated File/Edit/View/Help menubar, app icon, project name, dirty dot (left); min/max/close buttons (right). Cross-platform consistency. (completed 2026-05-16)
- [x] **Phase 68: Layers system overhaul** — Four-layer taxonomy (Hydraulic / Thermal / Sources / Reactor Physics). Independent checkbox toggles. Floating Layers chip top-right of canvas with layer-state color indicators. Hide-vs-dim setting. Off-layer locked (non-interactive). Non-clunky layer-aware connect tool. (completed 2026-05-16)
- [x] **Phase 69: Command palette (jump-only)** — Ctrl+P fuzzy search across component instance names + Resource names. Focus-on-canvas for components, focus-in-navigator for Resources. No action invocation in v1. (completed 2026-05-18)
- [ ] **Phase 70: Presets and templates** — `.scpr` file format (slimmed-down `.scp` sub-graph). Save-selection-as-preset, Load-preset. Presets toolbox category. Auto-resource-create on load with smart-name collision handling. No identity (Option 1 per issue #14).
- [ ] **Phase 71: Validation framework** — Pluggable validator registry. Uniform panel UX with severity (error/warning/info) + click-to-focus + action buttons (lossless-sync / value-transfer-picker / navigation-only). Red-ring markers on offending nodes + red highlights on offending property fields. Compact status-bar indicator (VS-Code-style: icons + counts). Initial rule set: z_N/length match, n-match for value sources, all-required-connections, port-type matching, dangling FlowPort, loop closure, gravity sum per loop, geometry consistency across shared coupling. Gates code-gen export on errors.
- [ ] **Phase 72: Design system / interaction contract** — Write the rules document (spatial / interaction / feedback / defaults / visual-restraint discipline) committing to "professional engineering tool, not consumer SaaS playground." Audit-and-apply pass over every existing panel. Deliverables include: thermal port handle restyle (outlined circle + chain-link state icons), tooltip system, Settings dialog (modal with left-nav categories), canvas cheatsheet (auto-generated demo component with numbered legend), accent palette for Sources and Reactor Physics layers, density expectations, visual style commitments (font, color, shadow, radius scales).

## Phase Details

### Phase 59: Correlation `geom`-first refactor

**Goal:** Establish a single uniform convention for every correlation factory in `src/physical_models/htc/correlations.jl` and `src/physical_models/friction/correlations.jl`: take `geom::PipeGeometry` as first positional argument, derive everything from it internally. Eliminate the duplicate-Dh-input problem in the GUI and the inconsistent factory signatures in the source.

**Design-decisions reference:** Section 3.1.
**Depends on:** v1.1 channels-redesign merged (prerequisite above).
**Plans:** 4/4 plans complete

- [x] 59-01-PLAN.md (Wave 1) — Refactor `laminar_friction` to `(geom::PipeGeometry)`; add `const HTCCorrelation = Function` alias + export; update PHY-03 tests.
- [x] 59-02-PLAN.md (Wave 2, depends on 59-01) — Refactor `elenbaas_htc`, `fully_developed_laminar_h_spl`, `developing_laminar_h_spl`, `regime_dependent` to `geom`-first signatures; collapse `regime_dependent` group validation to `(htc_natural, g)`; update HTC + NATCONV + PHY-04 tests.
- [x] 59-03-PLAN.md (Wave 3, depends on 59-01 + 59-02) — Sweep `src/examples.jl` (lines 438, 441, 443, 581), `test/test_composition.jl`, and `test/test_integration.jl` (TF-06 line 770, TF-07 line 854) call sites; run integrated test gate including `test/test_validation.jl` Python parity (load-bearing semantic-drift assertion against the pre-refactor parity_report.csv baseline).
- [x] 59-04-PLAN.md (Wave 4, depends on 59-03) — Emit `.planning/notes/correlation-geom-first-api.md` Phase 61 handoff doc per D-05.

### Phase 60: `fuel_assembly` composition helper

**Goal:** Add a new composition helper `fuel_assembly(channels, plates; bookend, closed, name)` to `src/composition/helpers.jl` that handles the four variants of alternating CAC↔Plate chains. Closes the gap where reactor fuel assemblies currently require hand-rolled `connect()` chains. GUI code-gen detects this topology and emits the helper call.

**Design-decisions reference:** Section 3.12.
**Depends on:** Phase 59.
**Plans:** 2/2 plans complete

- [x] 60-01-PLAN.md (Wave 1) — Implement `fuel_assembly` helper in `src/composition/helpers.jl` with four-variant dispatch + ArgumentError validation; export from `src/STREAM.jl`.
- [x] 60-02-PLAN.md (Wave 2, depends on 60-01) — Variant parity tests (4 testsets at rtol=1e-10) + ArgumentError tests in `test/test_composition.jl`; emit Phase 61 handoff note `.planning/notes/fuel-assembly-api.md` per D-07.

### Phase 61: Registry audit + rewrite for v1.1

**Goal:** Bring `gui/src/registry/components.json` into alignment with v1.1 source. Stream version bump to `1.1.0`. Add 4 missing components. Rewrite Channel/CHF entries (drop thermal ports, drop `htc_correlation` on Channel, add `h_left`/`h_right`, declare `T_wall_*`/`q_*` external-input variables). Collapse correlation sub-parameter trees per geom-first refactor. Add `scope` field per parameter to support Properties-tab vs BCs-tab split.

**Design-decisions reference:** Section 3.2, Section 3.10, plus the audit methodology captured in the conversation lineage.
**Depends on:** Phase 60 (so the registry can reflect helper additions).
**Plans:** 5/5 plans complete

- [x] 61-01-PLAN.md (Wave 1) — Schema + types reshape: bump versions, extend types.ts with v1.1 vocabulary (external_inputs, type_union, BCPort, etc.)
- [x] 61-02-PLAN.md (Wave 2, depends on 61-01) — Channel-family + HD rewrite (Channel, CHF, CAC, HD entries)
- [x] 61-03-PLAN.md (Wave 3, depends on 61-02) — Add WallTemperature, HeatFluxSource, PointKinetics, ReactivityController + register icons
- [x] 61-04-PLAN.md (Wave 4, depends on 61-03) — Re-audit unchanged components (Pump, Flapper, etc.) + global legacy port-key sweep
- [x] 61-05-PLAN.md (Wave 5, depends on 61-04) — Update tests + reconcile downstream consumers + human-verified GUI smoke (HAS CHECKPOINT)

### Phase 62: Resources panel architecture

**Goal:** The single biggest architectural shift in this milestone. Components no longer carry inline geometry/power-shape values; they reference named, definable, reusable model-level Resources by stable UUID. Navigator gains Model Options (singleton) and Resources branches alongside Components.

**Design-decisions reference:** Section 3.2.
**Depends on:** Phase 61 (registry must support resource-ref shape).
**Plans:** 15/15 plans complete

- [x] 62-01-PLAN.md — Julia src/utilities.jl with rebin_extensive + cosine_power_shape; test/test_utilities.jl (Wave 1)
- [x] 62-02-PLAN.md — Zustand Resources + ModelOptions + activeLeftTab + selection-kind slices; sentinel UUID baked into initial state (Wave 1)
- [x] 62-03-PLAN.md — shadcn popover.tsx + context-menu.tsx shims; Pitfall 1 click-outside-disabled smoke test (Wave 1)
- [x] 62-04-PLAN.md — projectIO.ts rewrite for .scp v2.0; hard cutover from .streamgui; delete 5 stale export examples (Wave 2)
- [x] 62-05-PLAN.md — App.tsx Tabs shell + Ctrl+1/2/3 keyboard; SOURCES category header in ToolboxPanel (Wave 2)
- [x] 62-06-PLAN.md — Resources tab body: hand-rolled tree + group headers + search + inline-rename + context-menu (Wave 2)
- [x] 62-07-PLAN.md — Project tab body: Model Options form (name, description, fluid, g, solver defaults) (Wave 2)
- [x] 62-08-PLAN.md — Resource editors + ResourceReferencePicker + anchored Popover (non-dismiss-on-outside + Pitfall 1 focus return) (Wave 2)
- [x] 62-09-PLAN.md — SidebarPanel selection-kind router; header text per kind; Esc cascade tail (Wave 3)
- [x] 62-10-PLAN.md — codeGenerator.ts rewrite: Resources block at top + four PowerShape kinds + Pitfall 4 warnings (Wave 3)
- [x] 62-11-PLAN.md — Fresh simple_loop.scp fixture + INV-CG-05 smoke test + human-verify checkpoint (Wave 3, has checkpoint)
- [x] 62-12-PLAN.md (Wave 4, gap closure) — ResourceReferencePicker narrow-row wrap fix (flex-wrap + min-w-0 + shrink-0 + basis-full) closes UAT Gap 1.
- [x] 62-13-PLAN.md (Wave 4, gap closure) — ResourceRow usage-detection scans both `parameters[name]` and `parameters[name+'_ref']` via PARAM_KEY_BY_KIND; delete AlertDialog now lists live + legacy usage. Closes UAT Gap 2.
- [x] 62-14-PLAN.md (Wave 4, gap closure) — `useStore.saveProjectAs` derives default filename from `modelOptions.name` via `computeSaveAsDefaultFilename`; `FALLBACK_SAVE_AS_FILENAME` when name empty. Closes UAT Gap 3.
- [x] 62-15-PLAN.md (Wave 5, copy audit) — Cross-cutting engineering-tool voice rewrite: 19 OLD-string instances removed; new copy ("Save failed" / "Open failed" / "(leave unset — set in code)" sentinel / "Used by N component(s)." in AlertDialog) verified. Closes UAT Gap 4.

### Phase 63: BCs tab + value-source components in GUI

**Goal:** Split the property panel into Properties tab (constructor kwargs) and BCs tab (external-input variables). BCs tab supports five modes per field: scalar value, preset profile, imported profile, "mark in code for later," and "driven by source block." `WallTemperature` and `HeatFluxSource` toolbox entries (the value-source components from v1.1). Distinct dashed-edge BC connection style. Bidirectional sync between BCs tab dropdown selection and the canvas connection.

**Design-decisions reference:** Section 3.10, Section 3.11.
**Depends on:** Phase 62.
**Plans:** 4/4 plans complete

- [x] 63-A-PLAN.md (Wave 1) — Julia `rebin_intensive` (1D + 2D) + `cosine_T_wall_profile` thin alias in `src/utilities.jl`; tests in `test/test_utilities.jl`; exports in `STREAM.jl`.
- [x] 63-B-PLAN.md (Wave 1, parallel to 63-A) — Zustand `bcMode` slice + `bcSymmetric` + `errorNodeIds`; `gui/src/lib/bcMode.ts` shared types + `isAllowedBCConnection`; `codeGenerator.ts` 5-mode emit + symmetric expansion; vitest coverage.
- [x] 63-C-PLAN.md (Wave 2, depends on 63-B) — BCs tab UI: `SidebarPanel.tsx` Tabs wrapper, new `BCsTabForm.tsx` + `BCModePicker.tsx` + extracted `SegmentedButtonGroup.tsx` primitive; `+ New <SourceKind>` inline-button flow.
- [x] 63-D-PLAN.md (Wave 2, parallel to 63-C, depends on 63-B) — Canvas BC edge: `BCEdge.tsx` dashed + click-to-cycle chip; `StreamNode.tsx` BCPort hollow-square handle + source-label + drop overlay + red-ring; `CanvasPanel.tsx` edgeTypes + isValidConnection BCPort allow-list; `ToolboxPanel.tsx` Sources populated.

### Phase 63.1: BC architecture rework — unified BCs tab (INSERTED)

**Goal:** Rework BC architecture from Phase 63 — unified BCs tab as single per-component surface for Anchors + External Inputs (D-09), hide Sources canvas nodes (D-06), dropdown mode picker (D-11), segmented Sym/Asym (D-12), new anchors Record slice replacing legacy bcs[] (D-02/D-03), selector-derived validation replacing errorTagsByNodeId (D-15..D-19/D-23), canvas anchor indicator (D-13), Promote-to-shared-source flow (D-07/D-08), plus CR-01/CR-02/CR-03 + click-vs-drag bug fixes (D-20/D-21/D-22).
**Requirements**: D-01..D-23 (no global REQ-IDs; coverage tracked via CONTEXT.md decisions)
**Depends on:** Phase 63
**Plans:** 14/14 plans complete

Plans:

- [x] 63.1-01-PLAN.md (Wave 0) — Test scaffolding: nine RED test files covering selectNodeErrors, anchors slice, codegen anchors, projectIO schema, CR-01, CR-02/CR-03, click-vs-drag, promoteToSharedSource, StreamNode anchor indicator.
- [x] 63.1-02-PLAN.md (Wave 1, depends on 01) — selectNodeErrors pure selector + delete errorTagsByNodeId slice + _checkBCNMismatch action; StreamNode migrated; useStore.bc.test.ts rewritten.
- [x] 63.1-03-PLAN.md (Wave 2, depends on 02) — anchors slice (Record<nodeId, AnchorEntry>) + setAnchor/clearAnchor + projectIO schema swap; delete bcs/addBC/removeBC.
- [x] 63.1-04-PLAN.md (Wave 3, depends on 03) — codeGenerator signature swap + anchors emission + validateTopology Object.keys check + Toolbar/CodePreview call-sites.
- [x] 63.1-05-PLAN.md (Wave 3, depends on 03, parallel to 04) — Delete BCPanel.tsx, BCRow.tsx; remove BCs tab from BottomPanel.tsx.
- [x] 63.1-06-PLAN.md (Wave 4, depends on 03/04/05) — AnchorsSection.tsx + SidebarPanel.tsx ComponentTabs BCs body (Anchors + External Inputs two-section layout).
- [x] 63.1-07-PLAN.md (Wave 4, depends on 03/05, parallel to 06) — BCsTabForm.tsx: inline shadcn Select dropdown replaces BCModePicker; SegmentedButtonGroup replaces SymmetricToggle; delete BCModePicker.tsx.
- [x] 63.1-08-PLAN.md (Wave 5, depends on 06/07) — promoteToSharedSource store action + ↗ Promote to shared source ghost button in BCsTabForm; remove legacy + New ${sourceCompId} button.
- [x] 63.1-09-PLAN.md (Wave 5, depends on 03, parallel to 08) — ToolboxPanel.tsx Sources block deleted (D-06); StreamNode.tsx anchor indicator (D-13).
- [x] 63.1-10-PLAN.md (Wave 6, depends on 08) — CR-01 addEdge BCPort fix; CR-02/CR-03 setBCSymmetric fix + _reconcileEdgesForBCMode helper; click-vs-drag onNodesChange.select sync; D-23 verified.
- [x] 63.1-11-PLAN.md (Wave 7, gap closure, depends on 07/08) — RC-1: ParameterForm type_union branch + tests; unblocks WT.T_wall / HFS.q / Channel.h_left editability (closes UAT GAP-RC-1, GAP-RC-3 primary path).
- [x] 63.1-12-PLAN.md (Wave 7, gap closure, depends on 10) — RC-2: add BCPort target handles to Channel + ChannelHeatFlux registry; StreamNode source-vs-target dispatch; delete decoy whole-body overlay (closes UAT GAP-RC-2 / test 6 blocked-by-prior-phase).
- [x] 63.1-13-PLAN.md (Wave 8, gap closure, depends on 09/11) — Cosmetic + minor sweep: anchor glyph swap (lucide Anchor), Source SelectItem disabled gate, Promote button icon-only restyle, promoteToSharedSource default-seed (T_wall=300 / q=0) (closes UAT GAP-COSMETIC-ANCHOR, GAP-MINOR-SOURCE-GATE, GAP-COSMETIC-PROMOTE, GAP-RC-3 default-seed sweetener).
- [x] 63.1-14-PLAN.md (Wave 8, gap closure, depends on 11/13) — BC-mode parity for WT.T_wall / HFS.q: new `sourceValueEntry.ts` 4-arm discriminated union (value / cosine-profile / file-profile / function); shared `modeEditors.tsx` extracted from BCsTabForm; ParameterForm TypeUnionField gains 3-option Mode dropdown (Value/Profile/Function) for Sources-category params; codeGenerator `sourceEmitPlan` emits profile-var assignments + function stubs; StreamNode `sourceLabelLine` dispatches per-mode; promoteToSharedSource seeds `defaultSourceValueEntry(300.0|0.0)` (closes UAT GAP-RC-4).

### Phase 64: Connection routing

**Goal:** Solve the connection-arrow ugliness verified in the example_*.png screenshots. Per-port autoflip moves each FlowPort handle to the side facing its connected neighbor. Asymmetric same-side placement disambiguates when both ports of a component end up on the same edge. Thermal-port-pair axis-flip for CAC/HD (left/right or top/bottom). Optional polish hook for anti-parallel offset of bidirectional pairs.

**Design-decisions reference:** Section 3.3, Section 3.4.
**Depends on:** Phase 62.
**Plans:** 4/4 plans complete

Plans:
**Wave 1**

- [x] 64-01-autoflip-pure-module-PLAN.md (Wave 1) — Pure autoflip module: resolveFlowPortSide / resolveAsymmetricOffset / resolveThermalPairSides / detectAxisCollision / findAntiParallelSibling in gui/src/lib/autoflip.ts; vitest coverage of D-08..D-18.
- [x] 64-02-anti-parallel-bow-PLAN.md (Wave 1) — HydraulicEdge.tsx ±8px perpendicular bow for bidirectional hydraulic pairs (D-06/D-07/D-08/D-17 same-type-only filter); uses useStore.getState() (no hook subscription) to avoid render-storm.

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 64-03-streamnode-autoflip-integration-PLAN.md (Wave 2, depends on 01) — Wire autoflip into FlowPortHandle + new ThermalPortHandle in StreamNode.tsx; D-09/D-10 inline-style 25%/75%; useUpdateNodeInternals on side flip; closes Pitfall 6 latent CAC thermal undefined-side bug; human smoke checkpoint.
- [x] 64-04-topology-hint-validation-PLAN.md (Wave 2, depends on 01; sequenced after 03 on StreamNode.tsx) — selectTopologyHints pure selector in gui/src/lib/selectors/topologyHints.ts mirroring nodeErrors.ts; non-blocking yellow chip in StreamNode for D-15 axis-collision.

### Phase 65: Interaction model overhaul

**Goal:** Rewire the canvas interaction model from v0.8's ReactFlow defaults. Left-marquee selection + right-pan + right-click context menu (per drawio convention). Edge deletion. Copy/paste/cut/duplicate with smart-name-increment. Reset-to-empty for property fields. Snap-to-grid toggle (Settings + canvas overlay). AutoRecover (sidecar snapshot, OS temp dir, prompt-on-next-launch-after-crash).

**Design-decisions reference:** Section 3.5.
**Depends on:** —.
**Plans:** 14 plans (8 original + 6 gap closure from UAT 2026-05-15).

Plans:
**Wave 1**

- [x] 65-01-PLAN.md — Naming retrofit: lowest-free nextInstanceName + delete instanceCounters (D-17, D-18).
- [x] 65-02-PLAN.md — Reset-to-empty unified field reset across Properties / BCs / type_union editors.
- [x] 65-03-PLAN.md — Canvas interaction props (panOnDrag=[2], selectionOnDrag, Esc-clears, edge-delete-via-Del) + useRightClickContextMenu 5px/250ms disambiguation (D-12).

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 65-04-PLAN.md — Clipboard core + Ctrl+C/X/V/D keyboard wiring + smart-parse-and-increment (D-15, D-16, D-19).

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 65-05-PLAN.md — Node / Edge / Canvas context menus via shadcn ContextMenu + Popover (D-11, D-14); Auto-Layout grayed-out; "Show errors" hidden until Phase 71.

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 65-06-PLAN.md — Snap-to-grid overlay button + ReactFlow snapToGrid/snapGrid + .scp layout.snap_to_grid persistence (D-07..D-10).

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 65-07-PLAN.md — AutoRecover I/O substrate: sidecar writer + lockfile + crash detection + Tauri PID commands (D-01..D-06).

**Wave 6** *(blocked on Wave 5 completion)*

- [x] 65-08-PLAN.md — AutoRecover restore modal + App.tsx mount/unmount integration (D-03, D-04).

**Wave 7** *(gap closure — UAT 2026-05-15; runs after Phase 65 ship)*

- [x] 65-09-autorecover-capability-fix-PLAN.md (gap closure) — BLOCKER: grant Tauri v2 fs ACL appdata scope (4 new permissions in capabilities/default.json) + DEV-mode logging on 8 autoRecover silent-catch blocks. Closes UAT Tests 16+17 (sidecar writer + crash modal). Has manual UAT checkpoint.
- [x] 65-10-esc-input-focus-guard-PLAN.md (gap closure) — Major: SidebarPanel.tsx Esc keydown handler gains input-focus guard mirroring CanvasPanel.tsx — restores zustand ↔ ReactFlow selection lockstep when Esc fires inside a text input. Closes UAT Test 7.
- [x] 65-11-addcomponent-submenu-radix-PLAN.md (gap closure) — Major: swap hand-rolled PopoverMenuSub* (W10 workaround from Plan 05) for Radix DropdownMenu.Sub with built-in Floating UI viewport-collision flip; new `gui/src/components/ui/dropdown-menu.tsx` shadcn shim. Closes UAT Test 13 (submenus offscreen at right edge).
- [x] 65-12-marquee-css-PLAN.md (gap closure) — Cosmetic: two CSS rule blocks appended to `gui/src/index.css` — solid border on `.react-flow__selection` (color-mix oklch), `display: none` on `.react-flow__nodesselection-rect`. Closes UAT Test 4 marquee dotted border + bounding-box gaps.
- [x] 65-13-canvas-controls-dedup-PLAN.md (gap closure) — Cosmetic: add 4 top-right overlay buttons (ZoomIn/ZoomOut/FitView/InteractiveLock mirroring SnapToGridButton.tsx pattern) + new session-only `interactiveLocked` useStore field driving nodesDraggable/nodesConnectable/elementsSelectable/panOnDrag; delete ReactFlow built-in `<Controls />`. Closes UAT Test 14.
- [x] 65-14-perf-trivial-gates-PLAN.md (gap closure, Wave 8 — depends on 65-13 for useStore.ts) — Minor (trivial dimension only): install `subscribeWithSelector` middleware on useStore; gate App.tsx title-sync subscribe so Tauri setTitle IPC fires only on {currentFilePath, isDirty} change; gate autoRecover subscribe to fire only on isDirty edge transitions. DEFERRED to future perf phase: autoflip memoization, isDirty-at-drag-stop, WSL2/WebKitGTK env retest. Partial closure of UAT Test 4 perf complaint.

### Phase 66: Code preview rework

**Goal:** Refactor code generator from flat string output to structured `CodeSection[]` output with source-UUID tracking. Build the section-block Code Preview UI with hover-to-highlight on canvas, click-to-pin sections, copy + export buttons inline in the panel, and explicit "jump to code" from canvas selection.

**Design-decisions reference:** Section 3.11 (code-gen impact), plus the code-tab rework discussion captured in the conversation lineage.
**Depends on:** Phase 62 (resources are part of generated sections).
**Plans:** 6/5 plans complete

- [x] 66-01-red-tests-structured-codegen-PLAN.md — Wave 0: RED tests for CodeSection[] + serializeSections + CodePreview UI behavior (5 new vitest files; all RED to lock the contract before implementation)
- [x] 66-02-codegenerator-structured-output-PLAN.md — Wave 1: refactor codeGenerator.ts to return CodeSection[]; add serializeSections; migrate 5 existing codegen test files via one-line adapter + D-12 header updates; TEMP-wrap CodePreview/Toolbar to preserve runtime
- [x] 66-03-store-slices-hooks-exportcode-PLAN.md — Wave 2: hoveredSourceIds/pinnedSourceIds/pendingShowCodeFor Zustand slices; useShowCodeFor hook; global Esc handler in App.tsx; exportCode.ts shared util; Toolbar migration to use the util
- [x] 66-04-codepreview-ui-rewrite-PLAN.md — Wave 3: CodePreview.tsx full rewrite (section-by-section, hover/click/scroll/flash); BottomPanel.tsx Copy + Export buttons in TabsList; flips Plan 01 RED CodePreview tests to GREEN
- [x] 66-05-streamnode-hover-ring-PLAN.md — Wave 4: StreamNode.tsx subscribes to hoveredSourceIds/pinnedSourceIds; index.css placeholder ring CSS; Phase 72 handoff doc; manual UAT checkpoint (end-to-end bidirectional traceability)

### Phase 67: Custom titlebar

**Goal:** Replace OS chrome with a custom Tauri titlebar to fix WSLg ugliness and get cross-platform consistency. Integrated menubar in the titlebar to save vertical space.

**Design-decisions reference:** Section 3.6.
**Depends on:** —.
**Plans:** 5/3 plans complete

- [x] 67-01-PLAN.md (Wave 1) — Tauri 4-layer foundation: npm install @tauri-apps/plugin-os; Cargo + lib.rs plugin register; 5 capability permissions; `decorations: false`; copy app icon to gui/public/. Isolates the dominant silent-failure risk per RESEARCH.md.
- [x] 67-02-PLAN.md (Wave 2, depends on 01) — Leaf primitives: useTheme.ts `THEMES` export (D-21 array-driven), `useWindowMaximized` hook, `WindowControls.tsx` (platform-branched macOS circles vs Windows/Linux Lucide icons), shadcn `dialog` install, `AboutDialog.tsx`.
- [x] 67-03-PLAN.md (Wave 3, depends on 01+02; HAS CHECKPOINT) — Composition + integration: `EditMenu.tsx`/`ViewMenu.tsx`/`HelpMenu.tsx`, `CustomTitlebar.tsx` shell with drag-region sibling per D-26, `SecondaryToolbar.tsx`, App.tsx root restructure, delete Toolbar.tsx + ThemeMenu.tsx; manual WSLg UAT covering drag/double-click/min/max/close + known-risk edge-resize (D-18).

### Phase 68: Layers system overhaul

**Goal:** Four-layer taxonomy (Hydraulic / Thermal / Sources / Reactor Physics) with independent checkbox visibility. Floating chip top-right of canvas with layer-state color squares. Hide-vs-dim user preference. Off-layer locked. Forgiving layer-aware connect tool that auto-enables relevant layers rather than blocking.

**Design-decisions reference:** Section 3.13.
**Depends on:** Phase 62 (Sources layer requires Sources category to exist).
**Plans:** 5/5 plans complete

Plans:
**Wave 1**

- [x] 68-01-PLAN.md (Wave 1) — Rewrite `gui/src/lib/layers.ts` to the 4-layer independent-toggle API (LayerKey / ActiveLayers / isNodeVisible / isEdgeDimmed / getComponentLayers via registry category); install shadcn Checkbox primitive; full test rewrite for the new API.

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 68-02-PLAN.md (Wave 2, depends 01) — Replace activeLayer / cycleLayer / setActiveLayer in useStore with activeLayers + hideOffLayer slices and toggleLayer / setLayerVisible / setAllLayersVisible / setHideOffLayer actions; extend projectIO `.scp` layout block with active_layers + hide_off_layer + read-side legacy active_layer shim; update fixtures in 4 affected test files.

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 68-03-PLAN.md (Wave 3, depends 02) — Rewrite CanvasPanel node + edge enrichment for dim/hide/lock; layer-aware onConnect auto-enable; remove Tab cycle shortcut + stale onNodeClick guard; update StreamNode per-handle dim for dual-layer nodes (D-02/D-03); strip ToolboxPanel layer filter per D-11 + update its tests.
- [x] 68-05-PLAN.md (Wave 3, depends 02) — Delete SecondaryToolbar.tsx (D-08); add "Export to Julia…" to File menu (D-09); add "Toggle Code Preview" back to View menu with Ctrl+backtick shortcut hint (D-10); register Ctrl+backtick in App.tsx keyboard hub (D-13); redesign BottomPanel with header collapse button + 20px closed-state stub strip (D-10); preserve BottomPanel Export button (D-12).

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 68-04-PLAN.md (Wave 4, depends 02 + 03) — Create LayersChip component (4-color indicator + Popover with 4 Checkbox rows + Dim/Hide Toggle pair per D-01); mount into the CanvasPanel top-right overlay stack; companion Vitest interaction test file.

### Phase 69: Command palette (jump-only)

**Goal:** Ctrl+P fuzzy search restricted to navigation use: jump-to-component-by-name and jump-to-resource. No action invocation in v1. Components focus the canvas + select; Resources focus the navigator + open property panel.

**Design-decisions reference:** Section 3.7.
**Depends on:** Phase 62.
**Plans:** 3/3 plans complete

Plans:
**Wave 1**

- [x] 69-01-PLAN.md (Wave 1) — cmdk dependency audit + install + shadcn command.tsx shim + buildSearchPool helper with unit tests + ResourcesTreePanel scrollIntoView effect (D-01, D-06 foundations).

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 69-02-PLAN.md (Wave 2, depends 01) — CommandPalette.tsx component: top-anchored Dialog (D-02), browse-vs-flat modes, per-layer accent off-layer chip (D-03/D-08), per-kind on-select dispatch (D-04/D-05/D-06), no matched-char highlighting (D-07); vitest behavior suite.

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 69-03-PLAN.md (Wave 3, depends 02) — App.tsx Ctrl+P shortcut (synchronous preventDefault, Pitfall 1) + CommandPalette mount inside ReactFlowProvider (Pitfall 2); 69-UAT-CHECKLIST.md artifact; blocking human-verify UAT.

### Phase 70: Presets and templates

**Goal:** Reusable component-bundle templates. `.scpr` file format (slimmed-down version of `.scp`). "Save selection as preset" right-click + File menu entry. "Load preset" via File menu + Presets toolbox category. No identity (copy-paste templates per issue #14 resolution). Forward-compatible to passive-identity if real usage demands it later.

**Design-decisions reference:** Section 3.14.
**Depends on:** Phase 62.
**Plans:** 2/6 plans executed

Plans:
- [x] 70-01-PLAN.md (Wave 1) — Tauri substrate: `watch` Cargo feature + 4 ACL permissions (incl. `$APPCONFIG/presets/**` scope) + shadcn `textarea` / `radio-group` installs (HAS CHECKPOINT for shadcn install).
- [x] 70-02-PLAN.md (Wave 1, parallel to 01) — Pure `gui/src/lib/presetIO.ts` (schema v1.0, `autoExtendSelection` BC-hop algorithm, `normalizeLayout`, `isValidPresetName`) + full vitest coverage.
- [ ] 70-03-PLAN.md (Wave 2, depends 01+02) — `useStore` presets slice: `projectPresets` / `libraryPresets` state, `refreshPresetsDir`, `saveSelectionAsPreset`, `loadPresetAtPosition`, `loadPresetFromPath`, `renamePreset`, `deletePreset` actions + Tauri-mocked vitest coverage.
- [ ] 70-04-PLAN.md (Wave 3, depends 01+02+03) — `PresetsPanel.tsx` 4th-tab body with two collapsible sections + file-system watcher useEffect + `PresetRow.tsx` (drag handle / inline rename / context menu / delete confirmation).
- [ ] 70-05-PLAN.md (Wave 3, depends 01+02+03, parallel to 04) — `SavePresetModal.tsx` Radix Dialog (Name / Description / Store-radio default Library) + auto-extend preview painting `data.autoExtended` + `StreamNode.tsx` amber dashed outline + `projectIO.serializeProject` strips the transient flag (Pitfall 7 defense).
- [ ] 70-06-PLAN.md (Wave 4, depends 01-05) — Wiring: `App.tsx` Ctrl+4 + 4th TabsContent + lifted `SavePresetModal` mount via custom-event; `ResponsiveTabsList` widened; `FileMenu` Load preset… + Save selection as preset… (disabled <2); `NodeContextMenu` Save selection as preset… (visible only ≥2); `CanvasPanel` `application/stream-preset` drop branch; manual UAT checkpoint (rebuild Tauri + 16-step end-to-end verification).

### Phase 71: Validation framework

**Goal:** One unified, rule-pluggable validation framework covering everything introspectable that's physically or structurally wrong. Uniform panel UX, click-to-focus, fix-action buttons (lossless-sync / value-transfer-picker / navigation-only). Red-ring markers on canvas, red highlights on offending property fields, VS-Code-style compact status-bar indicator (icons + counts). Validators registered for: z_N/length match, n-match for value sources, all-required-connections, port-type matching, dangling FlowPort, loop closure, gravity sum per loop, geometry consistency across shared coupling. Severity gates code-gen export.

**Design-decisions reference:** Section 3.9.
**Depends on:** Phase 62 (operates on Resources + components).
**Plans:** TBD via `/gsd:plan-phase`.

### Phase 72: Design system / interaction contract

**Goal:** Establish the design contract document that codifies the spatial / interaction / feedback / defaults / visual-restraint rules. Run an audit-and-apply pass over every existing panel to bring it into compliance. Deliver the visual surfaces: thermal port handle restyle, tooltip system, Settings dialog, canvas cheatsheet, accent palette extensions for Sources and Reactor Physics layers, density commitments. This is where the "professional engineering tool, not consumer SaaS playground" framing becomes concrete decisions about fonts, colors, shadows, radii, spacing.

**Design-decisions reference:** Section 3.8.
**Depends on:** All prior phases (it audits and applies the contract to every functional surface). The contract *document* itself can be drafted in parallel with earlier phases.
**Plans:** TBD via `/gsd:plan-phase`.

## Dependency Graph Summary

```
Prerequisite: v1.1 channels-redesign merged
                         │
                         ▼
                       Phase 59 (correlation refactor) ─┐
                         │                              │
                         ▼                              │
                       Phase 60 (fuel_assembly)         │
                         │                              │
                         ▼                              │
                       Phase 61 (registry audit) ◄──────┘
                         │
                         ▼
                       Phase 62 (Resources architecture) ─────────────────────┐
                         │                                                    │
            ┌────────────┼────────────┬─────────────┬───────────────┐         │
            ▼            ▼            ▼             ▼               ▼         │
        Phase 63     Phase 64     Phase 66      Phase 68         Phase 70     │
        (BCs tab)    (routing)    (code panel)  (layers)         (presets)    │
                                                                              │
                                                  Phase 69 (palette) ─────────┤
                                                                              │
                                                  Phase 71 (validation) ◄─────┘

Independent of Phase 62:
   Phase 65 (interaction model)
   Phase 67 (titlebar)

Phase 72 (design system) depends on all phases — runs audit at the end;
contract document drafted in parallel throughout.
```

## Progress

| Phase | Plans Complete | Status      | Completed |
|-------|----------------|-------------|-----------|
| 59. Correlation `geom`-first refactor                | 4/4 | Complete    | 2026-05-11 |
| 60. `fuel_assembly` composition helper               | 2/2 | Complete    | 2026-05-11 |
| 61. Registry audit + rewrite for v1.1                | 5/5 | Complete   | 2026-05-12 |
| 62. Resources panel architecture                     | 15/15 | Complete    | 2026-05-13 |
| 63. BCs tab + value-source components in GUI         | 4/4 | Complete    | 2026-05-13 |
| 63.1. BC architecture rework — unified BCs tab       | 14/14 | Complete   | 2026-05-14 |
| 64. Connection routing                               | 4/4 | Complete    | 2026-05-14 |
| 65. Interaction model overhaul                       | 8/14 | Gap closure in flight | — |
| 66. Code preview rework                              | 6/5 | Complete    | 2026-05-16 |
| 67. Custom titlebar                                  | 5/3 | Complete   | 2026-05-16 |
| 68. Layers system overhaul                           | 5/5 | Complete    | 2026-05-16 |
| 69. Command palette (jump-only)                      | 3/3 | Complete    | 2026-05-18 |
| 70. Presets and templates                            | 2/6 | In Progress|  |
| 71. Validation framework                             | 0/TBD | Planned | — |
| 72. Design system / interaction contract             | 0/TBD | Planned | — |

## Coverage

Requirements coverage for v1.2 is currently captured in the design-decisions doc rather than `REQUIREMENTS.md`. The next step is to extract concrete REQ-IDs per phase during `/gsd:plan-phase` for each phase, and append them to `REQUIREMENTS.md`. The design contract phase (72) is exceptional — its "requirements" are the design rules themselves, which are deliverables rather than measurable success criteria.

## Notes

- **Branching policy** (from CLAUDE.md): user owns branch creation. The working branch `gui-redesign` already exists; do not create per-phase branches. `.planning/config.json` `git.branching_strategy` MUST stay `"none"`.
- **Per-phase planning workflow:** for each phase, run `/gsd:discuss-phase` to gather context-aware questions, then `/gsd:plan-phase` to produce the phase plan with task breakdown.
- **The design-decisions doc is authoritative.** Any apparent conflict between this ROADMAP and the design-decisions doc resolves to the design-decisions doc; update the ROADMAP to match.

---

*v1.1 ROADMAP content moved to `.planning/MILESTONES.md` per the existing convention for shipped milestones (v1.1 entry already lives there). Per-phase artifacts for v1.1 (52-58) remain in `.planning/phases/` and `.planning/milestones/`.*
