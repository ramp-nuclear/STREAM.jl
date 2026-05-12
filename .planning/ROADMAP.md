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
- [ ] **Phase 61: Registry audit + rewrite for v1.1** — `gui/src/registry/components.json` rewritten against v1.1 source. Add `WallTemperature`, `HeatFluxSource`, `PointKinetics`, `ReactivityController`. Collapse correlation sub-param trees per geom-first. Add `scope` field per parameter (constructor_kwarg vs external_input) for Properties-tab vs BCs-tab split. Bump `stream_version` to `1.1.0`.
- [ ] **Phase 62: Resources panel architecture** — Navigator restructure to `Project → Model Options + Resources + Components`. Foreign-key UUID references. Save format (`.scp`). Reference picker UX. Sources toolbox category.
- [ ] **Phase 63: BCs tab + value-source components in GUI** — Properties tab vs BCs tab separation. Five BC modes (value / profile / function / mark-in-code / driven-by-source-block). `WallTemperature` and `HeatFluxSource` toolbox entries. Dashed BC edge style. Bidirectional sync between BCs tab and canvas connections.
- [ ] **Phase 64: Connection routing** — Per-port autoflip for FlowPorts with asymmetric same-side placement. Independent axis-flip for thermal-pair ports on CAC/HD. Anti-parallel offset for bidirectional pairs as polish hook.
- [ ] **Phase 65: Interaction model overhaul** — Left-marquee selection, right-click drag pan, right-click no-drag context menu. Edge deletion (Del/Backspace + right-click). Copy/Cut/Paste/Duplicate (Ctrl+C/X/V/D) with smart-parse-and-increment naming. Reset-to-empty rule for property fields. Snap-to-grid toggle. AutoRecover sidecar snapshot mechanism.
- [ ] **Phase 66: Code preview rework** — Structured `CodeSection[]` output replacing flat string code-gen. Section blocks (Imports / Resources / Components / Composition / Main). Bidirectional traceability (code-hover → canvas-highlight; canvas-select → explicit code-jump). Click-to-pin sections. Copy + Export buttons in code panel toolbar. Hand-rolled formatting rules.
- [ ] **Phase 67: Custom titlebar** — Tauri `decorations: false` + custom HTML titlebar. Integrated File/Edit/View/Help menubar, app icon, project name, dirty dot (left); min/max/close buttons (right). Cross-platform consistency.
- [ ] **Phase 68: Layers system overhaul** — Four-layer taxonomy (Hydraulic / Thermal / Sources / Reactor Physics). Independent checkbox toggles. Floating Layers chip top-right of canvas with layer-state color indicators. Hide-vs-dim setting. Off-layer locked (non-interactive). Non-clunky layer-aware connect tool.
- [ ] **Phase 69: Command palette (jump-only)** — Ctrl+P fuzzy search across component instance names + Resource names. Focus-on-canvas for components, focus-in-navigator for Resources. No action invocation in v1.
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
**Plans:** 3/5 plans executed
- [x] 61-01-PLAN.md (Wave 1) — Schema + types reshape: bump versions, extend types.ts with v1.1 vocabulary (external_inputs, type_union, BCPort, etc.)
- [x] 61-02-PLAN.md (Wave 2, depends on 61-01) — Channel-family + HD rewrite (Channel, CHF, CAC, HD entries)
- [x] 61-03-PLAN.md (Wave 3, depends on 61-02) — Add WallTemperature, HeatFluxSource, PointKinetics, ReactivityController + register icons
- [ ] 61-04-PLAN.md (Wave 4, depends on 61-03) — Re-audit unchanged components (Pump, Flapper, etc.) + global legacy port-key sweep
- [ ] 61-05-PLAN.md (Wave 5, depends on 61-04) — Update tests + reconcile downstream consumers + human-verified GUI smoke (HAS CHECKPOINT)

### Phase 62: Resources panel architecture

**Goal:** The single biggest architectural shift in this milestone. Components no longer carry inline geometry/power-shape values; they reference named, definable, reusable model-level Resources by stable UUID. Navigator gains Model Options (singleton) and Resources branches alongside Components.

**Design-decisions reference:** Section 3.2.
**Depends on:** Phase 61 (registry must support resource-ref shape).
**Plans:** TBD via `/gsd:plan-phase`.

### Phase 63: BCs tab + value-source components in GUI

**Goal:** Split the property panel into Properties tab (constructor kwargs) and BCs tab (external-input variables). BCs tab supports five modes per field: scalar value, preset profile, imported profile, "mark in code for later," and "driven by source block." `WallTemperature` and `HeatFluxSource` toolbox entries (the value-source components from v1.1). Distinct dashed-edge BC connection style. Bidirectional sync between BCs tab dropdown selection and the canvas connection.

**Design-decisions reference:** Section 3.10, Section 3.11.
**Depends on:** Phase 62.
**Plans:** TBD via `/gsd:plan-phase`.

### Phase 64: Connection routing

**Goal:** Solve the connection-arrow ugliness verified in the example_*.png screenshots. Per-port autoflip moves each FlowPort handle to the side facing its connected neighbor. Asymmetric same-side placement disambiguates when both ports of a component end up on the same edge. Thermal-port-pair axis-flip for CAC/HD (left/right or top/bottom). Optional polish hook for anti-parallel offset of bidirectional pairs.

**Design-decisions reference:** Section 3.3, Section 3.4.
**Depends on:** Phase 62.
**Plans:** TBD via `/gsd:plan-phase`.

### Phase 65: Interaction model overhaul

**Goal:** Rewire the canvas interaction model from v0.8's ReactFlow defaults. Left-marquee selection + right-pan + right-click context menu (per drawio convention). Edge deletion. Copy/paste/cut/duplicate with smart-name-increment. Reset-to-empty for property fields. Snap-to-grid toggle (Settings + canvas overlay). AutoRecover (sidecar snapshot, OS temp dir, prompt-on-next-launch-after-crash).

**Design-decisions reference:** Section 3.5.
**Depends on:** —.
**Plans:** TBD via `/gsd:plan-phase`.

### Phase 66: Code preview rework

**Goal:** Refactor code generator from flat string output to structured `CodeSection[]` output with source-UUID tracking. Build the section-block Code Preview UI with hover-to-highlight on canvas, click-to-pin sections, copy + export buttons inline in the panel, and explicit "jump to code" from canvas selection.

**Design-decisions reference:** Section 3.11 (code-gen impact), plus the code-tab rework discussion captured in the conversation lineage.
**Depends on:** Phase 62 (resources are part of generated sections).
**Plans:** TBD via `/gsd:plan-phase`.

### Phase 67: Custom titlebar

**Goal:** Replace OS chrome with a custom Tauri titlebar to fix WSLg ugliness and get cross-platform consistency. Integrated menubar in the titlebar to save vertical space.

**Design-decisions reference:** Section 3.6.
**Depends on:** —.
**Plans:** TBD via `/gsd:plan-phase`.

### Phase 68: Layers system overhaul

**Goal:** Four-layer taxonomy (Hydraulic / Thermal / Sources / Reactor Physics) with independent checkbox visibility. Floating chip top-right of canvas with layer-state color squares. Hide-vs-dim user preference. Off-layer locked. Forgiving layer-aware connect tool that auto-enables relevant layers rather than blocking.

**Design-decisions reference:** Section 3.13.
**Depends on:** Phase 62 (Sources layer requires Sources category to exist).
**Plans:** TBD via `/gsd:plan-phase`.

### Phase 69: Command palette (jump-only)

**Goal:** Ctrl+P fuzzy search restricted to navigation use: jump-to-component-by-name and jump-to-resource. No action invocation in v1. Components focus the canvas + select; Resources focus the navigator + open property panel.

**Design-decisions reference:** Section 3.7.
**Depends on:** Phase 62.
**Plans:** TBD via `/gsd:plan-phase`.

### Phase 70: Presets and templates

**Goal:** Reusable component-bundle templates. `.scpr` file format (slimmed-down version of `.scp`). "Save selection as preset" right-click + File menu entry. "Load preset" via File menu + Presets toolbox category. No identity (copy-paste templates per issue #14 resolution). Forward-compatible to passive-identity if real usage demands it later.

**Design-decisions reference:** Section 3.14.
**Depends on:** Phase 62.
**Plans:** TBD via `/gsd:plan-phase`.

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
| 61. Registry audit + rewrite for v1.1                | 3/5 | In Progress|  |
| 62. Resources panel architecture                     | 0/TBD | Planned | — |
| 63. BCs tab + value-source components in GUI         | 0/TBD | Planned | — |
| 64. Connection routing                               | 0/TBD | Planned | — |
| 65. Interaction model overhaul                       | 0/TBD | Planned | — |
| 66. Code preview rework                              | 0/TBD | Planned | — |
| 67. Custom titlebar                                  | 0/TBD | Planned | — |
| 68. Layers system overhaul                           | 0/TBD | Planned | — |
| 69. Command palette (jump-only)                      | 0/TBD | Planned | — |
| 70. Presets and templates                            | 0/TBD | Planned | — |
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
