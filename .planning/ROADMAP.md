# ROADMAP: STREAM.jl

## Milestones

- ✅ **v0.1 MVP** — Phases 1-5 (shipped 2026-03-13)
- 🚧 **v0.2 Component & Network Expansion** — Phases 6-9 (in progress)

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

### 🚧 v0.2 Component & Network Expansion (In Progress)

**Milestone Goal:** Validate multi-branch hydraulic networks, add gravity to vertical loops, add Inertia and HeatExchanger lumped components, and deliver ChannelAndContacts as the per-cell thermal interface for future fuel-plate coupling.

- [x] **Phase 6: Gravity Validation** - Gravity term validated in a vertical closed loop with cancellation test (completed 2026-03-13)
- [x] **Phase 7: Network Architecture** - Resistor component and multi-branch Cube problem solved via MTK connect() (completed 2026-03-13)
- [x] **Phase 8: Inertia and HeatExchanger** - Inertia ODE component validated; HeatExchanger exposed as public API (completed 2026-03-13)
- [ ] **Phase 9: ChannelAndContacts** - Per-cell ThermalPort array component implemented and validated against Channel

## Phase Details

### Phase 6: Gravity Validation
**Goal**: Gravity term is correctly wired and validated in a vertical closed loop
**Depends on**: Phase 5 (v0.1 complete)
**Requirements**: GRAV-01, GRAV-02
**Success Criteria** (what must be TRUE):
  1. A vertical closed loop (Channel with g_acc=9.80665 + Gravity component on return leg of equal height) assembles, compiles with mtkcompile, and solves without error
  2. The gravity cancellation test passes: equal up/down height gives the same steady-state mass flow rate as the horizontal reference loop within 1%
  3. The test suite passes with the new gravity tests included (no regressions in v0.1 tests)
**Plans**: 1 plan
Plans:
- [ ] 06-01-PLAN.md — add build_loop_vertical + GRAV-01/GRAV-02 tests

### Phase 7: Network Architecture
**Goal**: Multi-branch hydraulic networks assemble and solve correctly via MTK connect() semantics
**Depends on**: Phase 6
**Requirements**: NET-01, NET-02, NET-03
**Success Criteria** (what must be TRUE):
  1. Resistor component exists: `dp ~ R * mdot` with a scalar resistance parameter, and a standalone test confirms it compiles and solves
  2. The Cube problem (12 Resistors, 8 nodes, 1 Pump) assembles using multi-port connect() calls and solves without error
  3. The Cube problem flow distribution matches the analytical equivalent resistance (5/6 R) within 1%
**Plans**: 2 plans
Plans:
- [ ] 07-01-PLAN.md — Resistor component (NET-01): TDD implementation + export
- [ ] 07-02-PLAN.md — build_cube utility + NET-02/NET-03 Cube validation

### Phase 8: Inertia and HeatExchanger
**Goal**: Inertia ODE component and HeatExchanger public component are implemented and accessible
**Depends on**: Phase 7
**Requirements**: COMP-01, COMP-02
**Success Criteria** (what must be TRUE):
  1. Inertia component implements `dp ~ (L/A) * D(mdot)` and a transient test matches the Python STREAM Inertia result within 1%
  2. HeatExchanger is an exported public component (not internal _make_temp_bc) with a fixed outlet temperature and no pressure drop
  3. build_loop uses HeatExchanger instead of the internal _make_temp_bc; existing v0.1 validation tests continue to pass
**Plans**: 2 plans
Plans:
- [ ] 08-01-PLAN.md — Phase 8 test stubs + Inertia TDD implementation (COMP-01)
- [ ] 08-02-PLAN.md — HeatExchanger refactor: move _make_temp_bc, update build_loop call sites, export (COMP-02)

### Phase 9: ChannelAndContacts
**Goal**: Per-cell ThermalPort array component is implemented, tested, and backward-compatible with Channel
**Depends on**: Phase 8
**Requirements**: THERM-01, THERM-02, THERM-03
**Success Criteria** (what must be TRUE):
  1. ChannelAndContacts component exposes n ThermalPorts (one per axial cell) and its energy balance uses per-cell wall temperature: `h_tc[i] * (π*Dh) * dz * (thermal[i].T - T[i])`
  2. All v0.1 tests pass unchanged — existing Channel (single ThermalPort) is not modified
  3. ChannelAndContacts steady-state result matches Channel result within 0.1% when all n ThermalPorts are driven by the same uniform wall temperature
**Plans**: TBD

## Progress

**Execution Order:** 6 → 7 → 8 → 9

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Foundation | v0.1 | 3/3 | Complete | 2026-03-12 |
| 2. Components | v0.1 | 4/4 | Complete | 2026-03-12 |
| 3. Integration and Validation | v0.1 | 3/3 | Complete | 2026-03-12 |
| 4. Tech Debt Cleanup | v0.1 | 1/1 | Complete | 2026-03-12 |
| 5. Nyquist Validation | v0.1 | 1/1 | Complete | 2026-03-12 |
| 6. Gravity Validation | v0.2 | 1/1 | Complete | 2026-03-13 |
| 7. Network Architecture | 2/2 | Complete   | 2026-03-13 | - |
| 8. Inertia and HeatExchanger | 2/2 | Complete   | 2026-03-13 | - |
| 9. ChannelAndContacts | v0.2 | 0/? | Not started | - |

---

*Created: 2026-03-12*
*Updated: 2026-03-13 — v0.2 roadmap added (phases 6-9)*
*Updated: 2026-03-13 — Phase 6 plan written (06-01-PLAN.md)*
*Updated: 2026-03-13 — Phase 7 plans written (07-01-PLAN.md, 07-02-PLAN.md)*
*Updated: 2026-03-13 — Phase 8 plans written (08-01-PLAN.md, 08-02-PLAN.md)*
