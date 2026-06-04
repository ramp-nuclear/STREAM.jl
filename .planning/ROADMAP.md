# Roadmap: STREAM.jl

## Milestones

- ✅ **v0.1** — Phases 1–5 (single forced-convection loop validated within 1%, shipped 2026-02)
- ✅ **v0.2** — Phases 6–12 (multi-branch networks + gravity + inertia + HeatExchanger + ChannelAndContacts)
- ✅ **v0.3** — Phases 13–17 (HeatDiffusion 2D FD fuel plate, MTR assembly Python parity)
- ✅ **v0.4** — Phases 18–22 (MTR Dh correction, pluggable HTC/friction correlations, composition helpers)
- ✅ **v0.5** — Phases 23–27 (file-layout canonicalization, 13-module test suite, docstrings, CLAUDE.md)
- ✅ **v0.6** — Phases 28–31 (flow reversal, NC HTC, time-varying pump, Flapper, validated LOF transient)
- ✅ **v0.7** — Phase 32 (per-cell P / T_sat / T_ONB, SCB, threshold analysis, full HTC/friction library)
- ✅ **v0.8** — Phases 33–44 (STREAM Composer GUI, Tauri 2 + React + ReactFlow, shipped)
- ✅ **v0.9** — Phases 45–49 (Point Kinetics, ReactivityController, temperature feedback, `build_loop_pk`)
- ✅ **v1.0** — Phases 50–51 (open-source release, MIT, CI, examples)
- ✅ **v1.1** — Phases 52–58 (final channel-family redesign + Python STREAM cross-validation)
- ✅ **v1.2 — GUI Redesign** — Phases 59–72 + 63.1 (15 phases, 97 plans, shipped 2026-05-28). See [milestones/v1.2-ROADMAP.md](milestones/v1.2-ROADMAP.md).

## Phases

<details>
<summary>✅ v1.2 GUI Redesign (Phases 59–72 + 63.1) — SHIPPED 2026-05-28</summary>

- [x] Phase 59: Correlation `geom`-first refactor (4 plans) — completed 2026-05-11
- [x] Phase 60: `fuel_assembly` composition helper (2 plans) — completed 2026-05-11
- [x] Phase 61: Registry audit + rewrite for v1.1 (5 plans) — completed 2026-05-12
- [x] Phase 62: Resources panel architecture (15 plans) — completed 2026-05-13
- [x] Phase 63: BCs tab + value-source components in GUI (12 plans) — completed 2026-05-13
- [x] Phase 63.1: BC architecture rework — unified BCs tab (14 plans) — completed 2026-05-14
- [x] Phase 64: Connection routing (2 plans) — completed 2026-05-14
- [x] Phase 65: Interaction model overhaul (5 plans) — completed 2026-05-14
- [x] Phase 66: Code preview rework (5 plans) — completed 2026-05-16
- [x] Phase 67: Custom titlebar (1 plan) — completed 2026-05-16
- [x] Phase 68: Layers system overhaul (3 plans) — completed 2026-05-16
- [x] Phase 69: Command palette (jump-only) (4 plans) — completed 2026-05-18
- [x] Phase 70: Presets and templates (5 plans) — completed 2026-05-20
- [x] Phase 71: Validation framework (13 plans) — completed 2026-05-21
- [x] Phase 72: GUI redesign via Impeccable (Impeccable workflow, 0 PLAN.md files; SUMMARY.md only) — completed 2026-05-28

</details>

## Progress

| Milestone | Phases | Status | Shipped |
|-----------|--------|--------|---------|
| v0.1–v1.1 | 1–58 | Complete | through 2026-05-09 |
| v1.2 GUI Redesign | 59–72 + 63.1 | Complete | 2026-05-28 |

## Next

`/gsd:new-milestone` — start the next milestone cycle (questioning → research → requirements → roadmap).

Pending work before v1.2 PR can merge to `main`:

1. PR #15 (`channels-redesign → main`) must merge first.
2. Rebase `gui-redesign` onto fresh `main`.
3. Open v1.2 PR.
