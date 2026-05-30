# Milestone v1.1: Final Channel-Family Redesign

**Status:** Active (planning complete)
**Phases:** 52-56 (5 phases)
**Branch:** `channels-redesign` (single PR at end)
**Defined:** 2026-05-05

## Overview

Last rewrite of the three Channel components (`Channel`, `ChannelHeatFlux`, `ChannelAndContacts`). Goal: design matches Python STREAM's intent and never needs touching again — a single shared `_channel_core` private function, no flag-driven helpers, correct enthalpy-form energy balance, and per-cell/per-side connector types that compose idiomatically with MTK acausal semantics.

Reference implementation: Python STREAM at `/home/itayb/projects/STREAM/stream/calculations/channel.py`. Julia translation: a single private `_channel_core(...; q_left_expr, q_right_expr)` plus three thin public constructors that differ only in how `q_left[i]` and `q_right[i]` are produced.

22 requirements across 5 categories (CONN, CORE, VAR, NRG, TEST). All work delivered as a single PR off branch `channels-redesign`.

## Phases

- [x] **Phase 52: Channel Connectors** — New per-cell, per-side connector types for `Channel` (T_wall + h) and `ChannelHeatFlux` (q); adiabatic/zero-flux defaults *(completed 2026-05-06)*
- [x] **Phase 53: Shared `_channel_core` with Enthalpy-Form Energy Balance** — Single private core function; `_channel_base_eqs` and all flag plumbing deleted; convective term switched to face-averaged cp with cp(T_in) at the boundary face (completed 2026-05-06)
- [x] **Phase 54: Variant Rewrites & File Consolidation** — `Channel`, `ChannelHeatFlux`, `ChannelAndContacts` rebuilt onto the shared core; old `channel.jl` and `thermal_channel.jl` deleted; new `src/components/channels.jl` (completed 2026-05-07)
- [x] **Phase 55: Composition Helpers, Examples & Test Suite** — `symmetric_plate`/`plate`/`one_sided_connection` updated for new connectors; all builders and `test_channel.jl` ported; full test suite green locally (completed 2026-05-07)
- [x] **Phase 56: Python STREAM Cross-Validation** — Steady-state cross-validation harness landed (424 CLEAN / 78 GRAY / 34 FAIL all documented); ≤1% rtol target met for simple_loop scenario, mtr asymmetric/one-sided residual drift documented per MILESTONES.md v1.1 entry *(completed 2026-05-09)*

## Phase Details

### Phase 52: Channel Connectors

**Goal:** New MTK acausal connector types carrying `(T_wall, h)` for `Channel` and `q` for `ChannelHeatFlux` — per cell, per side, with safe defaults when unconnected. Establish the connector contract before the core or variants are touched, since both depend on the connector shape.

**Depends on:** Nothing (first phase of v1.1)
**Requirements:** CONN-01, CONN-02, CONN-03, CONN-04
**Success Criteria** (what must be TRUE):
  1. New connectors are defined in `src/connectors.jl` and exported from `src/STREAM.jl` alongside `FlowPort`/`ThermalPort`; calling `using STREAM` and constructing a connector instance succeeds at the REPL.
  2. Each new connector type passes a focused unit test that asserts: correct across/flow variable annotations, `connect()` produces well-formed MTK equations, and an unconnected port yields the documented adiabatic/zero-flux default (`T_wall = T` and/or `h = 0` ⇒ `q = 0` for Channel; `q = 0` for ChannelHeatFlux) when wrapped in a minimal `compose()`.
  3. `instream(...)` integrates with the upstream-temperature selection in the connector for Channel without caller-side wiring tricks; a smoke compose verifies no MTK warnings about unset stream connections.
  4. `ChannelAndContacts`'s existing `ThermalPort` arrays are confirmed compatible with the refactored connector landscape (no behavioral regression at the connector level).
**Plans:** 2 plans
- [x] 52-01-PLAN.md — Add WallPort and HeatFluxPort connector definitions to src/connectors.jl and extend the export line in src/STREAM.jl
- [x] 52-02-PLAN.md — Append three inline test stubs and ~16 testsets to test/test_connectors.jl covering CONN-01/02/04 (structural + behavioural + smoke)

### Phase 53: Shared `_channel_core` with Enthalpy-Form Energy Balance

**Goal:** Extract a single private `_channel_core(...; q_left_expr, q_right_expr)` function that is the only source of truth for energy balance, mass conservation, momentum ODE `(L/A)·D(mdot)`, friction `dp[i]`, port wiring, and observables (Re, Pe, P[i], T_sat, T_ONB, dP). Switch the energy-balance convective term to enthalpy form (face-averaged cp, cp(T_in) at the boundary face) in the same change since both touch the same equation.

**Depends on:** Phase 52
**Requirements:** CORE-01, CORE-02, CORE-03, CORE-04, CORE-05, NRG-01, NRG-02, NRG-03, NRG-04
**Success Criteria** (what must be TRUE):
  1. A single `_channel_core` function exists; `_channel_base_eqs` is fully deleted from `src/components/channel.jl` and grep returns no remaining references.
  2. No `observed_mode`, `skip_htc`, or `T_wall_cells=nothing` flags exist anywhere in the codebase (`grep -rn 'observed_mode\|skip_htc\|T_wall_cells'` is empty across `src/`).
  3. Convective enthalpy-form energy balance is implemented: numerator uses face-averaged cp `(cp(T_up) + cp(T[i])) / 2`; boundary face of cell 1 (forward) and cell n (reverse) uses `cp(instream(port_in.T))` / `cp(instream(port_out.T))`; denominator retains local `cp(T[i])` so the two cp values do not cancel.
  4. Flow reversal symmetry: the same `ifelse(mdot ≥ 0, ...)` expression that selects upstream T also selects upstream cp; a focused unit test on a single-cell channel asserts forward and reverse runs are mirror images of each other.
  5. Every code path inside `_channel_core` is exercised by at least one variant — no dead branches remain after the core is wired up against placeholder `q_left_expr`/`q_right_expr` arguments in test scaffolding.
**Plans:** 4/4 plans complete
- [x] 53-01-PLAN.md — Wave-0 test scaffolding: _StubChannelCore harness, test/data/stage2_reference.py, runtests.jl wiring, v1.0 baseline capture (Pitfall 4 Option A locked here)
- [x] 53-02-PLAN.md — Add _channel_core to src/components/channel.jl with enthalpy-form energy balance; coexists with _channel_base_eqs; fill in _StubChannelCore body
- [x] 53-03-PLAN.md — G1 (Stage-1 baseline rtol=1e-6) + G2 (Stage-2 Python parity rtol=1e-9) + G3 (single-cell mirror rtol=1e-12) + G4 (branch-coverage matrix) testsets
- [x] 53-04-PLAN.md — Inline _channel_base_eqs body into CAC and CHF call sites, delete _channel_base_eqs and all flag knobs (observed_mode, skip_htc, T_wall_cells); final regression

### Phase 54: Variant Rewrites & File Consolidation

**Goal:** Rewrite the three public variants on top of `_channel_core` — `Channel` as a passive recipient (q derived from external T_wall + h), `ChannelHeatFlux` receiving q directly per cell per side, `ChannelAndContacts` retaining correlation-driven h with optional SCB. Consolidate `channel.jl` and `thermal_channel.jl` into a single `src/components/channels.jl` (plural, matching the `connectors.jl`/`resistors.jl` pattern); update `STREAM.jl` `include` line and `CLAUDE.md` File Structure Standard accordingly.

**Depends on:** Phase 53
**Requirements:** VAR-01, VAR-02, VAR-03, VAR-04
**Success Criteria** (what must be TRUE):
  1. `Channel(...)`, `ChannelHeatFlux(...)`, and `ChannelAndContacts(...)` all construct, `mtkcompile` cleanly, and pass a smoke `solve_steady` on a minimal closed loop; their old API surface (positional vs. keyword arguments per CLAUDE.md authoring conventions) is preserved where it does not conflict with the new connector contract.
  2. `Channel` is a passive recipient: with no external connection it is adiabatic; with an external `T_wall + h` source the per-cell `q_side[i] = h_side[i] · (T_wall_side[i] − T[i])` is observable in the solution; scalar `thermal::ThermalPort` and any internal h-correlation are gone.
  3. `ChannelHeatFlux` consumes per-cell, per-side `q_left[i] / q_right[i]` directly via the CONN-02 connector; the scalar `T_wall` parameter and internal h correlation are removed; a uniform-q test reproduces the previous scalar-T_wall behavior to within numerical tolerance.
  4. `ChannelAndContacts` is rebuilt on `_channel_core`: it computes h via correlation, supports the existing optional `scb_correction` keyword without any flag plumbing, and continues to expose `thermal_left[1:n]` / `thermal_right[1:n]` `ThermalPort` arrays.
  5. Files `src/components/channel.jl` and `src/components/thermal_channel.jl` are deleted; `src/components/channels.jl` exists; `src/STREAM.jl` `include` line and `CLAUDE.md` File Structure Standard are updated; `git ls-files src/components/` confirms exactly one channels file.
  6. **Per-variant integration smoke (added 2026-05-06 during Phase 52 retrospective; rewritten 2026-05-07 during Phase 54 discuss after the WallPort removal pivot):** Before this phase closes, each rewritten variant is exercised on a real closed loop, not a stub system. **Architectural rule (locked, see `feedback_channel_hd_connection_rule.md`):** `HeatDiffusion` connects ONLY to `ChannelAndContacts`; `Channel` and `ChannelHeatFlux` never wire to `HeatDiffusion`. (a) `Channel` exercised on a closed `Pump → Channel → Pump` loop with per-cell `T` binding equations on its `ThermalPort` arrays (left side driven; right side adiabatic via default `h_right=0.0`), and `h_left::Vector` supplied as a Channel constructor kwarg; asserts per-cell `q_wall_left[i]` observable is finite and signed-correctly under the new kwarg-driven external-h architecture. (b) `ChannelHeatFlux` exercised on a closed `Pump → ChannelHeatFlux → Pump` loop with per-cell `q_flux` binding equations on its `HeatFluxPort` arrays (left side driven; right side adiabatic via dangling port + IC `q_flux=0`); asserts per-cell `q_wall_left[i]` matches supplied flux × heated-area × dz. (c) `ChannelAndContacts` ↔ `HeatDiffusion` over the existing `ThermalPort` arrays as a CONN-03 regression check. Each smoke must `mtkcompile` and `solve_transient` (not just `solve_steady`) on a minimal closed loop, asserting via named symbolic accessors. Rationale: Phase 55's full-rewiring sweep would pile three suspect layers onto any failure; this gate isolates the variant-rewrite layer first.
**Plans:** 5/5 plans complete
- [x] 54-01-PLAN.md — Channel rewrite + WallPort removal: create src/components/channels.jl with _channel_core (moved from channel.jl) + new Channel(; h_left, h_right) on ThermalPort arrays; delete WallPort from connectors.jl, STREAM.jl exports, and test/test_connectors.jl (VAR-01)
- [x] 54-02-PLAN.md — ChannelHeatFlux rewrite onto _channel_core: minimal signature (no T_wall, no htc_correlation), HeatFluxPort arrays, q_left_expr = q_flux × heated × dz (VAR-02)
- [x] 54-03-PLAN.md — ChannelAndContacts rewrite onto _channel_core: ThermalPort arrays kept (CONN-03 carry-forward), h_tc + optional SCB migrated verbatim, all CAC-only observables retained (VAR-03)
- [x] 54-04-PLAN.md — Consolidate channels file: delete src/components/channel.jl and src/components/thermal_channel.jl; prune STREAM.jl includes; update CLAUDE.md File Structure Standard (VAR-04)
- [x] 54-05-PLAN.md — Per-variant integration smokes in test/test_channels.jl: closed loops for Channel, CHF, and CAC↔HD via symmetric_plate; wired into runtests.jl; phase close gate (VAR-01/02/03)

### Phase 55: Composition Helpers, Examples & Test Suite

**Goal:** Re-architect `Channel` and `ChannelHeatFlux` to drop their per-cell ports in favor of channel-level external-input variables (so the Python STREAM args.funcs idiom works natively in Julia MTK via direct binding eqns and via new `WallTemperature` / `HeatFluxSource` value-source components); retire `HeatFluxPort` from the connector roster; verify or update composition helpers; port all six shipped builders and all `examples/*.jl` to the new design (with a spike to choose `build_loop_lof_bypass`'s heated-leg topology between CAC + WallTemperature and CAC + HeatDiffusion plate); reorganize the test suite onto Python STREAM's organizational rules; and confirm the full local test suite has no NEW failures vs the v1.0 baseline. Goal rewritten 2026-05-07 during Phase 55 discuss to reflect the architectural redesign and the rewrite-not-port frame — see `.planning/phases/55-composition-helpers-examples-test-suite/55-CONTEXT.md`.

**Depends on:** Phase 54
**Requirements:** TEST-01, TEST-02, TEST-03, TEST-05
**Success Criteria** (what must be TRUE):
  1. `Channel` and `ChannelHeatFlux` no longer have per-cell `ThermalPort` / `HeatFluxPort` arrays. Both expose channel-level external-input variables instead: `Channel` has `T_wall_left[1:n]` / `T_wall_right[1:n]`, `ChannelHeatFlux` has `q_left[1:n]` / `q_right[1:n]`. `HeatFluxPort` is deleted from `src/connectors.jl` and from `src/STREAM.jl` exports. `ChannelAndContacts` is unchanged (still exposes `ThermalPort` arrays for HD wiring).
  2. New `src/components/sources.jl` ships `WallTemperature(; n, T_wall::Real|Vector|Function)` and `HeatFluxSource(; n, q::Real|Vector|Function)` as portless value-source components, exported from STREAM. Both styles work natively without over-determination: direct binding eqns at compose time (`[ch.T_wall_left[i] ~ value for i in 1:n]...`) AND value-source components (`@named wt = WallTemperature(; n, T_wall=value); [ch.T_wall_left[i] ~ wt.T_wall_out[i] for i in 1:n]...`).
  3. `symmetric_plate`, `plate`, `one_sided_connection`, and `compose_systems` in `src/composition/helpers.jl` are verified under the new design. Zero-change is an acceptable outcome (helpers wire CAC↔HD via ThermalPort which is unchanged); update only if a test fails. MTR assembly tests (HeatDiffusion + 2× ChannelAndContacts in symmetric, asymmetric, and one-sided wiring) compile and solve.
  4. All shipped builders (`build_loop`, `build_loop_vertical`, `build_loop_transient`, `build_cube`, `build_loop_lof_bypass`, `build_loop_pk`) and `examples/simple_loop.jl` / `examples/mtr_assembly.jl` / `examples/lof_transient.jl` build, `mtkcompile`, and run `solve_steady` / `solve_transient` without regression. `build_loop_lof_bypass`'s heated-leg topology is decided by a Phase 55 spike (CAC + WallTemperature vs CAC + HeatDiffusion plate; pick the simpler one that reproduces v1.0 LOF NC-reversal qualitative behavior in reasonable runtime).
  5. Test suite reorganized onto Python STREAM's rules: 14-file layout with one-file-per-component for unit tests, `test_composition.jl` for compose-correctness (heavy CAC↔HD), one big `test_integration.jl` for system-level multi-component tests (LOF, PK loops, SCB integration, builder smokes, solver wrappers — all sections of one file), library tests in `test_correlations.jl` / `test_thresholds.jl` (renamed from `test_analysis.jl`) / `test_fluids.jl`, `test_validation.jl` untouched (Phase 56). `test_channels.jl` is rewritten under the new design (variants + `_channel_core` + sign-safety merged in) and the legacy `test/test_channel.jl` is deleted. `test_point_kinetics.jl` is trimmed to component-unit tests only (LOOP-* and full-coupling TF tests relocate to `test_integration.jl`).
  6. Full test suite has no NEW failures vs the v1.0 baseline: `bin/jl test/runtests.jl` (or `julia --project=. test/runtests.jl` without the daemon). Pre-existing flakies (VAL-01 Fourier numerical, NET-03 Cube flow KINSOL convergence) remain tolerated per the v1.0 baseline — "no new errors vs baseline" is the gate, not "zero failures absolute."
**Plans:** 11/11 plans complete

Plans:
**Wave 1**
- [x] 55-01-PLAN.md — Wave 0 spikes: dangling-port hypothesis + LOF topology selection
- [x] 55-02-PLAN.md — Channel + ChannelHeatFlux architectural redesign (drop per-cell ports)
- [x] 55-03-PLAN.md — Create src/components/sources.jl + STREAM.jl includes/exports update

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 55-04-PLAN.md — HeatFluxPort retirement (connectors.jl + test_connectors.jl)
- [x] 55-05-PLAN.md — test_channels.jl rewrite (TEST-01 unification: variants + core + sign-safety)
- [x] 55-06-PLAN.md — WallTemperature + HeatFluxSource unit tests in test_misc.jl

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 55-07-PLAN.md — test_composition.jl rewrite (TEST-03 + composition helpers verify)

**Wave 4** *(blocked on Wave 3 completion)*
- [x] 55-08-PLAN.md — Migrate three simple-loop builders + simple_loop.jl + mtr_assembly.jl + build_loop_pk verify

**Wave 5** *(blocked on Wave 4 completion)*
- [x] 55-09-PLAN.md — build_loop_lof_bypass migration + lof_transient.jl update (gated by Wave 0 LOF spike)

**Wave 6** *(blocked on Wave 5 completion)*
- [x] 55-10-PLAN.md — Create test_integration.jl + trim test_point_kinetics.jl + delete absorbed files

**Wave 7** *(blocked on Wave 6 completion)*
- [x] 55-11-PLAN.md — Phase 55 close gate: test_thresholds rename + runtests.jl + CLAUDE.md + TEST-05 verify

### Phase 56: Python STREAM Cross-Validation

**Goal:** Quantitative cross-validation against Python STREAM under the new convective scheme — the milestone gate. Steady-state outputs must match within ≤1% rtol; transient trajectories must remain within their existing tolerances after the enthalpy-form switch.

**Depends on:** Phase 55
**Requirements:** TEST-04
**Success Criteria** (what must be TRUE):
  1. Steady-state cross-validation: `T_out`, `mdot`, and per-cell `T[i]` from the canonical reference loop match Python STREAM hardcoded reference constants within ≤1% rtol; the existing `test/test_validation.jl` assertions pass under the new energy balance.
  2. Transient cross-validation: LOF transient (`build_loop_lof_bypass`) and PK transient (`build_loop_pk`) trajectories remain within their pre-existing tolerances; energy-balance residual on the LOF transient stays below the v0.6 threshold (~0.1% rtol).
  3. Any drift introduced strictly by the enthalpy-form switch is documented in `MILESTONES.md` (with sign and magnitude); if a tolerance had to be retuned, the change is justified by Python STREAM behavior, not by Julia regression.
  4. Final milestone-close checkpoint: branch `channels-redesign` is ready for a single PR — clean working tree, full test suite green, no `_channel_base_eqs` / `observed_mode` / `skip_htc` references anywhere.
**Plans:** 5/6 plans executed

Plans:
**Wave 1**
- [x] 56-01-PLAN.md — Build test/parity_helpers.jl with ParityRow + parity_check + drift-report machinery + 5 equivalence-checklist asserts (D-15)
- [x] 56-02-PLAN.md — Rewrite test/generate_reference.py to emit all D-07 tiers for the simple-loop scenario as ready-to-paste Julia const blocks (D-17)
- [x] 56-03-PLAN.md — Rewrite test/generate_mtr_reference.py to emit all D-07 tiers (incl. plate T(z,x)) for 3 MTR variants (D-02 + D-17)

**Wave 2** *(blocked on Wave 1)*
- [x] 56-04-PLAN.md — Manual checkpoint: run both Python generators on developer machine; paste const blocks into test/data/python_parity_reference.jl + replace REGENERATE placeholders in test/parity_helpers.jl (D-05/D-06)

**Wave 3** *(blocked on Wave 2)*
- [x] 56-05-PLAN.md — Rewrite the 5 Python-parity testsets in test_validation.jl following the parity_check pipeline; produce test/data/parity_report.csv (D-13/D-14/D-08/D-16)

**Wave 4** *(blocked on Wave 3)*
- [x] 56-06-PLAN.md — Phase 56 close gate: cleanup grep + branch verification + .planning/MILESTONES.md narrative entry per D-09 + decide on FAIL-tier dispositions per D-04/D-11/D-12 *(resumed 2026-05-09 post-57+58; included R-1 MTR L/R fix + per-side h_tc rewrite; final tally 424 CLEAN / 78 GRAY / 34 FAIL all documented)*

---

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 52. Channel Connectors | 2/2 | Complete | 2026-05-06 |
| 53. Shared `_channel_core` + Enthalpy-Form Energy Balance | 4/4 | Complete    | 2026-05-06 |
| 54. Variant Rewrites & File Consolidation | 5/5 | Complete   | 2026-05-07 |
| 55. Composition Helpers, Examples & Test Suite | 11/11 | Complete    | 2026-05-08 |
| 56. Python STREAM Cross-Validation | 5/6 | In Progress|  |

### Phase 57: HTC film-temperature evaluation

**Goal:** Switch the Channel HTC pipeline (Re, Pr, leading k outside Nu) to evaluate fluid properties at the film temperature T_film = (T_cool + T_wall) / 2, matching Python STREAM. Friction Re and natural-convection Gr stay at bulk T (Python convention). Close Phase 56 parity Gap #2: simple_loop h_tc_*[i] and q_density_*[i] rows move from FAIL (~0.18-0.20 rtol) into CLEAN or GRAY (≤0.02 rtol).
**Requirements**: TBD (covered by CONTEXT.md D-01..D-06)
**Depends on:** Phase 56
**Plans:** 1/1 plans complete

Plans:
- [x] 57-01-PLAN.md — Switch ChannelAndContacts SPL+SCB HTC pipeline to T_film, document eval-point convention in HTC correlation docstrings, regenerate parity_report.csv

### Phase 58: MTK system determinacy repair

**Goal:** Fix the MTK system determinacy gap that causes seven Phase-58 in-scope scenarios (3 MTR + VAL-01 HD Fourier + VAL-02 two-plate steady + VAL-02 transient + PK validation) to fail at the `mtkcompile`/`solve_steady` boundary. Root cause (verified live): `HeatDiffusion`'s `power(t)` is declared as an `@variables` unknown but no equation closes it; the broken scenarios forgot the `hd.power ~ <value>` connection-list pin that `build_loop_lof_bypass` (`src/examples.jl:499`) and `build_loop_pk` (`:651`) already use. Fix at source per the user's directive — no `check_length=false` workarounds, no MTK package downgrades. Add the missing pins, audit every `fully_determined=false` site, and ship `test/test_determinacy.jl` as the regression target so this class of bug cannot recur silently across MTK upgrades.
**Requirements**: none — Phase 58 has no mapped REQ-IDs in REQUIREMENTS.md (v1.1 REQs were closed by Phases 52–56). Validation surface is `test/test_determinacy.jl` plus the seven in-scope scenarios reaching working solver calls.
**Depends on:** Phase 57
**Plans:** 5/5 plans complete

Plans:
**Wave 1**
- [x] 58-01-PLAN.md — Diagnostic table + fully_determined audit + Wave 0 regression scaffold (test/test_determinacy.jl created with canonical-builder testset GREEN, Phase-58 scenario testset RED-as-expected)

**Wave 2** *(blocked on Wave 1)*
- [x] 58-02-PLAN.md — MTR family fix: add `hd.power ~ 1e4` to MTR sym/asym/one-sided conns, flip three audit sites; sync test_determinacy.jl helpers (3 of 5 Phase-58 scenarios green)

**Wave 3** *(blocked on Wave 2)*
- [x] 58-03-PLAN.md — VAL-01 HD Fourier fix: add `hd_v01.power ~ 0.0` to conns_v01, flip audit; sync helper (4 of 5 green)

**Wave 4** *(blocked on Wave 3)*
- [x] 58-04-PLAN.md — VAL-02 fixes: two-plate steady (two pins) + transient symbol-access (`ssys.sys.T_wall_callable` → `ssys.T_wall_callable`) + simple_loop audit flip; sync helper (5 of 5 green)

**Wave 5** *(blocked on Wave 4)*
- [x] 58-05-PLAN.md — Phase-close audit + PK verify: flip last bug-hiding site (test_heat_diffusion.jl:185), inline-comment legitimate-structural sites, tighten flapper.jl:38 docstring, full bin/jl test/runtests.jl green

---

## Coverage

22/22 v1.1 requirements mapped to exactly one phase.

| Phase | Requirements | Count |
|-------|--------------|-------|
| 52 | CONN-01, CONN-02, CONN-03, CONN-04 | 4 |
| 53 | CORE-01, CORE-02, CORE-03, CORE-04, CORE-05, NRG-01, NRG-02, NRG-03, NRG-04 | 9 |
| 54 | VAR-01, VAR-02, VAR-03, VAR-04 | 4 |
| 55 | TEST-01, TEST-02, TEST-03, TEST-05 | 4 |
| 56 | TEST-04 | 1 |
| **Total** | | **22** |

No orphaned requirements. No duplicates.
