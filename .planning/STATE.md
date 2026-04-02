---
gsd_state_version: 1.0
milestone: v0.8
milestone_name: STREAM Composer GUI
status: executing
stopped_at: Completed 35-01-PLAN.md (plan 01 of 03 in phase 35)
last_updated: "2026-04-02T00:23:14.950Z"
last_activity: 2026-04-02 -- Phase 35 execution started
progress:
  total_phases: 9
  completed_phases: 2
  total_plans: 10
  completed_plans: 8
---

# STATE: STREAM.jl

*Project memory — updated at the start and end of every session*

---

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-01)

**Core value:** A Julia MTK-based thermal-hydraulics library that matches Python STREAM results, proving the architecture is sound before large-scale porting begins.
**Current focus:** Phase 35 — parameter-editing
**Python STREAM reference:** ~/projects/STREAM

**Roadmap summary:**

- v0.7 (complete): Phases 27-32 — Safety Physics & Pressure Field (7 phases, 13 plans)
- v0.8 (active): Phases 33-40 — STREAM Composer GUI (8 phases, 40 requirements, 0 started)

---

## Current Position

Phase: 35 (parameter-editing) — EXECUTING
Plan: 1 of 3
Status: Executing Phase 35
Last activity: 2026-04-02 -- Phase 35 execution started

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

## Accumulated Context

### Key Decisions (v0.8 GUI)

- [v0.8 SCAF-01]: Tailwind v4 + @tailwindcss/vite: npm create tauri-app installs Tailwind v4; shadcn init expects v3 config file. components.json and src/index.css created manually with v4 CSS variable design tokens (New York/Zinc style). Future `npx shadcn add [component]` works correctly with this setup.
- [v0.8 SCAF-01]: vitest --passWithNoTests in test script: Vitest exits code 1 when no test files exist; flag added so CI passes before registry tests added in Plan 02.
- [v0.8 SCAF-01]: tsconfig.json not tsconfig.app.json: Tauri react-ts template generates tsconfig.json + tsconfig.node.json; path aliases added to tsconfig.json directly.
- [v0.8 SCAF-01]: Zustand + ReactFlow integration pattern: store owns nodes/edges arrays; onNodesChange/onEdgesChange use applyNodeChanges/applyEdgeChanges; CanvasPanel reads from store via useStore hook.
- [v0.8 SCAF-02]: vitest default environment is node (not jsdom): jsdom has ESM incompatibility with html-encoding-sniffer on Node.js 18; React component tests in later phases should add @vitest-environment jsdom docblock per-file.
- [v0.8 SCAF-02]: Registry Parameter interface has positional: boolean field for Phase 36 code generation to distinguish @named macro positional vs keyword arg syntax.
- [v0.8 SCAF-02]: ChannelHeatFlux has no ThermalPort in the registry -- T_wall is a scalar Real parameter, not a port connection; _note field documents this in the JSON entry.

### Key Decisions (carry-forward for v0.7)

- [v0.7 SCB-01]: max(dT, 0.0) inside ifelse() exponentiation prevents DomainError when dT < 0 (Julia ifelse evaluates both branches eagerly)
- [v0.7 SCB-04]: regime_dependent_q_scb is a factory (not direct function) to capture pressure at construction time, matching scb_correction closure contract
- [v0.7 ISCB-01]: skip_htc kwarg in _channel_base_eqs suppresses h_tc push so caller can provide custom equations (SCB correction)
- [v0.7 ISCB-01]: SCB correction factors are 10-100x when T_wall >> T_ONB; KINSOL diverges, transient solver or continuation needed for full-loop SCB steady-state
- [v0.7 ISCB-01]: h_tc default guess 5000.0 in ChannelAndContacts prevents MTK cyclic guesses initialization error

- [v0.6]: ifelse() for all conditional switching — use for T_wall >= T_ONB SCB switching (ISCB-01)
- [v0.6]: @register_symbolic for opaque fluid functions — sat_temperature(P) follows same pattern as rho_water(T)
- [v0.6]: Correlation functions are plain Julia closures — HTC-01..04, FRIC-01..02 follow same pattern
- [v0.6]: @observed for diagnostic quantities not on RHS of other equations — P[i], T_sat[i], T_ONB[i] qualify
- [v0.4]: Re/Nu/velocity/Pe are @observed (not unknowns) — pressure observables follow same rule
- [v0.3]: New component files go in src/components/ — subcooled_boiling.jl goes in src/physical_models/
- [v0.6 LOF]: pressure anchor pump.port_in.P ~ 1.0e5 required for multi-branch networks — P[i] absolute values depend on this anchor being present

### Pending Todos

None.

### Blockers/Concerns

- VAL-01 (Fourier series validation) is a pre-existing flaky numerical test — not caused by v0.6 changes.
- NET-03 (Cube flow) is a pre-existing KINSOL convergence failure — not caused by v0.7 changes.

---

## Session Continuity

**Last session:** 2026-04-02T00:23:14.947Z
**Stopped at:** Completed 35-01-PLAN.md (plan 01 of 03 in phase 35)
**Next action:** Phase 35-02 — sidebar UI
**Resume file:** None

---

*Last updated: 2026-03-31 — v0.8 STREAM Composer GUI roadmap added (phases 31-38, 40 requirements)*

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260322-l7z | Create LOF transient example script with comprehensive plots and analysis | 2026-03-22 | 52f4e44 | [260322-l7z-create-lof-transient-example-script-with](./quick/260322-l7z-create-lof-transient-example-script-with/) |
| 260331-q27 | Audit and fix GSD planning artifacts (PROJECT.md Phase 27/28 requirements, evolution log, footer) | 2026-03-31 | 435be6b | [260331-q27-audit-gsd-planning-artifacts-and-surface](./quick/260331-q27-audit-gsd-planning-artifacts-and-surface/) |
