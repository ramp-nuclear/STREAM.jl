# Requirements: STREAM.jl

**Defined:** 2026-03-13
**Milestone:** v0.2 — Component & Network Expansion
**Core Value:** A Julia MTK-based thermal-hydraulics library that matches Python STREAM results, proving the architecture is sound before large-scale porting begins.

## v0.2 Requirements

### Gravity & Vertical Loop

- [x] **GRAV-01**: Vertical closed loop (Channel with g_acc set to 9.80665 + Gravity component on return leg of equal height) assembles, compiles, and solves correctly
- [x] **GRAV-02**: Gravity cancellation test — equal height up/down gives the same steady-state flow as the horizontal reference loop within 1%

### Network Architecture

- [x] **NET-01**: Resistor component: linear pressure drop `dp ~ R * mdot`, where R is a scalar resistance parameter
- [x] **NET-02**: Cube problem (12 Resistors, 8 nodes, 1 Pump) assembled using multi-port `connect()` calls — no Junction component needed; MTK connection semantics handle flow conservation automatically
- [x] **NET-03**: Cube problem flow distribution matches analytical solution (equivalent resistance = 5/6 R) within 1%

### Lumped Components

- [x] **COMP-01**: Inertia component: `dp ~ (L/A) * D(mdot)`, validated against Python STREAM Inertia on a transient test case
- [x] **COMP-02**: HeatExchanger component (public): fixed outlet temperature, no pressure drop — replaces internal `_make_temp_bc`; existing build_loop updated to use it

### Per-Cell Thermal Coupling

- [x] **THERM-01**: ChannelAndContacts component: n ThermalPorts (one per axial cell), per-cell wall temperature in energy balance: `h_tc[i] * (π*Dh) * dz * (thermal[i].T - T[i])`
- [x] **THERM-02**: Existing Channel (single ThermalPort) remains unchanged and all v0.1 tests continue to pass
- [x] **THERM-03**: ChannelAndContacts steady-state result matches Channel result when all n ThermalPorts are driven by the same uniform wall temperature (within 0.1%)

## v3 Requirements (deferred)

### HeatDiffusion

- **HEAT-01**: HeatDiffusion component: 2D (x-z) finite-difference fuel plate with `T(t)[1:nx, 1:nz]` indexed MTK variables
- **HEAT-02**: HeatDiffusion exposes `thermal_left[1:n]` and `thermal_right[1:n]` ThermalPort arrays for left/right channel coupling
- **HEAT-03**: Coupled HeatDiffusion + ChannelAndContacts system solves and matches Python STREAM MTR reference case
- **HEAT-04**: Asymmetric left/right heating (two independent channels on either side of a plate) works without model changes

## Out of Scope

| Feature | Reason |
|---------|--------|
| Junction component | MTK multi-port connect() is the junction — no explicit component needed |
| PointKinetics | v0.4+ — thermal-hydraulic architecture must be complete first |
| Additional HTC correlations (laminar, Marco-Han, etc.) | v0.4+ — minimal rewrite when added; not blocking anything now |
| Additional friction correlations (Colebrook, regime-dependent) | v0.4+ — same as HTC |
| Decay heat models | Irrelevant without neutronics |
| Heavy water / other fluids | v0.4+ — light water only through v0.3 |
| Solver wrapper structs (SteadySolution, TransientSolution) | ODESolution is sufficient; defer unless usage patterns demand it |
| Python adapter (juliacall) | If Julia-STREAM is good, use it from Julia |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| GRAV-01 | Phase 6 | Complete |
| GRAV-02 | Phase 6 | Complete |
| NET-01 | Phase 7 | Complete |
| NET-02 | Phase 7 | Complete |
| NET-03 | Phase 7 | Complete |
| COMP-01 | Phase 8 | Complete |
| COMP-02 | Phase 8 | Complete |
| THERM-01 | Phase 9 | Complete |
| THERM-02 | Phase 9 | Complete |
| THERM-03 | Phase 9 | Complete |

**Coverage:**
- v0.2 requirements: 10 total
- Mapped to phases: 10 ✓
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-13*
*Last updated: 2026-03-13 — traceability mapped to phases 6-9*
