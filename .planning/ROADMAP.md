# ROADMAP: STREAM.jl

## Milestones

- ✅ **v0.1 MVP** — Phases 1-5 (shipped 2026-03-13)
- ✅ **v0.2 Component & Network Expansion** — Phases 6-9 (shipped 2026-03-13)
- ✅ **v0.3 HeatDiffusion** — Phases 10-12.1 (shipped 2026-03-14)
- ✅ **v0.4 Composability & Physics** — Phases 13-16 (shipped 2026-03-16)
- ✅ **v0.5 Code Quality** — Phases 17-19 (shipped 2026-03-16)
- ✅ **v0.6 Flow Reversal Systems** — Phases 20-26 (shipped 2026-03-27)
- ✅ **v0.7 Safety Physics & Pressure Field** — Phases 27-32 (shipped 2026-04-01)
- 🔄 **v0.8 STREAM Composer GUI** — Phases 33-44 (active)

## Phases

<details>
<summary>✅ v0.1 MVP (Phases 1-5) — SHIPPED 2026-03-13</summary>

- [x] Phase 1: Foundation (3/3 plans) — completed 2026-03-12
- [x] Phase 2: Components (4/4 plans) — completed 2026-03-12
- [x] Phase 3: Integration and Validation (3/3 plans) — completed 2026-03-12
- [x] Phase 4: Tech Debt Cleanup (1/1 plan) — completed 2026-03-12
- [x] Phase 5: Nyquist Validation (1/1 plan) — completed 2026-03-12

Full phase details: `.planning/milestones/v0.1-ROADMAP.md`

</details>

<details>
<summary>✅ v0.2 Component & Network Expansion (Phases 6-9) — SHIPPED 2026-03-13</summary>

- [x] Phase 6: Gravity Validation (1/1 plan) — completed 2026-03-13
- [x] Phase 7: Network Architecture (2/2 plans) — completed 2026-03-13
- [x] Phase 8: Inertia and HeatExchanger (2/2 plans) — completed 2026-03-13
- [x] Phase 9: ChannelAndContacts (2/2 plans) — completed 2026-03-13

Full phase details: `.planning/milestones/v0.2-ROADMAP.md`

</details>

<details>
<summary>✅ v0.3 HeatDiffusion (Phases 10-12.1) — SHIPPED 2026-03-14</summary>

- [x] Phase 10: ChannelAndContacts Two-Sided Upgrade (2/2 plans) — completed 2026-03-13
- [x] Phase 11: HeatDiffusion Component (2/2 plans) — completed 2026-03-14
- [x] Phase 12: MTR Validation (2/2 plans) — completed 2026-03-14
- [x] Phase 12.1: PipeGeometry Struct (2/2 plans) — completed 2026-03-14

Full phase details: `.planning/milestones/v0.3-ROADMAP.md`

</details>

<details>
<summary>✅ v0.4 Composability & Physics (Phases 13-16) — SHIPPED 2026-03-16</summary>

- [x] Phase 13: Physics Foundation (2/2 plans) — completed 2026-03-14
- [x] Phase 14: Laminar Correlations (2/2 plans) — completed 2026-03-14
- [x] Phase 15: Composition Helpers & QoL (2/2 plans) — completed 2026-03-15
- [x] Phase 16: Validation (1/1 plan) — completed 2026-03-15

Full phase details: `.planning/milestones/v0.4-ROADMAP.md`

</details>

<details>
<summary>✅ v0.5 Code Quality (Phases 17-19) — SHIPPED 2026-03-16</summary>

- [x] Phase 17: File Structure Reorganization (2/2 plans) — completed 2026-03-16
- [x] Phase 18: Test Split and API Cleanup (2/2 plans) — completed 2026-03-16
- [x] Phase 19: Docstrings, CLAUDE.md, and Final Polish (2/2 plans) — completed 2026-03-16

Full phase details: `.planning/milestones/v0.5-ROADMAP.md`

</details>

<details>
<summary>✅ v0.6 Flow Reversal Systems (Phases 20-26) — SHIPPED 2026-03-27</summary>

- [x] Phase 20: Sign Safety (2/2 plans) — completed 2026-03-17
- [x] Phase 21: Fluid Properties & Natural Convection (2/2 plans) — completed 2026-03-17
- [x] Phase 22: Time-Varying Pump (2/2 plans) — completed 2026-03-18
- [x] Phase 23: Flapper & Solver Events (2/2 plans) — completed 2026-03-20
- [x] Phase 24: Loss-of-Flow Validation (1/1 plan) — completed 2026-03-21
- [x] Phase 24.1: Bypass LOF Topology (2/2 plans) — completed 2026-03-21
- [x] Phase 25: Argument Structure Audit (1/1 plan) — completed 2026-03-26
- [x] Phase 26: NC Regime HTC + LOF Cleanup (2/2 plans) — completed 2026-03-26

Full phase details: `.planning/milestones/v0.6-ROADMAP.md`

</details>

<details>
<summary>✅ v0.7 Safety Physics & Pressure Field (Phases 27-32) — SHIPPED 2026-04-01</summary>

- [x] Phase 27: Pressure Field (2/2 plans) — completed 2026-03-28
- [x] Phase 27.1: Channel Momentum & Inertia (3/3 plans) — completed 2026-03-29
- [x] Phase 28: Subcooled Boiling (2/2 plans) — completed 2026-03-30
- [x] Phase 29: Threshold Analysis (2/2 plans) — completed 2026-03-31
- [x] Phase 30: HTC & Friction Completions (2/2 plans) — completed 2026-04-01
- [x] Phase 31: Write Phase 27 Verification Document (1/1 plans) — completed 2026-04-01
- [x] Phase 32: THRS-09 & Phase 30 Integration Hardening (1/1 plans) — completed 2026-04-01

Full phase details: `.planning/milestones/v0.7-ROADMAP.md`

</details>

### 🔄 v0.8 STREAM Composer GUI (Phases 33-44) — ACTIVE

- [x] **Phase 33: Project Scaffold** — Tauri 2 + React + ReactFlow skeleton; component metadata registry; dev environment verified (completed 2026-04-01)
- [x] **Phase 34: Canvas & Node Editor** — Drag-from-toolbox, custom node components with FlowPort handles, edge drawing, zoom/pan/minimap, undo/redo (completed 2026-04-01)
- [x] **Phase 35: Parameter Editing** — Sidebar form generation from component schema; PipeGeometry picker; Pump mode toggle; scalar validation; rename (completed 2026-04-02)
- [x] **Phase 35.1: Correlation Picker** — Extend registry with factory sub-parameter schemas; sidebar dropdown for all HTC/friction correlations; factory correlations (regime_dependent, elenbaas_htc, maximal_htc) show nested sub-fields; capped at one level of nesting (completed 2026-04-02)
- [x] **Phase 36: Code Generation** — Graph-to-Julia translator; BC editor; live code preview panel; export to .jl file (completed 2026-04-02)
- [x] **Phase 37: Project Persistence** — Save/load .streamgui JSON; unsaved-changes guard; recent projects list (completed 2026-04-02)
- [x] **Phase 38: UI Design Pass** — shadcn/ui integration throughout; three-panel layout; component icons/colors; design contract and visual audit gates (completed 2026-04-03)
- [x] **Phase 39: Topology Validation** — Unconnected port warnings; missing pressure BC alert; missing driving element alert (completed 2026-04-03)
- [x] **Phase 40: Thermal Composition** — ChannelAndContacts ThermalPort array visualization; HeatDiffusion connections; composition helper code generation (completed 2026-04-03)
- [x] **Phase 41: Layered Canvas** — Hydraulic and thermal content on separate toggleable layers; reduces visual clutter when both are present (completed 2026-04-03)
- [ ] **Phase 42: Edge & Path Visual Overhaul** — Correct arrowheads; clean loop routing; thermal edge clarity; cursor glitch fix; rename counter bug fix
- [ ] **Phase 43: UI Polish & Redesign** — Professional polish pass: nodes, buttons, sidebar, spacing, field descriptions, resizable panels
- [ ] **Phase 44: Light/Dark Mode** — Theme toggle in settings menu; all surfaces correct in both modes

## Phase Details

### Phase 33: Project Scaffold
**Goal**: Developer and user can launch the STREAM Composer desktop app; component metadata registry defines all STREAM.jl components
**Depends on**: Nothing (first GUI phase; independent of v0.7)
**Requirements**: SCAF-01, SCAF-02, SCAF-03, SCAF-04, SCAF-05
**Success Criteria** (what must be TRUE):
  1. `npm run tauri dev` starts the app in a browser/webview within 10 seconds
  2. ReactFlow canvas renders at center of screen with no console errors
  3. Component registry JSON contains all 12 STREAM.jl components with correct port definitions
  4. App bundles to a distributable installer on at least one platform
**Plans:** 4/4 plans complete

Plans:
- [x] 33-01-PLAN.md — Tauri 2 scaffold with React, ReactFlow, Zustand, Vitest, shadcn, three-panel layout
- [x] 33-02-PLAN.md — Component metadata registry JSON (12 components) with TypeScript types and tests
- [ ] 33-03-PLAN.md — Human-verify: desktop app launches with three-panel layout
- [ ] 33-04-PLAN.md — Human-verify: Tauri build produces native installer (SCAF-02)

**UI hint**: yes

### Phase 34: Canvas & Node Editor
**Goal**: Users can visually build hydraulic system topologies by placing components and wiring them together
**Depends on**: Phase 33
**Requirements**: CANV-01, CANV-02, CANV-03, CANV-04, CANV-05, CANV-06, CANV-07
**Success Criteria** (what must be TRUE):
  1. User can drag Pump from toolbox; it appears as a node on canvas
  2. User can connect Pump.port_out to Channel.port_in with a visible edge
  3. User can delete a node and its connected edges are removed
  4. Undo/redo reverses at least 10 sequential operations correctly
**Plans:** 3/3 plans complete

Plans:
- [x] 34-01-PLAN.md — Install zundo, extend store with temporal + actions, create StreamNode and ToolboxItem components
- [x] 34-02-PLAN.md — Wire CanvasPanel and ToolboxPanel, create unit tests for store and StreamNode
- [ ] 34-03-PLAN.md — Human-verify: canvas drag-drop, edge drawing, delete, undo/redo

**UI hint**: yes

### Phase 35: Parameter Editing
**Goal**: Users can configure every component parameter through a sidebar form with validation and mode-specific fields
**Depends on**: Phase 34
**Requirements**: PARA-01, PARA-02, PARA-03, PARA-04, PARA-05, PARA-06
**Success Criteria** (what must be TRUE):
  1. Clicking a Channel node opens sidebar showing L, Dh, n, and PipeGeometry fields
  2. Changing n from 5 to 10 is reflected immediately; no stale value remains
  3. Pump sidebar shows dP_pump field in fixed-dP mode; toggling to fixed-mdot replaces it with mdot0
  4. Entering letters in a numeric field shows a visible error, not a crash
**Plans**: 3 plans

Plans:
- [x] 35-01-PLAN.md — Extend registry schema, store (updateNodeParams, defaults), validation lib, canvas selection wiring, shadcn install
- [x] 35-02-PLAN.md — Build sidebar component tree (SidebarPanel, ParameterForm, NumericField, PipeGeometryPicker, FunctionSelect, ModeToggle)
- [x] 35-03-PLAN.md — Human-verify: parameter editing sidebar across all component types

**UI hint**: yes

### Phase 35.1: Correlation Picker
**Goal**: Users can select any available HTC or friction correlation from a dropdown, including factory correlations that require sub-parameters
**Depends on**: Phase 35
**Requirements**: (no PARA- requirement yet — emerged from Phase 35 discuss-phase)
**Success Criteria** (what must be TRUE):
  1. Channel sidebar shows a dropdown for htc_correlation with all available HTC correlations (dittus_boelter, constant_Nusselt, elenbaas_htc, regime_dependent, maximal_htc)
  2. Selecting regime_dependent reveals sub-fields: htc_forced dropdown (simple closures only), htc_natural dropdown (simple closures only), threshold Float
  3. Selecting elenbaas_htc reveals sub-fields: b, L, Dh (Real), g (Real, default 9.80665)
  4. Selecting a simple closure (dittus_boelter, constant_Nusselt) shows no sub-fields
  5. Code generation (Phase 36) emits correct nested factory call: `htc_correlation=regime_dependent(htc_forced=dittus_boelter, htc_natural=elenbaas_htc(b=0.003, L=0.6, Dh=0.0025))`
**Plans**: TBD
**UI hint**: yes

**Design decisions captured during Phase 35 discuss-phase (2026-04-02):**
- Phase 35 shows factory correlations grayed-out in the dropdown with tooltip "factory correlation editing coming soon" — not interactive
- Phase 35.1 activates them by adding sub-parameter schemas to the registry and rendering nested form sections
- **Registry schema extension needed**: add `options` field to Function-type parameters in `components.json`. Each option entry has: `id` (Julia function name), `label` (display name), `kind` ("simple" | "factory"), and for factory kind: `sub_parameters[]` array using the same Parameter schema as component parameters
- **Recursion depth cap**: factory sub-dropdowns only offer simple closures (no further factories). This covers 99% of real use cases. `regime_dependent.htc_forced` and `regime_dependent.htc_natural` can be dittus_boelter/constant_Nusselt/elenbaas_htc but NOT another regime_dependent. `maximal_htc.htc1`/`htc2` same rule.
- **Code gen contract**: Phase 36 must handle Function-type params specially — emit as bare Julia identifier for simple closures (`dittus_boelter`), emit as factory call for factories (`elenbaas_htc(b=0.003, L=0.6, Dh=0.0025, g=9.80665)`). Phase 35.1 stores factory selection + sub-param values in `parameters` map as a structured object, not a flat string.
- **Known factory correlations and their sub-params**:
  - `regime_dependent(htc_forced, htc_natural; threshold=1.0)` — htc_forced/htc_natural: closure selector (simple only); threshold: Real
  - `elenbaas_htc(; b, L, Dh, g=9.80665)` — b: Real (channel gap, m); L: Real (channel length, m); Dh: Real (hydraulic diameter, m); g: Real (gravity, m/s², default 9.80665)
  - `maximal_htc(htc1, htc2)` — htc1/htc2: closure selectors (simple only)
- **Simple closures** (directly usable, no sub-params): `dittus_boelter`, `constant_Nusselt` (HTC); `blasius_friction`, `laminar_friction` (friction)
- `marco_han_nusselt` — check if this is exported before adding to picker list
- **Open design question for discuss-phase**: How should `param.description` be surfaced in the sidebar? Options: (a) shadcn Tooltip on the label (hover), (b) secondary text below the label, (c) info icon next to the label. Decision must be made in 35.1 discuss-phase and applied consistently from 35.1 forward.

### Phase 36: Code Generation
**Goal**: Users can view and export valid STREAM.jl Julia code generated from their canvas topology
**Depends on**: Phase 35
**Requirements**: CODE-01, CODE-02, CODE-03, CODE-04, CODE-05, CODE-06, CODE-07
**Success Criteria** (what must be TRUE):
  1. Canvas with Pump-HeatExchanger-Channel-Pump loop generates valid STREAM.jl code
  2. Generated code compiles without errors when pasted into a Julia REPL with `using STREAM`
  3. Pressing Export opens native file dialog; saved file contains the generated code
  4. BC panel allows adding `pump.port_in.P ~ 1.0e5`; generated code includes it
**Plans:** 3/3 plans complete

Plans:
- [x] 36-01-PLAN.md — Pure code generator function with comprehensive unit tests (TDD)
- [x] 36-02-PLAN.md — Store BC state, Tauri plugins, UI components (Toolbar, BottomPanel, CodePreview, BCPanel)
- [ ] 36-03-PLAN.md — Human-verify: code preview, BC editing, export

**UI hint**: yes

### Phase 37: Project Persistence
**Goal**: Users can save, load, and resume their work across sessions without data loss
**Depends on**: Phase 36
**Requirements**: PERS-01, PERS-02, PERS-03, PERS-04
**Success Criteria** (what must be TRUE):
  1. Ctrl+S saves project; reloading the app and opening the file restores all nodes, edges, positions, and parameters exactly
  2. Closing the app with unsaved changes shows a confirmation dialog
  3. Recent Projects list shows last 5 files by name
**Plans:** 3/3 plans complete

Plans:
- [x] 37-01-PLAN.md — projectIO pure functions + store extensions (isDirty, file actions, recent files) + Tauri permissions
- [x] 37-02-PLAN.md — FileMenu dropdown, WelcomeOverlay, keyboard shortcuts, window title sync, close guard
- [x] 37-03-PLAN.md — Human-verify: save/load round-trip, dirty indicator, recent projects, close guard

**UI hint**: yes

### Phase 38: UI Design Pass
**Goal**: Every UI surface uses shadcn/ui design system with consistent visual language and quality-gated process
**Depends on**: Phase 37
**Requirements**: DSGN-01, DSGN-02, DSGN-03, DSGN-04, DSGN-05
**Success Criteria** (what must be TRUE):
  1. Every UI element uses shadcn/ui primitives (no raw `<button>` or `<input>` with inline styles)
  2. UI-SPEC.md design contract was written and approved before Phase 38 coding began
  3. UI-REVIEW.md audit was completed after Phase 38 coding; no BLOCK verdicts
  4. Toolbox icons are distinct (not identical placeholder boxes)
**Plans**: 3 plans

Plans:
- [x] 38-01-PLAN.md — Icon map, category colors, StreamNode + ToolboxItem visual redesign
- [x] 38-02-PLAN.md — Panel collapse/resize behavior, store additions, shadcn audit
- [ ] 38-03-PLAN.md — Human-verify: visual verification of all DSGN requirements
**UI hint**: yes

### Phase 39: Topology Validation
**Goal**: Users receive immediate visual feedback when their system topology has structural problems
**Depends on**: Phase 34
**Requirements**: VALD-01, VALD-02, VALD-03
**Success Criteria** (what must be TRUE):
  1. A Channel with port_in unconnected shows a red/orange visual indicator on the canvas node
  2. A complete loop with no Pump shows an alert banner "No driving element detected"
  3. A complete loop missing a pressure anchor shows a separate alert banner
  4. Alerts disappear when the condition is resolved
**Plans**: 3 plans

Plans:
- [x] 39-01-PLAN.md — Validation logic (pure function + tests) and store integration
- [x] 39-02-PLAN.md — ValidationDialog component, StreamNode error ring, export/save gates
- [ ] 39-03-PLAN.md — Human-verify: topology validation visual and functional verification
**UI hint**: yes

### Phase 40: Thermal Composition
**Goal**: Users can build and wire thermal fuel assembly topologies with array-port connections and smart code generation
**Depends on**: Phase 36, Phase 34
**Requirements**: THERM-01, THERM-02, THERM-03
**Success Criteria** (what must be TRUE):
  1. ChannelAndContacts(n=4) node shows 4 thermal_left and 4 thermal_right port handles
  2. Connecting a HeatDiffusion left-side port to thermal_left[2] is possible and draws a typed edge
  3. Symmetric_plate topology (HeatDiffusion between two ChannelAndContacts) generates `symmetric_plate(cac1, fuel)` call in output code
**Plans**: 2 plans

Plans:
- [x] 40-01-PLAN.md — ThermalPort handle rendering, connection enforcement, amber dashed edge styling
- [x] 40-02-PLAN.md — Thermal topology detection and composition helper code generation
**UI hint**: yes

### Phase 41: Layered Canvas
**Goal**: Hydraulic and thermal canvas content live on separate toggleable layers so the canvas stays readable when both are present
**Depends on**: Phase 40
**Requirements**: LAYR-01, LAYR-02, LAYR-03, LAYR-04, LAYR-05
**Success Criteria** (what must be TRUE):
  1. A toolbar layer toggle lets the user switch between Hydraulic, Thermal, and Both views
  2. In Hydraulic view, thermal nodes/edges are visually subordinated (dimmed or hidden)
  3. In Thermal view, hydraulic nodes/edges are visually subordinated
  4. Components that belong to both layers (e.g. ChannelAndContacts) remain visible in both layer views
  5. Layer selection is persisted with the project in .streamgui
**Plans**: 2 plans

Plans:
- [x] 41-01-PLAN.md — Layer detection utility, store activeLayer state, projectIO v2 schema
- [x] 41-02-PLAN.md — Toolbar toggle, toolbox filtering, canvas dimming, handle dimming, Tab cycling

**UI hint**: yes

### Phase 42: Edge & Path Visual Overhaul
**Goal**: Hydraulic and thermal edges look clean — correct arrowheads, sensible routing for parallel edges, no clipping artifacts
**Depends on**: Phase 41
**Requirements**: TBD
**Success Criteria** (what must be TRUE):
  1. Arrowheads are visible and correctly positioned at edge endpoints (not hidden behind node borders)
  2. A Pump→Channel→Pump loop shows two distinct, non-overlapping edge routes
  3. Thermal (amber) edges route cleanly and are visually distinct from hydraulic edges
  4. Edge drag handles show correct cursor state (no cursor disappearance)
  5. Rename counter is correctly reconstructed on project load even for custom-named nodes
**Plans**: TBD
**UI hint**: yes

### Phase 43: UI Polish & Redesign
**Goal**: Every surface of the GUI looks intentional and professional — clean spacing, consistent visual hierarchy, no rough edges
**Depends on**: Phase 42
**Requirements**: TBD
**Success Criteria** (what must be TRUE):
  1. All buttons have consistent sizing, padding, and hover states
  2. ThermalPort amber diamond handles are visually clean and proportional
  3. Sidebar shows a brief description for each parameter field (tooltip or inline text)
  4. Panel dividers are draggable (canvas↔sidebar, canvas↔bottom panel)
  5. A developer familiar with shadcn/ui would not immediately notice rough edges on casual inspection
**Plans**: TBD
**UI hint**: yes

### Phase 44: Light/Dark Mode
**Goal**: Users can toggle between light and dark themes via a settings menu; all surfaces look correct in both modes
**Depends on**: Phase 43
**Requirements**: TBD
**Success Criteria** (what must be TRUE):
  1. A settings button (gear icon) opens a settings panel or dropdown
  2. Light/Dark/System options are available; selection persists across sessions
  3. All shadcn/ui components display correctly in both themes
  4. ReactFlow canvas background and node colors adapt to the active theme
  5. Amber thermal edges and red error rings remain legible in both themes
**Plans**: TBD
**UI hint**: yes

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Foundation | v0.1 | 3/3 | Complete | 2026-03-12 |
| 2. Components | v0.1 | 4/4 | Complete | 2026-03-12 |
| 3. Integration and Validation | v0.1 | 3/3 | Complete | 2026-03-12 |
| 4. Tech Debt Cleanup | v0.1 | 1/1 | Complete | 2026-03-12 |
| 5. Nyquist Validation | v0.1 | 1/1 | Complete | 2026-03-12 |
| 6. Gravity Validation | v0.2 | 1/1 | Complete | 2026-03-13 |
| 7. Network Architecture | v0.2 | 2/2 | Complete | 2026-03-13 |
| 8. Inertia and HeatExchanger | v0.2 | 2/2 | Complete | 2026-03-13 |
| 9. ChannelAndContacts | v0.2 | 2/2 | Complete | 2026-03-13 |
| 10. ChannelAndContacts Two-Sided Upgrade | v0.3 | 2/2 | Complete | 2026-03-13 |
| 11. HeatDiffusion Component | v0.3 | 2/2 | Complete | 2026-03-14 |
| 12. MTR Validation | v0.3 | 2/2 | Complete | 2026-03-14 |
| 12.1. PipeGeometry Struct | v0.3 | 2/2 | Complete | 2026-03-14 |
| 13. Physics Foundation | v0.4 | 2/2 | Complete | 2026-03-14 |
| 14. Laminar Correlations | v0.4 | 2/2 | Complete | 2026-03-14 |
| 15. Composition Helpers & QoL | v0.4 | 2/2 | Complete | 2026-03-15 |
| 16. Validation | v0.4 | 1/1 | Complete | 2026-03-15 |
| 17. File Structure Reorganization | v0.5 | 2/2 | Complete | 2026-03-16 |
| 18. Test Split and API Cleanup | v0.5 | 2/2 | Complete | 2026-03-16 |
| 19. Docstrings, CLAUDE.md, and Final Polish | v0.5 | 2/2 | Complete | 2026-03-16 |
| 20. Sign Safety | v0.6 | 2/2 | Complete | 2026-03-17 |
| 21. Fluid Properties & Natural Convection | v0.6 | 2/2 | Complete | 2026-03-17 |
| 22. Time-Varying Pump | v0.6 | 2/2 | Complete | 2026-03-18 |
| 23. Flapper & Solver Events | v0.6 | 2/2 | Complete | 2026-03-20 |
| 24. Loss-of-Flow Validation | v0.6 | 1/1 | Complete | 2026-03-21 |
| 24.1. Bypass LOF Topology | v0.6 | 2/2 | Complete | 2026-03-21 |
| 25. Argument Structure Audit | v0.6 | 1/1 | Complete | 2026-03-26 |
| 26. NC Regime HTC + LOF Cleanup | v0.6 | 2/2 | Complete | 2026-03-26 |
| 27. Pressure Field | v0.7 | 2/2 | Complete | 2026-03-28 |
| 27.1. Channel Momentum & Inertia | v0.7 | 3/3 | Complete | 2026-03-29 |
| 28. Subcooled Boiling | v0.7 | 2/2 | Complete | 2026-03-30 |
| 29. Threshold Analysis | v0.7 | 2/2 | Complete    | 2026-03-31 |
| 30. HTC & Friction Completions | v0.7 | 2/2 | Complete | 2026-04-01 |
| 31. Write Phase 27 Verification Document | v0.7 | 1/1 | Complete | 2026-04-01 |
| 32. THRS-09 & Phase 30 Integration Hardening | v0.7 | 1/1 | Complete | 2026-04-01 |
| 33. Project Scaffold | v0.8 | 4/4 | Complete | 2026-04-01 |
| 34. Canvas & Node Editor | v0.8 | 3/3 | Complete | 2026-04-01 |
| 35. Parameter Editing | v0.8 | 3/3 | Complete | 2026-04-02 |
| 35.1. Correlation Picker | v0.8 | 4/4 | Complete | 2026-04-02 |
| 36. Code Generation | v0.8 | 3/3 | Complete | 2026-04-02 |
| 37. Project Persistence | v0.8 | 3/3 | Complete | 2026-04-02 |
| 38. UI Design Pass | v0.8 | 3/3 | Complete | 2026-04-03 |
| 39. Topology Validation | v0.8 | 3/3 | Complete | 2026-04-03 |
| 40. Thermal Composition | v0.8 | 2/2 | Complete | 2026-04-03 |
| 41. Layered Canvas | v0.8 | 2/2 | Complete   | 2026-04-03 |
| 42. Edge & Path Visual Overhaul | v0.8 | 0/? | Planned | — |
| 43. UI Polish & Redesign | v0.8 | 0/? | Planned | — |
| 44. Light/Dark Mode | v0.8 | 0/? | Planned | — |

---

*Created: 2026-03-12*
*Updated: 2026-04-03 — Phase 41 planned (2 plans, LAYR-01..05 requirements defined)*
