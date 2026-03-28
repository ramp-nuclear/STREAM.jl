# ROADMAP: STREAM.jl

## Milestones

- ✅ **v0.1 MVP** — Phases 1-5 (shipped 2026-03-13)
- ✅ **v0.2 Component & Network Expansion** — Phases 6-9 (shipped 2026-03-13)
- ✅ **v0.3 HeatDiffusion** — Phases 10-12.1 (shipped 2026-03-14)
- ✅ **v0.4 Composability & Physics** — Phases 13-16 (shipped 2026-03-16)
- ✅ **v0.5 Code Quality** — Phases 17-19 (shipped 2026-03-16)
- ✅ **v0.6 Flow Reversal Systems** — Phases 20-26 (shipped 2026-03-27)
- 🚧 **v0.7 Safety Physics & Pressure Field** — Phases 27-30 (in progress)

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

### v0.7 Safety Physics & Pressure Field (In Progress)

**Milestone Goal:** Add per-cell absolute pressure to all channel components, implement subcooled boiling HTC with in-loop correction, deliver a post-process threshold analysis suite matching Python STREAM, and complete the laminar HTC and friction correlation libraries.

- [x] **Phase 27: Pressure Field** - Per-cell dP refactor, absolute pressure observables, sat_temperature, and T_sat/T_ONB in channels (completed 2026-03-28)
- [ ] **Phase 27.1: Channel Momentum Inertia** (INSERTED) - Momentum ODE in all channel variants, P[i] inertia correction, transient validation
- [ ] **Phase 28: Subcooled Boiling** - McAdams and Bergles-Rohsenow SCB correlations plus in-loop ChannelAndContacts correction
- [ ] **Phase 29: Threshold Analysis** - ONB/OFI/OSV/CHF physics functions and threshold_analysis post-processor
- [ ] **Phase 30: HTC & Friction Completions** - Marco-Han laminar Nusselt, developing laminar, maximal_htc, Colebrook-White, viscosity correction

## Phase Details

### Phase 27: Pressure Field
**Goal**: All channel variants expose per-cell absolute pressure and saturation-related observables so downstream safety calculations have the spatial pressure profile they require
**Depends on**: Phase 26
**Requirements**: PRES-01, PRES-02, PRES-03, PRES-04
**Success Criteria** (what must be TRUE):
  1. `sol[ch.P[i], :]` returns meaningful absolute pressure at each axial cell for Channel, ChannelAndContacts, and ChannelHeatFlux
  2. `sol[ch.dP]` equals `sum(dp[i])` exactly (per-cell sum, not i_mid lump)
  3. `sat_temperature(P)` is callable from MTK equations and returns physically correct saturation temperature for typical reactor pressures (e.g. ~393 K at 2 bar)
  4. `sol[ch.T_sat[i], :]` and `sol[ch.T_ONB[i], :]` are accessible observables in ChannelAndContacts and ChannelHeatFlux
**Plans:** 2/2 plans complete
Plans:
- [x] 27-01-PLAN.md — sat_temperature + _bergles_rohsenow_dT_ONB functions and unit tests
- [x] 27-02-PLAN.md — Per-cell dp[i] refactor, P[i]/T_sat[i]/T_ONB[i] observables, integration tests

### Phase 27.1: channel-momentum-inertia (INSERTED)

**Goal:** Add momentum ODE to all channel variants so transient inertia physics is correct, dp[i] stays algebraic, P[i] observed includes the distributed inertia correction term, and dP = port_in.P - port_out.P
**Requirements**: PRES-05, PRES-06, PRES-07, PRES-08, PRES-09, PRES-10, PRES-11, PRES-12, VAL-PRES-01
**Depends on:** Phase 27
**Plans:** 1/2 plans executed

Plans:
- [x] 27.1-01-PLAN.md — Momentum ODE in Channel/_channel_base_eqs, updated P[i]/dP observed, thermal variant updates
- [ ] 27.1-02-PLAN.md — Transient inertia tests PRES-05..12, Inertia compatibility, VAL-PRES-01 placeholder

### Phase 28: Subcooled Boiling
**Goal**: Subcooled boiling heat flux correlations are available as standalone functions and ChannelAndContacts can optionally apply an in-loop SCB correction when wall temperature exceeds T_ONB
**Depends on**: Phase 27
**Requirements**: SCB-01, SCB-02, SCB-03, SCB-04, ISCB-01, ISCB-02
**Success Criteria** (what must be TRUE):
  1. `McAdams_SCB_heat_flux` and `Bergles_Rohsenow_SCB_heat_flux` return physically plausible values in unit tests with known inputs
  2. `regime_dependent_q_scb` selects the correct correlation branch (McAdams for turbulent, Bergles-Rohsenow for laminar) based on Re
  3. ChannelAndContacts with `scb_correction` kwarg solves without error; when `T_wall[i] < T_ONB[i]` the effective HTC matches the pure single-phase result exactly
  4. When `T_wall >> T_sat`, the effective HTC from the SCB-corrected ChannelAndContacts is measurably higher than the uncorrected single-phase HTC
**Plans:** 2 plans
Plans:
- [x] 27-01-PLAN.md — sat_temperature + _bergles_rohsenow_dT_ONB functions and unit tests
- [ ] 27-02-PLAN.md — Per-cell dp[i] refactor, P[i]/T_sat[i]/T_ONB[i] observables, integration tests

### Phase 29: Threshold Analysis
**Goal**: The full Python STREAM threshold analysis suite is available as callable Julia functions (physics layer) and as a post-process runner that accepts an ODESolution and returns named safety margins per cell
**Depends on**: Phase 27
**Requirements**: THRS-01, THRS-02, THRS-03, THRS-04, THRS-05, THRS-06, THRS-07, THRS-08, THRS-09
**Success Criteria** (what must be TRUE):
  1. Each of the seven physics functions (T_ONB, q_boiling_onset, q_OFI, q_OSV, q_CHF x3, twall_limit) returns a scalar when called with representative MTR inputs
  2. `threshold_analysis(sol, ch; ...)` returns a NamedTuple with one field per threshold function provided by the caller
  3. `threshold_analysis` handles both steady-state and transient ODESolution without branching at the call site; steady returns one value per cell, transient returns a vector per cell
  4. Results for at least one CHF correlation match Python STREAM output within 5% on the canonical MTR geometry
**Plans:** 2 plans
Plans:
- [ ] 27-01-PLAN.md — sat_temperature + _bergles_rohsenow_dT_ONB functions and unit tests
- [ ] 27-02-PLAN.md — Per-cell dp[i] refactor, P[i]/T_sat[i]/T_ONB[i] observables, integration tests

### Phase 30: HTC & Friction Completions
**Goal**: The correlation library covers developing and fully-developed laminar rectangular-duct flow, a combinator for taking the elementwise maximum across correlations, Colebrook-White turbulent friction, and a viscosity correction factor
**Depends on**: Phase 28
**Requirements**: HTC-01, HTC-02, HTC-03, HTC-04, FRIC-01, FRIC-02
**Success Criteria** (what must be TRUE):
  1. `Marco_Han_Nusselt(aspect_ratio)` returns tabulated Nu values within 1% of published data for standard aspect ratios (e.g. Nu=7.541 for square duct)
  2. `fully_developed_laminar_h_spl` and `developing_laminar_h_spl` return pluggable 4-arg closures accepted by `regime_dependent` without modification
  3. `maximal_htc(corr1, corr2)` returns a closure that produces the elementwise max Nu when called; demonstrated with at least two correlations
  4. `turbulent_friction(Re, epsilon)` returns Darcy friction factor consistent with Moody chart values; smooth-pipe limit matches Blasius within 2% for Re in [4000, 1e5]
**Plans:** 2 plans
Plans:
- [ ] 27-01-PLAN.md — sat_temperature + _bergles_rohsenow_dT_ONB functions and unit tests
- [ ] 27-02-PLAN.md — Per-cell dp[i] refactor, P[i]/T_sat[i]/T_ONB[i] observables, integration tests

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
| 27. Pressure Field | v0.7 | 2/2 | Complete   | 2026-03-28 |
| 27.1. Channel Momentum Inertia | v0.7 | 1/2 | In Progress|  |
| 28. Subcooled Boiling | v0.7 | 0/? | Not started | - |
| 29. Threshold Analysis | v0.7 | 0/? | Not started | - |
| 30. HTC & Friction Completions | v0.7 | 0/? | Not started | - |

---

*Created: 2026-03-12*
*Updated: 2026-03-28 — Phase 27.1 planned (channel momentum inertia)*
