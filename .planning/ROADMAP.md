# ROADMAP: STREAM.jl

## Milestones

- ✅ **v0.1 MVP** — Phases 1-5 (shipped 2026-03-13)
- ✅ **v0.2 Component & Network Expansion** — Phases 6-9 (shipped 2026-03-13)
- ✅ **v0.3 HeatDiffusion** — Phases 10-12.1 (shipped 2026-03-14)
- ✅ **v0.4 Composability & Physics** — Phases 13-16 (shipped 2026-03-16)
- ✅ **v0.5 Code Quality** — Phases 17-19 (shipped 2026-03-16)
- ✅ **v0.6 Flow Reversal Systems** — Phases 20-26 (shipped 2026-03-27)
- 🔄 **v0.7 Safety Physics & Pressure Field** — Phases 27-30 (in progress)
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
<summary>🔄 v0.7 Safety Physics & Pressure Field (Phases 27-30) — IN PROGRESS</summary>

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
- [ ] Phase 30: HTC & Friction Completions (0/? plans) — pending

</details>

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
| 30. HTC & Friction Completions | v0.7 | 0/? | Pending | — |

---

*Created: 2026-03-12*
*Updated: 2026-03-31 — Phase 29 threshold-analysis complete (2/2 plans); Phase 30 next*
