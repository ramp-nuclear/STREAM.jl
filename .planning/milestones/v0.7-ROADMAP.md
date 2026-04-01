# ROADMAP: STREAM.jl

## Milestones

- ✅ **v0.1 MVP** — Phases 1-5 (shipped 2026-03-13)
- ✅ **v0.2 Component & Network Expansion** — Phases 6-9 (shipped 2026-03-13)
- ✅ **v0.3 HeatDiffusion** — Phases 10-12.1 (shipped 2026-03-14)
- ✅ **v0.4 Composability & Physics** — Phases 13-16 (shipped 2026-03-16)
- ✅ **v0.5 Code Quality** — Phases 17-19 (shipped 2026-03-16)
- ✅ **v0.6 Flow Reversal Systems** — Phases 20-26 (shipped 2026-03-27)
- 🚧 **v0.7 Safety Physics & Pressure Field** — Phases 27-32 (in progress)
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
<summary>🔄 v0.7 Safety Physics & Pressure Field (Phases 27-32) — IN PROGRESS</summary>

- [x] Phase 27: Pressure Field (2/2 plans) — completed 2026-03-28
- [x] Phase 27.1: Channel Momentum & Inertia (3/3 plans) — completed 2026-03-29
- [x] Phase 28: Subcooled Boiling (2/2 plans) — completed 2026-03-30
- [ ] Phase 29: Threshold Analysis (0/2 plans) — planned
  **Goal:** Nuclear safety threshold correlations (ONB, OFI, OSV, CHF) + post-processing framework
  **Plans:** 2 plans
  **Requirements:** [THRS-01, THRS-02, THRS-03, THRS-04, THRS-05, THRS-06, THRS-07, THRS-08, THRS-09]
  Plans:
  - [x] 29-01-PLAN.md — Physics functions (THRS-01..08): Bergles-Rohsenow T_ONB, boiling onset, OFI, OSV, CHF (Sudo-Kaminaga, Mirshak, Fabrega), twall_limit
  - [x] 29-02-PLAN.md — Post-processing framework (THRS-09): ChannelState, threshold_analysis, chfr, pre-built wrappers
- [ ] Phase 30: HTC & Friction Completions (0/2 plans) — planned
  **Goal:** Complete the HTC and friction correlation library — Marco-Han laminar Nusselt, developing laminar (Shah & London), maximal_htc combiner, Colebrook-White turbulent friction, viscosity correction
  **Plans:** 2 plans
  **Requirements:** [HTC-01, HTC-02, HTC-03, HTC-04, FRIC-01, FRIC-02]
  Plans:
  - [x] 30-01-PLAN.md — File split (correlations.jl -> htc/ + friction/) + Marco_Han_Nusselt, turbulent_friction, viscosity_correction
  - [x] 30-02-PLAN.md — HTC factories (_two_sided_heating_nusselt, fully_developed_laminar_h_spl, developing_laminar_h_spl, maximal_htc)
- [ ] Phase 31: Write Phase 27 Verification Document (0/1 plans) — planned
  **Goal:** Write 27-VERIFICATION.md retroactively from VALIDATION.md evidence — closes PRES-01..04 documentation gap
  **Plans:** 1 plan
  **Requirements:** [PRES-01, PRES-02, PRES-03, PRES-04]
  **Gap Closure:** Closes PRES-01..04 partial status from v0.7 audit
  Plans:
  - [x] 31-01-PLAN.md — Write 27-VERIFICATION.md + update REQUIREMENTS.md traceability for PRES-01..04
- [ ] Phase 32: THRS-09 & Phase 30 Integration Hardening (0/1 plans) — planned
  **Goal:** Add precondition guard to _extract_channel_state, add E2E integration test (real MTK solve → extract → analyze), add Phase 30 correlation in-system smoke test
  **Plans:** 1 plan
  **Requirements:** [THRS-09]
  **Gap Closure:** Closes THRS-09 integration gap + Phase 30 integration gap from v0.7 audit
  Plans:
  - [x] 32-01-PLAN.md — Precondition guard + docstring on _extract_channel_state, E2E test, Phase 30 smoke test

</details>

### Phase 30: HTC & Friction Completions
**Goal**: Complete the HTC and friction correlation library with missing laminar and turbulent correlations needed for full physical accuracy
**Depends on**: Phase 29
**Requirements**: HTC-01, HTC-02, HTC-03, HTC-04, FRIC-01, FRIC-02
**Success Criteria** (what must be TRUE):
  1. Marco_Han_Nusselt(aspect_ratio) returns physically correct Nu for fully-developed laminar rectangular duct flow
  2. fully_developed_laminar_h_spl and developing_laminar_h_spl are usable as drop-in correlation closures in Channel
  3. maximal_htc(correlations...) returns elementwise max across all provided correlations
  4. turbulent_friction(Re, epsilon) matches Colebrook-White values from Python STREAM within 0.1%
  5. viscosity_correction returns the correct multiplicative factor matching Python STREAM reference
**Plans**: 2 plans

### Phase 31: Write Phase 27 Verification Document
**Goal**: Retroactively write 27-VERIFICATION.md from existing VALIDATION.md evidence, closing the PRES-01..04 documentation gap identified by the v0.7 audit
**Depends on**: Phase 30
**Requirements**: PRES-01, PRES-02, PRES-03, PRES-04
**Gap Closure**: v0.7 audit gap — Phase 27 VERIFICATION.md was never written despite all PRES-01..04 being fully implemented and validated
**Success Criteria** (what must be TRUE):
  1. 27-VERIFICATION.md exists in .planning/phases/27-pressure-field/
  2. All 4 PRES-01..04 requirements listed as verified with evidence from VALIDATION.md
  3. PRES-01..04 status in REQUIREMENTS.md traceability updated from Pending to Complete
**Plans**: 1 plan

### Phase 32: THRS-09 & Phase 30 Integration Hardening
**Goal**: Add a precondition guard to `_extract_channel_state`, add an E2E integration test (real MTK solve → extract → analyze pipeline), and add a Phase 30 correlation in-system smoke test
**Depends on**: Phase 30
**Requirements**: THRS-09
**Gap Closure**: v0.7 audit gaps — THRS-09 `_extract_channel_state` silent failure for Channel/ChannelHeatFlux; THRS-09 E2E pipeline untested; Phase 30 correlations never used in compiled system
**Success Criteria** (what must be TRUE):
  1. `_extract_channel_state` raises a clear `ArgumentError` when called with a non-ChannelAndContacts system
  2. Docstring for `_extract_channel_state` documents the ChannelAndContacts precondition
  3. test_analysis.jl contains an E2E test: mtkcompile + solve a ChannelAndContacts system, call _extract_channel_state, call threshold_analysis, verify NamedTuple output
  4. test_correlations.jl (or test_channel.jl) contains a smoke test: build and compile a Channel with fully_developed_laminar_h_spl or developing_laminar_h_spl — no symbolic tracing error
**Plans**: 1 plan

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
| 30. HTC & Friction Completions | v0.7 | 2/2 | Complete    | 2026-04-01 |
| 31. Write Phase 27 Verification Document | v0.7 | 1/1 | Complete   | 2026-04-01 |
| 32. THRS-09 & Phase 30 Integration Hardening | v0.7 | 1/1 | Complete    | 2026-04-01 |

---

*Created: 2026-03-12*
*Updated: 2026-04-01 — Gap closure phases 31-32 added from v0.7 audit*
