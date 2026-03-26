# ROADMAP: STREAM.jl

## Milestones

- ✅ **v0.1 MVP** — Phases 1-5 (shipped 2026-03-13)
- ✅ **v0.2 Component & Network Expansion** — Phases 6-9 (shipped 2026-03-13)
- ✅ **v0.3 HeatDiffusion** — Phases 10-12.1 (shipped 2026-03-14)
- ✅ **v0.4 Composability & Physics** — Phases 13-16 (shipped 2026-03-16)
- ✅ **v0.5 Code Quality** — Phases 17-19 (shipped 2026-03-16)
- 🚧 **v0.6 Flow Reversal Systems** — Phases 20-24 (in progress)

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

### 🚧 v0.6 Flow Reversal Systems (In Progress)

**Milestone Goal:** Enable loss-of-flow accident simulation — from forced flow through pump coastdown, flow reversal, Flapper opening, to established natural circulation.

- [x] **Phase 20: Sign Safety** - Audit and fix all channel components to handle negative mass flow correctly (completed 2026-03-17)
- [x] **Phase 21: Fluid Properties & Natural Convection** - Add thermal expansion coefficient, Gr/Ra utilities, and Elenbaas HTC correlation (completed 2026-03-17)
- [x] **Phase 22: Time-Varying Pump** - Enable callable dP_pump for coastdown and ramp scenarios (completed 2026-03-18)
- [x] **Phase 23: Flapper & Solver Events** - Implement Flapper check-valve component with MTK continuous event and expose callback API (completed 2026-03-20)
- [x] **Phase 24: Loss-of-Flow Validation** - Validate full loss-of-flow transient end-to-end against analytical expectations (completed 2026-03-21)
- [x] **Phase 24.1: Bypass LOF Topology** - Replace series-loop LOF model with real bypass topology (junctions, parallel paths, channel momentum inertia, natural circulation) (completed 2026-03-21)
- [x] **Phase 25: Argument Structure Audit** - Sweep all public functions and constructors, replace keyword-only where positional + multiple dispatch is more idiomatic Julia (completed 2026-03-26)
- [x] **Phase 26: NC Regime HTC + LOF Cleanup** - Wire NC detection (Gr/Re²>1 → Elenbaas override) into regime_dependent, wire into build_loop_lof_bypass, validate NC temperature rise against Elenbaas, remove dead build_loop_lof, fix stale docs (completed 2026-03-26)

## Phase Details

### Phase 20: Sign Safety
**Goal**: All channel components handle negative mass flow without non-physical results
**Depends on**: Phase 19
**Requirements**: SIGN-01, SIGN-02, SIGN-03, SIGN-04
**Success Criteria** (what must be TRUE):
  1. A Channel run with negative mdot produces a reversed (decreasing axial) temperature profile matching the upstream-to-outlet direction
  2. Re, Nu, velocity, and Pe @observed variables remain positive and physically meaningful under negative mdot in ChannelAndContacts
  3. ChannelHeatFlux produces correct energy balance under negative mdot
  4. The test suite explicitly asserts correct reversed temperature profile and positive Re for all three channel types run with mdot < 0
**Plans**: 2 plans

Plans:
- [ ] 20-01: Sign-safe audit and fix for Channel, ChannelAndContacts, ChannelHeatFlux
- [ ] 20-02: Reversed-flow test suite (SIGN-04)

### Phase 21: Fluid Properties & Natural Convection
**Goal**: beta_water, Gr, Ra, and Elenbaas correlation are available and validated for natural-convection-coupled simulations
**Depends on**: Phase 20
**Requirements**: FLUID-01, FLUID-02, FLUID-03, NATCONV-01, NATCONV-02
**Success Criteria** (what must be TRUE):
  1. `beta_water(T)` is callable from any MTK equation (registered symbolic) and returns physically correct thermal expansion coefficient for light water
  2. `Gr(beta, g, dT, L, nu)` and `Ra(Gr_val, Pr_val)` return correct dimensionless numbers from plain Julia calls at known reference conditions
  3. `elenbaas_nusselt(Ra, b, L)` returns Nu values that match published Elenbaas table values or analytical limiting cases within stated tolerance
  4. `elenbaas_nusselt` is accepted as a pluggable HTC argument in Channel or ChannelAndContacts without code changes to those components
**Plans**: 2 plans

Plans:
- [ ] 21-01-PLAN.md — beta_water, dimensionless.jl, HTC 4-arg interface extension
- [ ] 21-02-PLAN.md — Elenbaas correlation and validation tests

### Phase 22: Time-Varying Pump
**Goal**: Pump accepts a Julia callable for time-varying pressure rise, enabling coastdown and ramp scenarios; solve_transient redesigned to clean positional API
**Depends on**: Phase 20
**Requirements**: PUMP-01, PUMP-02, PUMP-03
**Success Criteria** (what must be TRUE):
  1. `Pump(dP_pump=f)` where `f` is a Julia callable `f(t) -> Float64` compiles and runs a transient without changes to `solve_transient`
  2. Existing `Pump(dP_pump=scalar)` and `Pump(mdot0=...)` modes produce results identical to v0.5 (no regression)
  3. A pump ramped from 1e5 to 0 Pa over 100 s produces mdot decay to zero that matches the analytical expectation within tolerance
**Plans**: 2 plans

Plans:
- [ ] 22-01-PLAN.md — Pump callable dispatch, solve_transient redesign, build_loop_transient update
- [ ] 22-02-PLAN.md — PUMP-01/02/03 tests, SOLV-02 and VAL-02 test rewrites

### Phase 23: Flapper & Solver Events
**Goal**: Flapper check-valve component available with MTK continuous event triggering and solve_transient exposes user-supplied callbacks
**Depends on**: Phase 21, Phase 22
**Requirements**: FLAP-01, FLAP-02, FLAP-03, FLAP-04, FLAP-05, FLAP-06, SOLV-01
**Success Criteria** (what must be TRUE):
  1. `Flapper` compiles as an MTK ODESystem with FlowPorts and is wired to a reference flow via a plain algebraic equation during system composition
  2. Flapper resistance stays near maximum when ref_mdot exceeds threshold — a test verifies near-zero leakage through the Flapper path under positive flow
  3. When ref_mdot crosses threshold from above, T_open is recorded without solver restart and the C1 smooth ramp correctly transitions resistance from closed to open
  4. `solve_transient` accepts a `callbacks` keyword argument and passes it through to the DifferentialEquations.jl solver alongside MTK-native events
**Plans**: 2 plans

Plans:
- [x] 23-01-PLAN.md — Flapper component implementation (FLAP-01..04), module wiring, SOLV-01 scope
- [x] 23-02-PLAN.md — Flapper closed/open tests (FLAP-05, FLAP-06) and SOLV-01 smoke test

### Phase 24: Loss-of-Flow Validation
**Goal**: Full loss-of-flow transient validated end-to-end: forced flow, pump coastdown, flow reversal, Flapper opening, natural circulation
**Depends on**: Phase 23
**Requirements**: VAL-01, VAL-02
**Success Criteria** (what must be TRUE):
  1. The simulation runs continuously from forced-flow steady state through pump-off, mdot sign reversal, Flapper opening, and into natural circulation without solver restart or crash
  2. Energy balance (Q_in = mdot * cp * dT) holds within stated tolerance at all simulated time checkpoints throughout the transient
  3. Natural circulation temperature rise matches the Elenbaas-based analytical estimate within a stated tolerance
**Plans**: 1 plan

Plans:
- [x] 24-01-PLAN.md — build_loop_lof() helper and VAL-01/VAL-02 test suite

### Phase 24.1: Bypass LOF Topology
**Goal**: Replace the series-loop LOF model with a physically correct bypass topology: real junctions, parallel paths (channel vs flapper shortcut), channel momentum inertia, and validated natural circulation after flow reversal
**Depends on**: Phase 24
**Requirements**: LOF-01, LOF-02, LOF-03, VAL-01, VAL-02
**Success Criteria** (what must be TRUE):
  1. Channel components have `L/A * Dt(mdot)` in their pressure equations; transient mdot shows inertial overshoot at flow reversal
  2. `build_loop_lof_bypass()` compiles and runs: 4-node/6-edge network with ChannelHeatFlux, unheated return Channel, Flapper, Resistor, HX, Pump+Inertia
  3. Channel mdot crosses zero and settles at a negative (upward) NC value after the Flapper opens
  4. Energy balance holds within 5% rtol throughout the transient
  5. NC equilibrium mdot magnitude matches analytical buoyancy estimate within 20%
**Plans**: 2 plans

Plans:
- [x] 24.1-01-PLAN.md — Channel momentum inertia + build_loop_lof_bypass topology
- [x] 24.1-02-PLAN.md — Bypass LOF transient tests and NC validation

### Phase 25: Argument Structure Audit
**Goal**: Sweep all exported functions and component constructors; replace keyword-only signatures with positional arguments + multiple dispatch wherever it improves clarity or enables type-based dispatch
**Depends on**: Phase 24.1
**Requirements**: (none — code quality / convention alignment)
**Success Criteria** (what must be TRUE):
  1. All functions where the argument type determines behavior (e.g., `Real` vs `Function`) use positional dispatch instead of runtime `isa` checks
  2. Short utility functions and internal `_`-prefixed helpers use positional arguments where natural
  3. Large multi-arg constructors where keyword-only prevents argument-order bugs remain keyword-only (no regression)
  4. CLAUDE.md updated to reflect the new rule: positional + dispatch preferred when types differ; keyword-only when distinguishing between named concepts of the same type
**Plans**: 1 plan

Plans:
- [x] 25-01: Argument structure sweep and CLAUDE.md update

### Phase 26: NC Regime HTC + LOF Cleanup
**Goal**: Wire natural convection detection (Gr/Re²>1 criterion, matching Python STREAM) into `regime_dependent`; use it in `build_loop_lof_bypass` so the NC phase of a LOF transient uses Elenbaas HTC; validate NC temperature rise against Elenbaas prediction; remove dead `build_loop_lof`; fix all stale docs from v0.6 audit
**Depends on**: Phase 25
**Requirements**: VAL-02, NATCONV-01
**Success Criteria** (what must be TRUE):
  1. `regime_dependent` accepts optional `htc_natural`, `Dh`, `g` kwargs; when provided, wraps forced-conv HTC in `ifelse(Gr_val > Re^2, htc_natural(...), htc_forced)` — MTK-compatible via `ifelse`
  2. `build_loop_lof_bypass` wires `regime_dependent` (with `elenbaas_htc` as NC override and laminar friction below Re_transition) for both `ch` and `ret`
  3. VAL-02 test asserts that NC-phase temperature rise matches the Elenbaas-based analytical estimate within a stated tolerance (currently the test only validates mdot via gravity-friction balance)
  4. `build_loop_lof` is removed from `src/examples.jl` and from exports in `STREAM.jl`
  5. 3 channel docstrings updated to document the 4-arg `(Re, Pr, T_bulk, T_wall)->Nu` HTC interface
  6. `24.1-VERIFICATION.md` rewritten to reflect actual HEAD state (SC1 channel inertia: PASS, SC2 parallel topology: PASS, VAL-02: PASS after this phase)
  7. `build_loop_lof_bypass` docstring stale "R_ext not used" note removed
**Plans**: 2 plans

Plans:
- [x] 26-01: Extend regime_dependent with NC detection + wire into build_loop_lof_bypass
- [x] 26-02: VAL-02 temperature-rise test + remove build_loop_lof + stale doc fixes

## Progress

**Execution Order:** Phases execute in numeric order: 20 → 21 → 22 → 23 → 24 → 24.1 → 25

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
| 20. Sign Safety | 2/2 | Complete    | 2026-03-17 | - |
| 21. Fluid Properties & Natural Convection | 2/2 | Complete    | 2026-03-17 | - |
| 22. Time-Varying Pump | 2/2 | Complete    | 2026-03-18 | - |
| 23. Flapper & Solver Events | v0.6 | 2/2 | Complete    | 2026-03-20 |
| 24. Loss-of-Flow Validation | v0.6 | 1/1 | Complete    | 2026-03-21 |
| 24.1. Bypass LOF Topology | v0.6 | 2/2 | Complete   | 2026-03-21 |
| 25. Argument Structure Audit | v0.6 | 1/1 | Complete    | 2026-03-26 |
| 26. NC Regime HTC + LOF Cleanup | v0.6 | 2/2 | Complete   | 2026-03-26 |

---

*Created: 2026-03-12*
*Updated: 2026-03-21 — Phase 24.1 plans created: channel momentum inertia + bypass LOF topology*
