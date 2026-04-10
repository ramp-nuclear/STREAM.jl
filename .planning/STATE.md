---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: Open-Source Release
status: executing
stopped_at: Phase 51 context gathered
last_updated: "2026-04-10T16:07:31.196Z"
last_activity: 2026-04-10
progress:
  total_phases: 1
  completed_phases: 1
  total_plans: 2
  completed_plans: 2
  percent: 100
---

# STATE: STREAM.jl

*Project memory — updated at the start and end of every session*

---

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-04)

**Core value:** A Julia MTK-based thermal-hydraulics library that matches Python STREAM results, proving the architecture is sound before large-scale porting begins.
**Current focus:** Phase 50 — open-source-readiness
**Python STREAM reference:** ~/projects/STREAM

**Roadmap summary:**

- v0.8 (complete): Phases 33-44 — STREAM Composer GUI (shipped 2026-04-04)
- v0.9 (active): Phases 45+ — Point Kinetics & Reactor Control

---

## Current Position

Phase: 50 (open-source-readiness) — EXECUTING
Plan: 1 of 5
Status: Executing Phase 50
Last activity: 2026-04-10

## Performance Metrics

**v0.6 velocity reference:** 14 plans completed

| Phase | Plans | Avg/Plan |
|-------|-------|----------|
| 26 NC Regime HTC + LOF Cleanup | 2 | ~35 min |
| 25 Argument Structure Audit | 1 | ~15 min |
| 24.1 Bypass LOF Topology | 2 | ~33 min |
| 24 Loss-of-Flow Validation | 1 | ~90 min |

*Updated after each plan completion*

---
| Phase 20-sign-safety P01 | 2 | 2 tasks | 2 files |
| Phase 20 P02 | 100 | 2 tasks | 4 files |
| Phase 21 P01 | 27 | 2 tasks | 7 files |
| Phase 21 P02 | 10 | 2 tasks | 2 files |
| Phase 22-time-varying-pump P01 | 7 | 2 tasks | 3 files |
| Phase 22-time-varying-pump P02 | 32 | 2 tasks | 6 files |
| Phase 23-flapper-solver-events P01 | 9 | 2 tasks | 4 files |
| Phase 23 P02 | 21 | 1 tasks | 1 files |
| Phase 24-loss-of-flow P01 | 90 | 2 tasks | 4 files |
| Phase 24.1 P01 | 12 | 2 tasks | 4 files |
| Phase 24.1 P02 | 55 | 2 tasks | 4 files |
| Phase 25 P01 | 15 | 2 tasks | 17 files |
| Phase 26-nc-regime-htc-lof-cleanup P01 | 10 | 2 tasks | 4 files |
| Phase 26 P02 | 60 | 2 tasks | 6 files |
| Phase 28-subcooled-boiling P01 | 5 | 2 tasks | 4 files |
| Phase 28 P02 | 51 | 2 tasks | 4 files |
| Phase 29 P01 | 30 | 2 tasks | 6 files |
| Phase 29-threshold-analysis P02 | 18 | 2 tasks | 3 files |
| Phase 33 P01 | 7 | 2 tasks | 44 files |
| Phase 33 P02 | 4 | 2 tasks | 5 files |
| Phase 34 P01 | 1 | 2 tasks | 5 files |
| Phase 34 P02 | 3 | 3 tasks | 6 files |
| Phase 35 P01 | 284 | 2 tasks | 16 files |
| Phase 35 P02 | 5 | 3 tasks | 14 files |
| Phase 35.1 P1 | 8 | 2 tasks | 2 files |
| Phase 35.1 P2 | 5 | 2 tasks | 1 files |
| Phase 35.1 P3 | 5 | 3 tasks | 3 files |
| Phase 35.1 P4 | 3 | 3 tasks | 5 files |
| Phase 36 P02 | 4 | 2 tasks | 11 files |
| Phase 37 P01 | 3 | 2 tasks | 5 files |
| Phase 37 P02 | 525623 | 2 tasks | 6 files |
| Phase 38 P02 | 3 | 2 tasks | 6 files |
| Phase 39-topology-validation P02 | 163 | 2 tasks | 5 files |
| Phase 40 P02 | 209 | 1 tasks | 2 files |
| Phase 41-layered-canvas P01 | 3 | 2 tasks | 6 files |
| Phase 41-layered-canvas P02 | 3 | 2 tasks | 6 files |
| Phase 42-edge-path-visual-overhaul P01 | 197 | 2 tasks | 2 files |
| Phase 43 P01 | 1 | 2 tasks | 3 files |
| Phase 43 P02 | 96 | 2 tasks | 4 files |
| Phase 44-light-dark-mode P01 | 2 | 2 tasks | 6 files |
| Phase 44-light-dark-mode P02 | 15 | 2 tasks | 3 files |
| Phase 45-pointkinetics-bare-component P01 | - | 2 tasks | 2 files |
| Phase 45-pointkinetics-bare-component P02 | - | 2 tasks | 1 files |
| Phase 46-callable-control-reactivity P01 | 15 | 3 tasks | 2 files |
| Phase 46-callable-control-reactivity P02 | 25 | 2 tasks | 1 files |
| Phase 47 P02 | 35 | 2 tasks | 2 files |

## Accumulated Context

### Roadmap Evolution

- Phase 51 added: Julia Startup Performance & Reliable Sysimage — fix WSL2 sysimage build crashes, reduce TTFX for `using STREAM`, `mtkcompile`, and loop construction

### Key Decisions (v0.9 Point Kinetics)

- [v0.9 PK-01]: Callable MTK parameter pattern: `FType=typeof(fn)` at construction; `@parameters (fn::FType)(..)` variadic; used in equations as `fn(t)`. Matches Pump(dP_pump::Any) precedent from Phase 22.
- [v0.9 PK-02]: ReactivityController callable struct: `ctrl(t) = worth(ctrl, t)` allows passing ctrl directly as the MTK callable parameter without wrapper closure. FType = typeof(ctrl) captured at PointKinetics construction time.
- [v0.9 PK-03]: Additive rho composition (D-01): `rho_val + rho_c_fn(t) - beta_sum` for power ODE; `reactivity ~ rho_val + rho_c_fn(t)` for observed. Extends cleanly to Phase 47 temperature feedback.
- [v0.9 PK-04]: State-aware input reactivity signature: `(state, t_state, t) -> Float64` matches Python STREAM InputReactivity protocol. MTK callable parameter receives only `(t)` — RC forwards via worth(ctrl, t).
- [v0.9 PK-05]: Prompt-jump test window: sample at `t_step + Lambda/delta_rho` (not plan's 0.01s). At Lambda=5.4e-5, delta_rho=0.002: window = 0.027s. Sampling at 0.028s gives 0.08% error vs expected formula.
- [v0.9 PK-06]: op-dict uses `Pair{Any,Any}[]` for callable-parameter entries; `ssys.rho_c_fn => ctrl` binds the callable at solve time (D-10 from RESEARCH.md).
- [v0.9 TF-01]: scoped_comps kwarg in connect_temperature_feedback: when cac is wrapped in symmetric_plate(cac, fuel; name=:rods), its T vars are re-scoped to rods+cac+T. Pass scoped_comps=Dict(cac=>rods.cac) so feedback equations bind to the correct symbolic while pk.T_source_cac name stays from original nameof(cac).
- [v0.9 TF-02]: IC path after mtkcompile: compiled system IS the named system (ssys IS core). Variables are ssys.rods.cac.T, not ssys.core.rods.cac.T. Extra prefix causes KeyError.
- [v0.9 TF-03]: TF-07 fixture uses power=0.0 in HeatDiffusion — fixed background power warms channel before step insertion, causing P_max==P0 failure. Zero power keeps feedback=0 at t=0 so step reactivity can drive P above P0.

### Key Decisions (v0.8 GUI)

- [v0.8 EDGE-01]: Bidirectional pair detection matches on node IDs only (not handles) -- real loops use different port names (port_out->port_in) in each direction; enrichEdges is a pure exported function for testability
- [v0.8 SCAF-01]: Tailwind v4 + @tailwindcss/vite: npm create tauri-app installs Tailwind v4; shadcn init expects v3 config file. components.json and src/index.css created manually with v4 CSS variable design tokens (New York/Zinc style). Future `npx shadcn add [component]` works correctly with this setup.
- [v0.8 SCAF-01]: vitest --passWithNoTests in test script: Vitest exits code 1 when no test files exist; flag added so CI passes before registry tests added in Plan 02.
- [v0.8 SCAF-01]: tsconfig.json not tsconfig.app.json: Tauri react-ts template generates tsconfig.json + tsconfig.node.json; path aliases added to tsconfig.json directly.
- [v0.8 SCAF-01]: Zustand + ReactFlow integration pattern: store owns nodes/edges arrays; onNodesChange/onEdgesChange use applyNodeChanges/applyEdgeChanges; CanvasPanel reads from store via useStore hook.
- [v0.8 SCAF-02]: vitest default environment is node (not jsdom): jsdom has ESM incompatibility with html-encoding-sniffer on Node.js 18; React component tests in later phases should add @vitest-environment jsdom docblock per-file.
- [v0.8 SCAF-02]: Registry Parameter interface has positional: boolean field for Phase 36 code generation to distinguish @named macro positional vs keyword arg syntax.
- [v0.8 SCAF-02]: ChannelHeatFlux has no ThermalPort in the registry -- T_wall is a scalar Real parameter, not a port connection; _note field documents this in the JSON entry.
- [v0.8 35.1-4]: getByDisplayValue for inputMode=decimal inputs: NumericField uses inputMode not type=number so spinbutton ARIA role is not assigned; use getByDisplayValue on the default value string in tests.
- [v0.8 35.1-4]: getAllByRole combobox[0] for factory sub-field context: selecting factory option renders second FunctionSelect so there are multiple comboboxes in DOM; index [0] is always the top-level trigger.

### Key Decisions (carry-forward for v0.7)

- [v0.7 SCB-01]: max(dT, 0.0) inside ifelse() exponentiation prevents DomainError when dT < 0 (Julia ifelse evaluates both branches eagerly)
- [v0.7 SCB-04]: regime_dependent_q_scb is a factory (not direct function) to capture pressure at construction time, matching scb_correction closure contract
- [v0.7 ISCB-01]: skip_htc kwarg in _channel_base_eqs suppresses h_tc push so caller can provide custom equations (SCB correction)
- [v0.7 ISCB-01]: SCB correction factors are 10-100x when T_wall >> T_ONB; KINSOL diverges, transient solver or continuation needed for full-loop SCB steady-state
- [v0.7 ISCB-01]: h_tc default guess 5000.0 in ChannelAndContacts prevents MTK cyclic guesses initialization error

- [v0.6]: ifelse() for all conditional switching -- use for T_wall >= T_ONB SCB switching (ISCB-01)
- [v0.6]: @register_symbolic for opaque fluid functions -- sat_temperature(P) follows same pattern as rho_water(T)
- [v0.6]: Correlation functions are plain Julia closures -- HTC-01..04, FRIC-01..02 follow same pattern
- [v0.6]: @observed for diagnostic quantities not on RHS of other equations -- P[i], T_sat[i], T_ONB[i] qualify
- [v0.4]: Re/Nu/velocity/Pe are @observed (not unknowns) -- pressure observables follow same rule
- [v0.3]: New component files go in src/components/ -- subcooled_boiling.jl goes in src/physical_models/
- [v0.6 LOF]: pressure anchor pump.port_in.P ~ 1.0e5 required for multi-branch networks -- P[i] absolute values depend on this anchor being present

### Pending Todos

None.

### Blockers/Concerns

- VAL-01 (Fourier series validation) is a pre-existing flaky numerical test -- not caused by v0.6 changes.
- NET-03 (Cube flow) is a pre-existing KINSOL convergence failure -- not caused by v0.7 changes.

---

## Session Continuity

**Last session:** 2026-04-10T10:05:30.717Z
**Stopped at:** Phase 51 context gathered
**Next action:** Check remaining v0.9 phases (50+) or run /gsd-progress
**Resume file:** .planning/phases/51-julia-startup-performance-reliable-sysimage/51-CONTEXT.md

---

*Last updated: 2026-04-04 -- Phase 46 complete (callable PointKinetics + ReactivityController, 1344 tests pass)*

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260322-l7z | Create LOF transient example script with comprehensive plots and analysis | 2026-03-22 | 52f4e44 | [260322-l7z-create-lof-transient-example-script-with](./quick/260322-l7z-create-lof-transient-example-script-with/) |
| 260331-q27 | Audit and fix GSD planning artifacts (PROJECT.md Phase 27/28 requirements, evolution log, footer) | 2026-03-31 | 435be6b | [260331-q27-audit-gsd-planning-artifacts-and-surface](./quick/260331-q27-audit-gsd-planning-artifacts-and-surface/) |
| 260408-qv7 | Commit scram_callback signature fix (ssys first arg) and verify Phase 48->49 state | 2026-04-08 | 98a64ac | [260408-qv7-commit-scram-callback-signature-fix-and-](./quick/260408-qv7-commit-scram-callback-signature-fix-and-/) |
