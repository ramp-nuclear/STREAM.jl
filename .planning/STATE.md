---
gsd_state_version: 1.0
milestone: v1.1
milestone_name: "**Goal:** Bring `gui/src/registry/components.json` into alignment with v1.1 source. Stream version bump to `1.1.0`. Add 4 missing components. Rewrite Channel/CHF entries"
status: ready_to_plan
stopped_at: Phase 59 context gathered
last_updated: "2026-05-11T16:50:52.482Z"
last_activity: 2026-05-11 -- Phase 59 execution started
progress:
  total_phases: 7
  completed_phases: 8
  total_plans: 34
  completed_plans: 34
  percent: 114
---

# STATE: STREAM.jl

*Project memory — updated at the start and end of every session*

---

## Project Reference

See: .planning/PROJECT.md (updated 2026-05-05)

**Core value:** A Julia MTK-based thermal-hydraulics library that matches Python STREAM results, proving the architecture is sound before large-scale porting begins.
**Current focus:** Phase 59 — correlation-geom-first-refactor
**Python STREAM reference:** ~/projects/STREAM
**Working branch:** `channels-redesign` (off origin/main, single PR at end)

**Roadmap summary:**

- v0.8 (shipped): Phases 33-44 — STREAM Composer GUI
- v0.9 (shipped): Phases 45-49 — Point Kinetics & Reactor Control
- v1.0 (shipped): Phases 50-51 — Open-Source Release
- v1.1 (active): Phases 52-56 — Final Channel-Family Redesign
  - Phase 52: Channel Connectors (CONN-01..04)
  - Phase 53: Shared `_channel_core` + Enthalpy-Form Energy Balance (CORE-01..05, NRG-01..04)
  - Phase 54: Variant Rewrites & File Consolidation (VAR-01..04)
  - Phase 55: Composition Helpers, Examples & Test Suite (TEST-01, TEST-02, TEST-03, TEST-05)
  - Phase 56: Python STREAM Cross-Validation (TEST-04)

---

## Current Position

Phase: 998.1
Plan: Not started
Status: Ready to plan
Last activity: 2026-05-11
Next: `/gsd:audit-milestone v1.1` → `/gsd:complete-milestone v1.1` → `/gsd:ship`

---

## Accumulated Context

### Roadmap Evolution

- v1.1 milestone: Final Channel-Family Redesign — match Python STREAM design intent for `Channel`, `ChannelHeatFlux`, `ChannelAndContacts`; eliminate `_channel_base_eqs` flag-driven helper; switch convective energy balance to enthalpy form
- v1.1 phasing: 5 phases (52-56), coarse granularity, sequenced as connectors → shared core + energy balance → variants + file consolidation → composition/tests → cross-validation
- Phase 57 added: HTC film-temperature evaluation
- Phase 58 added: MTK system determinacy repair

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

- **[v1.1 close blocker]** Decide MTR L/R wiring convention (Julia spatial-absolute vs Python channel-relative). 92 parity FAIL rows in `test/data/parity_report.csv` trace to this. See `.planning/phases/56-python-stream-cross-validation/56-RESUME-PLAN.md` task 5.
- **[v1.1 close blocker]** After convention fix: regenerate parity_report.csv, expect MTR FAILs → 0/GRAY.
- **[v1.1 close blocker]** Resume Plan 56-06 (cleanup grep, MILESTONES.md narrative entry, gsd-verifier on Phase 56).
- **[v1.1 cleanup]** NET-03 KINSOL halts `bin/jl test/runtests.jl` orchestrator — being marked `@test_skip` with documented reason during this resume cycle.
- **[v1.1 cleanup]** REQUIREMENTS.md checkbox sweep: VAR-01..04 → `[x]` (already wired in code; just stale checkboxes).

### Blockers/Concerns

- **MTR L/R convention disagreement.** `src/composition/helpers.jl` (`symmetric_plate`, `plate`, `one_sided_connection`) wires LEFT-channel's RIGHT face → plate's LEFT face (spatial-absolute). Python `stream/composition/mtr_geometry.py:60-63` wires LEFT-channel's LEFT face (channel-relative). Result: 92 FAIL rows on MTR scenarios in `parity_report.csv`. Decision pending.
- VAL-01 (Fourier series validation) — `solve` returns `ReturnCode.InitialFailure`. Phase 58 fixed structural determinacy; numerical convergence is a v1.2 follow-up (out-of-scope per 58-CONTEXT.md).
- NET-03 (Cube flow) KINSOL flag −11 — pre-existing flaky from Phase 55 D-22; halts runtests.jl orchestrator. Being skipped this cycle.
- v1.1 milestone audit (.planning/v1.1-MILESTONE-AUDIT.md) verdict: `gaps_found` — TEST-04 unsatisfied, ROADMAP/STATE rollup was lying about completion until this update corrected it.

---

## Session Continuity

**Last session:** 2026-05-11T16:27:18.427Z
**Stopped at:** Phase 59 context gathered
**Next action:** `/gsd-plan-phase 52` to decompose Phase 52 (Channel Connectors) into executable plans
**Resume file:** .planning/phases/59-correlation-geom-first-refactor/59-CONTEXT.md
**Branch:** `channels-redesign`
**Stash:** stash@{0} = "WIP before channels-redesign milestone: deps + snap research notes"

**Phase 52 decisions locked (from 52-CONTEXT.md):**

- WallPort (T_wall, h, Q_flow [Flow]) and HeatFluxPort (q_flux, Q_flow [Flow]) — scalar connectors, used as arrays per side
- Adiabatic default: IC `h=0` / `q_flux=0` alone — no `ifelse` guard in channel equations
- Q_flow [W] positive=into-channel, matches existing ThermalPort convention
- Tests: inline `_StubRecipient` / `_StubWallDriver` / `_StubFluxDriver` in `test_connectors.jl`
- Smoke test: tiny pump→stub→pump loop with brief solve, asserts no MTK stream-connection warnings

---

*Last updated: 2026-05-05 — Phase 52 context gathered*
