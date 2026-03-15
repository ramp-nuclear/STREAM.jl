# ROADMAP: STREAM.jl

## Milestones

- ✅ **v0.1 MVP** — Phases 1-5 (shipped 2026-03-13)
- ✅ **v0.2 Component & Network Expansion** — Phases 6-9 (shipped 2026-03-13)
- ✅ **v0.3 HeatDiffusion** — Phases 10-12.1 (shipped 2026-03-14)
- 🚧 **v0.4 Composability & Physics** — Phases 13-16 (in progress)

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

### 🚧 v0.4 Composability & Physics (In Progress)

**Milestone Goal:** Make Julia STREAM ergonomic for real reactor assembly workflows and physically correct for the full MTR operating envelope (including laminar flow).

- [x] **Phase 13: Physics Foundation** — Dh fix, fixed-flow Pump (completed 2026-03-14)
- [x] **Phase 14: Laminar Correlations** — Pluggable HTC/friction correlations with regime switching (completed 2026-03-14)
- [x] **Phase 15: Composition Helpers & QoL** — symmetric_plate, plate, one_sided_connection, compose_systems, @observed, gravity check, port helper (completed 2026-03-15)
- [ ] **Phase 16: Validation** — Transient HeatDiffusion, two-plate CAC, one-sided quantitative assertion

## Phase Details

### Phase 13: Physics Foundation
**Goal**: Physics computations are correct for rectangular MTR geometry; fixed-flow Pump available
**Depends on**: Phase 12.1 (PipeGeometry struct exists)
**Requirements**: PHY-01, PHY-05
**Plans**: 2 plans
Plans:
- [ ] 13-01-PLAN.md — Redesign PipeGeometry struct, add factory constructors, migrate all call sites
- [ ] 13-02-PLAN.md — Add Pump(mdot0=...) dual-mode, regenerate MTR reference constants
**Success Criteria** (what must be TRUE):
  1. `PipeGeometry.rectangular(...)` computes `Dh = 4A / wet_perimeter` using all four walls; `wet_perimeter` is a readable field
  2. `PipeGeometry.circular(D=...)` sets `wet_perimeter = π*D`; existing circular-geometry tests still pass
  3. `Pump(mdot0=0.6)` assembles and solves a loop with fixed mass flow rate; `Pump(dp=1e5)` still works

### Phase 14: Laminar Correlations
**Goal**: ChannelAndContacts supports pluggable HTC and friction correlations including laminar regime
**Depends on**: Phase 13 (corrected Dh available; existing turbulent tests provide regression baseline)
**Requirements**: PHY-02, PHY-03, PHY-04
**Plans**: 2 plans
Plans:
- [ ] 14-01-PLAN.md — Create src/correlations.jl (all six correlation functions/factories), extend PipeGeometry with width/depth, wire into STREAM module
- [ ] 14-02-PLAN.md — Refactor _channel_base_eqs and Channel to accept correlation kwargs; add PHY-02/03/04 tests
**Success Criteria** (what must be TRUE):
  1. `constant_Nusselt(Nu=8.235)` can be passed as `htc_correlation` to ChannelAndContacts and produces the expected constant Nu in solution
  2. `laminar_friction(Re)` returns `64/Re` (or rectangular correction) and can be passed as `friction_correlation` to ChannelAndContacts
  3. `regime_dependent(; Re_transition=2300)` wraps any htc + friction pair and switches based on Re; a test exercises both branches
  4. Existing Dittus-Boelter + Blasius path remains default and all prior MTR tests still pass

### Phase 15: Composition Helpers & QoL
**Goal**: Users can assemble MTR subsystems in one call and inspect diagnostic variables from solutions
**Depends on**: Phase 13 (corrected Dh), Phase 14 (correlation pluggables available for use inside helpers)
**Requirements**: COMP-01, COMP-02, COMP-03, COMP-04, QOL-01, QOL-02, QOL-03
**Success Criteria** (what must be TRUE):
  1. `symmetric_plate(channel, fuel)` returns a solvable ODESystem; user can pass u0/p and get a solution without manual MTK wiring
  2. `plate(ch_left, ch_right, fuel)` and `one_sided_connection(channel, fuel, side=:left)` each return solvable ODESystems
  3. `compose_systems(sys_a, sys_b, connections)` merges two independently-built ODESystems into one solvable system
  4. After solving a ChannelAndContacts system, `sol[sys.ch.Re, :]` returns a length-nz array of Reynolds numbers
  5. `port(sys, :thermal_left, i)` returns the correct MTK subsystem; `check_gravity_mismatch(sys)` returns `:ok` on a balanced loop
**Plans**: 2 plans
Plans:
- [ ] 15-01-PLAN.md — Wave 0 test stubs; refactor ChannelAndContacts @observed (Re/Nu/v/Pe + 10 vars); create src/helpers.jl with port() and check_gravity_mismatch()
- [ ] 15-02-PLAN.md — Extend src/helpers.jl with symmetric_plate, plate, one_sided_connection, compose_systems; full COMP tests

### Phase 16: Validation
**Goal**: HeatDiffusion transient behavior and all two-plate coupling configurations are quantitatively validated
**Depends on**: Phase 15 (composition helpers available for use in validation assembly)
**Requirements**: VAL-01, VAL-02, VAL-03
**Success Criteria** (what must be TRUE):
  1. A transient HeatDiffusion test compares T_plate_center(t) to the analytical 1D slab Fourier series solution and passes within tolerance
  2. A system with two HeatDiffusion instances connected to one ChannelAndContacts (both thermal_left and thermal_right active) assembles and solves to a physically consistent steady state
  3. The one-sided connection test has a quantitative T_plate_center assertion derived from analytical energy balance (T_center = T_wall + q*L/(2kA)); the test comment documents the Python STREAM discrepancy
**Plans**: TBD

## Progress

**Execution Order:** Phases execute in numeric order: 13 → 14 → 15 → 16

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
| 15. Composition Helpers & QoL | 2/2 | Complete   | 2026-03-15 | - |
| 16. Validation | v0.4 | 0/TBD | Not started | - |

---

*Created: 2026-03-12*
*Updated: 2026-03-15 — Phase 15 replanned (2 plans: 15-01 QOL+observed refactor, 15-02 composition helpers)*
