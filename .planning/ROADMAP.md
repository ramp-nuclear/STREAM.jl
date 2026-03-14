# ROADMAP: STREAM.jl

## Milestones

- ✅ **v0.1 MVP** — Phases 1-5 (shipped 2026-03-13)
- ✅ **v0.2 Component & Network Expansion** — Phases 6-9 (shipped 2026-03-13)
- 🚧 **v0.3 HeatDiffusion** — Phases 10-12 (in progress)

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

### 🚧 v0.3 HeatDiffusion (In Progress)

**Milestone Goal:** Implement a 2D finite-difference fuel plate (HeatDiffusion) and upgrade ChannelAndContacts to two-sided thermal coupling, validated against the Python STREAM MTR reference case.

## Phase Summary

- [x] **Phase 10: ChannelAndContacts Two-Sided Upgrade** - Upgrade ChannelAndContacts to thermal_left/right ports, clear v0.2 tech debt, verify adiabatic default (completed 2026-03-13)
- [x] **Phase 11: HeatDiffusion Component** - Implement 2D FD fuel plate with x-direction diffusion, two-sided ThermalPort arrays, and isolated unit tests (completed 2026-03-14)
- [x] **Phase 12: MTR Validation** - Couple HeatDiffusion + two ChannelAndContacts in MTR geometry and validate against Python STREAM within 1% (completed 2026-03-14)
- [ ] **Phase 12.1: PipeGeometry Struct** - Introduce PipeGeometry struct, refactor channel constructors, restore quantitative VAL-01/02/03 assertions with correct rectangular MTR geometry (0/2 plans)

## Phase Details

### Phase 10: ChannelAndContacts Two-Sided Upgrade
**Goal**: ChannelAndContacts exposes stable two-sided thermal port API and v0.2 tech debt is cleared, establishing the interface contract that HeatDiffusion will be written against
**Depends on**: Phase 9 (v0.2 ChannelAndContacts complete)
**Requirements**: DEBT-01, DEBT-02, DEBT-03, CHAN-01, CHAN-02, CHAN-03
**Success Criteria** (what must be TRUE):
  1. `_channel_base_eqs` can be called without a `t_inlet` argument and all existing tests pass
  2. ChannelAndContacts has `thermal_left[1:n]` and `thermal_right[1:n]` port arrays; old `thermal_ports` name is gone from the codebase
  3. `q_wall[i]` in ChannelAndContacts is verified by test to equal `thermal_left[i].Q_flow + thermal_right[i].Q_flow`
  4. A test with only one side connected confirms the unconnected side has Q_flow = 0 at steady state (adiabatic default explicit, not assumed)
  5. The THERM-03 test directly asserts ChannelAndContacts behavioral output rather than relying on a proxy
**Plans**: 2 plans

Plans:
- [ ] 10-01-PLAN.md — Rewrite ChannelAndContacts (dual ports, two-sided energy balance), remove t_inlet from _channel_base_eqs, add ConstantTemperature, DEBT-03 doc fix
- [ ] 10-02-PLAN.md — Update THERM-01 port assertions, rewrite THERM-03 as CAC-vs-CHF, add CHAN-03 adiabatic test

### Phase 11: HeatDiffusion Component
**Goal**: HeatDiffusion is a working, unit-tested 2D finite-difference fuel plate component with x-direction diffusion and two-sided ThermalPort arrays, axis convention locked and validated in isolation
**Depends on**: Phase 10
**Requirements**: HDIFF-01, HDIFF-02, HDIFF-03, HDIFF-04, HDIFF-05
**Success Criteria** (what must be TRUE):
  1. User can instantiate `HeatDiffusion(nz=5, nx=3, ...)` and the resulting MTK system has state `T(t)[1:nz, 1:nx]` with rows=axial and cols=lateral (matching Python STREAM axis convention)
  2. HeatDiffusion with pinned boundary temperatures (T_boundary < T_interior) solves at steady state with `sum(thermal_left[i].Q_flow) < 0` and `sum(thermal_right[i].Q_flow) < 0` (heat leaving the plate, correct Q_flow sign)
  3. `power_shape[1:nz, 1:nx]` (constructor parameter) and `power` (MTK parameter) together drive the correct volumetric heat source in the FD equations
  4. Leaving `thermal_right` unconnected and connecting only `thermal_left` produces a valid compiled system where all `thermal_right[i].Q_flow ~ 0` holds at steady state
**Plans**: 2 plans

Plans:
- [ ] 11-01-PLAN.md — Implement _diffusion_eqs helper and HeatDiffusion constructor; export from STREAM module (HDIFF-01, HDIFF-02, HDIFF-03, HDIFF-04)
- [x] 11-02-PLAN.md — Write Phase 11 test suite: instantiation/port smoke tests + steady-state behavioral test + adiabatic one-sided test (HDIFF-01 through HDIFF-05) (completed 2026-03-14)

### Phase 12: MTR Validation
**Goal**: Coupled HeatDiffusion + two ChannelAndContacts in MTR geometry (cladding+meat+cladding, two water channels) solves and matches Python STREAM reference outputs within 1%, including an asymmetric heating case that confirms left/right coupling direction is correct
**Depends on**: Phase 11
**Requirements**: VAL-01, VAL-02, VAL-03
**Success Criteria** (what must be TRUE):
  1. Steady-state T_outlet on both channels and T_plate (center and wall) match Python STREAM MTR reference within 1%
  2. An asymmetric test (left channel 50 K hotter than right) produces a non-symmetric plate temperature profile consistent with Python STREAM — confirming the left/right coupling direction is not swapped
  3. One-sided coupling (HeatDiffusion connected to one channel, other face adiabatic) solves correctly and is validated against Python STREAM one-sided reference
**Plans**: 2 plans

Plans:
- [ ] 12-01-PLAN.md — Write generate_mtr_reference.py (VAL-01/02/03 scenarios) + HDIFF-03 gap test; checkpoint to run Python script and obtain reference constants
- [ ] 12-02-PLAN.md — Write VAL-01 (symmetric MTR), VAL-02 (asymmetric), VAL-03 (one-sided) Julia integration tests with hardcoded reference constants

### Phase 12.1: PipeGeometry Struct (INSERTED)

**Goal:** Introduce `PipeGeometry` struct with `L`, `Dh`, `A`, `heated_parts::NTuple{2,Float64}` and two keyword-argument outer constructors (`circular` via kwarg `D`, `rectangular` via kwarg `y`). Refactor `Channel`, `ChannelHeatFlux`, and `ChannelAndContacts` constructors to accept `PipeGeometry`. Update all call sites in tests and regenerate correct VAL-01/02/03 reference constants with proper rectangular MTR geometry, then add 1% quantitative assertions.
**Requirements**: none (addresses physics correctness gap from Phase 12)
**Depends on:** Phase 12
**Plans:** 1/2 plans executed

Plans:
- [ ] 12.1-01-PLAN.md — Define PipeGeometry struct + refactor all three channel constructors + update all test call sites + update generate_mtr_reference.py
- [ ] 12.1-02-PLAN.md — Run Python reference script (checkpoint), hardcode reference constants into VAL-01/02/03 with 1% assertions, update STATE.md stale entries

## Progress

**Execution Order:** 10 → 11 → 12 → 12.1

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
| 12.1. PipeGeometry Struct | 1/2 | In Progress|  | - |

---

*Created: 2026-03-12*
*Updated: 2026-03-14 — Phase 12.1 plans created (2 plans, 2 waves)*
