---
gsd_state_version: 1.0
milestone: v1.2
milestone_name: "**Goal:** Bring `gui/src/registry/components.json` into alignment with v1.1 source. Stream version bump to `1.1.0`. Add 4 missing components. Rewrite Channel/CHF entries"
status: executing
stopped_at: Phase 71 context gathered
last_updated: "2026-05-21T11:58:52.615Z"
last_activity: 2026-05-21
progress:
  total_phases: 15
  completed_phases: 13
  total_plans: 97
  completed_plans: 94
  percent: 87
---

# STATE: STREAM.jl

*Project memory — updated at the start and end of every session*

---

## Project Reference

See: .planning/PROJECT.md (updated 2026-05-05)

**Core value:** A Julia MTK-based thermal-hydraulics library that matches Python STREAM results, proving the architecture is sound before large-scale porting begins.
**Current focus:** Phase 71 — validation-framework
**Python STREAM reference:** ~/projects/STREAM
**Working branch:** `gui-redesign` (off `main`; PR #15 — v1.1 `channels-redesign` → `main` — is currently OPEN but not a blocker; `gui-redesign` already contains the full v1.1 architecture and will fast-forward once PR #15 merges).

**Roadmap summary:**

- v0.8 (shipped): Phases 33-44 — STREAM Composer GUI
- v0.9 (shipped): Phases 45-49 — Point Kinetics & Reactor Control
- v1.0 (shipped): Phases 50-51 — Open-Source Release
- v1.1 (shipped to `gui-redesign`; PR #15 → `main` open): Phases 52-58 — Final Channel-Family Redesign + cross-validation + HTC film-temperature + MTK determinacy repair
  - Phase 52: Channel Connectors (CONN-01..04)
  - Phase 53: Shared `_channel_core` + Enthalpy-Form Energy Balance (CORE-01..05, NRG-01..04)
  - Phase 54: Variant Rewrites & File Consolidation (VAR-01..04)
  - Phase 55: Composition Helpers, Examples & Test Suite
  - Phase 56: Python STREAM Cross-Validation (TEST-04)
  - Phase 57: HTC film-temperature evaluation
  - Phase 58: MTK system determinacy repair
- v1.2 (active): Phases 59-72 — GUI Redesign (canonical decisions: `.planning/notes/gui-redesign-design-decisions.md`)
  - Phase 59: Correlation `geom`-first refactor ✓ shipped 2026-05-11
  - Phase 60: `fuel_assembly` composition helper ✓ shipped 2026-05-11
  - Phase 61: Registry audit + rewrite for v1.1 source ✓ shipped 2026-05-12
  - Phase 62: Resources panel architecture ✓ shipped 2026-05-13 (15/15 plans, 18/18 UAT gaps closed)
  - Phase 63: BCs tab + value-source components in GUI ✓ shipped 2026-05-13
  - Phase 63.1: BC architecture rework — unified BCs tab ✓ shipped 2026-05-14 (14/14 plans, 7/7 UAT gaps closed via Plans 11–14)
  - Phase 64: Connection routing ✓ shipped 2026-05-14
  - Phase 65: Interaction model overhaul ✓ shipped 2026-05-14, gap closure 2026-05-15 (14/14 plans = 8 original + 6 gap-closure 09–14 from UAT 2026-05-15; manual UAT still pending for live-shell surfaces — see VERIFICATION.md and individual SUMMARYs)
  - Phase 66: Code preview rework (next)
  - Phases 67-72: see ROADMAP.md

---

## Current Position

Phase: 71 (validation-framework) — EXECUTING
Plan: 7 of 13
Status: Ready to execute
Last activity: 2026-05-21
Next: Plan 05 (lengthMatch rule) — or next plan in the wave-2 parallel rule batch.

Phase 65 manual UAT: CLOSED 2026-05-21. All 20 tests in 65-UAT.md pass — including the 6 originally-deferred interactive items (canvas interaction matrix, clipboard, context menus + Rename focus, snap-to-grid persistence, AutoRecover crash sim, Untitled→Save As). VERIFICATION.md status flipped from `human_needed` to `complete`. (Phase 64 manual UAT also closed in the same sweep: 4/5 pass + 1 cosmetic issue routed to Phase 72 follow-up todo.)

Outstanding non-blocking items (NOT 71's job, but Phase 71 owns the tsc/vitest reconciliation):

- 11 pre-existing tsc errors + 1 pre-existing vitest failure (`SidebarPanel.anchors.test.tsx "Symmetric (L = R)"`) — Phase 71 owns reconciliation per Phase 61's deferred-items.
- Channel BCs tab visual layout fit issues — explicitly deferred to Phase 72 (v1.2 cosmetics / design system audit). Originally tagged for Phase 65 but Phase 65 scope was interaction model + AutoRecover, not BC visual layout.

---

## Accumulated Context

### Roadmap Evolution

- v1.1 milestone: Final Channel-Family Redesign — match Python STREAM design intent for `Channel`, `ChannelHeatFlux`, `ChannelAndContacts`; eliminate `_channel_base_eqs` flag-driven helper; switch convective energy balance to enthalpy form
- v1.1 phasing: 5 phases (52-56), coarse granularity, sequenced as connectors → shared core + energy balance → variants + file consolidation → composition/tests → cross-validation
- Phase 57 added: HTC film-temperature evaluation
- Phase 58 added: MTK system determinacy repair
- v1.2 milestone (2026-05-11): GUI Redesign — Phases 59-72. Phase 59 is a `src/` cleanup prerequisite (correlation factories take `geom::PipeGeometry` first), Phase 60 adds the `fuel_assembly` composition helper, Phase 61 rewrites the GUI component registry, then Phases 62-72 ship the actual GUI redesign (resources panel, BCs tab, connection routing, interaction model, code preview, etc.). Canonical decisions live in `.planning/notes/gui-redesign-design-decisions.md`.
- Phase 59 (2026-05-11): Correlation `geom`-first refactor shipped. All HTC + friction factories take `geom::PipeGeometry` positionally; `const HTCCorrelation = Function` exported. Python parity gate held (424 CLEAN / 34 FAIL / 78 GRAY, zero verdict flips). Phase 61 handoff doc at `.planning/notes/correlation-geom-first-api.md`.
- Phase 61 (2026-05-12): Registry audit + rewrite shipped — `gui/src/registry/components.json` now has 16 components (Channel/CHF/CAC/HD rewritten for v1.1; new: WallTemperature, HeatFluxSource, PointKinetics, ReactivityController). Envelope stream_version 1.1.0 / schema_version 2.0. 239 tests pass (was 232; +7 cross-validation tests for FK / array_size / pair_with resolution). `npm run build` baseline 7 pre-existing tsc errors (documented in `.planning/phases/61-.../deferred-items.md` — Phase 71 owns reconciliation). Phase 61 deliberately did NOT touch GUI rendering (`ToolboxPanel.tsx`, `StreamNode.tsx`, `ParameterForm.tsx`); the new categories (Sources / Reactor Physics / Resources) are invisible in the running app and Channel's new params don't render until Phase 62 (Resources panel + Sources toolbox category), Phase 63 (Properties vs BCs tab split + value-source UI), and Phase 68 (four-layer taxonomy) land. Plan 61-05 Task 3's smoke-test wording was over-eager — it described UI visibility that a data-only refactor cannot deliver; treat that as a planner-template lesson, not a Phase 61 gap.
- Phase 63.1 inserted after Phase 63: BC architecture rework — unified BCs tab (URGENT)

### Key Decisions (carry-forward)

- [v1.1 57-01, 2026-05-08]: Phase 57 Plan 01 shipped — HTC pipeline (Re, Pr, leading k outside Nu) in `ChannelAndContacts` SPL/SCB branches and the variant_obs Nu[i] observable now evaluate fluid properties at film T `T_film = (T[i] + T_w_i)/2`, matching Python STREAM `heat_transfer_coefficient/__init__.py:208-209`. Friction Re (channels.jl:139), `_channel_core` Pe/Pr observable (line 147), and variant_obs NC nu_i/Gr_i (lines ~778-779) intentionally remain at bulk T (Python convention). HTC correlation 4-arg signature unchanged; module header + 7 factory docstrings document the convention; `elenbaas_htc` carries the bulk-NC exception note. Gap #2 closed: all 20 simple_loop `h_tc_*[i]` rows + all 30 `q_density_*[i]` rows now CLEAN tier (rtol ~2.76e-11; was FAIL ~0.196 against the 0.02 hard ceiling). Single anchored block comment in CAC SPL branch documents the HTC=film vs friction/NC=bulk split.
- [v1.1 plan]: Branch `channels-redesign` is the single delivery vehicle for v1.1; no commits to main; stash@{0} (Manifest.toml + Project.toml + 3 untracked snap research notes) preserved for restoration after merge
- [v1.1 design]: Per-cell water property handling is already correct (`@register_symbolic` evaluated at local T[i]); v1.1 only changes the convective scheme to enthalpy form, not the property functions themselves
- [v1.1 CONN spike, 2026-05-05]: Connector pattern is **array of scalar MTK connectors per side** (matching existing `ChannelAndContacts` `thermal_left[1:n]` / `thermal_right[1:n]` pattern), NOT single vector-form connectors per side. Why: a focused spike (`/tmp/vec_diagnose3.jl`) showed vector-form connectors carrying `(T_wall(t))[1:n]` arrays exhibit a reproducible MTK bug — when compiled alongside any other scalar-port system in the same session (which always happens because of `FlowPort`), the first unknown of the vector system mis-integrates and clamps to its connected `T_wall`. Bug appears in raw `sol.u` (not just symbolic accessors) so it's an integration-level issue, not introspection. Vector form is correct in isolation but unsafe in any realistic `build_loop` composition. Stick with the proven array-of-scalar pattern; ergonomics are abstracted via composition helpers (`symmetric_plate`, `plate`, `one_sided_connection`).
- [v1.1 env, 2026-05-05]: Project.toml `[compat] julia = "1.12"` and Manifest regenerated under julia 1.12.6. Default toolchain is `juliaup default release`. Old Manifest had stale Statistics 1.10.0 stdlib pin (Statistics moved out of stdlib in julia 1.11) which blocked Pkg.resolve under 1.12.
- [v1.1 phasing]: CORE-* and NRG-* live in the same phase (53) because both touch the energy balance equation; bundling them avoids touching `_channel_core` twice
- [v1.1 phasing]: VAR-04 (file consolidation `channel.jl` + `thermal_channel.jl` → `channels.jl`) sits in Phase 54 with the variant rewrites — single-file pattern matching `connectors.jl`/`resistors.jl`
- [v1.1 phasing]: Cross-validation (TEST-04) gets its own phase (56) so the milestone-closing gate is unambiguous
- [v1.1 CONN-impl, 2026-05-06]: Phase 52 delivered `WallPort(T_wall, h, Q_flow)` and `HeatFluxPort(q_flux, Q_flow)` as scalar `@connector` types in `src/connectors.jl`, exported from `STREAM.jl`. Adiabatic-when-unconnected via Float64 IC defaults (`h=0.0` zeros the q expression `h·(T_wall−T)`); zero `ifelse` guards. Phase 54's `Channel`/`ChannelHeatFlux` rewrites must adopt the **drive-aware pattern** discovered during Plan 02 testing: WallPort's 2-across/1-flow shape is structurally underdetermined when unconnected (MTK's Flow rule auto-zeros only `Q_flow`, leaving `T_wall` and `h` free). Driven ports get the channel-side `Q_flow ~ h·A·(T_wall−T)` equation; unconnected ports self-anchor `T_wall ~ T_default; h ~ 0`. The two cases are mutually exclusive per port — mixing them over-determines the system. See `_StubRecipient` in `test/test_connectors.jl` for the contract.

- [v0.9 PK-01]: Callable MTK parameter pattern: `FType=typeof(fn)` at construction; `@parameters (fn::FType)(..)` variadic; used in equations as `fn(t)`. Matches Pump(dP_pump::Any) precedent from Phase 22.
- [v0.9 PK-02]: ReactivityController callable struct: `ctrl(t) = worth(ctrl, t)` allows passing ctrl directly as the MTK callable parameter without wrapper closure. FType = typeof(ctrl) captured at PointKinetics construction time.
- [v0.9 PK-03]: Additive rho composition (D-01): `rho_val + rho_c_fn(t) - beta_sum` for power ODE; `reactivity ~ rho_val + rho_c_fn(t)` for observed. Extends cleanly to Phase 47 temperature feedback.
- [v0.9 PK-04]: State-aware input reactivity signature: `(state, t_state, t) -> Float64` matches Python STREAM InputReactivity protocol. MTK callable parameter receives only `(t)` — RC forwards via worth(ctrl, t).
- [v0.9 PK-05]: Prompt-jump test window: sample at `t_step + Lambda/delta_rho` (not plan's 0.01s). At Lambda=5.4e-5, delta_rho=0.002: window = 0.027s. Sampling at 0.028s gives 0.08% error vs expected formula.
- [v0.9 TF-01]: scoped_comps kwarg in connect_temperature_feedback: when cac is wrapped in symmetric_plate(cac, fuel; name=:rods), its T vars are re-scoped to rods+cac+T. Pass scoped_comps=Dict(cac=>rods.cac) so feedback equations bind to the correct symbolic while pk.T_source_cac name stays from original nameof(cac).
- [v0.9 TF-02]: IC path after mtkcompile: compiled system IS the named system (ssys IS core). Variables are ssys.rods.cac.T, not ssys.core.rods.cac.T. Extra prefix causes KeyError.

- [v0.7 SCB-01]: max(dT, 0.0) inside ifelse() exponentiation prevents DomainError when dT < 0 (Julia ifelse evaluates both branches eagerly)
- [v0.7 ISCB-01]: SCB correction factors are 10-100x when T_wall >> T_ONB; KINSOL diverges, transient solver or continuation needed for full-loop SCB steady-state
- [v0.7 ISCB-01]: h_tc default guess 5000.0 in ChannelAndContacts prevents MTK cyclic guesses initialization error

- [v0.6]: ifelse() for all conditional switching (flow reversal, regime detection, T_wall ≥ T_ONB)
- [v0.6]: @register_symbolic for opaque fluid functions (rho_water, cp_water, mu_water, k_water, beta_water, sat_temperature)
- [v0.6]: Correlation functions are plain Julia closures (not @register_symbolic) — MTK traces them symbolically
- [v0.6]: @observed for diagnostic quantities not on RHS of other equations
- [v0.6 LOF]: pressure anchor pump.port_in.P ~ 1.0e5 required for multi-branch networks — P[i] absolute values depend on this anchor

### Pending Todos

(v1.1 close blockers + cleanup items removed 2026-05-21 — all resolved during Plan 56-06 close-up. MTR L/R wiring fixed via R-1 minimal-diff fix in tests; parity_report.csv regenerated to 424 CLEAN / 78 GRAY / 34 FAIL; NET-03 `@test_skip` markers in place; REQUIREMENTS.md VAR-01..04 already marked complete. See `.planning/archive/v1.1/phases/56-python-stream-cross-validation/56-06-SUMMARY.md` and `.planning/v1.1-MILESTONE-AUDIT.md` (status: tech_debt, 22/22 requirements complete). Numerical residuals VAL-01 + NET-03 carried forward to `.planning/todos/pending/v12-numerical-investigation-val01-net03.md` for a future numerical phase.)

No v1.2-active pending todos currently tracked in STATE.md. See `.planning/todos/pending/` for the live backlog (4 items: Phase 72 handle visual rework, codegen resource dedup, GUI visual design pass, panel-resize overflow, plus the v1.2 numerical-investigation entry just filed).

### Blockers/Concerns

(v1.1-era blockers cleared 2026-05-21 — MTR L/R convention disagreement resolved via R-1 fix; NET-03 KINSol flakies absorbed by `@test_skip` markers; v1.1 milestone audit re-audited to `tech_debt` with 22/22 requirements complete; VAL-01 + NET-03 numerical residuals routed to v1.2-numerical-investigation backlog todo.)

No v1.2-active blockers currently tracked. Phase 71 (validation framework, next up) is unstarted, not blocked.

---

## Session Continuity

**Last session:** 2026-05-21T11:58:52.600Z
**Stopped at:** Phase 71 context gathered
**Next action:** `/gsd:discuss-phase 66` (Code preview rework) — or `/gsd:ship` to open a milestone PR first and run UAT on the 6 deferred Phase 65 surfaces
**Resume file:** None
**Branch:** `gui-redesign`
**Stash:** none

**Phase 65 outcomes (carry-forward):**

- Lowest-free `nextInstanceName` is canonical in `useStore.ts:328`; module-level `instanceCounters` is gone (Plan 65-01).
- Clipboard payload contract: OS-clipboard JSON via `navigator.clipboard.writeText`; lowest-free renaming on paste; internal edges only (Plan 65-04, `gui/src/lib/clipboard.ts`).
- Canvas interaction model now drawio-style: left-marquee, right-drag pan with 5px/250ms long-pan suppression (`gui/src/hooks/useRightClickContextMenu.ts`); 3 shadcn-based context menus (`gui/src/components/canvasMenus/`).
- Snap-to-grid: 16px fixed grid via ReactFlow built-ins, canvas-overlay toggle button, persisted per-project in `.scp` `layout.snap_to_grid`.
- AutoRecover: 2s debounced sidecar writer to `appDataDir/STREAM-Composer/autorecover/`; PID-alive lockfile crash detection; blocking Radix Dialog restore modal; bit-identical-to-Save payload via `projectIO.serialize`.

**Process anomalies (no code impact, lessons for future phases):**

- Plan 65-02 executor had a cwd-drift bug — committed directly to `gui-redesign` instead of its worktree branch. Code is correct but worktree isolation was bypassed.
- Plan 65-07 worktree forked off an ancient commit (66dc2bf, pre-v1.1). Recovered via cherry-pick onto current HEAD; useStore.ts conflict resolved manually (dropped dead `clearInstanceCounters`, fixed outdated `serializeProject` signature).
- Plan 65-08's render gate broke 3 AppShell tests; fixed by mocking `lib/autoRecover` and converting to `findByRole` (commit 46b07b0).

**Phase 59 outcomes (carry-forward into Phase 60 and Phase 61):**

- All correlation factories (`laminar_friction`, `elenbaas_htc`, `fully_developed_laminar_h_spl`, `developing_laminar_h_spl`, `regime_dependent`) take `geom::PipeGeometry` positionally. Old kwarg-only forms physically deleted (clean break per D-01). `const HTCCorrelation = Function` exported from `STREAM.jl` (declared BEFORE includes that reference it — see `f4a0042` fix).
- Repo-wide closure check: zero non-geom call sites remain in `src/` or `test/`.
- Python parity preserved exactly: 424 CLEAN / 34 FAIL / 78 GRAY (same as pre-refactor baseline; zero verdict flips).
- API surface and remaining deferred items documented in `.planning/notes/correlation-geom-first-api.md` for Phase 61 to consume when rewriting the GUI registry.

---

*Last updated: 2026-05-14 — Phase 65 complete (8/8 plans, verification PASS); ready for Phase 66*
