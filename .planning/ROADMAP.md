# ROADMAP: STREAM.jl

## Milestones

- ✅ **v0.1 MVP** — Phases 1-5 (shipped 2026-03-13)
- ✅ **v0.2 Component & Network Expansion** — Phases 6-9 (shipped 2026-03-13)
- ✅ **v0.3 HeatDiffusion** — Phases 10-12.1 (shipped 2026-03-14)
- ✅ **v0.4 Composability & Physics** — Phases 13-16 (shipped 2026-03-16)
- ✅ **v0.5 Code Quality** — Phases 17-19 (shipped 2026-03-16)
- ✅ **v0.6 Flow Reversal Systems** — Phases 20-26 (shipped 2026-03-27)
- ✅ **v0.7 Safety Physics & Pressure Field** — Phases 27-32 (shipped 2026-04-01)
- 🔄 **v0.8 STREAM Composer GUI** — Phases 33-40 (active)

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

### 🔄 v0.8 STREAM Composer GUI (Phases 33-40) — ACTIVE

- [ ] **Phase 33: Project Scaffold** — Tauri 2 + React + ReactFlow skeleton; component metadata registry; dev environment verified
- [ ] **Phase 34: Canvas & Node Editor** — Drag-from-toolbox, custom node components with FlowPort handles, edge drawing, zoom/pan/minimap, undo/redo
- [ ] **Phase 35: Parameter Editing** — Sidebar form generation from component schema; PipeGeometry picker; Pump mode toggle; scalar validation; rename
- [ ] **Phase 36: Code Generation** — Graph-to-Julia translator; BC editor; live code preview panel; export to .jl file
- [ ] **Phase 37: Project Persistence** — Save/load .streamgui JSON; unsaved-changes guard; recent projects list
- [ ] **Phase 38: UI Design Pass** — shadcn/ui integration throughout; three-panel layout; component icons/colors; design contract and visual audit gates
- [ ] **Phase 39: Topology Validation** — Unconnected port warnings; missing pressure BC alert; missing driving element alert
- [ ] **Phase 40: Thermal Composition** — ChannelAndContacts ThermalPort array visualization; HeatDiffusion connections; composition helper code generation

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
**Plans:** 3 plans

Plans:
- [ ] 33-01-PLAN.md — Tauri 2 scaffold with React, ReactFlow, Zustand, Vitest, shadcn, three-panel layout
- [ ] 33-02-PLAN.md — Component metadata registry JSON (12 components) with TypeScript types and tests
- [ ] 33-03-PLAN.md — Human-verify: desktop app launches with three-panel layout

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
**Plans**: TBD
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
**Plans**: TBD
**UI hint**: yes

### Phase 36: Code Generation
**Goal**: Users can view and export valid STREAM.jl Julia code generated from their canvas topology
**Depends on**: Phase 35
**Requirements**: CODE-01, CODE-02, CODE-03, CODE-04, CODE-05, CODE-06, CODE-07
**Success Criteria** (what must be TRUE):
  1. Canvas with Pump-HeatExchanger-Channel-Pump loop generates valid STREAM.jl code
  2. Generated code compiles without errors when pasted into a Julia REPL with `using STREAM`
  3. Pressing Export opens native file dialog; saved file contains the generated code
  4. BC panel allows adding `pump.port_in.P ~ 1.0e5`; generated code includes it
**Plans**: TBD
**UI hint**: yes

### Phase 37: Project Persistence
**Goal**: Users can save, load, and resume their work across sessions without data loss
**Depends on**: Phase 36
**Requirements**: PERS-01, PERS-02, PERS-03, PERS-04
**Success Criteria** (what must be TRUE):
  1. Ctrl+S saves project; reloading the app and opening the file restores all nodes, edges, positions, and parameters exactly
  2. Closing the app with unsaved changes shows a confirmation dialog
  3. Recent Projects list shows last 5 files by name
**Plans**: TBD
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
**Plans**: TBD
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
**Plans**: TBD
**UI hint**: yes

### Phase 40: Thermal Composition
**Goal**: Users can build and wire thermal fuel assembly topologies with array-port connections and smart code generation
**Depends on**: Phase 36, Phase 34
**Requirements**: THERM-01, THERM-02, THERM-03
**Success Criteria** (what must be TRUE):
  1. ChannelAndContacts(n=4) node shows 4 thermal_left and 4 thermal_right port handles
  2. Connecting a HeatDiffusion left-side port to thermal_left[2] is possible and draws a typed edge
  3. Symmetric_plate topology (HeatDiffusion between two ChannelAndContacts) generates `symmetric_plate(cac1, fuel)` call in output code
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
| 33. Project Scaffold | v0.8 | 0/3 | Not started | — |
| 34. Canvas & Node Editor | v0.8 | 0/? | Not started | — |
| 35. Parameter Editing | v0.8 | 0/? | Not started | — |
| 36. Code Generation | v0.8 | 0/? | Not started | — |
| 37. Project Persistence | v0.8 | 0/? | Not started | — |
| 38. UI Design Pass | v0.8 | 0/? | Not started | — |
| 39. Topology Validation | v0.8 | 0/? | Not started | — |
| 40. Thermal Composition | v0.8 | 0/? | Not started | — |

---

*Created: 2026-03-12*
*Updated: 2026-04-01 — Phase 33 planned: 3 plans in 2 waves*
